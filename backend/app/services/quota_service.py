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
import logging

from backend.app.models.revenue import (
    ReservationResult,
    ReservationStatus,
    UsageOpStatus,
)
from backend.app.database_revenue import (
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_FOOD_ANALYSIS_IDEMPOTENCY,
)

logger = logging.getLogger(__name__)

DEFAULT_LEASE_SECONDS = 60
DEFAULT_CACHE_TTL_HOURS = 24


def _extract_matched_count(res: Any) -> int:
    if hasattr(res, "matched_count"):
        return getattr(res, "matched_count", 0)
    if isinstance(res, dict):
        return res.get("matched_count", 0)
    return 1 if res else 0


class StorageUnavailableException(Exception):
    """Raised when the revenue database is unreachable during an operation lookup."""
    pass


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

    def _get_window_bounds(self, as_of: datetime) -> Tuple[datetime, datetime, str]:
        """Calculates start, end, and bucket_key for the monthly quota cycle."""
        year = as_of.year
        month = as_of.month
        start = datetime(year, month, 1, 0, 0, 0, tzinfo=timezone.utc)
        if month == 12:
            end = datetime(year + 1, 1, 1, 0, 0, 0, tzinfo=timezone.utc)
        else:
            end = datetime(year, month + 1, 1, 0, 0, 0, tzinfo=timezone.utc)
        period_key = f"{year:04d}{month:02d}"
        bucket_key = f"monthly:{period_key}"
        return start, end, bucket_key

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
    ) -> str:
        """
        Idempotently ensures the usage bucket document exists for the window.
        Returns the bucket_id.
        """
        existing = buckets_col.find_one({
            "user_id": user_id,
            "bucket_key": bucket_key,
            "window_start": window_start,
        })
        if existing:
            return existing.get("bucket_id") or str(existing.get("_id"))

        bucket_id = f"bucket_{user_id}_{benefit_id}_{bucket_key}"
        new_doc = {
            "bucket_id": bucket_id,
            "user_id": user_id,
            "benefit_id": benefit_id,
            "bucket_key": bucket_key,
            "period_type": "monthly",
            "window_start": window_start,
            "window_end": window_end,
            "limit_units": limit_units,
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
        return (bucket.get("bucket_id") or str(bucket.get("_id"))) if bucket else bucket_id

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
    ) -> ReservationResult:
        """
        Atomically checks remaining capacity and reserves quota units.
        
        Guarantees:
        - Standalone Mongo atomic capacity check: (consumed + reserved + units <= limit)
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

        eval_time = as_of or datetime.now(timezone.utc)
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

        window_start, window_end, bucket_key = self._get_window_bounds(eval_time)

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
                    exp_time = existing_op.get("expires_at")
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
            bucket_id = self._ensure_bucket(
                buckets_col=buckets_col,
                user_id=user_id,
                benefit_id=benefit_id,
                bucket_key=bucket_key,
                window_start=window_start,
                window_end=window_end,
                limit_units=limit_units,
                now=eval_time,
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
        atomic_update = {
            "$inc": {"reserved_units": units},
            "$set": {"updated_at": eval_time},
        }

        try:
            # findOneAndUpdate performs atomic test-and-set
            updated_bucket = None
            if hasattr(buckets_col, "find_one_and_update"):
                from pymongo import ReturnDocument
                updated_bucket = buckets_col.find_one_and_update(
                    atomic_query,
                    atomic_update,
                    return_document=ReturnDocument.AFTER,
                )
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
                remaining = max(0, lim - (consumed + reserved))
                return ReservationResult(
                    status=ReservationStatus.QUOTA_EXHAUSTED,
                    units=units,
                    consumed_units=consumed,
                    remaining_units=remaining,
                    limit_units=lim,
                    error_message=f"Quota exhausted: {consumed + reserved}/{lim} units used or reserved."
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
            remaining = max(0, lim - (consumed + reserved))

            return ReservationResult(
                status=ReservationStatus.RESERVED,
                operation_id=op_id,
                lease_token=lease_token,
                bucket_id=bucket_id,
                units=units,
                consumed_units=consumed,
                remaining_units=remaining,
                limit_units=lim,
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

