"""Bounded, principal-scoped read context for Core 3 chat requests."""

import json
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional
from bson import ObjectId

try:
    from backend.app.services.context_utils import (
        build_user_query,
        get_vn_date_str,
        get_vn_day_range_utc,
        normalize_email,
        utc_to_vn_date_str,
    )
except ImportError:
    from app.services.context_utils import (
        build_user_query,
        get_vn_date_str,
        get_vn_day_range_utc,
        normalize_email,
        utc_to_vn_date_str,
    )

try:
    from backend.app.services.journey_context import build_journey_context
except ImportError:
    from app.services.journey_context import build_journey_context

try:
    from backend.app.services.story_community_context import (
        build_community_context,
        build_story_logs_context,
    )
except ImportError:
    from app.services.story_community_context import (
        build_community_context,
        build_story_logs_context,
    )

try:
    from backend.app.services.recommendations_context import build_recommendations_context
except ImportError:
    from app.services.recommendations_context import build_recommendations_context

try:
    from backend.app.services.intent_router import IntentRouteResult
except ImportError:
    from app.services.intent_router import IntentRouteResult

try:
    from backend.app.services.workout_recovery_helper import (
        calculate_muscle_recovery_load,
        compact_muscle_recovery_for_ai,
        compute_rolling_anomaly_tags,
    )
except ImportError:
    from app.services.workout_recovery_helper import (
        calculate_muscle_recovery_load,
        compact_muscle_recovery_for_ai,
        compute_rolling_anomaly_tags,
    )

try:
    from backend.app.services.quota_service import get_video_citation_days
except ImportError:
    try:
        from app.services.quota_service import get_video_citation_days
    except ImportError:
        def get_video_citation_days(tier: str) -> int:
            return {"free": 0, "plus": 7, "pro": 14, "ultra": 30}.get((tier or "free").lower(), 0)



_PROFILE_FIELDS = (
    "profile", "health_stats", "preferences", "age", "gender", "activity_level",
    "goal", "weight", "height", "tdee_value",
)
_SAFE_PROFILE_FIELDS = ("age", "gender", "activity_level", "goal", "weight", "height")
_USER_PROJECTION = {
    "_id": 0,
    **{field: 1 for field in _PROFILE_FIELDS if field != "profile"},
    **{f"profile.{field}": 1 for field in _SAFE_PROFILE_FIELDS},
}


def _status(rows, truncated=False):
    if rows is None:
        return {"status": "unavailable", "coverage_truncated": False, "coverage_missing": True}
    if not rows:
        return {"status": "empty", "coverage_truncated": bool(truncated), "coverage_missing": True}
    return {"status": "available", "coverage_truncated": bool(truncated), "coverage_missing": bool(truncated)}


def _number(value):
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _date_bounds(today, days):
    start_str = get_vn_date_str(offset_days=-(days - 1), now=today)
    end_str = get_vn_date_str(now=today)
    start, _ = get_vn_day_range_utc(start_str)
    _, end_of_last_day = get_vn_day_range_utc(end_str)
    # The helper returns the last microsecond of the day; use an exclusive bound.
    end = end_of_last_day + timedelta(microseconds=1)
    return start_str, end_str, start, end


def _user_and_date_query(identity_query, date_query):
    return {"$and": [identity_query, date_query]}


def _parse_utc_naive(value) -> Optional[datetime]:
    """Parse datetime or ISO string into a UTC-naive datetime for safe comparison."""
    if value is None:
        return None
    if isinstance(value, str):
        raw = value.strip()
        if not raw:
            return None
        try:
            value = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except (ValueError, TypeError):
            return None
    if not isinstance(value, datetime):
        return None
    if value.tzinfo is not None:
        return value.astimezone(timezone.utc).replace(tzinfo=None)
    return value


def _is_after_day_reset(created_at, reset_at) -> bool:
    """Return True iff created_at is a valid timestamp strictly after reset_at."""
    created_dt = _parse_utc_naive(created_at)
    reset_dt = _parse_utc_naive(reset_at)
    if created_dt is None or reset_dt is None:
        return False
    return created_dt > reset_dt


def _resolve_day_resets_collection(nutrition_collection, day_resets_collection=None):
    if day_resets_collection is not None:
        return day_resets_collection
    try:
        col_db = getattr(nutrition_collection, "database", None)
        if col_db is not None:
            return col_db["day_resets"]
    except Exception:
        pass
    return None


def _compact_exercises(logs):
    grouped = {}
    truncated = len(logs) >= 200
    for item in logs[:200]:
        if not isinstance(item, dict):
            continue
        name = str(item.get("exercise_slug") or item.get("exercise_id") or item.get("name") or "Exercise")
        entry = grouped.setdefault(name, {"name": name, "sets": 0, "max_weight_kg": None, "total_reps": 0})
        entry["sets"] += int(_number(item.get("sets")) or 1)
        weight = _number(item.get("weight_kg", item.get("weight", item.get("max_weight_kg"))))
        if weight is not None:
            entry["max_weight_kg"] = max(entry["max_weight_kg"] or weight, weight)
        reps = _number(item.get("reps", item.get("reps_completed", item.get("total_reps"))))
        if reps is not None:
            entry["total_reps"] += int(reps)
        cv_summary = item.get("cv_form_summary") or item.get("cvFormSummary")
        if isinstance(cv_summary, dict):
            entry["cv_form_summary"] = {
                key: cv_summary[key]
                for key in ("valid_reps", "fast_reps", "avg_elbow_angle_deg", "avg_tempo_sec")
                if key in cv_summary
            }
        if item.get("reps_summary") is not None:
            entry["reps_summary"] = str(item["reps_summary"])[:120]

        # Extract video_story_id if present
        v_id = item.get("video_story_id") or item.get("videoStoryId")
        if v_id and "video_story_id" not in entry:
            entry["video_story_id"] = str(v_id)

        # Extract compact rep timeline with visibility_confidence >= 0.6
        rep_tl = item.get("rep_timeline") or item.get("repTimeline")
        if isinstance(rep_tl, list) and rep_tl:
            faulty_reps = []
            for r in rep_tl:
                if not isinstance(r, dict):
                    continue
                vis = float(r.get("visibility_confidence") if r.get("visibility_confidence") is not None else r.get("visibilityConfidence", 1.0))
                if vis < 0.6:
                    continue
                issue = r.get("issue_type") or r.get("issueType")
                if issue and issue != "none":
                    faulty_reps.append({
                        "rep": int(r.get("rep_index", r.get("repIndex", 0)) or 0),
                        "issue": str(issue),
                        "vis": round(vis, 2),
                    })
            if faulty_reps:
                entry.setdefault("rep_issues", []).extend(faulty_reps[:5])

    exercises = list(grouped.values())
    for exercise in exercises:
        if exercise["total_reps"] == 0:
            exercise.pop("total_reps")
        if exercise["max_weight_kg"] is None:
            exercise.pop("max_weight_kg")
        if "rep_issues" in exercise and isinstance(exercise["rep_issues"], list):
            exercise["rep_issues"] = exercise["rep_issues"][:5]
    return exercises[:8], truncated or len(exercises) > 8


def _normalized_preferences(user_doc):
    prefs = user_doc.get("preferences") or {}
    if not isinstance(prefs, dict):
        prefs = {}
    persona = prefs.get("coach_persona") or prefs.get("reply_style")
    result = {
        "coach_persona": persona,
        "reply_style": prefs.get("reply_style") or persona,
    }
    for key in ("food_dislikes", "equipment", "target_muscles", "notes"):
        value = prefs.get(key, [] if key != "notes" else "")
        if isinstance(value, list):
            result[key] = [str(item)[:100] for item in value[:12]]
        elif isinstance(value, str):
            result[key] = value[:300]
        elif value is not None:
            result[key] = value
        else:
            result[key] = [] if key != "notes" else ""
    for key in ("coach_persona", "reply_style"):
        if isinstance(result[key], str):
            result[key] = result[key][:100]
    return result


def build_core3_context(
    *, principal, nutrition_collection, workout_collection, users_collection,
    water_collection=None, weight_history_collection=None,
    journeys_collection=None, story_logs_collection=None,
    community_posts_collection=None, community_interactions_collection=None,
    community_follows_collection=None,
    shop_products_collection=None, journal_articles_collection=None,
    supplements_collection=None, recipes_collection=None,
    day_resets_collection=None,
    question=None,
    tier="core3", now=None,
    intent_route: Optional[IntentRouteResult] = None,
    video_stories_collection: Any = None,
    membership_tier: str = "free",
    account_id: Optional[str] = None,
):
    """Read bounded, allowlisted user context using Vietnam calendar-day windows."""
    tier = (tier or "core3").strip().lower()
    if tier not in {"swift3", "core3", "pro3"}:
        tier = "core3"
    now = now or datetime.now(timezone.utc)
    today_str = get_vn_date_str(now=now)
    identity_id = principal.get("_id") or principal.get("user_id") or principal.get("identity_id")
    email = normalize_email(principal.get("email"))
    identity_query = build_user_query(identity_id, email)
    nutrition_days = {"swift3": 1, "core3": 7, "pro3": 30}[tier]
    workout_days, workout_limit = {"swift3": (1, 2), "core3": (14, 10), "pro3": (30, 20)}[tier]
    nutrition_start, nutrition_end, _, _ = _date_bounds(now, nutrition_days)
    workout_start_str, workout_end_str, workout_start, workout_end = _date_bounds(now, workout_days)

    # Determine collection filtering based on intent_route
    allowed_cols = intent_route.collections if intent_route is not None else None

    # Nutrition is grouped by local date after a strictly identity- and date-bounded read.
    nutrition = {"status": "skipped" if allowed_cols is not None and "nutrition" not in allowed_cols else "unavailable", "coverage_truncated": False, "coverage_missing": True, "summary": []}
    if (allowed_cols is None or "nutrition" in allowed_cols) and nutrition_collection is not None and (identity_id is not None or email):
        try:
            raw_rows = list(nutrition_collection.find(
                _user_and_date_query(identity_query, {"date": {"$gte": nutrition_start, "$lte": nutrition_end}}),
                {
                    "_id": 0,
                    "date": 1,
                    "created_at": 1,
                    "meal_type": 1,
                    "foods": 1,
                    "total_calories": 1,
                    "total_protein": 1,
                    "total_carbs": 1,
                    "total_fat": 1,
                },
            ).limit(1001))
            truncated = len(raw_rows) > 1000

            reset_by_day: Dict[str, datetime] = {}
            resets_col = _resolve_day_resets_collection(nutrition_collection, day_resets_collection)
            if resets_col is not None:
                try:
                    reset_cursor = resets_col.find(
                        _user_and_date_query(identity_query, {"date": {"$gte": nutrition_start, "$lte": nutrition_end}}),
                        {"_id": 0, "date": 1, "reset_at": 1},
                    )
                    reset_rows = list(reset_cursor.limit(100)) if hasattr(reset_cursor, "limit") else list(reset_cursor)
                    for reset_doc in reset_rows:
                        if not isinstance(reset_doc, dict):
                            continue
                        reset_day = str(reset_doc.get("date") or "")[:10]
                        reset_dt = _parse_utc_naive(reset_doc.get("reset_at"))
                        if reset_day and reset_dt is not None:
                            if reset_day not in reset_by_day or reset_dt > reset_by_day[reset_day]:
                                reset_by_day[reset_day] = reset_dt
                except Exception:
                    reset_by_day = {}

            rows = []
            for row in raw_rows[:1000]:
                if not isinstance(row, dict):
                    continue
                day = str(row.get("date") or "")[:10]
                if not day:
                    continue
                reset_at = reset_by_day.get(day)
                if reset_at is not None and not _is_after_day_reset(row.get("created_at"), reset_at):
                    continue
                rows.append(row)

            daily = {}
            meals_by_day: Dict[str, List[Dict[str, Any]]] = {}
            for row in rows:
                day = str(row.get("date") or "")[:10]
                totals = daily.setdefault(day, [0.0, 0.0, 0.0, 0.0])
                for index, field in enumerate(("total_calories", "total_protein", "total_carbs", "total_fat")):
                    totals[index] += _number(row.get(field)) or 0.0

                day_meals = meals_by_day.setdefault(day, [])
                if len(day_meals) < 8:
                    raw_foods = row.get("foods")
                    food_names: List[str] = []
                    if isinstance(raw_foods, list):
                        for item in raw_foods:
                            if isinstance(item, dict):
                                name = str(item.get("name") or item.get("food_name") or item.get("title") or "").strip()
                            elif isinstance(item, str):
                                name = item.strip()
                            else:
                                name = ""
                            if name:
                                food_names.append(name[:60])
                            if len(food_names) >= 4:
                                break
                    day_meals.append({
                        "meal_type": str(row.get("meal_type") or "meal"),
                        "foods": food_names[:4],
                        "calories": round(_number(row.get("total_calories")) or 0),
                        "protein_g": round(_number(row.get("total_protein")) or 0, 1),
                    })

            summary = [
                {
                    "date": day,
                    "calories": round(values[0]),
                    "protein_g": round(values[1], 1),
                    "carbs_g": round(values[2], 1),
                    "fat_g": round(values[3], 1),
                    "meals": meals_by_day.get(day, [])[:8],
                }
                for day, values in sorted(daily.items())[-nutrition_days:]
            ]
            nutrition = {**_status(rows, truncated), "summary": summary}
        except Exception:
            pass

    # Profile lookup never projects email, name, password, or other PII.
    user_doc = None
    if (allowed_cols is None or "profile" in allowed_cols) and users_collection is not None and (identity_id is not None or email):
        try:
            clauses = []
            if identity_id is not None:
                clauses.append({"_id": identity_id})
                uid_str = str(identity_id).strip()
                if ObjectId.is_valid(uid_str):
                    oid = ObjectId(uid_str)
                    if {"_id": oid} not in clauses:
                        clauses.append({"_id": oid})
                    if {"_id": uid_str} not in clauses:
                        clauses.append({"_id": uid_str})
            if email:
                clauses.append({"email": email})
            user_query = clauses[0] if len(clauses) == 1 else {"$or": clauses}
            user_doc = users_collection.find_one(user_query, _USER_PROJECTION)
        except Exception:
            user_doc = None
    profile_data = {key: user_doc[key] for key in _PROFILE_FIELDS if user_doc and key in user_doc}
    health_stats = profile_data.get("health_stats")
    if isinstance(health_stats, dict):
        safe_health_fields = (
            "water_target_ml", "daily_calories", "daily_calorie_needs", "target_protein",
            "target_carbs", "target_fat", "bmi", "bmr", "tdee",
        )
        profile_data["health_stats"] = {key: health_stats[key] for key in safe_health_fields if key in health_stats}
    if isinstance(profile_data.get("profile"), dict):
        profile_data["profile"] = {
            key: profile_data["profile"][key]
            for key in _SAFE_PROFILE_FIELDS
            if key in profile_data["profile"]
        }
    profile = {
        "status": "available" if profile_data else ("unavailable" if users_collection is None else "empty"),
        "coverage_missing": not bool(profile_data),
        "data": profile_data,
    }
    preferences = _normalized_preferences(user_doc or {})

    # Water records are daily totals keyed by VN date.
    target_ml = _number(((user_doc or {}).get("health_stats") or {}).get("water_target_ml")) or 2000
    water = {"status": "skipped" if allowed_cols is not None and "water" not in allowed_cols else "unavailable", "coverage_missing": True, "today_ml": 0, "target_ml": target_ml, "daily": []}
    water_days = {"swift3": 1, "core3": 7, "pro3": 30}[tier]
    if (allowed_cols is None or "water" in allowed_cols) and water_collection is not None and (identity_id is not None or email):
        try:
            water_start, _, _, _ = _date_bounds(now, water_days)
            water_rows = list(water_collection.find(
                _user_and_date_query(identity_query, {"date": {"$gte": water_start, "$lte": today_str}}),
                {"_id": 0, "date": 1, "amount_ml": 1, "current_amount_ml": 1},
            ).limit(water_days + 1))
            amounts = {}
            for row in water_rows:
                day = str(row.get("date") or "")[:10]
                amount = _number(row.get("amount_ml", row.get("current_amount_ml"))) or 0
                if day:
                    amounts[day] = max(amounts.get(day, 0), amount)
            daily = [{"date": day, "amount_ml": amount} for day, amount in sorted(amounts.items())]
            available = bool(water_rows)
            water = {
                "status": "available" if available else "empty", "coverage_missing": not available,
                "today_ml": amounts.get(today_str, 0), "target_ml": target_ml, "daily": daily,
            }
            if tier != "swift3" and daily:
                water["average_ml"] = round(sum(item["amount_ml"] for item in daily) / len(daily))
        except Exception:
            pass

    # Workout reads match either UTC timestamps or the persisted VN date string.
    raw_workout_sessions = []
    workout = {"status": "skipped" if allowed_cols is not None and "workout" not in allowed_cols else "unavailable", "coverage_truncated": False, "coverage_missing": True, "sessions": []}
    if (allowed_cols is None or "workout" in allowed_cols) and workout_collection is not None and (identity_id is not None or email):
        try:
            sessions = list(workout_collection.find(
                {"$and": [identity_query, {"$or": [
                    {"started_at": {"$gte": workout_start, "$lt": workout_end}},
                    {"date": {"$gte": workout_start_str, "$lte": workout_end_str}},
                ]}]},
                {"_id": 1, "started_at": 1, "date": 1, "plan_name": 1, "total_volume_kg": 1,
                 "duration_minutes": 1, "total_duration_minutes": 1, "exercise_logs": {"$slice": 200}},
            ).sort([("started_at", -1), ("date", -1), ("_id", -1)]).limit(workout_limit + 1))
            raw_workout_sessions = sessions[:workout_limit]
            result_truncated = len(sessions) > workout_limit
            summary = []
            for session in sessions[:workout_limit]:
                logs = session.get("exercise_logs") or []
                exercises, exercise_truncated = _compact_exercises(logs)
                started = session.get("started_at")
                day = session.get("date") or (utc_to_vn_date_str(started) if isinstance(started, datetime) else str(started or "")[:10])
                summary.append({
                    "date": day,
                    "session": str(session.get("plan_name") or "Workout")[:100],
                    "total_volume_kg": session.get("total_volume_kg"),
                    "duration_minutes": session.get("total_duration_minutes", session.get("duration_minutes")),
                    "exercises": exercises,
                    "coverage_truncated": exercise_truncated,
                })
                result_truncated = result_truncated or exercise_truncated
            workout = {**_status(sessions, result_truncated), "sessions": summary}
        except Exception:
            pass

    # Muscle recovery calculation (72h) from workout_sessions
    muscle_recovery = None
    if allowed_cols is None or "recovery" in allowed_cols:
        try:
            # If workout was queried, use raw_workout_sessions, otherwise query if needed
            rec_sessions = raw_workout_sessions
            if not rec_sessions and workout_collection is not None and (identity_id is not None or email):
                rec_sessions = list(workout_collection.find(
                    identity_query,
                    {"_id": 1, "started_at": 1, "date": 1, "finished_at": 1, "exercise_logs": {"$slice": 100}},
                ).sort([("started_at", -1)]).limit(20))
            if rec_sessions:
                full_rec = calculate_muscle_recovery_load(rec_sessions, now)
                muscle_recovery = compact_muscle_recovery_for_ai(full_rec)
        except Exception:
            muscle_recovery = None

    # Rolling anomaly tags computation
    anomaly_tags = []
    try:
        if raw_workout_sessions:
            anomaly_tags = compute_rolling_anomaly_tags(
                raw_workout_sessions,
                recovery_compact=muscle_recovery,
                min_visibility=0.6,
            )
    except Exception:
        anomaly_tags = []

    # Video story evidence query
    video_story_evidence = []
    citation_days = get_video_citation_days(membership_tier)
    should_query_video_stories = (
        citation_days > 0
        and (allowed_cols is None or "video_stories" in allowed_cols)
        and video_stories_collection is not None
        and bool(account_id or identity_id or email)
    )
    if should_query_video_stories:
        try:
            # Query video stories bounded by citation_days
            story_owner_clauses = []
            if account_id:
                story_owner_clauses.append({"account_id": str(account_id).strip()})
            if identity_id:
                story_owner_clauses.append({"user_id": str(identity_id).strip()})
                if ObjectId.is_valid(str(identity_id)):
                    story_owner_clauses.append({"user_id": ObjectId(str(identity_id))})
            if email:
                story_owner_clauses.append({"email": email})
            story_owner_query = story_owner_clauses[0] if len(story_owner_clauses) == 1 else {"$or": story_owner_clauses}

            v_start_str, v_end_str, v_start_dt, v_end_dt = _date_bounds(now, citation_days)
            story_query = {
                "$and": [
                    story_owner_query,
                    {"$or": [
                        {"created_at": {"$gte": v_start_dt, "$lte": v_end_dt}},
                        {"date": {"$gte": v_start_str, "$lte": v_end_str}},
                    ]},
                ]
            }
            v_stories = list(video_stories_collection.find(
                story_query,
                {
                    "_id": 1, "video_story_id": 1, "exercise_slug": 1, "date": 1, "created_at": 1,
                    "rep_timeline": 1,
                }
            ).sort([("created_at", -1), ("_id", -1)]).limit(5))

            for st in v_stories:
                vs_id = str(st.get("video_story_id") or st.get("_id") or "")
                slug = str(st.get("exercise_slug") or "")
                dt_str = str(st.get("date") or "")
                if not dt_str and st.get("created_at"):
                    dt_str = str(st.get("created_at"))[:10]
                rep_tl = st.get("rep_timeline") or []
                if isinstance(rep_tl, list):
                    for r in rep_tl:
                        if not isinstance(r, dict):
                            continue
                        vis = float(r.get("visibility_confidence") if r.get("visibility_confidence") is not None else r.get("visibilityConfidence", 1.0))
                        if vis < 0.6:
                            continue
                        issue = r.get("issue_type") or r.get("issueType")
                        if issue and issue != "none":
                            video_story_evidence.append({
                                "video_story_id": vs_id,
                                "exercise_slug": slug,
                                "date": dt_str,
                                "rep_index": int(r.get("rep_index", r.get("repIndex", 0)) or 0),
                                "start_sec": _number(r.get("start_sec", r.get("startSec"))),
                                "end_sec": _number(r.get("end_sec", r.get("endSec"))),
                                "issue_type": str(issue),
                                "metric_angle_deg": _number(r.get("metric_angle_deg", r.get("metricAngleDeg"))),
                                "visibility_confidence": round(vis, 3),
                            })
            # Bound evidence count to at most 10 items
            video_story_evidence = video_story_evidence[:10]
        except Exception:
            video_story_evidence = []

    # Swift omits historical weight reads entirely; other tiers use bounded date queries.
    weight_history = {"status": "skipped" if (tier == "swift3" or (allowed_cols is not None and "weight" not in allowed_cols)) else "unavailable", "entries": []}
    if tier != "swift3" and (allowed_cols is None or "weight" in allowed_cols) and weight_history_collection is not None and (identity_id is not None or email):
        try:
            weight_days = 14 if tier == "core3" else 30
            weight_start, _, _, _ = _date_bounds(now, weight_days)
            entries = list(weight_history_collection.find(
                _user_and_date_query(identity_query, {"date": {"$gte": weight_start, "$lte": today_str}}),
                {"_id": 0, "date": 1, "weight_kg": 1},
            ).sort([("date", -1)]).limit(501))
            entries.sort(key=lambda row: str(row.get("date") or ""), reverse=True)
            compact = [{"date": row.get("date"), "weight_kg": _number(row.get("weight_kg"))} for row in entries[:10]]
            weights = [item["weight_kg"] for item in compact if item["weight_kg"] is not None]
            latest = weights[0] if weights else None
            delta = round(latest - weights[-1], 2) if len(weights) > 1 else None
            weight_history = {
                "status": "available" if entries else "empty", "entries_count": len(entries),
                "latest_weight_kg": latest, "delta_kg": delta, "entries": compact,
            }
            if tier == "pro3":
                goal = (user_doc or {}).get("goal")
                if goal is not None:
                    weight_history["goal"] = goal
                    if latest is not None and isinstance(goal, dict):
                        goal_weight = _number(goal.get("target_weight_kg", goal.get("weight_kg")))
                        if goal_weight is not None:
                            weight_history["goal_progress_kg"] = round(latest - goal_weight, 2)
        except Exception:
            pass

    journey = {"status": "skipped"} if (allowed_cols is not None and "journey" not in allowed_cols) else build_journey_context(
        principal=principal,
        journeys_collection=journeys_collection,
        tier=tier,
        now=now,
    )
    if (
        allowed_cols is None or "journey" in allowed_cols
    ) and (
        isinstance(journey, dict)
        and journey.get("status") == "unavailable"
        and journeys_collection is not None
        and isinstance(principal, dict)
        and "identity_id" not in principal
        and identity_id is not None
    ):
        journey = build_journey_context(
            principal={**principal, "identity_id": identity_id},
            journeys_collection=journeys_collection,
            tier=tier,
            now=now,
        )

    story_logs = {"status": "skipped"} if (allowed_cols is not None and "story_logs" not in allowed_cols) else build_story_logs_context(
        principal=principal,
        story_logs_collection=story_logs_collection,
        tier=tier,
        now=now,
    )
    if (
        allowed_cols is None or "story_logs" in allowed_cols
    ) and (
        isinstance(story_logs, dict)
        and story_logs.get("status") == "unavailable"
        and story_logs_collection is not None
        and isinstance(principal, dict)
        and "identity_id" not in principal
        and identity_id is not None
    ):
        story_logs = build_story_logs_context(
            principal={**principal, "identity_id": identity_id},
            story_logs_collection=story_logs_collection,
            tier=tier,
            now=now,
        )

    community = {"status": "skipped"} if (allowed_cols is not None and "community" not in allowed_cols) else build_community_context(
        principal=principal,
        community_posts_collection=community_posts_collection,
        community_interactions_collection=community_interactions_collection,
        community_follows_collection=community_follows_collection,
        tier=tier,
    )
    if (
        allowed_cols is None or "community" in allowed_cols
    ) and (
        isinstance(community, dict)
        and community.get("status") == "unavailable"
        and any(
            col is not None
            for col in (
                community_posts_collection,
                community_interactions_collection,
                community_follows_collection,
            )
        )
        and isinstance(principal, dict)
        and "identity_id" not in principal
        and identity_id is not None
    ):
        community = build_community_context(
            principal={**principal, "identity_id": identity_id},
            community_posts_collection=community_posts_collection,
            community_interactions_collection=community_interactions_collection,
            community_follows_collection=community_follows_collection,
            tier=tier,
        )

    # Supplements reading by tier: swift3 = 1 day, core3 = 7 days, pro3 = 30 days
    supplements = {"status": "skipped" if (allowed_cols is not None and "supplements" not in allowed_cols) else "unavailable", "coverage_missing": True, "coverage_truncated": False, "entries": []}
    if (allowed_cols is None or "supplements" in allowed_cols) and supplements_collection is not None and (identity_id is not None or email):
        try:
            sup_days = {"swift3": 1, "core3": 7, "pro3": 30}[tier]
            sup_limit = 5 if tier == "swift3" else 20
            sup_start_str, sup_end_str, _, _ = _date_bounds(now, sup_days)
            sup_rows = list(supplements_collection.find(
                _user_and_date_query(identity_query, {"date": {"$gte": sup_start_str, "$lte": sup_end_str}}),
                {"_id": 0, "date": 1, "name": 1, "supplement_name": 1, "dosage": 1, "amount": 1, "unit": 1, "time": 1, "timing": 1},
            ).limit(51))
            is_truncated = len(sup_rows) > sup_limit
            status_info = _status(sup_rows, is_truncated)
            sup_entries = []
            for row in sup_rows[:sup_limit]:
                if not isinstance(row, dict):
                    continue
                name = str(row.get("name") or row.get("supplement_name") or "").strip()[:80]
                amount = _number(row.get("amount"))
                unit = str(row.get("unit") or "").strip()[:30]
                dosage = str(row.get("dosage") or "").strip()[:60]
                if not dosage and amount is not None:
                    dosage = f"{amount:g} {unit}".strip() if unit else f"{amount:g}"
                time_val = str(row.get("time") or row.get("timing") or "").strip()[:20]
                entry = {
                    "date": str(row.get("date") or "")[:10],
                    "name": name,
                }
                if dosage:
                    entry["dosage"] = dosage
                if amount is not None:
                    entry["amount"] = int(amount) if amount.is_integer() else amount
                if unit:
                    entry["unit"] = unit
                if time_val:
                    entry["time"] = time_val
                sup_entries.append(entry)
            supplements = {
                "status": status_info["status"],
                "coverage_missing": status_info["coverage_missing"],
                "coverage_truncated": status_info["coverage_truncated"],
                "entries": sup_entries,
            }
        except Exception:
            pass

    # Recipes reading by tier: core3/pro3 only, skipped for swift3
    if tier == "swift3" or (allowed_cols is not None and "recipes" not in allowed_cols):
        recipes = {"status": "skipped", "recipes": []}
    else:
        recipes = {"status": "unavailable", "coverage_missing": True, "coverage_truncated": False, "recipes": []}
        if recipes_collection is not None and (identity_id is not None or email):
            try:
                rec_limit = 5 if tier == "core3" else 10
                rec_rows = list(recipes_collection.find(
                    identity_query,
                    {"_id": 0, "name": 1, "servings": 1, "calories_per_serving": 1, "protein_per_serving": 1, "carbs_per_serving": 1, "fat_per_serving": 1, "category": 1},
                ).limit(11))
                status_info = _status(rec_rows, len(rec_rows) > rec_limit)
                rec_items = []
                for row in rec_rows[:rec_limit]:
                    if not isinstance(row, dict):
                        continue
                    servings = _number(row.get("servings"))
                    cals = _number(row.get("calories_per_serving"))
                    pro = _number(row.get("protein_per_serving"))
                    carbs = _number(row.get("carbs_per_serving"))
                    fat = _number(row.get("fat_per_serving"))
                    item = {
                        "name": str(row.get("name") or "")[:100],
                        "servings": int(servings) if servings is not None and servings.is_integer() else servings,
                        "calories_per_serving": round(cals) if cals is not None else None,
                        "protein_per_serving": round(pro, 1) if pro is not None else None,
                        "carbs_per_serving": round(carbs, 1) if carbs is not None else None,
                        "fat_per_serving": round(fat, 1) if fat is not None else None,
                    }
                    if row.get("category") is not None:
                        item["category"] = str(row.get("category"))[:60]
                    rec_items.append(item)
                recipes = {
                    "status": status_info["status"],
                    "coverage_missing": status_info["coverage_missing"],
                    "coverage_truncated": status_info["coverage_truncated"],
                    "recipes": rec_items,
                }
            except Exception:
                pass

    context = {
        "tier": tier,
        "nutrition": nutrition,
        "water": water,
        "workout": workout,
        "weight_history": weight_history,
        "profile": profile,
        "preferences": preferences,
        "journey": journey,
        "story_logs": story_logs,
        "community": community,
        "supplements": supplements,
        "recipes": recipes,
    }
    if muscle_recovery is not None:
        context["muscle_recovery"] = muscle_recovery
    if anomaly_tags:
        context["anomaly_tags"] = anomaly_tags
    if video_story_evidence:
        context["video_story_evidence"] = video_story_evidence

    if allowed_cols is None or "recommendations" in allowed_cols:
        recommendations = build_recommendations_context(
            question=question,
            base_context=context,
            shop_products_collection=shop_products_collection,
            journal_articles_collection=journal_articles_collection,
            tier=tier,
        )
        context["recommendations"] = recommendations

    # The prompt adapter counts UTF-8 bytes as its conservative token bound.
    def context_size():
        return len(json.dumps(context, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))

    if tier == "swift3":
        while context_size() > 1500:
            for skipped_key in ("recommendations", "recipes", "community", "story_logs", "journey"):
                if skipped_key in context:
                    context.pop(skipped_key)
                    break
            else:
                if "video_story_evidence" in context:
                    context.pop("video_story_evidence")
                    continue
                if "anomaly_tags" in context:
                    context.pop("anomaly_tags")
                    continue
                if "muscle_recovery" in context:
                    context.pop("muscle_recovery")
                    continue
                if context.get("preferences", {}).get("notes"):
                    context["preferences"].pop("notes")
                    continue
                profile_data_map = context.get("profile", {}).get("data")
                if isinstance(profile_data_map, dict):
                    if "preferences" in profile_data_map:
                        profile_data_map.pop("preferences")
                        continue
                    health_stats = profile_data_map.get("health_stats")
                    if isinstance(health_stats, dict) and len(health_stats) > 1:
                        trimmed_stat = False
                        for key in list(health_stats):
                            if key != "water_target_ml":
                                health_stats.pop(key)
                                trimmed_stat = True
                                break
                        if trimmed_stat:
                            continue
                    nested_profile = profile_data_map.get("profile")
                    if isinstance(nested_profile, dict):
                        dup_key = next(
                            (k for k in list(nested_profile) if k in profile_data_map),
                            None,
                        )
                        if dup_key is not None:
                            nested_profile.pop(dup_key)
                            if not nested_profile:
                                profile_data_map.pop("profile", None)
                            continue
                sessions = context["workout"].get("sessions", [])
                if len(sessions) > 1:
                    sessions.pop()
                    context["workout"]["coverage_truncated"] = True
                    continue
                if sessions and sessions[-1].get("exercises"):
                    sessions[-1]["exercises"].pop()
                    context["workout"]["coverage_truncated"] = True
                    continue
                if sessions:
                    sessions.pop()
                    context["workout"]["coverage_truncated"] = True
                    continue
                sups = context.get("supplements", {}).get("entries")
                if isinstance(sups, list) and len(sups) > 1:
                    seen_sigs = set()
                    dup_idx = None
                    for idx, item in enumerate(sups):
                        sig = (
                            item.get("date"),
                            item.get("name"),
                            item.get("dosage"),
                            item.get("time"),
                        )
                        if sig in seen_sigs:
                            dup_idx = idx
                            break
                        seen_sigs.add(sig)
                    if dup_idx is not None:
                        sups.pop(dup_idx)
                        context["supplements"]["coverage_truncated"] = True
                        continue
                if isinstance(sups, list) and sups:
                    sups.pop()
                    context["supplements"]["coverage_truncated"] = True
                    continue
                if "supplements" in context:
                    context.pop("supplements")
                    continue
                prefs_map = context.get("preferences")
                if isinstance(prefs_map, dict):
                    trimmed_pref = False
                    for list_key in ("food_dislikes", "equipment", "target_muscles"):
                        if isinstance(prefs_map.get(list_key), list) and prefs_map[list_key]:
                            prefs_map[list_key].pop()
                            trimmed_pref = True
                            break
                    if trimmed_pref:
                        continue
                break
    elif tier == "core3":
        while context_size() > 11000:
            recs = context.get("recommendations")
            if isinstance(recs, dict):
                articles = recs.get("journal_articles")
                if isinstance(articles, list) and len(articles) > 2:
                    articles.pop()
                    continue
                products = recs.get("shop_products")
                if isinstance(products, list) and len(products) > 2:
                    products.pop()
                    continue
                if isinstance(articles, list) and len(articles) > 1:
                    articles.pop()
                    continue
                if isinstance(products, list) and len(products) > 1:
                    products.pop()
                    continue
            if "recommendations" in context:
                context.pop("recommendations")
                continue
            recs_list = context.get("recipes", {}).get("recipes")
            if isinstance(recs_list, list) and recs_list:
                recs_list.pop()
                context["recipes"]["coverage_truncated"] = True
                continue
            if "recipes" in context:
                context.pop("recipes")
                continue
            sups = context.get("supplements", {}).get("entries")
            if isinstance(sups, list) and sups:
                sups.pop()
                context["supplements"]["coverage_truncated"] = True
                continue
            if "supplements" in context:
                context.pop("supplements")
                continue
            v_ev = context.get("video_story_evidence")
            if isinstance(v_ev, list) and len(v_ev) > 2:
                v_ev.pop()
                continue
            sessions = context["workout"].get("sessions", [])
            if sessions and sessions[-1].get("exercises"):
                sessions[-1]["exercises"].pop()
                context["workout"]["coverage_truncated"] = True
                continue
            if len(sessions) > 1:
                sessions.pop()
                context["workout"]["coverage_truncated"] = True
                continue
            if isinstance(v_ev, list) and v_ev:
                v_ev.pop()
                continue
            if "video_story_evidence" in context:
                context.pop("video_story_evidence")
                continue
            if "anomaly_tags" in context:
                context.pop("anomaly_tags")
                continue
            if "muscle_recovery" in context:
                context.pop("muscle_recovery")
                continue
            break
    elif tier == "pro3":
        while context_size() > 18000:
            comm = context.get("community")
            if isinstance(comm, dict):
                saved_posts = comm.get("saved_posts")
                if isinstance(saved_posts, list) and saved_posts:
                    last_post = saved_posts[-1]
                    if isinstance(last_post, dict):
                        trimmed_text = False
                        for text_key in ("caption", "question", "note", "content"):
                            val = last_post.get(text_key)
                            if isinstance(val, str) and len(val) > 60:
                                last_post[text_key] = val[:60]
                                comm["coverage_truncated"] = True
                                trimmed_text = True
                                break
                        if trimmed_text:
                            continue
                    saved_posts.pop()
                    comm["coverage_truncated"] = True
                    continue
                questions = comm.get("questions")
                if isinstance(questions, list) and questions:
                    last_q = questions[-1]
                    if isinstance(last_q, dict):
                        trimmed_text = False
                        for text_key in ("details", "question", "caption", "note", "content"):
                            val = last_q.get(text_key)
                            if isinstance(val, str) and len(val) > 60:
                                last_q[text_key] = val[:60]
                                comm["coverage_truncated"] = True
                                trimmed_text = True
                                break
                        if trimmed_text:
                            continue
                    questions.pop()
                    comm["coverage_truncated"] = True
                    continue

            s_logs = context.get("story_logs")
            if isinstance(s_logs, dict):
                entries = s_logs.get("entries")
                if isinstance(entries, list) and entries:
                    last_entry = entries[-1]
                    if isinstance(last_entry, dict):
                        trimmed_text = False
                        for text_key in ("note", "caption", "content"):
                            val = last_entry.get(text_key)
                            if isinstance(val, str) and len(val) > 60:
                                last_entry[text_key] = val[:60]
                                s_logs["coverage_truncated"] = True
                                trimmed_text = True
                                break
                        if trimmed_text:
                            continue
                    entries.pop()
                    s_logs["coverage_truncated"] = True
                    continue

            recs = context.get("recommendations")
            if isinstance(recs, dict):
                articles = recs.get("journal_articles")
                if isinstance(articles, list) and articles:
                    articles.pop()
                    continue
                products = recs.get("shop_products")
                if isinstance(products, list) and products:
                    products.pop()
                    continue

            recs_list = context.get("recipes", {}).get("recipes")
            if isinstance(recs_list, list) and recs_list:
                recs_list.pop()
                context["recipes"]["coverage_truncated"] = True
                continue
            if "recipes" in context:
                context.pop("recipes")
                continue

            sups = context.get("supplements", {}).get("entries")
            if isinstance(sups, list) and sups:
                sups.pop()
                context["supplements"]["coverage_truncated"] = True
                continue
            if "supplements" in context:
                context.pop("supplements")
                continue

            sessions = context["workout"].get("sessions", [])
            if sessions and sessions[-1].get("exercises"):
                sessions[-1]["exercises"].pop()
                context["workout"]["coverage_truncated"] = True
                continue
            if len(sessions) > 1:
                sessions.pop()
                context["workout"]["coverage_truncated"] = True
                continue
            v_ev = context.get("video_story_evidence")
            if isinstance(v_ev, list) and v_ev:
                v_ev.pop()
                continue
            if "video_story_evidence" in context:
                context.pop("video_story_evidence")
                continue
            if "anomaly_tags" in context:
                context.pop("anomaly_tags")
                continue
            if "muscle_recovery" in context:
                context.pop("muscle_recovery")
                continue
            break
    return context
