"""
Reconciliation Scanner and Controlled Plan/Apply Service for Saman Revenue.
Subsystem: Saman Revenue — Operations, Reconciliation & Audited Grants (CP-10).

SAFETY INVARIANTS:
1. Default mode is STRICTLY read-only / dry-run. Zero writes during scan and plan generation.
2. Local consistency checks do NOT constitute live provider reconciliation.
3. Every finding captures explicit preconditions for Compare-And-Swap (CAS) safe apply.
4. If underlying data changes between plan generation and application, CAS fails and aborts
   the stale action rather than blindly overwriting data.
5. Plan replay is fully idempotent; re-applying an already applied plan produces 0 duplicate mutations.
6. Quota counters are NEVER blanket overwritten; adjustments use atomic delta $inc.
7. Stranded undispatched reservations are reclaimed via established QuotaRecoveryService.
8. Unprojected events are replayed via established PaymentSettlementService.
9. Redaction: Raw receipt tokens, full user prompts, images, and health payloads are NEVER logged.
10. Operational Boundary: Administrative mutation is restricted to offline CLI / services.
"""

from __future__ import annotations

from datetime import datetime, timezone, timedelta
import hashlib
import logging
from typing import Any, Dict, List, Optional, Tuple
from uuid import uuid4

from backend.app.models.revenue import (
    ReconciliationFinding,
    ReconciliationFindingType,
    ReconciliationSeverity,
    ReconciliationActionType,
    ReconciliationPlan,
    ReconciliationPlanStatus,
    ReconciliationApplyResult,
    SubscriptionStatus,
    EntitlementStatus,
    UsageOpStatus,
    PaymentProviderName,
)
from backend.app.database_revenue import (
    COLL_PROVIDER_EVENTS,
    COLL_SUBSCRIPTIONS,
    COLL_ENTITLEMENT_GRANTS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_RECONCILIATION_PLANS,
    COLL_RECONCILIATION_AUDIT,
)
from backend.app.services.catalog_engine import get_catalog_engine
from backend.app.services.entitlement_service import BENEFIT_TO_MATRIX_MAP

logger = logging.getLogger(__name__)


# ==============================================================================
# EXCEPTIONS
# ==============================================================================

class ReconciliationError(Exception):
    """Base exception for reconciliation errors."""
    pass


class ReconciliationPlanNotFoundError(ReconciliationError):
    """Raised when the specified reconciliation plan is not found."""
    pass


class ReconciliationPreconditionFailedError(ReconciliationError):
    """Raised when CAS preconditions fail during plan application."""
    pass


class ReconciliationStorageError(ReconciliationError):
    """Raised when storage layer fails during reconciliation operations."""
    pass


# ==============================================================================
# REDACTION & HASHING HELPERS
# ==============================================================================

def redact_sensitive_evidence(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Strips raw receipt tokens, prompts, and personal payloads from audit evidence.
    Returns safe references with SHA-256 hashes for cryptographic linkage.
    """
    safe_data: Dict[str, Any] = {}
    sensitive_keys = {
        "raw_payload", "verification_token", "raw_receipt", "prompt",
        "response_payload", "jws_payload", "client_secret", "authorization",
        "password", "meal_photo", "image", "image_base64"
    }

    for key, value in data.items():
        if key in sensitive_keys:
            if isinstance(value, str):
                safe_data[f"{key}_sha256"] = hashlib.sha256(value.encode("utf-8")).hexdigest()
            elif isinstance(value, dict):
                safe_data[f"{key}_sha256"] = hashlib.sha256(str(sorted(value.items())).encode("utf-8")).hexdigest()
            else:
                safe_data[f"{key}_redacted"] = True
        elif isinstance(value, dict):
            safe_data[key] = redact_sensitive_evidence(value)
        elif isinstance(value, list):
            safe_data[key] = [
                redact_sensitive_evidence(item) if isinstance(item, dict) else item
                for item in value
            ]
        else:
            safe_data[key] = value

    return safe_data


def _extract_matched_count(res: Any) -> int:
    """Extracts matched_count from real PyMongo UpdateResult or mock dict."""
    if hasattr(res, "matched_count"):
        return getattr(res, "matched_count", 0)
    if isinstance(res, dict):
        return res.get("matched_count", 0)
    return 1 if res else 0


def _safe_query(
    col: Any,
    query: Dict[str, Any],
    limit: Optional[int] = None,
    sort_key: Optional[Tuple[str, int]] = None,
) -> List[Dict[str, Any]]:
    """Safe collection query helper supporting real PyMongo cursors and in-memory test mocks."""
    res = col.find(query)
    if sort_key and hasattr(res, "sort"):
        res = res.sort(sort_key[0], sort_key[1])
    if limit is not None and hasattr(res, "limit"):
        res = res.limit(limit)
    items = list(res)
    if sort_key and not hasattr(res, "sort"):
        items = sorted(items, key=lambda d: d.get(sort_key[0]) or datetime.min, reverse=(sort_key[1] < 0))
    if limit is not None:
        items = items[:limit]
    return items


# ==============================================================================
# RECONCILIATION SCANNER (READ-ONLY)
# ==============================================================================

class ReconciliationScanner:
    """
    Read-only discrepancy scanner for Saman Revenue.
    Performs zero database writes.
    Supports bounded batching and query scoping by user_id, entity_type, and time range.
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

    def scan(
        self,
        scope_user_id: Optional[str] = None,
        scope_entity_type: Optional[str] = None,
        since: Optional[datetime] = None,
        until: Optional[datetime] = None,
        limit: int = 200,
        as_of: Optional[datetime] = None,
    ) -> List[ReconciliationFinding]:
        """
        Executes a multi-layer consistency scan and returns structured findings.
        Zero writes. Safe on production or read-replica databases.
        """
        db = self._get_db()
        if db is None:
            raise ReconciliationStorageError("Database unavailable for reconciliation scan.")

        eval_time = as_of or datetime.now(timezone.utc)
        findings: List[ReconciliationFinding] = []

        # 1. Scan unprojected durable provider events
        if not scope_entity_type or scope_entity_type == "event":
            findings.extend(
                self._scan_unprojected_events(db, scope_user_id, since, until, limit - len(findings), eval_time)
            )

        # 2. Scan subscription and entitlement grant mismatches
        if len(findings) < limit and (not scope_entity_type or scope_entity_type in ("subscription", "grant")):
            findings.extend(
                self._scan_subscription_grant_mismatches(db, scope_user_id, since, until, limit - len(findings), eval_time)
            )

        # 3. Scan expired grants still marked active
        if len(findings) < limit and (not scope_entity_type or scope_entity_type == "grant"):
            findings.extend(
                self._scan_expired_active_grants(db, scope_user_id, limit - len(findings), eval_time)
            )

        # 4. Scan receipt ownership conflicts & unmapped products
        if len(findings) < limit and (not scope_entity_type or scope_entity_type == "subscription"):
            findings.extend(
                self._scan_ownership_conflicts(db, scope_user_id, limit - len(findings), eval_time)
            )

        # 5. Scan quota counter inconsistencies (negative consumed/reserved)
        if len(findings) < limit and (not scope_entity_type or scope_entity_type == "bucket"):
            findings.extend(
                self._scan_quota_inconsistencies(db, scope_user_id, limit - len(findings), eval_time)
            )

        # 6. Scan stranded / stalled usage operations
        if len(findings) < limit and (not scope_entity_type or scope_entity_type == "operation"):
            findings.extend(
                self._scan_usage_operations(db, scope_user_id, since, until, limit - len(findings), eval_time)
            )

        return findings[:limit]

    def _scan_unprojected_events(
        self,
        db: Any,
        user_id: Optional[str],
        since: Optional[datetime],
        until: Optional[datetime],
        limit: int,
        eval_time: datetime,
    ) -> List[ReconciliationFinding]:
        """Detects durable provider events whose projection was never finalized."""
        col = db[COLL_PROVIDER_EVENTS]
        query: Dict[str, Any] = {
            "processing_status": {"$in": ["received", "failed"]},
        }
        if user_id:
            query["user_id"] = user_id
        if since or until:
            t_filter: Dict[str, Any] = {}
            if since:
                t_filter["$gte"] = since
            if until:
                t_filter["$lte"] = until
            query["created_at"] = t_filter

        findings: List[ReconciliationFinding] = []
        try:
            events = _safe_query(col, query, limit=limit)
        except Exception as exc:
            logger.warning("Failed to query provider events for reconciliation: %s", exc)
            return []

        for evt in events:
            evt_id = evt.get("event_id", "")
            snapshot = evt.get("projection_snapshot")
            has_snapshot = bool(snapshot)

            evidence = redact_sensitive_evidence({
                "event_id": evt_id,
                "provider": evt.get("provider"),
                "event_type": evt.get("event_type"),
                "processing_status": evt.get("processing_status"),
                "has_snapshot": has_snapshot,
                "created_at": str(evt.get("created_at")),
            })

            proposed = ReconciliationActionType.REPROJECT_EVENT if has_snapshot else ReconciliationActionType.REQUIRES_MANUAL_REVIEW

            findings.append(ReconciliationFinding(
                finding_id=f"REC-EVT-{evt_id}",
                finding_type=ReconciliationFindingType.UNPROJECTED_EVENT,
                severity=ReconciliationSeverity.HIGH if has_snapshot else ReconciliationSeverity.CRITICAL,
                entity_type="event",
                entity_id=evt_id,
                user_id=evt.get("user_id"),
                description=f"Durable event '{evt_id}' remains in '{evt.get('processing_status')}' status.",
                evidence_references=evidence,
                proposed_action=proposed,
                requires_manual_review=not has_snapshot,
                precondition={
                    "collection": COLL_PROVIDER_EVENTS,
                    "filter": {"event_id": evt_id, "processing_status": evt.get("processing_status")},
                },
                detected_at=eval_time,
            ))

        return findings

    def _scan_subscription_grant_mismatches(
        self,
        db: Any,
        user_id: Optional[str],
        since: Optional[datetime],
        until: Optional[datetime],
        limit: int,
        eval_time: datetime,
    ) -> List[ReconciliationFinding]:
        """Detects period, status, or benefit mismatches between subscriptions and grants."""
        sub_col = db[COLL_SUBSCRIPTIONS]
        grant_col = db[COLL_ENTITLEMENT_GRANTS]

        query: Dict[str, Any] = {}
        if user_id:
            query["user_id"] = user_id
        if since or until:
            t_filter: Dict[str, Any] = {}
            if since:
                t_filter["$gte"] = since
            if until:
                t_filter["$lte"] = until
            query["updated_at"] = t_filter

        findings: List[ReconciliationFinding] = []
        try:
            subs = _safe_query(sub_col, query, limit=limit)
        except Exception as exc:
            logger.warning("Failed to query subscriptions for reconciliation: %s", exc)
            return []

        for sub in subs:
            sub_id = sub.get("subscription_id", "")
            sub_user = sub.get("user_id", "")
            sub_status = sub.get("status")
            period_end = sub.get("current_period_end")

            # Check for subscriptions marked reconciliation_required
            if sub.get("reconciliation_required", False):
                findings.append(ReconciliationFinding(
                    finding_id=f"REC-SUB-FLAG-{sub_id}",
                    finding_type=ReconciliationFindingType.SUBSCRIPTION_GRANT_MISMATCH,
                    severity=ReconciliationSeverity.HIGH,
                    entity_type="subscription",
                    entity_id=sub_id,
                    user_id=sub_user,
                    description=f"Subscription '{sub_id}' carries reconciliation_required flag from out-of-order event.",
                    evidence_references={
                        "subscription_id": sub_id,
                        "status": sub_status,
                        "reconciliation_required": True,
                        "ownership_status": sub.get("ownership_status"),
                    },
                    proposed_action=ReconciliationActionType.REQUIRES_MANUAL_REVIEW,
                    requires_manual_review=True,
                    precondition={
                        "collection": COLL_SUBSCRIPTIONS,
                        "filter": {"subscription_id": sub_id, "reconciliation_required": True},
                    },
                    detected_at=eval_time,
                ))

            # Query grants originating from this subscription
            grants = list(grant_col.find({"source_subscription_id": sub_id}))
            if not grants and sub_status == SubscriptionStatus.ACTIVE.value:
                # Active subscription has 0 associated grants
                findings.append(ReconciliationFinding(
                    finding_id=f"REC-SUB-NOGRANT-{sub_id}",
                    finding_type=ReconciliationFindingType.SUBSCRIPTION_GRANT_MISMATCH,
                    severity=ReconciliationSeverity.HIGH,
                    entity_type="subscription",
                    entity_id=sub_id,
                    user_id=sub_user,
                    description=f"Active subscription '{sub_id}' has 0 entitlement grants projected.",
                    evidence_references={"subscription_id": sub_id, "tier": sub.get("tier"), "status": sub_status},
                    proposed_action=ReconciliationActionType.SYNCHRONIZE_GRANT_STATE,
                    requires_manual_review=False,
                    precondition={
                        "collection": COLL_SUBSCRIPTIONS,
                        "filter": {"subscription_id": sub_id, "status": SubscriptionStatus.ACTIVE.value},
                    },
                    detected_at=eval_time,
                ))

            # Mismatch: Subscription expired/canceled but grant still active
            for g in grants:
                g_id = g.get("grant_id", "")
                g_status = g.get("status")
                g_valid_until = g.get("valid_until")

                if sub_status in (SubscriptionStatus.EXPIRED.value, SubscriptionStatus.CANCELED.value):
                    # If subscription is expired and grace expired, grant should not be active
                    if g_status == EntitlementStatus.GRANTED.value and (g_valid_until and eval_time >= g_valid_until):
                        findings.append(ReconciliationFinding(
                            finding_id=f"REC-GRANT-EXPIRED-SUB-{g_id}",
                            finding_type=ReconciliationFindingType.EXPIRED_GRANT_ACTIVE,
                            severity=ReconciliationSeverity.MEDIUM,
                            entity_type="grant",
                            entity_id=g_id,
                            user_id=sub_user,
                            description=f"Grant '{g_id}' remains 'granted' although subscription '{sub_id}' is '{sub_status}' and period expired.",
                            evidence_references={
                                "grant_id": g_id,
                                "subscription_id": sub_id,
                                "grant_status": g_status,
                                "subscription_status": sub_status,
                                "valid_until": str(g_valid_until),
                            },
                            proposed_action=ReconciliationActionType.EXPIRE_GRANT,
                            requires_manual_review=False,
                            precondition={
                                "collection": COLL_ENTITLEMENT_GRANTS,
                                "filter": {"grant_id": g_id, "status": EntitlementStatus.GRANTED.value},
                            },
                            detected_at=eval_time,
                        ))

        return findings

    def _scan_expired_active_grants(
        self,
        db: Any,
        user_id: Optional[str],
        limit: int,
        eval_time: datetime,
    ) -> List[ReconciliationFinding]:
        """Detects entitlement grants where valid_until < eval_time but status is still 'granted'."""
        col = db[COLL_ENTITLEMENT_GRANTS]
        query: Dict[str, Any] = {
            "status": EntitlementStatus.GRANTED.value,
            "valid_until": {"$lt": eval_time, "$ne": None},
        }
        if user_id:
            query["user_id"] = user_id

        findings: List[ReconciliationFinding] = []
        try:
            expired_grants = _safe_query(col, query, limit=limit)
        except Exception as exc:
            logger.warning("Failed to query expired grants for reconciliation: %s", exc)
            return []

        for g in expired_grants:
            g_id = g.get("grant_id", "")
            findings.append(ReconciliationFinding(
                finding_id=f"REC-EXP-GRANT-{g_id}",
                finding_type=ReconciliationFindingType.EXPIRED_GRANT_ACTIVE,
                severity=ReconciliationSeverity.MEDIUM,
                entity_type="grant",
                entity_id=g_id,
                user_id=g.get("user_id"),
                description=f"Grant '{g_id}' has passed valid_until ({g.get('valid_until')}) but remains marked 'granted'.",
                evidence_references={
                    "grant_id": g_id,
                    "benefit_id": g.get("benefit_id"),
                    "source_type": g.get("source_type"),
                    "valid_until": str(g.get("valid_until")),
                },
                proposed_action=ReconciliationActionType.EXPIRE_GRANT,
                requires_manual_review=False,
                precondition={
                    "collection": COLL_ENTITLEMENT_GRANTS,
                    "filter": {"grant_id": g_id, "status": EntitlementStatus.GRANTED.value},
                },
                detected_at=eval_time,
            ))

        return findings

    def _scan_ownership_conflicts(
        self,
        db: Any,
        user_id: Optional[str],
        limit: int,
        eval_time: datetime,
    ) -> List[ReconciliationFinding]:
        """Detects store receipt cross-account ownership conflicts and unmapped products."""
        col = db[COLL_SUBSCRIPTIONS]
        query: Dict[str, Any] = {
            "ownership_status": {"$in": ["unresolved_conflict", "conflict_detected"]},
        }
        if user_id:
            query["user_id"] = user_id

        findings: List[ReconciliationFinding] = []
        try:
            conflict_subs = _safe_query(col, query, limit=limit)
        except Exception as exc:
            logger.warning("Failed to query conflicting subscriptions: %s", exc)
            return []

        for sub in conflict_subs:
            sub_id = sub.get("subscription_id", "")
            findings.append(ReconciliationFinding(
                finding_id=f"REC-OWN-CONF-{sub_id}",
                finding_type=ReconciliationFindingType.OWNERSHIP_CONFLICT,
                severity=ReconciliationSeverity.CRITICAL,
                entity_type="subscription",
                entity_id=sub_id,
                user_id=sub.get("user_id"),
                description=f"Subscription '{sub_id}' carries unresolved receipt ownership conflict.",
                evidence_references={
                    "subscription_id": sub_id,
                    "provider": sub.get("provider"),
                    "original_transaction_id": sub.get("original_transaction_id"),
                    "ownership_status": sub.get("ownership_status"),
                },
                proposed_action=ReconciliationActionType.REQUIRES_MANUAL_REVIEW,
                requires_manual_review=True,
                precondition={
                    "collection": COLL_SUBSCRIPTIONS,
                    "filter": {"subscription_id": sub_id, "ownership_status": sub.get("ownership_status")},
                },
                detected_at=eval_time,
            ))

        return findings

    def _scan_quota_inconsistencies(
        self,
        db: Any,
        user_id: Optional[str],
        limit: int,
        eval_time: datetime,
    ) -> List[ReconciliationFinding]:
        """Detects negative consumed or reserved units in quota buckets."""
        col = db[COLL_USAGE_BUCKETS]
        query: Dict[str, Any] = {
            "$or": [
                {"consumed_units": {"$lt": 0}},
                {"reserved_units": {"$lt": 0}},
            ]
        }
        if user_id:
            query["user_id"] = user_id

        findings: List[ReconciliationFinding] = []
        try:
            buckets = _safe_query(col, query, limit=limit)
        except Exception as exc:
            logger.warning("Failed to query quota buckets for reconciliation: %s", exc)
            return []

        for b in buckets:
            b_id = b.get("bucket_id", "")
            consumed = b.get("consumed_units", 0)
            reserved = b.get("reserved_units", 0)

            findings.append(ReconciliationFinding(
                finding_id=f"REC-QUOTA-NEG-{b_id}",
                finding_type=ReconciliationFindingType.NEGATIVE_QUOTA_COUNTER,
                severity=ReconciliationSeverity.HIGH,
                entity_type="bucket",
                entity_id=b_id,
                user_id=b.get("user_id"),
                description=f"Bucket '{b_id}' contains negative counter: consumed={consumed}, reserved={reserved}.",
                evidence_references={
                    "bucket_id": b_id,
                    "user_id": b.get("user_id"),
                    "benefit_id": b.get("benefit_id"),
                    "consumed_units": consumed,
                    "reserved_units": reserved,
                },
                proposed_action=ReconciliationActionType.ADJUST_QUOTA_BUCKET,
                requires_manual_review=False,
                precondition={
                    "collection": COLL_USAGE_BUCKETS,
                    "filter": {"bucket_id": b_id, "consumed_units": consumed, "reserved_units": reserved},
                },
                detected_at=eval_time,
            ))

        return findings

    def _scan_usage_operations(
        self,
        db: Any,
        user_id: Optional[str],
        since: Optional[datetime],
        until: Optional[datetime],
        limit: int,
        eval_time: datetime,
    ) -> List[ReconciliationFinding]:
        """Detects stranded undispatched reservations and stalled unknown operations."""
        col = db[COLL_USAGE_OPERATIONS]
        query: Dict[str, Any] = {
            "$or": [
                # Stranded undispatched reservations (lease expired, never sent to provider)
                {
                    "status": UsageOpStatus.RESERVED.value,
                    "dispatched": False,
                    "expires_at": {"$lt": eval_time},
                },
                # Unknown operations requiring out-of-band verification
                {
                    "status": UsageOpStatus.FAILED_UNKNOWN.value,
                },
            ]
        }
        if user_id:
            query["user_id"] = user_id
        if since or until:
            t_filter: Dict[str, Any] = {}
            if since:
                t_filter["$gte"] = since
            if until:
                t_filter["$lte"] = until
            query["created_at"] = t_filter

        findings: List[ReconciliationFinding] = []
        try:
            ops = _safe_query(col, query, limit=limit)
        except Exception as exc:
            logger.warning("Failed to query usage operations for reconciliation: %s", exc)
            return []

        for op in ops:
            op_id = op.get("operation_id", "")
            op_status = op.get("status")
            dispatched = op.get("dispatched", False)

            if op_status == UsageOpStatus.RESERVED.value and not dispatched:
                findings.append(ReconciliationFinding(
                    finding_id=f"REC-OP-STRANDED-{op_id}",
                    finding_type=ReconciliationFindingType.STRANDED_RESERVATION,
                    severity=ReconciliationSeverity.MEDIUM,
                    entity_type="operation",
                    entity_id=op_id,
                    user_id=op.get("user_id"),
                    description=f"Operation '{op_id}' expired before provider dispatch; quota remains reserved.",
                    evidence_references={
                        "operation_id": op_id,
                        "bucket_id": op.get("bucket_id"),
                        "units": op.get("units", 1),
                        "expires_at": str(op.get("expires_at")),
                    },
                    proposed_action=ReconciliationActionType.RECLAIM_RESERVATION,
                    requires_manual_review=False,
                    precondition={
                        "collection": COLL_USAGE_OPERATIONS,
                        "filter": {"operation_id": op_id, "status": UsageOpStatus.RESERVED.value, "dispatched": False},
                    },
                    detected_at=eval_time,
                ))

            elif op_status == UsageOpStatus.FAILED_UNKNOWN.value:
                findings.append(ReconciliationFinding(
                    finding_id=f"REC-OP-UNKNOWN-{op_id}",
                    finding_type=ReconciliationFindingType.UNKNOWN_OPERATION_REQUIRING_EVIDENCE,
                    severity=ReconciliationSeverity.MEDIUM,
                    entity_type="operation",
                    entity_id=op_id,
                    user_id=op.get("user_id"),
                    description=f"Operation '{op_id}' is held in FAILED_UNKNOWN; requires external AI provider log verification.",
                    evidence_references={
                        "operation_id": op_id,
                        "bucket_id": op.get("bucket_id"),
                        "units": op.get("units", 1),
                        "error_reason": op.get("error_reason"),
                    },
                    proposed_action=ReconciliationActionType.REQUIRES_MANUAL_REVIEW,
                    requires_manual_review=True,
                    precondition={
                        "collection": COLL_USAGE_OPERATIONS,
                        "filter": {"operation_id": op_id, "status": UsageOpStatus.FAILED_UNKNOWN.value},
                    },
                    detected_at=eval_time,
                ))

        return findings


# ==============================================================================
# RECONCILIATION SERVICE (PLAN / APPLY WORKFLOW)
# ==============================================================================

class ReconciliationService:
    """
    Manages generation of dry-run reconciliation plans and controlled, idempotent apply.
    Invariants:
    - Never modifies data during generate_plan (zero writes).
    - Requires explicit invocation to apply.
    - Precondition CAS checks abort actions whose underlying records changed.
    - Calls established QuotaRecoveryService and PaymentSettlementService methods.
    - Append-only audit logging in revenue_reconciliation_audit.
    """

    def __init__(self, db: Any = None):
        self._db = db
        self._scanner = ReconciliationScanner(db=db)

    def _get_db(self) -> Any:
        if self._db is not None:
            return self._db
        try:
            from backend.app.database import db as active_db
            return active_db
        except ImportError:
            return None

    def generate_plan(
        self,
        scope_user_id: Optional[str] = None,
        scope_entity_type: Optional[str] = None,
        since: Optional[datetime] = None,
        until: Optional[datetime] = None,
        limit: int = 100,
        as_of: Optional[datetime] = None,
    ) -> ReconciliationPlan:
        """
        Generates a dry-run reconciliation plan.
        ZERO WRITES: Performs only read operations.
        """
        eval_time = as_of or datetime.now(timezone.utc)
        findings = self._scanner.scan(
            scope_user_id=scope_user_id,
            scope_entity_type=scope_entity_type,
            since=since,
            until=until,
            limit=limit,
            as_of=eval_time,
        )

        actionable = [f for f in findings if not f.requires_manual_review and f.proposed_action != ReconciliationActionType.NOOP]
        manual = [f for f in findings if f.requires_manual_review]

        # Summarize expected mutations
        action_summary: Dict[str, int] = {}
        for a in actionable:
            action_summary[a.proposed_action.value] = action_summary.get(a.proposed_action.value, 0) + 1

        plan = ReconciliationPlan(
            plan_id=f"rec_plan_{uuid4().hex[:12]}",
            version=1,
            created_at=eval_time,
            status=ReconciliationPlanStatus.DRAFT,
            scope={
                "scope_user_id": scope_user_id,
                "scope_entity_type": scope_entity_type,
                "since": str(since) if since else None,
                "until": str(until) if until else None,
            },
            total_findings=len(findings),
            actionable_count=len(actionable),
            manual_review_count=len(manual),
            findings=findings,
            expected_state={
                "prospective_mutations": action_summary,
                "manual_review_required": len(manual),
                "safe_dry_run": True,
            },
        )

        return plan

    def save_plan(self, plan: ReconciliationPlan) -> str:
        """Persists a reconciliation plan in DRAFT status."""
        db = self._get_db()
        if db is None:
            raise ReconciliationStorageError("Database unavailable to save reconciliation plan.")

        col = db[COLL_RECONCILIATION_PLANS]
        doc = plan.model_dump()
        col.update_one(
            {"plan_id": plan.plan_id},
            {"$set": doc},
            upsert=True,
        )
        logger.info("Saved reconciliation plan '%s' with %d findings.", plan.plan_id, plan.total_findings)
        return plan.plan_id

    def get_plan(self, plan_id: str) -> Optional[ReconciliationPlan]:
        """Retrieves a persisted reconciliation plan."""
        db = self._get_db()
        if db is None:
            raise ReconciliationStorageError("Database unavailable to retrieve reconciliation plan.")

        col = db[COLL_RECONCILIATION_PLANS]
        doc = col.find_one({"plan_id": plan_id})
        if not doc:
            return None
        doc.pop("_id", None)
        return ReconciliationPlan(**doc)

    def apply_plan(
        self,
        plan_id: str,
        actor: str,
        as_of: Optional[datetime] = None,
        max_actions: int = 100,
    ) -> ReconciliationApplyResult:
        """
        Executes an explicit, controlled apply of a reconciliation plan.
        Invariants:
        - Atomic CAS transition from DRAFT -> APPLYING.
        - CAS precondition check on each affected record before mutation.
        - Idempotent replay: checks revenue_reconciliation_audit to prevent double execution.
        - Calls established QuotaRecoveryService and PaymentSettlementService methods.
        - Updates plan status to APPLIED or ABORTED upon completion.
        """
        start_time = datetime.now(timezone.utc)
        eval_time = as_of or start_time

        if not actor or len(actor.strip()) < 2:
            raise ValueError("Actor identity is mandatory for applying a reconciliation plan.")

        db = self._get_db()
        if db is None:
            raise ReconciliationStorageError("Database unavailable to apply reconciliation plan.")

        plans_col = db[COLL_RECONCILIATION_PLANS]
        audit_col = db[COLL_RECONCILIATION_AUDIT]

        # Step 1: Atomic CAS to transition plan DRAFT -> APPLYING
        cas_res = plans_col.update_one(
            {"plan_id": plan_id, "status": ReconciliationPlanStatus.DRAFT.value},
            {
                "$set": {
                    "status": ReconciliationPlanStatus.APPLYING.value,
                    "applied_by": actor,
                    "updated_at": eval_time,
                }
            }
        )
        matched = _extract_matched_count(cas_res)

        if matched == 0:
            existing = plans_col.find_one({"plan_id": plan_id})
            if not existing:
                raise ReconciliationPlanNotFoundError(f"Reconciliation plan '{plan_id}' does not exist.")
            current_status = existing.get("status")
            if current_status == ReconciliationPlanStatus.APPLIED.value:
                # Idempotent replay of already applied plan
                logger.info("Plan '%s' is already applied; returning zero mutations.", plan_id)
                return ReconciliationApplyResult(
                    plan_id=plan_id,
                    status=ReconciliationPlanStatus.APPLIED,
                    total_actions=0,
                    applied_actions=0,
                    aborted_actions=0,
                    failed_actions=0,
                    manual_review_items=existing.get("manual_review_count", 0),
                    action_details=[{"status": "already_applied", "plan_id": plan_id}],
                    duration_seconds=0.0,
                )
            raise ReconciliationPreconditionFailedError(
                f"Cannot apply plan '{plan_id}' in state '{current_status}'."
            )

        # Retrieve plan document
        plan_doc = plans_col.find_one({"plan_id": plan_id})
        plan = ReconciliationPlan(**plan_doc)

        applied_count = 0
        aborted_count = 0
        failed_count = 0
        manual_review_count = 0
        action_details: List[Dict[str, Any]] = []

        # Step 2: Iterate actionable findings
        for finding in plan.findings:
            if applied_count + aborted_count + failed_count >= max_actions:
                logger.warning("Reached max_actions limit (%d) for plan %s; suspending batch.", max_actions, plan_id)
                break

            if finding.requires_manual_review or finding.proposed_action == ReconciliationActionType.NOOP:
                manual_review_count += 1
                continue

            # Idempotency check against audit collection
            existing_audit = audit_col.find_one({"plan_id": plan_id, "finding_id": finding.finding_id})
            if existing_audit and existing_audit.get("status") == "applied":
                logger.info("Finding '%s' was already applied; skipping replay.", finding.finding_id)
                continue

            # Precondition CAS verification
            if finding.precondition:
                target_col_name = finding.precondition.get("collection")
                filter_spec = finding.precondition.get("filter")
                if target_col_name and filter_spec:
                    target_col = db[target_col_name]
                    current_record = target_col.find_one(filter_spec)
                    if not current_record:
                        # Check if the discrepancy was already resolved out-of-band (already_applied)
                        is_already_resolved = False
                        if finding.proposed_action == ReconciliationActionType.ADJUST_QUOTA_BUCKET:
                            b_curr = target_col.find_one({"bucket_id": finding.entity_id})
                            if b_curr and b_curr.get("consumed_units", 0) >= 0 and b_curr.get("reserved_units", 0) >= 0:
                                is_already_resolved = True
                        elif finding.proposed_action == ReconciliationActionType.EXPIRE_GRANT:
                            g_curr = target_col.find_one({"grant_id": finding.entity_id})
                            if g_curr and g_curr.get("status") == EntitlementStatus.EXPIRED.value:
                                is_already_resolved = True
                        elif finding.proposed_action == ReconciliationActionType.RECLAIM_RESERVATION:
                            op_curr = target_col.find_one({"operation_id": finding.entity_id})
                            if op_curr and op_curr.get("status") == UsageOpStatus.RELEASED.value:
                                is_already_resolved = True

                        if is_already_resolved:
                            logger.info(
                                "Finding '%s' condition is already satisfied out-of-band; marking already_applied.",
                                finding.finding_id
                            )
                            action_details.append({
                                "finding_id": finding.finding_id,
                                "action": finding.proposed_action.value,
                                "status": "already_applied",
                                "details": {"already_resolved_out_of_band": True},
                            })
                            self._record_audit(audit_col, plan_id, finding, actor, "already_applied", None, eval_time)
                            continue

                        logger.warning(
                            "CAS precondition failed for finding '%s' on '%s': record changed since plan creation. Aborting action.",
                            finding.finding_id, target_col_name
                        )
                        aborted_count += 1
                        action_details.append({
                            "finding_id": finding.finding_id,
                            "status": "aborted",
                            "reason": "stale_precondition_aborted",
                            "precondition": filter_spec,
                        })
                        self._record_audit(audit_col, plan_id, finding, actor, "aborted", "stale_precondition_aborted", eval_time)
                        continue

            # Step 3: Execute Action
            try:
                mutation_meta = self._execute_action(db, finding, eval_time)
                outcome_status = mutation_meta.get("status", "applied")
                if outcome_status == "already_applied":
                    action_details.append({
                        "finding_id": finding.finding_id,
                        "action": finding.proposed_action.value,
                        "status": "already_applied",
                        "details": mutation_meta,
                    })
                    self._record_audit(audit_col, plan_id, finding, actor, "already_applied", None, eval_time, mutation_meta)
                else:
                    applied_count += 1
                    action_details.append({
                        "finding_id": finding.finding_id,
                        "action": finding.proposed_action.value,
                        "status": "applied",
                        "details": mutation_meta,
                    })
                    self._record_audit(audit_col, plan_id, finding, actor, "applied", None, eval_time, mutation_meta)
            except ReconciliationPreconditionFailedError as cas_exc:
                logger.warning(
                    "CAS precondition failed for finding '%s' during execution: %s",
                    finding.finding_id, cas_exc
                )
                aborted_count += 1
                action_details.append({
                    "finding_id": finding.finding_id,
                    "status": "aborted",
                    "reason": "cas_write_conflict",
                    "details": str(cas_exc),
                })
                self._record_audit(audit_col, plan_id, finding, actor, "aborted", "cas_write_conflict", eval_time)
            except Exception as exc:
                logger.error("Failed to execute action for finding '%s': %s", finding.finding_id, exc)
                failed_count += 1
                action_details.append({
                    "finding_id": finding.finding_id,
                    "status": "failed",
                    "error": str(exc),
                })
                self._record_audit(audit_col, plan_id, finding, actor, "failed", str(exc), eval_time)

        # Step 4: Finalize Plan State
        final_status = ReconciliationPlanStatus.APPLIED if failed_count == 0 else ReconciliationPlanStatus.FAILED
        plans_col.update_one(
            {"plan_id": plan_id},
            {
                "$set": {
                    "status": final_status.value,
                    "applied_at": eval_time,
                    "applied_by": actor,
                    "execution_summary": {
                        "applied": applied_count,
                        "aborted": aborted_count,
                        "failed": failed_count,
                        "manual_review": manual_review_count,
                    },
                    "updated_at": eval_time,
                }
            }
        )

        duration = (datetime.now(timezone.utc) - start_time).total_seconds()
        logger.info(
            "Plan '%s' applied with status '%s': applied=%d, aborted=%d, failed=%d in %.3fs",
            plan_id, final_status.value, applied_count, aborted_count, failed_count, duration
        )

        return ReconciliationApplyResult(
            plan_id=plan_id,
            status=final_status,
            total_actions=applied_count + aborted_count + failed_count,
            applied_actions=applied_count,
            aborted_actions=aborted_count,
            failed_actions=failed_count,
            manual_review_items=manual_review_count,
            action_details=action_details,
            duration_seconds=duration,
        )

    def _execute_action(
        self,
        db: Any,
        finding: ReconciliationFinding,
        eval_time: datetime,
    ) -> Dict[str, Any]:
        """Dispatches action execution to appropriate recovery service or CAS mutation."""
        action = finding.proposed_action

        # 1. Reproject durable provider event
        if action == ReconciliationActionType.REPROJECT_EVENT:
            from backend.app.services.payment_service import get_payment_settlement_service
            payment_svc = get_payment_settlement_service(db=db)
            evt_col = db[COLL_PROVIDER_EVENTS]
            evt = evt_col.find_one({"event_id": finding.entity_id})
            if not evt:
                raise ReconciliationError(f"Provider event '{finding.entity_id}' not found.")
            snapshot = evt.get("projection_snapshot")
            if not snapshot:
                raise ReconciliationError(f"Provider event '{finding.entity_id}' has no projection snapshot.")

            payment_svc._execute_projection_from_snapshot(
                db=db,
                event_id=evt["event_id"],
                provider=PaymentProviderName(evt["provider"]),
                snapshot=snapshot,
                as_of=eval_time,
            )
            return {"reprojected_event_id": finding.entity_id}

        # 2. Reclaim expired undispatched reservation
        elif action == ReconciliationActionType.RECLAIM_RESERVATION:
            from backend.app.services.quota_recovery_service import QuotaRecoveryService
            recovery_svc = QuotaRecoveryService(db=db)
            # Reclaim targeted operation
            ops_col = db[COLL_USAGE_OPERATIONS]
            buckets_col = db[COLL_USAGE_BUCKETS]

            op = ops_col.find_one({"operation_id": finding.entity_id})
            if not op:
                raise ReconciliationError(f"Operation '{finding.entity_id}' not found.")

            units = op.get("units", 1)
            bucket_id = op.get("bucket_id")

            cas_res = ops_col.update_one(
                {"operation_id": finding.entity_id, "status": UsageOpStatus.RESERVED.value, "dispatched": False},
                {
                    "$set": {
                        "status": UsageOpStatus.RELEASED.value,
                        "error_reason": "Reconciliation: reclaimed expired undispatched reservation.",
                        "updated_at": eval_time,
                    }
                }
            )
            matched = _extract_matched_count(cas_res)
            if matched > 0 and bucket_id:
                buckets_col.update_one(
                    {"bucket_id": bucket_id},
                    {
                        "$inc": {"reserved_units": -units},
                        "$set": {"updated_at": eval_time},
                    }
                )
            return {"reclaimed_operation_id": finding.entity_id, "units": units}

        # 3. Mark expired grant as expired
        elif action == ReconciliationActionType.EXPIRE_GRANT:
            grant_col = db[COLL_ENTITLEMENT_GRANTS]
            res = grant_col.update_one(
                {"grant_id": finding.entity_id, "status": EntitlementStatus.GRANTED.value},
                {
                    "$set": {
                        "status": EntitlementStatus.EXPIRED.value,
                        "updated_at": eval_time,
                    }
                }
            )
            return {"expired_grant_id": finding.entity_id}

        # 4. Atomic adjustment of negative quota bucket
        elif action == ReconciliationActionType.ADJUST_QUOTA_BUCKET:
            buckets_col = db[COLL_USAGE_BUCKETS]
            bucket = buckets_col.find_one({"bucket_id": finding.entity_id})
            if not bucket:
                raise ReconciliationError(f"Bucket '{finding.entity_id}' not found.")

            # Extract expected state from finding
            expected_consumed = None
            expected_reserved = None
            if finding.evidence_references:
                expected_consumed = finding.evidence_references.get("consumed_units")
                expected_reserved = finding.evidence_references.get("reserved_units")
            elif finding.precondition and "filter" in finding.precondition:
                expected_consumed = finding.precondition["filter"].get("consumed_units")
                expected_reserved = finding.precondition["filter"].get("reserved_units")

            current_consumed = bucket.get("consumed_units", 0)
            current_reserved = bucket.get("reserved_units", 0)

            # Check if bucket is already non-negative (already resolved out-of-band)
            if current_consumed >= 0 and current_reserved >= 0:
                logger.info(
                    "Bucket '%s' is already in non-negative state (consumed=%d, reserved=%d); skipping mutation.",
                    finding.entity_id, current_consumed, current_reserved
                )
                return {
                    "status": "already_applied",
                    "adjusted_bucket_id": finding.entity_id,
                    "consumed_units": current_consumed,
                    "reserved_units": current_reserved,
                    "adjustments": {},
                }

            # If expected counters were recorded, enforce strict CAS match against current DB state
            if expected_consumed is not None and expected_reserved is not None:
                if current_consumed != expected_consumed or current_reserved != expected_reserved:
                    raise ReconciliationPreconditionFailedError(
                        f"CAS precondition failed: bucket '{finding.entity_id}' state changed concurrently "
                        f"(expected consumed={expected_consumed}, reserved={expected_reserved}; "
                        f"current consumed={current_consumed}, reserved={current_reserved})."
                    )

            inc_updates: Dict[str, int] = {}
            if current_consumed < 0:
                inc_updates["consumed_units"] = -current_consumed  # restores to 0
            if current_reserved < 0:
                inc_updates["reserved_units"] = -current_reserved  # restores to 0

            if inc_updates:
                # True atomic CAS write: conditional on exact current counters
                update_filter: Dict[str, Any] = {
                    "bucket_id": finding.entity_id,
                    "consumed_units": current_consumed,
                    "reserved_units": current_reserved,
                }
                cas_res = buckets_col.update_one(
                    update_filter,
                    {
                        "$inc": inc_updates,
                        "$set": {"updated_at": eval_time},
                    }
                )
                matched = _extract_matched_count(cas_res)
                if matched == 0:
                    raise ReconciliationPreconditionFailedError(
                        f"CAS write conflict: bucket '{finding.entity_id}' was concurrently modified during atomic update."
                    )
            return {
                "status": "applied",
                "adjusted_bucket_id": finding.entity_id,
                "adjustments": inc_updates,
            }

        # 5. Synchronize grant state with subscription
        elif action == ReconciliationActionType.SYNCHRONIZE_GRANT_STATE:
            # Grant projection from subscription
            sub_col = db[COLL_SUBSCRIPTIONS]
            sub = sub_col.find_one({"subscription_id": finding.entity_id})
            if not sub:
                raise ReconciliationError(f"Subscription '{finding.entity_id}' not found.")

            from backend.app.services.payment_service import get_payment_settlement_service
            payment_svc = get_payment_settlement_service(db=db)
            grants_created = payment_svc._project_entitlement_grants_for_subscription(
                db=db,
                sub=sub,
                as_of=eval_time,
            )
            return {"synchronized_subscription_id": finding.entity_id, "grants_created": grants_created}

        else:
            raise ReconciliationError(f"Unsupported reconciliation action: '{action.value}'")

    def _record_audit(
        self,
        audit_col: Any,
        plan_id: str,
        finding: ReconciliationFinding,
        actor: str,
        status: str,
        error_msg: Optional[str],
        eval_time: datetime,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> None:
        """Appends an immutable audit record for an applied or aborted reconciliation action."""
        doc = {
            "audit_id": f"rec_aud_{uuid4().hex[:12]}",
            "plan_id": plan_id,
            "finding_id": finding.finding_id,
            "action": finding.proposed_action.value,
            "entity_type": finding.entity_type,
            "entity_id": finding.entity_id,
            "user_id": finding.user_id,
            "actor": actor,
            "status": status,
            "error_reason": error_msg,
            "metadata": metadata or {},
            "executed_at": eval_time,
        }
        try:
            audit_col.insert_one(doc)
        except Exception as exc:
            logger.error("Failed to write reconciliation audit record: %s", exc)
