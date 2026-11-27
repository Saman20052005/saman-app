"""R2 expired workout video retention cleanup and client error telemetry helpers."""

from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from typing import Any, Optional

from backend.app.services.media_storage_service import get_media_storage_service

logger = logging.getLogger(__name__)

CLIENT_ERROR_TTL_SECONDS = 30 * 24 * 3600
CLIENT_ERROR_TTL_INDEX_NAME = "ttl_client_error_logs_30d"

_JWT_RE = re.compile(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+")
_BEARER_RE = re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+")
_EMAIL_RE = re.compile(r"[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}")
_GOOGLE_API_KEY_RE = re.compile(r"AIza[0-9A-Za-z_-]+")
_SENSITIVE_KV_RE = re.compile(r"(?i)(key|token|password|secret)=[^&\s]+")


def _parse_utc_datetime(val: Any) -> Optional[datetime]:
    """Parse a datetime or ISO-8601 string into a timezone-aware UTC datetime.

    Returns None if val is None, unsupported, or cannot be parsed.
    """
    if val is None or isinstance(val, bool):
        return None

    if isinstance(val, datetime):
        if val.tzinfo is None:
            return val.replace(tzinfo=timezone.utc)
        return val.astimezone(timezone.utc)

    if isinstance(val, str):
        raw = val.strip()
        if not raw:
            return None
        if raw.endswith(("Z", "z")):
            raw = f"{raw[:-1]}+00:00"
        try:
            parsed = datetime.fromisoformat(raw)
        except ValueError:
            return None
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)

    return None


def _to_iso_utc_z(dt: datetime) -> str:
    aware = dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt.astimezone(timezone.utc)
    return aware.isoformat().replace("+00:00", "Z")


def _build_story_update_filter(doc: dict[str, Any]) -> Optional[dict[str, Any]]:
    if "_id" in doc and doc["_id"] is not None:
        return {"_id": doc["_id"]}
    if doc.get("story_id"):
        return {"story_id": doc["story_id"]}
    if doc.get("storage_key"):
        return {"storage_key": doc["storage_key"]}
    return None


def cleanup_expired_r2_videos(
    video_stories_collection: Any,
    *,
    media_storage: Any = None,
    now_utc: Optional[datetime] = None,
    dry_run: bool = False,
    batch_limit: int = 200,
) -> dict[str, Any]:
    """Delete expired workout video stories from object storage and mark them deleted in MongoDB.

    Handles both ISO-8601 UTC strings ("...Z") and BSON datetime values for `retention_expires_at`,
    and always double-checks expiration in Python before deleting.
    """
    if video_stories_collection is None:
        raise RuntimeError("workout_video_stories collection is unavailable")

    now_dt = _parse_utc_datetime(now_utc) if now_utc is not None else datetime.now(timezone.utc)
    if now_dt is None:
        raise ValueError(f"Invalid now_utc value: {now_utc!r}")

    now_iso_z = _to_iso_utc_z(now_dt)
    effective_limit = max(1, int(batch_limit))

    query = {
        "$and": [
            {
                "$or": [
                    {"deleted_at": {"$exists": False}},
                    {"deleted_at": None},
                ]
            },
            {"retention_expires_at": {"$ne": None}},
            {
                "$or": [
                    {"retention_expires_at": {"$lte": now_iso_z}},
                    {"retention_expires_at": {"$lte": now_dt}},
                ]
            },
        ]
    }

    cursor = video_stories_collection.find(query)
    if hasattr(cursor, "limit"):
        cursor = cursor.limit(effective_limit)

    scanned = 0
    eligible = 0
    deleted = 0
    failed = 0
    freed_bytes = 0
    storage = media_storage

    for doc in cursor:
        if scanned >= effective_limit:
            break
        scanned += 1

        if not isinstance(doc, dict):
            continue

        # Never re-delete already soft-deleted records (idempotent)
        if doc.get("deleted_at") is not None:
            continue

        # Double-check expiration timestamp in Python; never delete None/unparseable values
        expires_at = _parse_utc_datetime(doc.get("retention_expires_at"))
        if expires_at is None or expires_at > now_dt:
            continue

        eligible += 1
        raw_size = doc.get("size_bytes")
        try:
            size_bytes = max(0, int(raw_size or 0))
        except (TypeError, ValueError):
            size_bytes = 0

        if dry_run:
            freed_bytes += size_bytes
            continue

        storage_key = str(doc.get("storage_key") or "").strip()
        if not storage_key:
            logger.warning(
                "Skipping expired video story without storage_key (story_id=%r)",
                doc.get("story_id"),
            )
            failed += 1
            continue

        if storage is None:
            storage = get_media_storage_service()

        try:
            delete_ok = bool(storage.delete_object(storage_key))
        except Exception as exc:
            logger.warning(
                "Failed to delete expired R2 video object %s (story_id=%r): %s",
                storage_key,
                doc.get("story_id"),
                exc,
            )
            failed += 1
            continue

        if not delete_ok:
            logger.warning(
                "Media storage delete_object returned False for %s (story_id=%r)",
                storage_key,
                doc.get("story_id"),
            )
            failed += 1
            continue

        doc_filter = _build_story_update_filter(doc)
        if doc_filter is None:
            logger.warning("Cannot mark expired video story deleted: missing document identifier")
            failed += 1
            continue

        try:
            video_stories_collection.update_one(
                doc_filter,
                {
                    "$set": {
                        "deleted_at": now_iso_z,
                        "storage_deleted": True,
                    }
                },
            )
        except Exception as exc:
            logger.warning(
                "Deleted object %s but failed to mark DB record deleted (story_id=%r): %s",
                storage_key,
                doc.get("story_id"),
                exc,
            )
            failed += 1
            continue

        deleted += 1
        freed_bytes += size_bytes

    return {
        "dry_run": bool(dry_run),
        "scanned": scanned,
        "eligible": eligible,
        "deleted": deleted,
        "failed": failed,
        "freed_bytes": freed_bytes,
        "executed_at": now_iso_z,
    }


def scrub_client_error_text(text: Optional[str], *, max_len: int = 2000) -> str:
    """Scrub PII and secrets (JWT, Bearer tokens, emails, API keys, query secrets) and truncate."""
    if text is None:
        return ""

    cleaned = str(text)
    cleaned = _JWT_RE.sub("[REDACTED_JWT]", cleaned)
    cleaned = _BEARER_RE.sub("Bearer [REDACTED]", cleaned)
    cleaned = _EMAIL_RE.sub("[REDACTED_EMAIL]", cleaned)
    cleaned = _GOOGLE_API_KEY_RE.sub("[REDACTED_KEY]", cleaned)
    cleaned = _SENSITIVE_KV_RE.sub(r"\1=[REDACTED]", cleaned)

    if max_len <= 0:
        return ""
    return cleaned[:max_len]


def ensure_client_error_ttl_index(collection: Any) -> str:
    """Ensure a 30-day MongoDB TTL index on `client_error_logs.created_at`."""
    if collection is None:
        raise RuntimeError("client_error_logs collection is unavailable")

    return collection.create_index(
        [("created_at", 1)],
        expireAfterSeconds=CLIENT_ERROR_TTL_SECONDS,
        name=CLIENT_ERROR_TTL_INDEX_NAME,
    )
