"""Bounded, principal-scoped read context for Core 3 chat requests."""

from datetime import datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


def _status(rows, truncated=False):
    if rows is None:
        return {"status": "unavailable", "coverage_truncated": False, "coverage_missing": True}
    if not rows:
        return {"status": "empty", "coverage_truncated": bool(truncated), "coverage_missing": True}
    return {"status": "available", "coverage_truncated": bool(truncated), "coverage_missing": bool(truncated)}


def build_core3_context(*, principal, nutrition_collection, workout_collection, users_collection, now=None):
    """Read only allowlisted fields with explicit DB-side bounds."""
    now = now or datetime.now(timezone.utc)
    local_today = now.astimezone(VN_TZ).date()
    first_day = local_today - timedelta(days=6)
    nutrition = None
    workout = None
    profile = None

    email = str(principal.get("email") or "")
    if nutrition_collection is None:
        nutrition = {"status": "unavailable", "coverage_truncated": False, "coverage_missing": True, "summary": []}
    elif not email:
        nutrition = {"status": "forbidden", "coverage_truncated": False, "coverage_missing": True, "summary": []}
    else:
        try:
            rows = list(nutrition_collection.find(
                {"user_email": email, "date": {"$gte": first_day.isoformat(), "$lte": local_today.isoformat()}},
                {"_id": 0, "date": 1, "total_calories": 1, "total_protein": 1, "total_carbs": 1, "total_fat": 1},
            ).limit(501))
            truncated = len(rows) > 500
            daily = {}
            for row in rows[:500]:
                key = str(row.get("date", ""))
                if key:
                    totals = daily.setdefault(key, [0.0, 0.0, 0.0, 0.0])
                    for i, field in enumerate(("total_calories", "total_protein", "total_carbs", "total_fat")):
                        try:
                            totals[i] += float(row.get(field) or 0)
                        except (TypeError, ValueError):
                            pass
            lines = [f"{day}: {vals[0]:.0f} kcal, P {vals[1]:.1f}g, C {vals[2]:.1f}g, F {vals[3]:.1f}g" for day, vals in sorted(daily.items())[-7:]]
            nutrition = {**_status(rows, truncated), "summary": lines}
        except Exception:
            nutrition = {"status": "unavailable", "coverage_truncated": False, "coverage_missing": True, "summary": []}

    user_id = str(principal.get("_id") or principal.get("user_id") or "")
    if workout_collection is None:
        workout = {"status": "unavailable", "coverage_truncated": False, "coverage_missing": True, "sessions": []}
    elif not user_id:
        workout = {"status": "forbidden", "coverage_truncated": False, "coverage_missing": True, "sessions": []}
    else:
        start = datetime.combine(local_today - timedelta(days=13), time.min, VN_TZ).astimezone(timezone.utc)
        end = datetime.combine(local_today + timedelta(days=1), time.min, VN_TZ).astimezone(timezone.utc)
        try:
            sessions = list(workout_collection.find(
                {"user_id": user_id, "started_at": {"$gte": start, "$lt": end}},
                {"_id": 1, "started_at": 1, "date": 1, "plan_name": 1, "exercise_logs": {"$slice": 400}},
            ).sort([("started_at", -1), ("_id", -1)]).limit(10))
            summary = []
            truncated = len(sessions) >= 10
            for session in sessions:
                logs = session.get("exercise_logs") or []
                set_cap = len(logs) >= 400
                grouped = {}
                for item in logs[:400]:
                    name = str(item.get("exercise_slug") or item.get("exercise_id") or "Exercise")
                    grouped[name] = grouped.get(name, 0) + 1
                summary.append({"date": str(session.get("date") or session.get("started_at") or ""),
                                "session": str(session.get("plan_name") or "Workout"),
                                "exercises": [{"name": name, "sets": count} for name, count in list(grouped.items())[:8]],
                                "coverage_truncated": set_cap})
                truncated = truncated or set_cap or len(grouped) > 8
            workout = {**_status(sessions, truncated), "sessions": summary}
        except Exception:
            workout = {"status": "unavailable", "coverage_truncated": False, "coverage_missing": True, "sessions": []}

    if users_collection is None:
        profile = {"status": "unavailable", "coverage_missing": True, "data": {}}
    elif not user_id:
        profile = {"status": "forbidden", "coverage_missing": True, "data": {}}
    else:
        try:
            # Match canonical principal id; never project PII/free text.
            profile_doc = users_collection.find_one(
                {"_id": principal.get("_id") if principal.get("_id") is not None else principal.get("user_id")},
                {"_id": 0, "goal": 1, "weight": 1, "height": 1, "tdee_value": 1, "tdee_source": 1},
            )
            profile = {key: profile_doc[key] for key in ("goal", "weight", "height", "tdee_value", "tdee_source") if profile_doc and key in profile_doc}
            profile_status = "available" if profile else "empty"
            profile = {"status": profile_status, "coverage_missing": profile_status != "available", "data": profile}
        except Exception:
            profile = {"status": "unavailable", "coverage_missing": True, "data": {}}

    return {"nutrition": nutrition, "workout": workout, "profile": profile}
