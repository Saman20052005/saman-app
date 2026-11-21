"""Zero-Error Retrieval utilities for user scoping and Vietnam timezone date handling."""

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple
from zoneinfo import ZoneInfo

from bson import ObjectId

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


def normalize_email(email: Optional[str]) -> str:
    """Normalize an email address by stripping whitespace and lowercasing."""
    return (email or "").strip().lower()


def build_user_query(
    user_id: Optional[Any] = None,
    email: Optional[str] = None,
) -> Dict[str, Any]:
    """Build a fail-closed MongoDB $or query matching user_id and/or email variants."""
    clauses: List[Dict[str, Any]] = []

    def _add_clause(clause: Dict[str, Any]) -> None:
        if clause not in clauses:
            clauses.append(clause)

    if user_id is not None:
        uid_str = str(user_id).strip()
        if uid_str:
            _add_clause({"user_id": uid_str})
            if ObjectId.is_valid(uid_str):
                _add_clause({"user_id": ObjectId(uid_str)})

    clean_email = normalize_email(email)
    if clean_email:
        _add_clause({"user_email": clean_email})
        _add_clause({"email": clean_email})

    if not clauses:
        return {"_id": None}

    return {"$or": clauses}


def get_vn_date_str(offset_days: int = 0, now: Optional[datetime] = None) -> str:
    """Return the YYYY-MM-DD date string in Asia/Ho_Chi_Minh timezone."""
    if now is None:
        local_now = datetime.now(VN_TZ)
    else:
        aware_now = (
            now.replace(tzinfo=timezone.utc)
            if now.tzinfo is None or now.tzinfo.utcoffset(now) is None
            else now
        )
        local_now = aware_now.astimezone(VN_TZ)

    target = local_now + timedelta(days=offset_days)
    return target.strftime("%Y-%m-%d")


def get_vn_day_range_utc(date_str: str) -> Tuple[datetime, datetime]:
    """Convert a YYYY-MM-DD Vietnam date string into (start_utc, end_utc) datetimes."""
    parsed = datetime.strptime(date_str, "%Y-%m-%d")
    start_local = datetime(parsed.year, parsed.month, parsed.day, 0, 0, 0, tzinfo=VN_TZ)
    end_local = datetime(
        parsed.year, parsed.month, parsed.day, 23, 59, 59, 999999, tzinfo=VN_TZ
    )
    return (start_local.astimezone(timezone.utc), end_local.astimezone(timezone.utc))


def utc_to_vn_date_str(dt: Optional[datetime]) -> Optional[str]:
    """Convert a datetime (naive treated as UTC) to a YYYY-MM-DD string in VN_TZ."""
    if dt is None:
        return None
    aware_dt = (
        dt.replace(tzinfo=timezone.utc)
        if dt.tzinfo is None or dt.tzinfo.utcoffset(dt) is None
        else dt
    )
    return aware_dt.astimezone(VN_TZ).strftime("%Y-%m-%d")
