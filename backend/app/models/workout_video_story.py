"""Pydantic models and constants for Workout Video Stories & Rep Timeline (Phase 3)."""

from __future__ import annotations

from typing import Any, Optional
from pydantic import BaseModel, ConfigDict, Field

MAX_VIDEO_STORY_BYTES: int = 15 * 1024 * 1024  # 15 MB
ALLOWED_VIDEO_CONTENT_TYPES: frozenset[str] = frozenset({"video/mp4", "video/quicktime"})


class RepTimelineItem(BaseModel):
    """Fine-grained kinematic timeline of a single repetition recorded by Workout CV."""

    model_config = ConfigDict(populate_by_name=True)

    rep_index: int = Field(..., alias="repIndex", ge=1)
    start_sec: float = Field(..., alias="startSec", ge=0.0)
    bottom_sec: float = Field(..., alias="bottomSec", ge=0.0)
    end_sec: float = Field(..., alias="endSec", ge=0.0)
    duration_sec: float = Field(..., alias="durationSec", ge=0.0)
    metric_angle_deg: Optional[float] = Field(default=None, alias="metricAngleDeg")
    is_valid: bool = Field(..., alias="isValid")
    issue_type: str = Field(default="none", alias="issueType")
    view_angle: str = Field(default="unknown", alias="viewAngle")
    visibility_confidence: float = Field(default=1.0, alias="visibilityConfidence", ge=0.0, le=1.0)


class VideoStoryPresignRequest(BaseModel):
    """Client request to prepare an authenticated upload slot for a Video Story."""

    model_config = ConfigDict(populate_by_name=True)

    exercise_slug: str = Field(..., alias="exerciseSlug")
    content_type: str = Field(default="video/mp4", alias="contentType")
    size_bytes: int = Field(..., alias="sizeBytes", gt=0)
    duration_sec: float = Field(default=0.0, alias="durationSec", ge=0.0)
    resolution: Optional[str] = Field(default=None)


class VideoStoryPresignResponse(BaseModel):
    """Presigned upload credentials and quota usage status."""

    model_config = ConfigDict(populate_by_name=True)

    story_id: str = Field(..., alias="storyId")
    storage_key: str = Field(..., alias="storageKey")
    upload_url: str = Field(..., alias="uploadUrl")
    public_url: str = Field(..., alias="publicUrl")
    headers: dict[str, str] = Field(default_factory=dict)
    expires_in: int = Field(..., alias="expiresIn")
    limit_mb: int = Field(..., alias="limitMb")
    used_bytes: int = Field(..., alias="usedBytes")


class VideoStoryCompleteRequest(BaseModel):
    """Client request acknowledging completed direct upload to media storage."""

    model_config = ConfigDict(populate_by_name=True)

    story_id: str = Field(..., alias="storyId")
    storage_key: str = Field(..., alias="storageKey")
    video_url: str = Field(..., alias="videoUrl")
    thumbnail_url: Optional[str] = Field(default=None, alias="thumbnailUrl")
    workout_session_id: Optional[str] = Field(default=None, alias="workoutSessionId")
    exercise_slug: str = Field(..., alias="exerciseSlug")
    duration_sec: float = Field(default=0.0, alias="durationSec", ge=0.0)
    size_bytes: int = Field(..., alias="sizeBytes", gt=0)
    resolution: Optional[str] = Field(default=None)
    cv_form_summary: Optional[dict[str, Any]] = Field(default=None, alias="cvFormSummary")
    rep_timeline: list[RepTimelineItem] = Field(default_factory=list, alias="repTimeline")


class VideoStoryCompleteResponse(BaseModel):
    """Acknowledgment of recorded Video Story metadata and updated storage quota."""

    model_config = ConfigDict(populate_by_name=True)

    video_story_id: str = Field(..., alias="videoStoryId")
    video_url: str = Field(..., alias="videoUrl")
    storage_key: str = Field(..., alias="storageKey")
    size_bytes: int = Field(..., alias="sizeBytes")
    used_bytes: int = Field(..., alias="usedBytes")
    limit_mb: int = Field(..., alias="limitMb")
    retention_expires_at: Optional[str] = Field(default=None, alias="retentionExpiresAt")


class VideoStoryDetailResponse(BaseModel):
    """Full detail of a recorded Workout Video Story."""

    model_config = ConfigDict(populate_by_name=True)

    video_story_id: str = Field(..., alias="videoStoryId")
    account_id: str = Field(..., alias="accountId")
    user_id: str = Field(..., alias="userId")
    workout_session_id: Optional[str] = Field(default=None, alias="workoutSessionId")
    exercise_slug: str = Field(..., alias="exerciseSlug")
    date: str
    created_at: str = Field(..., alias="createdAt")
    storage_key: str = Field(..., alias="storageKey")
    video_url: str = Field(..., alias="videoUrl")
    thumbnail_url: Optional[str] = Field(default=None, alias="thumbnailUrl")
    duration_sec: float = Field(..., alias="durationSec")
    size_bytes: int = Field(..., alias="sizeBytes")
    resolution: Optional[str] = Field(default=None)
    retention_expires_at: Optional[str] = Field(default=None, alias="retentionExpiresAt")
    cv_form_summary: Optional[dict[str, Any]] = Field(default=None, alias="cvFormSummary")
    rep_timeline: list[RepTimelineItem] = Field(default_factory=list, alias="repTimeline")
