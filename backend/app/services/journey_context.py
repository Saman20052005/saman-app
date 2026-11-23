"""Read a privacy-safe summary of the user's active journey for AI Chat."""

try:
    from backend.app.services.context_utils import (
        build_user_query,
        get_vn_date_str,
        normalize_email,
    )
except ImportError:
    from app.services.context_utils import (
        build_user_query,
        get_vn_date_str,
        normalize_email,
    )


def build_journey_context(*, principal: dict, journeys_collection, tier: str = "core3", now=None) -> dict:
    """Return a compact summary for the principal's active journey, if available."""
    if (tier or "core3").strip().lower() == "swift3":
        return {
            "status": "skipped",
            "coverage_missing": False,
            "active_journey": None,
        }

    unavailable = {
        "status": "unavailable",
        "coverage_missing": True,
        "active_journey": None,
    }

    try:
        if journeys_collection is None or not isinstance(principal, dict):
            return unavailable

        identity_id = principal.get("identity_id")
        email = normalize_email(principal.get("email"))
        if identity_id is None or not str(identity_id).strip() or not email:
            return unavailable

        query = {"$and": [build_user_query(identity_id, email), {"status": "active"}]}
        cursor = journeys_collection.find(query)
        if hasattr(cursor, "sort"):
            sorted_cursor = cursor.sort([("created_at", -1), ("_id", -1)])
            if sorted_cursor is not None:
                cursor = sorted_cursor
        if hasattr(cursor, "limit"):
            limited_cursor = cursor.limit(1)
            if limited_cursor is not None:
                cursor = limited_cursor
        if isinstance(cursor, (list, tuple)):
            doc = cursor[0] if cursor else None
        else:
            doc = next(iter(cursor), None)
        if not isinstance(doc, dict):
            return {"status": "empty", "coverage_missing": True, "active_journey": None}

        today_str = get_vn_date_str(now=now)
        days = doc.get("days", [])
        if not isinstance(days, list):
            days = []
        today_record = next(
            (day for day in days if isinstance(day, dict) and day.get("date") == today_str),
            None,
        )

        completed_tasks = []
        pending_tasks = []
        if today_record:
            tasks = today_record.get("tasks", [])
            if isinstance(tasks, list):
                for task in tasks:
                    if not isinstance(task, dict):
                        continue
                    title = str(task.get("title") or "")[:80]
                    item = {"type": task.get("type"), "title": title}
                    if task.get("is_completed"):
                        if len(completed_tasks) < 8:
                            completed_tasks.append(item)
                    elif len(pending_tasks) < 8:
                        pending_tasks.append(
                            {
                                **item,
                                "subtitle": str(task.get("subtitle") or "")[:100],
                            }
                        )

        return {
            "status": "available",
            "coverage_missing": False,
            "active_journey": {
                "focus": doc.get("focus"),
                "total_days": doc.get("total_days"),
                "day_index": today_record.get("day_index") if today_record else None,
                "completed_days_count": doc.get("completed_days_count", 0),
                "current_streak": doc.get("current_streak", 0),
                "best_streak": doc.get("best_streak", 0),
                "today_date": today_str,
                "is_rest_day": today_record.get("is_rest_day") if today_record else None,
                "today_completed": today_record.get("is_completed") if today_record else None,
                "pending_tasks": pending_tasks,
                "completed_tasks": completed_tasks,
            },
        }
    except Exception:
        return unavailable
