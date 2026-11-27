"""Internal maintenance cron endpoints and client error telemetry router."""

from __future__ import annotations

import hmac
import logging
import os
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

from fastapi import APIRouter, Header, HTTPException, Query, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

import backend.app.database as _db_mod
from backend.app.services.r2_retention_service import (
    cleanup_expired_r2_videos,
    scrub_client_error_text,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["Maintenance & Telemetry"])
maintenance_router = router


class ClientErrorReportIn(BaseModel):
    error_type: str = Field(..., min_length=1, max_length=120)
    message: str = Field(..., min_length=1, max_length=1000)
    stack_preview: Optional[str] = None
    app_version: Optional[str] = Field(default=None, max_length=64)
    platform: Optional[str] = Field(default=None, max_length=32)
    screen: Optional[str] = Field(default=None, max_length=200)
    is_fatal: bool = False


def _get_video_stories_collection() -> Any:
    col = getattr(_db_mod, "workout_video_stories_collection", None)
    if col is not None:
        return col
    db_target = _db_mod.get_db() if hasattr(_db_mod, "get_db") else getattr(_db_mod, "db", None)
    if db_target is not None:
        return db_target["workout_video_stories"]
    return None


def _get_client_error_logs_collection() -> Any:
    db_target = getattr(_db_mod, "db", None)
    if db_target is None and hasattr(_db_mod, "get_db"):
        db_target = _db_mod.get_db()
    if db_target is not None:
        return db_target["client_error_logs"]
    return None


def _verify_maintenance_secret(x_maintenance_secret: Optional[str]) -> None:
    """Fail-closed constant-time verification for internal maintenance endpoints."""
    expected = (os.getenv("MAINTENANCE_CRON_SECRET") or "").strip()
    provided = (x_maintenance_secret or "").strip()
    if not expected or not provided or not hmac.compare_digest(provided, expected):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "forbidden",
                "message": "Invalid or unconfigured maintenance secret",
            },
        )


@router.post("/api/internal/maintenance/cleanup-expired-videos")
def trigger_cleanup_expired_videos(
    dry_run: bool = False,
    limit: int = Query(default=200, ge=1, le=1000),
    x_maintenance_secret: Optional[str] = Header(default=None, alias="X-Maintenance-Secret"),
) -> dict[str, Any]:
    """Internal cron endpoint to clean up expired R2 workout video stories."""
    _verify_maintenance_secret(x_maintenance_secret)

    story_col = _get_video_stories_collection()
    if story_col is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "db_unavailable",
                "message": "workout_video_stories collection is unavailable",
            },
        )

    return cleanup_expired_r2_videos(
        story_col,
        dry_run=dry_run,
        batch_limit=limit,
    )


@router.post("/api/telemetry/client-error", status_code=status.HTTP_201_CREATED)
def report_client_error(payload: ClientErrorReportIn) -> JSONResponse:
    """Receive scrubbed client error telemetry without requiring JWT auth."""
    log_id = uuid.uuid4().hex
    doc = {
        "log_id": log_id,
        "error_type": scrub_client_error_text(payload.error_type, max_len=120),
        "message": scrub_client_error_text(payload.message, max_len=1000),
        "stack_preview": (
            scrub_client_error_text(payload.stack_preview, max_len=2000)
            if payload.stack_preview is not None
            else None
        ),
        "app_version": (
            scrub_client_error_text(payload.app_version, max_len=64)
            if payload.app_version is not None
            else None
        ),
        "platform": (
            scrub_client_error_text(payload.platform, max_len=32)
            if payload.platform is not None
            else None
        ),
        "screen": (
            scrub_client_error_text(payload.screen, max_len=200)
            if payload.screen is not None
            else None
        ),
        "is_fatal": bool(payload.is_fatal),
        "created_at": datetime.now(timezone.utc),
    }

    col = _get_client_error_logs_collection()
    if col is None:
        logger.warning(
            "client_error_logs collection unavailable; dropping telemetry report (log_id=%s)",
            log_id,
        )
        return JSONResponse(
            status_code=status.HTTP_202_ACCEPTED,
            content={"accepted": True, "log_id": log_id},
        )

    try:
        col.insert_one(doc)
    except Exception as exc:
        logger.warning(
            "Failed to persist client error telemetry (log_id=%s): %s",
            log_id,
            exc,
        )
        return JSONResponse(
            status_code=status.HTTP_202_ACCEPTED,
            content={"accepted": True, "log_id": log_id},
        )

    return JSONResponse(
        status_code=status.HTTP_201_CREATED,
        content={"accepted": True, "log_id": log_id},
    )
