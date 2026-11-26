"""
Atomic Quota Reservation and Concurrency Service for Saman Revenue.
Subsystem: Saman Revenue — Membership, Billing & Entitlements (CP-04).

Guarantees:
1. Standalone MongoDB atomicity using single-document atomic operators ($expr, $lte, $inc).
2. Race-condition-free quota capacity checking and reservation under high concurrency.
3. Tenant and operation idempotency: (user_id, benefit_id, idempotency_key).
4. Request fingerprint verification to detect payload mismatches (409 Conflict).
5. Idempotent commit and release transitions preventing double-increment or negative counters.
6. Lease token protection against stale worker finalization.
7. Window reset safety: operations finalize to their originating bucket document.
"""

from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List, Optional, Tuple
from uuid import uuid4
from zoneinfo import ZoneInfo
import logging

from backend.app.models.revenue import (
    EntitlementStatus,
    MembershipTier,
    ReservationResult,
    ReservationStatus,
    SubscriptionStatus,
    UsageOpStatus,
)
from backend.app.database_revenue import (
    COLL_ENTITLEMENT_GRANTS,
    COLL_SUBSCRIPTIONS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_FOOD_ANALYSIS_IDEMPOTENCY,
)

logger = logging.getLogger(__name__)

DEFAULT_LEASE_SECONDS = 60
DEFAULT_CACHE_TTL_HOURS = 24
VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")

TIER_QUOTA_LIMITS: Dict[str, Dict[str, Tuple[str, int]]] = {
    "free": {
        "ai.chat.swift3": ("daily", 5),
        "ai.chat.core3": ("daily", 0),
        "ai.chat.pro3": ("daily", 0),
        "ai.nutrition_gemini": ("daily", 1),
        "workout.cv.ai": ("weekly", 2),
    },
    "plus": {
        "ai.chat.swift3": ("daily", 30),
        "ai.chat.core3": ("daily", 10),
        "ai.chat.pro3": ("daily", 0),
        "ai.nutrition_gemini": ("daily", 5),
        "workout.cv.ai": ("weekly", 5),
    },
    "pro": {
        "ai.chat.swift3": ("daily", 50),
        "ai.chat.core3": ("daily", 30),
        "ai.chat.pro3": ("daily", 0),
        "ai.nutrition_gemini": ("daily", 10),
        "workout.cv.ai": ("weekly", -1),
    },
    "ultra": {
        "ai.chat.swift3": ("daily", 50),
        "ai.chat.core3": ("daily", 30),
        "ai.chat.pro3": ("daily", 15),
        "ai.nutrition_gemini": ("daily", 20),
        "workout.cv.ai": ("weekly", -1),
    },
}

TIER_STORAGE_LIMITS_MB: dict[str, int] = {
    "free": 0,
    "plus": 500,
    "pro": 5000,
    "ultra": 20000,
}

TIER_VIDEO_CITATION_DAYS: dict[str, int] = {
    "free": 0,
    "plus": 7,
    "pro": 14,
    "ultra": 30,
}


def get_video_story_storage_limit_mb(tier: str) -> int:
    """Returns cumulative video story storage quota (MB) for the given membership tier."""
    normalized = (tier or "free").strip().lower()
    return TIER_STORAGE_LIMITS_MB.get(normalized, 0)


def get_video_citation_days(tier: str) -> int:
    """Returns video citation retention window (days) for the given membership tier."""
    normalized = (tier or "free").strip().lower()
    return TIER_VIDEO_CITATION_DAYS.get(normalized, 0)

_TIER_RANK: Dict[MembershipTier, int] = {
    MembershipTier.FREE: 0,
    MembershipTier.PLUS: 1,
    MembershipTier.PRO: 2,
    MembershipTier.ULTRA: 3,
}


def _extract_matched_count(res: Any) -> int:
    if hasattr(res, "matched_count"):
        return getattr(res, "matched_count", 0)
    if isinstance(res, dict):
        return res.get("matched_count", 0)
    return 1 if res else 0


class StorageUnavailableException(Exception):
    """Raised when the revenue database is unreachable during an operation lookup."""
    pass


def _normalize_utc(dt: Optional[datetime]) -> Optional[datetime]:
    if dt is None or not isinstance(dt, datetime):
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def resolve_user_tier_and_quota(
    db: Any,
    user_id: Optional[str],
    email: Optional[str] = None,
    benefit_id: str = "ai.chat.core3",
    as_of: Optional[datetime] = None,
) -> Tuple[MembershipTier, str, int]:
    """
    Resolves effective membership tier, quota period_type, and limit_units for a user & benefit.
    Reads active subscriptions in `revenue_subscriptions` and active grants in
    `revenue_entitlement_grants` (e.g. `ai.advanced_thinking` upgrades `ai.chat.pro3` to 15/day).
    Raises StorageUnavailableException on missing/failing DB (fail-closed).
    """
    if db is None:
        raise StorageUnavailableException("Database is unavailable; cannot resolve user tier and quota.")

    eval_time = _normalize_utc(as_of) or datetime.now(timezone.utc)

    candidates: List[str] = []
    for raw_ident in (
        user_id.strip() if isinstance(user_id, str) and user_id.strip() else (str(user_id) if user_id else None),
        email.strip().lower() if isinstance(email, str) and email.strip() else None,
        email.strip() if isinstance(email, str) and email.strip() else None,
    ):
        if raw_ident and raw_ident not in candidates:
            candidates.append(raw_ident)

    try:
        # Also resolve canonical account_id from users collection if available
        try:
            users_col = db["users"]
        except KeyError:
            users_col = None

        if users_col is not None:
            for ident in list(candidates):
                user_doc = None
                if "@" in ident:
                    user_doc = users_col.find_one({"email": ident})
                else:
                    user_doc = users_col.find_one({"account_id": ident})
                if user_doc and isinstance(user_doc, dict):
                    acct_id = user_doc.get("account_id")
                    if isinstance(acct_id, str) and acct_id.strip() and acct_id.strip() not in candidates:
                        candidates.insert(0, acct_id.strip())
                    uid_val = user_doc.get("_id")
                    if uid_val is not None and str(uid_val) not in candidates:
                        candidates.append(str(uid_val))

        effective_tier = MembershipTier.FREE

        if candidates:
            subs_col = db[COLL_SUBSCRIPTIONS]
            active_statuses = [
                SubscriptionStatus.ACTIVE.value,
                SubscriptionStatus.TRIALING.value,
                SubscriptionStatus.PAST_DUE.value,
            ]
            for cand in candidates:
                raw_subs = list(subs_col.find({
                    "user_id": cand,
                    "status": {"$in": active_statuses},
                }))
                for s in raw_subs:
                    sub_st = s.get("status")
                    if sub_st == SubscriptionStatus.PAST_DUE.value:
                        in_grace = s.get("in_grace_period", False)
                        grace_end = _normalize_utc(s.get("grace_period_expires_at"))
                        if not in_grace or not grace_end or eval_time >= grace_end:
                            continue
                    else:
                        p_start = _normalize_utc(s.get("current_period_start"))
                        p_end = _normalize_utc(s.get("current_period_end"))
                        if p_start and eval_time < p_start:
                            continue
                        if p_end and eval_time >= p_end:
                            continue

                    try:
                        sub_tier = MembershipTier(s.get("tier"))
                        if _TIER_RANK.get(sub_tier, 0) > _TIER_RANK.get(effective_tier, 0):
                            effective_tier = sub_tier
                    except (ValueError, TypeError):
                        continue

        tier_limits = TIER_QUOTA_LIMITS.get(effective_tier.value, TIER_QUOTA_LIMITS["free"])
        period_type, limit_units = tier_limits.get(benefit_id, ("daily", 0))

        # Check active grants in revenue_entitlement_grants
        if candidates:
            grants_col = db[COLL_ENTITLEMENT_GRANTS]
            grant_benefit_ids = [benefit_id]
            if benefit_id == "ai.chat.pro3":
                grant_benefit_ids.append("ai.advanced_thinking")

            for cand in candidates:
                for gb_id in grant_benefit_ids:
                    raw_grants = list(grants_col.find({
                        "user_id": cand,
                        "benefit_id": gb_id,
                    }))
                    for g in raw_grants:
                        if g.get("status") != EntitlementStatus.GRANTED.value:
                            continue
                        v_from = _normalize_utc(g.get("valid_from"))
                        v_until = _normalize_utc(g.get("valid_until"))
                        if v_from and eval_time < v_from:
                            continue
                        if v_until and eval_time >= v_until:
                            continue

                        explicit_lim = g.get("limit_units")
                        if isinstance(explicit_lim, int) and not isinstance(explicit_lim, bool):
                            if explicit_lim < 0:
                                limit_units = -1
                            elif limit_units >= 0:
                                limit_units = max(limit_units, explicit_lim)
                            continue

                        grant_tier_str = g.get("tier")
                        if isinstance(grant_tier_str, str) and grant_tier_str in TIER_QUOTA_LIMITS:
                            _, grant_lim = TIER_QUOTA_LIMITS[grant_tier_str].get(benefit_id, (period_type, limit_units))
                            if grant_lim < 0:
                                limit_units = -1
                            elif limit_units >= 0:
                                limit_units = max(limit_units, grant_lim)
                            continue

                        if benefit_id == "ai.chat.pro3":
                            ultra_lim = TIER_QUOTA_LIMITS["ultra"]["ai.chat.pro3"][1]
                            if limit_units >= 0:
                                limit_units = max(limit_units, ultra_lim)
                        elif benefit_id == "ai.chat.core3":
                            plus_lim = TIER_QUOTA_LIMITS["plus"]["ai.chat.core3"][1]
                            if limit_units >= 0:
                                limit_units = max(limit_units, plus_lim)
                        elif benefit_id == "ai.nutrition_gemini" and effective_tier == MembershipTier.FREE:
                            plus_lim = TIER_QUOTA_LIMITS["plus"]["ai.nutrition_gemini"][1]
                            if limit_units >= 0:
                                limit_units = max(limit_units, plus_lim)
                        elif benefit_id == "workout.cv.ai":
                            limit_units = -1
                        elif benefit_id == "ai.chat.swift3":
                            plus_lim = TIER_QUOTA_LIMITS["plus"]["ai.chat.swift3"][1]
                            if limit_units >= 0:
                                limit_units = max(limit_units, plus_lim)

        return effective_tier, period_type, limit_units
    except StorageUnavailableException:
        raise
    except Exception as exc:
        logger.error("Storage error resolving user tier and quota: %s", exc)
        raise StorageUnavailableException(f"Storage error resolving user tier and quota: {exc}") from exc


class QuotaService:
    """
    Atomic Quota Reservation and Lifecycle Service.
    """

    def __init__(self, db: Any = None):
        self._db = db

    def _get_db(self) -> Any:
        if self._db is not None:
            return self._db
        try:
            from backend.app.database import db as active_db
            return active_db
        except ImportError:
            return None

    def _get_window_bounds(
        self,
        as_of: datetime,
        period_type: str = "monthly",
        benefit_id: Optional[str] = None,
    ) -> Tuple[datetime, datetime, str]:
        """Calculates start, end (UTC), and bucket_key for monthly, daily (VN), or weekly (VN) cycles."""
        as_of_utc = _normalize_utc(as_of) or datetime.now(timezone.utc)

        if period_type == "monthly":
            year = as_of_utc.year
            month = as_of_utc.month
            start = datetime(year, month, 1, 0, 0, 0, tzinfo=timezone.utc)
            if month == 12:
                end = datetime(year + 1, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
            else:
                end = datetime(year, month + 1, 1, 0, 0, 0, tzinfo=timezone.utc)
            period_key = f"{year:04d}{month:02d}"
            bucket_key = f"monthly:{period_key}"
            return start, end, bucket_key

        if period_type == "daily":
            local_dt = as_of_utc.astimezone(VN_TZ)
            local_start = datetime(local_dt.year, local_dt.month, local_dt.day, 0, 0, 0, tzinfo=VN_TZ)
            local_end = local_start + timedelta(days=1)
            start = local_start.astimezone(timezone.utc)
            end = local_end.astimezone(timezone.utc)
            date_vn = local_start.strftime("%Y-%m-%d")
            bucket_key = f"daily:{date_vn}:{benefit_id}"
            return start, end, bucket_key

        if period_type == "weekly":
            local_dt = as_of_utc.astimezone(VN_TZ)
            local_day_start = datetime(local_dt.year, local_dt.month, local_dt.day, 0, 0, 0, tzinfo=VN_TZ)
            local_start = local_day_start - timedelta(days=local_day_start.weekday())
            local_end = local_start + timedelta(days=7)
            start = local_start.astimezone(timezone.utc)
            end = local_end.astimezone(timezone.utc)
            iso_year, iso_week, _ = local_start.isocalendar()
            bucket_key = f"weekly:{iso_year:04d}W{iso_week:02d}:{benefit_id}"
            return start, end, bucket_key

        raise ValueError(f"Unsupported period_type: {period_type}")

    def _ensure_bucket(
        self,
        buckets_col: Any,
        user_id: str,
        benefit_id: str,
        bucket_key: str,
        window_start: datetime,
        window_end: datetime,
        limit_units: int,
        now: datetime,
        period_type: str = "monthly",
    ) -> Tuple[str, Dict[str, Any]]:
        """
        Idempotently ensures the usage bucket document exists for the window.
        Returns (bucket_id, bucket_doc).
        """
        existing = buckets_col.find_one({
            "user_id": user_id,
            "bucket_key": bucket_key,
            "window_start": window_start,
        })
        if existing:
            if period_type != "monthly" and existing.get("limit_units") != limit_units:
                buckets_col.update_one(
                    {"user_id": user_id, "bucket_key": bucket_key, "window_start": window_start},
                    {"$set": {"limit_units": limit_units, "updated_at": now}},
                )
                existing["limit_units"] = limit_units
            b_id = existing.get("bucket_id") or str(existing.get("_id"))
            return b_id, existing

        bucket_id = f"bucket_{user_id}_{benefit_id}_{bucket_key}"
        new_doc = {
            "bucket_id": bucket_id,
            "user_id": user_id,
            "benefit_id": benefit_id,
            "bucket_key": bucket_key,
            "period_type": period_type,
            "window_start": window_start,
            "window_end": window_end,
            "limit_units": limit_units,
            "bonus_units": 0,
            "consumed_units": 0,
            "reserved_units": 0,
            "reset_at": window_end,
            "schema_version": 1,
            "created_at": now,
            "updated_at": now,
        }
        try:
            buckets_col.update_one(
                {
                    "user_id": user_id,
                    "bucket_key": bucket_key,
                    "window_start": window_start,
                },
                {"$setOnInsert": new_doc},
                upsert=True,
            )
        except Exception:
            # Another concurrent thread may have inserted; query again
            pass

        bucket = buckets_col.find_one({
            "user_id": user_id,
            "bucket_key": bucket_key,
            "window_start": window_start,
        })
        if bucket:
            return (bucket.get("bucket_id") or str(bucket.get("_id"))), bucket
        return bucket_id, new_doc

    def add_bonus_quota(
        self,
        user_id: str,
        benefit_id: str,
        bonus_units: int,
        period_type: str = "daily",
        as_of: Optional[datetime] = None,
    ) -> bool:
        """
        Adds bonus quota units (e.g. from P3.1 Wallet) to the user's current period bucket.
        """
        if bonus_units < 1:
            return False

        db = self._get_db()
        if db is None:
            return False

        eval_time = _normalize_utc(as_of) or datetime.now(timezone.utc)
        buckets_col = db[COLL_USAGE_BUCKETS]
        window_start, window_end, bucket_key = self._get_window_bounds(
            eval_time,
            period_type=period_type,
            benefit_id=benefit_id,
        )
        _, _, resolved_limit = resolve_user_tier_and_quota(
            db,
            user_id=user_id,
            benefit_id=benefit_id,
            as_of=eval_time,
        )
        self._ensure_bucket(
            buckets_col=buckets_col,
            user_id=user_id,
            benefit_id=benefit_id,
            bucket_key=bucket_key,
            window_start=window_start,
            window_end=window_end,
            limit_units=resolved_limit,
            now=eval_time,
            period_type=period_type,
        )
        res = buckets_col.update_one(
            {
                "user_id": user_id,
                "bucket_key": bucket_key,
                "window_start": window_start,
            },
            {
                "$inc": {"bonus_units": bonus_units},
                "$set": {"updated_at": eval_time},
            },
        )
        return _extract_matched_count(res) > 0

    def reserve_quota(
        self,
        user_id: str,
        benefit_id: str,
        units: int = 1,
        limit_units: int = 30,
        idempotency_key: str = "",
        request_hash: Optional[str] = None,
        client_request_id: Optional[str] = None,
        lease_duration_seconds: int = DEFAULT_LEASE_SECONDS,
        as_of: Optional[datetime] = None,
        period_type: str = "monthly",
    ) -> ReservationResult:
        """
        Atomically checks remaining capacity and reserves quota units.
        
        Guarantees:
        - Standalone Mongo atomic capacity check: (consumed + reserved + units <= limit + bonus)
        - Unlimited capacity bypass when limit_units < 0
        - Idempotency check: returns existing in-progress or completed operation.
        - Payload fingerprint mismatch detection (returns OPERATION_CONFLICT).
        - Prevents negative units or zero-unit exploits.
        """
        if units < 1:
            return ReservationResult(
                status=ReservationStatus.OPERATION_CONFLICT,
                units=units,
                error_message="Reservation units must be an integer >= 1."
            )

        if not idempotency_key:
            idempotency_key = f"key_{uuid4().hex}"

        eval_time = _normalize_utc(as_of) or datetime.now(timezone.utc)
        db = self._get_db()
        if db is None:
            return ReservationResult(
                status=ReservationStatus.STORAGE_UNAVAILABLE,
                units=units,
                error_message="Database is unavailable; fail-closed on quota reservation."
            )

        ops_col = db[COLL_USAGE_OPERATIONS]
        buckets_col = db[COLL_USAGE_BUCKETS]
        cache_col = db[COLL_FOOD_ANALYSIS_IDEMPOTENCY]

        window_start, window_end, bucket_key = self._get_window_bounds(
            eval_time,
            period_type=period_type,
            benefit_id=benefit_id,
        )

        # ----------------------------------------------------------------------
        # Step 1: Idempotency & Conflict Check
        # ----------------------------------------------------------------------
        try:
            existing_op = ops_col.find_one({
                "user_id": user_id,
                "benefit_id": benefit_id,
                "idempotency_key": idempotency_key,
            })
            if existing_op:
                existing_hash = existing_op.get("request_hash")
                # Payload mismatch check
                if request_hash and existing_hash and request_hash != existing_hash:
                    return ReservationResult(
                        status=ReservationStatus.OPERATION_CONFLICT,
                        operation_id=existing_op.get("operation_id"),
                        units=units,
                        error_message="Idempotency key was previously used with a different request payload."
                    )

                op_status = existing_op.get("status")
                op_id = existing_op.get("operation_id")

                # Case A: Operation already completed successfully
                if op_status == UsageOpStatus.COMMITTED.value:
                    cached_doc = None
                    if client_request_id:
                        cached_doc = cache_col.find_one({
                            "user_id": user_id,
                            "client_request_id": client_request_id,
                        })
                    return ReservationResult(
                        status=ReservationStatus.ALREADY_COMPLETED,
                        operation_id=op_id,
                        units=existing_op.get("units", 1),
                        cached_payload=cached_doc.get("response_payload") if cached_doc else None,
                    )

                # Case B: Operation currently in flight or lease active
                if op_status in (UsageOpStatus.RESERVED.value, UsageOpStatus.EXECUTING.value):
                    exp_time = _normalize_utc(existing_op.get("expires_at"))
                    if exp_time and eval_time < exp_time:
                        return ReservationResult(
                            status=ReservationStatus.IN_PROGRESS,
                            operation_id=op_id,
                            lease_token=existing_op.get("lease_token"),
                            units=existing_op.get("units", 1),
                        )
                    # Lease expired: if dispatched, outcome is unknown
                    if existing_op.get("dispatched", False):
                        return ReservationResult(
                            status=ReservationStatus.IN_PROGRESS,
                            operation_id=op_id,
                            error_message="Operation was dispatched but outcome is pending; cannot redispatch."
                        )
                    # If not dispatched and lease expired, worker can re-acquire lease
                    new_lease = f"lease_{uuid4().hex}"
                    new_exp = eval_time + timedelta(seconds=lease_duration_seconds)
                    ops_col.update_one(
                        {"operation_id": op_id},
                        {"$set": {"lease_token": new_lease, "expires_at": new_exp, "updated_at": eval_time}}
                    )
                    return ReservationResult(
                        status=ReservationStatus.RESERVED,
                        operation_id=op_id,
                        lease_token=new_lease,
                        units=existing_op.get("units", 1),
                    )

                # Case C: Operation was released or failed unknown
                if op_status == UsageOpStatus.FAILED_UNKNOWN.value:
                    return ReservationResult(
                        status=ReservationStatus.OPERATION_CONFLICT,
                        operation_id=op_id,
                        error_message="Operation failed with unknown outcome; requires recovery resolution."
                    )
        except Exception as exc:
            logger.error("Error inspecting existing usage operation: %s", exc)
            return ReservationResult(
                status=ReservationStatus.STORAGE_UNAVAILABLE,
                units=units,
                error_message=f"Storage error reading operations: {exc}"
            )

        # ----------------------------------------------------------------------
        # Step 2: Ensure Bucket Exists
        # ----------------------------------------------------------------------
        try:
            bucket_id, bucket_doc = self._ensure_bucket(
                buckets_col=buckets_col,
                user_id=user_id,
                benefit_id=benefit_id,
                bucket_key=bucket_key,
                window_start=window_start,
                window_end=window_end,
                limit_units=limit_units,
                now=eval_time,
                period_type=period_type,
            )
        except Exception as exc:
            logger.error("Error ensuring usage bucket: %s", exc)
            return ReservationResult(
                status=ReservationStatus.STORAGE_UNAVAILABLE,
                units=units,
                error_message=f"Storage error ensuring bucket: {exc}"
            )

        # ----------------------------------------------------------------------
        # Step 3: Atomic Capacity Check & Reservation (findOneAndUpdate)
        # ----------------------------------------------------------------------
        effective_bucket_limit = bucket_doc.get("limit_units", limit_units)
        has_bonus = bool(bucket_doc and (bucket_doc.get("bonus_units") or 0) > 0)

        if effective_bucket_limit is not None and effective_bucket_limit < 0:
            atomic_query: Dict[str, Any] = {
                "user_id": user_id,
                "bucket_key": bucket_key,
                "window_start": window_start,
            }
        elif not has_bonus:
            atomic_query = {
                "user_id": user_id,
                "bucket_key": bucket_key,
                "window_start": window_start,
                "$expr": {
                    "$lte": [
                        {"$add": ["$consumed_units", "$reserved_units", units]},
                        "$limit_units",
                    ]
                },
            }
        else:
            atomic_query = {
                "user_id": user_id,
                "bucket_key": bucket_key,
                "window_start": window_start,
                "$expr": {
                    "$lte": [
                        {"$add": ["$consumed_units", "$reserved_units", units]},
                        {"$add": ["$limit_units", {"$ifNull": ["$bonus_units", 0]}]},
                    ]
                },
            }
        atomic_update = {
            "$inc": {"reserved_units": units},
            "$set": {"updated_at": eval_time},
        }

        try:
            # findOneAndUpdate performs atomic test-and-set
            updated_bucket = None
            if hasattr(buckets_col, "find_one_and_update"):
                try:
                    from pymongo import ReturnDocument
                    updated_bucket = buckets_col.find_one_and_update(
                        atomic_query,
                        atomic_update,
                        return_document=ReturnDocument.AFTER,
                    )
                except ImportError:
                    updated_bucket = buckets_col.find_one_and_update(atomic_query, atomic_update)
            else:
                # Mock DB collection fallback
                updated_bucket = buckets_col.find_one_and_update(atomic_query, atomic_update)

            if updated_bucket is None:
                # Capacity limit exceeded!
                current_b = buckets_col.find_one({
                    "user_id": user_id,
                    "bucket_key": bucket_key,
                    "window_start": window_start,
                })
                consumed = current_b.get("consumed_units", 0) if current_b else 0
                reserved = current_b.get("reserved_units", 0) if current_b else 0
                lim = current_b.get("limit_units", limit_units) if current_b else limit_units
                bonus = (current_b.get("bonus_units", 0) or 0) if current_b else 0
                effective_lim = lim + bonus if lim >= 0 else lim
                remaining = -1 if effective_lim < 0 else max(0, effective_lim - (consumed + reserved))
                return ReservationResult(
                    status=ReservationStatus.QUOTA_EXHAUSTED,
                    units=units,
                    consumed_units=consumed,
                    remaining_units=remaining,
                    limit_units=effective_lim,
                    error_message=f"Quota exhausted: {consumed + reserved}/{effective_lim} units used or reserved."
                )

            # Successfully reserved units in bucket!
            op_id = f"op_{uuid4().hex}"
            lease_token = f"lease_{uuid4().hex}"
            expires_at = eval_time + timedelta(seconds=lease_duration_seconds)

            op_doc = {
                "operation_id": op_id,
                "user_id": user_id,
                "bucket_id": bucket_id,
                "benefit_id": benefit_id,
                "idempotency_key": idempotency_key,
                "client_request_id": client_request_id,
                "request_hash": request_hash,
                "units": units,
                "status": UsageOpStatus.RESERVED.value,
                "lease_token": lease_token,
                "dispatched": False,
                "created_at": eval_time,
                "expires_at": expires_at,
                "schema_version": 1,
            }

            try:
                ops_col.insert_one(op_doc)
            except Exception as insert_exc:
                # Roll back reserved units in bucket if insert fails due to race on unique key
                buckets_col.update_one(
                    {"bucket_id": bucket_id},
                    {"$inc": {"reserved_units": -units}}
                )
                logger.warning("Duplicate key collision on operation insert: %s", insert_exc)
                return ReservationResult(
                    status=ReservationStatus.OPERATION_CONFLICT,
                    units=units,
                    error_message="Concurrent request with identical idempotency key detected."
                )

            consumed = updated_bucket.get("consumed_units", 0)
            reserved = updated_bucket.get("reserved_units", units)
            lim = updated_bucket.get("limit_units", limit_units)
            bonus = updated_bucket.get("bonus_units", 0) or 0
            effective_lim = lim + bonus if lim >= 0 else lim
            remaining = -1 if effective_lim < 0 else max(0, effective_lim - (consumed + reserved))

            return ReservationResult(
                status=ReservationStatus.RESERVED,
                operation_id=op_id,
                lease_token=lease_token,
                bucket_id=bucket_id,
                units=units,
                consumed_units=consumed,
                remaining_units=remaining,
                limit_units=effective_lim,
            )

        except Exception as exc:
            logger.error("Storage error during atomic reservation: %s", exc)
            return ReservationResult(
                status=ReservationStatus.STORAGE_UNAVAILABLE,
                units=units,
                error_message=f"Storage error reserving quota: {exc}"
            )

    def mark_dispatched(self, operation_id: str, lease_token: str) -> bool:
        """
        Records that an operation was dispatched to the provider.
        Guarantees crash recovery knows provider call was initiated.
        """
        db = self._get_db()
        if db is None:
            return False

        ops_col = db[COLL_USAGE_OPERATIONS]
        now = datetime.now(timezone.utc)
        res = ops_col.update_one(
            {
                "operation_id": operation_id,
                "lease_token": lease_token,
                "status": UsageOpStatus.RESERVED.value,
            },
            {
                "$set": {
                    "dispatched": True,
                    "dispatched_at": now,
                    "status": UsageOpStatus.EXECUTING.value,
                    "updated_at": now,
                }
            }
        )
        matched = _extract_matched_count(res)
        return matched > 0

    def commit_quota(
        self,
        operation_id: str,
        lease_token: Optional[str] = None,
        response_payload: Optional[Dict[str, Any]] = None,
        as_of: Optional[datetime] = None,
    ) -> bool:
        """
        Finalizes a successful AI operation atomically.
        Transitions bucket: reserved_units -= units, consumed_units += units.
        Transitions operation: status = 'committed'.
        Idempotent: Repeated calls do not double-increment consumed_units.
        """
        db = self._get_db()
        if db is None:
            return False

        ops_col = db[COLL_USAGE_OPERATIONS]
        buckets_col = db[COLL_USAGE_BUCKETS]
        cache_col = db[COLL_FOOD_ANALYSIS_IDEMPOTENCY]
        now = as_of or datetime.now(timezone.utc)

        op = ops_col.find_one({"operation_id": operation_id})
        if not op:
            logger.error("Cannot commit: operation '%s' not found.", operation_id)
            return False

        current_status = op.get("status")
        if current_status == UsageOpStatus.COMMITTED.value:
            # Idempotent: already committed
            return True

        allowed_commit_statuses = (
            UsageOpStatus.RESERVED.value,
            UsageOpStatus.EXECUTING.value,
            UsageOpStatus.FAILED_UNKNOWN.value,
        )
        if current_status not in allowed_commit_statuses:
            logger.warning("Refusing to commit operation '%s' in status '%s'", operation_id, current_status)
            return False

        # Verify lease token if provided
        if lease_token and op.get("lease_token") != lease_token:
            logger.error("Lease token mismatch on commit for operation '%s'", operation_id)
            return False

        units = op.get("units", 1)
        bucket_id = op.get("bucket_id")

        # Atomic transition on operation record (CAS: status must still be reserved/executing/failed_unknown)
        op_query = {
            "operation_id": operation_id,
            "status": {"$in": list(allowed_commit_statuses)},
        }
        op_update = {
            "$set": {
                "status": UsageOpStatus.COMMITTED.value,
                "updated_at": now,
            }
        }
        res = ops_col.update_one(op_query, op_update)
        matched = _extract_matched_count(res)

        if matched == 0:
            # Lost race or already committed
            return True

        # Update originating bucket: convert reserved into consumed
        buckets_col.update_one(
            {"bucket_id": bucket_id},
            {
                "$inc": {
                    "reserved_units": -units,
                    "consumed_units": units,
                },
                "$set": {"updated_at": now},
            }
        )

        # Store in result cache if client_request_id provided
        client_req_id = op.get("client_request_id")
        user_id = op.get("user_id")
        benefit_id = op.get("benefit_id")
        req_hash = op.get("request_hash", "")

        if client_req_id and response_payload and cache_col is not None:
            cache_doc = {
                "user_id": user_id,
                "client_request_id": client_req_id,
                "benefit_id": benefit_id,
                "request_hash": req_hash,
                "operation_id": operation_id,
                "status": "completed",
                "response_payload": response_payload,
                "created_at": now,
                "expires_at": now + timedelta(hours=DEFAULT_CACHE_TTL_HOURS),
            }
            try:
                cache_col.update_one(
                    {"user_id": user_id, "client_request_id": client_req_id},
                    {"$set": cache_doc},
                    upsert=True,
                )
            except Exception as cache_exc:
                logger.warning("Failed to store result cache: %s", cache_exc)

        return True

    def release_quota(
        self,
        operation_id: str,
        lease_token: Optional[str] = None,
        reason: Optional[str] = None,
        as_of: Optional[datetime] = None,
    ) -> bool:
        """
        Releases reserved units back to the bucket upon recoverable non-consumption failure.
        Transitions bucket: reserved_units -= units.
        Transitions operation: status = 'released'.
        Idempotent: Repeated calls do not double-decrement reserved_units.
        """
        db = self._get_db()
        if db is None:
            return False

        ops_col = db[COLL_USAGE_OPERATIONS]
        buckets_col = db[COLL_USAGE_BUCKETS]
        now = as_of or datetime.now(timezone.utc)

        op = ops_col.find_one({"operation_id": operation_id})
        if not op:
            return False

        current_status = op.get("status")
        if current_status == UsageOpStatus.RELEASED.value:
            # Idempotent: already released
            return True

        allowed_release_statuses = (
            UsageOpStatus.RESERVED.value,
            UsageOpStatus.EXECUTING.value,
            UsageOpStatus.FAILED_UNKNOWN.value,
        )
        if current_status not in allowed_release_statuses:
            return False

        if lease_token and op.get("lease_token") != lease_token:
            return False

        units = op.get("units", 1)
        bucket_id = op.get("bucket_id")

        # Atomic transition on operation record
        op_query = {
            "operation_id": operation_id,
            "status": {"$in": list(allowed_release_statuses)},
        }
        op_update = {
            "$set": {
                "status": UsageOpStatus.RELEASED.value,
                "error_reason": reason,
                "updated_at": now,
            }
        }
        res = ops_col.update_one(op_query, op_update)
        matched = _extract_matched_count(res)

        if matched == 0:
            return True

        # Decrement reserved units back to bucket
        buckets_col.update_one(
            {"bucket_id": bucket_id},
            {
                "$inc": {"reserved_units": -units},
                "$set": {"updated_at": now},
            }
        )
        return True

    def mark_unknown(self, operation_id: str, reason: str = "Timeout awaiting provider response") -> bool:
        """
        Marks an operation as FAILED_UNKNOWN after an unresolved provider timeout.
        Crucial Invariant: Does NOT release units back to bucket blindly.
        """
        db = self._get_db()
        if db is None:
            return False

        ops_col = db[COLL_USAGE_OPERATIONS]
        now = datetime.now(timezone.utc)
        res = ops_col.update_one(
            {
                "operation_id": operation_id,
                "status": {"$in": [UsageOpStatus.RESERVED.value, UsageOpStatus.EXECUTING.value]},
            },
            {
                "$set": {
                    "status": UsageOpStatus.FAILED_UNKNOWN.value,
                    "error_reason": reason,
                    "updated_at": now,
                }
            }
        )
        matched = _extract_matched_count(res)
        return matched > 0

    def query_operation(self, user_id: str, operation_id: str) -> Optional[Dict[str, Any]]:
        """
        Queries an operation strictly by operation_id and user_id (tenant-isolated).
        Returns sanitized operation details and cached payload (if committed).
        Does NOT expose internal lease tokens or other users' operations.
        Raises StorageUnavailableException if database is unreachable.
        """
        db = self._get_db()
        if db is None:
            raise StorageUnavailableException("Database connection is unavailable for operation lookup.")

        try:
            ops_col = db[COLL_USAGE_OPERATIONS]
            op = ops_col.find_one({"operation_id": operation_id, "user_id": user_id})
            if not op:
                return None

            cached_payload = None
            if op.get("status") == UsageOpStatus.COMMITTED.value and op.get("client_request_id"):
                cache_col = db[COLL_FOOD_ANALYSIS_IDEMPOTENCY]
                cached = cache_col.find_one({
                    "user_id": user_id,
                    "client_request_id": op.get("client_request_id"),
                })
                if cached:
                    cached_payload = cached.get("response_payload")
        except Exception as exc:
            raise StorageUnavailableException(f"Database error querying operation: {exc}") from exc

        return {
            "operation_id": op.get("operation_id"),
            "benefit_id": op.get("benefit_id"),
            "user_id": op.get("user_id"),
            "units": op.get("units", 1),
            "status": op.get("status"),
            "dispatched": op.get("dispatched", False),
            "error_reason": op.get("error_reason"),
            "created_at": op.get("created_at"),
            "updated_at": op.get("updated_at"),
            "cached_payload": cached_payload,
            "cached_response": cached_payload,
        }

    def query_operation_by_idempotency_key(
        self, user_id: str, benefit_id: str, idempotency_key: str
    ) -> Optional[Dict[str, Any]]:
        """
        Queries an operation strictly by idempotency_key, benefit_id, and user_id (tenant-isolated).
        Enables clients to recover an in-flight or completed operation if the response was lost
        before client received the operation_id.
        Raises StorageUnavailableException if database is unreachable.
        """
        db = self._get_db()
        if db is None:
            raise StorageUnavailableException("Database connection is unavailable for operation lookup.")

        try:
            ops_col = db[COLL_USAGE_OPERATIONS]
            op = ops_col.find_one({
                "user_id": user_id,
                "benefit_id": benefit_id,
                "idempotency_key": idempotency_key,
            })
            if not op:
                return None

            cached_payload = None
            if op.get("status") == UsageOpStatus.COMMITTED.value and op.get("client_request_id"):
                cache_col = db[COLL_FOOD_ANALYSIS_IDEMPOTENCY]
                cached = cache_col.find_one({
                    "user_id": user_id,
                    "client_request_id": op.get("client_request_id"),
                })
                if cached:
                    cached_payload = cached.get("response_payload")
        except Exception as exc:
            raise StorageUnavailableException(f"Database error querying operation by idempotency key: {exc}") from exc

        return {
            "operation_id": op.get("operation_id"),
            "benefit_id": op.get("benefit_id"),
            "user_id": op.get("user_id"),
            "units": op.get("units", 1),
            "status": op.get("status"),
            "dispatched": op.get("dispatched", False),
            "error_reason": op.get("error_reason"),
            "created_at": op.get("created_at"),
            "updated_at": op.get("updated_at"),
            "cached_payload": cached_payload,
            "cached_response": cached_payload,
        }

