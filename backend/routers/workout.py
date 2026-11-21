# [File: routers/workout.py]
from fastapi import APIRouter, Depends, HTTPException, Query
from datetime import datetime, date, timedelta, timezone
from zoneinfo import ZoneInfo
from typing import Optional, List, Dict, Any
import hashlib
import re
import pydantic as pd
from bson import ObjectId
from pymongo.errors import DuplicateKeyError

# Import dependencies
from backend.auth_utils import verify_token, get_current_user
from backend.app.repositories.user_repository import UserRepository
from backend.app.database import workout_history_collection, custom_plans_collection, exercises_collection
from backend.app.services.context_utils import (
    build_user_query,
    get_vn_date_str,
    get_vn_day_range_utc,
    normalize_email,
    utc_to_vn_date_str,
)

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

    class Config:
        allow_population_by_field_name = True


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


def _session_fingerprint(doc: dict) -> tuple:
    return (
        doc.get("plan_id"),
        doc.get("plan_name"),
        _utc_ms(doc.get("started_at")),
        _utc_ms(doc.get("finished_at")),
        doc.get("exercise_logs") or [],
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
        if session.exercise_logs:
            for item in session.exercise_logs:
                cv_summary = item.cv_form_summary if isinstance(item.cv_form_summary, dict) else None
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
                })
        elif session.completed_exercises:
            for e in session.completed_exercises:
                raw_item = dict(e)
                cv_summary = raw_item.get("cv_form_summary") or raw_item.get("cvFormSummary")
                if not isinstance(cv_summary, dict):
                    cv_summary = None
                raw_item["cv_form_summary"] = cv_summary
                logs_data.append(raw_item)

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

        idempotent_id = _idempotent_session_object_id(user_id, session.id)
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

        serialized = _serialize_workout_session(doc)
        return {
            "message": "Workout session logged successfully",
            "session_id": str(doc["_id"]),
            "session": serialized,
            "logged_at": logged_at.isoformat(),
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
