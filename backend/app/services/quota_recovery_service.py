"""
Quota Recovery Service for Saman Revenue.
Subsystem: Saman Revenue — Membership, Billing & Entitlements (CP-04).

Responsible for:
- Detecting crashed in-flight reservations.
- Safely reclaiming expired reservations that were NEVER dispatched to a provider.
- Holding unknown operations in FAILED_UNKNOWN rather than blindly releasing quota.
"""

from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List, Optional
import logging

from backend.app.models.revenue import UsageOpStatus
from backend.app.database_revenue import (
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_FOOD_ANALYSIS_IDEMPOTENCY,
)

logger = logging.getLogger(__name__)


def _extract_matched_count(res: Any) -> int:
    if hasattr(res, "matched_count"):
        return getattr(res, "matched_count", 0)
    if isinstance(res, dict):
        return res.get("matched_count", 0)
    return 1 if res else 0


class QuotaRecoveryService:
    """
    Recovers crashed or stalled quota reservations.
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

    def reclaim_expired_undispatched_reservations(
        self,
        as_of: Optional[datetime] = None,
    ) -> int:
        """
        Safely reclaims expired reservations where the provider was NEVER called (dispatched == False).
        Decrements reserved_units in the originating bucket and marks operation 'released'.
        
        Returns:
            Count of reclaimed operations.
        """
        db = self._get_db()
        if db is None:
            logger.warning("Database unavailable; skipping quota recovery sweep.")
            return 0

        ops_col = db[COLL_USAGE_OPERATIONS]
        buckets_col = db[COLL_USAGE_BUCKETS]
        eval_time = as_of or datetime.now(timezone.utc)

        query = {
            "status": UsageOpStatus.RESERVED.value,
            "dispatched": False,
            "expires_at": {"$lt": eval_time},
        }

        expired_ops = list(ops_col.find(query))
        reclaimed_count = 0

        for op in expired_ops:
            op_id = op.get("operation_id")
            bucket_id = op.get("bucket_id")
            units = op.get("units", 1)

            # Atomic CAS update on operation
            cas_query = {
                "operation_id": op_id,
                "status": UsageOpStatus.RESERVED.value,
                "dispatched": False,
            }
            cas_update = {
                "$set": {
                    "status": UsageOpStatus.RELEASED.value,
                    "error_reason": "Automated recovery: lease expired before provider dispatch.",
                    "updated_at": eval_time,
                }
            }
            res = ops_col.update_one(cas_query, cas_update)
            matched = _extract_matched_count(res)

            if matched > 0:
                # Decrement reserved units back to bucket
                buckets_col.update_one(
                    {"bucket_id": bucket_id},
                    {
                        "$inc": {"reserved_units": -units},
                        "$set": {"updated_at": eval_time},
                    }
                )
                reclaimed_count += 1
                logger.info("Reclaimed undispatched expired reservation '%s' (%d units)", op_id, units)

        return reclaimed_count

    def transition_stalled_dispatched_to_unknown(
        self,
        as_of: Optional[datetime] = None,
    ) -> int:
        """
        Transitions stalled dispatched operations to FAILED_UNKNOWN.
        Crucial Invariant: Does NOT release units back to the bucket blindly.
        """
        db = self._get_db()
        if db is None:
            return 0

        ops_col = db[COLL_USAGE_OPERATIONS]
        eval_time = as_of or datetime.now(timezone.utc)

        query = {
            "status": {"$in": [UsageOpStatus.RESERVED.value, UsageOpStatus.EXECUTING.value]},
            "dispatched": True,
            "expires_at": {"$lt": eval_time},
        }

        stalled_ops = list(ops_col.find(query))
        flagged_count = 0

        for op in stalled_ops:
            op_id = op.get("operation_id")
            res = ops_col.update_one(
                {
                    "operation_id": op_id,
                    "status": {"$in": [UsageOpStatus.RESERVED.value, UsageOpStatus.EXECUTING.value]},
                },
                {
                    "$set": {
                        "status": UsageOpStatus.FAILED_UNKNOWN.value,
                        "error_reason": "Automated recovery: worker timed out after dispatch; outcome pending reconciliation.",
                        "updated_at": eval_time,
                    }
                }
            )
            matched = _extract_matched_count(res)
            if matched > 0:
                flagged_count += 1
                logger.warning("Flagged stalled dispatched operation '%s' as FAILED_UNKNOWN", op_id)

        return flagged_count

    def resolve_failed_unknown(
        self,
        operation_id: str,
        action: str,
        reason: str = "Manual reconciliation",
        response_payload: Optional[Dict[str, Any]] = None,
        as_of: Optional[datetime] = None,
    ) -> bool:
        """
        Deterministically resolves an operation stuck in FAILED_UNKNOWN status.
        - action='COMMIT': Late valid result verified. Converts reserved units to consumed units.
        - action='RELEASE': Verified provider never executed or failed. Decrements reserved units back to bucket allowance.
        """
        db = self._get_db()
        if db is None:
            return False

        ops_col = db[COLL_USAGE_OPERATIONS]
        buckets_col = db[COLL_USAGE_BUCKETS]
        cache_col = db[COLL_FOOD_ANALYSIS_IDEMPOTENCY]
        now = as_of or datetime.now(timezone.utc)

        op = ops_col.find_one({"operation_id": operation_id, "status": UsageOpStatus.FAILED_UNKNOWN.value})
        if not op:
            return False

        units = op.get("units", 1)
        bucket_id = op.get("bucket_id")
        normalized_action = action.strip().upper()

        if normalized_action == "COMMIT":
            res = ops_col.update_one(
                {"operation_id": operation_id, "status": UsageOpStatus.FAILED_UNKNOWN.value},
                {"$set": {"status": UsageOpStatus.COMMITTED.value, "error_reason": reason, "updated_at": now}}
            )
            if _extract_matched_count(res) > 0:
                buckets_col.update_one(
                    {"bucket_id": bucket_id},
                    {"$inc": {"reserved_units": -units, "consumed_units": units}, "$set": {"updated_at": now}}
                )
                if response_payload and op.get("client_request_id") and cache_col is not None:
                    cache_col.update_one(
                        {"user_id": op.get("user_id"), "client_request_id": op.get("client_request_id")},
                        {"$set": {
                            "user_id": op.get("user_id"),
                            "client_request_id": op.get("client_request_id"),
                            "benefit_id": op.get("benefit_id"),
                            "operation_id": operation_id,
                            "response_payload": response_payload,
                            "created_at": now,
                            "expires_at": now + timedelta(hours=24),
                        }},
                        upsert=True
                    )
                return True
            return False

        elif normalized_action == "RELEASE":
            res = ops_col.update_one(
                {"operation_id": operation_id, "status": UsageOpStatus.FAILED_UNKNOWN.value},
                {"$set": {"status": UsageOpStatus.RELEASED.value, "error_reason": reason, "updated_at": now}}
            )
            if _extract_matched_count(res) > 0:
                buckets_col.update_one(
                    {"bucket_id": bucket_id},
                    {"$inc": {"reserved_units": -units}, "$set": {"updated_at": now}}
                )
                return True
            return False

        return False
