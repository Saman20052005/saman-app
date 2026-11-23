"""Bounded, principal-scoped story_logs and community context for Pro 3 chat requests (CP3.2)."""

from datetime import datetime
from typing import Any, Dict, List, Optional

from bson import ObjectId

try:
    from backend.app.services.context_utils import (
        build_user_query,
        normalize_email,
        utc_to_vn_date_str,
    )
except ImportError:
    from app.services.context_utils import (
        build_user_query,
        normalize_email,
        utc_to_vn_date_str,
    )


_STORY_LOGS_PROJECTION: Dict[str, int] = {
    "_id": 0,
    "date": 1,
    "logged_at": 1,
    "meal_type": 1,
    "food_name": 1,
    "food_label": 1,
    "calories": 1,
    "protein": 1,
    "carbs": 1,
    "fat": 1,
    "note": 1,
    "created_at": 1,
}


def _number(value: Any) -> Optional[Any]:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return value
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _sort_timestamp_key(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.isoformat()
    return str(value)


def _extract_date_str(row: Dict[str, Any]) -> str:
    raw_date = row.get("date")
    if raw_date is not None:
        if isinstance(raw_date, datetime):
            return utc_to_vn_date_str(raw_date) or ""
        date_str = str(raw_date).strip()[:10]
        if date_str:
            return date_str

    for fallback_field in ("logged_at", "created_at"):
        raw_ts = row.get(fallback_field)
        if raw_ts is not None:
            if isinstance(raw_ts, datetime):
                return utc_to_vn_date_str(raw_ts) or ""
            ts_str = str(raw_ts).strip()[:10]
            if ts_str:
                return ts_str

    return ""


def _safe_find(collection: Any, query: Dict[str, Any], projection: Optional[Dict[str, Any]] = None) -> Any:
    if projection is not None:
        try:
            return collection.find(query, projection)
        except TypeError:
            return collection.find(query)
    return collection.find(query)


def _safe_sort(cursor: Any, sort_spec: List[tuple]) -> Any:
    if not hasattr(cursor, "sort"):
        return cursor
    try:
        return cursor.sort(sort_spec)
    except TypeError:
        if sort_spec:
            first_field, first_dir = sort_spec[0]
            try:
                return cursor.sort(first_field, first_dir)
            except Exception:
                return cursor
        return cursor
    except Exception:
        return cursor


def _safe_limit(cursor: Any, limit_count: int) -> Any:
    if hasattr(cursor, "limit"):
        try:
            return cursor.limit(limit_count)
        except Exception:
            return cursor
    return cursor


def _extract_identity_id(principal: Optional[Dict[str, Any]]) -> Any:
    if not isinstance(principal, dict):
        return None
    for key in ("identity_id", "_id", "user_id", "id"):
        val = principal.get(key)
        if val is not None and str(val).strip():
            return val
    return None


def build_story_logs_context(
    *,
    principal: dict,
    story_logs_collection,
    tier: str = "core3",
    now=None,
) -> dict:
    """Read bounded, PII-free story_logs context exclusively for Pro 3 tier."""
    norm_tier = (tier or "core3").strip().lower()
    if norm_tier != "pro3":
        return {"status": "skipped", "coverage_missing": False, "entries": []}

    if not isinstance(principal, dict):
        principal = {}
    identity_id = _extract_identity_id(principal)
    email = normalize_email(principal.get("email"))
    user_query = build_user_query(identity_id, email)

    if story_logs_collection is None or user_query == {"_id": None}:
        return {"status": "unavailable", "coverage_missing": True, "entries": []}

    try:
        cursor = _safe_find(story_logs_collection, user_query, _STORY_LOGS_PROJECTION)
        cursor = _safe_sort(cursor, [("logged_at", -1), ("created_at", -1)])
        cursor = _safe_limit(cursor, 5)
        raw_rows = [row for row in list(cursor) if isinstance(row, dict)]
        raw_rows.sort(
            key=lambda r: (
                _sort_timestamp_key(r.get("logged_at") or r.get("created_at")),
                _sort_timestamp_key(r.get("created_at")),
            ),
            reverse=True,
        )

        entries: List[Dict[str, Any]] = []
        for row in raw_rows[:5]:
            food_name = str(row.get("food_name") or row.get("food_label") or "")[:80]
            note = str(row.get("note") or "")[:150]
            entries.append(
                {
                    "date": _extract_date_str(row),
                    "meal_type": str(row.get("meal_type") or ""),
                    "food_name": food_name,
                    "calories": _number(row.get("calories")),
                    "protein": _number(row.get("protein")),
                    "carbs": _number(row.get("carbs")),
                    "fat": _number(row.get("fat")),
                    "note": note,
                }
            )

        return {
            "status": "available" if entries else "empty",
            "coverage_missing": not bool(entries),
            "entries": entries[:5],
        }
    except Exception:
        return {"status": "unavailable", "coverage_missing": True, "entries": []}


def _matches_post_author(doc: Dict[str, Any], uid_str: str) -> bool:
    author_obj = doc.get("author") if isinstance(doc.get("author"), dict) else {}
    candidates = (
        doc.get("author_id"),
        doc.get("user_id"),
        author_obj.get("id"),
        author_obj.get("_id"),
    )
    return any(c is not None and str(c).strip() == uid_str for c in candidates)


def _extract_post_author_id(doc: Dict[str, Any]) -> str:
    author_obj = doc.get("author") if isinstance(doc.get("author"), dict) else {}
    raw_author_id = (
        doc.get("author_id")
        or author_obj.get("id")
        or author_obj.get("_id")
        or doc.get("user_id")
    )
    return str(raw_author_id).strip() if raw_author_id is not None else ""


def _can_view_saved_post(
    doc: Dict[str, Any],
    uid_str: str,
    community_follows_collection: Any,
) -> bool:
    """Fail-closed audience enforcement matching community.py."""
    if doc.get("is_deleted") is True or doc.get("status") == "unpublished":
        return False
    if doc.get("status") not in ("published", None):
        return False

    privacy = str(doc.get("privacy") or "public").strip().lower()
    author_id = _extract_post_author_id(doc)

    if privacy == "public":
        return True
    if privacy == "private":
        return bool(author_id and author_id == uid_str)
    if privacy == "followers_only":
        if author_id and author_id == uid_str:
            return True
        if not author_id or community_follows_collection is None:
            return False
        try:
            return bool(
                community_follows_collection.find_one(
                    {"follower_id": uid_str, "following_id": author_id}
                )
            )
        except Exception:
            return False

    return False


def build_community_context(
    *,
    principal: dict,
    community_posts_collection,
    community_interactions_collection,
    community_follows_collection=None,
    tier: str = "core3",
) -> dict:
    """Read bounded, audience-enforced community context exclusively for Pro 3 tier."""
    norm_tier = (tier or "core3").strip().lower()
    if norm_tier != "pro3":
        return {
            "status": "skipped",
            "coverage_missing": False,
            "questions": [],
            "saved_posts": [],
        }

    if not isinstance(principal, dict):
        principal = {}
    identity_id = _extract_identity_id(principal)
    uid_str = str(identity_id).strip() if identity_id is not None else ""

    if (
        community_posts_collection is None
        and community_interactions_collection is None
    ) or not uid_str:
        return {
            "status": "unavailable",
            "coverage_missing": True,
            "questions": [],
            "saved_posts": [],
        }

    uid_obj = ObjectId(uid_str) if ObjectId.is_valid(uid_str) else None
    questions: List[Dict[str, Any]] = []
    saved_posts: List[Dict[str, Any]] = []

    # Part A: User's own Q&A questions in community_posts
    if community_posts_collection is not None:
        try:
            author_clauses: List[Dict[str, Any]] = [
                {"author_id": uid_str},
                {"user_id": uid_str},
                {"author.id": uid_str},
            ]
            if uid_obj is not None:
                author_clauses.extend(
                    [
                        {"author_id": uid_obj},
                        {"user_id": uid_obj},
                        {"author.id": uid_obj},
                    ]
                )

            qa_query: Dict[str, Any] = {
                "type": "qa",
                "is_deleted": {"$ne": True},
                "status": {"$in": ["published", None]},
                "$or": author_clauses,
            }
            qa_cursor = _safe_find(community_posts_collection, qa_query)
            qa_cursor = _safe_sort(qa_cursor, [("created_at", -1), ("_id", -1)])
            qa_cursor = _safe_limit(qa_cursor, 10)
            raw_qa_docs = [
                d
                for d in list(qa_cursor)
                if isinstance(d, dict)
                and d.get("type") == "qa"
                and d.get("is_deleted") is not True
                and d.get("status") in ("published", None)
                and _matches_post_author(d, uid_str)
            ]
            raw_qa_docs.sort(
                key=lambda d: _sort_timestamp_key(d.get("created_at")),
                reverse=True,
            )

            for doc in raw_qa_docs[:3]:
                qa_info = doc.get("qa_info") if isinstance(doc.get("qa_info"), dict) else {}
                raw_details = (
                    qa_info.get("details")
                    if qa_info.get("details") is not None
                    else (doc.get("details") or doc.get("body") or "")
                )
                raw_rc = (
                    qa_info.get("respondent_count")
                    if "respondent_count" in qa_info
                    else doc.get("respondent_count", 0)
                )
                questions.append(
                    {
                        "topic": str(doc.get("topic") or qa_info.get("topic") or ""),
                        "category_tag": str(
                            qa_info.get("category_tag") or doc.get("category_tag") or ""
                        ),
                        "question": str(
                            qa_info.get("question")
                            or doc.get("question")
                            or doc.get("title")
                            or doc.get("caption")
                            or ""
                        )[:150],
                        "details": str(raw_details or "")[:160],
                        "respondent_count": int(_number(raw_rc) or 0),
                    }
                )
        except Exception:
            pass

    # Part B: Up to 3 recently saved posts with fail-closed audience enforcement
    if (
        community_posts_collection is not None
        and community_interactions_collection is not None
    ):
        try:
            inter_cursor = _safe_find(
                community_interactions_collection,
                {"user_id": uid_str, "interaction_type": "save"},
            )
            inter_cursor = _safe_sort(inter_cursor, [("created_at", -1)])
            inter_cursor = _safe_limit(inter_cursor, 10)
            raw_inters = [
                i
                for i in list(inter_cursor)
                if isinstance(i, dict)
                and str(i.get("user_id") or "").strip() == uid_str
                and i.get("interaction_type") == "save"
                and i.get("post_id") is not None
            ]
            raw_inters.sort(
                key=lambda i: _sort_timestamp_key(i.get("created_at")),
                reverse=True,
            )
            recent_inters = raw_inters[:10]

            post_ids: List[str] = []
            for inter in recent_inters:
                pid = str(inter.get("post_id")).strip()
                if pid and pid not in post_ids:
                    post_ids.append(pid)

            if post_ids:
                or_clauses: List[Dict[str, Any]] = []
                for pid in post_ids:
                    if ObjectId.is_valid(pid):
                        or_clauses.append({"_id": ObjectId(pid)})
                    or_clauses.append({"id": pid})
                    or_clauses.append({"_id": pid})

                raw_posts = [
                    p
                    for p in list(_safe_find(community_posts_collection, {"$or": or_clauses}))
                    if isinstance(p, dict)
                ]
                posts_by_id: Dict[str, Dict[str, Any]] = {}
                for p in raw_posts:
                    if p.get("id") is not None:
                        posts_by_id[str(p.get("id"))] = p
                    if p.get("_id") is not None:
                        posts_by_id[str(p.get("_id"))] = p

                for pid in post_ids:
                    p_doc = posts_by_id.get(pid)
                    if p_doc is None and hasattr(community_posts_collection, "find_one"):
                        p_clauses: List[Dict[str, Any]] = [{"id": pid}, {"_id": pid}]
                        if ObjectId.is_valid(pid):
                            p_clauses.insert(0, {"_id": ObjectId(pid)})
                        found = community_posts_collection.find_one({"$or": p_clauses})
                        if isinstance(found, dict):
                            p_doc = found

                    if not isinstance(p_doc, dict):
                        continue

                    if not _can_view_saved_post(
                        p_doc, uid_str, community_follows_collection
                    ):
                        continue

                    post_type = str(p_doc.get("type") or "photo")
                    saved_item: Dict[str, Any] = {
                        "type": post_type,
                        "topic": str(p_doc.get("topic") or ""),
                        "caption": str(p_doc.get("caption") or "")[:180],
                    }

                    if post_type == "qa":
                        qa_info = (
                            p_doc.get("qa_info")
                            if isinstance(p_doc.get("qa_info"), dict)
                            else {}
                        )
                        saved_item["question"] = str(
                            qa_info.get("question")
                            or p_doc.get("question")
                            or p_doc.get("title")
                            or ""
                        )[:150]

                    workout_attachment = (
                        p_doc.get("workout_attachment")
                        if isinstance(p_doc.get("workout_attachment"), dict)
                        else {}
                    )
                    attachment_snapshot = (
                        p_doc.get("attachment_snapshot")
                        if isinstance(p_doc.get("attachment_snapshot"), dict)
                        else {}
                    )
                    workout_title = workout_attachment.get(
                        "title"
                    ) or attachment_snapshot.get("title")
                    if workout_title:
                        saved_item["workout_title"] = str(workout_title)[:120]

                    saved_posts.append(saved_item)
                    if len(saved_posts) >= 3:
                        break
        except Exception:
            pass

    has_data = bool(questions or saved_posts)
    return {
        "status": "available" if has_data else "empty",
        "coverage_missing": not has_data,
        "questions": questions,
        "saved_posts": saved_posts,
    }
