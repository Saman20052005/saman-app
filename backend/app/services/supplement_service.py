"""CRUD helpers for user-scoped supplement logs."""

from datetime import datetime, timezone
from typing import Any, Dict, List
from zoneinfo import ZoneInfo

from bson import ObjectId

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


VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


def _json_log(document: Dict[str, Any]) -> Dict[str, Any]:
    name = document.get("name") or document.get("supplement_name") or ""
    return {
        "id": str(document.get("_id", document.get("id", ""))),
        "name": name,
        "supplement_name": document.get("supplement_name") or name,
        "amount": document.get("amount", 1.0),
        "unit": document.get("unit", "serving"),
        "dosage": document.get("dosage", ""),
        "time": document.get("time") or document.get("timing") or "",
        "timing": document.get("timing") or document.get("time") or "",
        "date": document.get("date", ""),
        "notes": document.get("notes", ""),
    }


def create_supplement_log(
    collection, *, user_id: str, user_email: str, payload: dict
) -> dict:
    name = str(payload.get("name") or payload.get("supplement_name") or "").strip()
    if not name:
        raise ValueError("Supplement name is required")

    amount = float(payload.get("amount", 1.0))
    unit = str(payload.get("unit") or "serving")
    dosage = payload.get("dosage") or f"{amount:g} {unit}"

    date_value = payload.get("date")
    try:
        parsed_date = datetime.strptime(str(date_value), "%Y-%m-%d")
        date_str = parsed_date.strftime("%Y-%m-%d") if str(date_value) == parsed_date.strftime("%Y-%m-%d") else get_vn_date_str()
    except (TypeError, ValueError):
        date_str = get_vn_date_str()

    time_value = payload.get("timing") or payload.get("time")
    if isinstance(time_value, datetime):
        if time_value.tzinfo is None or time_value.utcoffset() is None:
            time_value = time_value.replace(tzinfo=timezone.utc)
        time_str = time_value.astimezone(VN_TZ).strftime("%H:%M")
    else:
        time_str = str(time_value).strip() if time_value else ""
    if not time_str:
        time_str = datetime.now(VN_TZ).strftime("%H:%M")

    document = {
        "user_id": str(user_id),
        "user_email": normalize_email(user_email),
        "date": date_str,
        "name": name,
        "supplement_name": name,
        "amount": amount,
        "unit": unit,
        "dosage": str(dosage),
        "time": time_str,
        "timing": time_str,
        "notes": payload.get("notes", ""),
        "created_at": datetime.utcnow(),
    }
    result = collection.insert_one(document)
    document["_id"] = result.inserted_id
    return _json_log(document)


def get_supplement_logs_by_date(
    collection, *, user_id: str, user_email: str, date_str: str
) -> List[dict]:
    query = {"$and": [build_user_query(user_id, user_email), {"date": date_str}]}
    logs = []
    for document in collection.find(query).sort("created_at", -1):
        stored_user_id = document.get("user_id")
        if user_id and stored_user_id not in (None, "") and str(stored_user_id) != str(user_id):
            continue
        logs.append(_json_log(document))
    return logs


def delete_supplement_log(
    collection, *, user_id: str, user_email: str, log_id: str
) -> bool:
    if not ObjectId.is_valid(log_id):
        raise ValueError("Invalid log_id")
    result = collection.delete_one(
        {
            "$and": [
                build_user_query(user_id, user_email),
                {"_id": ObjectId(log_id)},
            ]
        }
    )
    return result.deleted_count > 0
