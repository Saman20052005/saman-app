# [File: backend/app/models/workout_cv_telemetry.py]
from datetime import datetime, timezone
from typing import Optional, Set
from pydantic import BaseModel, ConfigDict, Field

MAX_CV_TELEMETRY_PAYLOAD_BYTES: int = 256 * 1024  # 256 KB
ALLOWED_TELEMETRY_ENCODINGS: Set[str] = {"gzip_json_b64", "json_compact"}


class WorkoutCvTelemetryIn(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    exercise_slug: str = Field(..., min_length=1, alias="exerciseSlug")
    view_angle: str = Field(default="unknown", alias="viewAngle")
    fps: float = Field(default=30.0, gt=0.0, le=120.0)
    frame_count: int = Field(..., alias="frameCount", ge=1, le=6000)
    cv_reps: int = Field(..., alias="cvReps", ge=0, le=500)
    final_logged_reps: Optional[int] = Field(default=None, alias="finalLoggedReps", ge=0, le=500)
    user_adjusted_reps: bool = Field(default=False, alias="userAdjustedReps")
    ml_mode: str = Field(default="ruleBased", alias="mlMode")
    payload_encoding: str = Field(default="gzip_json_b64", alias="payloadEncoding")
    compressed_payload_b64: str = Field(..., alias="compressedPayloadB64")
    client_schema_version: str = Field(default="v1", alias="clientSchemaVersion")


class WorkoutCvTelemetryOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    telemetry_id: str = Field(..., alias="telemetryId")
    subject_hash: str = Field(..., alias="subjectHash")
    exercise_slug: str = Field(..., alias="exerciseSlug")
    frame_count: int = Field(..., alias="frameCount")
    payload_bytes: int = Field(..., alias="payloadBytes")
    user_adjusted_reps: bool = Field(..., alias="userAdjustedReps")
    priority_bucket: str = Field(..., alias="priorityBucket")
    created_at: str = Field(..., alias="createdAt")


class WorkoutCvTelemetryStatsOut(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    cv_telemetry_opt_in: bool = Field(..., alias="cvTelemetryOptIn")
    total_clips_contributed: int = Field(..., alias="totalClipsContributed")
    rep_correction_clips: int = Field(..., alias="repCorrectionClips")
    subject_hash: str = Field(..., alias="subjectHash")
