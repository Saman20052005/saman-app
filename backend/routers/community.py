"""
FastAPI Router for Saman Community Remote Read API & Audience Enforcement.
Subsystem: Saman Community (JCOM-05-03).

Invariants:
- Canonical identity extracted strictly from server-side JWT auth.
- Feed and Detail share the exact same audience enforcement policy.
- Private posts are strictly viewable ONLY by the author (owner).
- Deleted (`is_deleted: true`) and unpublished posts are never returned publicly.
- Follower relationship is fail-closed: since follow relations are not yet implemented,
  'following' tab returns an empty list and 'followers_only' posts are hidden from non-authors.
- Zero private data leakage: Public author projections omit all sensitive User document fields
  (email, password, health stats, tokens).
- Attachments only read snapshot embedded in the post with public projection; no author private logs queried.
- Detail ID not found or forbidden returns 404 (preventing private resource existence enumeration).
- Stable cursor pagination with tie-breaker (_id).
"""

import asyncio
import base64
import io
import os
import re
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Union
from fastapi import Request, APIRouter, Depends, Header, HTTPException, Query, File, UploadFile
from starlette.routing import Route
from starlette.responses import FileResponse
from PIL import Image
from bson import ObjectId
import jwt
from pymongo.errors import DuplicateKeyError

from backend.app.database import db
from backend.app.models.community import (
    BlockStatusResponse,
    CreateCommunityCommentRequest,
    CreateReportRequest,
    CreateStoryRequest,
    PublishTextPostRequest,
    PublishQuestionRequest,
    PublishAttachmentPostRequest,
    PublishPhotoPostRequest,
    MediaUploadResponse,
    MuteStatusResponse,
    CommunityBlockedUsersResponse,
    CommunityCommentsResponse,
    CommunityCommentMutationResponse,
    CommunityAuthorModel,
    CommunityAuthorProfileResponse,
    CommunityCommentModel,
    CommunityDiscoverResponse,
    CommunityDraftModel,
    CommunityDraftsResponse,
    CommunityDraftUpsertRequest,
    CommunityFeedResponse,
    CommunityFollowListResponse,
    CommunityNotificationModel,
    CommunityNotificationsResponse,
    CommunityPostModel,
    CommunitySavedResponse,
    CommunitySettingsModel,
    CommunityArchivedStoryModel,
    CommunityStoriesArchiveResponse,
    CommunityStoriesFeedResponse,
    CommunityStoryAuthorGroupModel,
    CommunityStoryModel,
    CommunityTrendingTopicModel,
    CommunityVisualGridItemModel,
    ExerciseThumbnailPreviewModel,
    FollowResponse,
    InteractionLikeResponse,
    InteractionSaveResponse,
    NotificationReadResponse,
    NotificationsReadAllResponse,
    PostNutritionInfoModel,
    PostQaInfoModel,
    PostShareResponse,
    PostWorkoutAttachmentModel,
    QuestionAnswerModel,
    QuestionAnswersResponse,
    CreateQuestionAnswerRequest,
    QuestionAnswerReceipt,
    ReportReceiptResponse,
    StoryViewResponse,
    UpdateCommunityProfileRequest,
    UpdateCommunitySettingsRequest,
)

from backend.app.services.media_storage_service import (
    MediaStorageConfig,
    MediaStorageConfigError,
    MediaStorageUploadError,
    get_media_storage_service,
)
from backend.auth.config import JWT_ALGORITHM, JWT_SECRET

router = APIRouter(prefix="/api/community", tags=["Community"])


def get_community_posts_collection():
    if db is not None:
        return db["community_posts"]
    return None


def get_community_comments_collection():
    return db["community_comments"] if db is not None else None


def get_community_answers_collection():
    if db is not None:
        return db["community_answers"]
    return None


def get_community_interactions_collection():
    if db is not None:
        return db["community_interactions"]
    return None


def get_community_follows_collection():
    if db is not None:
        return db["community_follows"]
    return None


def get_community_notifications_collection():
    if db is not None:
        return db["community_notifications"]
    return None


def get_community_drafts_collection():
    if db is not None:
        return db["community_drafts"]
    return None


def get_users_collection():
    if db is not None:
        return db["users"]
    return None


def _safe_db_collection(name: str):
    if db is None:
        return None
    try:
        return db[name]
    except Exception:
        return None


def get_community_user_settings_collection():
    return _safe_db_collection("community_user_settings")


def get_community_blocks_collection():
    return _safe_db_collection("community_blocks")


def get_community_mutes_collection():
    return _safe_db_collection("community_mutes")


def get_community_reports_collection():
    return _safe_db_collection("community_reports")


def get_community_stories_collection():
    return _safe_db_collection("community_stories")


def get_community_story_views_collection():
    return _safe_db_collection("community_story_views")


def get_community_post_shares_collection():
    return _safe_db_collection("community_post_shares")


_MAX_MUTED_KEYWORDS = 50
_MAX_MUTED_KEYWORD_LENGTH = 40

_DEFAULT_COMMUNITY_SETTINGS: Dict[str, Any] = {
    "is_private_account": False,
    "who_can_dm": "everyone",
    "who_can_comment": "everyone",
    "who_can_reply_story": "everyone",
    "allow_mentions": "everyone",
    "hide_like_counts": False,
    "show_activity_status": True,
    "auto_prompt_share_workout": True,
    "auto_prompt_share_meal": True,
    "muted_keywords": [],
}


def _normalize_muted_keywords(
    raw_keywords: Any,
    *,
    strict: bool = False,
) -> List[str]:
    if not isinstance(raw_keywords, list):
        return []
    cleaned_keywords: List[str] = []
    seen_kw: set[str] = set()
    for raw_kw in raw_keywords:
        if raw_kw is None:
            continue
        kw = str(raw_kw).strip()
        if not kw:
            continue
        if strict and len(kw) > _MAX_MUTED_KEYWORD_LENGTH:
            raise HTTPException(
                status_code=422,
                detail=f"Muted keyword must be at most {_MAX_MUTED_KEYWORD_LENGTH} characters",
            )
        kw_low = kw.lower()
        if kw_low not in seen_kw:
            seen_kw.add(kw_low)
            cleaned_keywords.append(kw_low)
    if strict and len(cleaned_keywords) > _MAX_MUTED_KEYWORDS:
        raise HTTPException(
            status_code=422,
            detail=f"At most {_MAX_MUTED_KEYWORDS} muted keywords are allowed",
        )
    return cleaned_keywords[:_MAX_MUTED_KEYWORDS]


def _post_matches_muted_keywords(doc: Dict[str, Any], muted_keywords_lower: List[str]) -> bool:
    if not muted_keywords_lower:
        return False
    qa_info = doc.get("qa_info") if isinstance(doc.get("qa_info"), dict) else {}
    workout_att = doc.get("workout_attachment") if isinstance(doc.get("workout_attachment"), dict) else {}
    att_snap = doc.get("attachment_snapshot") if isinstance(doc.get("attachment_snapshot"), dict) else {}
    searchable_parts = [
        doc.get("caption"),
        doc.get("content"),
        doc.get("title"),
        qa_info.get("question"),
        qa_info.get("details"),
        workout_att.get("title"),
        att_snap.get("title"),
    ]
    haystack = " ".join(
        str(part) for part in searchable_parts if isinstance(part, str) and part.strip()
    ).lower()
    if not haystack:
        return False
    return any(kw in haystack for kw in muted_keywords_lower)


def _build_settings_model(doc: Optional[Dict[str, Any]]) -> CommunitySettingsModel:
    merged = dict(_DEFAULT_COMMUNITY_SETTINGS)
    if isinstance(doc, dict):
        for key in _DEFAULT_COMMUNITY_SETTINGS:
            if key in doc and doc[key] is not None:
                merged[key] = doc[key]
    merged["muted_keywords"] = _normalize_muted_keywords(merged.get("muted_keywords"), strict=False)
    return CommunitySettingsModel(**merged)


def _get_user_settings_doc(user_id: Optional[str]) -> Dict[str, Any]:
    merged = dict(_DEFAULT_COMMUNITY_SETTINGS)
    if not user_id or user_id == "unknown":
        return merged
    col = get_community_user_settings_collection()
    if col is None:
        return merged
    doc = col.find_one({"user_id": str(user_id)})
    if isinstance(doc, dict):
        for key in _DEFAULT_COMMUNITY_SETTINGS:
            if key in doc and doc[key] is not None:
                merged[key] = doc[key]
    return merged


def _get_user_settings_map(user_ids: List[str]) -> Dict[str, Dict[str, Any]]:
    result: Dict[str, Dict[str, Any]] = {}
    clean_ids = list({str(uid) for uid in user_ids if uid and str(uid) != "unknown"})
    if not clean_ids:
        return result
    col = get_community_user_settings_collection()
    if col is None:
        return result
    for doc in col.find({"user_id": {"$in": clean_ids}}):
        uid = str(doc.get("user_id") or "")
        if not uid:
            continue
        merged = dict(_DEFAULT_COMMUNITY_SETTINGS)
        for key in _DEFAULT_COMMUNITY_SETTINGS:
            if key in doc and doc[key] is not None:
                merged[key] = doc[key]
        result[uid] = merged
    return result


def _get_blocked_user_ids(viewer_id: Optional[str]) -> set[str]:
    """Return 2-way blocked user IDs (both blocked by viewer and blocking viewer)."""
    if not viewer_id:
        return set()
    col = get_community_blocks_collection()
    if col is None:
        return set()
    vid = str(viewer_id)
    blocked: set[str] = set()
    for doc in col.find({"$or": [{"blocker_id": vid}, {"blocked_id": vid}]}):
        blocker_id = str(doc.get("blocker_id") or "")
        blocked_id = str(doc.get("blocked_id") or "")
        if blocker_id == vid and blocked_id:
            blocked.add(blocked_id)
        elif blocked_id == vid and blocker_id:
            blocked.add(blocker_id)
    blocked.discard(vid)
    return blocked


def _is_blocked_between(user_a: Optional[str], user_b: Optional[str]) -> bool:
    if not user_a or not user_b:
        return False
    a = str(user_a)
    b = str(user_b)
    if a == b:
        return False
    col = get_community_blocks_collection()
    if col is None:
        return False
    return bool(
        col.find_one({
            "$or": [
                {"blocker_id": a, "blocked_id": b},
                {"blocker_id": b, "blocked_id": a},
            ]
        })
    )


def _get_muted_user_ids(viewer_id: Optional[str]) -> set[str]:
    """Return 1-way muted user IDs muted by viewer."""
    if not viewer_id:
        return set()
    col = get_community_mutes_collection()
    if col is None:
        return set()
    vid = str(viewer_id)
    muted = {
        str(doc.get("muted_id"))
        for doc in col.find({"muter_id": vid})
        if doc.get("muted_id")
    }
    muted.discard(vid)
    return muted


def _get_excluded_user_ids(viewer_id: Optional[str], include_muted: bool = True) -> set[str]:
    """
    Returns user IDs to exclude for viewer_id:
    - Always includes 2-way blocks (users viewer blocked + users who blocked viewer).
    - Includes 1-way mutes when include_muted=True (for feed/discover/stories).
    """
    if not viewer_id:
        return set()
    excluded = _get_blocked_user_ids(viewer_id)
    if include_muted:
        excluded |= _get_muted_user_ids(viewer_id)
    excluded.discard(str(viewer_id))
    return excluded


def _extract_doc_author_id(doc: Dict[str, Any]) -> str:
    return str(
        doc.get("author_id")
        or doc.get("user_id")
        or (doc.get("author") or {}).get("id")
        or (doc.get("author") or {}).get("_id")
        or ""
    )


def _validate_media_url(raw_url: str, field_label: str = "Media URL") -> str:
    if not isinstance(raw_url, str):
        raise HTTPException(status_code=422, detail=f"{field_label} must be a string")
    url = raw_url.strip()
    if not url:
        raise HTTPException(status_code=422, detail=f"{field_label} must not be empty")
    if url.startswith("/static/community/"):
        remainder = url[len("/static/community/"):]
        if not remainder or "/" in remainder or "\\" in remainder or ".." in remainder:
            raise HTTPException(status_code=422, detail=f"Invalid {field_label}")
    elif url.startswith("http://") or url.startswith("https://"):
        scheme_len = 8 if url.startswith("https://") else 7
        if len(url) <= scheme_len or any(ch.isspace() for ch in url):
            raise HTTPException(status_code=422, detail=f"Invalid HTTP(S) {field_label}")
    else:
        raise HTTPException(
            status_code=422,
            detail=f"{field_label} must start with /static/community/ or http(s)://",
        )
    return url


async def get_required_current_user(
    authorization: Optional[str] = Header(None),
) -> Dict[str, Any]:
    """
    Extracts canonical current_user.
    Raises HTTP 401 if not authenticated.
    """
    if not authorization:
        raise HTTPException(status_code=401, detail="Authentication required")
    user = await get_optional_current_user(authorization)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")
    return user



async def get_optional_current_user(
    authorization: Optional[str] = Header(None),
) -> Optional[Dict[str, Any]]:
    """
    Extracts canonical current_user if Authorization header is present.
    If no Authorization header: returns None (public anonymous viewer).
    If header is present but invalid/expired: raises HTTP 401.
    """
    if not authorization:
        return None

    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(status_code=401, detail="Invalid authorization header format")

    token = parts[1]
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        email = payload.get("email")
        if not email:
            raise HTTPException(status_code=401, detail="Invalid token payload")

        if db is not None:
            user = db["users"].find_one({"email": email})
            if user:
                return user

        # Fallback for mock/test environments
        user_id = payload.get("sub") or payload.get("user_id") or payload.get("id") or email
        return {
            "_id": user_id,
            "email": email,
            "name": payload.get("name", "User"),
        }
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token Expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid Token")


COMMUNITY_STATIC_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "static", "community"
)
os.makedirs(COMMUNITY_STATIC_DIR, exist_ok=True)


def _assert_local_static_serving_allowed() -> None:
    cfg = MediaStorageConfig.from_env()
    if cfg.is_production and not cfg.allow_local_media_storage:
        raise HTTPException(status_code=404, detail="Not found")


async def serve_static_community_file(request):
    _assert_local_static_serving_allowed()
    filename = request.path_params.get("filename", "")
    clean_name = os.path.basename(filename)
    if clean_name != filename or not clean_name:
        raise HTTPException(status_code=404, detail="File not found")
    filepath = os.path.join(COMMUNITY_STATIC_DIR, clean_name)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="File not found")
    ext = os.path.splitext(clean_name)[1].lower()
    media_type = "image/png" if ext == ".png" else ("image/webp" if ext == ".webp" else "image/jpeg")
    return FileResponse(filepath, media_type=media_type)


router.routes.append(Route("/static/community/{filename}", endpoint=serve_static_community_file, methods=["GET"]))


@router.get("/media/{filename}")
async def get_community_media(filename: str):
    _assert_local_static_serving_allowed()
    clean_name = os.path.basename(filename)
    if clean_name != filename or not clean_name:
        raise HTTPException(status_code=404, detail="File not found")
    filepath = os.path.join(COMMUNITY_STATIC_DIR, clean_name)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="File not found")
    ext = os.path.splitext(clean_name)[1].lower()
    media_type = "image/png" if ext == ".png" else ("image/webp" if ext == ".webp" else "image/jpeg")
    return FileResponse(filepath, media_type=media_type)


@router.post("/media/upload", response_model=MediaUploadResponse)
async def upload_community_media(
    file: UploadFile = File(...),
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    MAX_SIZE = 5 * 1024 * 1024
    content_buf = bytearray()
    chunk_size = 64 * 1024

    while True:
        chunk = await file.read(chunk_size)
        if not chunk:
            break
        content_buf.extend(chunk)
        if len(content_buf) > MAX_SIZE:
            raise HTTPException(
                status_code=400,
                detail="Dung lượng ảnh vượt quá giới hạn 5 MB.",
            )

    if len(content_buf) == 0:
        raise HTTPException(status_code=400, detail="File ảnh rỗng.")

    try:
        img = Image.open(io.BytesIO(content_buf))
        img_format = (img.format or "").upper()
        if img_format not in {"JPEG", "PNG", "WEBP"}:
            raise HTTPException(
                status_code=400,
                detail=f"Định dạng ảnh không hợp lệ: {img_format}. Chỉ chấp nhận JPEG, PNG, WEBP.",
            )
        img.verify()
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=400, detail="File không phải định dạng ảnh hợp lệ.")

    ext = "jpg" if img_format == "JPEG" else img_format.lower()
    generated_filename = f"{uuid.uuid4().hex}.{ext}"
    resolved_content_type = file.content_type or ("image/jpeg" if ext == "jpg" else f"image/{ext}")
    content = bytes(content_buf)

    def _upload() -> Any:
        storage = get_media_storage_service()
        return storage.upload_bytes(
            data=content,
            key_prefix="saman/community",
            filename=generated_filename,
            content_type=resolved_content_type,
            local_dir=Path(COMMUNITY_STATIC_DIR),
            local_url_prefix="/static/community",
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

    return MediaUploadResponse(
        media_url=upload_result.url,
        content_type=resolved_content_type,
        file_name=file.filename,
    )


def _find_author_doc(author_id: str) -> Optional[Dict[str, Any]]:
    """
    Looks up author in users_collection or community_posts.
    Returns minimal public profile fields.
    """
    users_col = get_users_collection()
    if users_col is not None:
        filters = [{"_id": author_id}, {"id": author_id}]
        if ObjectId.is_valid(author_id):
            filters.append({"_id": ObjectId(author_id)})
        u = users_col.find_one({"$or": filters})
        if u:
            return {
                "id": str(u.get("_id")),
                "name": u.get("name") or u.get("full_name") or "Saman Athlete",
                "avatar_url": u.get("avatar_url") or u.get("avatar") or u.get("custom_avatar"),
                "title": u.get("title") or "Thành viên Saman",
                "is_verified": bool(u.get("is_verified", False)),
                "handle": u.get("handle"),
                "bio": u.get("bio"),
                "interest_topics": list(u.get("interest_topics") or []),
            }

    posts_col = get_community_posts_collection()
    if posts_col is not None:
        p = posts_col.find_one({
            "$or": [{"author_id": author_id}, {"author.id": author_id}],
            "is_deleted": {"$ne": True},
        })
        if p and p.get("author"):
            a = p["author"]
            return {
                "id": str(a.get("id") or a.get("_id") or author_id),
                "name": a.get("name") or "Saman Athlete",
                "avatar_url": a.get("avatar_url"),
                "title": a.get("title") or "Thành viên Saman",
                "is_verified": bool(a.get("is_verified", False)),
                "handle": a.get("handle"),
                "bio": a.get("bio"),
                "interest_topics": list(a.get("interest_topics") or []),
            }
    return None


def _sanitize_author_projection(
    author_data: Optional[Dict[str, Any]],
    current_user_id: Optional[str] = None,
    is_following: Optional[bool] = None,
    follower_count_override: Optional[int] = None,
) -> CommunityAuthorModel:
    """
    Security barrier: Projects ONLY public profile fields.
    Never exposes email, hashed passwords, health stats, or credentials.
    """
    if not author_data:
        return CommunityAuthorModel(
            id="unknown",
            name="Saman Athlete",
            is_verified=False,
            follower_count=0,
            is_following=False,
        )

    auth_id = str(author_data.get("id") or author_data.get("_id") or "unknown")
    name = str(author_data.get("name") or author_data.get("full_name") or "Saman Athlete")
    avatar = author_data.get("avatar_url") or author_data.get("avatar")
    title = author_data.get("title")
    is_verified = bool(author_data.get("is_verified", False))

    final_is_following = False
    if is_following is not None:
        final_is_following = is_following
    elif current_user_id and auth_id != "unknown" and current_user_id != auth_id:
        follows_col = get_community_follows_collection()
        if follows_col is not None:
            final_is_following = bool(follows_col.find_one({"follower_id": current_user_id, "following_id": auth_id}))

    final_follower_count = int(author_data.get("follower_count", 0))
    if follower_count_override is not None:
        final_follower_count = follower_count_override
    else:
        follows_col = get_community_follows_collection()
        if follows_col is not None and auth_id != "unknown":
            final_follower_count = follows_col.count_documents({"following_id": auth_id})

    return CommunityAuthorModel(
        id=auth_id,
        name=name,
        avatar_url=avatar,
        title=title,
        is_verified=is_verified,
        follower_count=final_follower_count,
        is_following=final_is_following,
    )


def _sanitize_attachment(attachment_doc: Optional[Dict[str, Any]]) -> Optional[PostWorkoutAttachmentModel]:
    if not attachment_doc:
        return None

    # Privacy flags check (default: privacy-first)
    include_duration = attachment_doc.get("include_duration", True)
    include_exercises = attachment_doc.get("include_exercises_or_foods", True)

    exercises_list: List[ExerciseThumbnailPreviewModel] = []
    if include_exercises:
        raw_ex = attachment_doc.get("exercises") or []
        for ex in raw_ex:
            if isinstance(ex, dict) and "title" in ex:
                exercises_list.append(
                    ExerciseThumbnailPreviewModel(
                        title=str(ex.get("title")),
                        image_url=ex.get("image_url"),
                    )
                )

    return PostWorkoutAttachmentModel(
        title=str(attachment_doc.get("title", "Saman Workout")),
        category=str(attachment_doc.get("category", "Saman Kinetic")),
        duration_formatted=str(attachment_doc.get("duration_formatted")) if include_duration and attachment_doc.get("duration_formatted") else None,
        exercise_count=int(attachment_doc.get("exercise_count")) if include_exercises and attachment_doc.get("exercise_count") is not None else None,
        set_count=int(attachment_doc.get("set_count")) if include_exercises and attachment_doc.get("set_count") is not None else None,
        exercises=exercises_list,
    )


def _sanitize_nutrition(nutr_doc: Optional[Dict[str, Any]]) -> Optional[PostNutritionInfoModel]:
    if not nutr_doc:
        return None

    include_macros = nutr_doc.get("include_load_or_macros", True)
    if not include_macros and "include_load_or_macros" in nutr_doc:
        # Privacy enforcement: calories and macros are hidden
        return PostNutritionInfoModel(
            calories=None,
            protein_grams=None,
            carbs_grams=None,
            fat_grams=None,
            badge_label=nutr_doc.get("badge_label"),
            pro_tip=nutr_doc.get("pro_tip"),
        )

    return PostNutritionInfoModel(
        calories=nutr_doc.get("calories"),
        protein_grams=nutr_doc.get("protein_grams"),
        carbs_grams=nutr_doc.get("carbs_grams", 0.0),
        fat_grams=nutr_doc.get("fat_grams", 0.0),
        badge_label=nutr_doc.get("badge_label"),
        pro_tip=nutr_doc.get("pro_tip"),
    )


def _sanitize_qa(qa_doc: Optional[Dict[str, Any]]) -> Optional[PostQaInfoModel]:
    if not qa_doc:
        return None

    return PostQaInfoModel(
        question=str(qa_doc.get("question", "")),
        category_tag=str(qa_doc.get("category_tag", "#HỏiĐáp")),
        details=qa_doc.get("details"),
        respondent_count=int(qa_doc.get("respondent_count", 0)),
        respondents_summary=str(qa_doc.get("respondents_summary", "")),
        respondent_initials=list(qa_doc.get("respondent_initials", [])),
    )


def _sanitize_comments(
    raw_comments: List[Dict[str, Any]],
    current_user_id: Optional[str],
    blocked_ids: Optional[set[str]] = None,
) -> List[CommunityCommentModel]:
    out: List[CommunityCommentModel] = []
    for c in raw_comments:
        if not isinstance(c, dict) or c.get("is_deleted", False):
            continue

        raw_author = c.get("author") or {}
        cmt_author_id = str(raw_author.get("id") or raw_author.get("_id") or c.get("user_id") or "")
        if blocked_ids and cmt_author_id and cmt_author_id in blocked_ids:
            continue

        author = _sanitize_author_projection(raw_author, current_user_id)
        replies_raw = c.get("replies") or []
        replies_sanitized = _sanitize_comments(replies_raw, current_user_id, blocked_ids=blocked_ids)

        out.append(
            CommunityCommentModel(
                id=str(c.get("id") or c.get("_id") or f"cmt_{len(out)}"),
                author=author,
                time_ago=str(c.get("time_ago", "Vừa xong")),
                content=str(c.get("content", "")),
                like_count=int(c.get("like_count", 0)),
                is_liked=bool(c.get("is_liked", False)),
                parent_comment_id=c.get("parent_comment_id"),
                reply_to_author_name=c.get("reply_to_author_name"),
                replies=replies_sanitized,
            )
        )
    return out


def _build_post_model(
    doc: Dict[str, Any],
    current_user_id: Optional[str],
    liked_post_ids: Optional[set[str]] = None,
    saved_post_ids: Optional[set[str]] = None,
    override_like_count: Optional[int] = None,
    followed_author_ids: Optional[set[str]] = None,
    author_follower_counts: Optional[Dict[str, int]] = None,
    override_share_count: Optional[int] = None,
    author_hide_like_counts: Optional[bool] = None,
) -> CommunityPostModel:
    post_id = str(doc.get("id") or doc.get("_id"))
    post_type = str(doc.get("type", "photo"))

    raw_author = doc.get("author") or {}
    author_id = str(raw_author.get("id") or raw_author.get("_id") or doc.get("author_id") or "unknown")
    is_following_author = None
    if followed_author_ids is not None:
        is_following_author = author_id in followed_author_ids
    auth_cnt_override = None
    if author_follower_counts is not None and author_id in author_follower_counts:
        auth_cnt_override = author_follower_counts[author_id]

    author = _sanitize_author_projection(
        raw_author,
        current_user_id,
        is_following=is_following_author,
        follower_count_override=auth_cnt_override,
    )
    time_ago = str(doc.get("time_ago") or "Hôm nay")
    caption = str(doc.get("caption", ""))
    photo_urls = [str(u) for u in doc.get("photo_urls", [])]

    blocked_ids = _get_blocked_user_ids(current_user_id)

    nutrition = _sanitize_nutrition(doc.get("nutrition_info"))
    workout = _sanitize_attachment(doc.get("workout_attachment"))
    qa = _sanitize_qa(doc.get("qa_info"))
    if post_type == "qa" and qa is not None:
        answers_col = get_community_answers_collection()
        if answers_col is not None:
            ans_query: Dict[str, Any] = {"question_id": post_id, "is_deleted": {"$ne": True}}
            if blocked_ids:
                ans_query["user_id"] = {"$nin": list(blocked_ids)}
                ans_query["author.id"] = {"$nin": list(blocked_ids)}
            qa.respondent_count = answers_col.count_documents(ans_query)
            qa.respondents_summary = str(qa.respondent_count)

    # Persistent comments use their own paginated endpoint. No cached counter writes.
    comments_col = get_community_comments_collection()
    comments = _sanitize_comments(doc.get("comments") or [], current_user_id, blocked_ids=blocked_ids)
    legacy_docs = _legacy_comment_docs(doc)
    if blocked_ids:
        legacy_docs = [
            d for d in legacy_docs
            if str(d.get("user_id") or (d.get("author") or {}).get("id") or "") not in blocked_ids
        ]
    if comments_col is not None:
        cmt_query: Dict[str, Any] = {"post_id": post_id}
        if blocked_ids:
            cmt_query["user_id"] = {"$nin": list(blocked_ids)}
            cmt_query["author.id"] = {"$nin": list(blocked_ids)}
        comment_count = comments_col.count_documents(cmt_query) + len(legacy_docs)
    else:
        comment_count = int(doc.get("comment_count", len(comments)))

    # User interactions (bookmarked/liked)
    liked_by_ids = [str(x) for x in (doc.get("liked_by_ids") or [])]
    bookmarked_by_ids = [str(x) for x in (doc.get("bookmarked_by_ids") or [])]

    is_liked = False
    is_bookmarked = False
    if current_user_id:
        if liked_post_ids is not None:
            is_liked = post_id in liked_post_ids or str(doc.get("_id")) in liked_post_ids
        else:
            is_liked = current_user_id in liked_by_ids

        if saved_post_ids is not None:
            is_bookmarked = post_id in saved_post_ids or str(doc.get("_id")) in saved_post_ids
        else:
            is_bookmarked = current_user_id in bookmarked_by_ids

    final_like_count = override_like_count if override_like_count is not None else int(doc.get("like_count", 0))

    # Enforce author's hide_like_counts privacy setting (author always sees own like_count)
    if author_hide_like_counts is None:
        author_settings = _get_user_settings_doc(author_id) if author_id and author_id != "unknown" else None
        hide_likes_setting = bool(author_settings.get("hide_like_counts", False)) if author_settings else False
    else:
        hide_likes_setting = bool(author_hide_like_counts)

    is_viewer_author = bool(current_user_id and author_id and current_user_id == author_id)
    is_like_count_hidden = hide_likes_setting and not is_viewer_author
    if is_like_count_hidden:
        final_like_count = 0

    # Authoritative share_count from community_post_shares
    if override_share_count is not None:
        final_share_count = override_share_count
    else:
        shares_col = get_community_post_shares_collection()
        if shares_col is not None:
            target_pids = list({p for p in [post_id, str(doc.get("id") or ""), str(doc.get("_id") or "")] if p})
            c = shares_col.count_documents({"post_id": {"$in": target_pids}})
            final_share_count = c if c > 0 else int(doc.get("share_count", 0))
        else:
            final_share_count = int(doc.get("share_count", 0))

    from backend.app.services.community_attachment_service import public_snapshot
    return CommunityPostModel(
        id=post_id,
        privacy=doc.get("privacy", "public"),
        topic=doc.get("topic", ""),
        type=post_type,
        author=author,
        time_ago=time_ago,
        caption=caption,
        photo_urls=photo_urls,
        nutrition_info=nutrition,
        workout_attachment=workout,
        qa_info=qa,
        attachment_snapshot=public_snapshot(doc.get("attachment_snapshot")),
        like_count=final_like_count,
        comment_count=comment_count,
        share_count=final_share_count,
        is_like_count_hidden=is_like_count_hidden,
        is_liked=is_liked,
        is_bookmarked=is_bookmarked,
        liked_by_names=list(doc.get("liked_by_names", [])),
        liked_by_summary=str(doc.get("liked_by_summary", "")),
        comments=comments,
    )


# --- CURSOR HELPERS ---
def _encode_cursor(created_at: datetime, obj_id: str) -> str:
    raw = f"{created_at.isoformat()}|{obj_id}"
    return base64.urlsafe_b64encode(raw.encode("utf-8")).decode("utf-8")


def _decode_cursor(cursor_str: str) -> tuple[datetime, str]:
    try:
        raw = base64.urlsafe_b64decode(cursor_str.encode("utf-8")).decode("utf-8")
        parts = raw.split("|")
        if len(parts) != 2:
            raise ValueError("Malformed cursor format")
        dt = datetime.fromisoformat(parts[0])
        return dt, parts[1]
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid pagination cursor")


def _find_post_doc(post_id: str) -> Optional[Dict[str, Any]]:
    col = get_community_posts_collection()
    if col is None:
        return None
    if ObjectId.is_valid(post_id):
        return col.find_one({"$or": [{"_id": ObjectId(post_id)}, {"id": post_id}]})
    return col.find_one({"$or": [{"id": post_id}, {"_id": post_id}]})


def _check_post_audience(doc: Dict[str, Any], current_user_id: Optional[str]) -> None:
    if doc.get("is_deleted", False) or doc.get("status") == "unpublished":
        raise HTTPException(status_code=404, detail="Post not found")
    privacy = doc.get("privacy", "public")
    author_id = str(doc.get("author_id") or (doc.get("author") or {}).get("id") or "")
    if current_user_id and author_id and current_user_id != author_id:
        if _is_blocked_between(current_user_id, author_id):
            raise HTTPException(status_code=404, detail="Post not found")
    if privacy == "private":
        if not current_user_id or current_user_id != author_id:
            raise HTTPException(status_code=404, detail="Post not found")
    elif privacy == "followers_only":
        if not current_user_id:
            raise HTTPException(status_code=404, detail="Post not found")
        if current_user_id != author_id:
            follows_col = get_community_follows_collection()
            is_follower = False
            if follows_col is not None:
                is_follower = bool(follows_col.find_one({"follower_id": current_user_id, "following_id": author_id}))
            if not is_follower:
                raise HTTPException(status_code=404, detail="Post not found")


# --- ENDPOINTS ---

@router.get("/feed", response_model=CommunityFeedResponse)
async def get_community_feed(
    tab: str = Query("for_you", description="Feed tab filter: for_you (all), qa, following"),
    limit: int = Query(20, ge=1, le=50, description="Items per page"),
    cursor: Optional[str] = Query(None, description="Opaque cursor for stable pagination"),
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user),
):
    """
    R03 Community Feed endpoint with server-enforced audience controls.
    """
    norm_tab = tab.lower()
    if norm_tab not in ["for_you", "foryou", "all", "qa", "following"]:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid tab filter: {tab}. Allowed values: for_you, qa, following",
        )

    col = get_community_posts_collection()
    if col is None:
        return CommunityFeedResponse(items=[], next_cursor=None)

    current_user_id = str(current_user["_id"]) if current_user else None
    follows_col = get_community_follows_collection()
    excluded_ids = _get_excluded_user_ids(current_user_id, include_muted=True)

    followed_ids: List[str] = []
    if current_user_id and follows_col is not None:
        followed_ids = [
            str(f["following_id"])
            for f in follows_col.find({"follower_id": current_user_id})
            if str(f["following_id"]) not in excluded_ids
        ]

    if norm_tab == "following":
        if not current_user_id or not followed_ids:
            return CommunityFeedResponse(items=[], next_cursor=None)

    # Base query: non-deleted, published
    query: Dict[str, Any] = {
        "is_deleted": {"$ne": True},
        "status": {"$in": ["published", None]},
    }

    # Audience filter:
    if norm_tab == "following":
        author_filter = {
            "$or": [
                {"author_id": {"$in": followed_ids}},
                {"author.id": {"$in": followed_ids}},
            ]
        }
        privacy_filter = {"privacy": {"$in": ["public", "followers_only", None]}}
        query = {"$and": [query, author_filter, privacy_filter]}
    else:
        if current_user_id:
            audience_conditions = [
                {"privacy": {"$in": ["public", None]}},
                {"author_id": current_user_id},
                {"author.id": current_user_id},
            ]
            if followed_ids:
                audience_conditions.append({
                    "privacy": "followers_only",
                    "$or": [
                        {"author_id": {"$in": followed_ids}},
                        {"author.id": {"$in": followed_ids}},
                    ],
                })
            query["$or"] = audience_conditions
        else:
            query["privacy"] = {"$in": ["public", None]}

    # Tab filter
    if norm_tab == "qa":
        query["type"] = "qa"

    # Block (2-way) & Mute (1-way) filter (only wrap query when non-empty to preserve query shape)
    if excluded_ids:
        excluded_list = list(excluded_ids)
        exclude_filter = {
            "author_id": {"$nin": excluded_list},
            "author.id": {"$nin": excluded_list},
        }
        query = {"$and": [query, exclude_filter]}

    # Cursor filter
    if cursor:
        cursor_dt, cursor_id = _decode_cursor(cursor)
        cursor_filter = {
            "$or": [
                {"created_at": {"$lt": cursor_dt}},
                {
                    "created_at": cursor_dt,
                    "_id": {"$lt": ObjectId(cursor_id) if ObjectId.is_valid(cursor_id) else cursor_id},
                },
            ]
        }
        query = {"$and": [query, cursor_filter]}

    sort_order = [("created_at", -1), ("_id", -1)]

    viewer_muted_keywords: List[str] = []
    if current_user_id:
        viewer_settings = _get_user_settings_doc(current_user_id)
        viewer_muted_keywords = _normalize_muted_keywords(
            viewer_settings.get("muted_keywords"),
            strict=False,
        )

    # Fetch 1 extra to determine next_cursor
    if viewer_muted_keywords:
        docs = []
        for d in col.find(query).sort(sort_order):
            doc_author_id = _extract_doc_author_id(d)
            if excluded_ids and doc_author_id in excluded_ids:
                continue
            if doc_author_id != current_user_id and _post_matches_muted_keywords(d, viewer_muted_keywords):
                continue
            docs.append(d)
            if len(docs) > limit:
                break
    else:
        cursor_res = col.find(query).sort(sort_order).limit(limit + 1)
        docs = list(cursor_res)
        if excluded_ids:
            docs = [d for d in docs if _extract_doc_author_id(d) not in excluded_ids]

    has_more = len(docs) > limit
    results_docs = docs[:limit]

    # Query persistent interactions if authenticated
    liked_post_ids: Optional[set[str]] = None
    saved_post_ids: Optional[set[str]] = None
    if current_user_id:
        interactions_col = get_community_interactions_collection()
        if interactions_col is not None:
            liked_post_ids = set()
            saved_post_ids = set()
            post_id_strs = []
            for d in results_docs:
                if d.get("id"):
                    post_id_strs.append(str(d["id"]))
                if d.get("_id"):
                    post_id_strs.append(str(d["_id"]))

            for inter in interactions_col.find({
                "user_id": current_user_id,
                "post_id": {"$in": post_id_strs},
            }):
                itype = inter.get("interaction_type")
                pid = str(inter.get("post_id"))
                if itype == "like":
                    liked_post_ids.add(pid)
                elif itype == "save":
                    saved_post_ids.add(pid)

    # Authoritative like counts from community_interactions for batch posts:
    authoritative_like_counts: Dict[str, int] = {}
    interactions_col = get_community_interactions_collection()
    if interactions_col is not None and results_docs:
        all_pids = []
        for d in results_docs:
            if d.get("id"):
                all_pids.append(str(d["id"]))
            if d.get("_id"):
                all_pids.append(str(d["_id"]))
        for agg in interactions_col.aggregate([
            {"$match": {"post_id": {"$in": all_pids}, "interaction_type": "like"}},
            {"$group": {"_id": "$post_id", "count": {"$sum": 1}}},
        ]):
            authoritative_like_counts[str(agg["_id"])] = agg["count"]

    # Authoritative follower counts and follow state for batch posts:
    author_ids = []
    for d in results_docs:
        a_id = str(d.get("author_id") or (d.get("author") or {}).get("id") or (d.get("author") or {}).get("_id") or "")
        if a_id:
            author_ids.append(a_id)

    author_follower_counts: Dict[str, int] = {}
    followed_author_set: set[str] = set()
    if follows_col is not None and author_ids:
        for agg in follows_col.aggregate([
            {"$match": {"following_id": {"$in": author_ids}}},
            {"$group": {"_id": "$following_id", "count": {"$sum": 1}}},
        ]):
            author_follower_counts[str(agg["_id"])] = agg["count"]

        if current_user_id:
            for f in follows_col.find({"follower_id": current_user_id, "following_id": {"$in": author_ids}}):
                followed_author_set.add(str(f["following_id"]))

    author_settings_map = _get_user_settings_map(author_ids)

    authoritative_share_counts: Dict[str, int] = {}
    shares_col = get_community_post_shares_collection()
    if shares_col is not None and results_docs:
        all_share_pids: List[str] = []
        for d in results_docs:
            if d.get("id"):
                all_share_pids.append(str(d["id"]))
            if d.get("_id"):
                all_share_pids.append(str(d["_id"]))
        if all_share_pids:
            for agg in shares_col.aggregate([
                {"$match": {"post_id": {"$in": list(set(all_share_pids))}}},
                {"$group": {"_id": "$post_id", "count": {"$sum": 1}}},
            ]):
                authoritative_share_counts[str(agg["_id"])] = int(agg["count"])

    items = []
    for d in results_docs:
        pid = str(d.get("id") or d.get("_id"))
        doc_id = str(d.get("_id")) if d.get("_id") else None
        auth_cnt = None
        if pid in authoritative_like_counts:
            auth_cnt = authoritative_like_counts[pid]
        elif doc_id and doc_id in authoritative_like_counts:
            auth_cnt = authoritative_like_counts[doc_id]
        elif d.get("interaction_version", 0) > 0:
            auth_cnt = 0
        share_cnt = None
        if pid in authoritative_share_counts:
            share_cnt = authoritative_share_counts[pid]
        elif doc_id and doc_id in authoritative_share_counts:
            share_cnt = authoritative_share_counts[doc_id]
        elif shares_col is not None:
            share_cnt = int(d.get("share_count", 0))
        a_id = str(d.get("author_id") or (d.get("author") or {}).get("id") or (d.get("author") or {}).get("_id") or "")
        hide_likes = bool(author_settings_map.get(a_id, _DEFAULT_COMMUNITY_SETTINGS).get("hide_like_counts", False))
        items.append(_build_post_model(
            d,
            current_user_id,
            liked_post_ids,
            saved_post_ids,
            override_like_count=auth_cnt,
            followed_author_ids=followed_author_set if current_user_id else set(),
            author_follower_counts=author_follower_counts,
            override_share_count=share_cnt,
            author_hide_like_counts=hide_likes,
        ))

    next_cursor = None
    if has_more and results_docs:
        last_doc = results_docs[-1]
        c_dt = last_doc.get("created_at") or datetime.now(timezone.utc)
        if isinstance(c_dt, str):
            c_dt = datetime.fromisoformat(c_dt)
        next_cursor = _encode_cursor(c_dt, str(last_doc["_id"]))

    return CommunityFeedResponse(items=items, next_cursor=next_cursor)


@router.get("/posts/{post_id}", response_model=CommunityPostModel)
async def get_post_detail(
    post_id: str,
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user),
):
    """
    R05 Post Detail endpoint with audience enforcement.
    Returns 404 for non-existent, deleted, or forbidden private posts (fail-closed).
    """
    doc = _find_post_doc(post_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Post not found")

    current_user_id = str(current_user["_id"]) if current_user else None
    _check_post_audience(doc, current_user_id)
    canonical_post_id = str(doc.get("id") or doc.get("_id"))

    interactions_col = get_community_interactions_collection()
    liked_post_ids: Optional[set[str]] = None
    saved_post_ids: Optional[set[str]] = None
    auth_like_count = None
    if interactions_col is not None:
        target_pids = [canonical_post_id]
        if doc.get("id"):
            target_pids.append(str(doc["id"]))
        if doc.get("_id"):
            target_pids.append(str(doc["_id"]))
        c = interactions_col.count_documents({
            "post_id": {"$in": list(set(target_pids))},
            "interaction_type": "like",
        })
        if c > 0 or doc.get("interaction_version", 0) > 0:
            auth_like_count = c

        if current_user_id:
            liked_post_ids = set()
            saved_post_ids = set()
            target_ids = [post_id]
            if doc.get("id"):
                target_ids.append(str(doc["id"]))
            if doc.get("_id"):
                target_ids.append(str(doc["_id"]))

            for inter in interactions_col.find({
                "user_id": current_user_id,
                "post_id": {"$in": target_ids},
            }):
                itype = inter.get("interaction_type")
                if itype == "like":
                    liked_post_ids.add(post_id)
                    liked_post_ids.add(str(doc.get("id") or doc.get("_id")))
                elif itype == "save":
                    saved_post_ids.add(post_id)
                    saved_post_ids.add(str(doc.get("id") or doc.get("_id")))

    return _build_post_model(doc, current_user_id, liked_post_ids, saved_post_ids, override_like_count=auth_like_count)


@router.put("/posts/{post_id}/like", response_model=InteractionLikeResponse)
async def like_post(
    post_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    """
    Idempotent Like endpoint with Optimistic Concurrency Control (OCC).
    Inserts unique interaction (user_id, 'like', post_id).
    Updates like_count with interaction_version check to prevent stale overwrites.
    """
    current_user_id = str(current_user["_id"])
    posts_col = get_community_posts_collection()
    interactions_col = get_community_interactions_collection()

    if posts_col is None or interactions_col is None:
        raise HTTPException(status_code=500, detail="Database not configured")

    doc = _find_post_doc(post_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Post not found")

    _check_post_audience(doc, current_user_id)
    canonical_post_id = str(doc.get("id") or doc.get("_id"))

    # 1. Attempt atomic insert
    inserted_new_like = False
    try:
        interactions_col.insert_one({
            "user_id": current_user_id,
            "post_id": canonical_post_id,
            "interaction_type": "like",
            "created_at": datetime.now(timezone.utc),
        })
        inserted_new_like = True
    except DuplicateKeyError:
        pass

    if inserted_new_like:
        post_author_id = str(doc.get("author_id") or (doc.get("author") or {}).get("id") or "")
        snippet = (
            doc.get("caption")
            or (doc.get("qa_info") or {}).get("question")
            or (doc.get("workout_attachment") or {}).get("title")
        )
        _create_notification(
            recipient_id=post_author_id,
            actor_user=current_user,
            notif_type="like",
            action_text="đã thích bài viết của bạn",
            target_snippet=snippet,
            target_post_id=canonical_post_id,
            target_post_type=str(doc.get("type", "photo")),
        )

    # 2. Concurrency-safe OCC loop for updating cached count on community_posts
    MAX_RETRIES = 5
    for _ in range(MAX_RETRIES):
        fresh_doc = _find_post_doc(post_id)
        if not fresh_doc:
            raise HTTPException(status_code=404, detail="Post not found")
        current_version = fresh_doc.get("interaction_version", 0)

        # Authoritative count directly from canonical unique interaction records
        auth_count = interactions_col.count_documents({
            "post_id": canonical_post_id,
            "interaction_type": "like",
        })

        version_query: Dict[str, Any] = {"_id": fresh_doc["_id"]}
        if "interaction_version" in fresh_doc:
            version_query["interaction_version"] = current_version
        else:
            version_query["$or"] = [
                {"interaction_version": {"$exists": False}},
                {"interaction_version": 0},
            ]

        res = posts_col.update_one(
            version_query,
            {
                "$set": {
                    "like_count": auth_count,
                    "interaction_version": current_version + 1,
                },
                "$addToSet": {"liked_by_ids": current_user_id},
            },
        )
        if res.modified_count > 0 or res.matched_count > 0:
            break

    # Final authoritative count directly from interactions collection
    final_count = interactions_col.count_documents({
        "post_id": canonical_post_id,
        "interaction_type": "like",
    })
    return InteractionLikeResponse(
        post_id=canonical_post_id,
        is_liked=True,
        like_count=final_count,
    )


@router.delete("/posts/{post_id}/like", response_model=InteractionLikeResponse)
async def unlike_post(
    post_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    """
    Idempotent Unlike endpoint with Optimistic Concurrency Control (OCC).
    Deletes interaction (user_id, 'like', post_id).
    Derives authoritative like_count directly from community_interactions.
    """
    current_user_id = str(current_user["_id"])
    posts_col = get_community_posts_collection()
    interactions_col = get_community_interactions_collection()

    if posts_col is None or interactions_col is None:
        raise HTTPException(status_code=500, detail="Database not configured")

    doc = _find_post_doc(post_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Post not found")

    _check_post_audience(doc, current_user_id)
    canonical_post_id = str(doc.get("id") or doc.get("_id"))

    # 1. Attempt atomic delete
    interactions_col.delete_one({
        "user_id": current_user_id,
        "post_id": canonical_post_id,
        "interaction_type": "like",
    })

    # 2. Concurrency-safe OCC loop for updating cached count on community_posts
    MAX_RETRIES = 5
    for _ in range(MAX_RETRIES):
        fresh_doc = _find_post_doc(post_id)
        if not fresh_doc:
            raise HTTPException(status_code=404, detail="Post not found")
        current_version = fresh_doc.get("interaction_version", 0)

        # Authoritative count directly from canonical unique interaction records
        auth_count = interactions_col.count_documents({
            "post_id": canonical_post_id,
            "interaction_type": "like",
        })

        version_query: Dict[str, Any] = {"_id": fresh_doc["_id"]}
        if "interaction_version" in fresh_doc:
            version_query["interaction_version"] = current_version
        else:
            version_query["$or"] = [
                {"interaction_version": {"$exists": False}},
                {"interaction_version": 0},
            ]

        res = posts_col.update_one(
            version_query,
            {
                "$set": {
                    "like_count": auth_count,
                    "interaction_version": current_version + 1,
                },
                "$pull": {"liked_by_ids": current_user_id},
            },
        )
        if res.modified_count > 0 or res.matched_count > 0:
            break

    # Final authoritative count directly from interactions collection
    final_count = interactions_col.count_documents({
        "post_id": canonical_post_id,
        "interaction_type": "like",
    })
    return InteractionLikeResponse(
        post_id=canonical_post_id,
        is_liked=False,
        like_count=final_count,
    )


@router.put("/posts/{post_id}/save", response_model=InteractionSaveResponse)
async def save_post(
    post_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    """
    Idempotent Save endpoint.
    Inserts unique interaction (user_id, 'save', post_id).
    """
    current_user_id = str(current_user["_id"])
    posts_col = get_community_posts_collection()
    interactions_col = get_community_interactions_collection()

    if posts_col is None or interactions_col is None:
        raise HTTPException(status_code=500, detail="Database not configured")

    doc = _find_post_doc(post_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Post not found")

    _check_post_audience(doc, current_user_id)
    canonical_post_id = str(doc.get("id") or doc.get("_id"))

    try:
        interactions_col.insert_one({
            "user_id": current_user_id,
            "post_id": canonical_post_id,
            "interaction_type": "save",
            "created_at": datetime.now(timezone.utc),
        })
        posts_col.update_one(
            {"_id": doc["_id"]},
            {"$addToSet": {"bookmarked_by_ids": current_user_id}},
        )
    except DuplicateKeyError:
        pass

    return InteractionSaveResponse(post_id=canonical_post_id, is_saved=True)


@router.delete("/posts/{post_id}/save", response_model=InteractionSaveResponse)
async def unsave_post(
    post_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    """
    Idempotent Unsave endpoint.
    Deletes interaction (user_id, 'save', post_id).
    """
    current_user_id = str(current_user["_id"])
    posts_col = get_community_posts_collection()
    interactions_col = get_community_interactions_collection()

    if posts_col is None or interactions_col is None:
        raise HTTPException(status_code=500, detail="Database not configured")

    doc = _find_post_doc(post_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Post not found")

    _check_post_audience(doc, current_user_id)
    canonical_post_id = str(doc.get("id") or doc.get("_id"))

    interactions_col.delete_one({
        "user_id": current_user_id,
        "post_id": canonical_post_id,
        "interaction_type": "save",
    })
    posts_col.update_one(
        {"_id": doc["_id"]},
        {"$pull": {"bookmarked_by_ids": current_user_id}},
    )

    return InteractionSaveResponse(post_id=canonical_post_id, is_saved=False)


@router.get("/saved", response_model=CommunitySavedResponse)
async def get_saved_posts(
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    """
    R12 Saved Posts endpoint.
    Retrieves saved posts for authenticated user.
    Enforces audience rules at read time: deleted or newly-privatized posts
    (where viewer is not author) are silently filtered out.
    """
    current_user_id = str(current_user["_id"])
    posts_col = get_community_posts_collection()
    interactions_col = get_community_interactions_collection()

    if posts_col is None or interactions_col is None:
        return CommunitySavedResponse(items=[])

    # Find save interactions in reverse chronological order
    saved_interactions = list(
        interactions_col.find({
            "user_id": current_user_id,
            "interaction_type": "save",
        }).sort("created_at", -1)
    )

    if not saved_interactions:
        return CommunitySavedResponse(items=[])

    post_ids = [i["post_id"] for i in saved_interactions]

    # Fetch corresponding posts
    or_clauses = []
    for pid in post_ids:
        if ObjectId.is_valid(pid):
            or_clauses.append({"_id": ObjectId(pid)})
        or_clauses.append({"id": pid})
        or_clauses.append({"_id": pid})

    raw_posts = list(posts_col.find({"$or": or_clauses}))
    posts_by_id = {}
    for p in raw_posts:
        posts_by_id[str(p.get("id") or p.get("_id"))] = p
        posts_by_id[str(p.get("_id"))] = p

    liked_inters = list(
        interactions_col.find({
            "user_id": current_user_id,
            "interaction_type": "like",
            "post_id": {"$in": post_ids},
        })
    )
    liked_set = {str(i["post_id"]) for i in liked_inters}
    saved_set = set(post_ids)

    blocked_ids = _get_blocked_user_ids(current_user_id)
    valid_items: List[CommunityPostModel] = []
    for pid in post_ids:
        p_doc = posts_by_id.get(pid)
        if not p_doc:
            continue

        # Check soft delete & status
        if p_doc.get("is_deleted", False) or p_doc.get("status") == "unpublished":
            continue

        # Check audience & 2-way block at read time
        privacy = p_doc.get("privacy", "public")
        author_id = str(p_doc.get("author_id") or (p_doc.get("author") or {}).get("id"))
        if author_id in blocked_ids:
            continue
        if privacy == "private":
            if current_user_id != author_id:
                continue
        elif privacy == "followers_only":
            if current_user_id != author_id:
                follows_col = get_community_follows_collection()
                is_fol = bool(follows_col.find_one({"follower_id": current_user_id, "following_id": author_id})) if follows_col is not None else False
                if not is_fol:
                    continue

        post_model = _build_post_model(p_doc, current_user_id, liked_set, saved_set)
        valid_items.append(post_model)

    return CommunitySavedResponse(items=valid_items)



def _answer_question(question_id, viewer_id):
    # Reuse the proven canonical ID, publication and current audience boundary.
    post, canonical_id = _comment_post(question_id, viewer_id)
    if post.get("type") != "qa" or post.get("status") != "published":
        raise HTTPException(404, "Question not found")
    return post, canonical_id


def _answer_col():
    col = get_community_answers_collection()
    if col is None:
        raise HTTPException(503, "Answers unavailable")
    return col


def _answer_votes():
    if db is None:
        raise HTTPException(503, "Votes unavailable")
    return db["community_answer_votes"]


def _require_unique(col, keys):
    if not any(i.get("unique") and i.get("key") == keys for i in col.index_information().values()):
        raise HTTPException(503, "Required unique index unavailable")


def _answer_doc(question_id, answer_id):
    col = _answer_col()
    filters = [{"id": answer_id}, {"_id": answer_id}]
    if ObjectId.is_valid(answer_id):
        filters.append({"_id": ObjectId(answer_id)})
    doc = col.find_one({"question_id": question_id, "is_deleted": {"$ne": True}, "$or": filters})
    if not doc:
        raise HTTPException(404, "Answer not found")
    return doc


def _public_answer(doc, viewer_id):
    aid = str(doc.get("id") or doc["_id"])
    votes = _answer_votes()
    dt = doc.get("created_at")
    if isinstance(dt, datetime) and dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return QuestionAnswerModel(
        id=aid, question_id=doc["question_id"], created_at=dt,
        author=_sanitize_author_projection(doc.get("author"), viewer_id),
        content=doc.get("content", ""),
        time_ago=doc.get("time_ago") or (dt.strftime("%d/%m %H:%M UTC") if dt else ""),
        upvote_count=votes.count_documents({"answer_id": aid}),
        is_upvoted=bool(viewer_id and votes.find_one({"answer_id": aid, "user_id": viewer_id})),
        is_pinned_best=bool(doc.get("is_pinned_best", False)),
    )


@router.get("/questions/{question_id}/answers", response_model=QuestionAnswersResponse)
@router.get("/posts/{question_id}/answers", response_model=QuestionAnswersResponse)
def get_question_answers(question_id: str, limit: int = Query(20, ge=1, le=50),
                         cursor: Optional[str] = None,
                         current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user)):
    user = _canonical_comment_user(current_user)
    viewer_id = str(user["_id"]) if user else None
    _, qid = _answer_question(question_id, viewer_id)
    col = _answer_col()
    blocked_ids = _get_blocked_user_ids(viewer_id)
    query: Dict[str, Any] = {"question_id": qid, "is_deleted": {"$ne": True}}
    if blocked_ids:
        blocked_list = list(blocked_ids)
        query["user_id"] = {"$nin": blocked_list}
        query["author.id"] = {"$nin": blocked_list}
    if cursor:
        dt, aid = _decode_cursor(cursor)
        if not ObjectId.is_valid(aid):
            raise HTTPException(400, "Invalid pagination cursor")
        query["$or"] = [{"created_at": {"$gt": dt}}, {"created_at": dt, "_id": {"$gt": ObjectId(aid)}}]
    docs = list(col.find(query).sort([("created_at", 1), ("_id", 1)]).limit(limit + 1))
    if blocked_ids:
        docs = [d for d in docs if _extract_doc_author_id(d) not in blocked_ids]
    more = len(docs) > limit
    docs = docs[:limit]
    items = [_public_answer(d, viewer_id) for d in docs]
    count_query: Dict[str, Any] = {"question_id": qid, "is_deleted": {"$ne": True}}
    if blocked_ids:
        count_query["user_id"] = {"$nin": list(blocked_ids)}
        count_query["author.id"] = {"$nin": list(blocked_ids)}
    count = col.count_documents(count_query)
    _answer_question(question_id, viewer_id)
    return QuestionAnswersResponse(items=items, answer_count=count,
        next_cursor=_encode_cursor(docs[-1]["created_at"], str(docs[-1]["_id"])) if more else None)


@router.post("/questions/{question_id}/answers", response_model=QuestionAnswerReceipt)
def create_question_answer(question_id: str, body: CreateQuestionAnswerRequest,
        idempotency_key: str = Header(..., alias="X-Idempotency-Key", min_length=16, max_length=128, pattern=r"^[A-Za-z0-9_-]+$"),
        current_user: Dict[str, Any] = Depends(get_required_current_user)):
    user = _canonical_comment_user(current_user)
    uid = str(user["_id"])
    question_doc, qid = _answer_question(question_id, uid)
    content = body.content.strip()
    if not content:
        raise HTTPException(422, "Answer must not be blank")
    col = _answer_col()
    _require_unique(col, [("user_id", 1), ("request_key", 1)])
    identity = {"user_id": uid, "request_key": idempotency_key}
    payload = {"question_id": qid, "content": content}
    doc = col.find_one(identity)
    if doc is not None and any(doc.get(k) != v for k, v in payload.items()):
        raise HTTPException(409, "Idempotency key payload conflict")
    inserted_new_answer = False
    if doc is None:
        candidate = dict(identity, **payload, _id=ObjectId(), created_at=datetime.now(timezone.utc),
            author={"id": uid, "name": user.get("name") or user.get("full_name") or "Saman Athlete",
                    "avatar_url": user.get("avatar_url") or user.get("avatar"), "is_verified": bool(user.get("is_verified", False))})
        try:
            col.insert_one(candidate)
            doc = candidate
            inserted_new_answer = True
        except DuplicateKeyError:
            doc = col.find_one(identity)
    if doc is None:
        raise HTTPException(503, "Answer confirmation unavailable")
    if any(doc.get(k) != v for k, v in payload.items()):
        raise HTTPException(409, "Idempotency key payload conflict")
    if doc.get("is_deleted"):
        raise HTTPException(404, "Answer not found")
    if inserted_new_answer:
        question_author_id = str(question_doc.get("author_id") or (question_doc.get("author") or {}).get("id") or "")
        _create_notification(
            recipient_id=question_author_id,
            actor_user=user,
            notif_type="answer",
            action_text="đã trả lời câu hỏi của bạn",
            target_snippet=content,
            target_post_id=qid,
            target_post_type="qa",
        )
    answer = _public_answer(doc, uid)
    count = col.count_documents({"question_id": qid, "is_deleted": {"$ne": True}})
    _answer_question(question_id, uid)
    return QuestionAnswerReceipt(answer=answer, answer_count=count)


@router.get("/questions/{question_id}/answers/{answer_id}", response_model=QuestionAnswerModel)
def get_question_answer(question_id: str, answer_id: str,
        current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user)):
    user = _canonical_comment_user(current_user)
    uid = str(user["_id"]) if user else None
    _, qid = _answer_question(question_id, uid)
    ans_doc = _answer_doc(qid, answer_id)
    ans_author_id = _extract_doc_author_id(ans_doc)
    if uid and ans_author_id and _is_blocked_between(uid, ans_author_id):
        raise HTTPException(404, "Answer not found")
    answer = _public_answer(ans_doc, uid)
    _answer_question(question_id, uid)
    return answer


def _set_helpful(question_id, answer_id, user, desired):
    user = _canonical_comment_user(user)
    uid = str(user["_id"])
    _, qid = _answer_question(question_id, uid)
    doc = _answer_doc(qid, answer_id)
    aid = str(doc.get("id") or doc["_id"])
    if uid == str(doc.get("user_id") or (doc.get("author") or {}).get("id")):
        raise HTTPException(403, "Self voting is not enabled")
    votes = _answer_votes()
    _require_unique(votes, [("user_id", 1), ("answer_id", 1)])
    identity = {"user_id": uid, "answer_id": aid}
    if desired:
        try:
            votes.insert_one(dict(identity, created_at=datetime.now(timezone.utc)))
        except DuplicateKeyError:
            pass  # Desired-state PUT already applied.
    else:
        votes.delete_one(identity)  # Explicit unvote only, never test cleanup.
    answer = _public_answer(doc, uid)
    _answer_question(question_id, uid)
    return answer


@router.put("/questions/{question_id}/answers/{answer_id}/helpful", response_model=QuestionAnswerModel)
def put_answer_helpful(question_id: str, answer_id: str, current_user: Dict[str, Any] = Depends(get_required_current_user)):
    return _set_helpful(question_id, answer_id, current_user, True)


@router.delete("/questions/{question_id}/answers/{answer_id}/helpful", response_model=QuestionAnswerModel)
def delete_answer_helpful(question_id: str, answer_id: str, current_user: Dict[str, Any] = Depends(get_required_current_user)):
    return _set_helpful(question_id, answer_id, current_user, False)


# --- FOLLOW & PROFILE ENDPOINTS (JCOM-05-05) ---

@router.put("/authors/{author_id}/follow", response_model=FollowResponse)
async def follow_author(
    author_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    """
    Idempotent Follow endpoint.
    Follow is a one-way relationship from current_user (follower) to author_id (following).
    Rejects self-follow and non-existent target users.
    Authoritative counts derived from community_follows collection.
    """
    current_user_id = str(current_user["_id"])
    if current_user_id == author_id or author_id == "me":
        raise HTTPException(status_code=400, detail="Cannot follow yourself")

    target_info = _find_author_doc(author_id)
    if not target_info:
        raise HTTPException(status_code=404, detail="Author not found")

    if _is_blocked_between(current_user_id, author_id):
        raise HTTPException(status_code=403, detail="Cannot follow this user due to block")

    follows_col = get_community_follows_collection()
    if follows_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    inserted_new_follow = False
    try:
        follows_col.insert_one({
            "follower_id": current_user_id,
            "following_id": author_id,
            "created_at": datetime.now(timezone.utc),
        })
        inserted_new_follow = True
    except DuplicateKeyError:
        pass  # Idempotent PUT: already following

    if inserted_new_follow:
        _create_notification(
            recipient_id=author_id,
            actor_user=current_user,
            notif_type="follow",
            action_text="đã bắt đầu theo dõi bạn",
        )

    follower_count = follows_col.count_documents({"following_id": author_id})
    following_count = follows_col.count_documents({"follower_id": author_id})

    return FollowResponse(
        author_id=author_id,
        is_following=True,
        follower_count=follower_count,
        following_count=following_count,
    )


@router.delete("/authors/{author_id}/follow", response_model=FollowResponse)
async def unfollow_author(
    author_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    """
    Idempotent Unfollow endpoint.
    Removes follow relation between current_user and author_id.
    Authoritative counts updated immediately.
    """
    current_user_id = str(current_user["_id"])
    if current_user_id == author_id or author_id == "me":
        raise HTTPException(status_code=400, detail="Cannot unfollow yourself")

    target_info = _find_author_doc(author_id)
    if not target_info:
        raise HTTPException(status_code=404, detail="Author not found")

    follows_col = get_community_follows_collection()
    if follows_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    follows_col.delete_one({
        "follower_id": current_user_id,
        "following_id": author_id,
    })

    follower_count = follows_col.count_documents({"following_id": author_id})
    following_count = follows_col.count_documents({"follower_id": author_id})

    return FollowResponse(
        author_id=author_id,
        is_following=False,
        follower_count=follower_count,
        following_count=following_count,
    )


@router.get("/authors/{author_id}", response_model=CommunityAuthorProfileResponse)
async def get_community_author_profile(
    author_id: str,
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user),
):
    """
    R09 Author Profile endpoint.
    Returns minimal public profile projection with authoritative counts.
    Never exposes email, hashed passwords, health stats, or credentials.
    """
    current_user_id = str(current_user["_id"]) if current_user else None
    target_id = current_user_id if author_id == "me" else author_id

    if not target_id:
        raise HTTPException(status_code=401, detail="Authentication required")

    if current_user_id and target_id != current_user_id and _is_blocked_between(current_user_id, target_id):
        raise HTTPException(status_code=404, detail="Author not found")

    return _build_author_profile_response(
        target_id=target_id,
        current_user=current_user,
        allow_fallback_current_user=(author_id == "me"),
    )


@router.get("/authors/{author_id}/followers", response_model=CommunityFollowListResponse)
async def get_author_followers(
    author_id: str,
    limit: int = Query(20, ge=1, le=50, description="Items per page"),
    cursor: Optional[str] = Query(None, description="Opaque cursor for pagination"),
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user),
):
    """
    R10 Followers List endpoint with stable pagination and viewer is_following state.
    """
    current_user_id = str(current_user["_id"]) if current_user else None
    target_id = current_user_id if author_id == "me" else author_id
    if not target_id:
        raise HTTPException(status_code=401, detail="Authentication required")

    target_info = _find_author_doc(target_id)
    if not target_info and target_id != current_user_id:
        raise HTTPException(status_code=404, detail="Author not found")

    if current_user_id and target_id != current_user_id and _is_blocked_between(current_user_id, target_id):
        raise HTTPException(status_code=404, detail="Author not found")

    follows_col = get_community_follows_collection()
    if follows_col is None:
        return CommunityFollowListResponse(items=[], next_cursor=None, total_count=0)

    blocked_ids = _get_blocked_user_ids(current_user_id)
    total_count = follows_col.count_documents({"following_id": target_id})

    query: Dict[str, Any] = {"following_id": target_id}
    if blocked_ids:
        query["follower_id"] = {"$nin": list(blocked_ids)}
        total_count = follows_col.count_documents(query)
    if cursor:
        cursor_dt, cursor_id = _decode_cursor(cursor)
        query["$or"] = [
            {"created_at": {"$lt": cursor_dt}},
            {
                "created_at": cursor_dt,
                "_id": {"$lt": ObjectId(cursor_id) if ObjectId.is_valid(cursor_id) else cursor_id},
            },
        ]

    docs = list(follows_col.find(query).sort([("created_at", -1), ("_id", -1)]).limit(limit + 1))
    has_more = len(docs) > limit
    results = docs[:limit]

    follower_ids = [str(d["follower_id"]) for d in results]

    viewer_following_set = set()
    if current_user_id and follower_ids:
        for f in follows_col.find({"follower_id": current_user_id, "following_id": {"$in": follower_ids}}):
            viewer_following_set.add(str(f["following_id"]))

    items = []
    for d in results:
        fid = str(d["follower_id"])
        u_info = _find_author_doc(fid)
        name = u_info["name"] if u_info else "Saman Athlete"
        avatar = u_info.get("avatar_url") if u_info else None
        title = u_info.get("title") if u_info else "Thành viên Saman"
        is_verified = u_info.get("is_verified", False) if u_info else False
        f_count = follows_col.count_documents({"following_id": fid})
        is_fol = fid in viewer_following_set

        items.append(
            CommunityAuthorModel(
                id=fid,
                name=name,
                avatar_url=avatar,
                title=title,
                is_verified=is_verified,
                follower_count=f_count,
                is_following=is_fol,
            )
        )

    next_cursor = None
    if has_more and results:
        last = results[-1]
        c_dt = last.get("created_at") or datetime.now(timezone.utc)
        if isinstance(c_dt, str):
            c_dt = datetime.fromisoformat(c_dt)
        next_cursor = _encode_cursor(c_dt, str(last["_id"]))

    return CommunityFollowListResponse(items=items, next_cursor=next_cursor, total_count=total_count)


@router.get("/authors/{author_id}/following", response_model=CommunityFollowListResponse)
async def get_author_following(
    author_id: str,
    limit: int = Query(20, ge=1, le=50, description="Items per page"),
    cursor: Optional[str] = Query(None, description="Opaque cursor for pagination"),
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user),
):
    """
    R10 Following List endpoint with stable pagination and viewer is_following state.
    """
    current_user_id = str(current_user["_id"]) if current_user else None
    target_id = current_user_id if author_id == "me" else author_id
    if not target_id:
        raise HTTPException(status_code=401, detail="Authentication required")

    target_info = _find_author_doc(target_id)
    if not target_info and target_id != current_user_id:
        raise HTTPException(status_code=404, detail="Author not found")

    follows_col = get_community_follows_collection()
    if follows_col is None:
        return CommunityFollowListResponse(items=[], next_cursor=None, total_count=0)

    if current_user_id and target_id != current_user_id and _is_blocked_between(current_user_id, target_id):
        raise HTTPException(status_code=404, detail="Author not found")

    blocked_ids = _get_blocked_user_ids(current_user_id)
    total_count = follows_col.count_documents({"follower_id": target_id})

    query: Dict[str, Any] = {"follower_id": target_id}
    if blocked_ids:
        query["following_id"] = {"$nin": list(blocked_ids)}
        total_count = follows_col.count_documents(query)
    if cursor:
        cursor_dt, cursor_id = _decode_cursor(cursor)
        query["$or"] = [
            {"created_at": {"$lt": cursor_dt}},
            {
                "created_at": cursor_dt,
                "_id": {"$lt": ObjectId(cursor_id) if ObjectId.is_valid(cursor_id) else cursor_id},
            },
        ]

    docs = list(follows_col.find(query).sort([("created_at", -1), ("_id", -1)]).limit(limit + 1))
    has_more = len(docs) > limit
    results = docs[:limit]

    following_ids = [str(d["following_id"]) for d in results]

    viewer_following_set = set()
    if current_user_id and following_ids:
        for f in follows_col.find({"follower_id": current_user_id, "following_id": {"$in": following_ids}}):
            viewer_following_set.add(str(f["following_id"]))

    items = []
    for d in results:
        fid = str(d["following_id"])
        u_info = _find_author_doc(fid)
        name = u_info["name"] if u_info else "Saman Athlete"
        avatar = u_info.get("avatar_url") if u_info else None
        title = u_info.get("title") if u_info else "Thành viên Saman"
        is_verified = u_info.get("is_verified", False) if u_info else False
        f_count = follows_col.count_documents({"following_id": fid})
        is_fol = fid in viewer_following_set

        items.append(
            CommunityAuthorModel(
                id=fid,
                name=name,
                avatar_url=avatar,
                title=title,
                is_verified=is_verified,
                follower_count=f_count,
                is_following=is_fol,
            )
        )

    next_cursor = None
    if has_more and results:
        last = results[-1]
        c_dt = last.get("created_at") or datetime.now(timezone.utc)
        if isinstance(c_dt, str):
            c_dt = datetime.fromisoformat(c_dt)
        next_cursor = _encode_cursor(c_dt, str(last["_id"]))

    return CommunityFollowListResponse(items=items, next_cursor=next_cursor, total_count=total_count)


def _legacy_comment_docs(post):
    """Read-only compatibility for already embedded comments; no migration writes."""
    out = []
    for root in post.get("comments") or []:
        if not isinstance(root, dict) or root.get("is_deleted"):
            continue
        root_id = str(root.get("id") or root.get("_id"))
        for raw, parent in [(root, None)] + [(r, root_id) for r in root.get("replies", [])]:
            if not isinstance(raw, dict) or raw.get("is_deleted"):
                continue
            author = raw.get("author") or {}
            out.append(dict(raw, _id=str(raw.get("id") or raw.get("_id")),
                            parent_comment_id=parent, author=author,
                            user_id=str(author.get("id") or author.get("_id") or "unknown"),
                            created_at=datetime(1970, 1, 1, tzinfo=timezone.utc)))
    return out


# JCOM-05-06: one atomic insert is both the comment and durable replay record.
def _comment_post(post_id, user_id):
    doc = _find_post_doc(post_id)
    if not doc:
        raise HTTPException(404, "Post not found")
    _check_post_audience(doc, user_id)
    if doc.get("status") not in (None, "published") or doc.get("privacy", "public") not in ("public", "private", "followers_only"):
        raise HTTPException(404, "Post not found")
    return doc, str(doc.get("id") or doc["_id"])


def _canonical_comment_user(user):
    if user is None:
        return None
    users = get_users_collection()
    uid = str(user["_id"])
    filters = [{"_id": uid}]
    if ObjectId.is_valid(uid):
        filters.append({"_id": ObjectId(uid)})
    canonical = users.find_one({"$or": filters}) if users is not None else None
    if canonical is None:
        raise HTTPException(401, "Authentication required")
    return canonical


def _public_comment(doc, post, viewer_id):
    author_id = str(doc["user_id"])
    created_at = doc["created_at"]
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    return CommunityCommentModel(
        id=str(doc["_id"]),
        author=_sanitize_author_projection(doc["author"], viewer_id),
        content=doc["content"],
        created_at=created_at,
        time_ago=doc.get("time_ago") or created_at.strftime("%d/%m %H:%M UTC"),
        parent_comment_id=doc.get("parent_comment_id"),
        reply_to_author_name=doc.get("reply_to_author_name"),
        is_author_reply=author_id == str(post.get("author_id") or (post.get("author") or {}).get("id")),
    )


def _comments_collection():
    col = get_community_comments_collection()
    if col is None:
        raise HTTPException(503, "Comments unavailable")
    return col


@router.get("/posts/{post_id}/comments", response_model=CommunityCommentsResponse)
def get_post_comments(
    post_id: str,
    limit: int = Query(20, ge=1, le=100),
    cursor: Optional[str] = None,
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user),
):
    current_user = _canonical_comment_user(current_user)
    viewer_id = str(current_user["_id"]) if current_user else None
    post, canonical_id = _comment_post(post_id, viewer_id)
    col = _comments_collection()
    blocked_ids = _get_blocked_user_ids(viewer_id)
    query: Dict[str, Any] = {"post_id": canonical_id}
    if blocked_ids:
        blocked_list = list(blocked_ids)
        query["user_id"] = {"$nin": blocked_list}
        query["author.id"] = {"$nin": blocked_list}
    legacy = _legacy_comment_docs(post)
    if blocked_ids:
        legacy = [d for d in legacy if _extract_doc_author_id(d) not in blocked_ids]
    if cursor:
        dt, cid = _decode_cursor(cursor)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        legacy = [d for d in legacy if (d["created_at"], str(d["_id"])) > (dt, cid)]
        if ObjectId.is_valid(cid):
            query["$or"] = [{"created_at": {"$gt": dt}}, {"created_at": dt, "_id": {"$gt": ObjectId(cid)}}]
        elif dt != datetime(1970, 1, 1, tzinfo=timezone.utc):
            raise HTTPException(400, "Invalid pagination cursor")
    legacy.sort(key=lambda d: (d["created_at"], str(d["_id"])))
    db_docs = list(col.find(query).sort([("created_at", 1), ("_id", 1)]).limit(limit + 1))
    if blocked_ids:
        db_docs = [d for d in db_docs if _extract_doc_author_id(d) not in blocked_ids]
    docs = (legacy + db_docs)[:limit + 1]
    more = len(docs) > limit
    docs = docs[:limit]
    _comment_post(post_id, viewer_id)  # Revalidate before returning nested/public data.
    count_query: Dict[str, Any] = {"post_id": canonical_id}
    all_legacy = _legacy_comment_docs(post)
    if blocked_ids:
        count_query["user_id"] = {"$nin": list(blocked_ids)}
        count_query["author.id"] = {"$nin": list(blocked_ids)}
        all_legacy = [d for d in all_legacy if _extract_doc_author_id(d) not in blocked_ids]
    return CommunityCommentsResponse(
        items=[_public_comment(d, post, viewer_id) for d in docs],
        next_cursor=_encode_cursor(docs[-1]["created_at"], str(docs[-1]["_id"])) if more else None,
        comment_count=col.count_documents(count_query) + len(all_legacy),
    )


@router.post("/posts/{post_id}/comments", response_model=CommunityCommentMutationResponse)
def create_post_comment(
    post_id: str,
    body: CreateCommunityCommentRequest,
    idempotency_key: str = Header(..., alias="X-Idempotency-Key", min_length=16, max_length=128, pattern=r"^[A-Za-z0-9_-]+$"),
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user = _canonical_comment_user(current_user)
    user_id = str(current_user["_id"])
    raw_post = _find_post_doc(post_id)
    if raw_post and not raw_post.get("is_deleted", False) and raw_post.get("status") in (None, "published"):
        raw_author_id = str(raw_post.get("author_id") or (raw_post.get("author") or {}).get("id") or "")
        if raw_author_id and raw_author_id != user_id and _is_blocked_between(user_id, raw_author_id):
            if raw_post.get("privacy", "public") == "private":
                raise HTTPException(404, "Post not found")
            raise HTTPException(403, "Cannot comment on this user's post due to block")
    post, canonical_id = _comment_post(post_id, user_id)
    if post.get("type") == "qa" or not post.get("allow_comments", True):
        raise HTTPException(409, "Comments disabled")
    post_author_id = str(post.get("author_id") or (post.get("author") or {}).get("id") or "")
    if post_author_id and post_author_id != user_id:
        author_settings = _get_user_settings_doc(post_author_id)
        who_can_comment = author_settings.get("who_can_comment", "everyone")
        if who_can_comment == "nobody":
            raise HTTPException(403, "Author does not allow comments")
        if who_can_comment == "followers":
            follows_col = get_community_follows_collection()
            is_follower = bool(
                follows_col is not None
                and follows_col.find_one({"follower_id": user_id, "following_id": post_author_id})
            )
            if not is_follower:
                raise HTTPException(403, "Only followers can comment on this post")
    content = body.content.strip()
    if not content:
        raise HTTPException(422, "Comment must not be blank")
    col = _comments_collection()
    # Fail closed if explicit index setup has not been applied to this database.
    indexes = col.index_information().values()
    if not any(i.get("unique") and i.get("key") == [("user_id", 1), ("request_key", 1)] for i in indexes):
        raise HTTPException(503, "Comment idempotency index unavailable")
    identity = {"user_id": user_id, "request_key": idempotency_key}
    payload = {"post_id": canonical_id, "content": content, "parent_comment_id": body.parent_comment_id}
    existing = col.find_one(identity)
    if existing is not None and any(existing.get(k) != v for k, v in payload.items()):
        raise HTTPException(409, "Idempotency key payload conflict")
    parent = None
    if body.parent_comment_id:
        if ObjectId.is_valid(body.parent_comment_id):
            parent = col.find_one({"_id": ObjectId(body.parent_comment_id), "post_id": canonical_id})
        if parent is None:
            parent = next((d for d in _legacy_comment_docs(post) if str(d["_id"]) == body.parent_comment_id), None)
        if not parent:
            raise HTTPException(404, "Parent comment not found")
        parent_author_id_chk = _extract_doc_author_id(parent)
        if parent_author_id_chk and parent_author_id_chk != user_id and _is_blocked_between(user_id, parent_author_id_chk):
            raise HTTPException(403, "Cannot reply to a blocked user's comment")
        if parent.get("parent_comment_id"):
            raise HTTPException(422, "Only one reply level is supported")
    inserted_new_comment = False
    if existing is None:
        # Public snapshot is built exclusively from canonical server current_user.
        author = {
            "id": user_id,
            "name": current_user.get("name") or current_user.get("full_name") or "Saman Athlete",
            "avatar_url": current_user.get("avatar_url") or current_user.get("avatar"),
            "is_verified": bool(current_user.get("is_verified", False)),
        }
        candidate = dict(identity, **payload, _id=ObjectId(), author=author,
                         created_at=datetime.now(timezone.utc),
                         reply_to_author_name=_sanitize_author_projection(parent["author"], user_id).name if parent else None)
        try:
            col.insert_one(candidate)
            existing = candidate
            inserted_new_comment = True
        except DuplicateKeyError:
            existing = col.find_one(identity)
    if existing is None:
        raise HTTPException(503, "Comment confirmation unavailable")
    if any(existing.get(k) != v for k, v in payload.items()):
        raise HTTPException(409, "Idempotency key payload conflict")
    if inserted_new_comment:
        post_author_id = str(post.get("author_id") or (post.get("author") or {}).get("id") or "")
        post_type = str(post.get("type", "photo"))
        _create_notification(
            recipient_id=post_author_id,
            actor_user=current_user,
            notif_type="comment",
            action_text="đã bình luận về bài viết của bạn",
            target_snippet=content,
            target_post_id=canonical_id,
            target_post_type=post_type,
        )
        if parent is not None:
            parent_author_id = str(parent.get("user_id") or (parent.get("author") or {}).get("id") or "")
            if parent_author_id and parent_author_id != user_id and parent_author_id != post_author_id:
                _create_notification(
                    recipient_id=parent_author_id,
                    actor_user=current_user,
                    notif_type="comment",
                    action_text="đã trả lời bình luận của bạn",
                    target_snippet=content,
                    target_post_id=canonical_id,
                    target_post_type=post_type,
                )
    _comment_post(post_id, user_id)
    return CommunityCommentMutationResponse(
        comment=_public_comment(existing, post, user_id),
        comment_count=col.count_documents({"post_id": canonical_id}) + len(_legacy_comment_docs(post)),
    )


@router.get("/attachment-sources/{kind}")
def list_attachment_sources(kind: str, current_user: Dict[str, Any] = Depends(get_required_current_user)):
    from backend.app.services.community_attachment_service import recent
    user = _canonical_comment_user(current_user)
    return {"items": recent(db, user, kind)}


@router.get("/attachment-sources/{kind}/{source_id}")
def preview_attachment_source(request: Request, kind: str, source_id: str,
        include_duration: bool = True, include_exercises_or_foods: bool = True, include_load_or_macros: bool = False,
        current_user: Dict[str, Any] = Depends(get_required_current_user)):
    from backend.app.services.community_attachment_service import preview
    if set(request.query_params) - {"include_duration", "include_exercises_or_foods", "include_load_or_macros"}:
        raise HTTPException(422, "Unsupported attachment field selection")
    user = _canonical_comment_user(current_user)
    return preview(db, user, kind, source_id, include_duration, include_exercises_or_foods, include_load_or_macros)


def _published_receipt_post(doc, uid):
    current, _ = _comment_post(str(doc.get("id") or doc["_id"]), uid)
    if current.get("status") != "published":
        raise HTTPException(404, "Post not found")
    return current


@router.post("/posts", response_model=CommunityPostModel)
def publish_community_post(body: Union[PublishTextPostRequest, PublishQuestionRequest, PublishAttachmentPostRequest, PublishPhotoPostRequest],
        idempotency_key: str = Header(..., alias="X-Idempotency-Key", min_length=16, max_length=128, pattern=r"^[A-Za-z0-9_-]+$"),
        current_user: Dict[str, Any] = Depends(get_required_current_user)):
    user = _canonical_comment_user(current_user)
    uid = str(user["_id"])
    question = isinstance(body, PublishQuestionRequest)
    is_photo = isinstance(body, PublishPhotoPostRequest)
    content = (body.title if question else body.content).strip()
    if not content and not isinstance(body, PublishAttachmentPostRequest) and not is_photo:
        raise HTTPException(422, "Post content must not be blank")
    payload = dict(body.model_dump(), **({"title": content, "body": body.body.strip()} if question else {"content": content}))
    posts = get_community_posts_collection()
    if posts is None:
        raise HTTPException(503, "Publishing unavailable")
    _require_unique(posts, [("user_id", 1), ("request_key", 1)])
    identity = {"user_id": uid, "request_key": idempotency_key}
    doc = posts.find_one(identity)
    if doc is not None:
        # Resolve through current audience/publication rules before exposing even a conflict.
        _published_receipt_post(doc, uid)
        if doc.get("status") != "published":
            raise HTTPException(404, "Post not found")
        if doc.get("publication_payload") != payload:
            raise HTTPException(409, "Idempotency key payload conflict")
    else:
        snapshot = None
        if isinstance(body, PublishAttachmentPostRequest):
            from backend.app.services.community_attachment_service import preview
            choice = body.attachment
            current = preview(db, user, body.type, choice.source_id, choice.include_duration,
                choice.include_exercises_or_foods, choice.include_load_or_macros)
            if current["preview_hash"] != choice.preview_hash:
                raise HTTPException(409, "Attachment changed; review the preview before publishing")
            snapshot = current["snapshot"]
        candidate = dict(identity, _id=ObjectId(), publication_payload=payload,
            author_id=uid, author={"id": uid, "name": user.get("name") or user.get("full_name") or "Saman Athlete",
                "avatar_url": user.get("avatar_url") or user.get("avatar"), "is_verified": bool(user.get("is_verified", False))},
            type=body.type, caption="" if question else content, topic=body.topic, privacy=body.privacy,
            allow_comments=True if question else body.allow_comments, status="published", created_at=datetime.now(timezone.utc))
        if snapshot is not None: candidate["attachment_snapshot"] = snapshot
        if is_photo: candidate["photo_urls"] = list(body.photo_urls)
        if question:
            candidate["qa_info"] = {"question": content, "details": payload["body"],
                "category_tag": "HỎI ĐÁP • " + body.topic.upper(), "respondent_count": 0}
        try:
            posts.insert_one(candidate)
            doc = candidate
        except DuplicateKeyError:
            doc = posts.find_one(identity)
    if doc is None:
        raise HTTPException(503, "Publication confirmation unavailable")
    _published_receipt_post(doc, uid)
    if doc.get("status") != "published":
        raise HTTPException(404, "Post not found")
    if doc.get("publication_payload") != payload:
        raise HTTPException(409, "Idempotency key payload conflict")
    result = _build_post_model(doc, uid)
    _published_receipt_post(doc, uid)
    return result


@router.delete("/posts/{post_id}")
def delete_community_post(
    post_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    """
    Deletes a community post with ownership enforcement.
    Requires that the authenticated user is the post's author.
    Soft-deletes the record in MongoDB (is_deleted: True, deleted_at).
    Returns HTTP 403 Forbidden if current_user is not the author.
    Returns HTTP 404 Not Found if post does not exist or is already deleted.
    """
    try:
        user = _canonical_comment_user(current_user)
    except HTTPException:
        user = current_user
    uid = str((user or current_user)["_id"])

    posts_col = get_community_posts_collection()
    if posts_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    doc = _find_post_doc(post_id)
    if not doc or doc.get("is_deleted", False):
        raise HTTPException(status_code=404, detail="community_post_not_found")

    post_author_id = str(doc.get("author_id") or (doc.get("author") or {}).get("id") or "")
    if post_author_id != uid:
        raise HTTPException(
            status_code=403,
            detail="community_delete_forbidden_not_author",
        )

    posts_col.update_one(
        {"_id": doc["_id"]},
        {"$set": {"is_deleted": True, "deleted_at": datetime.now(timezone.utc)}},
    )
    return {"success": True, "post_id": post_id}


# --- WAVE 2: NOTIFICATIONS, DRAFTS, AUTHOR POSTS & PROFILE ---

_HANDLE_RE = re.compile(r"^[a-z0-9._]{1,32}$")


def _format_time_ago(dt: Optional[datetime]) -> str:
    if not dt:
        return "Vừa xong"
    if isinstance(dt, str):
        try:
            dt = datetime.fromisoformat(dt)
        except ValueError:
            return "Vừa xong"
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    diff_seconds = max(0, int((now - dt).total_seconds()))
    if diff_seconds < 60:
        return "Vừa xong"
    minutes = diff_seconds // 60
    if minutes < 60:
        return f"{minutes} phút trước"
    hours = minutes // 60
    if hours < 24:
        return f"{hours} giờ trước"
    days = hours // 24
    if days < 7:
        return f"{days} ngày trước"
    return dt.strftime("%d/%m/%Y")


def _extract_actor_summary(actor_user: Optional[Dict[str, Any]]) -> tuple[Optional[str], str, Optional[str]]:
    if not actor_user:
        return None, "Saman", None
    actor_id = str(actor_user.get("_id") or actor_user.get("id") or "") or None
    actor_name = str(actor_user.get("name") or actor_user.get("full_name") or "Saman Athlete")
    actor_avatar = actor_user.get("avatar_url") or actor_user.get("avatar") or actor_user.get("custom_avatar")
    return actor_id, actor_name, actor_avatar


def _create_notification(
    recipient_id: Optional[str],
    actor_user: Optional[Dict[str, Any]],
    notif_type: str,
    action_text: str,
    target_snippet: Optional[str] = None,
    target_post_id: Optional[str] = None,
    target_post_type: Optional[str] = None,
) -> Optional[Dict[str, Any]]:
    if not recipient_id:
        return None
    recipient_id_str = str(recipient_id).strip()
    if not recipient_id_str or recipient_id_str == "unknown":
        return None

    actor_id, actor_name, actor_avatar = _extract_actor_summary(actor_user)
    if actor_id and actor_id == recipient_id_str:
        return None

    col = get_community_notifications_collection()
    if col is None:
        return None

    if actor_id and (not actor_avatar or actor_name in ("User", "Saman Athlete")):
        author_info = _find_author_doc(actor_id)
        if author_info:
            if author_info.get("name"):
                actor_name = author_info["name"]
            if author_info.get("avatar_url"):
                actor_avatar = author_info["avatar_url"]

    snippet = None
    if target_snippet:
        cleaned = str(target_snippet).strip()
        if cleaned:
            snippet = cleaned[:140]

    now = datetime.now(timezone.utc)
    doc = {
        "_id": ObjectId(),
        "recipient_id": recipient_id_str,
        "actor_id": actor_id,
        "actor_name": actor_name,
        "actor_avatar_url": actor_avatar,
        "action_text": action_text,
        "target_snippet": snippet,
        "type": notif_type,
        "target_post_id": str(target_post_id) if target_post_id else None,
        "target_post_type": target_post_type,
        "is_read": False,
        "created_at": now,
    }
    try:
        col.insert_one(doc)
        return doc
    except Exception:
        return None


def _build_notification_model(doc: Dict[str, Any]) -> CommunityNotificationModel:
    dt = doc.get("created_at")
    if isinstance(dt, str):
        try:
            dt = datetime.fromisoformat(dt)
        except ValueError:
            dt = None
    if isinstance(dt, datetime) and dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    is_read = doc["is_read"] if "is_read" in doc else (not doc.get("is_unread", True))
    return CommunityNotificationModel(
        id=str(doc.get("id") or doc.get("_id")),
        actor_id=str(doc["actor_id"]) if doc.get("actor_id") else None,
        actor_name=str(doc.get("actor_name") or "Saman"),
        actor_avatar_url=doc.get("actor_avatar_url"),
        action_text=str(doc.get("action_text") or ""),
        target_snippet=doc.get("target_snippet"),
        time_ago=doc.get("time_ago") or _format_time_ago(dt),
        created_at=dt,
        is_unread=not bool(is_read),
        type=doc.get("type", "system"),
        target_post_id=str(doc["target_post_id"]) if doc.get("target_post_id") else None,
        target_post_type=doc.get("target_post_type"),
    )


def _is_author_post(doc: Dict[str, Any], target_id: str) -> bool:
    if doc.get("is_deleted", False):
        return False
    if doc.get("status") not in (None, "published"):
        return False
    doc_author_id = str(doc.get("author_id") or (doc.get("author") or {}).get("id") or "")
    return doc_author_id == target_id


def _is_workout_post(doc: Dict[str, Any]) -> bool:
    if doc.get("type") == "workout":
        return True
    if doc.get("workout_attachment"):
        return True
    snap = doc.get("attachment_snapshot")
    if isinstance(snap, dict) and snap.get("kind") == "workout":
        return True
    return False


def _is_meal_post(doc: Dict[str, Any]) -> bool:
    if doc.get("type") == "meal":
        return True
    if doc.get("nutrition_info"):
        return True
    snap = doc.get("attachment_snapshot")
    if isinstance(snap, dict) and snap.get("kind") == "meal":
        return True
    return False


def _build_author_profile_response(
    target_id: str,
    current_user: Optional[Dict[str, Any]],
    allow_fallback_current_user: bool = False,
) -> CommunityAuthorProfileResponse:
    current_user_id = str(current_user["_id"]) if current_user else None
    author_info = _find_author_doc(target_id)
    if not author_info:
        if allow_fallback_current_user and current_user:
            author_info = {
                "id": current_user_id,
                "name": current_user.get("name") or current_user.get("full_name") or "Saman Athlete",
                "avatar_url": current_user.get("avatar_url") or current_user.get("avatar") or current_user.get("custom_avatar"),
                "title": current_user.get("title") or "Thành viên Saman",
                "is_verified": bool(current_user.get("is_verified", False)),
                "handle": current_user.get("handle"),
                "bio": current_user.get("bio"),
                "interest_topics": list(current_user.get("interest_topics") or []),
            }
        else:
            raise HTTPException(status_code=404, detail="Author not found")

    follows_col = get_community_follows_collection()
    posts_col = get_community_posts_collection()
    interactions_col = get_community_interactions_collection()

    follower_count = 0
    following_count = 0
    post_count = 0
    workout_post_count = 0
    meal_post_count = 0
    total_likes_received = 0
    is_following = False

    if follows_col is not None:
        follower_count = follows_col.count_documents({"following_id": target_id})
        following_count = follows_col.count_documents({"follower_id": target_id})
        if current_user_id and current_user_id != target_id:
            is_following = bool(follows_col.find_one({"follower_id": current_user_id, "following_id": target_id}))

    if posts_col is not None:
        raw_posts = list(
            posts_col.find({
                "$or": [{"author_id": target_id}, {"author.id": target_id}],
                "is_deleted": {"$ne": True},
                "status": {"$in": ["published", None]},
            })
        )
        author_posts = [p for p in raw_posts if _is_author_post(p, target_id)]
        post_count = len(author_posts)
        workout_post_count = sum(1 for p in author_posts if _is_workout_post(p))
        meal_post_count = sum(1 for p in author_posts if _is_meal_post(p))

        if interactions_col is not None and author_posts:
            post_id_set: set[str] = set()
            for p in author_posts:
                if p.get("id"):
                    post_id_set.add(str(p["id"]))
                if p.get("_id"):
                    post_id_set.add(str(p["_id"]))
            if post_id_set:
                total_likes_received = interactions_col.count_documents({
                    "post_id": {"$in": list(post_id_set)},
                    "interaction_type": "like",
                })

    return CommunityAuthorProfileResponse(
        id=target_id,
        name=author_info["name"],
        avatar_url=author_info.get("avatar_url"),
        title=author_info.get("title"),
        is_verified=author_info.get("is_verified", False),
        follower_count=follower_count,
        following_count=following_count,
        post_count=post_count,
        is_following=is_following,
        handle=author_info.get("handle"),
        bio=author_info.get("bio"),
        interest_topics=list(author_info.get("interest_topics") or []),
        workout_post_count=workout_post_count,
        meal_post_count=meal_post_count,
        total_likes_received=total_likes_received,
    )


def _hydrate_post_docs(
    results_docs: List[Dict[str, Any]],
    current_user_id: Optional[str],
) -> List[CommunityPostModel]:
    liked_post_ids: Optional[set[str]] = None
    saved_post_ids: Optional[set[str]] = None
    interactions_col = get_community_interactions_collection()
    follows_col = get_community_follows_collection()

    if current_user_id and interactions_col is not None and results_docs:
        liked_post_ids = set()
        saved_post_ids = set()
        post_id_strs: List[str] = []
        for d in results_docs:
            if d.get("id"):
                post_id_strs.append(str(d["id"]))
            if d.get("_id"):
                post_id_strs.append(str(d["_id"]))
        for inter in interactions_col.find({
            "user_id": current_user_id,
            "post_id": {"$in": post_id_strs},
        }):
            itype = inter.get("interaction_type")
            pid = str(inter.get("post_id"))
            if itype == "like":
                liked_post_ids.add(pid)
            elif itype == "save":
                saved_post_ids.add(pid)

    authoritative_like_counts: Dict[str, int] = {}
    if interactions_col is not None and results_docs:
        all_pids: List[str] = []
        for d in results_docs:
            if d.get("id"):
                all_pids.append(str(d["id"]))
            if d.get("_id"):
                all_pids.append(str(d["_id"]))
        for agg in interactions_col.aggregate([
            {"$match": {"post_id": {"$in": all_pids}, "interaction_type": "like"}},
            {"$group": {"_id": "$post_id", "count": {"$sum": 1}}},
        ]):
            authoritative_like_counts[str(agg["_id"])] = agg["count"]

    author_ids: List[str] = []
    for d in results_docs:
        a_id = str(d.get("author_id") or (d.get("author") or {}).get("id") or (d.get("author") or {}).get("_id") or "")
        if a_id:
            author_ids.append(a_id)

    author_follower_counts: Dict[str, int] = {}
    followed_author_set: set[str] = set()
    if follows_col is not None and author_ids:
        for agg in follows_col.aggregate([
            {"$match": {"following_id": {"$in": author_ids}}},
            {"$group": {"_id": "$following_id", "count": {"$sum": 1}}},
        ]):
            author_follower_counts[str(agg["_id"])] = agg["count"]
        if current_user_id:
            for f in follows_col.find({"follower_id": current_user_id, "following_id": {"$in": author_ids}}):
                followed_author_set.add(str(f["following_id"]))

    author_settings_map = _get_user_settings_map(author_ids)

    authoritative_share_counts: Dict[str, int] = {}
    shares_col = get_community_post_shares_collection()
    if shares_col is not None and results_docs:
        all_share_pids: List[str] = []
        for d in results_docs:
            if d.get("id"):
                all_share_pids.append(str(d["id"]))
            if d.get("_id"):
                all_share_pids.append(str(d["_id"]))
        if all_share_pids:
            for agg in shares_col.aggregate([
                {"$match": {"post_id": {"$in": list(set(all_share_pids))}}},
                {"$group": {"_id": "$post_id", "count": {"$sum": 1}}},
            ]):
                authoritative_share_counts[str(agg["_id"])] = int(agg["count"])

    items: List[CommunityPostModel] = []
    for d in results_docs:
        pid = str(d.get("id") or d.get("_id"))
        doc_id = str(d.get("_id")) if d.get("_id") else None
        auth_cnt = None
        if pid in authoritative_like_counts:
            auth_cnt = authoritative_like_counts[pid]
        elif doc_id and doc_id in authoritative_like_counts:
            auth_cnt = authoritative_like_counts[doc_id]
        elif d.get("interaction_version", 0) > 0:
            auth_cnt = 0
        share_cnt = None
        if pid in authoritative_share_counts:
            share_cnt = authoritative_share_counts[pid]
        elif doc_id and doc_id in authoritative_share_counts:
            share_cnt = authoritative_share_counts[doc_id]
        elif shares_col is not None:
            share_cnt = int(d.get("share_count", 0))
        a_id = str(d.get("author_id") or (d.get("author") or {}).get("id") or (d.get("author") or {}).get("_id") or "")
        hide_likes = bool(author_settings_map.get(a_id, _DEFAULT_COMMUNITY_SETTINGS).get("hide_like_counts", False))
        items.append(_build_post_model(
            d,
            current_user_id,
            liked_post_ids,
            saved_post_ids,
            override_like_count=auth_cnt,
            followed_author_ids=followed_author_set if current_user_id else set(),
            author_follower_counts=author_follower_counts,
            override_share_count=share_cnt,
            author_hide_like_counts=hide_likes,
        ))
    return items


@router.get("/notifications", response_model=CommunityNotificationsResponse)
async def get_community_notifications(
    filter: str = Query("all", description="Notification filter: all, interactions, system"),
    limit: int = Query(20, ge=1, le=50, description="Items per page"),
    cursor: Optional[str] = Query(None, description="Opaque cursor for pagination"),
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    norm_filter = filter.lower()
    if norm_filter not in ("all", "interactions", "system"):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid notification filter: {filter}. Allowed values: all, interactions, system",
        )

    current_user_id = str(current_user["_id"])
    col = get_community_notifications_collection()
    if col is None:
        return CommunityNotificationsResponse(items=[], unread_count=0, next_cursor=None)

    unread_count = col.count_documents({"recipient_id": current_user_id, "is_read": False})

    query: Dict[str, Any] = {"recipient_id": current_user_id}
    if norm_filter == "interactions":
        query["type"] = {"$in": ["like", "comment", "follow", "answer"]}
    elif norm_filter == "system":
        query["type"] = "system"

    if cursor:
        cursor_dt, cursor_id = _decode_cursor(cursor)
        cursor_filter = {
            "$or": [
                {"created_at": {"$lt": cursor_dt}},
                {
                    "created_at": cursor_dt,
                    "_id": {"$lt": ObjectId(cursor_id) if ObjectId.is_valid(cursor_id) else cursor_id},
                },
            ]
        }
        query = {"$and": [query, cursor_filter]}

    docs = list(col.find(query).sort([("created_at", -1), ("_id", -1)]).limit(limit + 1))
    has_more = len(docs) > limit
    results = docs[:limit]

    next_cursor = None
    if has_more and results:
        last_doc = results[-1]
        c_dt = last_doc.get("created_at") or datetime.now(timezone.utc)
        if isinstance(c_dt, str):
            c_dt = datetime.fromisoformat(c_dt)
        next_cursor = _encode_cursor(c_dt, str(last_doc.get("_id") or last_doc.get("id")))

    return CommunityNotificationsResponse(
        items=[_build_notification_model(d) for d in results],
        unread_count=unread_count,
        next_cursor=next_cursor,
    )


@router.patch("/notifications/{notification_id}/read", response_model=NotificationReadResponse)
async def mark_notification_read(
    notification_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])
    col = get_community_notifications_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    id_filters: List[Dict[str, Any]] = [{"id": notification_id}, {"_id": notification_id}]
    if ObjectId.is_valid(notification_id):
        id_filters.append({"_id": ObjectId(notification_id)})

    doc = col.find_one({"recipient_id": current_user_id, "$or": id_filters})
    if not doc:
        raise HTTPException(status_code=404, detail="Notification not found")

    col.update_one(
        {"_id": doc["_id"], "recipient_id": current_user_id},
        {"$set": {"is_read": True, "read_at": datetime.now(timezone.utc)}},
    )
    unread_count = col.count_documents({"recipient_id": current_user_id, "is_read": False})
    return NotificationReadResponse(
        id=str(doc.get("id") or doc["_id"]),
        is_unread=False,
        unread_count=unread_count,
    )


@router.post("/notifications/read-all", response_model=NotificationsReadAllResponse)
async def mark_all_notifications_read(
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])
    col = get_community_notifications_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    col.update_many(
        {"recipient_id": current_user_id, "is_read": False},
        {"$set": {"is_read": True, "read_at": datetime.now(timezone.utc)}},
    )
    unread_count = col.count_documents({"recipient_id": current_user_id, "is_read": False})
    return NotificationsReadAllResponse(unread_count=unread_count)


def _build_draft_model(doc: Dict[str, Any]) -> CommunityDraftModel:
    updated_at = doc.get("updated_at") or datetime.now(timezone.utc)
    if isinstance(updated_at, str):
        updated_at = datetime.fromisoformat(updated_at)
    if isinstance(updated_at, datetime) and updated_at.tzinfo is None:
        updated_at = updated_at.replace(tzinfo=timezone.utc)
    return CommunityDraftModel(
        id=str(doc.get("id") or doc["_id"]),
        user_id=str(doc["user_id"]),
        caption=str(doc.get("caption", "")),
        media_urls=[str(u) for u in (doc.get("media_urls") or [])],
        aspect_ratio=str(doc.get("aspect_ratio", "1:1")),
        rotation=int(doc.get("rotation", 0)),
        brightness=float(doc.get("brightness", 0.0)),
        contrast=float(doc.get("contrast", 0.0)),
        audience=str(doc.get("audience", "Công khai")),
        topic=str(doc.get("topic", "#BữaĂn")),
        allow_comments=bool(doc.get("allow_comments", True)),
        attachment=doc.get("attachment"),
        question_title=doc.get("question_title"),
        question_details=doc.get("question_details"),
        updated_at=updated_at,
    )


def _find_draft_by_id(col, draft_id: str) -> Optional[Dict[str, Any]]:
    id_filters: List[Dict[str, Any]] = [{"id": draft_id}, {"_id": draft_id}]
    if ObjectId.is_valid(draft_id):
        id_filters.append({"_id": ObjectId(draft_id)})
    return col.find_one({"$or": id_filters})


def _upsert_draft(
    current_user_id: str,
    body: CommunityDraftUpsertRequest,
    path_draft_id: Optional[str] = None,
) -> CommunityDraftModel:
    col = get_community_drafts_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    target_id = path_draft_id.strip() if path_draft_id else (body.id.strip() if body.id else None)
    now = datetime.now(timezone.utc)
    fields: Dict[str, Any] = {
        "caption": body.caption,
        "media_urls": list(body.media_urls),
        "aspect_ratio": body.aspect_ratio,
        "rotation": body.rotation,
        "brightness": body.brightness,
        "contrast": body.contrast,
        "audience": body.audience,
        "topic": body.topic,
        "allow_comments": bool(body.allow_comments),
        "attachment": body.attachment,
        "question_title": body.question_title,
        "question_details": body.question_details,
        "updated_at": now,
    }

    if target_id:
        existing = _find_draft_by_id(col, target_id)
        if existing is not None:
            if str(existing.get("user_id")) != current_user_id:
                raise HTTPException(status_code=404, detail="Draft not found")
            col.update_one(
                {"_id": existing["_id"], "user_id": current_user_id},
                {"$set": fields},
            )
            return _build_draft_model(dict(existing, **fields))

        new_oid = ObjectId(target_id) if ObjectId.is_valid(target_id) else ObjectId()
        doc = {
            "_id": new_oid,
            "id": target_id,
            "user_id": current_user_id,
            "created_at": now,
            **fields,
        }
        col.insert_one(doc)
        return _build_draft_model(doc)

    new_oid = ObjectId()
    doc = {
        "_id": new_oid,
        "id": str(new_oid),
        "user_id": current_user_id,
        "created_at": now,
        **fields,
    }
    col.insert_one(doc)
    return _build_draft_model(doc)


@router.get("/drafts", response_model=CommunityDraftsResponse)
async def list_community_drafts(
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])
    col = get_community_drafts_collection()
    if col is None:
        return CommunityDraftsResponse(items=[])

    docs = list(col.find({"user_id": current_user_id}).sort([("updated_at", -1), ("_id", -1)]))
    return CommunityDraftsResponse(items=[_build_draft_model(d) for d in docs])


@router.post("/drafts", response_model=CommunityDraftModel)
async def create_or_upsert_community_draft(
    body: CommunityDraftUpsertRequest,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    return _upsert_draft(str(current_user["_id"]), body)


@router.put("/drafts/{draft_id}", response_model=CommunityDraftModel)
async def upsert_community_draft_by_id(
    draft_id: str,
    body: CommunityDraftUpsertRequest,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    return _upsert_draft(str(current_user["_id"]), body, path_draft_id=draft_id)


@router.delete("/drafts/{draft_id}")
async def delete_community_draft(
    draft_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])
    col = get_community_drafts_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    id_filters: List[Dict[str, Any]] = [{"id": draft_id}, {"_id": draft_id}]
    if ObjectId.is_valid(draft_id):
        id_filters.append({"_id": ObjectId(draft_id)})
    doc = col.find_one({"user_id": current_user_id, "$or": id_filters})
    if not doc:
        raise HTTPException(status_code=404, detail="Draft not found")

    col.delete_one({"_id": doc["_id"], "user_id": current_user_id})
    return {"success": True, "id": str(doc.get("id") or doc["_id"])}


@router.get("/authors/{author_id}/posts", response_model=CommunityFeedResponse)
async def get_author_posts(
    author_id: str,
    tab: Literal["all", "workout", "meal", "qa"] = Query("all"),
    limit: int = Query(20, ge=1, le=50),
    cursor: Optional[str] = Query(None),
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user),
):
    current_user_id = str(current_user["_id"]) if current_user else None
    target_id = current_user_id if author_id == "me" else author_id
    if not target_id:
        raise HTTPException(status_code=401, detail="Authentication required")

    target_info = _find_author_doc(target_id)
    if not target_info and target_id != current_user_id:
        raise HTTPException(status_code=404, detail="Author not found")

    if current_user_id and target_id != current_user_id and _is_blocked_between(current_user_id, target_id):
        raise HTTPException(status_code=404, detail="Author not found")

    posts_col = get_community_posts_collection()
    if posts_col is None:
        return CommunityFeedResponse(items=[], next_cursor=None)

    follows_col = get_community_follows_collection()
    if current_user_id and current_user_id == target_id:
        allowed_privacies: List[Optional[str]] = ["public", "followers_only", "private", None]
    else:
        is_follower = False
        if current_user_id and follows_col is not None:
            is_follower = bool(follows_col.find_one({"follower_id": current_user_id, "following_id": target_id}))
        allowed_privacies = ["public", "followers_only", None] if is_follower else ["public", None]

    and_clauses: List[Dict[str, Any]] = [
        {"is_deleted": {"$ne": True}},
        {"status": {"$in": ["published", None]}},
        {"$or": [{"author_id": target_id}, {"author.id": target_id}]},
        {"privacy": {"$in": allowed_privacies}},
    ]

    if tab == "workout":
        and_clauses.append({
            "$or": [
                {"type": "workout"},
                {"workout_attachment": {"$ne": None}},
                {"attachment_snapshot.kind": "workout"},
            ]
        })
    elif tab == "meal":
        and_clauses.append({
            "$or": [
                {"type": "meal"},
                {"nutrition_info": {"$ne": None}},
                {"attachment_snapshot.kind": "meal"},
            ]
        })
    elif tab == "qa":
        and_clauses.append({"type": "qa"})

    if cursor:
        cursor_dt, cursor_id = _decode_cursor(cursor)
        and_clauses.append({
            "$or": [
                {"created_at": {"$lt": cursor_dt}},
                {
                    "created_at": cursor_dt,
                    "_id": {"$lt": ObjectId(cursor_id) if ObjectId.is_valid(cursor_id) else cursor_id},
                },
            ]
        })

    docs = list(posts_col.find({"$and": and_clauses}).sort([("created_at", -1), ("_id", -1)]).limit(limit + 1))

    # Defense-in-depth audience enforcement via _check_post_audience
    visible_docs: List[Dict[str, Any]] = []
    for d in docs:
        try:
            _check_post_audience(d, current_user_id)
            visible_docs.append(d)
        except HTTPException:
            continue

    has_more = len(visible_docs) > limit
    results_docs = visible_docs[:limit]

    items = _hydrate_post_docs(results_docs, current_user_id)

    next_cursor = None
    if has_more and results_docs:
        last_doc = results_docs[-1]
        c_dt = last_doc.get("created_at") or datetime.now(timezone.utc)
        if isinstance(c_dt, str):
            c_dt = datetime.fromisoformat(c_dt)
        next_cursor = _encode_cursor(c_dt, str(last_doc["_id"]))

    return CommunityFeedResponse(items=items, next_cursor=next_cursor)


@router.patch("/profile", response_model=CommunityAuthorProfileResponse)
async def update_community_profile(
    body: UpdateCommunityProfileRequest,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    current_user_id = str(current_user["_id"])
    users_col = get_users_collection()
    if users_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    id_filters: List[Dict[str, Any]] = [{"_id": current_user_id}, {"id": current_user_id}]
    if ObjectId.is_valid(current_user_id):
        id_filters.append({"_id": ObjectId(current_user_id)})
    user_doc = users_col.find_one({"$or": id_filters})
    if not user_doc and current_user.get("email"):
        user_doc = users_col.find_one({"email": current_user["email"]})
    if not user_doc:
        raise HTTPException(status_code=404, detail="User not found")

    updates: Dict[str, Any] = {}

    if body.name is not None:
        clean_name = body.name.strip()
        if not clean_name:
            raise HTTPException(status_code=422, detail="Name must not be blank")
        updates["name"] = clean_name

    if body.handle is not None:
        raw_handle = body.handle.strip()
        if raw_handle == "":
            updates["handle"] = None
        else:
            stripped = raw_handle.lstrip("@").strip().lower()
            if not stripped or not _HANDLE_RE.fullmatch(stripped):
                raise HTTPException(
                    status_code=422,
                    detail="Handle must contain only lowercase letters, numbers, dots, and underscores (1-32 chars)",
                )
            existing_handle_user = users_col.find_one({"handle": stripped})
            if existing_handle_user is not None:
                existing_ids = {str(existing_handle_user.get("_id"))}
                if existing_handle_user.get("id"):
                    existing_ids.add(str(existing_handle_user.get("id")))
                my_ids = {current_user_id, str(user_doc.get("_id"))}
                if user_doc.get("id"):
                    my_ids.add(str(user_doc.get("id")))
                if not (existing_ids & my_ids):
                    raise HTTPException(status_code=409, detail="Handle already in use")
            updates["handle"] = stripped

    if body.title is not None:
        updates["title"] = body.title.strip()

    if body.bio is not None:
        updates["bio"] = body.bio.strip()

    if body.interest_topics is not None:
        cleaned_topics: List[str] = []
        for topic in body.interest_topics:
            ct = topic.strip()
            if ct and ct not in cleaned_topics:
                cleaned_topics.append(ct)
        if len(cleaned_topics) > 3:
            raise HTTPException(status_code=422, detail="At most 3 interest topics are allowed")
        updates["interest_topics"] = cleaned_topics

    if body.avatar_url is not None:
        clean_avatar = body.avatar_url.strip() or None
        updates["avatar_url"] = clean_avatar
        updates["custom_avatar"] = clean_avatar

    if updates:
        updates["updated_at"] = datetime.now(timezone.utc)
        users_col.update_one({"_id": user_doc["_id"]}, {"$set": updates})

        post_author_updates: Dict[str, Any] = {}
        if "name" in updates:
            post_author_updates["author.name"] = updates["name"]
        if "title" in updates:
            post_author_updates["author.title"] = updates["title"]
        if "avatar_url" in updates:
            post_author_updates["author.avatar_url"] = updates["avatar_url"]

        if post_author_updates:
            target_author_ids = list({
                current_user_id,
                str(user_doc["_id"]),
                *([str(user_doc["id"])] if user_doc.get("id") else []),
            })
            posts_col = get_community_posts_collection()
            if posts_col is not None and hasattr(posts_col, "update_many"):
                posts_col.update_many(
                    {"$or": [{"author_id": {"$in": target_author_ids}}, {"author.id": {"$in": target_author_ids}}]},
                    {"$set": post_author_updates},
                )

    return _build_author_profile_response(
        target_id=current_user_id,
        current_user=current_user,
        allow_fallback_current_user=True,
    )


# --- WAVE 3: DISCOVER ENDPOINT ---

_DISCOVER_TOPIC_CHIPS: List[str] = ["all", "workout", "meal", "recipe", "qna", "journey"]


def _is_public_discover_post(doc: Dict[str, Any]) -> bool:
    if not isinstance(doc, dict):
        return False
    if doc.get("privacy") != "public":
        return False
    if doc.get("is_deleted") is True:
        return False
    if doc.get("status") not in ("published", None):
        return False
    return True


def _build_discover_topic_clause(active_topic: str) -> Optional[Dict[str, Any]]:
    if not active_topic or active_topic == "all":
        return None
    if active_topic == "workout":
        return {
            "$or": [
                {"type": "workout"},
                {"topic": "#TậpLuyện"},
                {"attachment_snapshot.kind": "workout"},
            ]
        }
    if active_topic == "meal":
        return {
            "$or": [
                {"type": "meal"},
                {"topic": "#BữaĂn"},
                {"attachment_snapshot.kind": "meal"},
            ]
        }
    if active_topic == "recipe":
        return {
            "$or": [
                {"topic": {"$in": ["#BữaĂn", "#Mẹo"]}},
                {"caption": {"$regex": r"công thức|recipe", "$options": "i"}},
                {"topic": {"$regex": r"công thức|recipe", "$options": "i"}},
            ]
        }
    if active_topic == "qna":
        return {"type": "qa"}
    if active_topic == "journey":
        return {"topic": {"$in": ["#KỷLuật", "#PhụcHồi", "#ChiaSẻ"]}}
    if active_topic.startswith("#"):
        escaped_tag = re.escape(active_topic)
        stripped_tag = re.escape(active_topic.lstrip("#"))
        clauses: List[Dict[str, Any]] = [
            {"topic": {"$regex": f"^{escaped_tag}$", "$options": "i"}},
        ]
        if stripped_tag:
            clauses.append({"topic": {"$regex": f"^{stripped_tag}$", "$options": "i"}})
        return {"$or": clauses}
    return {"topic": active_topic}


@router.get("/discover", response_model=CommunityDiscoverResponse)
async def get_community_discover(
    topic: str = Query("all"),
    q: str = Query("", max_length=100),
    limit: int = Query(18, ge=1, le=50),
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user),
):
    current_user_id = str(current_user["_id"]) if current_user else None

    raw_topic = (topic or "all").strip()
    if not raw_topic:
        active_topic = "all"
    elif raw_topic.startswith("#"):
        active_topic = raw_topic
    else:
        active_topic = raw_topic.lower()

    query_text = (q or "").strip()
    escaped_q = re.escape(query_text) if query_text else ""
    q_regex = re.compile(escaped_q, re.IGNORECASE) if escaped_q else None

    posts_col = get_community_posts_collection()
    interactions_col = get_community_interactions_collection()
    follows_col = get_community_follows_collection()
    users_col = get_users_collection()
    excluded_ids = _get_excluded_user_ids(current_user_id, include_muted=True)

    grid_items: List[CommunityVisualGridItemModel] = []
    trending_topics: List[CommunityTrendingTopicModel] = []
    recommended_creators: List[CommunityAuthorModel] = []

    if posts_col is not None:
        and_clauses: List[Dict[str, Any]] = [
            {"privacy": "public"},
            {"is_deleted": {"$ne": True}},
            {"status": {"$in": ["published", None]}},
            {"photo_urls.0": {"$exists": True}},
        ]

        if excluded_ids:
            excluded_list = list(excluded_ids)
            and_clauses.append({
                "author_id": {"$nin": excluded_list},
                "author.id": {"$nin": excluded_list},
            })

        topic_clause = _build_discover_topic_clause(active_topic)
        if topic_clause is not None:
            and_clauses.append(topic_clause)

        if escaped_q:
            regex_cond = {"$regex": escaped_q, "$options": "i"}
            and_clauses.append({
                "$or": [
                    {"caption": regex_cond},
                    {"topic": regex_cond},
                    {"qa_info.question": regex_cond},
                    {"attachment_snapshot.title": regex_cond},
                    {"author.name": regex_cond},
                ]
            })

        raw_grid_docs = list(
            posts_col.find({"$and": and_clauses})
            .sort([("created_at", -1), ("_id", -1)])
            .limit(limit)
        )

        grid_docs: List[tuple[Dict[str, Any], List[str]]] = []
        for d in raw_grid_docs:
            if not _is_public_discover_post(d):
                continue
            if excluded_ids and _extract_doc_author_id(d) in excluded_ids:
                continue
            valid_photos = [
                str(u).strip()
                for u in (d.get("photo_urls") or [])
                if isinstance(u, str) and u.strip()
            ]
            if not valid_photos:
                continue
            grid_docs.append((d, valid_photos))

        grid_author_ids = [_extract_doc_author_id(d) for d, _ in grid_docs]
        grid_author_settings = _get_user_settings_map(grid_author_ids)

        authoritative_like_counts: Dict[str, int] = {}
        if interactions_col is not None and grid_docs:
            all_pids: List[str] = []
            for d, _ in grid_docs:
                if d.get("id"):
                    all_pids.append(str(d["id"]))
                if d.get("_id") is not None:
                    all_pids.append(str(d["_id"]))
            if all_pids:
                for agg in interactions_col.aggregate([
                    {"$match": {"post_id": {"$in": list(set(all_pids))}, "interaction_type": "like"}},
                    {"$group": {"_id": "$post_id", "count": {"$sum": 1}}},
                ]):
                    authoritative_like_counts[str(agg["_id"])] = int(agg["count"])

        for d, valid_photos in grid_docs:
            pid = str(d.get("id") or d.get("_id"))
            doc_oid = str(d.get("_id")) if d.get("_id") is not None else None
            auth_cnt: Optional[int] = None
            if pid in authoritative_like_counts:
                auth_cnt = authoritative_like_counts[pid]
            elif doc_oid and doc_oid in authoritative_like_counts:
                auth_cnt = authoritative_like_counts[doc_oid]
            elif d.get("interaction_version", 0) > 0:
                auth_cnt = 0
            final_like_count = auth_cnt if auth_cnt is not None else int(d.get("like_count", 0))
            d_author_id = _extract_doc_author_id(d)
            if (
                d_author_id
                and d_author_id != current_user_id
                and bool(grid_author_settings.get(d_author_id, _DEFAULT_COMMUNITY_SETTINGS).get("hide_like_counts", False))
            ):
                final_like_count = 0

            alt_text = (
                str(d.get("caption") or "").strip()
                or str((d.get("attachment_snapshot") or {}).get("title") or "").strip()
                or str((d.get("qa_info") or {}).get("question") or "").strip()
                or None
            )
            grid_items.append(
                CommunityVisualGridItemModel(
                    id=pid,
                    post_id=pid,
                    image_url=valid_photos[0],
                    like_count=final_like_count,
                    has_multi_photo=len(valid_photos) > 1,
                    has_video=bool(d.get("has_video", False) or d.get("video_url")),
                    alt_text=alt_text,
                )
            )

        trending_match: Dict[str, Any] = {
            "privacy": "public",
            "is_deleted": {"$ne": True},
            "status": {"$in": ["published", None]},
            "topic": {"$exists": True, "$ne": ""},
        }
        if excluded_ids:
            excluded_list = list(excluded_ids)
            trending_match["author_id"] = {"$nin": excluded_list}
            trending_match["author.id"] = {"$nin": excluded_list}
        topic_counts: Dict[str, int] = {}
        for agg in posts_col.aggregate([
            {"$match": trending_match},
            {"$group": {"_id": "$topic", "count": {"$sum": 1}}},
        ]):
            raw_t = agg.get("_id")
            if not isinstance(raw_t, str):
                continue
            cleaned_t = raw_t.strip()
            if not cleaned_t:
                continue
            hashtag = cleaned_t if cleaned_t.startswith("#") else f"#{cleaned_t}"
            topic_counts[hashtag] = topic_counts.get(hashtag, 0) + int(agg.get("count", 0))

        topic_entries = list(topic_counts.items())
        if q_regex is not None:
            topic_entries = [
                (tag, cnt) for tag, cnt in topic_entries if q_regex.search(tag)
            ]

        topic_entries.sort(key=lambda item: (-item[1], item[0].lower()))
        for idx, (hashtag, cnt) in enumerate(topic_entries[:5], start=1):
            slug = re.sub(r"[^a-z0-9]+", "_", hashtag.lower()).strip("_") or str(idx)
            trending_topics.append(
                CommunityTrendingTopicModel(
                    id=f"trending_{idx}_{slug}",
                    hashtag=hashtag,
                    post_count_formatted=f"{cnt} bài viết thảo luận",
                    growth_percent="Ổn định",
                    is_stable=True,
                    icon_name="tag",
                )
            )

    if users_col is not None:
        user_query: Dict[str, Any] = {}
        if escaped_q:
            regex_cond = {"$regex": escaped_q, "$options": "i"}
            user_query = {
                "$or": [
                    {"name": regex_cond},
                    {"full_name": regex_cond},
                    {"title": regex_cond},
                    {"handle": regex_cond},
                ]
            }

        raw_users = list(users_col.find(user_query).limit(200))
        candidate_users: List[tuple[str, Dict[str, Any]]] = []
        seen_uids: set[str] = set()
        for u in raw_users:
            uid = str(u.get("_id") or u.get("id") or "")
            alt_uid = str(u.get("id") or "")
            if not uid or uid in seen_uids:
                continue
            if current_user_id and (uid == current_user_id or alt_uid == current_user_id):
                continue
            if excluded_ids and (uid in excluded_ids or (alt_uid and alt_uid in excluded_ids)):
                continue
            seen_uids.add(uid)
            candidate_users.append((uid, u))

        creator_ids = [uid for uid, _ in candidate_users]
        creator_follower_counts: Dict[str, int] = {}
        viewer_following_ids: set[str] = set()
        if follows_col is not None and creator_ids:
            for agg in follows_col.aggregate([
                {"$match": {"following_id": {"$in": creator_ids}}},
                {"$group": {"_id": "$following_id", "count": {"$sum": 1}}},
            ]):
                creator_follower_counts[str(agg["_id"])] = int(agg["count"])
            if current_user_id:
                for f in follows_col.find({
                    "follower_id": current_user_id,
                    "following_id": {"$in": creator_ids},
                }):
                    viewer_following_ids.add(str(f["following_id"]))

        creators_all: List[CommunityAuthorModel] = []
        for uid, u in candidate_users:
            creators_all.append(
                _sanitize_author_projection(
                    u,
                    current_user_id=current_user_id,
                    is_following=(uid in viewer_following_ids) if current_user_id else False,
                    follower_count_override=creator_follower_counts.get(uid, 0),
                )
            )

        creators_all.sort(key=lambda c: (-c.follower_count, c.name.lower()))
        recommended_creators = creators_all[:10]

    return CommunityDiscoverResponse(
        topic_chips=list(_DISCOVER_TOPIC_CHIPS),
        active_topic=active_topic,
        grid_items=grid_items,
        trending_topics=trending_topics,
        recommended_creators=recommended_creators,
    )


# --- WAVE 4: SOCIAL SETTINGS, BLOCK/MUTE/REPORT, STORIES 24H & POST SHARE ---


@router.get("/settings", response_model=CommunitySettingsModel)
async def get_community_settings(
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    col = get_community_user_settings_collection()
    if col is None:
        return _build_settings_model(None)
    doc = col.find_one({"user_id": uid})
    return _build_settings_model(doc)


@router.patch("/settings", response_model=CommunitySettingsModel)
async def update_community_settings(
    body: UpdateCommunitySettingsRequest,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    col = get_community_user_settings_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    existing = col.find_one({"user_id": uid})
    merged = dict(_DEFAULT_COMMUNITY_SETTINGS)
    if isinstance(existing, dict):
        for key in _DEFAULT_COMMUNITY_SETTINGS:
            if key in existing and existing[key] is not None:
                merged[key] = existing[key]

    if body.is_private_account is not None:
        merged["is_private_account"] = bool(body.is_private_account)
    if body.who_can_dm is not None:
        merged["who_can_dm"] = body.who_can_dm
    if body.who_can_comment is not None:
        merged["who_can_comment"] = body.who_can_comment
    if body.who_can_reply_story is not None:
        merged["who_can_reply_story"] = body.who_can_reply_story
    if body.allow_mentions is not None:
        merged["allow_mentions"] = body.allow_mentions
    if body.hide_like_counts is not None:
        merged["hide_like_counts"] = bool(body.hide_like_counts)
    if body.show_activity_status is not None:
        merged["show_activity_status"] = bool(body.show_activity_status)
    if body.auto_prompt_share_workout is not None:
        merged["auto_prompt_share_workout"] = bool(body.auto_prompt_share_workout)
    if body.auto_prompt_share_meal is not None:
        merged["auto_prompt_share_meal"] = bool(body.auto_prompt_share_meal)
    if body.muted_keywords is not None:
        merged["muted_keywords"] = _normalize_muted_keywords(body.muted_keywords, strict=True)

    now = datetime.now(timezone.utc)
    col.update_one(
        {"user_id": uid},
        {
            "$set": {
                "user_id": uid,
                **merged,
                "updated_at": now,
            },
            "$setOnInsert": {
                "created_at": now,
            },
        },
        upsert=True,
    )
    return _build_settings_model(merged)


@router.put("/users/{target_user_id}/block", response_model=BlockStatusResponse)
async def block_community_user(
    target_user_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    if target_user_id == uid or target_user_id == "me":
        raise HTTPException(status_code=400, detail="Cannot block yourself")

    target_info = _find_author_doc(target_user_id)
    if not target_info:
        raise HTTPException(status_code=404, detail="User not found")

    blocks_col = get_community_blocks_collection()
    if blocks_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    try:
        blocks_col.insert_one({
            "_id": ObjectId(),
            "blocker_id": uid,
            "blocked_id": target_user_id,
            "created_at": datetime.now(timezone.utc),
        })
    except DuplicateKeyError:
        pass

    follows_col = get_community_follows_collection()
    if follows_col is not None:
        if hasattr(follows_col, "delete_many"):
            follows_col.delete_many({
                "$or": [
                    {"follower_id": uid, "following_id": target_user_id},
                    {"follower_id": target_user_id, "following_id": uid},
                ]
            })
        else:
            follows_col.delete_one({"follower_id": uid, "following_id": target_user_id})
            follows_col.delete_one({"follower_id": target_user_id, "following_id": uid})

    return BlockStatusResponse(target_user_id=target_user_id, is_blocked=True)


@router.delete("/users/{target_user_id}/block", response_model=BlockStatusResponse)
async def unblock_community_user(
    target_user_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    if target_user_id == uid or target_user_id == "me":
        raise HTTPException(status_code=400, detail="Cannot unblock yourself")

    blocks_col = get_community_blocks_collection()
    if blocks_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    blocks_col.delete_one({"blocker_id": uid, "blocked_id": target_user_id})
    return BlockStatusResponse(target_user_id=target_user_id, is_blocked=False)


@router.get("/settings/blocked", response_model=CommunityBlockedUsersResponse)
async def list_blocked_users(
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    blocks_col = get_community_blocks_collection()
    if blocks_col is None:
        return CommunityBlockedUsersResponse(items=[], total_count=0)

    docs = list(blocks_col.find({"blocker_id": uid}).sort([("created_at", -1), ("_id", -1)]))
    items: List[CommunityAuthorModel] = []
    for d in docs:
        target_id = str(d.get("blocked_id") or "")
        if not target_id:
            continue
        info = _find_author_doc(target_id) or {"id": target_id, "name": "Saman Athlete"}
        items.append(
            _sanitize_author_projection(
                info,
                current_user_id=uid,
                is_following=False,
            )
        )
    return CommunityBlockedUsersResponse(items=items, total_count=len(items))


@router.put("/users/{target_user_id}/mute", response_model=MuteStatusResponse)
async def mute_community_user(
    target_user_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    if target_user_id == uid or target_user_id == "me":
        raise HTTPException(status_code=400, detail="Cannot mute yourself")

    target_info = _find_author_doc(target_user_id)
    if not target_info:
        raise HTTPException(status_code=404, detail="User not found")

    mutes_col = get_community_mutes_collection()
    if mutes_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    try:
        mutes_col.insert_one({
            "_id": ObjectId(),
            "muter_id": uid,
            "muted_id": target_user_id,
            "created_at": datetime.now(timezone.utc),
        })
    except DuplicateKeyError:
        pass

    return MuteStatusResponse(target_user_id=target_user_id, is_muted=True)


@router.delete("/users/{target_user_id}/mute", response_model=MuteStatusResponse)
async def unmute_community_user(
    target_user_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    if target_user_id == uid or target_user_id == "me":
        raise HTTPException(status_code=400, detail="Cannot unmute yourself")

    mutes_col = get_community_mutes_collection()
    if mutes_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    mutes_col.delete_one({"muter_id": uid, "muted_id": target_user_id})
    return MuteStatusResponse(target_user_id=target_user_id, is_muted=False)


@router.get("/settings/muted", response_model=CommunityBlockedUsersResponse)
async def list_muted_users(
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    mutes_col = get_community_mutes_collection()
    if mutes_col is None:
        return CommunityBlockedUsersResponse(items=[], total_count=0)

    docs = list(mutes_col.find({"muter_id": uid}).sort([("created_at", -1), ("_id", -1)]))
    items: List[CommunityAuthorModel] = []
    for d in docs:
        target_id = str(d.get("muted_id") or "")
        if not target_id:
            continue
        info = _find_author_doc(target_id) or {"id": target_id, "name": "Saman Athlete"}
        items.append(_sanitize_author_projection(info, current_user_id=uid))
    return CommunityBlockedUsersResponse(items=items, total_count=len(items))


def _verify_report_target_exists(target_type: str, target_id: str) -> None:
    if target_type == "post":
        post = _find_post_doc(target_id)
        if not post or post.get("is_deleted", False) or post.get("status") == "unpublished":
            raise HTTPException(status_code=404, detail="Report target not found")
        return

    if target_type == "comment":
        col = get_community_comments_collection()
        if col is None:
            raise HTTPException(status_code=503, detail="Database unavailable")
        filters: List[Dict[str, Any]] = [{"id": target_id}, {"_id": target_id}]
        if ObjectId.is_valid(target_id):
            filters.append({"_id": ObjectId(target_id)})
        if not col.find_one({"$or": filters}):
            raise HTTPException(status_code=404, detail="Report target not found")
        return

    if target_type == "answer":
        col = get_community_answers_collection()
        if col is None:
            raise HTTPException(status_code=503, detail="Database unavailable")
        filters = [{"id": target_id}, {"_id": target_id}]
        if ObjectId.is_valid(target_id):
            filters.append({"_id": ObjectId(target_id)})
        if not col.find_one({"is_deleted": {"$ne": True}, "$or": filters}):
            raise HTTPException(status_code=404, detail="Report target not found")
        return

    if target_type == "user":
        if not _find_author_doc(target_id):
            raise HTTPException(status_code=404, detail="Report target not found")
        return

    raise HTTPException(status_code=422, detail="Unsupported report target type")


@router.post("/reports", response_model=ReportReceiptResponse)
async def create_community_report(
    body: CreateReportRequest,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    target_id = body.target_id.strip()
    if not target_id:
        raise HTTPException(status_code=422, detail="target_id must not be blank")

    if body.target_type == "user" and target_id in (uid, "me"):
        raise HTTPException(status_code=400, detail="Cannot report yourself")

    reports_col = get_community_reports_collection()
    if reports_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    _verify_report_target_exists(body.target_type, target_id)

    identity = {
        "reporter_id": uid,
        "target_type": body.target_type,
        "target_id": target_id,
    }
    existing = reports_col.find_one(identity)
    if existing is not None:
        created_at = existing.get("created_at") or datetime.now(timezone.utc)
        if isinstance(created_at, datetime) and created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        return ReportReceiptResponse(
            report_id=str(existing.get("id") or existing["_id"]),
            target_type=existing.get("target_type", body.target_type),
            target_id=str(existing.get("target_id", target_id)),
            reason=existing.get("reason", body.reason),
            status=str(existing.get("status", "received")),
            created_at=created_at,
            already_reported=True,
        )

    now = datetime.now(timezone.utc)
    doc = {
        "_id": ObjectId(),
        **identity,
        "reason": body.reason,
        "details": body.details.strip(),
        "status": "received",
        "created_at": now,
    }
    already_reported = False
    try:
        reports_col.insert_one(doc)
    except DuplicateKeyError:
        existing = reports_col.find_one(identity)
        if existing is not None:
            doc = existing
            already_reported = True

    created_at = doc.get("created_at") or now
    if isinstance(created_at, datetime) and created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    return ReportReceiptResponse(
        report_id=str(doc.get("id") or doc["_id"]),
        target_type=doc.get("target_type", body.target_type),
        target_id=str(doc.get("target_id", target_id)),
        reason=doc.get("reason", body.reason),
        status=str(doc.get("status", "received")),
        created_at=created_at,
        already_reported=already_reported,
    )


def _normalize_utc_dt(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value)
        except ValueError:
            return None
    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)
    return None


def _find_story_doc(story_id: str) -> Optional[Dict[str, Any]]:
    col = get_community_stories_collection()
    if col is None:
        return None
    filters: List[Dict[str, Any]] = [{"id": story_id}, {"_id": story_id}]
    if ObjectId.is_valid(story_id):
        filters.append({"_id": ObjectId(story_id)})
    return col.find_one({"$or": filters})


def _can_view_story(
    story_doc: Dict[str, Any],
    viewer_id: Optional[str],
    now: Optional[datetime] = None,
    followed_ids: Optional[set[str]] = None,
) -> bool:
    if not story_doc or story_doc.get("is_deleted", False):
        return False
    check_now = now or datetime.now(timezone.utc)
    expires_at = _normalize_utc_dt(story_doc.get("expires_at"))
    if expires_at is None or expires_at <= check_now:
        return False

    author_id = str(story_doc.get("user_id") or "")
    if not author_id:
        return False
    if viewer_id and viewer_id == author_id:
        return True
    if viewer_id and _is_blocked_between(viewer_id, author_id):
        return False

    privacy = story_doc.get("privacy", "public")
    if privacy == "public":
        return True
    if privacy == "followers_only":
        if not viewer_id:
            return False
        if followed_ids is not None:
            return author_id in followed_ids
        follows_col = get_community_follows_collection()
        return bool(
            follows_col is not None
            and follows_col.find_one({"follower_id": viewer_id, "following_id": author_id})
        )
    return False


def _build_story_model(
    doc: Dict[str, Any],
    view_count: int = 0,
    is_viewed: bool = False,
) -> CommunityStoryModel:
    created_at = _normalize_utc_dt(doc.get("created_at")) or datetime.now(timezone.utc)
    expires_at = _normalize_utc_dt(doc.get("expires_at")) or (created_at + timedelta(hours=24))
    return CommunityStoryModel(
        id=str(doc.get("id") or doc["_id"]),
        author_id=str(doc.get("user_id") or ""),
        media_type=doc.get("media_type", "text"),
        media_url=doc.get("media_url"),
        caption=str(doc.get("caption") or ""),
        background_color=doc.get("background_color"),
        privacy=doc.get("privacy", "public"),
        created_at=created_at,
        expires_at=expires_at,
        time_ago=_format_time_ago(created_at),
        view_count=view_count,
        is_viewed=is_viewed,
    )


@router.post("/stories", response_model=CommunityStoryModel)
async def create_community_story(
    body: CreateStoryRequest,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    stories_col = get_community_stories_collection()
    if stories_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    caption = body.caption.strip()
    clean_media_url: Optional[str] = None

    if body.media_type in ("photo", "video"):
        if not body.media_url or not body.media_url.strip():
            raise HTTPException(
                status_code=422,
                detail=f"media_url is required for {body.media_type} stories",
            )
        clean_media_url = _validate_media_url(body.media_url, field_label="Story media_url")
    else:
        if not caption:
            raise HTTPException(status_code=422, detail="caption must not be blank for text stories")
        if body.media_url and body.media_url.strip():
            clean_media_url = _validate_media_url(body.media_url, field_label="Story media_url")

    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(hours=24)
    doc = {
        "_id": ObjectId(),
        "user_id": uid,
        "author": {
            "id": uid,
            "name": current_user.get("name") or current_user.get("full_name") or "Saman Athlete",
            "avatar_url": current_user.get("avatar_url") or current_user.get("avatar") or current_user.get("custom_avatar"),
            "title": current_user.get("title") or "Thành viên Saman",
            "is_verified": bool(current_user.get("is_verified", False)),
        },
        "media_type": body.media_type,
        "media_url": clean_media_url,
        "caption": caption,
        "background_color": body.background_color.strip() if body.background_color else None,
        "privacy": body.privacy,
        "is_deleted": False,
        "created_at": now,
        "expires_at": expires_at,
    }
    stories_col.insert_one(doc)
    return _build_story_model(doc, view_count=0, is_viewed=False)


@router.get("/stories", response_model=CommunityStoriesFeedResponse)
async def get_community_stories(
    current_user: Optional[Dict[str, Any]] = Depends(get_optional_current_user),
):
    stories_col = get_community_stories_collection()
    if stories_col is None:
        return CommunityStoriesFeedResponse(items=[])

    current_user_id = str(current_user["_id"]) if current_user else None
    now = datetime.now(timezone.utc)
    excluded_ids = _get_excluded_user_ids(current_user_id, include_muted=True)

    follows_col = get_community_follows_collection()
    followed_ids: set[str] = set()
    if current_user_id and follows_col is not None:
        followed_ids = {
            str(f["following_id"])
            for f in follows_col.find({"follower_id": current_user_id})
            if str(f["following_id"]) not in excluded_ids
        }

    query: Dict[str, Any] = {
        "expires_at": {"$gt": now},
        "is_deleted": {"$ne": True},
    }
    if excluded_ids:
        query["user_id"] = {"$nin": list(excluded_ids)}

    raw_stories = list(stories_col.find(query).sort([("created_at", 1), ("_id", 1)]))

    visible_docs: List[Dict[str, Any]] = []
    for doc in raw_stories:
        author_id = str(doc.get("user_id") or "")
        if not author_id or author_id in excluded_ids:
            continue
        if not _can_view_story(doc, current_user_id, now=now, followed_ids=followed_ids):
            continue
        visible_docs.append(doc)

    if not visible_docs:
        return CommunityStoriesFeedResponse(items=[])

    story_ids = [str(d.get("id") or d["_id"]) for d in visible_docs]
    views_col = get_community_story_views_collection()
    view_counts: Dict[str, int] = {}
    viewed_story_ids: set[str] = set()
    if views_col is not None and story_ids:
        for agg in views_col.aggregate([
            {"$match": {"story_id": {"$in": story_ids}}},
            {"$group": {"_id": "$story_id", "count": {"$sum": 1}}},
        ]):
            view_counts[str(agg["_id"])] = int(agg["count"])
        if current_user_id:
            for v in views_col.find({"viewer_id": current_user_id, "story_id": {"$in": story_ids}}):
                viewed_story_ids.add(str(v["story_id"]))

    grouped_docs: Dict[str, List[Dict[str, Any]]] = {}
    for doc in visible_docs:
        aid = str(doc["user_id"])
        grouped_docs.setdefault(aid, []).append(doc)

    groups: List[CommunityStoryAuthorGroupModel] = []
    for aid, author_docs in grouped_docs.items():
        author_info = _find_author_doc(aid) or author_docs[-1].get("author") or {"id": aid, "name": "Saman Athlete"}
        author_model = _sanitize_author_projection(
            author_info,
            current_user_id=current_user_id,
            is_following=(aid in followed_ids) if current_user_id else False,
        )
        story_models: List[CommunityStoryModel] = []
        for sdoc in author_docs:
            sid = str(sdoc.get("id") or sdoc["_id"])
            story_models.append(
                _build_story_model(
                    sdoc,
                    view_count=view_counts.get(sid, 0),
                    is_viewed=(sid in viewed_story_ids),
                )
            )
        is_self = bool(current_user_id and str(aid) == str(current_user_id))
        has_unviewed = any(not s.is_viewed for s in story_models)
        latest_dt = max(s.created_at for s in story_models)
        groups.append(
            CommunityStoryAuthorGroupModel(
                author=author_model,
                is_self=is_self,
                has_unviewed=has_unviewed,
                latest_created_at=latest_dt,
                stories=story_models,
            )
        )

    groups.sort(
        key=lambda g: (
            0 if g.is_self else 1,
            0 if g.has_unviewed else 1,
            -(g.latest_created_at.timestamp() if g.latest_created_at else 0.0),
        )
    )
    return CommunityStoriesFeedResponse(items=groups)


@router.get("/stories/archive", response_model=CommunityStoriesArchiveResponse)
async def get_community_stories_archive(
    include_active: bool = Query(
        False,
        description="Include active (<24h) stories alongside expired stories",
    ),
    limit: int = Query(20, ge=1, le=50, description="Items per page"),
    cursor: Optional[str] = Query(None, description="Opaque cursor for stable pagination"),
    offset: Optional[int] = Query(
        None,
        ge=0,
        description="Optional offset pagination (ignored when cursor is provided)",
    ),
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    """
    Personal Story Archive endpoint.
    Returns only stories created by the authenticated user (is_deleted != True),
    sorted newest first (created_at DESC, _id DESC).
    By default returns expired stories (expires_at <= now); pass include_active=true
    to return all non-deleted stories of the current user.
    """
    stories_col = get_community_stories_collection()
    if stories_col is None:
        return CommunityStoriesArchiveResponse(items=[], next_cursor=None, total_count=0)

    current_user_id = str(current_user["_id"])
    now = datetime.now(timezone.utc)

    base_query: Dict[str, Any] = {
        "user_id": current_user_id,
        "is_deleted": {"$ne": True},
    }
    if not include_active:
        base_query["expires_at"] = {"$lte": now}

    query: Dict[str, Any] = dict(base_query)
    if cursor:
        cursor_dt, cursor_id = _decode_cursor(cursor)
        cursor_filter = {
            "$or": [
                {"created_at": {"$lt": cursor_dt}},
                {
                    "created_at": cursor_dt,
                    "_id": {"$lt": ObjectId(cursor_id) if ObjectId.is_valid(cursor_id) else cursor_id},
                },
            ]
        }
        query = {"$and": [base_query, cursor_filter]}

    sort_order = [("created_at", -1), ("_id", -1)]

    def _is_eligible_archive_doc(doc: Dict[str, Any]) -> bool:
        if str(doc.get("user_id") or "") != current_user_id:
            return False
        if doc.get("is_deleted", False):
            return False
        if not include_active:
            exp_dt = _normalize_utc_dt(doc.get("expires_at"))
            if exp_dt is None or exp_dt > now:
                return False
        return True

    effective_offset = 0 if cursor else int(offset or 0)
    needed = effective_offset + limit + 1
    raw_docs = list(stories_col.find(query).sort(sort_order).limit(needed))
    eligible_docs = [d for d in raw_docs if _is_eligible_archive_doc(d)]
    if len(eligible_docs) < needed and len(raw_docs) == needed:
        # Fallback scan if an in-memory mock does not evaluate $lte in query
        all_docs = list(stories_col.find(query).sort(sort_order))
        eligible_docs = [d for d in all_docs if _is_eligible_archive_doc(d)]

    sliced_docs = eligible_docs[effective_offset:]
    has_more = len(sliced_docs) > limit
    page_docs = sliced_docs[:limit]

    total_count = stories_col.count_documents(base_query)

    story_ids = [str(d.get("id") or d["_id"]) for d in page_docs]
    views_col = get_community_story_views_collection()
    view_counts: Dict[str, int] = {}
    viewed_story_ids: set[str] = set()
    if views_col is not None and story_ids:
        for agg in views_col.aggregate([
            {"$match": {"story_id": {"$in": story_ids}}},
            {"$group": {"_id": "$story_id", "count": {"$sum": 1}}},
        ]):
            view_counts[str(agg["_id"])] = int(agg["count"])
        for v in views_col.find({"viewer_id": current_user_id, "story_id": {"$in": story_ids}}):
            viewed_story_ids.add(str(v["story_id"]))

    items: List[CommunityArchivedStoryModel] = []
    for sdoc in page_docs:
        sid = str(sdoc.get("id") or sdoc["_id"])
        base_model = _build_story_model(
            sdoc,
            view_count=view_counts.get(sid, 0),
            is_viewed=(sid in viewed_story_ids),
        )
        items.append(
            CommunityArchivedStoryModel(
                **base_model.model_dump(),
                is_expired=bool(base_model.expires_at <= now),
            )
        )

    next_cursor = None
    if has_more and page_docs:
        last_doc = page_docs[-1]
        c_dt = _normalize_utc_dt(last_doc.get("created_at")) or now
        next_cursor = _encode_cursor(c_dt, str(last_doc["_id"]))

    return CommunityStoriesArchiveResponse(
        items=items,
        next_cursor=next_cursor,
        total_count=total_count,
    )


@router.post("/stories/{story_id}/view", response_model=StoryViewResponse)
async def view_community_story(
    story_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    views_col = get_community_story_views_collection()
    if views_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    story_doc = _find_story_doc(story_id)
    if not story_doc or not _can_view_story(story_doc, uid):
        raise HTTPException(status_code=404, detail="Story not found")

    canonical_story_id = str(story_doc.get("id") or story_doc["_id"])
    now = datetime.now(timezone.utc)
    views_col.update_one(
        {"story_id": canonical_story_id, "viewer_id": uid},
        {
            "$setOnInsert": {
                "story_id": canonical_story_id,
                "viewer_id": uid,
                "viewed_at": now,
            }
        },
        upsert=True,
    )
    view_count = views_col.count_documents({"story_id": canonical_story_id})
    return StoryViewResponse(
        story_id=canonical_story_id,
        is_viewed=True,
        view_count=view_count,
    )


@router.delete("/stories/{story_id}")
async def delete_community_story(
    story_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    stories_col = get_community_stories_collection()
    if stories_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    story_doc = _find_story_doc(story_id)
    if not story_doc or story_doc.get("is_deleted", False):
        raise HTTPException(status_code=404, detail="Story not found")
    if str(story_doc.get("user_id") or "") != uid:
        raise HTTPException(status_code=404, detail="Story not found")

    canonical_story_id = str(story_doc.get("id") or story_doc["_id"])
    stories_col.update_one(
        {"_id": story_doc["_id"]},
        {"$set": {"is_deleted": True, "deleted_at": datetime.now(timezone.utc)}},
    )
    return {"success": True, "story_id": canonical_story_id}


@router.post("/posts/{post_id}/share", response_model=PostShareResponse)
async def share_community_post(
    post_id: str,
    current_user: Dict[str, Any] = Depends(get_required_current_user),
):
    uid = str(current_user["_id"])
    posts_col = get_community_posts_collection()
    shares_col = get_community_post_shares_collection()
    if posts_col is None or shares_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    doc = _find_post_doc(post_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Post not found")

    _check_post_audience(doc, uid)
    canonical_post_id = str(doc.get("id") or doc["_id"])

    shares_col.insert_one({
        "_id": ObjectId(),
        "post_id": canonical_post_id,
        "user_id": uid,
        "created_at": datetime.now(timezone.utc),
    })

    share_count = shares_col.count_documents({"post_id": canonical_post_id})
    if hasattr(posts_col, "update_one"):
        posts_col.update_one(
            {"_id": doc["_id"]},
            {"$set": {"share_count": share_count}},
        )

    return PostShareResponse(post_id=canonical_post_id, share_count=share_count)
