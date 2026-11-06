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

import base64
import io
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Union
from fastapi import Request, APIRouter, Depends, Header, HTTPException, Query, File, UploadFile
from starlette.routing import Route
from starlette.responses import FileResponse
from PIL import Image
from bson import ObjectId
import jwt
from pymongo.errors import DuplicateKeyError

from backend.app.database import db
from backend.app.models.community import (
    CreateCommunityCommentRequest,
    PublishTextPostRequest,
    PublishQuestionRequest,
    PublishAttachmentPostRequest,
    PublishPhotoPostRequest,
    MediaUploadResponse,
    CommunityCommentsResponse,
    CommunityCommentMutationResponse,
    CommunityAuthorModel,
    CommunityAuthorProfileResponse,
    CommunityCommentModel,
    CommunityFeedResponse,
    CommunityFollowListResponse,
    CommunityPostModel,
    CommunitySavedResponse,
    ExerciseThumbnailPreviewModel,
    FollowResponse,
    InteractionLikeResponse,
    InteractionSaveResponse,
    PostNutritionInfoModel,
    PostQaInfoModel,
    PostWorkoutAttachmentModel,
    QuestionAnswerModel,
    QuestionAnswersResponse,
    CreateQuestionAnswerRequest,
    QuestionAnswerReceipt,
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


def get_users_collection():
    if db is not None:
        return db["users"]
    return None


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


async def serve_static_community_file(request):
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
    filename = f"{uuid.uuid4().hex}.{ext}"
    filepath = os.path.join(COMMUNITY_STATIC_DIR, filename)

    with open(filepath, "wb") as f:
        f.write(content_buf)

    media_url = f"/static/community/{filename}"
    return MediaUploadResponse(
        media_url=media_url,
        content_type=file.content_type or f"image/{ext}",
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
                "avatar_url": u.get("avatar") or u.get("avatar_url") or u.get("custom_avatar"),
                "title": u.get("title") or "Thành viên Saman",
                "is_verified": bool(u.get("is_verified", False)),
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


def _sanitize_comments(raw_comments: List[Dict[str, Any]], current_user_id: Optional[str]) -> List[CommunityCommentModel]:
    out: List[CommunityCommentModel] = []
    for c in raw_comments:
        if not isinstance(c, dict) or c.get("is_deleted", False):
            continue

        author = _sanitize_author_projection(c.get("author"), current_user_id)
        replies_raw = c.get("replies") or []
        replies_sanitized = _sanitize_comments(replies_raw, current_user_id)

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

    nutrition = _sanitize_nutrition(doc.get("nutrition_info"))
    workout = _sanitize_attachment(doc.get("workout_attachment"))
    qa = _sanitize_qa(doc.get("qa_info"))
    if post_type == "qa" and qa is not None:
        answers_col = get_community_answers_collection()
        if answers_col is not None:
            qa.respondent_count = answers_col.count_documents({"question_id": post_id, "is_deleted": {"$ne": True}})
            qa.respondents_summary = str(qa.respondent_count)

    # Persistent comments use their own paginated endpoint. No cached counter writes.
    comments_col = get_community_comments_collection()
    comments = _sanitize_comments(doc.get("comments") or [], current_user_id)
    comment_count = (comments_col.count_documents({"post_id": post_id}) + len(_legacy_comment_docs(doc))
                     if comments_col is not None else int(doc.get("comment_count", len(comments))))

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
    author_id = str(doc.get("author_id") or (doc.get("author") or {}).get("id"))
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

    followed_ids: List[str] = []
    if current_user_id and follows_col is not None:
        followed_ids = [str(f["following_id"]) for f in follows_col.find({"follower_id": current_user_id})]

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

    # Fetch 1 extra to determine next_cursor
    cursor_res = col.find(query).sort(sort_order).limit(limit + 1)
    docs = list(cursor_res)

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
        items.append(_build_post_model(
            d,
            current_user_id,
            liked_post_ids,
            saved_post_ids,
            override_like_count=auth_cnt,
            followed_author_ids=followed_author_set if current_user_id else set(),
            author_follower_counts=author_follower_counts,
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
    try:
        interactions_col.insert_one({
            "user_id": current_user_id,
            "post_id": canonical_post_id,
            "interaction_type": "like",
            "created_at": datetime.now(timezone.utc),
        })
    except DuplicateKeyError:
        pass

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

    valid_items: List[CommunityPostModel] = []
    for pid in post_ids:
        p_doc = posts_by_id.get(pid)
        if not p_doc:
            continue

        # Check soft delete & status
        if p_doc.get("is_deleted", False) or p_doc.get("status") == "unpublished":
            continue

        # Check audience at read time
        privacy = p_doc.get("privacy", "public")
        author_id = str(p_doc.get("author_id") or (p_doc.get("author") or {}).get("id"))
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
    query = {"question_id": qid, "is_deleted": {"$ne": True}}
    if cursor:
        dt, aid = _decode_cursor(cursor)
        if not ObjectId.is_valid(aid):
            raise HTTPException(400, "Invalid pagination cursor")
        query["$or"] = [{"created_at": {"$gt": dt}}, {"created_at": dt, "_id": {"$gt": ObjectId(aid)}}]
    docs = list(col.find(query).sort([("created_at", 1), ("_id", 1)]).limit(limit + 1))
    more = len(docs) > limit
    docs = docs[:limit]
    items = [_public_answer(d, viewer_id) for d in docs]
    count = col.count_documents({"question_id": qid, "is_deleted": {"$ne": True}})
    _answer_question(question_id, viewer_id)
    return QuestionAnswersResponse(items=items, answer_count=count,
        next_cursor=_encode_cursor(docs[-1]["created_at"], str(docs[-1]["_id"])) if more else None)


@router.post("/questions/{question_id}/answers", response_model=QuestionAnswerReceipt)
def create_question_answer(question_id: str, body: CreateQuestionAnswerRequest,
        idempotency_key: str = Header(..., alias="X-Idempotency-Key", min_length=16, max_length=128, pattern=r"^[A-Za-z0-9_-]+$"),
        current_user: Dict[str, Any] = Depends(get_required_current_user)):
    user = _canonical_comment_user(current_user)
    uid = str(user["_id"])
    _, qid = _answer_question(question_id, uid)
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
    if doc is None:
        candidate = dict(identity, **payload, _id=ObjectId(), created_at=datetime.now(timezone.utc),
            author={"id": uid, "name": user.get("name") or user.get("full_name") or "Saman Athlete",
                    "avatar_url": user.get("avatar_url") or user.get("avatar"), "is_verified": bool(user.get("is_verified", False))})
        try:
            col.insert_one(candidate)
            doc = candidate
        except DuplicateKeyError:
            doc = col.find_one(identity)
    if doc is None:
        raise HTTPException(503, "Answer confirmation unavailable")
    if any(doc.get(k) != v for k, v in payload.items()):
        raise HTTPException(409, "Idempotency key payload conflict")
    if doc.get("is_deleted"):
        raise HTTPException(404, "Answer not found")
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
    answer = _public_answer(_answer_doc(qid, answer_id), uid)
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

    follows_col = get_community_follows_collection()
    if follows_col is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    try:
        follows_col.insert_one({
            "follower_id": current_user_id,
            "following_id": author_id,
            "created_at": datetime.now(timezone.utc),
        })
    except DuplicateKeyError:
        pass  # Idempotent PUT: already following

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

    author_info = _find_author_doc(target_id)
    if not author_info:
        if author_id == "me" and current_user:
            author_info = {
                "id": current_user_id,
                "name": current_user.get("name", "Saman Athlete"),
                "avatar_url": current_user.get("avatar") or current_user.get("custom_avatar"),
                "title": current_user.get("title", "Thành viên Saman"),
                "is_verified": bool(current_user.get("is_verified", False)),
            }
        else:
            raise HTTPException(status_code=404, detail="Author not found")

    follows_col = get_community_follows_collection()
    posts_col = get_community_posts_collection()

    follower_count = 0
    following_count = 0
    post_count = 0
    is_following = False

    if follows_col is not None:
        follower_count = follows_col.count_documents({"following_id": target_id})
        following_count = follows_col.count_documents({"follower_id": target_id})
        if current_user_id and current_user_id != target_id:
            is_following = bool(follows_col.find_one({"follower_id": current_user_id, "following_id": target_id}))

    if posts_col is not None:
        post_count = posts_col.count_documents({
            "$or": [{"author_id": target_id}, {"author.id": target_id}],
            "is_deleted": {"$ne": True},
            "status": {"$in": ["published", None]},
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

    follows_col = get_community_follows_collection()
    if follows_col is None:
        return CommunityFollowListResponse(items=[], next_cursor=None, total_count=0)

    total_count = follows_col.count_documents({"following_id": target_id})

    query: Dict[str, Any] = {"following_id": target_id}
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

    total_count = follows_col.count_documents({"follower_id": target_id})

    query: Dict[str, Any] = {"follower_id": target_id}
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
    query = {"post_id": canonical_id}
    legacy = _legacy_comment_docs(post)
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
    docs = (legacy + list(col.find(query).sort([("created_at", 1), ("_id", 1)]).limit(limit + 1)))[:limit + 1]
    more = len(docs) > limit
    docs = docs[:limit]
    _comment_post(post_id, viewer_id)  # Revalidate before returning nested/public data.
    return CommunityCommentsResponse(
        items=[_public_comment(d, post, viewer_id) for d in docs],
        next_cursor=_encode_cursor(docs[-1]["created_at"], str(docs[-1]["_id"])) if more else None,
        comment_count=col.count_documents({"post_id": canonical_id}) + len(_legacy_comment_docs(post)),
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
    post, canonical_id = _comment_post(post_id, user_id)
    if post.get("type") == "qa" or not post.get("allow_comments", True):
        raise HTTPException(409, "Comments disabled")
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
        if parent.get("parent_comment_id"):
            raise HTTPException(422, "Only one reply level is supported")
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
        except DuplicateKeyError:
            existing = col.find_one(identity)
    if existing is None:
        raise HTTPException(503, "Comment confirmation unavailable")
    if any(existing.get(k) != v for k, v in payload.items()):
        raise HTTPException(409, "Idempotency key payload conflict")
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
        if is_photo: candidate["photo_urls"] = body.photo_urls
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
