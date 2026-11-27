# [File: routers/workout.py]
from fastapi import APIRouter, Body, Depends, HTTPException, Query, status
from datetime import datetime, date, timedelta, timezone
from zoneinfo import ZoneInfo
from typing import Optional, List, Dict, Any, Literal, Tuple
import hashlib
import logging
import math
import os
import re
import base64
import gzip
import json
from uuid import uuid4
import pydantic as pd
from bson import ObjectId
from pymongo.errors import DuplicateKeyError

# Import dependencies
from backend.auth_utils import verify_token, get_current_user
from backend.app.repositories.user_repository import UserRepository
import backend.app.database as _db_mod
from backend.app.database import (
    workout_history_collection,
    custom_plans_collection,
    exercises_collection,
)
workout_video_stories_collection = getattr(_db_mod, "workout_video_stories_collection", None)
workout_cv_telemetry_collection = getattr(_db_mod, "workout_cv_telemetry_collection", None)
from backend.app.models.workout_cv_telemetry import (
    MAX_CV_TELEMETRY_PAYLOAD_BYTES,
    ALLOWED_TELEMETRY_ENCODINGS,
    WorkoutCvTelemetryIn,
    WorkoutCvTelemetryOut,
    WorkoutCvTelemetryStatsOut,
)
from backend.app.services.workout_recovery_helper import calculate_muscle_recovery_load
from backend.app.services.context_utils import (
    build_user_query,
    get_vn_date_str,
    get_vn_day_range_utc,
    normalize_email,
    utc_to_vn_date_str,
)
from backend.app.models.workout_video_story import (
    ALLOWED_VIDEO_CONTENT_TYPES,
    MAX_VIDEO_STORY_BYTES,
    RepTimelineItem,
    VideoStoryCompleteRequest,
    VideoStoryCompleteResponse,
    VideoStoryDetailResponse,
    VideoStoryPresignRequest,
    VideoStoryPresignResponse,
)
from backend.app.services.media_storage_service import (
    ALLOWED_STORAGE_PREFIXES,
    MediaStorageConfigError,
    get_media_storage_service,
)
from backend.app.services.quota_service import (
    get_video_citation_days,
    get_video_story_storage_limit_mb,
)

try:
    from backend.app.services.revenue_guard import is_ai_paywall_enabled
except ImportError:
    try:
        from app.services.revenue_guard import is_ai_paywall_enabled
    except ImportError:  # pragma: no cover
        is_ai_paywall_enabled = None

if not callable(is_ai_paywall_enabled):
    def is_ai_paywall_enabled() -> bool:
        return os.getenv("ENABLE_AI_PAYWALL", "false").strip().lower() in ("1", "true", "yes", "on")

try:
    from backend.app.services.entitlement_service import EntitlementService
    from backend.app.models.revenue import EntitlementDecisionStatus, ReservationStatus
    from backend.app.database_revenue import COLL_USAGE_BUCKETS
    from backend.app.services.quota_service import (
        TIER_QUOTA_LIMITS,
        QuotaService,
        StorageUnavailableException as QuotaStorageUnavailableException,
        resolve_user_tier_and_quota,
    )
    from backend.app.services.revenuecat_adapter import resolve_or_create_account_id
except ImportError:
    try:
        from app.services.entitlement_service import EntitlementService
        from app.models.revenue import EntitlementDecisionStatus, ReservationStatus
        from app.database_revenue import COLL_USAGE_BUCKETS
        from app.services.quota_service import (
            TIER_QUOTA_LIMITS,
            QuotaService,
            StorageUnavailableException as QuotaStorageUnavailableException,
            resolve_user_tier_and_quota,
        )
        from app.services.revenuecat_adapter import resolve_or_create_account_id
    except ImportError:  # pragma: no cover
        EntitlementService = None
        EntitlementDecisionStatus = None
        ReservationStatus = None
        COLL_USAGE_BUCKETS = "revenue_usage_buckets"
        TIER_QUOTA_LIMITS = {}
        QuotaService = None
        QuotaStorageUnavailableException = None
        resolve_user_tier_and_quota = None
        resolve_or_create_account_id = None

logger = logging.getLogger(__name__)
WORKOUT_CV_BENEFIT_ID = "workout.cv.ai"

try:
    from zoneinfo import ZoneInfo
    ICT_ZONE = ZoneInfo("Asia/Ho_Chi_Minh")
except Exception:
    ICT_ZONE = timezone(timedelta(hours=7))

router = APIRouter(prefix="/api/workouts", tags=["Workouts"])

# Initialize services
user_repo = UserRepository()

@router.get("/exercises", response_model=dict)
async def get_exercises(
    muscle_group: Optional[str] = None,
    difficulty: Optional[str] = None,
    equipment: Optional[str] = None,
    search: Optional[str] = None,
    skip: int = 0,
    limit: int = 20,
):
    try:
        if exercises_collection is None:
            raise HTTPException(status_code=503, detail="Database unavailable")

        # Build query filter
        query = {}
        if muscle_group:
            query["muscleGroup"] = muscle_group.lower()
        if difficulty:
            query["difficulty"] = difficulty.lower()
        if equipment:
            query["equipment"] = equipment.lower()
        if search:
            query["$or"] = [
                {"name": {"$regex": search, "$options": "i"}},
                {"nameVi": {"$regex": search, "$options": "i"}},
            ]

        exercises = _safe_find(
            exercises_collection,
            query,
            skip=skip,
            limit=limit,
        )
        exercises = [_serialize_mongo(e) for e in exercises]
        total = _safe_count(exercises_collection, query)

        return {
            "exercises": exercises,
            "total": total,
            "skip": skip,
            "limit": limit,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch exercises: {str(e)}")

def _serialize_mongo(value: Any) -> Any:
    if isinstance(value, ObjectId):
        return str(value)
    if isinstance(value, datetime):
        return value.isoformat()
    if isinstance(value, dict):
        return {k: _serialize_mongo(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_serialize_mongo(v) for v in value]
    return value

def _safe_find(collection, query: dict, *, sort=None, skip: int = 0, limit: Optional[int] = None) -> List[dict]:
    if collection is None:
        return []
    cursor = collection.find(query)
    if sort is not None:
        cursor = cursor.sort(sort)
    if skip:
        cursor = cursor.skip(skip)
    if limit is not None:
        cursor = cursor.limit(limit)
    return list(cursor)

def _safe_count(collection, query: dict) -> int:
    if collection is None:
        return 0
    return int(collection.count_documents(query))

def _extract_weight_kg(item: dict) -> float:
    for k in ("weight_kg", "weightKg", "weight"):
        v = item.get(k)
        if v is not None:
            try:
                return float(v)
            except (ValueError, TypeError):
                pass
    return 0.0

def _extract_reps(item: dict) -> int:
    for k in ("reps_completed", "repsCompleted", "reps"):
        v = item.get(k)
        if v is not None:
            try:
                return int(v)
            except (ValueError, TypeError):
                pass
    return 0

def _extract_set_number(item: dict, default: int = 1) -> int:
    for k in ("set_number", "setNumber"):
        v = item.get(k)
        if v is not None:
            try:
                return int(v)
            except (ValueError, TypeError):
                pass
    return default

def _is_set_completed(item: dict) -> bool:
    for k in ("is_completed", "isCompleted"):
        if k in item and item[k] is not None:
            return bool(item[k])
    return True

def _extract_session_date(session: dict) -> Optional[str]:
    d = session.get("date")
    if isinstance(d, str) and len(d) >= 10:
        return d[:10]
    if isinstance(d, datetime):
        return utc_to_vn_date_str(d)
    dt = session.get("started_at") or session.get("created_at") or session.get("start_time")
    if isinstance(dt, datetime):
        return utc_to_vn_date_str(dt)
    if isinstance(dt, str) and len(dt) >= 10:
        return dt[:10]
    return None

def _safe_non_neg_int(val: Any) -> int:
    if val is None or isinstance(val, bool):
        return 0
    try:
        return max(0, int(val))
    except (ValueError, TypeError):
        return 0


def _is_cv_detected(item: dict) -> bool:
    for k in ("cv_detected", "cvDetected"):
        if k in item and item[k] is not None:
            return bool(item[k])
    return False


def _compute_cv_form_metrics(
    matching_logs: List[Tuple[int, dict]],
    session: dict,
) -> Optional[Dict[str, Any]]:
    valid_reps = 0
    fast_reps = 0
    abort_count = 0
    sum_reps_in_cv_logs = 0
    found_cv = False

    for entry in matching_logs:
        item = entry[1] if isinstance(entry, tuple) and len(entry) == 2 else entry
        if not isinstance(item, dict):
            continue
        summary = item.get("cv_form_summary") or item.get("cvFormSummary")
        if isinstance(summary, dict) and summary:
            found_cv = True
            valid_reps += _safe_non_neg_int(summary.get("valid_reps"))
            fast_reps += _safe_non_neg_int(summary.get("fast_reps"))
            abort_count += _safe_non_neg_int(summary.get("abort_count"))
            sum_reps_in_cv_logs += max(0, _extract_reps(item))

    if not found_cv and isinstance(session, dict):
        session_summary = session.get("cv_form_summary") or session.get("cvFormSummary")
        if isinstance(session_summary, dict) and session_summary:
            raw_logs = session.get("exercise_logs") or session.get("completed_exercises") or []
            matched_items = [
                entry[1] if isinstance(entry, tuple) and len(entry) == 2 else entry
                for entry in matching_logs
            ]
            any_cv_detected = any(
                isinstance(item, dict) and _is_cv_detected(item)
                for item in matched_items
            )
            other_log_has_summary = any(
                isinstance(log, dict)
                and bool(log.get("cv_form_summary") or log.get("cvFormSummary"))
                for log in raw_logs
            )
            all_logs_belong_to_exercise = len(raw_logs) == len(matched_items) and len(matched_items) > 0

            if any_cv_detected or (not other_log_has_summary and all_logs_belong_to_exercise):
                found_cv = True
                valid_reps = _safe_non_neg_int(session_summary.get("valid_reps"))
                fast_reps = _safe_non_neg_int(session_summary.get("fast_reps"))
                abort_count = _safe_non_neg_int(session_summary.get("abort_count"))
                if any_cv_detected:
                    for item in matched_items:
                        if isinstance(item, dict) and _is_cv_detected(item):
                            sum_reps_in_cv_logs += max(0, _extract_reps(item))
                elif len(matched_items) == 1 and isinstance(matched_items[0], dict):
                    sum_reps_in_cv_logs = max(0, _extract_reps(matched_items[0]))

    if not found_cv:
        return None

    denom = max(sum_reps_in_cv_logs, valid_reps + fast_reps)
    if denom <= 0:
        return None

    raw_score = int(round((valid_reps / denom) * 100))
    if abort_count >= 2:
        raw_score -= min(15, abort_count * 5)
    form_score = max(0, min(100, raw_score))
    fast_ratio = fast_reps / denom

    return {
        "form_score": form_score,
        "fast_reps": fast_reps,
        "fast_ratio": fast_ratio,
        "valid_reps": valid_reps,
        "abort_count": abort_count,
    }


def _find_last_performance_for_exercise(sessions: List[dict], target_id: str) -> Optional[dict]:
    clean_target = target_id.strip()
    if not clean_target:
        return None

    for session in sessions:
        raw_logs = session.get("exercise_logs") or session.get("completed_exercises") or []
        matching_logs = []
        for idx, item in enumerate(raw_logs):
            if not isinstance(item, dict):
                continue
            ex_id = str(item.get("exercise_id") or item.get("exerciseId") or "")
            ex_slug = str(item.get("exercise_slug") or item.get("exerciseSlug") or "")
            if ex_id == clean_target or ex_slug == clean_target:
                matching_logs.append((idx + 1, item))

        if not matching_logs:
            continue

        all_sets_completed = len(matching_logs) > 0 and all(
            _is_set_completed(item) for _, item in matching_logs
        )

        completed_logs = [(idx, item) for idx, item in matching_logs if _is_set_completed(item)]
        candidates = completed_logs if completed_logs else matching_logs

        def _sort_key(entry):
            idx, item = entry
            s_num = _extract_set_number(item, default=idx)
            return (_extract_weight_kg(item), _extract_reps(item), s_num)

        _, best_set = max(candidates, key=_sort_key)
        last_weight_kg = _extract_weight_kg(best_set)
        last_reps = _extract_reps(best_set)

        cv_metrics = _compute_cv_form_metrics(matching_logs, session)
        if cv_metrics is not None:
            form_score = cv_metrics["form_score"]
            fast_reps = cv_metrics["fast_reps"]
            fast_ratio = cv_metrics["fast_ratio"]
            if (
                form_score >= 85
                and fast_ratio <= 0.25
                and all_sets_completed
                and last_reps >= 8
            ):
                if last_weight_kg > 0:
                    suggested_weight_kg = round(last_weight_kg + 2.5, 1)
                    suggested_reps = last_reps
                    suggestion_reason = "cv_form_verified_add_weight"
                else:
                    suggested_weight_kg = 0.0
                    suggested_reps = last_reps + 1
                    suggestion_reason = "cv_form_verified_add_rep"
            elif form_score < 70:
                suggested_weight_kg = last_weight_kg
                suggested_reps = last_reps
                suggestion_reason = "cv_form_refine_technique"
            else:
                suggested_weight_kg = last_weight_kg
                suggested_reps = last_reps
                suggestion_reason = "maintain_current_load"
        else:
            form_score = None
            fast_reps = None
            if all_sets_completed and last_reps >= 8:
                if last_weight_kg > 0:
                    suggested_weight_kg = round(last_weight_kg + 2.5, 1)
                    suggested_reps = last_reps
                    suggestion_reason = "completed_target_add_weight"
                else:
                    suggested_weight_kg = 0.0
                    suggested_reps = last_reps + 1
                    suggestion_reason = "completed_target_add_rep"
            else:
                suggested_weight_kg = last_weight_kg
                suggested_reps = last_reps
                suggestion_reason = "maintain_current_load"

        last_date = _extract_session_date(session)

        return {
            "exercise_id": clean_target,
            "last_weight_kg": last_weight_kg,
            "last_reps": last_reps,
            "suggested_weight_kg": suggested_weight_kg,
            "suggested_reps": suggested_reps,
            "suggestion_reason": suggestion_reason,
            "last_date": last_date,
            "cv_form_score": form_score,
            "cv_fast_reps": fast_reps,
        }

    return None

class ExerciseOut(pd.BaseModel):
    id: str
    slug: str
    name: str
    nameVi: Optional[str] = None
    muscleGroup: str
    targetMuscles: List[str]
    secondaryMuscles: List[str]
    equipment: List[str]
    difficulty: str  # 'beginner', 'intermediate', 'advanced'
    thumbnailUrl: Optional[str] = None
    youtubeVideoId: Optional[str] = None
    cues: List[str] = []
    commonMistakes: List[str] = []
    defaultSets: int
    restSeconds: int
    defaultReps: int
    repType: str  # 'reps', 'seconds'
    cvSupported: bool = False
    cvModuleId: Optional[str] = None

class Exercise(pd.BaseModel):
    name: str
    sets: int
    reps: int
    weight: Optional[float] = None
    rest_time: int  # seconds

class WorkoutPlan(pd.BaseModel):
    id: Optional[str] = None
    name: str
    description: str
    exercises: List[Exercise]
    duration_minutes: int
    difficulty: str  # beginner, intermediate, advanced
    target_muscles: List[str]

class ExerciseSetLogIn(pd.BaseModel):
    exercise_id: str = pd.Field(..., alias="exerciseId")
    exercise_slug: str = pd.Field(..., alias="exerciseSlug")
    set_number: int = pd.Field(..., alias="setNumber")
    reps_completed: int = pd.Field(0, alias="repsCompleted")
    unit: Optional[str] = None
    seconds_completed: Optional[int] = pd.Field(None, alias="secondsCompleted")
    weight_kg: float = pd.Field(0.0, alias="weightKg")
    is_completed: bool = pd.Field(True, alias="isCompleted")
    rest_taken_seconds: Optional[int] = pd.Field(None, alias="restTakenSeconds")
    cv_detected: bool = pd.Field(False, alias="cvDetected")
    cv_form_summary: Optional[Dict[str, Any]] = pd.Field(None, alias="cvFormSummary")
    set_type: Literal["warmup", "normal", "drop", "failure"] = pd.Field("normal", alias="setType")
    rpe: Optional[float] = pd.Field(None, ge=1, le=10)
    note: Optional[str] = pd.Field(None, max_length=300)
    superset_group_id: Optional[str] = pd.Field(None, alias="supersetGroupId")
    is_pr: bool = pd.Field(False, alias="isPr")
    rep_timeline: Optional[List[RepTimelineItem]] = pd.Field(default=None, alias="repTimeline")
    video_story_id: Optional[str] = pd.Field(default=None, alias="videoStoryId")

    model_config = pd.ConfigDict(populate_by_name=True)


class WorkoutSession(pd.BaseModel):
    id: Optional[str] = None
    plan_id: Optional[str] = None
    plan_name: Optional[str] = pd.Field(None, alias="planName")
    name: Optional[str] = None
    started_at: Optional[datetime] = pd.Field(None, alias="startedAt")
    start_time: Optional[datetime] = None
    finished_at: Optional[datetime] = pd.Field(None, alias="finishedAt")
    end_time: Optional[datetime] = None
    exercise_logs: List[ExerciseSetLogIn] = pd.Field(default_factory=list, alias="exerciseLogs")
    completed_exercises: Optional[List[Dict[str, Any]]] = None
    total_duration_minutes: Optional[int] = pd.Field(None, alias="totalDurationMinutes")
    duration_minutes: Optional[int] = None
    total_volume_kg: int = pd.Field(0, alias="totalVolumeKg")
    calories_burned: Optional[int] = None
    cv_form_summary: Optional[Dict[str, Any]] = pd.Field(None, alias="cvFormSummary")

    class Config:
        allow_population_by_field_name = True


def _format_utc_iso(dt_val) -> Optional[str]:
    if dt_val is None:
        return None
    if isinstance(dt_val, str):
        try:
            dt_val = datetime.fromisoformat(dt_val.replace("Z", "+00:00"))
        except Exception:
            return dt_val
    if isinstance(dt_val, datetime):
        if dt_val.tzinfo is None:
            dt_val = dt_val.replace(tzinfo=timezone.utc)
        else:
            dt_val = dt_val.astimezone(timezone.utc)
        return dt_val.isoformat().replace("+00:00", "Z")
    return None


# High-entropy client session identity generated once per workout by the app.
# Legacy identities (e.g. "demo-session-N") were reused across distinct workouts
# and therefore never participate in idempotent replay.
_IDEMPOTENT_CLIENT_ID = re.compile(r"ws-[0-9a-f]{32}")


def _idempotent_session_object_id(user_id: str, client_id: Optional[str]) -> Optional[ObjectId]:
    """Deterministic _id per (owner, client identity) so the unique _id index makes retries atomic."""
    if not client_id or not _IDEMPOTENT_CLIENT_ID.fullmatch(client_id):
        return None
    digest = hashlib.sha256(f"workout_session:v1|{user_id}|{client_id}".encode("utf-8")).digest()
    return ObjectId(digest[:12])


def _utc_ms(value: Optional[datetime]) -> Optional[datetime]:
    """MongoDB stores millisecond precision and returns naive UTC datetimes."""
    if value is None:
        return None
    value = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)
    return value.replace(microsecond=value.microsecond // 1000 * 1000)


_VALID_SET_TYPES = ("warmup", "normal", "drop", "failure")
_CANONICAL_MUSCLE_GROUPS = ("chest", "back", "legs", "shoulders", "arms", "core")

_MUSCLE_GROUP_ALIASES: Dict[str, str] = {
    "chest": "chest",
    "pectorals": "chest",
    "pecs": "chest",
    "upper_chest": "chest",
    "lower_chest": "chest",
    "inner_chest": "chest",
    "back": "back",
    "lats": "back",
    "latissimus": "back",
    "latissimus_dorsi": "back",
    "upper_back": "back",
    "lower_back": "back",
    "middle_back": "back",
    "traps": "back",
    "trapezius": "back",
    "rhomboids": "back",
    "erector_spinae": "back",
    "legs": "legs",
    "leg": "legs",
    "quads": "legs",
    "quadriceps": "legs",
    "hamstrings": "legs",
    "glutes": "legs",
    "gluteus": "legs",
    "calves": "legs",
    "calf": "legs",
    "lower_body": "legs",
    "thighs": "legs",
    "adductors": "legs",
    "abductors": "legs",
    "hip_flexors": "legs",
    "shoulders": "shoulders",
    "shoulder": "shoulders",
    "delts": "shoulders",
    "deltoids": "shoulders",
    "front_delts": "shoulders",
    "side_delts": "shoulders",
    "rear_delts": "shoulders",
    "lateral_delts": "shoulders",
    "anterior_deltoid": "shoulders",
    "posterior_deltoid": "shoulders",
    "arms": "arms",
    "arm": "arms",
    "biceps": "arms",
    "triceps": "arms",
    "forearms": "arms",
    "forearm": "arms",
    "brachialis": "arms",
    "wrists": "arms",
    "core": "core",
    "abs": "core",
    "abdominals": "core",
    "obliques": "core",
    "rectus_abdominis": "core",
    "transverse_abdominis": "core",
    "lower_abs": "core",
}

_FALLBACK_SLUG_MUSCLE_RULES: Tuple[Tuple[str, Tuple[str, ...]], ...] = (
    (
        "core",
        (
            "leg-raise",
            "leg_raise",
            "plank",
            "crunch",
            "sit-up",
            "situp",
            "oblique",
            "russian-twist",
            "dead-bug",
            "ab-",
            "abs",
            "core",
        ),
    ),
    (
        "legs",
        (
            "leg-curl",
            "leg_curl",
            "hamstring-curl",
            "hamstring_curl",
            "nordic-curl",
        ),
    ),
    (
        "arms",
        (
            "curl",
            "tricep",
            "bicep",
            "pushdown",
            "skullcrusher",
            "skull-crusher",
            "preacher",
            "forearm",
            "wrist",
        ),
    ),
    (
        "chest",
        (
            "bench",
            "chest",
            "pec",
            "fly",
            "push-up",
            "pushup",
            "incline-press",
            "decline-press",
            "crossover",
        ),
    ),
    (
        "shoulders",
        (
            "face-pull",
            "face_pull",
            "lateral-raise",
            "lateral_raise",
            "front-raise",
            "rear-delt",
            "shoulder",
            "overhead-press",
            "overhead_press",
            "military-press",
            "arnold-press",
            "upright-row",
            "shrug",
            "delt",
        ),
    ),
    (
        "legs",
        (
            "squat",
            "lunge",
            "leg-press",
            "leg_press",
            "leg-extension",
            "leg-",
            "leg_",
            "calf",
            "calves",
            "glute",
            "hip-thrust",
            "bulgarian",
            "step-up",
            "hamstring",
            "quad",
            "rdl",
        ),
    ),
    (
        "back",
        (
            "row",
            "pulldown",
            "pull-down",
            "pull-up",
            "pullup",
            "chin-up",
            "chinup",
            "deadlift",
            "lat-",
            "lat_",
            "back",
            "hyperextension",
            "good-morning",
        ),
    ),
    ("shoulders", ("press",)),
)


def _normalize_set_type(value: Any) -> str:
    if isinstance(value, str) and value in _VALID_SET_TYPES:
        return value
    return "normal"


def _estimate_epley_1rm(weight_kg: float, reps: int) -> float:
    if weight_kg <= 0 or reps <= 0:
        return 0.0
    return weight_kg * (1.0 + reps / 30.0)


def _is_pr_eligible_set(item: Any) -> bool:
    if not isinstance(item, dict):
        return False
    if not _is_set_completed(item):
        return False
    set_type = _normalize_set_type(
        item.get("set_type") if item.get("set_type") is not None else item.get("setType")
    )
    if set_type == "warmup":
        return False
    return _extract_weight_kg(item) > 0 and _extract_reps(item) > 0


def _detect_and_mark_prs(
    logs_data: List[dict],
    owner_query: dict,
    exclude_session_id: Optional[ObjectId] = None,
) -> List[dict]:
    """Detect Personal Records (weight & Epley 1RM) against prior sessions and mark is_pr in-place."""
    if not logs_data:
        return []

    alias_to_key: Dict[str, str] = {}
    session_ex_keys: List[str] = []
    for item in logs_data:
        if not isinstance(item, dict):
            continue
        item["is_pr"] = False
        ex_id = str(item.get("exercise_id") or item.get("exerciseId") or "").strip()
        ex_slug = str(item.get("exercise_slug") or item.get("exerciseSlug") or "").strip()
        ex_key = alias_to_key.get(ex_id) or alias_to_key.get(ex_slug) or ex_id or ex_slug
        if not ex_key:
            continue
        if ex_key not in session_ex_keys:
            session_ex_keys.append(ex_key)
        if ex_id:
            alias_to_key.setdefault(ex_id, ex_key)
        if ex_slug:
            alias_to_key.setdefault(ex_slug, ex_key)

    if not session_ex_keys:
        return []

    prior_sessions = _safe_find(workout_history_collection, owner_query)
    prev_best_weight: Dict[str, float] = {k: 0.0 for k in session_ex_keys}
    prev_best_1rm: Dict[str, float] = {k: 0.0 for k in session_ex_keys}

    for hist_doc in prior_sessions:
        if exclude_session_id is not None and hist_doc.get("_id") == exclude_session_id:
            continue
        raw_hist_logs = hist_doc.get("exercise_logs") or hist_doc.get("completed_exercises") or []
        for h_item in raw_hist_logs:
            if not _is_pr_eligible_set(h_item):
                continue
            h_id = str(h_item.get("exercise_id") or h_item.get("exerciseId") or "").strip()
            h_slug = str(h_item.get("exercise_slug") or h_item.get("exerciseSlug") or "").strip()
            matched_key = alias_to_key.get(h_id) or alias_to_key.get(h_slug)
            if not matched_key:
                continue
            w = _extract_weight_kg(h_item)
            r = _extract_reps(h_item)
            est = _estimate_epley_1rm(w, r)
            if w > prev_best_weight[matched_key]:
                prev_best_weight[matched_key] = w
            if est > prev_best_1rm[matched_key]:
                prev_best_1rm[matched_key] = est

    eligible_indices_by_key: Dict[str, List[int]] = {k: [] for k in session_ex_keys}
    for idx, item in enumerate(logs_data):
        if not _is_pr_eligible_set(item):
            continue
        ex_id = str(item.get("exercise_id") or item.get("exerciseId") or "").strip()
        ex_slug = str(item.get("exercise_slug") or item.get("exerciseSlug") or "").strip()
        matched_key = alias_to_key.get(ex_id) or alias_to_key.get(ex_slug)
        if matched_key:
            eligible_indices_by_key[matched_key].append(idx)

    pr_by_index: Dict[int, str] = {}
    eps = 1e-9

    for ex_key, indices in eligible_indices_by_key.items():
        if not indices:
            continue
        has_history = prev_best_weight[ex_key] > 0.0 or prev_best_1rm[ex_key] > 0.0
        if has_history:
            running_weight = prev_best_weight[ex_key]
            running_1rm = prev_best_1rm[ex_key]
            for idx in indices:
                item = logs_data[idx]
                w = _extract_weight_kg(item)
                r = _extract_reps(item)
                est = _estimate_epley_1rm(w, r)
                beat_weight = w > running_weight + eps
                beat_1rm = est > running_1rm + eps
                if beat_weight or beat_1rm:
                    if beat_weight and beat_1rm:
                        pr_by_index[idx] = "both"
                    elif beat_weight:
                        pr_by_index[idx] = "weight"
                    else:
                        pr_by_index[idx] = "1rm"
                    if beat_weight:
                        running_weight = w
                    if beat_1rm:
                        running_1rm = est
        else:
            best_1rm_idx = indices[0]
            best_1rm_score = (-1.0, -1.0)
            best_weight_idx = indices[0]
            best_weight_score = (-1.0, -1.0)
            for idx in indices:
                item = logs_data[idx]
                w = _extract_weight_kg(item)
                r = _extract_reps(item)
                est = _estimate_epley_1rm(w, r)
                if (est > best_1rm_score[0] + eps) or (
                    abs(est - best_1rm_score[0]) <= eps and w > best_1rm_score[1] + eps
                ):
                    best_1rm_score = (est, w)
                    best_1rm_idx = idx
                if (w > best_weight_score[0] + eps) or (
                    abs(w - best_weight_score[0]) <= eps and est > best_weight_score[1] + eps
                ):
                    best_weight_score = (w, est)
                    best_weight_idx = idx
            if best_1rm_idx == best_weight_idx:
                pr_by_index[best_1rm_idx] = "both"
            else:
                pr_by_index[best_weight_idx] = "weight"
                pr_by_index[best_1rm_idx] = "1rm"

    new_prs: List[dict] = []
    for idx in sorted(pr_by_index.keys()):
        item = logs_data[idx]
        item["is_pr"] = True
        w = _extract_weight_kg(item)
        r = _extract_reps(item)
        est = _estimate_epley_1rm(w, r)
        new_prs.append({
            "exerciseId": str(item.get("exercise_id") or item.get("exerciseId") or ""),
            "exerciseSlug": str(item.get("exercise_slug") or item.get("exerciseSlug") or ""),
            "setNumber": _extract_set_number(item, default=idx + 1),
            "weightKg": w,
            "repsCompleted": r,
            "estimated1Rm": round(est, 2),
            "prType": pr_by_index[idx],
        })

    return new_prs


def _parse_utc_datetime(val: Any) -> Optional[datetime]:
    if val is None:
        return None
    if isinstance(val, datetime):
        if val.tzinfo is None:
            return val.replace(tzinfo=timezone.utc)
        return val.astimezone(timezone.utc)
    if isinstance(val, str):
        try:
            dt = datetime.fromisoformat(val.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                return dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except Exception:
            return None
    return None


def _normalize_muscle_group(raw: Any) -> Optional[str]:
    if not isinstance(raw, str):
        return None
    cleaned = raw.strip().lower().replace("-", "_").replace(" ", "_")
    if not cleaned:
        return None
    if cleaned in _MUSCLE_GROUP_ALIASES:
        return _MUSCLE_GROUP_ALIASES[cleaned]
    if "pec" in cleaned or "chest" in cleaned:
        return "chest"
    if "lat" in cleaned or "trap" in cleaned or "rhomb" in cleaned or "back" in cleaned:
        return "back"
    if "quad" in cleaned or "hamstring" in cleaned or "glute" in cleaned or "calf" in cleaned or "calves" in cleaned or "leg" in cleaned:
        return "legs"
    if "delt" in cleaned or "shoulder" in cleaned:
        return "shoulders"
    if "bicep" in cleaned or "tricep" in cleaned or "forearm" in cleaned or "arm" in cleaned:
        return "arms"
    if "ab" in cleaned or "oblique" in cleaned or "core" in cleaned:
        return "core"
    return None


def _resolve_exercise_muscles(
    exercise_id: str,
    exercise_slug: str,
    cache: Dict[Tuple[str, str], Dict[str, float]],
) -> Dict[str, float]:
    cache_key = (exercise_id, exercise_slug)
    if cache_key in cache:
        return cache[cache_key]

    muscles: Dict[str, float] = {}

    if exercises_collection is not None and (exercise_id or exercise_slug):
        or_clauses: List[dict] = []
        if exercise_slug:
            or_clauses.append({"slug": exercise_slug})
        if exercise_id:
            or_clauses.append({"id": exercise_id})
            if exercise_id != exercise_slug:
                or_clauses.append({"slug": exercise_id})
            if ObjectId.is_valid(exercise_id):
                or_clauses.append({"_id": ObjectId(exercise_id)})
        try:
            ex_doc = exercises_collection.find_one({"$or": or_clauses}) if or_clauses else None
        except Exception:
            ex_doc = None

        if isinstance(ex_doc, dict):
            primary = _normalize_muscle_group(ex_doc.get("muscleGroup") or ex_doc.get("muscle_group"))
            if primary:
                muscles[primary] = 1.0
            else:
                target_muscles = ex_doc.get("targetMuscles") or ex_doc.get("target_muscles") or []
                if isinstance(target_muscles, list):
                    for tm in target_muscles:
                        norm_tm = _normalize_muscle_group(tm)
                        if norm_tm:
                            muscles[norm_tm] = 1.0
                            break

            secondary_muscles = ex_doc.get("secondaryMuscles") or ex_doc.get("secondary_muscles") or []
            if isinstance(secondary_muscles, list):
                for sm in secondary_muscles:
                    norm_sm = _normalize_muscle_group(sm)
                    if norm_sm and norm_sm not in muscles:
                        muscles[norm_sm] = 0.4

    if not muscles:
        combined = f"{exercise_slug} {exercise_id}".lower().strip()
        if combined:
            for muscle_group, keywords in _FALLBACK_SLUG_MUSCLE_RULES:
                if any(kw in combined for kw in keywords):
                    muscles[muscle_group] = 1.0
                    break

    cache[cache_key] = muscles
    return muscles


def _normalize_log_for_fingerprint(item: Any) -> tuple:
    if not isinstance(item, dict):
        return ()
    rep_tl = item.get("rep_timeline") or item.get("repTimeline")
    tl_fingerprint = ()
    if isinstance(rep_tl, list):
        tl_fingerprint = tuple(
            (
                r.get("rep_index", r.get("repIndex")),
                r.get("start_sec", r.get("startSec")),
                r.get("bottom_sec", r.get("bottomSec")),
                r.get("end_sec", r.get("endSec")),
                r.get("duration_sec", r.get("durationSec")),
                r.get("metric_angle_deg", r.get("metricAngleDeg")),
                r.get("is_valid", r.get("isValid")),
                r.get("issue_type", r.get("issueType")),
            )
            for r in rep_tl
            if isinstance(r, dict)
        )
    return (
        item.get("exercise_id"),
        item.get("exercise_slug"),
        item.get("set_number"),
        item.get("reps_completed"),
        item.get("unit"),
        item.get("seconds_completed"),
        item.get("weight_kg"),
        item.get("is_completed"),
        item.get("rest_taken_seconds"),
        item.get("cv_detected"),
        item.get("cv_form_summary"),
        _normalize_set_type(item.get("set_type")),
        item.get("rpe"),
        item.get("note"),
        item.get("superset_group_id"),
        tl_fingerprint,
        item.get("video_story_id") or item.get("videoStoryId"),
    )


def _session_fingerprint(doc: dict) -> tuple:
    raw_logs = doc.get("exercise_logs") or []
    normalized_logs = tuple(_normalize_log_for_fingerprint(item) for item in raw_logs)
    return (
        doc.get("plan_id"),
        doc.get("plan_name"),
        _utc_ms(doc.get("started_at")),
        _utc_ms(doc.get("finished_at")),
        normalized_logs,
        doc.get("total_duration_minutes"),
        doc.get("total_volume_kg"),
        doc.get("cv_form_summary"),
    )


def _serialize_workout_session(doc: dict) -> dict:
    if not doc:
        return {}
    session_id = str(doc.get("_id") or doc.get("id") or "")
    raw_logs = doc.get("exercise_logs") or doc.get("completed_exercises") or []
    exercise_logs = []
    for item in raw_logs:
        raw_rpe = item.get("rpe")
        rpe_val = float(raw_rpe) if raw_rpe is not None else None
        raw_note = item.get("note")
        note_val = str(raw_note) if raw_note is not None else None
        superset_raw = (
            item.get("superset_group_id")
            if item.get("superset_group_id") is not None
            else item.get("supersetGroupId")
        )
        superset_val = str(superset_raw) if superset_raw is not None else None
        is_pr_raw = item.get("is_pr") if item.get("is_pr") is not None else item.get("isPr", False)

        rep_tl_raw = item.get("rep_timeline") if item.get("rep_timeline") is not None else item.get("repTimeline")
        rep_timeline_out = None
        if isinstance(rep_tl_raw, list):
            rep_timeline_out = []
            for r in rep_tl_raw:
                if isinstance(r, RepTimelineItem):
                    rep_timeline_out.append(r.model_dump(by_alias=True))
                elif isinstance(r, dict):
                    rep_timeline_out.append({
                        "repIndex": int(r.get("rep_index", r.get("repIndex", 1))),
                        "startSec": float(r.get("start_sec", r.get("startSec", 0.0))),
                        "bottomSec": float(r.get("bottom_sec", r.get("bottomSec", 0.0))),
                        "endSec": float(r.get("end_sec", r.get("endSec", 0.0))),
                        "durationSec": float(r.get("duration_sec", r.get("durationSec", 0.0))),
                        "metricAngleDeg": (
                            float(r["metric_angle_deg"])
                            if r.get("metric_angle_deg") is not None
                            else (float(r["metricAngleDeg"]) if r.get("metricAngleDeg") is not None else None)
                        ),
                        "isValid": bool(r.get("is_valid", r.get("isValid", True))),
                        "issueType": str(r.get("issue_type", r.get("issueType", "none"))),
                        "viewAngle": str(r.get("view_angle", r.get("viewAngle", "unknown"))),
                        "visibilityConfidence": float(r.get("visibility_confidence", r.get("visibilityConfidence", 1.0))),
                    })

        video_story_id_out = (
            str(item["video_story_id"])
            if item.get("video_story_id") is not None
            else (str(item["videoStoryId"]) if item.get("videoStoryId") is not None else None)
        )

        exercise_logs.append({
            "exerciseId": str(item.get("exercise_id") or item.get("exerciseId") or ""),
            "exerciseSlug": str(item.get("exercise_slug") or item.get("exerciseSlug") or ""),
            "setNumber": int(item.get("set_number") or item.get("setNumber") or 1),
            "repsCompleted": int(item.get("reps_completed") if item.get("reps_completed") is not None else item.get("repsCompleted", 0)),
            "unit": item.get("unit"),
            "secondsCompleted": item.get("seconds_completed") if item.get("seconds_completed") is not None else item.get("secondsCompleted"),
            "weightKg": float(item.get("weight_kg") if item.get("weight_kg") is not None else item.get("weightKg", 0.0)),
            "isCompleted": bool(item.get("is_completed") if item.get("is_completed") is not None else item.get("isCompleted", True)),
            "restTakenSeconds": item.get("rest_taken_seconds") if item.get("rest_taken_seconds") is not None else item.get("restTakenSeconds"),
            "cvDetected": bool(item.get("cv_detected") if item.get("cv_detected") is not None else item.get("cvDetected", False)),
            "cvFormSummary": item.get("cv_form_summary") or item.get("cvFormSummary"),
            "setType": _normalize_set_type(item.get("set_type") if item.get("set_type") is not None else item.get("setType")),
            "rpe": rpe_val,
            "note": note_val,
            "supersetGroupId": superset_val,
            "isPr": bool(is_pr_raw),
            "repTimeline": rep_timeline_out,
            "videoStoryId": video_story_id_out,
        })

    started_at = _format_utc_iso(doc.get("started_at") or doc.get("start_time") or doc.get("created_at"))
    finished_at = _format_utc_iso(doc.get("finished_at") or doc.get("end_time"))

    serialized = {
        "id": session_id,
        "planName": str(doc.get("plan_name") or doc.get("planName") or doc.get("name") or "Workout Session"),
        "startedAt": started_at or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "finishedAt": finished_at,
        "exerciseLogs": exercise_logs,
        "totalDurationMinutes": doc.get("total_duration_minutes") if doc.get("total_duration_minutes") is not None else doc.get("duration_minutes"),
        "totalVolumeKg": int(doc.get("total_volume_kg") if doc.get("total_volume_kg") is not None else 0),
    }
    cv_form_summary = doc.get("cv_form_summary") or doc.get("cvFormSummary")
    if cv_form_summary is not None:
        serialized["cvFormSummary"] = cv_form_summary
    return serialized

@router.get("/plans")
async def get_workout_plans(
    difficulty: Optional[str] = Query(None),
    target_muscle: Optional[str] = Query(None),
    email: str = Depends(verify_token)
):
    """Get available workout plans"""
    try:
        user = user_repo.get_by_email(email)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        user_id = str(user.get("_id")) if user.get("_id") is not None else None
        try:
            owner_query = build_user_query(user_id, email)
        except NameError:
            from backend.app.services.context_utils import build_user_query as _buq
            owner_query = _buq(user_id, email)

        clauses = [owner_query]
        if difficulty:
            clauses.append({"difficulty": difficulty})
        if target_muscle:
            clauses.append({
                "$or": [
                    {"target_muscles": target_muscle},
                    {"muscle_groups": target_muscle},
                ]
            })

        if len(clauses) > 1:
            plan_query: dict = {"$and": clauses}
        else:
            plan_query = owner_query

        plans = _safe_find(custom_plans_collection, plan_query)
        plans = [_serialize_mongo(p) for p in plans]

        return {
            "plans": plans,
            "total_count": len(plans),
            "filters_applied": {
                "difficulty": difficulty,
                "target_muscle": target_muscle
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/streak", response_model=dict)
async def get_workout_streak(current_user: dict = Depends(get_current_user)):
    try:
        user_id = str(current_user["_id"]) if current_user.get("_id") is not None else None
        email = current_user.get("email")
        if not email and not user_id:
            raise HTTPException(status_code=401, detail="Unauthorized")

        today_str = get_vn_date_str()
        thirty_days_ago_str = get_vn_date_str(-30)
        start_30_utc, _ = get_vn_day_range_utc(thirty_days_ago_str)

        streak_query = {
            "$and": [
                build_user_query(user_id, email),
                {
                    "$or": [
                        {"date": {"$gte": thirty_days_ago_str}},
                        {"started_at": {"$gte": start_30_utc}},
                        {"created_at": {"$gte": start_30_utc}},
                    ]
                },
            ]
        }
        sessions = _safe_find(workout_history_collection, streak_query)

        # Tập hợp các ngày đã tập (set để dedup)
        worked_out_dates = set()
        for s in sessions:
            raw_date = s.get("date") or s.get("started_at") or s.get("start_time") or s.get("created_at")
            if not raw_date:
                continue
            try:
                if isinstance(raw_date, datetime):
                    vn_str = utc_to_vn_date_str(raw_date)
                    if vn_str:
                        worked_out_dates.add(vn_str)
                elif isinstance(raw_date, str):
                    if "T" in raw_date:
                        try:
                            dt = datetime.fromisoformat(raw_date.replace("Z", "+00:00"))
                            vn_str = utc_to_vn_date_str(dt)
                            if vn_str:
                                worked_out_dates.add(vn_str)
                            else:
                                worked_out_dates.add(raw_date[:10])
                        except Exception:
                            worked_out_dates.add(raw_date[:10])
                    else:
                        worked_out_dates.add(raw_date[:10])
            except Exception:
                continue

        # 7 ngày gần nhất — index 0 = 6 ngày trước, index 6 = hôm nay
        streak_days = []
        for i in range(6, -1, -1):
            day = get_vn_date_str(-i)
            streak_days.append(day in worked_out_dates)

        # Tính current streak (đếm ngược từ hôm nay)
        current_streak = 0
        for i in range(30):
            day = get_vn_date_str(-i)
            if day in worked_out_dates:
                current_streak += 1
            else:
                break

        # Tính longest streak trong 30 ngày
        longest_streak = 0
        temp = 0
        for i in range(29, -1, -1):
            day = get_vn_date_str(-i)
            if day in worked_out_dates:
                temp += 1
                longest_streak = max(longest_streak, temp)
            else:
                temp = 0

        last_workout_date = max(worked_out_dates) if worked_out_dates else None
        month_prefix = today_str[:7]
        total_this_month = sum(
            1 for d in worked_out_dates
            if d.startswith(month_prefix)
        )

        return {
            # Field mới — Frontend dùng cái này
            "streak_days": streak_days,          # [false, true, false, ...] 7 items
                                                  # index 0 = 6 ngày trước, index 6 = hôm nay
            # Giữ nguyên các field cũ
            "current_streak": current_streak,
            "longest_streak": longest_streak,
            "last_workout_date": last_workout_date,
            "total_workouts_this_month": total_this_month,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Streak error: {str(e)}")

@router.get("/report/weekly")
async def get_weekly_workout_report(
    start_date: Optional[str] = Query(None),
    email: str = Depends(verify_token)
):
    """Get weekly workout report"""
    try:
        user = user_repo.get_by_email(email)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        # Default to last 7 days if no start date provided
        if not start_date:
            start_date = get_vn_date_str(-7)

        start_d = date.fromisoformat(start_date)
        end_d = start_d + timedelta(days=6)
        start_dt, _ = get_vn_day_range_utc(start_date)
        _, end_dt = get_vn_day_range_utc(end_d.isoformat())

        user_id = str(user.get("_id")) if user.get("_id") is not None else None
        base_user_query = build_user_query(user_id, email)

        time_query = {
            "$or": [
                {"date": {"$gte": start_date, "$lte": end_d.isoformat()}},
                {"date": {"$gte": start_dt, "$lte": end_dt}},
                {"started_at": {"$gte": start_dt, "$lte": end_dt}},
                {"created_at": {"$gte": start_dt, "$lte": end_dt}},
            ]
        }
        report_query = {"$and": [base_user_query, time_query]}
        workouts = _safe_find(workout_history_collection, report_query, sort=[("date", 1), ("created_at", 1)], limit=1000)

        def _get_minutes(s: dict) -> int:
            for k in ("total_duration_minutes", "duration_minutes", "duration", "duration_min", "minutes"):
                v = s.get(k)
                if isinstance(v, (int, float)):
                    return int(v)
            return 0

        def _get_calories(s: dict) -> int:
            for k in ("calories_burned", "calories", "kcal"):
                v = s.get(k)
                if isinstance(v, (int, float)):
                    return int(v)
            return 0

        worked_days = set()
        for w in workouts:
            d = _extract_session_date(w)
            if d:
                worked_days.add(d)
        workout_days = len(worked_days)

        total_workouts = len(workouts)
        total_duration = sum(_get_minutes(w) for w in workouts)
        total_calories = sum(_get_calories(w) for w in workouts)
        avg_duration = int(total_duration / total_workouts) if total_workouts else 0

        return {
            "period": {
                "start_date": start_d.isoformat(),
                "end_date": end_d.isoformat()
            },
            "summary": {
                "total_workouts": total_workouts,
                "total_duration_minutes": total_duration,
                "avg_duration_per_workout": avg_duration,
                "calories_burned": total_calories,
                "workout_days": workout_days
            },
            "daily_data": [_serialize_mongo(w) for w in workouts]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/sessions", status_code=201)
async def log_workout_session(
    session: WorkoutSession,
    current_user: dict = Depends(get_current_user)
):
    """Log workout session with authenticated user_id principal"""
    try:
        user_id = str(current_user["_id"])
        email = current_user.get("email")

        if workout_history_collection is None:
            raise HTTPException(status_code=503, detail="Database not connected")

        now_utc = datetime.now(timezone.utc)

        # Normalize started_at
        raw_start = session.started_at or session.start_time or now_utc
        if raw_start.tzinfo is None:
            start_utc = raw_start.replace(tzinfo=timezone.utc)
        else:
            start_utc = raw_start.astimezone(timezone.utc)

        # Normalize finished_at
        raw_end = session.finished_at or session.end_time
        if raw_end is not None:
            if raw_end.tzinfo is None:
                end_utc = raw_end.replace(tzinfo=timezone.utc)
            else:
                end_utc = raw_end.astimezone(timezone.utc)
        else:
            end_utc = None

        # Asia/Ho_Chi_Minh workout date
        vn_date = start_utc.astimezone(ICT_ZONE).strftime("%Y-%m-%d")

        # Normalize exercise logs
        logs_data = []
        linked_story_ids = set()
        if session.exercise_logs:
            for item in session.exercise_logs:
                cv_summary = item.cv_form_summary if isinstance(item.cv_form_summary, dict) else None
                rep_tl_dump = None
                if item.rep_timeline:
                    rep_tl_dump = [
                        r.model_dump(by_alias=False) if hasattr(r, "model_dump") else dict(r)
                        for r in item.rep_timeline
                    ]
                v_story_id = (item.video_story_id or "").strip() or None
                if v_story_id:
                    linked_story_ids.add(v_story_id)

                logs_data.append({
                    "exercise_id": item.exercise_id,
                    "exercise_slug": item.exercise_slug,
                    "set_number": item.set_number,
                    "reps_completed": item.reps_completed,
                    "unit": item.unit,
                    "seconds_completed": item.seconds_completed,
                    "weight_kg": item.weight_kg,
                    "is_completed": item.is_completed,
                    "rest_taken_seconds": item.rest_taken_seconds,
                    "cv_detected": item.cv_detected,
                    "cv_form_summary": cv_summary,
                    "set_type": item.set_type,
                    "rpe": item.rpe,
                    "note": item.note,
                    "superset_group_id": item.superset_group_id,
                    "is_pr": False,
                    "rep_timeline": rep_tl_dump,
                    "video_story_id": v_story_id,
                })
        elif session.completed_exercises:
            for e in session.completed_exercises:
                raw_item = dict(e)
                cv_summary = raw_item.get("cv_form_summary") or raw_item.get("cvFormSummary")
                if not isinstance(cv_summary, dict):
                    cv_summary = None
                raw_item["cv_form_summary"] = cv_summary
                raw_item["set_type"] = _normalize_set_type(
                    raw_item.get("set_type") if raw_item.get("set_type") is not None else raw_item.get("setType")
                )
                raw_item["rpe"] = raw_item.get("rpe")
                raw_item["note"] = raw_item.get("note")
                raw_item["superset_group_id"] = (
                    raw_item.get("superset_group_id")
                    if raw_item.get("superset_group_id") is not None
                    else raw_item.get("supersetGroupId")
                )
                raw_item["is_pr"] = False
                raw_rep_tl = raw_item.get("rep_timeline") if raw_item.get("rep_timeline") is not None else raw_item.get("repTimeline")
                if isinstance(raw_rep_tl, list):
                    raw_item["rep_timeline"] = [
                        r.model_dump(by_alias=False) if hasattr(r, "model_dump") else dict(r)
                        for r in raw_rep_tl
                    ]
                else:
                    raw_item["rep_timeline"] = None
                raw_story_id = (
                    raw_item.get("video_story_id")
                    if raw_item.get("video_story_id") is not None
                    else raw_item.get("videoStoryId")
                )
                v_story_id = str(raw_story_id).strip() if raw_story_id else None
                raw_item["video_story_id"] = v_story_id
                if v_story_id:
                    linked_story_ids.add(v_story_id)
                logs_data.append(raw_item)

        idempotent_id = _idempotent_session_object_id(user_id, session.id)
        owner_query = build_user_query(user_id, email)
        new_prs = _detect_and_mark_prs(
            logs_data,
            owner_query,
            exclude_session_id=idempotent_id,
        )

        total_duration = session.total_duration_minutes if session.total_duration_minutes is not None else session.duration_minutes
        plan_title = session.plan_name or session.name or "Workout Session"

        doc = {
            "user_id": user_id,
            "email": normalize_email(email),
            "client_id": session.id,
            "plan_id": session.plan_id,
            "plan_name": plan_title,
            "started_at": start_utc,
            "finished_at": end_utc,
            "date": vn_date,
            "exercise_logs": logs_data,
            "total_duration_minutes": total_duration,
            "total_volume_kg": session.total_volume_kg,
            "created_at": now_utc,
        }
        if session.cv_form_summary is not None:
            doc["cv_form_summary"] = session.cv_form_summary

        logged_at = now_utc
        if idempotent_id is None:
            result = workout_history_collection.insert_one(doc)
            doc["_id"] = result.inserted_id
        else:
            doc["_id"] = idempotent_id
            try:
                workout_history_collection.insert_one(doc)
            except DuplicateKeyError:
                existing = workout_history_collection.find_one({"_id": idempotent_id})
                if (
                    not existing
                    or existing.get("user_id") != user_id
                    or _session_fingerprint(existing) != _session_fingerprint(doc)
                ):
                    raise HTTPException(
                        status_code=409,
                        detail="Workout session identity already saved with different data",
                    )
                doc = existing
                logged_at = _utc_ms(existing.get("created_at")) or now_utc

        # Link workout_session_id in workout_video_stories fail-safely
        if linked_story_ids:
            try:
                db_target = _db_mod.db
                story_col = getattr(_db_mod, "workout_video_stories_collection", None)
                if story_col is None and db_target is not None:
                    story_col = db_target["workout_video_stories"]
                if story_col is not None:
                    session_id_str = str(doc["_id"])
                    raw_acc_id = current_user.get("account_id")
                    user_acc_or_id = (
                        raw_acc_id.strip()
                        if isinstance(raw_acc_id, str) and raw_acc_id.strip()
                        else user_id
                    )
                    story_col.update_many(
                        {
                            "story_id": {"$in": list(linked_story_ids)},
                            "$and": [
                                {
                                    "$or": [
                                        {"account_id": user_acc_or_id},
                                        {"user_id": user_id},
                                    ]
                                },
                                {
                                    "$or": [
                                        {"workout_session_id": None},
                                        {"workout_session_id": {"$exists": False}},
                                    ]
                                },
                            ],
                        },
                        {"$set": {"workout_session_id": session_id_str}},
                    )
            except Exception as exc:
                logger.warning("Fail-safe linking of video stories to session failed: %s", exc)

        serialized = _serialize_workout_session(doc)
        return {
            "message": "Workout session logged successfully",
            "session_id": str(doc["_id"]),
            "session": serialized,
            "logged_at": logged_at.isoformat(),
            "new_prs": new_prs,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/plans")
async def create_workout_plan(
    plan: WorkoutPlan,
    email: str = Depends(verify_token)
):
    """Create new workout plan"""
    try:
        user = user_repo.get_by_email(email)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        if custom_plans_collection is None:
            raise HTTPException(status_code=503, detail="Database not connected")

        user_id = str(user.get("_id")) if user.get("_id") is not None else None
        now = datetime.utcnow()
        doc = plan.dict()
        doc["email"] = normalize_email(email)
        if user_id:
            doc["user_id"] = user_id
        doc["created_at"] = now

        result = custom_plans_collection.insert_one(doc)
        inserted = {**doc, "_id": result.inserted_id}

        return {
            "id": str(result.inserted_id),
            "message": "Workout plan created successfully",
            "plan": _serialize_mongo(inserted),
            "created_at": now.isoformat(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.delete("/plans/{plan_id}")
async def delete_workout_plan(
    plan_id: str,
    email: str = Depends(verify_token)
):
    """Delete workout plan"""
    try:
        user = user_repo.get_by_email(email)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        if custom_plans_collection is None:
            raise HTTPException(status_code=503, detail="Database not connected")

        user_id = str(user.get("_id")) if user.get("_id") is not None else None
        try:
            owner_query = build_user_query(user_id, email)
        except NameError:
            from backend.app.services.context_utils import build_user_query as _buq
            owner_query = _buq(user_id, email)

        try:
            oid = ObjectId(plan_id)
            id_query = {"_id": oid}
        except Exception:
            id_query = {"id": plan_id}

        query = {"$and": [owner_query, id_query]}
        result = custom_plans_collection.delete_one(query)
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Workout plan not found")

        return {
            "id": plan_id,
            "message": "Workout plan deleted successfully",
            "deleted_at": datetime.utcnow().isoformat(),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/plans/{plan_id}")
async def update_workout_plan(
    plan_id: str,
    plan: WorkoutPlan,
    email: str = Depends(verify_token)
):
    """Update existing workout plan"""
    try:
        user = user_repo.get_by_email(email)
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        if custom_plans_collection is None:
            raise HTTPException(status_code=503, detail="Database not connected")

        user_id = str(user.get("_id")) if user.get("_id") is not None else None
        try:
            owner_query = build_user_query(user_id, email)
        except NameError:
            from backend.app.services.context_utils import build_user_query as _buq
            owner_query = _buq(user_id, email)

        try:
            oid = ObjectId(plan_id)
            id_query = {"_id": oid}
        except Exception:
            id_query = {"id": plan_id}

        if not plan.name or not plan.name.strip():
            raise HTTPException(status_code=400, detail="Plan name cannot be empty")
        if plan.duration_minutes <= 0 or plan.duration_minutes > 600:
            raise HTTPException(status_code=400, detail="Invalid duration_minutes")
        if not plan.difficulty or plan.difficulty.lower() not in ("beginner", "intermediate", "advanced"):
            raise HTTPException(status_code=400, detail="Invalid difficulty")
        for ex in plan.exercises:
            if (
                not ex.name
                or not ex.name.strip()
                or ex.sets <= 0
                or ex.reps <= 0
                or ex.rest_time < 0
                or (ex.weight is not None and ex.weight < 0)
            ):
                raise HTTPException(status_code=400, detail="Invalid exercise parameters")

        query = {"$and": [owner_query, id_query]}
        existing = custom_plans_collection.find_one(query)
        if not existing:
            raise HTTPException(status_code=404, detail="Workout plan not found")

        now = datetime.utcnow()
        update_doc = {
            "name": plan.name.strip(),
            "description": plan.description,
            "exercises": [e.model_dump() if hasattr(e, "model_dump") else e.dict() for e in plan.exercises],
            "duration_minutes": plan.duration_minutes,
            "difficulty": plan.difficulty.lower(),
            "target_muscles": plan.target_muscles,
            "updated_at": now,
        }

        custom_plans_collection.update_one(query, {"$set": update_doc})
        updated = custom_plans_collection.find_one(query)

        return {
            "id": plan_id,
            "message": "Workout plan updated successfully",
            "plan": _serialize_mongo(updated),
            "updated_at": now.isoformat(),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/log-session", status_code=201)
async def log_workout_session_legacy(
    session: WorkoutSession,
    current_user: dict = Depends(get_current_user)
):
    """Log workout session (Legacy endpoint - redirects to /sessions)"""
    return await log_workout_session(session, current_user)

@router.get("/history")
async def get_workout_history(
    limit: int = Query(10, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(get_current_user)
):
    """Get workout history filtered strictly by authenticated user_id"""
    try:
        user_id = str(current_user["_id"]) if current_user.get("_id") is not None else None
        email = current_user.get("email")
        workout_query = build_user_query(user_id, email)

        total = _safe_count(workout_history_collection, workout_query)
        sessions = _safe_find(
            workout_history_collection,
            workout_query,
            sort=[("started_at", -1), ("date", -1), ("created_at", -1)],
            skip=offset,
            limit=limit,
        )

        return {
            "sessions": [_serialize_workout_session(s) for s in sessions],
            "pagination": {
                "limit": limit,
                "offset": offset,
                "total": total
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/sessions/{session_id}")
async def get_workout_session_detail(
    session_id: str,
    current_user: dict = Depends(get_current_user)
):
    """Get single workout session detail strictly owned by authenticated user_id"""
    try:
        user_id = str(current_user["_id"]) if current_user.get("_id") is not None else None
        email = current_user.get("email")
        owner_filter = build_user_query(user_id, email)

        try:
            oid = ObjectId(session_id)
            id_filter = {"$or": [{"_id": oid}, {"client_id": session_id}]}
        except Exception:
            id_filter = {"client_id": session_id}

        query = {"$and": [owner_filter, id_filter]}
        doc = workout_history_collection.find_one(query) if workout_history_collection is not None else None
        if not doc:
            raise HTTPException(status_code=404, detail="Workout session not found")

        return {
            "session": _serialize_workout_session(doc),
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/last-performance", response_model=dict)
async def get_workout_last_performance(
    exercise_ids: str = Query(..., description="Comma-separated exercise IDs or slugs"),
    current_user: dict = Depends(get_current_user),
):
    """Get last performance and progressive overload suggestions for multiple exercises"""
    try:
        user_id = str(current_user["_id"]) if current_user.get("_id") is not None else None
        email = current_user.get("email")
        owner_query = build_user_query(user_id, email)

        ids = [i.strip() for i in exercise_ids.split(",") if i.strip()]
        if not ids:
            return {"items": {}}

        sessions = _safe_find(
            workout_history_collection,
            owner_query,
            sort=[("started_at", -1), ("created_at", -1)],
            limit=30,
        )

        items = {}
        for target_id in ids:
            perf = _find_last_performance_for_exercise(sessions, target_id)
            if perf is not None:
                items[target_id] = perf

        return {"items": items}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch last performance: {str(e)}")


@router.get("/exercises/{exercise_id}/last-performance")
async def get_exercise_last_performance(
    exercise_id: str,
    current_user: dict = Depends(get_current_user),
):
    """Alias endpoint for single exercise last performance and progressive overload suggestion"""
    try:
        user_id = str(current_user["_id"]) if current_user.get("_id") is not None else None
        email = current_user.get("email")
        owner_query = build_user_query(user_id, email)

        sessions = _safe_find(
            workout_history_collection,
            owner_query,
            sort=[("started_at", -1), ("created_at", -1)],
            limit=30,
        )

        perf = _find_last_performance_for_exercise(sessions, exercise_id)
        if not perf:
            return {"found": False}
        return perf
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch last performance: {str(e)}")


# ─── MUSCLE RECOVERY ENDPOINT ─────────────────────────────────────────────────

@router.get("/muscle-recovery", response_model=dict)
async def get_workout_muscle_recovery(
    current_user: dict = Depends(get_current_user),
):
    """Estimate 0-100% muscle recovery across 6 canonical muscle groups from the last 72 hours."""
    try:
        user_id = str(current_user["_id"]) if current_user.get("_id") is not None else None
        email = current_user.get("email")
        if not email and not user_id:
            raise HTTPException(status_code=401, detail="Unauthorized")

        now_utc = datetime.now(timezone.utc)
        owner_query = build_user_query(user_id, email)
        sessions = _safe_find(
            workout_history_collection,
            owner_query,
            sort=[("started_at", -1), ("created_at", -1)],
            limit=100,
        )

        exercise_muscle_cache: Dict[str, Tuple[List[str], List[str]]] = {}
        if exercises_collection is not None:
            for session_doc in sessions:
                raw_logs = session_doc.get("exercise_logs") or session_doc.get("completed_exercises") or []
                for item in raw_logs:
                    if not isinstance(item, dict):
                        continue
                    ex_id = str(item.get("exercise_id") or item.get("exerciseId") or "").strip()
                    ex_slug = str(item.get("exercise_slug") or item.get("exerciseSlug") or "").strip()
                    cache_key = ex_id or ex_slug
                    if not cache_key or cache_key in exercise_muscle_cache:
                        continue
                    or_clauses: List[dict] = []
                    if ex_slug:
                        or_clauses.append({"slug": ex_slug})
                    if ex_id:
                        or_clauses.append({"id": ex_id})
                        if ex_id != ex_slug:
                            or_clauses.append({"slug": ex_id})
                        if ObjectId.is_valid(ex_id):
                            or_clauses.append({"_id": ObjectId(ex_id)})
                    try:
                        ex_doc = exercises_collection.find_one({"$or": or_clauses}) if or_clauses else None
                    except Exception:
                        ex_doc = None
                    if isinstance(ex_doc, dict):
                        target_list: List[str] = []
                        primary_raw = ex_doc.get("muscleGroup") or ex_doc.get("muscle_group")
                        if isinstance(primary_raw, str) and primary_raw.strip():
                            target_list.append(primary_raw)
                        raw_targets = ex_doc.get("targetMuscles") or ex_doc.get("target_muscles") or []
                        if isinstance(raw_targets, list):
                            target_list.extend(str(tm) for tm in raw_targets if isinstance(tm, str))
                        raw_secondary = ex_doc.get("secondaryMuscles") or ex_doc.get("secondary_muscles") or []
                        secondary_list = (
                            [str(sm) for sm in raw_secondary if isinstance(sm, str)]
                            if isinstance(raw_secondary, list)
                            else []
                        )
                        exercise_muscle_cache[cache_key] = (target_list, secondary_list)

        recovery_result = calculate_muscle_recovery_load(
            sessions,
            now_utc,
            exercise_muscle_cache=exercise_muscle_cache or None,
        )

        return {
            "muscles": recovery_result["muscles"],
            "generatedAt": recovery_result["generatedAt"],
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Muscle recovery error: {str(e)}")


# ─── MUSCLE GROUP ENDPOINTS ───────────────────────────────────────────────────

MUSCLE_GROUPS = [
    {
        "slug": "back",
        "name": "Back",
        "nameVi": "Lưng",
        "iconUrl": None,
        "exerciseCount": 10,
    },
    # Các nhóm cơ khác sẽ thêm sau khi có data
]


@router.get("/muscle-groups", response_model=dict)
async def get_muscle_groups():
    """Lấy danh sách tất cả nhóm cơ có sẵn."""
    try:
        return {"muscleGroups": MUSCLE_GROUPS}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/muscle-groups/featured", response_model=dict)
async def get_featured_muscle_groups():
    """Lấy nhóm cơ nổi bật để hiển thị trên home screen."""
    try:
        # Hiện tại chỉ có back — sau này filter theo criteria khác
        featured = MUSCLE_GROUPS[:4]
        return {"muscleGroups": featured}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/muscle-groups/{slug}", response_model=dict)
async def get_muscle_group_detail(slug: str):
    """Lấy chi tiết 1 nhóm cơ + danh sách exercises thuộc nhóm đó."""
    try:
        # Validate slug tồn tại
        group = next((g for g in MUSCLE_GROUPS if g["slug"] == slug), None)
        if not group:
            raise HTTPException(status_code=404, detail=f"Muscle group '{slug}' not found")

        # Lấy exercises thuộc nhóm cơ này từ DB
        if exercises_collection is None:
            raise HTTPException(status_code=503, detail="Database unavailable")

        exercises = _safe_find(
            exercises_collection,
            {"muscleGroup": slug},
            limit=50,
        )
        exercises = [_serialize_mongo(e) for e in exercises]

        return {
            "muscleGroup": group,
            "exercises": exercises,
            "total": len(exercises),
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─── WORKOUT CV AI QUOTA AUTHORIZATION ────────────────────────────────────────

class WorkoutCvAuthorizeRequest(pd.BaseModel):
    exercise_slug: Optional[str] = None
    source_mode: str = "realtime"
    idempotency_key: Optional[str] = None


class WorkoutCvAuthorizeResponse(pd.BaseModel):
    allowed: bool
    paywall_enforced: bool = True
    tier: str
    benefit_id: str = WORKOUT_CV_BENEFIT_ID
    limit_units: int
    remaining_units: int
    operation_id: Optional[str] = None


def _raise_cv_storage_unavailable() -> None:
    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail={
            "code": "storage_unavailable",
            "benefit_id": WORKOUT_CV_BENEFIT_ID,
            "message": "Hệ thống kiểm tra hạn mức tạm thời gián đoạn. Vui lòng thử lại sau.",
        },
    )


def _compute_cv_bucket_remaining(
    db: Any,
    q_svc: Any,
    account_id: str,
    period_type: str,
    limit_units: int,
) -> Tuple[int, int]:
    """Reads current (effective_limit, remaining_units) from usage bucket for idempotent replays."""
    if limit_units < 0:
        return -1, -1
    try:
        now_utc = datetime.now(timezone.utc)
        window_start, _, bucket_key = q_svc._get_window_bounds(
            now_utc,
            period_type=period_type,
            benefit_id=WORKOUT_CV_BENEFIT_ID,
        )
        bucket_doc = db[COLL_USAGE_BUCKETS].find_one({
            "user_id": account_id,
            "bucket_key": bucket_key,
            "window_start": window_start,
        })
        if bucket_doc:
            consumed = int(bucket_doc.get("consumed_units", 0) or 0)
            reserved = int(bucket_doc.get("reserved_units", 0) or 0)
            lim = int(bucket_doc.get("limit_units", limit_units))
            bonus = int(bucket_doc.get("bonus_units", 0) or 0)
            effective_lim = lim + bonus if lim >= 0 else lim
            remaining = -1 if effective_lim < 0 else max(0, effective_lim - (consumed + reserved))
            return effective_lim, remaining
    except Exception as exc:
        logger.warning("Failed to read workout CV bucket remaining: %s", type(exc).__name__)
    return limit_units, max(0, limit_units)


@router.post("/cv/authorize", response_model=WorkoutCvAuthorizeResponse)
async def authorize_workout_cv(
    payload: Optional[WorkoutCvAuthorizeRequest] = Body(default=None),
    current_user: dict = Depends(get_current_user),
):
    """
    Authorizes and consumes 1 weekly unit of `workout.cv.ai` (Form Check AI)
    when ENABLE_AI_PAYWALL is enabled.
    """
    req = payload or WorkoutCvAuthorizeRequest()
    raw_email = current_user.get("email")
    email = raw_email.strip().lower() if isinstance(raw_email, str) and raw_email.strip() else ""
    raw_user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else ""
    raw_account_id = current_user.get("account_id")
    account_id_hint = (
        raw_account_id.strip()
        if isinstance(raw_account_id, str) and raw_account_id.strip()
        else ""
    )

    if not is_ai_paywall_enabled():
        tier_str = "free"
        free_limits = TIER_QUOTA_LIMITS.get(tier_str, {})
        _, default_limit = free_limits.get(WORKOUT_CV_BENEFIT_ID, ("weekly", 0))
        return WorkoutCvAuthorizeResponse(
            allowed=True,
            paywall_enforced=False,
            tier=tier_str,
            benefit_id=WORKOUT_CV_BENEFIT_ID,
            limit_units=default_limit,
            remaining_units=default_limit,
            operation_id=None,
        )

    db = _db_mod.db
    if (
        db is None
        or QuotaService is None
        or EntitlementService is None
        or resolve_or_create_account_id is None
        or resolve_user_tier_and_quota is None
    ):
        _raise_cv_storage_unavailable()

    auth_ref = account_id_hint or email or raw_user_id
    if not auth_ref:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
        )

    try:
        account_id = resolve_or_create_account_id(db, auth_ref)
    except Exception as exc:
        logger.warning("Workout CV account resolution failed: %s", type(exc).__name__)
        _raise_cv_storage_unavailable()

    # Evaluate entitlement via EntitlementService (detects storage outage / explicit revocation)
    try:
        ent_decision = EntitlementService(db=db).evaluate_entitlement(
            account_id,
            WORKOUT_CV_BENEFIT_ID,
        )
    except Exception as exc:
        logger.warning("Workout CV entitlement evaluation failed: %s", type(exc).__name__)
        _raise_cv_storage_unavailable()

    if EntitlementDecisionStatus is not None:
        if ent_decision.status == EntitlementDecisionStatus.STORAGE_UNAVAILABLE:
            _raise_cv_storage_unavailable()
        if ent_decision.status == EntitlementDecisionStatus.REVOKED:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "entitlement_required",
                    "benefit_id": WORKOUT_CV_BENEFIT_ID,
                    "message": "Gói hiện tại chưa bao gồm tính năng Form Check AI. Nâng cấp Pro để sử dụng.",
                },
            )

    # Resolve effective tier & dynamic quota limit from TIER_QUOTA_LIMITS (plus active grants)
    try:
        effective_tier, period_type, limit_units = resolve_user_tier_and_quota(
            db,
            user_id=account_id,
            email=email or None,
            benefit_id=WORKOUT_CV_BENEFIT_ID,
        )
    except Exception as exc:
        if QuotaStorageUnavailableException is not None and isinstance(exc, QuotaStorageUnavailableException):
            _raise_cv_storage_unavailable()
        logger.warning("Workout CV tier/quota resolution failed: %s", type(exc).__name__)
        _raise_cv_storage_unavailable()

    tier_str = effective_tier.value if hasattr(effective_tier, "value") else str(effective_tier or "free")
    if ent_decision.tier is not None and tier_str == "free":
        tier_str = ent_decision.tier.value
        tier_limits = TIER_QUOTA_LIMITS.get(tier_str, TIER_QUOTA_LIMITS.get("free", {}))
        period_type, limit_units = tier_limits.get(WORKOUT_CV_BENEFIT_ID, (period_type, limit_units))

    q_svc = QuotaService(db=db)

    if limit_units == 0:
        has_bonus_quota = False
        try:
            now_utc = datetime.now(timezone.utc)
            window_start, _, bucket_key = q_svc._get_window_bounds(
                now_utc,
                period_type=period_type,
                benefit_id=WORKOUT_CV_BENEFIT_ID,
            )
            bucket_doc = db[COLL_USAGE_BUCKETS].find_one({
                "user_id": account_id,
                "bucket_key": bucket_key,
                "window_start": window_start,
            })
            if bucket_doc:
                b_bonus = int(bucket_doc.get("bonus_units", 0) or 0)
                b_consumed = int(bucket_doc.get("consumed_units", 0) or 0)
                b_reserved = int(bucket_doc.get("reserved_units", 0) or 0)
                if (limit_units + b_bonus) > (b_consumed + b_reserved):
                    has_bonus_quota = True
        except Exception as exc:
            logger.warning("Failed to inspect workout CV bonus bucket: %s", type(exc).__name__)

        if not has_bonus_quota:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "entitlement_required",
                    "benefit_id": WORKOUT_CV_BENEFIT_ID,
                    "message": "Gói hiện tại chưa bao gồm tính năng Form Check AI. Nâng cấp Pro để sử dụng.",
                },
            )

    idem_key = (
        req.idempotency_key.strip()
        if isinstance(req.idempotency_key, str) and req.idempotency_key.strip()
        else f"cv:{uuid4().hex}"
    )

    res = q_svc.reserve_quota(
        user_id=account_id,
        benefit_id=WORKOUT_CV_BENEFIT_ID,
        units=1,
        limit_units=limit_units,
        period_type=period_type,
        idempotency_key=idem_key,
    )

    if ReservationStatus is not None:
        if res.status == ReservationStatus.STORAGE_UNAVAILABLE:
            _raise_cv_storage_unavailable()
        if res.status == ReservationStatus.QUOTA_EXHAUSTED:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "code": "quota_exceeded",
                    "benefit_id": WORKOUT_CV_BENEFIT_ID,
                    "limit_units": res.limit_units if res.limit_units is not None else limit_units,
                    "remaining_units": 0,
                    "message": "Bạn đã dùng hết lượt Form Check AI trong tuần. Nâng cấp Pro để dùng không giới hạn.",
                },
            )
        if res.status == ReservationStatus.OPERATION_CONFLICT:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "operation_conflict",
                    "benefit_id": WORKOUT_CV_BENEFIT_ID,
                    "message": res.error_message or "Yêu cầu xung đột với thao tác trước đó.",
                },
            )
        if res.status == ReservationStatus.RESERVED and res.operation_id:
            q_svc.commit_quota(
                res.operation_id,
                lease_token=res.lease_token,
            )
            eff_limit = res.limit_units if res.limit_units is not None else limit_units
            rem_units = (
                -1
                if eff_limit < 0
                else (res.remaining_units if res.remaining_units is not None else max(0, eff_limit - 1))
            )
            return WorkoutCvAuthorizeResponse(
                allowed=True,
                paywall_enforced=True,
                tier=tier_str,
                benefit_id=WORKOUT_CV_BENEFIT_ID,
                limit_units=eff_limit,
                remaining_units=rem_units,
                operation_id=res.operation_id,
            )
        if res.status in (ReservationStatus.ALREADY_COMPLETED, ReservationStatus.IN_PROGRESS):
            eff_limit, rem_units = _compute_cv_bucket_remaining(
                db=db,
                q_svc=q_svc,
                account_id=account_id,
                period_type=period_type,
                limit_units=limit_units,
            )
            return WorkoutCvAuthorizeResponse(
                allowed=True,
                paywall_enforced=True,
                tier=tier_str,
                benefit_id=WORKOUT_CV_BENEFIT_ID,
                limit_units=eff_limit,
                remaining_units=rem_units,
                operation_id=res.operation_id,
            )

    _raise_cv_storage_unavailable()


# ─── WORKOUT VIDEO STORIES & CLOUD STORAGE (PHASE 3) ─────────────────────────

def _get_user_video_story_used_bytes(col, account_id: str) -> int:
    """Calculate cumulative size_bytes of Video Stories owned by account_id.

    Compatible with both real MongoDB aggregate and in-memory mock collections.
    """
    if col is None or not account_id:
        return 0
    try:
        if hasattr(col, "aggregate"):
            pipeline = [
                {"$match": {"account_id": account_id}},
                {"$group": {"_id": None, "total_bytes": {"$sum": "$size_bytes"}}},
            ]
            res = list(col.aggregate(pipeline))
            if res and isinstance(res[0], dict):
                return int(res[0].get("total_bytes", 0) or 0)
    except Exception as exc:
        logger.debug("Mongo aggregate for video story bytes failed: %s, falling back to find", exc)

    try:
        cursor = col.find({"account_id": account_id})
        return sum(int(doc.get("size_bytes", 0) or 0) for doc in cursor if isinstance(doc, dict))
    except Exception as exc:
        logger.warning("Failed to calculate used video story bytes for account %s: %s", account_id, exc)
        return 0


def _resolve_account_id_and_tier_for_workout(current_user: dict) -> Tuple[str, str]:
    """Helper to resolve normalized account_id and effective membership tier."""
    raw_email = current_user.get("email")
    email = raw_email.strip().lower() if isinstance(raw_email, str) and raw_email.strip() else ""
    raw_user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else ""
    raw_account_id = current_user.get("account_id")
    account_id_hint = (
        raw_account_id.strip()
        if isinstance(raw_account_id, str) and raw_account_id.strip()
        else ""
    )

    db = _db_mod.db
    auth_ref = account_id_hint or email or raw_user_id
    if not auth_ref:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
        )

    account_id = auth_ref
    if db is not None and resolve_or_create_account_id is not None:
        try:
            account_id = resolve_or_create_account_id(db, auth_ref)
        except Exception as exc:
            logger.warning("Account ID resolution failed: %s", exc)

    tier_str = "free"
    if db is not None and resolve_user_tier_and_quota is not None:
        try:
            eff_tier, _, _ = resolve_user_tier_and_quota(
                db,
                user_id=account_id,
                email=email or None,
                benefit_id=WORKOUT_CV_BENEFIT_ID,
            )
            tier_str = eff_tier.value if hasattr(eff_tier, "value") else str(eff_tier or "free")
        except Exception as exc:
            logger.warning("Tier resolution failed: %s", exc)

    return account_id, tier_str.lower()


@router.post("/video-stories/presign", response_model=VideoStoryPresignResponse)
async def presign_video_story(
    req: VideoStoryPresignRequest,
    current_user: dict = Depends(get_current_user),
):
    """Generate a presigned upload slot for Workout Video Story based on membership cloud quota."""
    if req.content_type not in ALLOWED_VIDEO_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported content_type: {req.content_type}. Allowed: {sorted(ALLOWED_VIDEO_CONTENT_TYPES)}",
        )

    if req.size_bytes > MAX_VIDEO_STORY_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Video file exceeds maximum allowed size of {MAX_VIDEO_STORY_BYTES // (1024 * 1024)} MB.",
        )

    account_id, tier = _resolve_account_id_and_tier_for_workout(current_user)
    limit_mb = get_video_story_storage_limit_mb(tier)

    story_col = getattr(_db_mod, "workout_video_stories_collection", None)
    if story_col is None and _db_mod.db is not None:
        story_col = _db_mod.db["workout_video_stories"]

    used_bytes = _get_user_video_story_used_bytes(story_col, account_id)

    if limit_mb <= 0:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "entitlement_required",
                "benefit_id": "workout.video_story.cloud_mb",
                "limit_mb": 0,
                "used_bytes": used_bytes,
                "message": "Gói Free chỉ lưu chỉ số JSON. Nâng cấp Plus/Pro/Ultra để lưu Video Workout Story lên Cloud.",
            },
        )

    limit_bytes = limit_mb * 1024 * 1024
    if used_bytes + req.size_bytes > limit_bytes:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "code": "storage_quota_exceeded",
                "benefit_id": "workout.video_story.cloud_mb",
                "limit_mb": limit_mb,
                "used_bytes": used_bytes,
                "message": "Bạn đã dùng hết dung lượng Cloud Video Story của gói hiện tại.",
            },
        )

    story_id = uuid4().hex
    ext = "mov" if req.content_type == "video/quicktime" else "mp4"
    storage_key = f"saman/workouts/{account_id}/{story_id}.{ext}"

    try:
        storage_svc = get_media_storage_service()
        presigned = storage_svc.generate_presigned_upload_url(
            storage_key=storage_key,
            content_type=req.content_type,
            max_bytes=req.size_bytes,
            expires_in=900,
        )
    except MediaStorageConfigError as exc:
        logger.error("Media storage configuration error: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Media storage is not configured or unavailable.",
        )
    except Exception as exc:
        logger.error("Failed to generate presigned upload url: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate presigned upload URL: {exc}",
        )

    return VideoStoryPresignResponse(
        story_id=story_id,
        storage_key=storage_key,
        upload_url=presigned.upload_url,
        public_url=presigned.public_url,
        headers=presigned.headers,
        expires_in=presigned.expires_in,
        limit_mb=limit_mb,
        used_bytes=used_bytes,
    )


@router.post("/video-stories/complete", response_model=VideoStoryCompleteResponse)
async def complete_video_story(
    req: VideoStoryCompleteRequest,
    current_user: dict = Depends(get_current_user),
):
    """Complete upload and record metadata for Workout Video Story with retention policy."""
    if req.size_bytes > MAX_VIDEO_STORY_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Video file exceeds maximum allowed size of {MAX_VIDEO_STORY_BYTES // (1024 * 1024)} MB.",
        )

    account_id, tier = _resolve_account_id_and_tier_for_workout(current_user)
    raw_user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else account_id

    # Anti-tampering check: storage_key MUST strictly belong to this account
    expected_prefix = f"saman/workouts/{account_id}/"
    if not req.storage_key.startswith(expected_prefix) or ".." in req.storage_key:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied to storage_key: invalid prefix or traversal sequence.",
        )

    story_col = getattr(_db_mod, "workout_video_stories_collection", None)
    if story_col is None and _db_mod.db is not None:
        story_col = _db_mod.db["workout_video_stories"]
    if story_col is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Database unavailable")

    limit_mb = get_video_story_storage_limit_mb(tier)
    if limit_mb <= 0:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "entitlement_required",
                "benefit_id": "workout.video_story.cloud_mb",
                "limit_mb": 0,
                "used_bytes": 0,
                "message": "Gói Free chỉ lưu chỉ số JSON. Nâng cấp Plus/Pro/Ultra để lưu Video Workout Story lên Cloud.",
            },
        )

    # Check if this exact story already exists for idempotent replay
    existing_story = story_col.find_one({"story_id": req.story_id, "account_id": account_id})
    used_bytes = _get_user_video_story_used_bytes(story_col, account_id)
    limit_bytes = limit_mb * 1024 * 1024

    if existing_story:
        old_size = int(existing_story.get("size_bytes", 0) or 0)
        net_addition = req.size_bytes - old_size
        if used_bytes + net_addition > limit_bytes:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "code": "storage_quota_exceeded",
                    "benefit_id": "workout.video_story.cloud_mb",
                    "limit_mb": limit_mb,
                    "used_bytes": used_bytes,
                    "message": "Bạn đã dùng hết dung lượng Cloud Video Story của gói hiện tại.",
                },
            )
    else:
        if used_bytes + req.size_bytes > limit_bytes:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "code": "storage_quota_exceeded",
                    "benefit_id": "workout.video_story.cloud_mb",
                    "limit_mb": limit_mb,
                    "used_bytes": used_bytes,
                    "message": "Bạn đã dùng hết dung lượng Cloud Video Story của gói hiện tại.",
                },
            )

    now_utc = datetime.now(timezone.utc)
    vn_date = now_utc.astimezone(ICT_ZONE).strftime("%Y-%m-%d")
    citation_days = get_video_citation_days(tier)
    retention_expires_at = (
        (now_utc + timedelta(days=citation_days)).isoformat().replace("+00:00", "Z")
        if citation_days > 0
        else None
    )

    timeline_data = [
        item.model_dump(by_alias=False) if hasattr(item, "model_dump") else dict(item)
        for item in req.rep_timeline
    ]

    doc = {
        "story_id": req.story_id,
        "video_story_id": req.story_id,
        "account_id": account_id,
        "user_id": raw_user_id,
        "workout_session_id": req.workout_session_id,
        "exercise_slug": req.exercise_slug,
        "date": vn_date,
        "created_at": now_utc.isoformat().replace("+00:00", "Z"),
        "storage_key": req.storage_key,
        "video_url": req.video_url,
        "thumbnail_url": req.thumbnail_url,
        "duration_sec": req.duration_sec,
        "size_bytes": req.size_bytes,
        "resolution": req.resolution,
        "retention_expires_at": retention_expires_at,
        "cv_form_summary": req.cv_form_summary,
        "rep_timeline": timeline_data,
    }

    try:
        story_col.update_one(
            {"story_id": req.story_id, "account_id": account_id},
            {"$set": doc},
            upsert=True,
        )
    except Exception as exc:
        logger.error("Failed to persist video story document: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to record video story: {exc}",
        )

    updated_used_bytes = _get_user_video_story_used_bytes(story_col, account_id)
    return VideoStoryCompleteResponse(
        video_story_id=req.story_id,
        video_url=req.video_url,
        storage_key=req.storage_key,
        size_bytes=req.size_bytes,
        used_bytes=updated_used_bytes,
        limit_mb=limit_mb,
        retention_expires_at=retention_expires_at,
    )


@router.get("/video-stories/{story_id}", response_model=VideoStoryDetailResponse)
async def get_video_story_detail(
    story_id: str,
    current_user: dict = Depends(get_current_user),
):
    """Retrieve full detail of a Video Story isolated by account_id."""
    account_id, _ = _resolve_account_id_and_tier_for_workout(current_user)

    story_col = getattr(_db_mod, "workout_video_stories_collection", None)
    if story_col is None and _db_mod.db is not None:
        story_col = _db_mod.db["workout_video_stories"]
    if story_col is None:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Database unavailable")

    doc = story_col.find_one({"story_id": story_id, "account_id": account_id})
    if not doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Video story not found")

    tl_raw = doc.get("rep_timeline") or []
    rep_timeline_out = []
    for r in tl_raw:
        if isinstance(r, dict):
            rep_timeline_out.append(
                RepTimelineItem(
                    rep_index=int(r.get("rep_index", r.get("repIndex", 1))),
                    start_sec=float(r.get("start_sec", r.get("startSec", 0.0))),
                    bottom_sec=float(r.get("bottom_sec", r.get("bottomSec", 0.0))),
                    end_sec=float(r.get("end_sec", r.get("endSec", 0.0))),
                    duration_sec=float(r.get("duration_sec", r.get("durationSec", 0.0))),
                    metric_angle_deg=(
                        float(r["metric_angle_deg"])
                        if r.get("metric_angle_deg") is not None
                        else (float(r["metricAngleDeg"]) if r.get("metricAngleDeg") is not None else None)
                    ),
                    is_valid=bool(r.get("is_valid", r.get("isValid", True))),
                    issue_type=str(r.get("issue_type", r.get("issueType", "none"))),
                    view_angle=str(r.get("view_angle", r.get("viewAngle", "unknown"))),
                    visibility_confidence=float(r.get("visibility_confidence", r.get("visibilityConfidence", 1.0))),
                )
            )

    created_at_val = doc.get("created_at")
    if isinstance(created_at_val, datetime):
        created_at_str = created_at_val.isoformat().replace("+00:00", "Z")
    else:
        created_at_str = str(created_at_val or "")

    return VideoStoryDetailResponse(
        video_story_id=str(doc.get("video_story_id") or doc.get("story_id") or ""),
        account_id=str(doc.get("account_id") or ""),
        user_id=str(doc.get("user_id") or ""),
        workout_session_id=str(doc["workout_session_id"]) if doc.get("workout_session_id") else None,
        exercise_slug=str(doc.get("exercise_slug") or ""),
        date=str(doc.get("date") or ""),
        created_at=created_at_str,
        storage_key=str(doc.get("storage_key") or ""),
        video_url=str(doc.get("video_url") or ""),
        thumbnail_url=str(doc["thumbnail_url"]) if doc.get("thumbnail_url") else None,
        duration_sec=float(doc.get("duration_sec", 0.0)),
        size_bytes=int(doc.get("size_bytes", 0)),
        resolution=str(doc["resolution"]) if doc.get("resolution") else None,
        retention_expires_at=str(doc["retention_expires_at"]) if doc.get("retention_expires_at") else None,
        cv_form_summary=doc.get("cv_form_summary"),
        rep_timeline=rep_timeline_out,
    )


# ---------------------------------------------------------------------------
# CV Telemetry (Opt-in Data Flywheel)
# ---------------------------------------------------------------------------
def _is_user_cv_telemetry_opted_in(user_doc: dict) -> bool:
    """Check if the user has explicitly opted in to CV telemetry.

    Looks into top-level preferences.cv_telemetry_opt_in and profile.preferences.cv_telemetry_opt_in.
    Only returns True if explicitly boolean True.
    """
    if not isinstance(user_doc, dict):
        return False
    top_prefs = user_doc.get("preferences")
    if isinstance(top_prefs, dict) and top_prefs.get("cv_telemetry_opt_in") is True:
        return True
    prof = user_doc.get("profile")
    if isinstance(prof, dict):
        prof_prefs = prof.get("preferences")
        if isinstance(prof_prefs, dict) and prof_prefs.get("cv_telemetry_opt_in") is True:
            return True
    return False


def _compute_anonymous_subject_hash(account_id_or_uid: str) -> str:
    """One-way anonymous hash for CV telemetry."""
    salt = os.getenv("CV_TELEMETRY_HASH_SALT", "saman-ultra-p5-anon-v1")
    raw = f"{salt}:{account_id_or_uid}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:16]


@router.post("/cv/telemetry", response_model=WorkoutCvTelemetryOut, status_code=status.HTTP_201_CREATED)
async def submit_workout_cv_telemetry(
    payload: WorkoutCvTelemetryIn,
    current_user: dict = Depends(get_current_user),
):
    """Receive anonymous 33-landmark coordinate sequence (Opt-in Data Flywheel).

    - Strictly verifies opt-in before accepting telemetry.
    - Anonymizes subject via one-way hash (no PII, no video/images stored).
    - Validates gzip base64 payload size <= 256 KB.
    """
    users_col = getattr(_db_mod, "users_collection", None)
    if users_col is None and _db_mod.db is not None:
        users_col = _db_mod.db["users"]

    fresh_user = None
    if users_col is not None and current_user.get("_id") is not None:
        try:
            fresh_user = users_col.find_one({"_id": current_user["_id"]})
        except Exception:
            fresh_user = None

    eval_user = fresh_user if isinstance(fresh_user, dict) else current_user
    if not _is_user_cv_telemetry_opted_in(eval_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "telemetry_opt_in_required",
                "message": "Bạn cần bật tùy chọn chia sẻ dữ liệu xương ẩn danh trong Cài đặt trước khi gửi.",
            },
        )

    if payload.payload_encoding not in ALLOWED_TELEMETRY_ENCODINGS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported payloadEncoding: {payload.payload_encoding}. Allowed: {sorted(ALLOWED_TELEMETRY_ENCODINGS)}",
        )

    try:
        raw_bytes = base64.b64decode(payload.compressed_payload_b64, validate=True)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid base64 in compressedPayloadB64: {exc}",
        )

    payload_bytes_len = len(raw_bytes)
    if payload_bytes_len < 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Payload cannot be empty",
        )

    if payload_bytes_len > MAX_CV_TELEMETRY_PAYLOAD_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"Payload size ({payload_bytes_len} bytes) exceeds maximum limit of {MAX_CV_TELEMETRY_PAYLOAD_BYTES} bytes (256 KB).",
        )

    # Decompress / inspect payload to verify it is valid JSON and contains NO PII/video keys
    FORBIDDEN_KEYS = {"email", "user_email", "password", "image_base64", "video_url", "full_name", "phone"}
    if payload.payload_encoding == "gzip_json_b64":
        if not raw_bytes.startswith(b"\x1f\x8b"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid gzip header for gzip_json_b64 payload.",
            )
        try:
            decompressed = gzip.decompress(raw_bytes)
            if len(decompressed) > 2 * 1024 * 1024:  # 2 MB limit
                raise HTTPException(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    detail="Decompressed payload exceeds safety limit (2 MB).",
                )
            decompressed_text = decompressed.decode("utf-8")
            parsed_json = json.loads(decompressed_text)
            if isinstance(parsed_json, dict):
                found_keys = FORBIDDEN_KEYS.intersection(set(parsed_json.keys()))
                if found_keys:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"Payload contains sensitive/forbidden key(s): {sorted(found_keys)}",
                    )
        except HTTPException:
            raise
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Failed to decompress and parse gzip JSON payload: {exc}",
            )
    elif payload.payload_encoding == "json_compact":
        try:
            parsed_json = json.loads(raw_bytes.decode("utf-8"))
            if isinstance(parsed_json, dict):
                found_keys = FORBIDDEN_KEYS.intersection(set(parsed_json.keys()))
                if found_keys:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"Payload contains sensitive/forbidden key(s): {sorted(found_keys)}",
                    )
        except HTTPException:
            raise
        except Exception as exc:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Failed to parse JSON compact payload: {exc}",
            )

    account_id, _ = _resolve_account_id_and_tier_for_workout(current_user)
    subject_hash = _compute_anonymous_subject_hash(account_id)

    effective_adjusted = bool(
        payload.user_adjusted_reps
        or (payload.final_logged_reps is not None and payload.final_logged_reps != payload.cv_reps)
    )
    priority_bucket = "high_rep_correction" if effective_adjusted else "standard"

    telemetry_col = getattr(_db_mod, "workout_cv_telemetry_collection", None)
    if telemetry_col is None and _db_mod.db is not None:
        telemetry_col = _db_mod.db["workout_cv_telemetry"]

    telemetry_id = f"tel_{uuid4().hex}"
    now_utc = datetime.now(timezone.utc)
    created_at_str = now_utc.isoformat().replace("+00:00", "Z")

    telemetry_doc = {
        "telemetry_id": telemetry_id,
        "subject_hash": subject_hash,
        "exercise_slug": payload.exercise_slug,
        "view_angle": payload.view_angle,
        "fps": payload.fps,
        "frame_count": payload.frame_count,
        "cv_reps": payload.cv_reps,
        "final_logged_reps": payload.final_logged_reps,
        "user_adjusted_reps": effective_adjusted,
        "priority_bucket": priority_bucket,
        "ml_mode": payload.ml_mode,
        "payload_encoding": payload.payload_encoding,
        "compressed_payload_b64": payload.compressed_payload_b64,
        "payload_bytes": payload_bytes_len,
        "client_schema_version": payload.client_schema_version,
        "created_at": created_at_str,
    }

    if telemetry_col is not None:
        try:
            telemetry_col.insert_one(telemetry_doc)
        except Exception as exc:
            logger.error("Failed to insert telemetry document: %s", exc)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Failed to store telemetry data: {exc}",
            )

    return WorkoutCvTelemetryOut(
        telemetry_id=telemetry_id,
        subject_hash=subject_hash,
        exercise_slug=payload.exercise_slug,
        frame_count=payload.frame_count,
        payload_bytes=payload_bytes_len,
        user_adjusted_reps=effective_adjusted,
        priority_bucket=priority_bucket,
        created_at=created_at_str,
    )


@router.get("/cv/telemetry/stats", response_model=WorkoutCvTelemetryStatsOut)
async def get_workout_cv_telemetry_stats(
    current_user: dict = Depends(get_current_user),
):
    """Retrieve anonymous telemetry stats for the current user."""
    users_col = getattr(_db_mod, "users_collection", None)
    if users_col is None and _db_mod.db is not None:
        users_col = _db_mod.db["users"]

    fresh_user = None
    if users_col is not None and current_user.get("_id") is not None:
        try:
            fresh_user = users_col.find_one({"_id": current_user["_id"]})
        except Exception:
            fresh_user = None

    eval_user = fresh_user if isinstance(fresh_user, dict) else current_user
    opt_in = _is_user_cv_telemetry_opted_in(eval_user)

    account_id, _ = _resolve_account_id_and_tier_for_workout(current_user)
    subject_hash = _compute_anonymous_subject_hash(account_id)

    telemetry_col = getattr(_db_mod, "workout_cv_telemetry_collection", None)
    if telemetry_col is None and _db_mod.db is not None:
        telemetry_col = _db_mod.db["workout_cv_telemetry"]

    total_clips = 0
    rep_correction_clips = 0

    if telemetry_col is not None:
        try:
            total_clips = telemetry_col.count_documents({"subject_hash": subject_hash})
            rep_correction_clips = telemetry_col.count_documents({
                "subject_hash": subject_hash,
                "user_adjusted_reps": True,
            })
        except Exception as exc:
            logger.warning("Failed to count telemetry documents: %s", exc)

    return WorkoutCvTelemetryStatsOut(
        cv_telemetry_opt_in=opt_in,
        total_clips_contributed=total_clips,
        rep_correction_clips=rep_correction_clips,
        subject_hash=subject_hash,
    )

