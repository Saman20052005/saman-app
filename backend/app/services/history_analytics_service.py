"""Bounded, owner-scoped history analytics reads and preflight quotes."""

from copy import deepcopy
from datetime import date, datetime, time, timedelta, timezone
import json
import secrets
from threading import RLock
import time as monotonic_time
from zoneinfo import ZoneInfo

from pymongo import ASCENDING, DESCENDING

try:
    from backend.app.services.core3_provider import Core3PromptTooLarge, _estimate_tokens, render_prompt
except ImportError:
    from app.services.core3_provider import Core3PromptTooLarge, _estimate_tokens, render_prompt


VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")
ALLOWED_RANGES = (7, 14, 30)
MAX_NUTRITION_RECORDS = {7: 350, 14: 700, 30: 1500}
MAX_WORKOUTS = {7: 18, 14: 36, 30: 72}
MAX_ESTIMATED_TOKENS = 3800
QUOTE_TTL_SECONDS = 15 * 60
MAX_CACHED_QUOTES = 1000

NUTRITION_INDEX = [("user_email", ASCENDING), ("date", ASCENDING)]
WORKOUT_DATE_INDEX = [("user_id", ASCENDING), ("date", ASCENDING)]
WORKOUT_STARTED_INDEX = [("user_id", ASCENDING), ("started_at", ASCENDING)]

ANALYTICS_SYSTEM_INSTRUCTION = (
    "Bạn là Saman Coach, phân tích xu hướng dinh dưỡng và tập luyện từ dữ liệu được cung cấp. "
    "Chỉ nêu kết luận có căn cứ trong dữ liệu, ghi rõ khoảng thời gian và dữ liệu bị cắt nếu có. "
    "Không bịa số liệu; trả lời ngắn gọn bằng tiếng Việt và đưa ra gợi ý an toàn."
)

_quote_lock = RLock()
_quotes = {}


class HistoryAnalyticsPolicyError(ValueError):
    """Raised when a requested history range is blocked by pilot policy."""


class HistoryAnalyticsQuoteError(ValueError):
    """Raised for expired, mismatched, or already claimed preflight quotes."""


def _validate_range(range_days):
    if isinstance(range_days, str):
        clean_range = range_days.strip().lower()
        if clean_range == "all_time":
            raise HistoryAnalyticsPolicyError("ALL_TIME_GATED_BY_POLICY")
        if clean_range.isdigit():
            range_days = int(clean_range)
    if isinstance(range_days, bool) or not isinstance(range_days, int):
        raise ValueError("INVALID_RANGE")
    if range_days > 30:
        raise HistoryAnalyticsPolicyError("ALL_TIME_GATED_BY_POLICY")
    if range_days not in ALLOWED_RANGES:
        raise ValueError("INVALID_RANGE")
    return range_days


def _date_window(range_days, as_of_date=None):
    today = as_of_date or datetime.now(VN_TZ).date()
    if isinstance(today, str):
        today = date.fromisoformat(today)
    if isinstance(today, datetime):
        today = today.astimezone(VN_TZ).date() if today.tzinfo else today.date()
    start_day = today - timedelta(days=range_days - 1)
    start_local = datetime.combine(start_day, time.min, VN_TZ)
    end_local = datetime.combine(today + timedelta(days=1), time.min, VN_TZ)
    return {
        "start_date": start_day.isoformat(),
        "end_date": today.isoformat(),
        "start_datetime": start_local.astimezone(timezone.utc),
        "end_datetime": end_local.astimezone(timezone.utc),
    }


def _ensure_index(collection, keys, name):
    expected = list(keys)
    for existing_name, info in collection.index_information().items():
        if list(info.get("key", [])) != expected:
            continue
        if info.get("sparse") or info.get("partialFilterExpression"):
            continue
        return existing_name
    return collection.create_index(expected, name=name)


def ensure_history_analytics_indexes(db):
    """Create idempotent, non-unique indexes needed by bounded history reads."""
    if db is None:
        raise RuntimeError("Database is unavailable")
    return {
        "nutrition": _ensure_index(
            db["nutrition_plans"], NUTRITION_INDEX, "history_nutrition_user_date_idx"
        ),
        "workout_date": _ensure_index(
            db["workout_history"], WORKOUT_DATE_INDEX, "history_workout_user_date_idx"
        ),
        "workout_started_at": _ensure_index(
            db["workout_history"], WORKOUT_STARTED_INDEX, "history_workout_user_started_at_idx"
        ),
    }


def _owner_queries(user_id, user_email, window):
    if not user_email or not user_id:
        raise ValueError("Authenticated user identity is required")
    nutrition_query = {
        "user_email": user_email,
        "date": {"$gte": window["start_date"], "$lte": window["end_date"]},
    }
    date_workout_query, started_workout_query = _workout_queries(user_id, window)
    return nutrition_query, date_workout_query, started_workout_query


def _workout_queries(user_id, window):
    if not user_id:
        raise ValueError("Authenticated user identity is required")
    date_workout_query = {
        "user_id": user_id,
        "date": {"$gte": window["start_date"], "$lte": window["end_date"]},
    }
    # The second branch covers legacy rows whose local date is absent or outside
    # the requested window but whose canonical UTC start timestamp is in range.
    started_workout_query = {
        "user_id": user_id,
        "started_at": {
            "$gte": window["start_datetime"],
            "$lt": window["end_datetime"],
        },
        "$nor": [
            {"date": {"$gte": window["start_date"], "$lte": window["end_date"]}}
        ],
    }
    return date_workout_query, started_workout_query


def _count_documents(collection, query, hint):
    return int(collection.count_documents(query, hint=dict(hint)))


def _count_active_nutrition_days(collection, query, hint, range_days):
    rows = collection.aggregate(
        [
            {"$match": query},
            {"$group": {"_id": "$date"}},
            {"$limit": range_days + 1},
        ],
        hint=dict(hint),
    )
    return min(sum(1 for _ in rows), range_days)


def _count_history(db, user_id, user_email, range_days, as_of_date=None):
    window = _date_window(range_days, as_of_date)
    nutrition_query, workout_date_query, workout_started_query = _owner_queries(
        user_id, user_email, window
    )
    nutrition = db["nutrition_plans"]
    workouts = db["workout_history"]
    raw_nutrition_count = _count_documents(nutrition, nutrition_query, NUTRITION_INDEX)
    active_days = _count_active_nutrition_days(
        nutrition, nutrition_query, NUTRITION_INDEX, range_days
    )
    matched_workout_sessions = (
        _count_documents(workouts, workout_date_query, WORKOUT_DATE_INDEX)
        + _count_documents(workouts, workout_started_query, WORKOUT_STARTED_INDEX)
    )
    included_workout_sessions = min(
        matched_workout_sessions, MAX_WORKOUTS[range_days]
    )
    estimated_tokens = 500 + (active_days * 25) + (included_workout_sessions * 35)
    if estimated_tokens > MAX_ESTIMATED_TOKENS:
        raise RuntimeError("History analytics token budget invariant was exceeded")
    return {
        **window,
        "raw_nutrition_count": raw_nutrition_count,
        "active_days": active_days,
        "matched_workout_sessions": matched_workout_sessions,
        "included_workout_sessions": included_workout_sessions,
        "nutrition_truncated": raw_nutrition_count > MAX_NUTRITION_RECORDS[range_days],
        "workout_truncated": matched_workout_sessions > included_workout_sessions,
        "estimated_tokens": estimated_tokens,
    }


def _cache_quote(quote, user_id, user_email):
    now = monotonic_time.monotonic()
    with _quote_lock:
        expired = [key for key, value in _quotes.items() if value["expires_at"] <= now]
        for key in expired:
            _quotes.pop(key, None)
        while len(_quotes) >= MAX_CACHED_QUOTES:
            oldest = min(_quotes, key=lambda key: _quotes[key]["created_at"])
            _quotes.pop(oldest, None)
        _quotes[quote["quote_id"]] = {
            "quote": deepcopy(quote),
            "user_id": str(user_id),
            "user_email": user_email,
            "expires_at": now + QUOTE_TTL_SECONDS,
            "created_at": now,
            "state": "ready",
            "operation_id": None,
            "response": None,
        }


def claim_preflight_quote(quote_id, user_id, user_email, range_days, operation_id):
    """Bind one confirmation to its owner and prevent duplicate provider dispatch."""
    range_days = _validate_range(range_days)
    now = monotonic_time.monotonic()
    with _quote_lock:
        entry = _quotes.get(quote_id)
        if not entry or entry["expires_at"] <= now:
            _quotes.pop(quote_id, None)
            raise HistoryAnalyticsQuoteError("QUOTE_EXPIRED_OR_UNKNOWN")
        if (
            entry["user_id"] != str(user_id)
            or entry["user_email"] != user_email
            or entry["quote"].get("range_days") != range_days
        ):
            raise HistoryAnalyticsQuoteError("QUOTE_MISMATCH")
        if entry["state"] == "completed":
            if entry["operation_id"] != operation_id:
                raise HistoryAnalyticsQuoteError("QUOTE_ALREADY_USED")
            return deepcopy(entry["quote"]), deepcopy(entry["response"])
        if entry["state"] != "ready":
            raise HistoryAnalyticsQuoteError("QUOTE_ALREADY_USED")
        entry["state"] = "executing"
        entry["operation_id"] = operation_id
        return deepcopy(entry["quote"]), None


def complete_preflight_quote(quote_id, response):
    with _quote_lock:
        entry = _quotes.get(quote_id)
        if entry:
            entry["state"] = "completed"
            entry["response"] = deepcopy(response)


def fail_preflight_quote(quote_id):
    with _quote_lock:
        entry = _quotes.get(quote_id)
        if entry:
            entry["state"] = "failed"


def preflight_estimate(db, user_id, user_email, range_days):
    range_days = _validate_range(range_days)
    if db is None:
        raise RuntimeError("Database is unavailable")
    counts = _count_history(db, str(user_id), user_email, range_days)
    quote = {
        "quote_id": secrets.token_urlsafe(24),
        "range_days": range_days,
        "raw_nutrition_count": counts["raw_nutrition_count"],
        "active_days": counts["active_days"],
        "matched_workout_sessions": counts["matched_workout_sessions"],
        "included_workout_sessions": counts["included_workout_sessions"],
        "nutrition_truncated": counts["nutrition_truncated"],
        "workout_truncated": counts["workout_truncated"],
        "truncated": counts["nutrition_truncated"] or counts["workout_truncated"],
        "estimated_tokens": counts["estimated_tokens"],
        "quota_cost": 1,
        "start_date": counts["start_date"],
        "end_date": counts["end_date"],
    }
    _cache_quote(quote, str(user_id), user_email)
    return quote


def _metric_expression(primary, fallback):
    return {
        "$convert": {
            "input": {"$ifNull": [f"${primary}", f"${fallback}"]},
            "to": "double",
            "onError": 0.0,
            "onNull": 0.0,
        }
    }


def _nutrition_rollup(db, query, range_days):
    collection = db["nutrition_plans"]
    raw_count = _count_documents(collection, query, NUTRITION_INDEX)
    cap = MAX_NUTRITION_RECORDS[range_days]
    pipeline = [
        {"$match": query},
        {"$sort": {"date": DESCENDING}},
        {"$limit": cap},
        {
            "$project": {
                "date": 1,
                "calories_value": _metric_expression("total_calories", "calories"),
                "protein_value": _metric_expression("total_protein", "protein"),
                "carbs_value": _metric_expression("total_carbs", "carbs"),
                "fat_value": _metric_expression("total_fat", "fat"),
            }
        },
        {
            "$group": {
                "_id": "$date",
                "calories": {"$sum": "$calories_value"},
                "protein": {"$sum": "$protein_value"},
                "carbs": {"$sum": "$carbs_value"},
                "fat": {"$sum": "$fat_value"},
                "meals": {"$sum": 1},
            }
        },
        {"$sort": {"_id": ASCENDING}},
        {"$limit": range_days},
        {
            "$project": {
                "_id": 0,
                "date": "$_id",
                "calories": {"$round": ["$calories", 1]},
                "protein": {"$round": ["$protein", 1]},
                "carbs": {"$round": ["$carbs", 1]},
                "fat": {"$round": ["$fat", 1]},
                "meals": 1,
            }
        },
    ]
    daily = list(collection.aggregate(pipeline, hint=dict(NUTRITION_INDEX)))
    return daily, raw_count > cap


def _workout_sort_value(document):
    value = document.get("started_at") or document.get("date")
    if isinstance(value, datetime):
        dt = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value
        return dt.astimezone(VN_TZ).isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return str(value or "")[:32]


def _workout_date(document):
    value = document.get("date")
    if isinstance(value, datetime):
        dt = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value
        return dt.astimezone(VN_TZ).date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, str) and len(value) >= 10:
        return value[:10]
    started_at = document.get("started_at")
    if isinstance(started_at, datetime):
        dt = started_at.replace(tzinfo=timezone.utc) if started_at.tzinfo is None else started_at
        return dt.astimezone(VN_TZ).date().isoformat()
    return str(started_at or "")[:10]


def _workout_projection(db, query, hint, sort, limit):
    return list(
        db["workout_history"].aggregate(
            [
                {"$match": query},
                {"$sort": sort},
                {"$limit": limit},
                {
                    "$project": {
                        "date": 1,
                        "started_at": 1,
                        "total_duration_minutes": 1,
                        "duration_minutes": 1,
                        "exercise_logs": 1,
                        "exercises": 1,
                    }
                },
            ],
            hint=dict(hint),
        )
    )


def _workout_summaries(db, user_id, window, range_days):
    date_query, started_query = _workout_queries(user_id, window)
    cap = MAX_WORKOUTS[range_days]
    date_rows = _workout_projection(
        db,
        date_query,
        WORKOUT_DATE_INDEX,
        {"date": DESCENDING},
        cap + 1,
    )
    started_rows = _workout_projection(
        db,
        started_query,
        WORKOUT_STARTED_INDEX,
        {"started_at": DESCENDING, "_id": DESCENDING},
        cap + 1,
    )
    unique = {}
    for document in date_rows + started_rows:
        identity = document.get("_id")
        key = str(identity) if identity is not None else f"row:{id(document)}"
        unique.setdefault(key, document)
    newest = sorted(unique.values(), key=_workout_sort_value, reverse=True)[:cap]
    summaries = []
    for document in newest:
        raw_logs = document.get("exercise_logs") or document.get("exercises") or []
        names = []
        if isinstance(raw_logs, list):
            for item in raw_logs:
                if isinstance(item, dict):
                    name = (
                        item.get("exercise_name")
                        or item.get("name")
                        or item.get("exercise_slug")
                        or item.get("exercise_id")
                    )
                else:
                    name = item
                clean_name = str(name or "").strip()
                if clean_name and clean_name not in names:
                    names.append(clean_name[:50])
                if len(names) == 5:
                    break
        duration = document.get("total_duration_minutes")
        if duration is None:
            duration = document.get("duration_minutes")
        try:
            duration = max(0, int(float(duration or 0)))
        except (TypeError, ValueError):
            duration = 0
        summaries.append(
            {
                "date": _workout_date(document),
                "duration_minutes": duration,
                "exercise_count": len(names),
                "exercises": names,
            }
        )
    return summaries


def build_bounded_history_context(db, user_id, user_email, range_days, as_of_date=None):
    range_days = _validate_range(range_days)
    if db is None:
        raise RuntimeError("Database is unavailable")
    user_id = str(user_id)
    window = _date_window(range_days, as_of_date)
    nutrition_query, _, _ = _owner_queries(user_id, user_email, window)
    daily, nutrition_truncated = _nutrition_rollup(db, nutrition_query, range_days)
    counts = _count_history(db, user_id, user_email, range_days, window["end_date"])
    workouts = _workout_summaries(db, user_id, window, range_days)
    # Count and aggregation use the same indexed date window. A short result can
    # occur only if rows changed during the read; report actual included rows.
    included_workouts = min(len(workouts), MAX_WORKOUTS[range_days])
    workout_truncated = counts["matched_workout_sessions"] > included_workouts
    return {
        "range_days": range_days,
        "start_date": window["start_date"],
        "end_date": window["end_date"],
        "nutrition": daily,
        "workouts": workouts[:included_workouts],
        "raw_nutrition_count": counts["raw_nutrition_count"],
        "active_days": counts["active_days"],
        "included_active_days": len(daily),
        "matched_workout_sessions": counts["matched_workout_sessions"],
        "included_workout_sessions": included_workouts,
        "nutrition_truncated": nutrition_truncated,
        "workout_truncated": workout_truncated,
        "truncated": nutrition_truncated or workout_truncated,
        "estimated_tokens": (
            500 + (counts["active_days"] * 25) + (included_workouts * 35)
        ),
    }


def render_history_analytics_prompt(context):
    """Fit compact, deterministic history context under the Core 3 byte guard."""
    bounded = deepcopy(context)
    while True:
        prompt = render_prompt(
            question=(
                "Phân tích xu hướng dinh dưỡng và tập luyện trong khoảng thời gian "
                f"{bounded['start_date']} đến {bounded['end_date']}. Nêu điểm nổi bật, "
                "hạn chế dữ liệu và 1-3 gợi ý an toàn."
            ),
            history=[],
            context=bounded,
            system_instruction=ANALYTICS_SYSTEM_INSTRUCTION,
        )
        serialized_context = json.dumps(
            bounded, ensure_ascii=False, separators=(",", ":")
        )
        if (
            _estimate_tokens(prompt) <= MAX_ESTIMATED_TOKENS
            and f"Context: {serialized_context}" in prompt
        ):
            bounded["included_workout_sessions"] = len(bounded["workouts"])
            bounded["included_active_days"] = len(bounded["nutrition"])
            bounded["nutrition_truncated"] = bounded["nutrition_truncated"] or (
                bounded["included_active_days"] < bounded["active_days"]
            )
            bounded["workout_truncated"] = bounded["workout_truncated"] or (
                len(bounded["workouts"]) < bounded["matched_workout_sessions"]
            )
            bounded["truncated"] = (
                bounded["nutrition_truncated"] or bounded["workout_truncated"]
            )
            bounded["estimated_tokens"] = (
                500
                + (bounded["included_active_days"] * 25)
                + (bounded["included_workout_sessions"] * 35)
            )
            return prompt, bounded
        if bounded["workouts"]:
            bounded["workouts"].pop()
            bounded["workout_truncated"] = True
            continue
        if len(bounded["nutrition"]) > 1:
            bounded["nutrition"].pop(0)
            bounded["nutrition_truncated"] = True
            continue
        raise Core3PromptTooLarge("History analytics prompt exceeds input budget")
