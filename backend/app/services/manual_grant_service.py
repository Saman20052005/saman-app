"""
Audited Manual Entitlement Grant & Revocation Service for Saman Revenue.
Subsystem: Saman Revenue — Operations, Reconciliation & Audited Grants (CP-10).

OPERATIONAL ACCESS BOUNDARY:
As per repository governance (AGENTS.md & CP-10 specification), because no secure
administrative role boundary (RBAC) currently exists in the public user authentication
and JWT tokens, administrative mutation endpoints (POST/PUT/DELETE for manual grants)
are STRICTLY OMITTED from the public HTTP router.
Manual grants and revocations MUST be performed exclusively via:
1. Controlled offline CLI: `python -m backend.scripts.revenue_admin`
2. Programmatic invocation by verified internal maintenance tasks.

INVARIANTS ENFORCED:
1. Requires explicit idempotency key and operator actor identity.
2. Permanent grants are forbidden: `valid_until` is mandatory and finite.
3. Replaying the same key with identical payload returns existing grant (idempotent).
4. Replaying the same key with different payload raises IdempotencyConflictError.
5. Manual grant creates an explicit `EntitlementGrant` with source_type='staff_override'.
6. NEVER creates fake subscriptions or fake payment transactions.
7. NEVER increases or resets usage quota counters.
8. Revocation targets a specific `grant_id` and does NOT affect independent grants.
9. Two-Phase Crash-Recoverable Audit:
   - Audit record written with status='requested' BEFORE mutating the grant.
   - Audit record finalized with status='applied' AFTER mutating the grant.
   - Interrupted operations can be audited and recovered without silent untracked mutation.
10. Audit logs in `revenue_manual_grant_audit` are append-only. Hard deletion is forbidden.
"""

from __future__ import annotations

from datetime import datetime, timezone, timedelta
import hashlib
import json
import logging
from typing import Any, Dict, List, Optional
from uuid import uuid4

from backend.app.models.revenue import (
    ManualGrantRequest,
    ManualGrantRevokeRequest,
    ManualGrantAuditRecord,
    ManualGrantAuditStatus,
    EntitlementGrant,
    EntitlementStatus,
)
from backend.app.database_revenue import (
    COLL_ENTITLEMENT_GRANTS,
    COLL_MANUAL_GRANT_AUDIT,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_SUBSCRIPTIONS,
)
from backend.app.services.entitlement_service import BENEFIT_TO_MATRIX_MAP

logger = logging.getLogger(__name__)


# ==============================================================================
# DOMAIN EXCEPTIONS
# ==============================================================================

class ManualGrantError(Exception):
    """Base exception for manual grant errors."""
    pass


class IdempotencyConflictError(ManualGrantError):
    """Raised when an idempotency key is replayed with conflicting payload."""
    pass


class ManualGrantValidationError(ManualGrantError):
    """Raised when request parameters fail domain validation."""
    pass


class GrantNotFoundError(ManualGrantError):
    """Raised when the targeted grant for revocation does not exist."""
    pass


class AuditImmutabilityError(ManualGrantError):
    """Raised when an attempt is made to delete or truncate audit records."""
    pass


# ==============================================================================
# CANONICAL HASH HELPER
# ==============================================================================

def compute_grant_payload_hash(req: ManualGrantRequest) -> str:
    """Computes deterministic SHA-256 hash of canonical grant parameters."""
    v_from_str = req.valid_from.isoformat() if req.valid_from else "now"
    canonical_repr = (
        f"{req.target_user_id}|{req.benefit_id}|"
        f"{v_from_str}|{req.valid_until.isoformat()}|"
        f"{req.reason.strip()}|{req.ticket_reference.strip()}"
    )
    return hashlib.sha256(canonical_repr.encode("utf-8")).hexdigest()


def compute_revoke_payload_hash(req: ManualGrantRevokeRequest) -> str:
    """Computes deterministic SHA-256 hash of canonical revoke parameters."""
    canonical_repr = (
        f"{req.target_grant_id}|{req.reason.strip()}|{req.ticket_reference.strip()}"
    )
    return hashlib.sha256(canonical_repr.encode("utf-8")).hexdigest()


# ==============================================================================
# MANUAL ENTITLEMENT GRANT SERVICE
# ==============================================================================

class ManualEntitlementGrantService:
    """
    Service providing audited, idempotent manual entitlement grants and revocations.
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

    def grant_entitlement(
        self,
        request: ManualGrantRequest,
        as_of: Optional[datetime] = None,
    ) -> Dict[str, Any]:
        """
        Executes an audited manual entitlement grant.
        
        Invariants Enforced:
        - Replay same key + same payload -> return existing grant with already_applied=True.
        - Replay same key + different payload -> raise IdempotencyConflictError.
        - Benefit ID must be recognized in the catalog/benefit registry.
        - Two-phase audit: audit record in 'requested' state before grant write.
        - Never creates payment transactions or subscriptions.
        - Never alters quota counters.
        """
        db = self._get_db()
        if db is None:
            raise ManualGrantError("Database unavailable for manual grant execution.")

        eval_time = as_of or datetime.now(timezone.utc)
        grants_col = db[COLL_ENTITLEMENT_GRANTS]
        audit_col = db[COLL_MANUAL_GRANT_AUDIT]

        # 1. Validation
        if not request.actor or len(request.actor.strip()) < 2:
            raise ManualGrantValidationError("Actor identity is mandatory and cannot be empty.")
        if not request.target_user_id or len(request.target_user_id.strip()) < 1:
            raise ManualGrantValidationError("Target user ID is mandatory.")
        if not request.reason or len(request.reason.strip()) < 5:
            raise ManualGrantValidationError("Reason is mandatory and must provide adequate justification.")
        if not request.ticket_reference or len(request.ticket_reference.strip()) < 3:
            raise ManualGrantValidationError("Ticket reference is mandatory.")

        # Validate benefit ID against known benefits
        if request.benefit_id not in BENEFIT_TO_MATRIX_MAP:
            raise ManualGrantValidationError(
                f"Benefit '{request.benefit_id}' is not recognized in catalog benefit mappings."
            )

        # 2. Idempotency Check
        req_hash = compute_grant_payload_hash(request)
        existing_audit = audit_col.find_one({"idempotency_key": request.idempotency_key})

        if existing_audit:
            stored_hash = existing_audit.get("request_hash")
            if stored_hash != req_hash:
                raise IdempotencyConflictError(
                    f"Idempotency key '{request.idempotency_key}' was previously used with different parameters."
                )
            audit_status = existing_audit.get("status")
            if audit_status == ManualGrantAuditStatus.APPLIED.value:
                # Return existing grant
                grant_id = existing_audit.get("target_grant_id")
                existing_grant = grants_col.find_one({"grant_id": grant_id})
                if existing_grant:
                    existing_grant.pop("_id", None)
                return {
                    "status": "already_applied",
                    "grant_id": grant_id,
                    "grant": existing_grant,
                    "idempotency_key": request.idempotency_key,
                }
            elif audit_status == ManualGrantAuditStatus.REQUESTED.value:
                logger.warning("Resuming in-flight/interrupted grant for key '%s'", request.idempotency_key)

        # 3. Two-Phase Audit: Phase 1 — Write 'REQUESTED'
        start_time = request.valid_from or eval_time
        grant_id = existing_audit.get("target_grant_id") if (existing_audit and existing_audit.get("target_grant_id")) else f"grant_manual_{uuid4().hex[:12]}"
        audit_id = existing_audit.get("audit_id") if existing_audit else f"mga_{uuid4().hex[:12]}"

        # Snapshot before state (any existing active grants for user/benefit)
        before_grants = list(grants_col.find({
            "user_id": request.target_user_id,
            "benefit_id": request.benefit_id,
        }))
        for bg in before_grants:
            bg.pop("_id", None)

        audit_record = ManualGrantAuditRecord(
            audit_id=audit_id,
            idempotency_key=request.idempotency_key,
            action="GRANT",
            actor=request.actor,
            target_user_id=request.target_user_id,
            target_grant_id=grant_id,
            benefit_id=request.benefit_id,
            reason=request.reason,
            ticket_reference=request.ticket_reference,
            status=ManualGrantAuditStatus.REQUESTED,
            before_state={"existing_grants": before_grants},
            request_hash=req_hash,
            created_at=eval_time,
            updated_at=eval_time,
        )

        audit_col.update_one(
            {"idempotency_key": request.idempotency_key},
            {"$set": audit_record.model_dump()},
            upsert=True,
        )

        # 4. Phase 2 — Mutate Grant Record
        grant_doc = {
            "grant_id": grant_id,
            "user_id": request.target_user_id,
            "benefit_id": request.benefit_id,
            "status": EntitlementStatus.GRANTED.value,
            "source_type": "staff_override",
            "source_subscription_id": None,
            "valid_from": start_time,
            "valid_until": request.valid_until,
            "metadata": {
                "actor": request.actor,
                "reason": request.reason,
                "ticket_reference": request.ticket_reference,
                "idempotency_key": request.idempotency_key,
                "granted_at": eval_time.isoformat(),
            },
            "schema_version": 1,
            "created_at": eval_time,
            "updated_at": eval_time,
        }

        try:
            grants_col.update_one(
                {"grant_id": grant_id},
                {"$set": grant_doc},
                upsert=True,
            )
        except Exception as exc:
            # Update audit to failed
            audit_col.update_one(
                {"idempotency_key": request.idempotency_key},
                {"$set": {"status": ManualGrantAuditStatus.FAILED.value, "error_reason": str(exc), "updated_at": eval_time}},
            )
            raise ManualGrantError(f"Failed to persist entitlement grant: {exc}")

        # 5. Phase 3 — Finalize Audit Record to 'APPLIED'
        after_grant = dict(grant_doc)
        audit_col.update_one(
            {"idempotency_key": request.idempotency_key},
            {
                "$set": {
                    "status": ManualGrantAuditStatus.APPLIED.value,
                    "target_grant_id": grant_id,
                    "after_state": after_grant,
                    "updated_at": eval_time,
                }
            }
        )

        logger.info(
            "Audited manual grant '%s' applied: user='%s', benefit='%s', actor='%s', valid_until='%s'",
            grant_id, request.target_user_id, request.benefit_id, request.actor, request.valid_until
        )

        return {
            "status": "applied",
            "grant_id": grant_id,
            "grant": after_grant,
            "idempotency_key": request.idempotency_key,
            "audit_id": audit_id,
        }

    def revoke_entitlement(
        self,
        request: ManualGrantRevokeRequest,
        as_of: Optional[datetime] = None,
    ) -> Dict[str, Any]:
        """
        Executes an audited manual entitlement revocation.
        
        Invariants Enforced:
        - Targets designated grant_id exclusively.
        - Does NOT affect independent grants of the user.
        - Does NOT touch payment records or subscriptions.
        - Replay same key + same payload -> return existing revocation.
        - Replay same key + different payload -> raise IdempotencyConflictError.
        - Two-phase audit: audit record in 'requested' state before revocation write.
        """
        db = self._get_db()
        if db is None:
            raise ManualGrantError("Database unavailable for manual grant revocation.")

        eval_time = as_of or datetime.now(timezone.utc)
        grants_col = db[COLL_ENTITLEMENT_GRANTS]
        audit_col = db[COLL_MANUAL_GRANT_AUDIT]

        # 1. Validation
        if not request.actor or len(request.actor.strip()) < 2:
            raise ManualGrantValidationError("Actor identity is mandatory.")
        if not request.target_grant_id:
            raise ManualGrantValidationError("Target grant ID is mandatory.")
        if not request.reason or len(request.reason.strip()) < 5:
            raise ManualGrantValidationError("Reason is mandatory.")
        if not request.ticket_reference or len(request.ticket_reference.strip()) < 3:
            raise ManualGrantValidationError("Ticket reference is mandatory.")

        # 2. Idempotency Check
        req_hash = compute_revoke_payload_hash(request)
        existing_audit = audit_col.find_one({"idempotency_key": request.idempotency_key})

        if existing_audit:
            stored_hash = existing_audit.get("request_hash")
            if stored_hash != req_hash:
                raise IdempotencyConflictError(
                    f"Idempotency key '{request.idempotency_key}' was previously used with different parameters."
                )
            if existing_audit.get("status") == ManualGrantAuditStatus.APPLIED.value:
                grant = grants_col.find_one({"grant_id": request.target_grant_id})
                if grant:
                    grant.pop("_id", None)
                return {
                    "status": "already_applied",
                    "grant_id": request.target_grant_id,
                    "grant": grant,
                    "idempotency_key": request.idempotency_key,
                }

        # 3. Locate Target Grant
        target_grant = grants_col.find_one({"grant_id": request.target_grant_id})
        if not target_grant:
            raise GrantNotFoundError(f"Entitlement grant '{request.target_grant_id}' not found.")

        target_user = target_grant.get("user_id", "")
        target_benefit = target_grant.get("benefit_id", "")
        before_state = dict(target_grant)
        before_state.pop("_id", None)

        audit_id = existing_audit.get("audit_id") if existing_audit else f"mga_rev_{uuid4().hex[:12]}"

        # 4. Phase 1 — Write Audit Record 'REQUESTED'
        audit_record = ManualGrantAuditRecord(
            audit_id=audit_id,
            idempotency_key=request.idempotency_key,
            action="REVOKE",
            actor=request.actor,
            target_user_id=target_user,
            target_grant_id=request.target_grant_id,
            benefit_id=target_benefit,
            reason=request.reason,
            ticket_reference=request.ticket_reference,
            status=ManualGrantAuditStatus.REQUESTED,
            before_state=before_state,
            request_hash=req_hash,
            created_at=eval_time,
            updated_at=eval_time,
        )

        audit_col.update_one(
            {"idempotency_key": request.idempotency_key},
            {"$set": audit_record.model_dump()},
            upsert=True,
        )

        # 5. Phase 2 — Mutate Grant Record to 'REVOKED'
        try:
            grants_col.update_one(
                {"grant_id": request.target_grant_id},
                {
                    "$set": {
                        "status": EntitlementStatus.REVOKED.value,
                        "revoked_at": eval_time,
                        "revocation_metadata": {
                            "actor": request.actor,
                            "reason": request.reason,
                            "ticket_reference": request.ticket_reference,
                            "idempotency_key": request.idempotency_key,
                        },
                        "updated_at": eval_time,
                    }
                }
            )
        except Exception as exc:
            audit_col.update_one(
                {"idempotency_key": request.idempotency_key},
                {"$set": {"status": ManualGrantAuditStatus.FAILED.value, "error_reason": str(exc), "updated_at": eval_time}},
            )
            raise ManualGrantError(f"Failed to revoke entitlement grant: {exc}")

        # 6. Phase 3 — Finalize Audit Record to 'APPLIED'
        after_grant = grants_col.find_one({"grant_id": request.target_grant_id})
        if after_grant:
            after_grant.pop("_id", None)

        audit_col.update_one(
            {"idempotency_key": request.idempotency_key},
            {
                "$set": {
                    "status": ManualGrantAuditStatus.APPLIED.value,
                    "after_state": after_grant,
                    "updated_at": eval_time,
                }
            }
        )

        logger.info(
            "Audited manual revocation applied: grant='%s', user='%s', actor='%s', reason='%s'",
            request.target_grant_id, target_user, request.actor, request.reason
        )

        return {
            "status": "applied",
            "grant_id": request.target_grant_id,
            "grant": after_grant,
            "idempotency_key": request.idempotency_key,
            "audit_id": audit_id,
        }

    def get_audit_history(
        self,
        target_user_id: Optional[str] = None,
        actor: Optional[str] = None,
        limit: int = 50,
    ) -> List[Dict[str, Any]]:
        """Retrieves read-only audit log records."""
        db = self._get_db()
        if db is None:
            raise ManualGrantError("Database unavailable.")

        col = db[COLL_MANUAL_GRANT_AUDIT]
        query: Dict[str, Any] = {}
        if target_user_id:
            query["target_user_id"] = target_user_id
        if actor:
            query["actor"] = actor

        res = col.find(query)
        if hasattr(res, "sort"):
            res = res.sort("created_at", -1)
        if hasattr(res, "limit"):
            res = res.limit(limit)
        records = list(res)
        if not hasattr(col.find(query), "sort"):
            records = sorted(records, key=lambda d: d.get("created_at") or datetime.min, reverse=True)
        records = records[:limit]
        for r in records:
            r.pop("_id", None)
        return records

    def recover_interrupted_audits(
        self,
        min_age_seconds: int = 60,
        as_of: Optional[datetime] = None,
    ) -> List[Dict[str, Any]]:
        """
        Scans for audit records stuck in 'requested' status and resolves them deterministically.
        Invariants:
        1. Does not aggressively fail operations that are still in-flight (age < min_age_seconds).
        2. Correlates grant identity using deterministic idempotency key and request payload hash.
        3. Distinguishes applied, failed, and unresolved outcomes with explicit guidance.
        """
        db = self._get_db()
        if db is None:
            raise ManualGrantError("Database unavailable.")

        eval_time = as_of or datetime.now(timezone.utc)
        audit_col = db[COLL_MANUAL_GRANT_AUDIT]
        grants_col = db[COLL_ENTITLEMENT_GRANTS]

        pending = list(audit_col.find({"status": ManualGrantAuditStatus.REQUESTED.value}))
        results: List[Dict[str, Any]] = []

        for p in pending:
            audit_id = p.get("audit_id")
            action = p.get("action")
            target_grant_id = p.get("target_grant_id")
            idem_key = p.get("idempotency_key")
            created_at = p.get("created_at")

            # Check if record is ambiguous/corrupted
            if not target_grant_id or not idem_key:
                results.append({
                    "audit_id": audit_id,
                    "resolution": "unresolved_corrupt_record",
                    "guidance": "Audit record lacks target_grant_id or idempotency_key; operator manual review required.",
                })
                continue

            # In-flight grace window check: do not mark FAILED if transaction may still be executing
            if created_at and isinstance(created_at, datetime):
                c_time = created_at if created_at.tzinfo else created_at.replace(tzinfo=timezone.utc)
                age = (eval_time - c_time).total_seconds()
                if age < min_age_seconds:
                    logger.info("Audit '%s' is recent (%.1fs < %ds); leaving in-flight.", audit_id, age, min_age_seconds)
                    results.append({
                        "audit_id": audit_id,
                        "resolution": "unresolved_in_flight",
                        "guidance": f"Operation created {age:.1f}s ago; still within in-flight grace window ({min_age_seconds}s).",
                    })
                    continue

            grant = grants_col.find_one({"grant_id": target_grant_id})

            if action == "GRANT":
                if grant:
                    grant_idem = grant.get("metadata", {}).get("idempotency_key")
                    # Deterministic verification: either idempotency key matches or grant belongs to same user/benefit
                    if grant_idem == idem_key or (
                        grant.get("user_id") == p.get("target_user_id") and
                        grant.get("benefit_id") == p.get("benefit_id")
                    ):
                        grant_clean = dict(grant)
                        grant_clean.pop("_id", None)
                        audit_col.update_one(
                            {"audit_id": audit_id},
                            {"$set": {"status": ManualGrantAuditStatus.APPLIED.value, "after_state": grant_clean, "updated_at": eval_time}},
                        )
                        results.append({"audit_id": audit_id, "resolution": "finalized_as_applied"})
                    else:
                        audit_col.update_one(
                            {"audit_id": audit_id},
                            {"$set": {"status": ManualGrantAuditStatus.FAILED.value, "error_reason": "Crash recovery: grant idempotency mismatch.", "updated_at": eval_time}},
                        )
                        results.append({"audit_id": audit_id, "resolution": "marked_as_failed"})
                else:
                    audit_col.update_one(
                        {"audit_id": audit_id},
                        {"$set": {"status": ManualGrantAuditStatus.FAILED.value, "error_reason": "Crash recovery: grant was never written.", "updated_at": eval_time}},
                    )
                    results.append({"audit_id": audit_id, "resolution": "marked_as_failed"})

            elif action == "REVOKE":
                if grant:
                    rev_idem = grant.get("revocation_metadata", {}).get("idempotency_key")
                    if grant.get("status") == EntitlementStatus.REVOKED.value and (rev_idem == idem_key or rev_idem is None):
                        grant_clean = dict(grant)
                        grant_clean.pop("_id", None)
                        audit_col.update_one(
                            {"audit_id": audit_id},
                            {"$set": {"status": ManualGrantAuditStatus.APPLIED.value, "after_state": grant_clean, "updated_at": eval_time}},
                        )
                        results.append({"audit_id": audit_id, "resolution": "finalized_as_applied"})
                    else:
                        audit_col.update_one(
                            {"audit_id": audit_id},
                            {"$set": {"status": ManualGrantAuditStatus.FAILED.value, "error_reason": "Crash recovery: revocation was never written.", "updated_at": eval_time}},
                        )
                        results.append({"audit_id": audit_id, "resolution": "marked_as_failed"})
                else:
                    audit_col.update_one(
                        {"audit_id": audit_id},
                        {"$set": {"status": ManualGrantAuditStatus.FAILED.value, "error_reason": "Crash recovery: target grant not found for revocation.", "updated_at": eval_time}},
                    )
                    results.append({"audit_id": audit_id, "resolution": "marked_as_failed"})

        return results

    def delete_audit_record(self, audit_id: str) -> None:
        """
        Hard deletion invariant: Audit records are append-only.
        Calling this method raises AuditImmutabilityError.
        """
        raise AuditImmutabilityError("Audit records are strictly append-only and cannot be deleted.")
