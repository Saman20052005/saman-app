"""
FastAPI REST + WebSocket Router for Saman Community Messenger-Lite DM (Wave 4).

Security & Architecture Invariants:
- Independent JWT authentication using backend.auth.config (JWT_SECRET, JWT_ALGORITHM) + db["users"].
- Strict anti-IDOR membership enforcement: all conversation/message endpoints verify
  current_user_id in conversation["participants"] and return 404 if not a member.
- Enforces 2-way community_blocks (403) and community_user_settings.who_can_dm
  ("nobody" -> 403, "followers" -> check community_follows -> 403 if not following).
- Media upload validates extensions + magic bytes + size limits (Image <= 5MB,
  Audio <= 15MB, Video <= 50MB) and prevents path traversal via os.path.basename + realpath.
- Media streaming supports HTTP Range (206 Partial Content) for smooth iOS/Android
  audio & video playback/seeking.
- WebSocket /api/community/ws/chat closes with 4401 on missing/invalid/expired token
  and runs PyMongo calls via asyncio.to_thread so the event loop is never blocked.
"""

import asyncio
import base64
import io
import json
import os
import uuid
import weakref
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

import jwt
from bson import ObjectId
from fastapi import (
    APIRouter,
    Depends,
    File,
    Header,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.responses import StreamingResponse
from PIL import Image
from pymongo.errors import DuplicateKeyError
from starlette.routing import Route

from backend.app import database as _app_database
from backend.app.database_community_dm import (
    COLL_DM_CONVERSATIONS,
    COLL_DM_MESSAGES,
)
from backend.app.models.community_dm import (
    CreateConversationRequest,
    DmConversationModel,
    DmConversationsResponse,
    DmMediaUploadResponse,
    DmMessageModel,
    DmMessagesResponse,
    DmParticipantModel,
    DmSharedPostPreviewModel,
    DmUnreadCountResponse,
    SendDmMessageRequest,
)
from backend.app.services.media_storage_service import (
    MediaStorageConfig,
    MediaStorageConfigError,
    MediaStorageUploadError,
    get_media_storage_service,
)
from backend.auth.config import JWT_ALGORITHM, JWT_SECRET

router = APIRouter(prefix="/api/community/dm", tags=["Community DM"])
ws_router = APIRouter(tags=["Community DM WS"])

# Module-level db reference (supports direct monkeypatching in tests)
db = _app_database.db

COMMUNITY_DM_STATIC_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "static",
    "community_dm",
)
os.makedirs(COMMUNITY_DM_STATIC_DIR, exist_ok=True)

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
AUDIO_EXTENSIONS = {".m4a", ".aac", ".mp3", ".wav", ".ogg"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".webm"}

MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_AUDIO_BYTES = 15 * 1024 * 1024
MAX_VIDEO_BYTES = 50 * 1024 * 1024

MEDIA_CONTENT_TYPES: Dict[str, str] = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".m4a": "audio/mp4",
    ".aac": "audio/aac",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg",
    ".mp4": "video/mp4",
    ".mov": "video/quicktime",
    ".webm": "video/webm",
}


# ---------------------------------------------------------------------------
# Database collection helpers
# ---------------------------------------------------------------------------


def _get_db():
    if db is not None:
        return db
    return _app_database.db


def get_dm_conversations_collection():
    database = _get_db()
    return database[COLL_DM_CONVERSATIONS] if database is not None else None


def get_dm_messages_collection():
    database = _get_db()
    return database[COLL_DM_MESSAGES] if database is not None else None


def get_users_collection():
    database = _get_db()
    return database["users"] if database is not None else None


def get_community_blocks_collection():
    database = _get_db()
    return database["community_blocks"] if database is not None else None


def get_community_user_settings_collection():
    database = _get_db()
    return database["community_user_settings"] if database is not None else None


def get_community_follows_collection():
    database = _get_db()
    return database["community_follows"] if database is not None else None


def get_community_posts_collection():
    database = _get_db()
    return database["community_posts"] if database is not None else None


# ---------------------------------------------------------------------------
# Independent JWT authentication
# ---------------------------------------------------------------------------


def _decode_jwt_user_sync(token: str) -> Dict[str, Any]:
    """Synchronously decode JWT and resolve user from db['users']."""
    if not token or not token.strip():
        raise HTTPException(status_code=401, detail="Authentication required")

    try:
        payload = jwt.decode(token.strip(), JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token Expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid Token")

    email = payload.get("email")
    sub = payload.get("sub") or payload.get("user_id") or payload.get("id")
    if not email and not sub:
        raise HTTPException(status_code=401, detail="Invalid token payload")

    users_col = get_users_collection()
    if users_col is not None:
        if email:
            user = users_col.find_one({"email": email})
            if user:
                return user
        if sub:
            sub_str = str(sub)
            filters: List[Dict[str, Any]] = [{"_id": sub_str}, {"id": sub_str}]
            if ObjectId.is_valid(sub_str):
                filters.append({"_id": ObjectId(sub_str)})
            user = users_col.find_one({"$or": filters})
            if user:
                return user

    user_id = str(sub or email)
    return {
        "_id": user_id,
        "email": email,
        "name": payload.get("name", "User"),
    }


async def get_required_current_user(
    authorization: Optional[str] = Header(None),
) -> Dict[str, Any]:
    if not authorization:
        raise HTTPException(status_code=401, detail="Authentication required")
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(status_code=401, detail="Invalid authorization header format")
    return await asyncio.to_thread(_decode_jwt_user_sync, parts[1])


# ---------------------------------------------------------------------------
# WebSocket Connection Manager
# ---------------------------------------------------------------------------


def _get_loop_lock(store: "weakref.WeakKeyDictionary[Any, asyncio.Lock]") -> asyncio.Lock:
    """Return an asyncio.Lock bound to the currently running event loop (per-loop, GC-safe)."""
    loop = asyncio.get_running_loop()
    lock = store.get(loop)
    if lock is None:
        lock = asyncio.Lock()
        store[loop] = lock
    return lock


class DmConnectionManager:
    def __init__(self) -> None:
        self._connections: Dict[str, Set[WebSocket]] = {}
        self._loop_locks: "weakref.WeakKeyDictionary[Any, asyncio.Lock]" = (
            weakref.WeakKeyDictionary()
        )

    def _get_lock(self) -> asyncio.Lock:
        return _get_loop_lock(self._loop_locks)

    async def connect(self, user_id: str, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self._get_lock():
            self._connections.setdefault(user_id, set()).add(websocket)

    async def disconnect(self, user_id: str, websocket: WebSocket) -> bool:
        """Remove websocket; return True if user_id now has no remaining active sockets."""
        async with self._get_lock():
            sockets = self._connections.get(user_id)
            if not sockets:
                return True
            sockets.discard(websocket)
            if not sockets:
                self._connections.pop(user_id, None)
                return True
            return False

    async def send_to_user(self, user_id: str, payload: Dict[str, Any]) -> None:
        async with self._get_lock():
            sockets = list(self._connections.get(user_id, ()))

        if not sockets:
            return

        dead: List[WebSocket] = []
        for ws in sockets:
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)

        if dead:
            async with self._get_lock():
                user_set = self._connections.get(user_id)
                if user_set:
                    for ws in dead:
                        user_set.discard(ws)
                    if not user_set:
                        self._connections.pop(user_id, None)

    async def send_to_other_user_sockets(
        self,
        user_id: str,
        exclude_websocket: WebSocket,
        payload: Dict[str, Any],
    ) -> None:
        async with self._get_lock():
            sockets = [
                ws for ws in self._connections.get(user_id, ()) if ws is not exclude_websocket
            ]

        if not sockets:
            return

        dead: List[WebSocket] = []
        for ws in sockets:
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)

        if dead:
            async with self._get_lock():
                user_set = self._connections.get(user_id)
                if user_set:
                    for ws in dead:
                        user_set.discard(ws)
                    if not user_set:
                        self._connections.pop(user_id, None)

    async def send_to_users(self, user_ids: Iterable[str], payload: Dict[str, Any]) -> None:
        unique_ids = {str(uid) for uid in user_ids if uid}
        for uid in unique_ids:
            await self.send_to_user(uid, payload)


ws_manager = DmConnectionManager()


# ---------------------------------------------------------------------------
# In-Memory 1-1 Audio/Video Call Signaling Registry (Phase 5A)
# ---------------------------------------------------------------------------


@dataclass
class CallSession:
    call_id: str
    conversation_id: str
    caller_id: str
    callee_id: str
    call_type: str  # "audio" | "video"
    state: str = "ringing"  # "ringing" | "accepted" | "ended"
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    answered_at: Optional[datetime] = None
    logged: bool = False


class DmCallRegistry:
    """In-memory 1-1 audio/video call state registry protected by asyncio.Lock."""

    def __init__(self) -> None:
        self._loop_locks: "weakref.WeakKeyDictionary[Any, asyncio.Lock]" = (
            weakref.WeakKeyDictionary()
        )
        self.sessions: Dict[str, CallSession] = {}
        self.user_active_call: Dict[str, str] = {}

    def _get_lock(self) -> asyncio.Lock:
        return _get_loop_lock(self._loop_locks)

    def _clear_session_unlocked(self, session: CallSession) -> None:
        session.state = "ended"
        if self.user_active_call.get(session.caller_id) == session.call_id:
            self.user_active_call.pop(session.caller_id, None)
        if self.user_active_call.get(session.callee_id) == session.call_id:
            self.user_active_call.pop(session.callee_id, None)
        self.sessions.pop(session.call_id, None)

    async def start_invite(
        self,
        *,
        call_id: str,
        conversation_id: str,
        caller_id: str,
        callee_id: str,
        call_type: str,
    ) -> Tuple[Optional[CallSession], Optional[str]]:
        async with self._get_lock():
            if call_id in self.sessions:
                return None, "duplicate_call_id"
            if callee_id in self.user_active_call:
                return None, "callee_busy"
            if caller_id in self.user_active_call:
                return None, "caller_busy"

            session = CallSession(
                call_id=call_id,
                conversation_id=conversation_id,
                caller_id=caller_id,
                callee_id=callee_id,
                call_type=call_type,
                state="ringing",
                created_at=datetime.now(timezone.utc),
                answered_at=None,
                logged=False,
            )
            self.sessions[call_id] = session
            self.user_active_call[caller_id] = call_id
            self.user_active_call[callee_id] = call_id
            return session, None

    async def accept_call(
        self, call_id: str, user_id: str
    ) -> Tuple[Optional[CallSession], Optional[str]]:
        async with self._get_lock():
            session = self.sessions.get(call_id)
            if session is None:
                return None, "not_found"
            if session.callee_id != user_id:
                return None, "forbidden"
            if session.state != "ringing":
                return None, "invalid_state"
            session.state = "accepted"
            session.answered_at = datetime.now(timezone.utc)
            return session, None

    async def reject_call(
        self, call_id: str, user_id: str
    ) -> Tuple[Optional[CallSession], bool, Optional[str]]:
        async with self._get_lock():
            session = self.sessions.get(call_id)
            if session is None:
                return None, False, "not_found"
            if session.callee_id != user_id:
                return None, False, "forbidden"
            if session.state != "ringing":
                return None, False, "invalid_state"
            should_log = not session.logged
            session.logged = True
            self._clear_session_unlocked(session)
            return session, should_log, None

    async def cancel_call(
        self, call_id: str, user_id: str
    ) -> Tuple[Optional[CallSession], bool, Optional[str]]:
        async with self._get_lock():
            session = self.sessions.get(call_id)
            if session is None:
                return None, False, "not_found"
            if session.caller_id != user_id:
                return None, False, "forbidden"
            if session.state != "ringing":
                return None, False, "invalid_state"
            should_log = not session.logged
            session.logged = True
            self._clear_session_unlocked(session)
            return session, should_log, None

    async def busy_call(
        self, call_id: str, user_id: str
    ) -> Tuple[Optional[CallSession], bool, Optional[str]]:
        async with self._get_lock():
            session = self.sessions.get(call_id)
            if session is None:
                return None, False, "not_found"
            if session.callee_id != user_id:
                return None, False, "forbidden"
            if session.state != "ringing":
                return None, False, "invalid_state"
            should_log = not session.logged
            session.logged = True
            self._clear_session_unlocked(session)
            return session, should_log, None

    async def hangup_call(
        self, call_id: str, user_id: str
    ) -> Tuple[Optional[CallSession], str, int, bool, Optional[str]]:
        async with self._get_lock():
            session = self.sessions.get(call_id)
            if session is None:
                return None, "missed", 0, False, "not_found"
            if user_id not in (session.caller_id, session.callee_id):
                return None, "missed", 0, False, "forbidden"
            if session.state not in ("ringing", "accepted"):
                return None, "missed", 0, False, "invalid_state"

            now = datetime.now(timezone.utc)
            if session.state == "accepted" and session.answered_at is not None:
                duration_sec = max(0, int((now - session.answered_at).total_seconds()))
                call_status = "completed"
            else:
                duration_sec = 0
                call_status = "missed"

            should_log = not session.logged
            session.logged = True
            self._clear_session_unlocked(session)
            return session, call_status, duration_sec, should_log, None

    async def resolve_webrtc_peer(
        self, call_id: str, user_id: str
    ) -> Tuple[Optional[CallSession], Optional[str], Optional[str]]:
        async with self._get_lock():
            session = self.sessions.get(call_id)
            if session is None:
                return None, None, "not_found"
            if session.state not in ("ringing", "accepted"):
                return None, None, "invalid_state"
            if user_id == session.caller_id:
                return session, session.callee_id, None
            if user_id == session.callee_id:
                return session, session.caller_id, None
            return None, None, "forbidden"

    async def cleanup_user_disconnect(
        self, user_id: str
    ) -> Optional[Tuple[CallSession, str, str, int, bool]]:
        async with self._get_lock():
            call_id = self.user_active_call.get(user_id)
            if not call_id:
                return None
            session = self.sessions.get(call_id)
            if session is None or session.state not in ("ringing", "accepted"):
                self.user_active_call.pop(user_id, None)
                return None

            prev_state = session.state
            now = datetime.now(timezone.utc)
            if prev_state == "accepted" and session.answered_at is not None:
                duration_sec = max(0, int((now - session.answered_at).total_seconds()))
                call_status = "completed"
            else:
                duration_sec = 0
                call_status = "missed"

            should_log = not session.logged
            session.logged = True
            self._clear_session_unlocked(session)
            return session, prev_state, call_status, duration_sec, should_log


call_registry = DmCallRegistry()


# ---------------------------------------------------------------------------
# Cursor, timestamp, participant projection & privacy helpers
# ---------------------------------------------------------------------------


def _ensure_utc(dt: Any) -> datetime:
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    if isinstance(dt, str):
        parsed = datetime.fromisoformat(dt)
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    return datetime.now(timezone.utc)


def _encode_cursor(ts: Optional[datetime], obj_id: str) -> str:
    ts_part = _ensure_utc(ts).isoformat() if ts is not None else "NONE"
    raw = f"{ts_part}|{obj_id}"
    return base64.urlsafe_b64encode(raw.encode("utf-8")).decode("utf-8")


def _decode_cursor(cursor_str: str) -> Tuple[Optional[datetime], str]:
    try:
        raw = base64.urlsafe_b64decode(cursor_str.encode("utf-8")).decode("utf-8")
        parts = raw.split("|")
        if len(parts) != 2 or not parts[1]:
            raise ValueError("Malformed cursor format")
        if parts[0] == "NONE":
            return None, parts[1]
        dt = _ensure_utc(datetime.fromisoformat(parts[0]))
        return dt, parts[1]
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid pagination cursor")


def _make_pair_key(user_a: str, user_b: str) -> str:
    ordered = sorted([str(user_a), str(user_b)])
    return f"{ordered[0]}::{ordered[1]}"


def _get_peer_id(conv_doc: Dict[str, Any], current_user_id: str) -> str:
    for p in conv_doc.get("participants") or []:
        if str(p) != current_user_id:
            return str(p)
    return current_user_id


def _find_user_doc(user_id: str) -> Optional[Dict[str, Any]]:
    users_col = get_users_collection()
    if users_col is None:
        return None
    filters: List[Dict[str, Any]] = [{"_id": user_id}, {"id": user_id}]
    if ObjectId.is_valid(user_id):
        filters.append({"_id": ObjectId(user_id)})
    return users_col.find_one({"$or": filters})


def _get_user_settings_doc(user_id: str) -> Optional[Dict[str, Any]]:
    settings_col = get_community_user_settings_collection()
    if settings_col is None:
        return None
    filters: List[Dict[str, Any]] = [{"user_id": user_id}, {"_id": user_id}]
    if ObjectId.is_valid(user_id):
        filters.append({"_id": ObjectId(user_id)})
    return settings_col.find_one({"$or": filters})


def _sanitize_participant_projection(user_id: str) -> DmParticipantModel:
    """Project ONLY public profile fields; never leak email, password, tokens, or health data."""
    user_doc = _find_user_doc(user_id)
    settings_doc = _get_user_settings_doc(user_id)
    show_activity = bool(settings_doc.get("show_activity_status", True)) if settings_doc else True

    if not user_doc:
        return DmParticipantModel(
            id=str(user_id),
            name="Saman Athlete",
            avatar_url=None,
            is_verified=False,
            show_activity_status=show_activity,
        )

    return DmParticipantModel(
        id=str(user_doc.get("_id") or user_doc.get("id") or user_id),
        name=str(user_doc.get("name") or user_doc.get("full_name") or "Saman Athlete"),
        avatar_url=user_doc.get("avatar_url") or user_doc.get("avatar") or user_doc.get("custom_avatar"),
        is_verified=bool(user_doc.get("is_verified", False)),
        show_activity_status=show_activity,
    )


def _is_blocked_either_way(user_a: str, user_b: str) -> bool:
    blocks_col = get_community_blocks_collection()
    if blocks_col is None:
        return False
    doc = blocks_col.find_one(
        {
            "$or": [
                {"blocker_id": user_a, "blocked_id": user_b},
                {"blocker_id": user_b, "blocked_id": user_a},
                {"user_id": user_a, "blocked_user_id": user_b},
                {"user_id": user_b, "blocked_user_id": user_a},
            ]
        }
    )
    return doc is not None


def _get_blocked_user_ids(user_id: str) -> Set[str]:
    blocks_col = get_community_blocks_collection()
    if blocks_col is None:
        return set()
    blocked: Set[str] = set()
    cursor = blocks_col.find(
        {
            "$or": [
                {"blocker_id": user_id},
                {"blocked_id": user_id},
                {"user_id": user_id},
                {"blocked_user_id": user_id},
            ]
        }
    )
    for doc in cursor:
        b1 = doc.get("blocker_id") or doc.get("user_id")
        b2 = doc.get("blocked_id") or doc.get("blocked_user_id")
        if b1 is not None and str(b1) == user_id and b2 is not None:
            blocked.add(str(b2))
        elif b2 is not None and str(b2) == user_id and b1 is not None:
            blocked.add(str(b1))
    return blocked


def _enforce_dm_allowed(sender_id: str, target_user_id: str) -> None:
    """Enforce 2-way community_blocks and target's community_user_settings.who_can_dm."""
    if _is_blocked_either_way(sender_id, target_user_id):
        raise HTTPException(
            status_code=403,
            detail="Không thể nhắn tin do trạng thái chặn giữa hai người dùng.",
        )

    settings_doc = _get_user_settings_doc(target_user_id)
    who_can_dm = str((settings_doc or {}).get("who_can_dm") or "everyone").strip().lower()

    if who_can_dm == "nobody":
        raise HTTPException(
            status_code=403,
            detail="Người dùng này không nhận tin nhắn trực tiếp.",
        )

    if who_can_dm == "followers":
        follows_col = get_community_follows_collection()
        is_following = False
        if follows_col is not None:
            is_following = (
                follows_col.find_one(
                    {"follower_id": sender_id, "following_id": target_user_id}
                )
                is not None
            )
        if not is_following:
            raise HTTPException(
                status_code=403,
                detail="Bạn cần theo dõi người dùng này để gửi tin nhắn.",
            )


def _enforce_story_reply_allowed(sender_id: str, story_owner_id: str) -> None:
    """Enforce story owner's community_user_settings.who_can_reply_story."""
    if not story_owner_id or str(sender_id) == str(story_owner_id):
        return

    settings_doc = _get_user_settings_doc(story_owner_id)
    who_can_reply = str((settings_doc or {}).get("who_can_reply_story") or "everyone").strip().lower()

    if who_can_reply == "nobody":
        raise HTTPException(
            status_code=403,
            detail="Người dùng này không cho phép trả lời tin (Story).",
        )

    if who_can_reply == "followers":
        follows_col = get_community_follows_collection()
        is_following = False
        if follows_col is not None:
            is_following = (
                follows_col.find_one(
                    {"follower_id": sender_id, "following_id": story_owner_id}
                )
                is not None
            )
        if not is_following:
            raise HTTPException(
                status_code=403,
                detail="Bạn cần theo dõi người dùng này để trả lời tin (Story).",
            )


def _get_conversation_for_member(conversation_id: str, current_user_id: str) -> Dict[str, Any]:
    """Fetch conversation and verify participant membership; return 404 on miss or non-member (anti-IDOR)."""
    conv_col = get_dm_conversations_collection()
    if conv_col is None:
        raise HTTPException(status_code=500, detail="Database not configured")

    filters: List[Dict[str, Any]] = [{"_id": conversation_id}]
    if ObjectId.is_valid(conversation_id):
        filters.insert(0, {"_id": ObjectId(conversation_id)})

    conv = conv_col.find_one({"$or": filters})
    if not conv:
        raise HTTPException(status_code=404, detail="Conversation not found")

    participants = [str(p) for p in (conv.get("participants") or [])]
    if current_user_id not in participants:
        raise HTTPException(status_code=404, detail="Conversation not found")

    return conv


def _build_conversation_model(conv_doc: Dict[str, Any], current_user_id: str) -> DmConversationModel:
    peer_id = _get_peer_id(conv_doc, current_user_id)
    peer = _sanitize_participant_projection(peer_id)
    unread_counts = conv_doc.get("unread_counts") or {}
    unread = max(0, int(unread_counts.get(current_user_id, 0)))

    last_msg_at = conv_doc.get("last_message_at")
    updated_at = conv_doc.get("updated_at") or last_msg_at or conv_doc.get("created_at")

    return DmConversationModel(
        id=str(conv_doc["_id"]),
        peer=peer,
        last_message_preview=str(conv_doc.get("last_message_preview") or ""),
        last_message_type=conv_doc.get("last_message_type"),
        last_message_at=_ensure_utc(last_msg_at) if last_msg_at is not None else None,
        unread_count=unread,
        updated_at=_ensure_utc(updated_at),
    )


def _build_message_model(doc: Dict[str, Any]) -> DmMessageModel:
    is_deleted = bool(doc.get("is_deleted", False))
    preview_doc = None if is_deleted else doc.get("shared_post_preview")
    preview_model = (
        DmSharedPostPreviewModel(
            id=str(preview_doc.get("id", "")),
            type=str(preview_doc.get("type", "photo")),
            author_name=str(preview_doc.get("author_name", "Saman Athlete")),
            caption=str(preview_doc.get("caption", "")),
            thumbnail_url=preview_doc.get("thumbnail_url"),
        )
        if isinstance(preview_doc, dict)
        else None
    )

    raw_duration_sec = None if is_deleted else doc.get("duration_sec")
    duration_sec = int(raw_duration_sec) if raw_duration_sec is not None else None

    return DmMessageModel(
        id=str(doc["_id"]),
        conversation_id=str(doc["conversation_id"]),
        sender_id=str(doc["sender_id"]),
        type=doc["type"],
        content="" if is_deleted else str(doc.get("content") or ""),
        media_url=None if is_deleted else doc.get("media_url"),
        duration_seconds=None if is_deleted else doc.get("duration_seconds"),
        shared_post_id=None if is_deleted else doc.get("shared_post_id"),
        shared_post_preview=preview_model,
        reply_to_message_id=doc.get("reply_to_message_id"),
        is_deleted=is_deleted,
        created_at=_ensure_utc(doc.get("created_at")),
        call_type=None if is_deleted else doc.get("call_type"),
        call_status=None if is_deleted else doc.get("call_status"),
        duration_sec=duration_sec,
        call_id=None if is_deleted else doc.get("call_id"),
    )


def _validate_shared_post_preview(post_id: str, viewer_id: str) -> Dict[str, Any]:
    """Verify post exists and viewer is allowed to view it; return sanitized preview snapshot."""
    posts_col = get_community_posts_collection()
    if posts_col is None:
        raise HTTPException(status_code=404, detail="Shared post not found")

    if ObjectId.is_valid(post_id):
        post = posts_col.find_one({"$or": [{"_id": ObjectId(post_id)}, {"id": post_id}]})
    else:
        post = posts_col.find_one({"$or": [{"id": post_id}, {"_id": post_id}]})

    if not post or post.get("is_deleted", False) or post.get("status") == "unpublished":
        raise HTTPException(status_code=404, detail="Shared post not found")

    author_obj = post.get("author") or {}
    author_id = str(post.get("author_id") or author_obj.get("id") or author_obj.get("_id") or "")

    if author_id and author_id != viewer_id and _is_blocked_either_way(viewer_id, author_id):
        raise HTTPException(status_code=404, detail="Shared post not found")

    privacy = str(post.get("privacy") or "public").lower()
    if privacy == "private":
        if viewer_id != author_id:
            raise HTTPException(status_code=404, detail="Shared post not found")
    elif privacy == "followers_only":
        if viewer_id != author_id:
            follows_col = get_community_follows_collection()
            is_follower = (
                follows_col.find_one({"follower_id": viewer_id, "following_id": author_id}) is not None
                if follows_col is not None
                else False
            )
            if not is_follower:
                raise HTTPException(status_code=404, detail="Shared post not found")

    author_name = str(author_obj.get("name") or "")
    if not author_name and author_id:
        author_name = _sanitize_participant_projection(author_id).name
    if not author_name:
        author_name = "Saman Athlete"

    photo_urls = post.get("photo_urls") or []
    thumbnail = str(photo_urls[0]) if photo_urls else None
    caption = str(post.get("caption") or (post.get("qa_info") or {}).get("question") or "")[:200]

    return {
        "id": str(post.get("id") or post.get("_id")),
        "type": str(post.get("type") or "photo"),
        "author_name": author_name,
        "caption": caption,
        "thumbnail_url": thumbnail,
    }


def _validate_media_url(media_url: Optional[str]) -> str:
    if not media_url or not media_url.strip():
        raise HTTPException(status_code=400, detail="media_url là bắt buộc cho tin nhắn media.")
    cleaned = media_url.strip()
    if ".." in cleaned or "\\" in cleaned:
        raise HTTPException(status_code=400, detail="media_url không hợp lệ.")
    allowed_prefixes = (
        "/static/community_dm/",
        "/api/community/dm/media/",
        "/static/community/",
        "https://",
        "http://",
    )
    if not cleaned.startswith(allowed_prefixes):
        raise HTTPException(status_code=400, detail="media_url không được hỗ trợ.")
    return cleaned


def _format_last_message_preview(msg_type: str, content: str) -> str:
    if msg_type == "text":
        return content[:120]
    if msg_type == "story_reply":
        return content[:120] if content else "💬 Đã trả lời tin"
    if msg_type == "voice":
        return "🎤 Tin nhắn thoại"
    if msg_type == "photo":
        return "📷 Hình ảnh"
    if msg_type == "video":
        return "🎬 Video"
    if msg_type == "post_share":
        return "📌 Đã chia sẻ một bài viết"
    return content[:120]


def _format_call_duration(duration_sec: int) -> str:
    sec = max(0, int(duration_sec))
    hours, rem = divmod(sec, 3600)
    minutes, seconds = divmod(rem, 60)
    if hours > 0:
        return f"{hours:02d}:{minutes:02d}:{seconds:02d}"
    return f"{minutes:02d}:{seconds:02d}"


def _format_call_log_preview(call_type: str, call_status: str, duration_sec: int) -> str:
    is_video = call_type == "video"
    label = "Cuộc gọi video" if is_video else "Cuộc gọi thoại"
    if call_status == "completed":
        return f"{label} • {_format_call_duration(duration_sec)}"
    if call_status == "missed":
        return f"{label} nhỡ"
    if call_status == "rejected":
        return "Đã từ chối cuộc gọi video" if is_video else "Đã từ chối cuộc gọi"
    return label


def _persist_call_log_sync(
    database: Any,
    session: CallSession,
    call_status: str,
    duration_sec: int,
) -> Optional[DmMessageModel]:
    """Insert an idempotent call_log message and update conversation preview synchronously."""
    target_db = database if database is not None else _get_db()
    if target_db is None:
        return None

    msg_col = target_db[COLL_DM_MESSAGES]
    conv_col = target_db[COLL_DM_CONVERSATIONS]

    existing = msg_col.find_one({"type": "call_log", "call_id": session.call_id})
    if existing is not None:
        return _build_message_model(existing)

    now = datetime.now(timezone.utc)
    safe_duration = max(0, int(duration_sec))
    preview_text = _format_call_log_preview(session.call_type, call_status, safe_duration)
    request_key = f"call_log:{session.call_id}"

    msg_doc: Dict[str, Any] = {
        "_id": ObjectId(),
        "conversation_id": session.conversation_id,
        "sender_id": session.caller_id,
        "type": "call_log",
        "content": preview_text,
        "media_url": None,
        "duration_seconds": None,
        "shared_post_id": None,
        "shared_post_preview": None,
        "reply_to_message_id": None,
        "is_deleted": False,
        "created_at": now,
        "call_type": session.call_type,
        "call_status": call_status,
        "duration_sec": safe_duration,
        "call_id": session.call_id,
        "request_key": request_key,
    }

    try:
        msg_col.insert_one(msg_doc)
    except DuplicateKeyError:
        existing = msg_col.find_one({"type": "call_log", "call_id": session.call_id})
        if existing is not None:
            return _build_message_model(existing)
        return None

    conv_filters: List[Dict[str, Any]] = [{"_id": session.conversation_id}]
    if ObjectId.is_valid(session.conversation_id):
        conv_filters.insert(0, {"_id": ObjectId(session.conversation_id)})

    update_ops: Dict[str, Any] = {
        "$set": {
            "last_message_type": "call_log",
            "last_message_preview": preview_text,
            "last_message_at": now,
            "updated_at": now,
        }
    }
    if call_status == "missed":
        update_ops["$inc"] = {f"unread_counts.{session.callee_id}": 1}

    conv_col.update_one({"$or": conv_filters}, update_ops)
    return _build_message_model(msg_doc)


async def _persist_and_broadcast_call_log(
    session: CallSession,
    call_status: str,
    duration_sec: int,
) -> Optional[DmMessageModel]:
    msg_model = await asyncio.to_thread(
        _persist_call_log_sync,
        _get_db(),
        session,
        call_status,
        duration_sec,
    )
    if msg_model is not None:
        await ws_manager.send_to_users(
            [session.caller_id, session.callee_id],
            {
                "event": "message.created",
                "conversation_id": session.conversation_id,
                "message": msg_model.model_dump(mode="json"),
            },
        )
    return msg_model


# ---------------------------------------------------------------------------
# Media Upload & HTTP Range Streaming (206 Partial Content)
# ---------------------------------------------------------------------------


def _validate_audio_magic(ext: str, data: bytes) -> bool:
    if len(data) < 4:
        return False
    if ext == ".m4a":
        return len(data) >= 8 and data[4:8] == b"ftyp"
    if ext == ".aac":
        return (
            data[:2] in (b"\xff\xf1", b"\xff\xf9")
            or (len(data) >= 8 and data[4:8] == b"ftyp")
            or data[:3] == b"ID3"
        )
    if ext == ".mp3":
        return data[:3] == b"ID3" or (data[0] == 0xFF and (data[1] & 0xE0) == 0xE0)
    if ext == ".wav":
        return data[:4] == b"RIFF" and (len(data) < 12 or data[8:12] == b"WAVE")
    if ext == ".ogg":
        return data[:4] == b"OggS"
    return False


def _validate_video_magic(ext: str, data: bytes) -> bool:
    if len(data) < 4:
        return False
    if ext in (".mp4", ".mov"):
        return len(data) >= 8 and data[4:8] in (b"ftyp", b"moov")
    if ext == ".webm":
        return data[:4] == b"\x1a\x45\xdf\xa3"
    return False


def _resolve_safe_media_path(filename: str) -> Tuple[str, str]:
    clean_name = os.path.basename(filename or "")
    if (
        not clean_name
        or clean_name != filename
        or ".." in filename
        or "/" in filename
        or "\\" in filename
    ):
        raise HTTPException(status_code=404, detail="File not found")

    base_real = os.path.realpath(COMMUNITY_DM_STATIC_DIR)
    filepath = os.path.realpath(os.path.join(COMMUNITY_DM_STATIC_DIR, clean_name))
    if not filepath.startswith(base_real + os.sep) or not os.path.isfile(filepath):
        raise HTTPException(status_code=404, detail="File not found")

    ext = os.path.splitext(clean_name)[1].lower()
    media_type = MEDIA_CONTENT_TYPES.get(ext, "application/octet-stream")
    return filepath, media_type


def _iter_file_range(filepath: str, start: int, length: int, chunk_size: int = 64 * 1024):
    with open(filepath, "rb") as f:
        f.seek(start)
        remaining = length
        while remaining > 0:
            chunk = f.read(min(chunk_size, remaining))
            if not chunk:
                break
            remaining -= len(chunk)
            yield chunk


def _build_range_file_response(request: Request, filepath: str, media_type: str) -> Response:
    file_size = os.path.getsize(filepath)
    range_header = request.headers.get("range")

    if not range_header:
        headers = {
            "Accept-Ranges": "bytes",
            "Content-Length": str(file_size),
        }
        if request.method == "HEAD":
            return Response(status_code=200, headers=headers, media_type=media_type)
        return StreamingResponse(
            _iter_file_range(filepath, 0, file_size),
            status_code=200,
            headers=headers,
            media_type=media_type,
        )

    range_value = range_header.strip()
    if not range_value.lower().startswith("bytes=") or file_size == 0:
        return Response(
            status_code=416,
            headers={"Content-Range": f"bytes */{file_size}", "Accept-Ranges": "bytes"},
        )

    spec = range_value[6:].split(",")[0].strip()
    if "-" not in spec:
        return Response(
            status_code=416,
            headers={"Content-Range": f"bytes */{file_size}", "Accept-Ranges": "bytes"},
        )

    start_str, end_str = spec.split("-", 1)
    try:
        if start_str == "" and end_str != "":
            suffix = int(end_str)
            if suffix <= 0:
                raise ValueError("Invalid suffix length")
            start = max(0, file_size - suffix)
            end = file_size - 1
        elif start_str != "" and end_str == "":
            start = int(start_str)
            end = file_size - 1
        elif start_str != "" and end_str != "":
            start = int(start_str)
            end = min(int(end_str), file_size - 1)
        else:
            raise ValueError("Empty range")
    except ValueError:
        return Response(
            status_code=416,
            headers={"Content-Range": f"bytes */{file_size}", "Accept-Ranges": "bytes"},
        )

    if start < 0 or start >= file_size or start > end:
        return Response(
            status_code=416,
            headers={"Content-Range": f"bytes */{file_size}", "Accept-Ranges": "bytes"},
        )

    content_length = end - start + 1
    headers = {
        "Content-Range": f"bytes {start}-{end}/{file_size}",
        "Accept-Ranges": "bytes",
        "Content-Length": str(content_length),
    }
    if request.method == "HEAD":
        return Response(status_code=206, headers=headers, media_type=media_type)

    return StreamingResponse(
        _iter_file_range(filepath, start, content_length),
        status_code=206,
        headers=headers,
        media_type=media_type,
    )


def _assert_local_static_serving_allowed() -> None:
    cfg = MediaStorageConfig.from_env()
    if cfg.is_production and not cfg.allow_local_media_storage:
        raise HTTPException(status_code=404, detail="Not found")


async def serve_static_community_dm_file(request: Request) -> Response:
    _assert_local_static_serving_allowed()
    filename = request.path_params.get("filename", "")
    filepath, media_type = _resolve_safe_media_path(filename)
    return _build_range_file_response(request, filepath, media_type)


router.routes.append(
    Route(
        "/static/community_dm/{filename}",
        endpoint=serve_static_community_dm_file,
        methods=["GET", "HEAD"],
    )
)


@router.get("/media/{filename}")
async def get_dm_media(filename: str, request: Request):
    _assert_local_static_serving_allowed()
    filepath, media_type = _resolve_safe_media_path(filename)
    return _build_range_file_response(request, filepath, media_type)


@router.post("/media/upload", response_model=DmMediaUploadResponse)
async def upload_dm_media(
    file: UploadFile = File(...),
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    safe_orig_name = os.path.basename(file.filename or "")
    ext = os.path.splitext(safe_orig_name)[1].lower()

    if ext in IMAGE_EXTENSIONS:
        media_kind = "image"
        max_bytes = MAX_IMAGE_BYTES
    elif ext in AUDIO_EXTENSIONS:
        media_kind = "audio"
        max_bytes = MAX_AUDIO_BYTES
    elif ext in VIDEO_EXTENSIONS:
        media_kind = "video"
        max_bytes = MAX_VIDEO_BYTES
    else:
        raise HTTPException(
            status_code=400,
            detail="Định dạng file không được hỗ trợ. Chấp nhận ảnh (jpg/png/webp), âm thanh (m4a/aac/mp3/wav/ogg), hoặc video (mp4/mov/webm).",
        )

    content_buf = bytearray()
    chunk_size = 64 * 1024
    while True:
        chunk = await file.read(chunk_size)
        if not chunk:
            break
        content_buf.extend(chunk)
        if len(content_buf) > max_bytes:
            max_mb = max_bytes // (1024 * 1024)
            raise HTTPException(
                status_code=413,
                detail=f"Dung lượng file vượt quá giới hạn {max_mb} MB.",
            )

    if len(content_buf) == 0:
        raise HTTPException(status_code=400, detail="File rỗng.")

    raw_bytes = bytes(content_buf)
    stored_ext = ext.lstrip(".")

    if media_kind == "image":
        try:
            img = Image.open(io.BytesIO(raw_bytes))
            img_format = (img.format or "").upper()
            if img_format not in {"JPEG", "PNG", "WEBP"}:
                raise HTTPException(
                    status_code=400,
                    detail=f"Định dạng ảnh không hợp lệ: {img_format}.",
                )
            img.verify()
            stored_ext = "jpg" if img_format == "JPEG" else img_format.lower()
        except HTTPException:
            raise
        except Exception:
            raise HTTPException(status_code=400, detail="File ảnh không hợp lệ hoặc bị giả mạo.")
    elif media_kind == "audio":
        if not _validate_audio_magic(ext, raw_bytes):
            raise HTTPException(
                status_code=400,
                detail="File âm thanh không khớp định dạng (magic bytes không hợp lệ).",
            )
    elif media_kind == "video":
        if not _validate_video_magic(ext, raw_bytes):
            raise HTTPException(
                status_code=400,
                detail="File video không khớp định dạng (magic bytes không hợp lệ).",
            )

    generated_filename = f"{uuid.uuid4().hex}.{stored_ext}"
    resolved_content_type = MEDIA_CONTENT_TYPES.get(f".{stored_ext}", "application/octet-stream")

    def _upload() -> Any:
        storage = get_media_storage_service()
        return storage.upload_bytes(
            data=raw_bytes,
            key_prefix="saman/community_dm",
            filename=generated_filename,
            content_type=resolved_content_type,
            local_dir=Path(COMMUNITY_DM_STATIC_DIR),
            local_url_prefix="/static/community_dm",
        )

    try:
        upload_result = await asyncio.to_thread(_upload)
    except MediaStorageConfigError:
        raise HTTPException(
            status_code=503,
            detail="Media storage is not configured",
        )
    except MediaStorageUploadError:
        raise HTTPException(
            status_code=502,
            detail="Failed to upload media",
        )

    return DmMediaUploadResponse(
        media_url=upload_result.url,
        media_kind=media_kind,
        content_type=resolved_content_type,
        file_name=safe_orig_name or generated_filename,
        size_bytes=len(raw_bytes),
    )


# ---------------------------------------------------------------------------
# Conversations & Messages REST endpoints
# ---------------------------------------------------------------------------


@router.post("/conversations", response_model=DmConversationModel)
async def create_or_get_conversation(
    body: CreateConversationRequest,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])
    target_user_id = body.target_user_id.strip()

    if not target_user_id:
        raise HTTPException(status_code=400, detail="target_user_id không hợp lệ.")
    if target_user_id == current_user_id:
        raise HTTPException(status_code=400, detail="Không thể tự tạo cuộc trò chuyện với chính mình.")

    def _op() -> DmConversationModel:
        conv_col = get_dm_conversations_collection()
        if conv_col is None:
            raise HTTPException(status_code=500, detail="Database not configured")

        if _find_user_doc(target_user_id) is None:
            raise HTTPException(status_code=404, detail="Target user not found")

        _enforce_dm_allowed(current_user_id, target_user_id)

        pair_key = _make_pair_key(current_user_id, target_user_id)
        existing = conv_col.find_one({"participant_pair_key": pair_key})
        if existing:
            return _build_conversation_model(existing, current_user_id)

        now = datetime.now(timezone.utc)
        conv_doc = {
            "_id": ObjectId(),
            "participant_pair_key": pair_key,
            "participants": sorted([current_user_id, target_user_id]),
            "last_message_preview": "",
            "last_message_type": None,
            "last_message_at": None,
            "unread_counts": {current_user_id: 0, target_user_id: 0},
            "created_at": now,
            "updated_at": now,
        }
        try:
            conv_col.insert_one(conv_doc)
        except DuplicateKeyError:
            existing = conv_col.find_one({"participant_pair_key": pair_key})
            if existing:
                return _build_conversation_model(existing, current_user_id)
            raise

        return _build_conversation_model(conv_doc, current_user_id)

    return await asyncio.to_thread(_op)


@router.get("/conversations", response_model=DmConversationsResponse)
async def list_conversations(
    limit: int = Query(20, ge=1, le=50),
    cursor: Optional[str] = Query(None),
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])

    def _op() -> DmConversationsResponse:
        conv_col = get_dm_conversations_collection()
        if conv_col is None:
            return DmConversationsResponse(items=[], total_unread_count=0, next_cursor=None)

        blocked_ids = _get_blocked_user_ids(current_user_id)

        all_user_convs = list(conv_col.find({"participants": current_user_id}))
        visible_convs = [
            c for c in all_user_convs if _get_peer_id(c, current_user_id) not in blocked_ids
        ]

        total_unread = sum(
            max(0, int((c.get("unread_counts") or {}).get(current_user_id, 0)))
            for c in visible_convs
        )

        # Stable descending order: conversations with last_message_at first (newest -> oldest),
        # then conversations without messages yet by updated_at DESC, tie-broken by _id DESC.
        def _sort_key(doc: Dict[str, Any]):
            lma = doc.get("last_message_at")
            has_msg = 1 if lma is not None else 0
            ts = _ensure_utc(lma) if lma is not None else _ensure_utc(doc.get("updated_at") or doc.get("created_at"))
            return (has_msg, ts, str(doc["_id"]))

        visible_convs.sort(key=_sort_key, reverse=True)

        if cursor:
            cursor_dt, cursor_id = _decode_cursor(cursor)
            filtered = []
            for doc in visible_convs:
                doc_lma = doc.get("last_message_at")
                doc_id_str = str(doc["_id"])
                if cursor_dt is not None:
                    if doc_lma is None:
                        filtered.append(doc)
                    else:
                        doc_dt = _ensure_utc(doc_lma)
                        if doc_dt < cursor_dt or (doc_dt == cursor_dt and doc_id_str < cursor_id):
                            filtered.append(doc)
                else:
                    if doc_lma is None and doc_id_str < cursor_id:
                        filtered.append(doc)
            visible_convs = filtered

        has_more = len(visible_convs) > limit
        page_docs = visible_convs[:limit]

        items = [_build_conversation_model(doc, current_user_id) for doc in page_docs]

        next_cursor = None
        if has_more and page_docs:
            last_doc = page_docs[-1]
            next_cursor = _encode_cursor(last_doc.get("last_message_at"), str(last_doc["_id"]))

        return DmConversationsResponse(
            items=items,
            total_unread_count=total_unread,
            next_cursor=next_cursor,
        )

    return await asyncio.to_thread(_op)


@router.get("/conversations/{conversation_id}/messages", response_model=DmMessagesResponse)
async def list_messages(
    conversation_id: str,
    limit: int = Query(30, ge=1, le=100),
    cursor: Optional[str] = Query(None),
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])

    def _op() -> DmMessagesResponse:
        conv = _get_conversation_for_member(conversation_id, current_user_id)
        conv_id = str(conv["_id"])
        msg_col = get_dm_messages_collection()
        if msg_col is None:
            return DmMessagesResponse(items=[], next_cursor=None)

        query: Dict[str, Any] = {"conversation_id": conv_id}
        if cursor:
            cursor_dt, cursor_id = _decode_cursor(cursor)
            if cursor_dt is None:
                raise HTTPException(status_code=400, detail="Invalid pagination cursor")
            cursor_oid = ObjectId(cursor_id) if ObjectId.is_valid(cursor_id) else cursor_id
            query = {
                "$and": [
                    query,
                    {
                        "$or": [
                            {"created_at": {"$lt": cursor_dt}},
                            {"created_at": cursor_dt, "_id": {"$lt": cursor_oid}},
                        ]
                    },
                ]
            }

        docs = list(
            msg_col.find(query).sort([("created_at", -1), ("_id", -1)]).limit(limit + 1)
        )
        has_more = len(docs) > limit
        page_docs = docs[:limit]

        items = [_build_message_model(d) for d in page_docs]
        next_cursor = None
        if has_more and page_docs:
            last_doc = page_docs[-1]
            next_cursor = _encode_cursor(last_doc.get("created_at"), str(last_doc["_id"]))

        return DmMessagesResponse(items=items, next_cursor=next_cursor)

    return await asyncio.to_thread(_op)


@router.post("/conversations/{conversation_id}/messages", response_model=DmMessageModel)
async def send_message(
    conversation_id: str,
    body: SendDmMessageRequest,
    x_idempotency_key: Optional[str] = Header(None, alias="X-Idempotency-Key"),
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])
    request_key = x_idempotency_key.strip() if x_idempotency_key and x_idempotency_key.strip() else None

    def _op() -> Tuple[DmMessageModel, str, str, bool]:
        conv = _get_conversation_for_member(conversation_id, current_user_id)
        conv_id = str(conv["_id"])
        peer_id = _get_peer_id(conv, current_user_id)

        _enforce_dm_allowed(current_user_id, peer_id)
        if body.type == "story_reply":
            _enforce_story_reply_allowed(current_user_id, peer_id)

        conv_col = get_dm_conversations_collection()
        msg_col = get_dm_messages_collection()
        if conv_col is None or msg_col is None:
            raise HTTPException(status_code=500, detail="Database not configured")

        # Idempotency check before insertion
        if request_key is not None:
            existing = msg_col.find_one(
                {"sender_id": current_user_id, "request_key": request_key}
            )
            if existing is not None:
                if str(existing.get("conversation_id")) != conv_id:
                    raise HTTPException(
                        status_code=409,
                        detail="Idempotency key already used in another conversation.",
                    )
                return _build_message_model(existing), conv_id, peer_id, False

        cleaned_content = body.content.strip()
        validated_media_url: Optional[str] = None
        shared_post_preview: Optional[Dict[str, Any]] = None
        shared_post_id = body.shared_post_id.strip() if body.shared_post_id else None

        if body.type == "text":
            if not cleaned_content:
                raise HTTPException(status_code=400, detail="Nội dung tin nhắn không được để trống.")
        elif body.type in ("voice", "photo", "video"):
            validated_media_url = _validate_media_url(body.media_url)
        elif body.type == "post_share":
            if not shared_post_id:
                raise HTTPException(status_code=400, detail="shared_post_id là bắt buộc cho post_share.")
            shared_post_preview = _validate_shared_post_preview(shared_post_id, current_user_id)
        elif body.type == "story_reply":
            if body.media_url:
                validated_media_url = _validate_media_url(body.media_url)
            if not cleaned_content and not validated_media_url:
                raise HTTPException(status_code=400, detail="Nội dung trả lời tin không được để trống.")

        reply_to_id = body.reply_to_message_id.strip() if body.reply_to_message_id else None
        if reply_to_id:
            reply_filters: List[Dict[str, Any]] = [{"_id": reply_to_id, "conversation_id": conv_id}]
            if ObjectId.is_valid(reply_to_id):
                reply_filters.insert(0, {"_id": ObjectId(reply_to_id), "conversation_id": conv_id})
            if msg_col.find_one({"$or": reply_filters}) is None:
                raise HTTPException(status_code=404, detail="Replied message not found")

        now = datetime.now(timezone.utc)
        msg_doc: Dict[str, Any] = {
            "_id": ObjectId(),
            "conversation_id": conv_id,
            "sender_id": current_user_id,
            "type": body.type,
            "content": cleaned_content,
            "media_url": validated_media_url,
            "duration_seconds": body.duration_seconds,
            "shared_post_id": shared_post_id,
            "shared_post_preview": shared_post_preview,
            "reply_to_message_id": reply_to_id,
            "is_deleted": False,
            "created_at": now,
        }
        if request_key is not None:
            msg_doc["request_key"] = request_key

        try:
            msg_col.insert_one(msg_doc)
        except DuplicateKeyError:
            if request_key is not None:
                existing = msg_col.find_one(
                    {"sender_id": current_user_id, "request_key": request_key}
                )
                if existing is not None:
                    return _build_message_model(existing), conv_id, peer_id, False
            raise

        preview_text = _format_last_message_preview(body.type, cleaned_content)
        conv_col.update_one(
            {"_id": conv["_id"]},
            {
                "$set": {
                    "last_message_preview": preview_text,
                    "last_message_type": body.type,
                    "last_message_at": now,
                    "updated_at": now,
                },
                "$inc": {
                    f"unread_counts.{peer_id}": 1,
                },
            },
        )

        return _build_message_model(msg_doc), conv_id, peer_id, True

    message_model, conv_id, peer_id, created_new = await asyncio.to_thread(_op)

    if created_new:
        await ws_manager.send_to_users(
            [peer_id, current_user_id],
            {
                "event": "message.created",
                "conversation_id": conv_id,
                "message": message_model.model_dump(mode="json"),
            },
        )

    return message_model


@router.post("/conversations/{conversation_id}/read")
async def mark_conversation_read(
    conversation_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])

    def _op() -> Tuple[str, str, datetime]:
        conv = _get_conversation_for_member(conversation_id, current_user_id)
        conv_id = str(conv["_id"])
        peer_id = _get_peer_id(conv, current_user_id)
        now = datetime.now(timezone.utc)

        conv_col = get_dm_conversations_collection()
        conv_col.update_one(
            {"_id": conv["_id"]},
            {
                "$set": {
                    f"unread_counts.{current_user_id}": 0,
                    f"last_read_at.{current_user_id}": now,
                }
            },
        )
        return conv_id, peer_id, now

    conv_id, peer_id, read_at = await asyncio.to_thread(_op)

    await ws_manager.send_to_users(
        [peer_id, current_user_id],
        {
            "event": "conversation.read",
            "conversation_id": conv_id,
            "reader_id": current_user_id,
            "read_at": read_at.isoformat(),
        },
    )

    return {
        "conversation_id": conv_id,
        "unread_count": 0,
        "read_at": read_at.isoformat(),
    }


@router.delete("/messages/{message_id}")
async def delete_message(
    message_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])

    def _op() -> Tuple[str, str, str]:
        msg_col = get_dm_messages_collection()
        conv_col = get_dm_conversations_collection()
        if msg_col is None or conv_col is None:
            raise HTTPException(status_code=500, detail="Database not configured")

        filters: List[Dict[str, Any]] = [{"_id": message_id}]
        if ObjectId.is_valid(message_id):
            filters.insert(0, {"_id": ObjectId(message_id)})

        msg = msg_col.find_one({"$or": filters})
        if not msg:
            raise HTTPException(status_code=404, detail="Message not found")

        conv = _get_conversation_for_member(str(msg["conversation_id"]), current_user_id)
        conv_id = str(conv["_id"])
        peer_id = _get_peer_id(conv, current_user_id)

        if str(msg.get("sender_id")) != current_user_id:
            raise HTTPException(
                status_code=403,
                detail="Bạn chỉ có thể xóa tin nhắn của chính mình.",
            )

        now = datetime.now(timezone.utc)
        msg_col.update_one(
            {"_id": msg["_id"]},
            {
                "$set": {
                    "is_deleted": True,
                    "deleted_at": now,
                }
            },
        )

        # If this was the latest message in the conversation, redact the inbox preview
        latest = list(
            msg_col.find({"conversation_id": conv_id})
            .sort([("created_at", -1), ("_id", -1)])
            .limit(1)
        )
        if latest and str(latest[0]["_id"]) == str(msg["_id"]):
            conv_col.update_one(
                {"_id": conv["_id"]},
                {"$set": {"last_message_preview": "Tin nhắn đã bị thu hồi", "updated_at": now}},
            )

        return str(msg["_id"]), conv_id, peer_id

    msg_id, conv_id, peer_id = await asyncio.to_thread(_op)

    await ws_manager.send_to_users(
        [peer_id, current_user_id],
        {
            "event": "message.deleted",
            "conversation_id": conv_id,
            "message_id": msg_id,
            "deleted_by": current_user_id,
        },
    )

    return {
        "id": msg_id,
        "conversation_id": conv_id,
        "is_deleted": True,
    }


@router.get("/unread-count", response_model=DmUnreadCountResponse)
async def get_unread_count(
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])

    def _op() -> DmUnreadCountResponse:
        conv_col = get_dm_conversations_collection()
        if conv_col is None:
            return DmUnreadCountResponse(unread_count=0)

        blocked_ids = _get_blocked_user_ids(current_user_id)
        total = 0
        for conv in conv_col.find({"participants": current_user_id}):
            if _get_peer_id(conv, current_user_id) in blocked_ids:
                continue
            total += max(0, int((conv.get("unread_counts") or {}).get(current_user_id, 0)))

        return DmUnreadCountResponse(unread_count=total)

    return await asyncio.to_thread(_op)


# ---------------------------------------------------------------------------
# WebSocket Real-Time Endpoint (/api/community/ws/chat)
# ---------------------------------------------------------------------------


def _resolve_typing_peer_sync(current_user_id: str, conversation_id: str) -> Optional[str]:
    try:
        conv = _get_conversation_for_member(conversation_id, current_user_id)
    except HTTPException:
        return None
    peer_id = _get_peer_id(conv, current_user_id)
    if _is_blocked_either_way(current_user_id, peer_id):
        return None
    return peer_id


def _prepare_call_invite_sync(
    caller_id: str, conversation_id: str
) -> Tuple[str, str, Dict[str, Any]]:
    """Validate conversation membership, 2-way block & who_can_dm privacy, and project caller profile."""
    conv = _get_conversation_for_member(conversation_id, caller_id)
    canonical_conv_id = str(conv["_id"])
    callee_id = _get_peer_id(conv, caller_id)
    if not callee_id or callee_id == caller_id:
        raise HTTPException(status_code=400, detail="Không thể tự gọi cho chính mình.")
    _enforce_dm_allowed(caller_id, callee_id)
    caller_info = _sanitize_participant_projection(caller_id).model_dump(mode="json")
    return canonical_conv_id, callee_id, caller_info


_CALL_WS_EVENTS = frozenset(
    {
        "call.invite",
        "call.accept",
        "call.reject",
        "call.cancel",
        "call.hangup",
        "call.busy",
        "webrtc.offer",
        "webrtc.answer",
        "webrtc.ice",
    }
)

_CALL_ERROR_DETAILS: Dict[str, str] = {
    "not_found": "Cuộc gọi không tồn tại hoặc đã kết thúc.",
    "forbidden": "Bạn không có quyền thực hiện thao tác trên cuộc gọi này.",
    "invalid_state": "Trạng thái cuộc gọi không hợp lệ cho thao tác này.",
    "invalid_payload": "Dữ liệu signaling cuộc gọi không hợp lệ.",
}


async def _send_call_error(
    websocket: WebSocket,
    call_id: str,
    code: str,
    detail: Optional[str] = None,
) -> None:
    await websocket.send_json(
        {
            "event": "call.error",
            "call_id": call_id,
            "code": code,
            "detail": detail or _CALL_ERROR_DETAILS.get(code, "Lỗi signaling cuộc gọi."),
        }
    )


async def _handle_ws_call_event(
    websocket: WebSocket,
    current_user_id: str,
    event: str,
    frame: Dict[str, Any],
) -> None:
    call_id = str(frame.get("call_id") or "").strip()
    if not call_id or len(call_id) > 128:
        await _send_call_error(websocket, call_id, "invalid_payload", "call_id là bắt buộc.")
        return

    if event == "call.invite":
        conv_id = str(frame.get("conversation_id") or "").strip()
        call_type = str(frame.get("call_type") or "").strip().lower()
        if not conv_id or call_type not in ("audio", "video"):
            await _send_call_error(
                websocket,
                call_id,
                "invalid_payload",
                "conversation_id và call_type ('audio' hoặc 'video') là bắt buộc.",
            )
            return

        try:
            canonical_conv_id, callee_id, caller_info = await asyncio.to_thread(
                _prepare_call_invite_sync, current_user_id, conv_id
            )
        except HTTPException as exc:
            if exc.status_code == 403:
                code = "forbidden"
            elif exc.status_code == 404:
                code = "not_found"
            elif exc.status_code == 400:
                code = "invalid_payload"
            else:
                code = "server_error"
            await _send_call_error(websocket, call_id, code, str(exc.detail))
            return

        session, err = await call_registry.start_invite(
            call_id=call_id,
            conversation_id=canonical_conv_id,
            caller_id=current_user_id,
            callee_id=callee_id,
            call_type=call_type,
        )
        if err == "duplicate_call_id":
            await _send_call_error(
                websocket,
                call_id,
                "invalid_state",
                "call_id đang tồn tại trong một cuộc gọi khác.",
            )
            return
        if err == "callee_busy":
            await websocket.send_json(
                {
                    "event": "call.busy",
                    "call_id": call_id,
                    "conversation_id": canonical_conv_id,
                    "by_user_id": callee_id,
                }
            )
            busy_session = CallSession(
                call_id=call_id,
                conversation_id=canonical_conv_id,
                caller_id=current_user_id,
                callee_id=callee_id,
                call_type=call_type,
                state="ended",
                logged=True,
            )
            await _persist_and_broadcast_call_log(busy_session, "missed", 0)
            return
        if err == "caller_busy":
            await websocket.send_json(
                {
                    "event": "call.busy",
                    "call_id": call_id,
                    "conversation_id": canonical_conv_id,
                    "by_user_id": current_user_id,
                }
            )
            return

        assert session is not None
        await ws_manager.send_to_user(
            callee_id,
            {
                "event": "call.invite",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "call_type": session.call_type,
                "caller": caller_info,
            },
        )
        return

    if event == "call.accept":
        session, err = await call_registry.accept_call(call_id, current_user_id)
        if err or session is None:
            await _send_call_error(websocket, call_id, err or "invalid_state")
            return
        await ws_manager.send_to_user(
            session.caller_id,
            {
                "event": "call.accept",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "by_user_id": current_user_id,
            },
        )
        await ws_manager.send_to_other_user_sockets(
            current_user_id,
            websocket,
            {
                "event": "call.handled_elsewhere",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
            },
        )
        return

    if event == "call.reject":
        session, should_log, err = await call_registry.reject_call(call_id, current_user_id)
        if err or session is None:
            await _send_call_error(websocket, call_id, err or "invalid_state")
            return
        await ws_manager.send_to_user(
            session.caller_id,
            {
                "event": "call.reject",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "by_user_id": current_user_id,
            },
        )
        await ws_manager.send_to_other_user_sockets(
            current_user_id,
            websocket,
            {
                "event": "call.handled_elsewhere",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
            },
        )
        if should_log:
            await _persist_and_broadcast_call_log(session, "rejected", 0)
        return

    if event == "call.cancel":
        session, should_log, err = await call_registry.cancel_call(call_id, current_user_id)
        if err or session is None:
            await _send_call_error(websocket, call_id, err or "invalid_state")
            return
        await ws_manager.send_to_user(
            session.callee_id,
            {
                "event": "call.cancel",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "by_user_id": current_user_id,
            },
        )
        if should_log:
            await _persist_and_broadcast_call_log(session, "missed", 0)
        return

    if event == "call.hangup":
        session, call_status, duration_sec, should_log, err = await call_registry.hangup_call(
            call_id, current_user_id
        )
        if err or session is None:
            await _send_call_error(websocket, call_id, err or "invalid_state")
            return
        peer_id = (
            session.callee_id if current_user_id == session.caller_id else session.caller_id
        )
        await ws_manager.send_to_user(
            peer_id,
            {
                "event": "call.hangup",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "by_user_id": current_user_id,
                "duration_sec": duration_sec,
            },
        )
        if should_log:
            await _persist_and_broadcast_call_log(session, call_status, duration_sec)
        return

    if event == "call.busy":
        session, should_log, err = await call_registry.busy_call(call_id, current_user_id)
        if err or session is None:
            await _send_call_error(websocket, call_id, err or "invalid_state")
            return
        await ws_manager.send_to_user(
            session.caller_id,
            {
                "event": "call.busy",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "by_user_id": current_user_id,
            },
        )
        await ws_manager.send_to_other_user_sockets(
            current_user_id,
            websocket,
            {
                "event": "call.handled_elsewhere",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
            },
        )
        if should_log:
            await _persist_and_broadcast_call_log(session, "missed", 0)
        return

    if event in ("webrtc.offer", "webrtc.answer"):
        sdp = frame.get("sdp")
        if not isinstance(sdp, str) or not sdp.strip():
            await _send_call_error(
                websocket, call_id, "invalid_payload", "sdp là bắt buộc cho WebRTC offer/answer."
            )
            return
        session, peer_id, err = await call_registry.resolve_webrtc_peer(call_id, current_user_id)
        if err or session is None or peer_id is None:
            await _send_call_error(websocket, call_id, err or "invalid_state")
            return
        default_sdp_type = "offer" if event == "webrtc.offer" else "answer"
        sdp_type = str(frame.get("sdp_type") or default_sdp_type)
        await ws_manager.send_to_user(
            peer_id,
            {
                "event": event,
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "from_user_id": current_user_id,
                "sdp": sdp,
                "sdp_type": sdp_type,
            },
        )
        return

    if event == "webrtc.ice":
        if frame.get("candidate") is None:
            await _send_call_error(
                websocket, call_id, "invalid_payload", "candidate là bắt buộc cho webrtc.ice."
            )
            return
        session, peer_id, err = await call_registry.resolve_webrtc_peer(call_id, current_user_id)
        if err or session is None or peer_id is None:
            await _send_call_error(websocket, call_id, err or "invalid_state")
            return
        await ws_manager.send_to_user(
            peer_id,
            {
                "event": "webrtc.ice",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "from_user_id": current_user_id,
                "candidate": frame.get("candidate"),
                "sdp_mid": frame.get("sdp_mid"),
                "sdp_mline_index": frame.get("sdp_mline_index"),
            },
        )
        return


_BACKGROUND_CALL_TASKS: Set["asyncio.Future[Any]"] = set()


def _on_call_cleanup_done(task: "asyncio.Future[Any]") -> None:
    _BACKGROUND_CALL_TASKS.discard(task)
    if not task.cancelled():
        task.exception()  # retrieve to avoid "exception never retrieved" warnings


async def _cleanup_user_call_on_disconnect(user_id: str) -> None:
    result = await call_registry.cleanup_user_disconnect(user_id)
    if result is None:
        return
    session, prev_state, call_status, duration_sec, should_log = result
    peer_id = session.callee_id if user_id == session.caller_id else session.caller_id

    if prev_state == "ringing" and user_id == session.caller_id:
        await ws_manager.send_to_user(
            peer_id,
            {
                "event": "call.cancel",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "by_user_id": user_id,
            },
        )
    else:
        await ws_manager.send_to_user(
            peer_id,
            {
                "event": "call.hangup",
                "call_id": session.call_id,
                "conversation_id": session.conversation_id,
                "by_user_id": user_id,
                "duration_sec": duration_sec,
            },
        )

    if should_log:
        await _persist_and_broadcast_call_log(session, call_status, duration_sec)


def _extract_ws_token(websocket: WebSocket) -> Optional[str]:
    token = websocket.query_params.get("token")
    if token and token.strip():
        return token.strip()
    auth_header = websocket.headers.get("authorization")
    if auth_header:
        parts = auth_header.split()
        if len(parts) == 2 and parts[0].lower() == "bearer":
            return parts[1].strip()
    return None


@ws_router.websocket("/api/community/ws/chat")
async def dm_chat_websocket(websocket: WebSocket):
    token = _extract_ws_token(websocket)
    if not token:
        await websocket.close(code=4401, reason="Authentication required")
        return

    try:
        current_user = await asyncio.to_thread(_decode_jwt_user_sync, token)
    except HTTPException:
        await websocket.close(code=4401, reason="Invalid or expired token")
        return
    except Exception:
        await websocket.close(code=4401, reason="Authentication failed")
        return

    current_user_id = str(current_user["_id"])
    await ws_manager.connect(current_user_id, websocket)

    try:
        while True:
            raw_text = await websocket.receive_text()
            try:
                frame = json.loads(raw_text)
            except (ValueError, TypeError):
                await websocket.send_json({"event": "error", "detail": "Invalid JSON payload"})
                continue

            if not isinstance(frame, dict):
                continue

            event = frame.get("event")
            if event == "ping":
                await websocket.send_json({"event": "pong"})
            elif event == "typing":
                conv_id = str(frame.get("conversation_id") or "").strip()
                is_typing = bool(frame.get("is_typing", False))
                if not conv_id:
                    continue
                peer_id = await asyncio.to_thread(
                    _resolve_typing_peer_sync, current_user_id, conv_id
                )
                if peer_id:
                    await ws_manager.send_to_user(
                        peer_id,
                        {
                            "event": "typing",
                            "conversation_id": conv_id,
                            "user_id": current_user_id,
                            "is_typing": is_typing,
                        },
                    )
            elif event in _CALL_WS_EVENTS:
                await _handle_ws_call_event(websocket, current_user_id, event, frame)
    except WebSocketDisconnect:
        pass
    finally:
        was_last_socket = await asyncio.shield(ws_manager.disconnect(current_user_id, websocket))
        if was_last_socket:
            # Detached task: survives cancellation of this handler task (server shutdown,
            # TestClient exit) so the peer is still notified and the call_log persisted.
            cleanup_task = asyncio.ensure_future(_cleanup_user_call_on_disconnect(current_user_id))
            _BACKGROUND_CALL_TASKS.add(cleanup_task)
            cleanup_task.add_done_callback(_on_call_cleanup_done)
