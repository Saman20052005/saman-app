"""Comprehensive tests for Wave 4 Community Messenger-Lite DM (REST + Range Streaming + WebSocket)."""

from __future__ import annotations

import copy
import io
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

import jwt
import pytest
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image
from pymongo.errors import DuplicateKeyError
from starlette.websockets import WebSocketDisconnect

from backend.app.database_community_dm import (
    COLL_DM_CONVERSATIONS,
    COLL_DM_MESSAGES,
    ensure_community_dm_indexes,
)
from backend.auth.config import JWT_ALGORITHM, JWT_SECRET
from backend.routers import community_dm


# ---------------------------------------------------------------------------
# Minimal accurate in-memory MongoDB mock for unit/integration testing
# ---------------------------------------------------------------------------


def _get_nested(doc: Dict[str, Any], key: str) -> Any:
    cur: Any = doc
    for part in key.split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def _set_nested(doc: Dict[str, Any], key: str, value: Any) -> None:
    parts = key.split(".")
    cur = doc
    for part in parts[:-1]:
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = {}
        cur = cur[part]
    cur[parts[-1]] = value


def _inc_nested(doc: Dict[str, Any], key: str, delta: int | float) -> None:
    parts = key.split(".")
    cur = doc
    for part in parts[:-1]:
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = {}
        cur = cur[part]
    cur[parts[-1]] = cur.get(parts[-1], 0) + delta


def _matches_filter(doc: Dict[str, Any], flt: Dict[str, Any]) -> bool:
    if not flt:
        return True
    for k, cond in flt.items():
        if k == "$or":
            if not any(_matches_filter(doc, sub) for sub in cond):
                return False
            continue
        if k == "$and":
            if not all(_matches_filter(doc, sub) for sub in cond):
                return False
            continue

        val = _get_nested(doc, k)
        if isinstance(cond, dict):
            for op, expected in cond.items():
                if op == "$lt":
                    if val is None or not (val < expected):
                        return False
                elif op == "$lte":
                    if val is None or not (val <= expected):
                        return False
                elif op == "$gt":
                    if val is None or not (val > expected):
                        return False
                elif op == "$ne":
                    if val == expected:
                        return False
                elif op == "$in":
                    if isinstance(val, list):
                        if not any(v in expected for v in val):
                            return False
                    elif val not in expected:
                        return False
                elif op == "$nin":
                    if isinstance(val, list):
                        if any(v in expected for v in val):
                            return False
                    elif val in expected:
                        return False
                elif op == "$type":
                    if expected == "string" and not isinstance(val, str):
                        return False
                else:
                    raise NotImplementedError(f"Unsupported operator: {op}")
        else:
            if isinstance(val, list):
                if cond not in val:
                    return False
            else:
                if val != cond:
                    return False
    return True


class FakeCursor:
    def __init__(self, docs: List[Dict[str, Any]]):
        self._docs = docs

    def sort(self, spec: List[Tuple[str, int]]) -> "FakeCursor":
        docs = list(self._docs)
        for field, direction in reversed(spec):
            reverse = direction == -1
            docs.sort(
                key=lambda d: (
                    _get_nested(d, field) is not None,
                    _get_nested(d, field) if _get_nested(d, field) is not None else "",
                ),
                reverse=reverse,
            )
        return FakeCursor(docs)

    def limit(self, count: int) -> "FakeCursor":
        return FakeCursor(self._docs[:count])

    def __iter__(self):
        return iter(copy.deepcopy(self._docs))


class FakeCollection:
    def __init__(self, name: str):
        self.name = name
        self.docs: List[Dict[str, Any]] = []
        self.indexes: List[Dict[str, Any]] = []

    def create_index(self, keys, unique: bool = False, name: Optional[str] = None, **kwargs) -> str:
        idx_name = name or "_".join(f"{k}_{d}" for k, d in keys)
        for existing in self.indexes:
            if existing["name"] == idx_name:
                return idx_name
        self.indexes.append(
            {
                "name": idx_name,
                "keys": list(keys),
                "unique": unique,
                "partialFilterExpression": kwargs.get("partialFilterExpression"),
            }
        )
        return idx_name

    def find_one(self, flt: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        for doc in self.docs:
            if _matches_filter(doc, flt):
                return copy.deepcopy(doc)
        return None

    def find(self, flt: Optional[Dict[str, Any]] = None) -> FakeCursor:
        matched = [d for d in self.docs if _matches_filter(d, flt or {})]
        return FakeCursor(matched)

    def insert_one(self, doc: Dict[str, Any]):
        new_doc = copy.deepcopy(doc)
        if "_id" not in new_doc:
            new_doc["_id"] = ObjectId()

        for idx in self.indexes:
            if not idx["unique"]:
                continue
            pfe = idx.get("partialFilterExpression")
            if pfe and not _matches_filter(new_doc, pfe):
                continue
            new_key = tuple(_get_nested(new_doc, k) for k, _ in idx["keys"])
            for existing in self.docs:
                if pfe and not _matches_filter(existing, pfe):
                    continue
                old_key = tuple(_get_nested(existing, k) for k, _ in idx["keys"])
                if old_key == new_key:
                    raise DuplicateKeyError(f"Duplicate key on index {idx['name']}: {new_key}")

        self.docs.append(new_doc)
        return type("InsertOneResult", (), {"inserted_id": new_doc["_id"]})()

    def update_one(self, flt: Dict[str, Any], update: Dict[str, Any]):
        for doc in self.docs:
            if _matches_filter(doc, flt):
                if "$set" in update:
                    for k, v in update["$set"].items():
                        _set_nested(doc, k, copy.deepcopy(v))
                if "$inc" in update:
                    for k, delta in update["$inc"].items():
                        _inc_nested(doc, k, delta)
                return type("UpdateResult", (), {"matched_count": 1, "modified_count": 1})()
        return type("UpdateResult", (), {"matched_count": 0, "modified_count": 0})()

    def count_documents(self, flt: Optional[Dict[str, Any]] = None) -> int:
        return sum(1 for d in self.docs if _matches_filter(d, flt or {}))


class FakeDatabase:
    def __init__(self):
        self._cols: Dict[str, FakeCollection] = {}

    def __getitem__(self, name: str) -> FakeCollection:
        if name not in self._cols:
            self._cols[name] = FakeCollection(name)
        return self._cols[name]


# ---------------------------------------------------------------------------
# Helpers & Fixtures
# ---------------------------------------------------------------------------


def _make_token(user_id: str, email: str, name: str, exp_delta: Optional[timedelta] = None) -> str:
    payload: Dict[str, Any] = {"sub": user_id, "email": email, "name": name}
    if exp_delta is not None:
        payload["exp"] = datetime.now(timezone.utc) + exp_delta
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def _make_png_bytes(size=(32, 32), color="seagreen") -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, color=color).save(buf, format="PNG")
    return buf.getvalue()


@pytest.fixture()
def dm_env(tmp_path, monkeypatch):
    fake_db = FakeDatabase()
    ensure_community_dm_indexes(fake_db)

    monkeypatch.setattr(community_dm, "db", fake_db)
    monkeypatch.setattr(community_dm, "COMMUNITY_DM_STATIC_DIR", str(tmp_path))
    monkeypatch.setattr(community_dm, "ws_manager", community_dm.DmConnectionManager())

    user_a_id = str(ObjectId())
    user_b_id = str(ObjectId())
    user_c_id = str(ObjectId())

    fake_db["users"].insert_one(
        {
            "_id": ObjectId(user_a_id),
            "email": "alice@saman.test",
            "password_hash": "super-secret-hash",
            "name": "Alice Athlete",
            "avatar_url": "/static/avatars/alice.jpg",
            "is_verified": True,
        }
    )
    fake_db["users"].insert_one(
        {
            "_id": ObjectId(user_b_id),
            "email": "bob@saman.test",
            "password_hash": "bob-secret-hash",
            "name": "Bob Coach",
            "avatar_url": "/static/avatars/bob.jpg",
            "is_verified": False,
        }
    )
    fake_db["users"].insert_one(
        {
            "_id": ObjectId(user_c_id),
            "email": "charlie@saman.test",
            "password_hash": "charlie-secret-hash",
            "name": "Charlie Runner",
            "avatar_url": None,
            "is_verified": False,
        }
    )

    app = FastAPI()
    app.include_router(community_dm.router)
    app.include_router(community_dm.ws_router)
    # Context-managed TestClient keeps ONE shared anyio portal/event loop for REST calls and
    # WebSocket sessions, so REST handlers can push frames to live sockets without cross-loop hangs.
    with TestClient(app) as client:
        token_a = _make_token(user_a_id, "alice@saman.test", "Alice Athlete")
        token_b = _make_token(user_b_id, "bob@saman.test", "Bob Coach")
        token_c = _make_token(user_c_id, "charlie@saman.test", "Charlie Runner")

        yield {
            "db": fake_db,
            "client": client,
            "tmp_path": tmp_path,
            "a": {"id": user_a_id, "token": token_a, "headers": {"Authorization": f"Bearer {token_a}"}},
            "b": {"id": user_b_id, "token": token_b, "headers": {"Authorization": f"Bearer {token_b}"}},
            "c": {"id": user_c_id, "token": token_c, "headers": {"Authorization": f"Bearer {token_c}"}},
        }


# ---------------------------------------------------------------------------
# 1. Index setup tests
# ---------------------------------------------------------------------------


def test_ensure_community_dm_indexes():
    fake_db = FakeDatabase()
    created = ensure_community_dm_indexes(fake_db)

    assert created[COLL_DM_CONVERSATIONS] == ["idx_dm_pair_unique", "idx_dm_user_inbox"]
    assert created[COLL_DM_MESSAGES] == ["idx_dm_messages_stream", "idx_dm_msg_idempotent"]

    msg_indexes = {idx["name"]: idx for idx in fake_db[COLL_DM_MESSAGES].indexes}
    assert msg_indexes["idx_dm_msg_idempotent"]["unique"] is True
    assert msg_indexes["idx_dm_msg_idempotent"]["partialFilterExpression"] == {
        "request_key": {"$type": "string"}
    }

    with pytest.raises(RuntimeError):
        ensure_community_dm_indexes(None)


# ---------------------------------------------------------------------------
# 2. Media upload, magic bytes, size limit, path traversal & Range 206 tests
# ---------------------------------------------------------------------------


def test_media_upload_valid_photo_voice_video_and_range_streaming(dm_env):
    client: TestClient = dm_env["client"]
    auth_a = dm_env["a"]["headers"]

    # Valid PNG photo
    png_bytes = _make_png_bytes()
    r_img = client.post(
        "/api/community/dm/media/upload",
        headers=auth_a,
        files={"file": ("photo.png", png_bytes, "image/png")},
    )
    assert r_img.status_code == 200, r_img.text
    img_data = r_img.json()
    assert img_data["media_kind"] == "image"
    assert img_data["media_url"].startswith("/static/community_dm/")
    assert img_data["size_bytes"] == len(png_bytes)

    # Valid Voice formats (.m4a, .mp3, .aac, .wav, .ogg)
    voice_samples = [
        ("voice.m4a", b"\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00M4A isom" + b"A" * 64, "audio/mp4"),
        ("voice.mp3", b"ID3\x03\x00\x00\x00\x00\x00\x00" + b"B" * 64, "audio/mpeg"),
        ("voice_sync.mp3", b"\xff\xfb\x90\x64" + b"C" * 64, "audio/mpeg"),
        ("voice.aac", b"\xff\xf1\x50\x80\x02\x00\xfc" + b"D" * 64, "audio/aac"),
        ("voice.wav", b"RIFF\x24\x00\x00\x00WAVEfmt " + b"E" * 64, "audio/wav"),
        ("voice.ogg", b"OggS\x00\x02\x00\x00" + b"F" * 64, "audio/ogg"),
    ]
    for fname, payload, expected_ct in voice_samples:
        resp = client.post(
            "/api/community/dm/media/upload",
            headers=auth_a,
            files={"file": (fname, payload, expected_ct)},
        )
        assert resp.status_code == 200, f"{fname}: {resp.text}"
        body = resp.json()
        assert body["media_kind"] == "audio"
        assert body["content_type"] == expected_ct
        assert body["size_bytes"] == len(payload)

    # Valid Video (.mp4, .mov, .webm) + verify Range 206 Partial Content
    mp4_payload = b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom" + bytes(range(100))
    r_vid = client.post(
        "/api/community/dm/media/upload",
        headers=auth_a,
        files={"file": ("clip.mp4", mp4_payload, "video/mp4")},
    )
    assert r_vid.status_code == 200, r_vid.text
    vid_data = r_vid.json()
    assert vid_data["media_kind"] == "video"
    media_url = vid_data["media_url"]
    stored_name = media_url.rsplit("/", 1)[-1]

    # Test Range: bytes=0-9 on BOTH /static/community_dm/{filename} and /api/community/dm/media/{filename}
    for url in (media_url, f"/api/community/dm/media/{stored_name}"):
        r_partial = client.get(url, headers={"Range": "bytes=0-9"})
        assert r_partial.status_code == 206
        assert r_partial.headers["content-range"] == f"bytes 0-9/{len(mp4_payload)}"
        assert r_partial.headers["accept-ranges"] == "bytes"
        assert r_partial.headers["content-length"] == "10"
        assert r_partial.content == mp4_payload[:10]

        # Full GET returns 200 with Accept-Ranges
        r_full = client.get(url)
        assert r_full.status_code == 200
        assert r_full.headers["accept-ranges"] == "bytes"
        assert r_full.content == mp4_payload

        # Out of bounds Range returns 416
        r_oob = client.get(url, headers={"Range": f"bytes={len(mp4_payload) + 10}-"})
        assert r_oob.status_code == 416

    # Also check .mov (moov header) and .webm (EBML header)
    r_mov = client.post(
        "/api/community/dm/media/upload",
        headers=auth_a,
        files={"file": ("clip.mov", b"\x00\x00\x00\x20moov" + b"0" * 32, "video/quicktime")},
    )
    assert r_mov.status_code == 200

    r_webm = client.post(
        "/api/community/dm/media/upload",
        headers=auth_a,
        files={"file": ("clip.webm", b"\x1a\x45\xdf\xa3" + b"1" * 32, "video/webm")},
    )
    assert r_webm.status_code == 200


def test_media_upload_rejects_spoofed_magic_oversized_and_traversal(dm_env, monkeypatch):
    client: TestClient = dm_env["client"]
    auth_a = dm_env["a"]["headers"]

    # Spoofed files
    for fname, bad_bytes in [
        ("fake.png", b"NOT A PNG FILE"),
        ("fake.mp3", b"NOT AN MP3 FILE"),
        ("fake.m4a", b"NOT AN M4A FILE"),
        ("fake.mp4", b"NOT AN MP4 FILE"),
        ("fake.webm", b"NOT A WEBM FILE"),
        ("fake.wav", b"RIFF\x10\x00\x00\x00WEBPfake"),
        ("script.exe", b"MZ\x90\x00"),
    ]:
        resp = client.post(
            "/api/community/dm/media/upload",
            headers=auth_a,
            files={"file": (fname, bad_bytes, "application/octet-stream")},
        )
        assert resp.status_code == 400, f"Expected 400 for {fname}, got {resp.status_code}"

    # Oversized voice/video rejected with 413
    monkeypatch.setattr(community_dm, "MAX_AUDIO_BYTES", 32)
    r_big_audio = client.post(
        "/api/community/dm/media/upload",
        headers=auth_a,
        files={"file": ("long.ogg", b"OggS" + b"X" * 40, "audio/ogg")},
    )
    assert r_big_audio.status_code == 413

    monkeypatch.setattr(community_dm, "MAX_VIDEO_BYTES", 32)
    r_big_video = client.post(
        "/api/community/dm/media/upload",
        headers=auth_a,
        files={"file": ("big.mp4", b"\x00\x00\x00\x18ftypmp42" + b"Y" * 40, "video/mp4")},
    )
    assert r_big_video.status_code == 413

    # Path traversal on upload filename is neutralized via os.path.basename + UUID storage
    monkeypatch.setattr(community_dm, "MAX_AUDIO_BYTES", 1024)
    r_trav = client.post(
        "/api/community/dm/media/upload",
        headers=auth_a,
        files={"file": ("../../outside.ogg", b"OggS12345678", "audio/ogg")},
    )
    assert r_trav.status_code == 200
    assert ".." not in r_trav.json()["media_url"]
    assert r_trav.json()["file_name"] == "outside.ogg"

    # Path traversal on GET is blocked with 404
    assert client.get("/api/community/dm/media/..%2Fmain.py").status_code == 404
    assert client.get("/static/community_dm/..%2Fmain.py").status_code == 404


# ---------------------------------------------------------------------------
# 3. Conversation create/list, Block 403, who_can_dm 403
# ---------------------------------------------------------------------------


def test_conversation_create_list_block_and_who_can_dm(dm_env):
    client: TestClient = dm_env["client"]
    fake_db: FakeDatabase = dm_env["db"]
    a, b, c = dm_env["a"], dm_env["b"], dm_env["c"]

    # Extra fields forbidden
    r_extra = client.post(
        "/api/community/dm/conversations",
        headers=a["headers"],
        json={"target_user_id": b["id"], "unexpected": True},
    )
    assert r_extra.status_code == 422

    # Self-chat rejected
    r_self = client.post(
        "/api/community/dm/conversations",
        headers=a["headers"],
        json={"target_user_id": a["id"]},
    )
    assert r_self.status_code == 400

    # who_can_dm = "nobody" -> 403
    fake_db["community_user_settings"].insert_one(
        {"user_id": b["id"], "who_can_dm": "nobody", "show_activity_status": False}
    )
    r_nobody = client.post(
        "/api/community/dm/conversations",
        headers=a["headers"],
        json={"target_user_id": b["id"]},
    )
    assert r_nobody.status_code == 403

    # who_can_dm = "followers" -> 403 before following, 200 after following
    fake_db["community_user_settings"].update_one(
        {"user_id": b["id"]}, {"$set": {"who_can_dm": "followers"}}
    )
    r_followers_denied = client.post(
        "/api/community/dm/conversations",
        headers=a["headers"],
        json={"target_user_id": b["id"]},
    )
    assert r_followers_denied.status_code == 403

    fake_db["community_follows"].insert_one({"follower_id": a["id"], "following_id": b["id"]})
    r_conv = client.post(
        "/api/community/dm/conversations",
        headers=a["headers"],
        json={"target_user_id": b["id"]},
    )
    assert r_conv.status_code == 200, r_conv.text
    conv_ab = r_conv.json()
    assert conv_ab["peer"]["id"] == b["id"]
    assert conv_ab["peer"]["name"] == "Bob Coach"
    assert conv_ab["peer"]["show_activity_status"] is False
    assert "email" not in conv_ab["peer"]
    assert "password_hash" not in conv_ab["peer"]

    # Reverse direction B -> A returns same conversation (upsert by participant_pair_key)
    r_conv_rev = client.post(
        "/api/community/dm/conversations",
        headers=b["headers"],
        json={"target_user_id": a["id"]},
    )
    assert r_conv_rev.status_code == 200
    assert r_conv_rev.json()["id"] == conv_ab["id"]

    # 2-way Block check: C blocks A -> A cannot create conversation with C (403)
    fake_db["community_blocks"].insert_one({"blocker_id": c["id"], "blocked_id": a["id"]})
    r_blocked_create = client.post(
        "/api/community/dm/conversations",
        headers=a["headers"],
        json={"target_user_id": c["id"]},
    )
    assert r_blocked_create.status_code == 403

    # List conversations for A shows A-B
    r_list = client.get("/api/community/dm/conversations", headers=a["headers"])
    assert r_list.status_code == 200
    assert len(r_list.json()["items"]) == 1
    assert r_list.json()["items"][0]["id"] == conv_ab["id"]

    # Now A blocks B -> sending message returns 403 and A-B hidden from inbox list
    fake_db["community_blocks"].insert_one({"blocker_id": a["id"], "blocked_id": b["id"]})
    r_send_blocked = client.post(
        f"/api/community/dm/conversations/{conv_ab['id']}/messages",
        headers=a["headers"],
        json={"type": "text", "content": "Hello while blocked"},
    )
    assert r_send_blocked.status_code == 403

    r_list_after_block = client.get("/api/community/dm/conversations", headers=a["headers"])
    assert r_list_after_block.status_code == 200
    assert r_list_after_block.json()["items"] == []


# ---------------------------------------------------------------------------
# 4. Messages (text, voice, video, post_share), Idempotency, IDOR 404, Read & Delete
# ---------------------------------------------------------------------------


def test_messages_types_idempotency_idor_read_and_sender_delete(dm_env):
    client: TestClient = dm_env["client"]
    fake_db: FakeDatabase = dm_env["db"]
    a, b, c = dm_env["a"], dm_env["b"], dm_env["c"]

    # Seed public & private posts for post_share validation
    public_post_id = str(ObjectId())
    private_post_id = str(ObjectId())
    fake_db["community_posts"].insert_one(
        {
            "_id": ObjectId(public_post_id),
            "author_id": b["id"],
            "author": {"id": b["id"], "name": "Bob Coach"},
            "type": "photo",
            "privacy": "public",
            "caption": "Morning 5K run!",
            "photo_urls": ["/static/community/run.jpg"],
            "is_deleted": False,
            "status": "published",
        }
    )
    fake_db["community_posts"].insert_one(
        {
            "_id": ObjectId(private_post_id),
            "author_id": b["id"],
            "author": {"id": b["id"], "name": "Bob Coach"},
            "type": "text",
            "privacy": "private",
            "caption": "Bob's private diary",
            "is_deleted": False,
            "status": "published",
        }
    )

    conv_id = client.post(
        "/api/community/dm/conversations",
        headers=a["headers"],
        json={"target_user_id": b["id"]},
    ).json()["id"]

    # 1. Text message + Idempotency key replay
    idem_headers = {**a["headers"], "X-Idempotency-Key": "msg-key-001"}
    r_txt1 = client.post(
        f"/api/community/dm/conversations/{conv_id}/messages",
        headers=idem_headers,
        json={"type": "text", "content": "Hey Bob!"},
    )
    assert r_txt1.status_code == 200, r_txt1.text
    msg_txt = r_txt1.json()
    assert msg_txt["type"] == "text"
    assert msg_txt["content"] == "Hey Bob!"

    # Replay same X-Idempotency-Key -> same message ID, no duplicate, no extra unread count
    r_txt_replay = client.post(
        f"/api/community/dm/conversations/{conv_id}/messages",
        headers=idem_headers,
        json={"type": "text", "content": "Hey Bob!"},
    )
    assert r_txt_replay.status_code == 200
    assert r_txt_replay.json()["id"] == msg_txt["id"]
    assert fake_db[COLL_DM_MESSAGES].count_documents({"conversation_id": conv_id}) == 1
    assert client.get("/api/community/dm/unread-count", headers=b["headers"]).json()["unread_count"] == 1

    # 2. Voice message
    r_voice = client.post(
        f"/api/community/dm/conversations/{conv_id}/messages",
        headers=a["headers"],
        json={
            "type": "voice",
            "media_url": "/static/community_dm/sample.m4a",
            "duration_seconds": 12.5,
        },
    )
    assert r_voice.status_code == 200, r_voice.text
    assert r_voice.json()["duration_seconds"] == 12.5

    # 3. Video message
    r_video = client.post(
        f"/api/community/dm/conversations/{conv_id}/messages",
        headers=a["headers"],
        json={
            "type": "video",
            "media_url": "/static/community_dm/sample.mp4",
            "duration_seconds": 25.0,
        },
    )
    assert r_video.status_code == 200, r_video.text

    # 4. post_share (public post succeeds with preview; Bob's private post returns 404 for Alice)
    r_share_private = client.post(
        f"/api/community/dm/conversations/{conv_id}/messages",
        headers=a["headers"],
        json={"type": "post_share", "shared_post_id": private_post_id},
    )
    assert r_share_private.status_code == 404

    r_share_pub = client.post(
        f"/api/community/dm/conversations/{conv_id}/messages",
        headers=a["headers"],
        json={"type": "post_share", "shared_post_id": public_post_id, "content": "Check this out"},
    )
    assert r_share_pub.status_code == 200, r_share_pub.text
    share_body = r_share_pub.json()
    assert share_body["shared_post_preview"]["id"] == public_post_id
    assert share_body["shared_post_preview"]["author_name"] == "Bob Coach"
    assert share_body["shared_post_preview"]["thumbnail_url"] == "/static/community/run.jpg"

    # 5. IDOR protection: User C gets 404 on A-B conversation endpoints
    assert client.get(f"/api/community/dm/conversations/{conv_id}/messages", headers=c["headers"]).status_code == 404
    assert (
        client.post(
            f"/api/community/dm/conversations/{conv_id}/messages",
            headers=c["headers"],
            json={"type": "text", "content": "Intruder"},
        ).status_code
        == 404
    )
    assert client.post(f"/api/community/dm/conversations/{conv_id}/read", headers=c["headers"]).status_code == 404
    assert client.delete(f"/api/community/dm/messages/{msg_txt['id']}", headers=c["headers"]).status_code == 404

    # 6. Unread count & Mark Read
    assert client.get("/api/community/dm/unread-count", headers=b["headers"]).json()["unread_count"] == 4
    r_read = client.post(f"/api/community/dm/conversations/{conv_id}/read", headers=b["headers"])
    assert r_read.status_code == 200
    assert r_read.json()["unread_count"] == 0
    assert client.get("/api/community/dm/unread-count", headers=b["headers"]).json()["unread_count"] == 0

    # 7. Cursor pagination on messages (4 messages, page size 2)
    p1 = client.get(
        f"/api/community/dm/conversations/{conv_id}/messages?limit=2", headers=b["headers"]
    )
    assert p1.status_code == 200
    p1_json = p1.json()
    assert len(p1_json["items"]) == 2
    assert p1_json["next_cursor"] is not None

    p2 = client.get(
        f"/api/community/dm/conversations/{conv_id}/messages?limit=2&cursor={p1_json['next_cursor']}",
        headers=b["headers"],
    )
    assert p2.status_code == 200
    p2_json = p2.json()
    assert len(p2_json["items"]) == 2
    all_ids = [m["id"] for m in p1_json["items"]] + [m["id"] for m in p2_json["items"]]
    assert len(set(all_ids)) == 4

    # 8. Sender-only soft delete
    # Bob tries to delete Alice's message -> 403
    r_del_forbidden = client.delete(
        f"/api/community/dm/messages/{msg_txt['id']}", headers=b["headers"]
    )
    assert r_del_forbidden.status_code == 403

    # Alice deletes own message -> 200, redacted on subsequent read
    r_del_ok = client.delete(
        f"/api/community/dm/messages/{msg_txt['id']}", headers=a["headers"]
    )
    assert r_del_ok.status_code == 200
    assert r_del_ok.json()["is_deleted"] is True

    msgs_after = client.get(
        f"/api/community/dm/conversations/{conv_id}/messages?limit=10", headers=b["headers"]
    ).json()["items"]
    deleted_item = next(m for m in msgs_after if m["id"] == msg_txt["id"])
    assert deleted_item["is_deleted"] is True
    assert deleted_item["content"] == ""


# ---------------------------------------------------------------------------
# 5. WebSocket /api/community/ws/chat (4401 auth, ping/pong, typing, live REST push)
# ---------------------------------------------------------------------------


def test_websocket_auth_reject_4401(dm_env):
    client: TestClient = dm_env["client"]
    a = dm_env["a"]

    # Missing token
    with pytest.raises(WebSocketDisconnect) as exc_missing:
        with client.websocket_connect("/api/community/ws/chat"):
            pass
    assert exc_missing.value.code == 4401

    # Invalid token
    with pytest.raises(WebSocketDisconnect) as exc_invalid:
        with client.websocket_connect("/api/community/ws/chat?token=not-a-valid-jwt"):
            pass
    assert exc_invalid.value.code == 4401

    # Expired token
    expired_token = _make_token(
        a["id"], "alice@saman.test", "Alice Athlete", exp_delta=timedelta(minutes=-5)
    )
    with pytest.raises(WebSocketDisconnect) as exc_expired:
        with client.websocket_connect(f"/api/community/ws/chat?token={expired_token}"):
            pass
    assert exc_expired.value.code == 4401


def test_websocket_ping_pong_typing_and_realtime_rest_events(dm_env):
    client: TestClient = dm_env["client"]
    a, b = dm_env["a"], dm_env["b"]

    conv_id = client.post(
        "/api/community/dm/conversations",
        headers=a["headers"],
        json={"target_user_id": b["id"]},
    ).json()["id"]

    with client.websocket_connect(f"/api/community/ws/chat?token={a['token']}") as ws_a:
        with client.websocket_connect(f"/api/community/ws/chat?token={b['token']}") as ws_b:
            # 1. Ping -> Pong
            ws_a.send_json({"event": "ping"})
            assert ws_a.receive_json() == {"event": "pong"}

            # 2. Typing indicator forwarded from A -> B
            ws_a.send_json({"event": "typing", "conversation_id": conv_id, "is_typing": True})
            typing_evt = ws_b.receive_json()
            assert typing_evt == {
                "event": "typing",
                "conversation_id": conv_id,
                "user_id": a["id"],
                "is_typing": True,
            }

            # 3. REST send message -> real-time message.created pushed to B (and A)
            r_send = client.post(
                f"/api/community/dm/conversations/{conv_id}/messages",
                headers=a["headers"],
                json={"type": "text", "content": "Live hello over WS!"},
            )
            assert r_send.status_code == 200
            sent_msg = r_send.json()

            evt_b = ws_b.receive_json()
            assert evt_b["event"] == "message.created"
            assert evt_b["conversation_id"] == conv_id
            assert evt_b["message"]["id"] == sent_msg["id"]
            assert evt_b["message"]["content"] == "Live hello over WS!"

            evt_a = ws_a.receive_json()
            assert evt_a["event"] == "message.created"
            assert evt_a["message"]["id"] == sent_msg["id"]

            # 4. REST mark read by B -> real-time conversation.read pushed to A
            r_read = client.post(
                f"/api/community/dm/conversations/{conv_id}/read",
                headers=b["headers"],
            )
            assert r_read.status_code == 200
            read_evt_a = ws_a.receive_json()
            assert read_evt_a["event"] == "conversation.read"
            assert read_evt_a["conversation_id"] == conv_id
            assert read_evt_a["reader_id"] == b["id"]
            # Drain B's self-sync read event
            _ = ws_b.receive_json()

            # 5. REST delete message by A -> real-time message.deleted pushed to B
            r_del = client.delete(
                f"/api/community/dm/messages/{sent_msg['id']}",
                headers=a["headers"],
            )
            assert r_del.status_code == 200
            del_evt_b = ws_b.receive_json()
            assert del_evt_b == {
                "event": "message.deleted",
                "conversation_id": conv_id,
                "message_id": sent_msg["id"],
                "deleted_by": a["id"],
            }
