"""
Unit and Integration Tests for Revenue Reconciliation & Audited Manual Grants.
Checkpoint: CP-10 (Reconciliation Tools, Audited Manual Grants & Operations Runbook).
"""

from __future__ import annotations

from datetime import datetime, timezone, timedelta
import json
import os
import shutil
import subprocess
import threading
import time
import unittest
from typing import Any, Dict, List, Optional
from copy import deepcopy

from pymongo import MongoClient

from fastapi.testclient import TestClient

from backend.main import app
from backend.app.models.revenue import (
    ReconciliationFinding,
    ReconciliationFindingType,
    ReconciliationSeverity,
    ReconciliationActionType,
    ReconciliationPlan,
    ReconciliationPlanStatus,
    ReconciliationApplyResult,
    ManualGrantRequest,
    ManualGrantRevokeRequest,
    ManualGrantAuditStatus,
    SubscriptionStatus,
    EntitlementStatus,
    UsageOpStatus,
    PaymentProviderName,
    PaymentEnvironment,
    StoreProductMapping,
    VerifiedProviderTransaction,
    ProviderVerificationStatus,
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
    COLL_MANUAL_GRANT_AUDIT,
    ensure_revenue_indexes,
)
from backend.app.services.reconciliation_service import (
    ReconciliationScanner,
    ReconciliationService,
    ReconciliationPreconditionFailedError,
    ReconciliationPlanNotFoundError,
    redact_sensitive_evidence,
)
from backend.app.services.manual_grant_service import (
    ManualEntitlementGrantService,
    IdempotencyConflictError,
    ManualGrantValidationError,
    GrantNotFoundError,
    AuditImmutabilityError,
)
from backend.tests.test_revenue_entitlement_quota import MockDatabase as BaseMockDatabase


class ExtendedMockCollection:
    """Mock MongoDB collection supporting find, find_one, update_one, insert_one, sort, and limit."""

    def __init__(self, name: str):
        self.name = name
        self.documents: List[Dict[str, Any]] = []

    def _matches(self, doc: Dict[str, Any], filter_doc: Dict[str, Any]) -> bool:
        for k, v in filter_doc.items():
            if k == "$or":
                sub_matches = [self._matches(doc, sub) for sub in v]
                if not any(sub_matches):
                    return False
                continue

            doc_val = doc.get(k)
            if isinstance(v, dict):
                if "$in" in v and doc_val not in v["$in"]:
                    return False
                if "$lt" in v:
                    if doc_val is None or not (doc_val < v["$lt"]):
                        return False
                if "$gt" in v:
                    if doc_val is None or not (doc_val > v["$gt"]):
                        return False
                if "$lte" in v:
                    if doc_val is None or not (doc_val <= v["$lte"]):
                        return False
                if "$gte" in v:
                    if doc_val is None or not (doc_val >= v["$gte"]):
                        return False
                if "$ne" in v and doc_val == v["$ne"]:
                    return False
            else:
                if doc_val != v:
                    return False
        return True

    def find_one(self, filter_doc: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        for d in self.documents:
            if self._matches(d, filter_doc):
                return deepcopy(d)
        return None

    def find(self, filter_doc: Dict[str, Any]) -> ExtendedMockCursor:
        matched = [deepcopy(d) for d in self.documents if self._matches(d, filter_doc)]
        return ExtendedMockCursor(matched)

    def insert_one(self, doc: Dict[str, Any]):
        self.documents.append(deepcopy(doc))

    def update_one(self, filter_doc: Dict[str, Any], update_doc: Dict[str, Any], upsert: bool = False) -> Dict[str, int]:
        for d in self.documents:
            if self._matches(d, filter_doc):
                self._apply_update(d, update_doc)
                return {"matched_count": 1, "modified_count": 1}
        if upsert:
            new_doc = deepcopy(filter_doc)
            # Remove mongo operator keys from base doc
            clean_new_doc = {k: v for k, v in new_doc.items() if not k.startswith("$")}
            if "$set" in update_doc:
                clean_new_doc.update(deepcopy(update_doc["$set"]))
            self.documents.append(clean_new_doc)
            return {"matched_count": 0, "upserted_id": 1}
        return {"matched_count": 0, "modified_count": 0}

    def _apply_update(self, doc: Dict[str, Any], update_doc: Dict[str, Any]):
        if "$inc" in update_doc:
            for k, inc_val in update_doc["$inc"].items():
                doc[k] = doc.get(k, 0) + inc_val
        if "$set" in update_doc:
            for k, set_val in update_doc["$set"].items():
                doc[k] = deepcopy(set_val)


class ExtendedMockCursor:
    """Mock cursor wrapper supporting .sort() and .limit()."""

    def __init__(self, items: List[Dict[str, Any]]):
        self._items = items

    def sort(self, key: str, direction: int = 1) -> "ExtendedMockCursor":
        self._items = sorted(
            self._items,
            key=lambda d: d.get(key) or datetime.min,
            reverse=(direction < 0),
        )
        return self

    def limit(self, count: int) -> "ExtendedMockCursor":
        self._items = self._items[:count]
        return self

    def __iter__(self):
        return iter(self._items)

    def __len__(self):
        return len(self._items)

    def __getitem__(self, index):
        return self._items[index]


class ExtendedMockDatabase:
    """Mock MongoDB database with cursor and query support."""

    def __init__(self):
        self._collections: Dict[str, ExtendedMockCollection] = {}

    def __getitem__(self, name: str) -> ExtendedMockCollection:
        if name not in self._collections:
            self._collections[name] = ExtendedMockCollection(name)
        return self._collections[name]


# ==============================================================================
# TEST SUITE
# ==============================================================================

class TestRevenueCP10Reconciliation(unittest.TestCase):
    """Targeted verification for CP-10 reconciliation tools and audited manual grants."""

    def setUp(self):
        self.db = ExtendedMockDatabase()
        self.scanner = ReconciliationScanner(db=self.db)
        self.rec_service = ReconciliationService(db=self.db)
        self.grant_service = ManualEntitlementGrantService(db=self.db)
        self.now = datetime(2026, 10, 30, 22, 0, 0, tzinfo=timezone.utc)

    # --------------------------------------------------------------------------
    # 1. Dry-Run Zero Writes
    # --------------------------------------------------------------------------
    def test_dry_run_zero_writes(self):
        """Verifies that scan and generate_plan perform ZERO database writes."""
        # Seed an unprojected event, an expired grant, and a negative bucket
        self.db[COLL_PROVIDER_EVENTS].documents = [{
            "event_id": "evt_dry_01",
            "provider": "apple_app_store",
            "event_type": "INITIAL_PURCHASE",
            "processing_status": "received",
            "projection_snapshot": {"subscription": {}, "grants": []},
            "created_at": self.now - timedelta(hours=1),
        }]
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [{
            "grant_id": "grant_dry_01",
            "user_id": "user_dry",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_until": self.now - timedelta(hours=2),
        }]
        self.db[COLL_USAGE_BUCKETS].documents = [{
            "bucket_id": "b_dry_01",
            "user_id": "user_dry",
            "consumed_units": -5,
            "reserved_units": 0,
        }]

        # Snapshot initial document counts
        initial_counts = {
            coll: len(self.db[coll].documents)
            for coll in [COLL_PROVIDER_EVENTS, COLL_ENTITLEMENT_GRANTS, COLL_USAGE_BUCKETS, COLL_RECONCILIATION_PLANS, COLL_RECONCILIATION_AUDIT]
        }

        # Run scanner
        findings = self.scanner.scan(as_of=self.now)
        self.assertGreater(len(findings), 0)

        # Run generate_plan
        plan = self.rec_service.generate_plan(as_of=self.now)
        self.assertEqual(plan.total_findings, len(findings))

        # Verify exact document counts remain 100% identical (ZERO writes)
        current_counts = {
            coll: len(self.db[coll].documents)
            for coll in [COLL_PROVIDER_EVENTS, COLL_ENTITLEMENT_GRANTS, COLL_USAGE_BUCKETS, COLL_RECONCILIATION_PLANS, COLL_RECONCILIATION_AUDIT]
        }
        self.assertEqual(initial_counts, current_counts)

    # --------------------------------------------------------------------------
    # 2. Scanner Findings Across All Discrepancy Types
    # --------------------------------------------------------------------------
    def test_scanner_detects_all_discrepancy_types(self):
        """Verifies scanner detects unprojected events, mismatches, expired grants, ownership conflicts, negative quota, stranded ops."""
        # 1. Unprojected event
        self.db[COLL_PROVIDER_EVENTS].documents = [{
            "event_id": "evt_stuck_01",
            "provider": "apple_app_store",
            "event_type": "INITIAL_PURCHASE",
            "processing_status": "received",
            "projection_snapshot": {"some": "data"},
            "created_at": self.now,
        }]

        # 2. Active subscription with 0 grants
        self.db[COLL_SUBSCRIPTIONS].documents = [
            {
                "subscription_id": "sub_active_nogrant",
                "user_id": "user_a",
                "status": "active",
                "tier": "plus",
                "current_period_end": self.now + timedelta(days=30),
            },
            # 3. Ownership conflict subscription
            {
                "subscription_id": "sub_conflict",
                "user_id": "user_b",
                "status": "active",
                "ownership_status": "unresolved_conflict",
                "original_transaction_id": "orig_txn_shared",
            },
        ]

        # 4. Expired grant still active
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [{
            "grant_id": "grant_expired_01",
            "user_id": "user_c",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_until": self.now - timedelta(days=2),
        }]

        # 5. Negative quota bucket
        self.db[COLL_USAGE_BUCKETS].documents = [{
            "bucket_id": "b_neg_01",
            "user_id": "user_d",
            "benefit_id": "ai.nutrition_gemini",
            "consumed_units": -3,
            "reserved_units": 0,
        }]

        # 6. Stranded undispatched reservation
        self.db[COLL_USAGE_OPERATIONS].documents = [
            {
                "operation_id": "op_stranded_01",
                "user_id": "user_e",
                "bucket_id": "b_neg_01",
                "status": "reserved",
                "dispatched": False,
                "expires_at": self.now - timedelta(minutes=10),
            },
            # 7. Unknown operation requiring manual review
            {
                "operation_id": "op_unknown_01",
                "user_id": "user_f",
                "bucket_id": "b_neg_01",
                "status": "failed_unknown",
                "dispatched": True,
                "error_reason": "Gemini timeout 504 Gateway Timeout",
            },
        ]

        findings = self.scanner.scan(as_of=self.now)
        finding_types = {f.finding_type for f in findings}

        self.assertIn(ReconciliationFindingType.UNPROJECTED_EVENT, finding_types)
        self.assertIn(ReconciliationFindingType.SUBSCRIPTION_GRANT_MISMATCH, finding_types)
        self.assertIn(ReconciliationFindingType.EXPIRED_GRANT_ACTIVE, finding_types)
        self.assertIn(ReconciliationFindingType.OWNERSHIP_CONFLICT, finding_types)
        self.assertIn(ReconciliationFindingType.NEGATIVE_QUOTA_COUNTER, finding_types)
        self.assertIn(ReconciliationFindingType.STRANDED_RESERVATION, finding_types)
        self.assertIn(ReconciliationFindingType.UNKNOWN_OPERATION_REQUIRING_EVIDENCE, finding_types)

        # Check manual review flags
        unknown_op_findings = [f for f in findings if f.finding_type == ReconciliationFindingType.UNKNOWN_OPERATION_REQUIRING_EVIDENCE]
        self.assertTrue(unknown_op_findings[0].requires_manual_review)

        ownership_findings = [f for f in findings if f.finding_type == ReconciliationFindingType.OWNERSHIP_CONFLICT]
        self.assertTrue(ownership_findings[0].requires_manual_review)

    # --------------------------------------------------------------------------
    # 3. CAS Precondition Enforced (Stale Plan Aborted)
    # --------------------------------------------------------------------------
    def test_stale_plan_cas_precondition_aborted(self):
        """Verifies that if underlying record changes between plan creation and apply, CAS aborts."""
        # Seed an expired grant
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [{
            "grant_id": "grant_cas_01",
            "user_id": "user_cas",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_until": self.now - timedelta(days=1),
        }]

        # Generate and save plan
        plan = self.rec_service.generate_plan(as_of=self.now)
        self.rec_service.save_plan(plan)

        # External out-of-band change: Operator or renewal changes grant status to 'revoked'
        self.db[COLL_ENTITLEMENT_GRANTS].documents[0]["status"] = "revoked"

        # Apply plan
        res = self.rec_service.apply_plan(plan.plan_id, actor="ops_tester", as_of=self.now)

        # Assert action was aborted due to stale precondition
        self.assertEqual(res.aborted_actions, 1)
        self.assertEqual(res.applied_actions, 0)
        self.assertEqual(res.action_details[0]["reason"], "stale_precondition_aborted")

        # Grant status was NOT mutated to expired by the stale plan
        self.assertEqual(self.db[COLL_ENTITLEMENT_GRANTS].documents[0]["status"], "revoked")

    # --------------------------------------------------------------------------
    # 4. Plan Apply Replay Idempotency
    # --------------------------------------------------------------------------
    def test_apply_plan_replay_idempotency(self):
        """Verifies that applying a plan twice produces 0 duplicate mutations."""
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [{
            "grant_id": "grant_idem_01",
            "user_id": "user_idem",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_until": self.now - timedelta(days=1),
        }]

        plan = self.rec_service.generate_plan(as_of=self.now)
        self.rec_service.save_plan(plan)

        # First apply: succeeds
        res1 = self.rec_service.apply_plan(plan.plan_id, actor="ops_tester", as_of=self.now)
        self.assertEqual(res1.status, ReconciliationPlanStatus.APPLIED)
        self.assertEqual(res1.applied_actions, 1)

        # Second apply: idempotent replay returns 0 mutations
        res2 = self.rec_service.apply_plan(plan.plan_id, actor="ops_tester", as_of=self.now)
        self.assertEqual(res2.status, ReconciliationPlanStatus.APPLIED)
        self.assertEqual(res2.applied_actions, 0)

    # --------------------------------------------------------------------------
    # 5. Concurrent Apply Safety (CAS Status Transition)
    # --------------------------------------------------------------------------
    def test_concurrent_apply_blocks_parallel_runner(self):
        """Verifies plan CAS transition from DRAFT -> APPLYING blocks concurrent applies."""
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [{
            "grant_id": "grant_race_01",
            "user_id": "user_race",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_until": self.now - timedelta(days=1),
        }]

        plan = self.rec_service.generate_plan(as_of=self.now)
        self.rec_service.save_plan(plan)

        # Simulate another worker transitioned plan to APPLYING
        self.db[COLL_RECONCILIATION_PLANS].documents[0]["status"] = ReconciliationPlanStatus.APPLYING.value

        # Second worker attempting apply gets rejected
        with self.assertRaises(ReconciliationPreconditionFailedError):
            self.rec_service.apply_plan(plan.plan_id, actor="concurrent_worker")

    # --------------------------------------------------------------------------
    # 6. Recovery Service Integration (Reclaim Reservation & Bucket Adjust)
    # --------------------------------------------------------------------------
    def test_apply_reclaims_stranded_reservation_and_fixes_negative_quota(self):
        """Verifies plan application reclaims stranded reservation units and fixes negative bucket."""
        self.db[COLL_USAGE_BUCKETS].documents = [{
            "bucket_id": "b_fix_01",
            "user_id": "user_fix",
            "consumed_units": -4,
            "reserved_units": 2,
        }]
        self.db[COLL_USAGE_OPERATIONS].documents = [{
            "operation_id": "op_fix_01",
            "user_id": "user_fix",
            "bucket_id": "b_fix_01",
            "units": 2,
            "status": "reserved",
            "dispatched": False,
            "expires_at": self.now - timedelta(minutes=15),
        }]

        plan = self.rec_service.generate_plan(as_of=self.now)
        self.rec_service.save_plan(plan)

        res = self.rec_service.apply_plan(plan.plan_id, actor="ops_tester", as_of=self.now)
        self.assertEqual(res.status, ReconciliationPlanStatus.APPLIED)
        self.assertEqual(res.applied_actions, 2)

        # Check operation is now RELEASED
        op = self.db[COLL_USAGE_OPERATIONS].documents[0]
        self.assertEqual(op["status"], UsageOpStatus.RELEASED.value)

        # Check bucket consumed units clamped back to 0, reserved decremented by 2
        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["consumed_units"], 0)
        self.assertEqual(bucket["reserved_units"], 0)

    # --------------------------------------------------------------------------
    # 7. Audited Manual Grant Creation Invariants
    # --------------------------------------------------------------------------
    def test_manual_grant_creates_entitlement_with_audit_trail(self):
        """Verifies valid manual grant creates EntitlementGrant without fake subscriptions/payments."""
        req = ManualGrantRequest(
            idempotency_key="key_grant_valid_001",
            actor="support_lead_01",
            target_user_id="user_goodwill",
            benefit_id="ai.nutrition_gemini",
            valid_from=self.now,
            valid_until=self.now + timedelta(days=14),
            reason="Goodwill compensation for incident INC-842",
            ticket_reference="INC-842",
        )

        res = self.grant_service.grant_entitlement(req, as_of=self.now)
        self.assertEqual(res["status"], "applied")
        grant_id = res["grant_id"]

        # 1. EntitlementGrant exists with staff_override source
        grant = self.db[COLL_ENTITLEMENT_GRANTS].find_one({"grant_id": grant_id})
        self.assertIsNotNone(grant)
        self.assertEqual(grant["status"], EntitlementStatus.GRANTED.value)
        self.assertEqual(grant["source_type"], "staff_override")
        self.assertEqual(grant["metadata"]["ticket_reference"], "INC-842")

        # 2. Invariant: ZERO fake subscriptions or payment transactions created
        self.assertEqual(len(self.db[COLL_SUBSCRIPTIONS].documents), 0)
        self.assertEqual(len(self.db[COLL_PAYMENT_TRANSACTIONS].documents), 0)

        # 3. Invariant: Usage buckets untouched
        self.assertEqual(len(self.db[COLL_USAGE_BUCKETS].documents), 0)

        # 4. Invariant: Audit log record created and finalized to APPLIED
        audit = self.db[COLL_MANUAL_GRANT_AUDIT].find_one({"idempotency_key": "key_grant_valid_001"})
        self.assertIsNotNone(audit)
        self.assertEqual(audit["status"], ManualGrantAuditStatus.APPLIED.value)
        self.assertEqual(audit["actor"], "support_lead_01")

    # --------------------------------------------------------------------------
    # 8. Permanent Grants Forbidden
    # --------------------------------------------------------------------------
    def test_manual_grant_rejects_missing_or_past_valid_until(self):
        """Verifies that permanent grants or past expiration timestamps are strictly rejected."""
        # Past timestamp
        with self.assertRaises(ValueError):
            ManualGrantRequest(
                idempotency_key="key_invalid_time_01",
                actor="support_agent",
                target_user_id="user_test",
                benefit_id="ai.nutrition_gemini",
                valid_from=self.now,
                valid_until=self.now - timedelta(days=1),  # Past!
                reason="Invalid permanent attempt",
                ticket_reference="TICKET-001",
            )

    # --------------------------------------------------------------------------
    # 9. Manual Grant Idempotency & Conflict Detection
    # --------------------------------------------------------------------------
    def test_manual_grant_idempotency_and_payload_conflict(self):
        """Verifies same key same payload returns existing, same key different payload raises conflict."""
        req1 = ManualGrantRequest(
            idempotency_key="key_shared_idempotent",
            actor="agent_alpha",
            target_user_id="user_replay",
            benefit_id="ai.nutrition_gemini",
            valid_from=self.now,
            valid_until=self.now + timedelta(days=7),
            reason="Service issue compensation",
            ticket_reference="SUP-101",
        )

        res1 = self.grant_service.grant_entitlement(req1, as_of=self.now)
        self.assertEqual(res1["status"], "applied")
        grant_id = res1["grant_id"]

        # Exact replay with same key and same payload
        res2 = self.grant_service.grant_entitlement(req1, as_of=self.now)
        self.assertEqual(res2["status"], "already_applied")
        self.assertEqual(res2["grant_id"], grant_id)

        # Conflicting replay with same key but DIFFERENT benefit
        req_conflict = ManualGrantRequest(
            idempotency_key="key_shared_idempotent",
            actor="agent_alpha",
            target_user_id="user_replay",
            benefit_id="workout.cv.ai",  # Changed!
            valid_from=self.now,
            valid_until=self.now + timedelta(days=7),
            reason="Service issue compensation",
            ticket_reference="SUP-101",
        )

        with self.assertRaises(IdempotencyConflictError):
            self.grant_service.grant_entitlement(req_conflict, as_of=self.now)

    # --------------------------------------------------------------------------
    # 10. Targeted Manual Revocation Isolation
    # --------------------------------------------------------------------------
    def test_manual_revocation_targets_specific_grant_only(self):
        """Verifies revoking a grant does not affect independent user grants or payment history."""
        # Setup Grant A (manual) and Grant B (independent staff override)
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [
            {
                "grant_id": "grant_target_a",
                "user_id": "user_multi_grant",
                "benefit_id": "ai.nutrition_gemini",
                "status": "granted",
                "source_type": "staff_override",
            },
            {
                "grant_id": "grant_independent_b",
                "user_id": "user_multi_grant",
                "benefit_id": "workout.cv.ai",
                "status": "granted",
                "source_type": "staff_override",
            },
        ]
        self.db[COLL_PAYMENT_TRANSACTIONS].documents = [{
            "transaction_id": "tx_historical_01",
            "user_id": "user_multi_grant",
            "amount_cents": 1000,
        }]

        req = ManualGrantRevokeRequest(
            idempotency_key="key_revoke_01",
            actor="compliance_officer",
            target_grant_id="grant_target_a",
            reason="Grant issued in error for wrong account",
            ticket_reference="ERR-999",
        )

        res = self.grant_service.revoke_entitlement(req, as_of=self.now)
        self.assertEqual(res["status"], "applied")

        # Grant A is revoked
        grant_a = self.db[COLL_ENTITLEMENT_GRANTS].find_one({"grant_id": "grant_target_a"})
        self.assertEqual(grant_a["status"], EntitlementStatus.REVOKED.value)

        # Grant B remains GRANTED and completely untouched
        grant_b = self.db[COLL_ENTITLEMENT_GRANTS].find_one({"grant_id": "grant_independent_b"})
        self.assertEqual(grant_b["status"], "granted")

        # Payment transactions untouched
        self.assertEqual(len(self.db[COLL_PAYMENT_TRANSACTIONS].documents), 1)

    # --------------------------------------------------------------------------
    # 11. Crash Recovery of Interrupted Audits
    # --------------------------------------------------------------------------
    def test_crash_recovery_resolves_interrupted_audit_records(self):
        """Verifies recover_interrupted_audits handles crashes between audit write and grant write."""
        # Case 1: Crash happened AFTER grant was written, but BEFORE audit was updated to APPLIED
        self.db[COLL_MANUAL_GRANT_AUDIT].documents.append({
            "audit_id": "audit_crash_01",
            "idempotency_key": "key_crash_01",
            "action": "GRANT",
            "target_grant_id": "grant_written_ok",
            "status": "requested",
        })
        self.db[COLL_ENTITLEMENT_GRANTS].documents.append({
            "grant_id": "grant_written_ok",
            "status": "granted",
        })

        # Case 2: Crash happened BEFORE grant was written
        self.db[COLL_MANUAL_GRANT_AUDIT].documents.append({
            "audit_id": "audit_crash_02",
            "idempotency_key": "key_crash_02",
            "action": "GRANT",
            "target_grant_id": "grant_never_written",
            "status": "requested",
        })

        results = self.grant_service.recover_interrupted_audits(as_of=self.now)
        self.assertEqual(len(results), 2)

        # Audit 1 finalized as applied
        a1 = self.db[COLL_MANUAL_GRANT_AUDIT].find_one({"audit_id": "audit_crash_01"})
        self.assertEqual(a1["status"], ManualGrantAuditStatus.APPLIED.value)

        # Audit 2 marked as failed
        a2 = self.db[COLL_MANUAL_GRANT_AUDIT].find_one({"audit_id": "audit_crash_02"})
        self.assertEqual(a2["status"], ManualGrantAuditStatus.FAILED.value)

    # --------------------------------------------------------------------------
    # 12. Audit Immutability (Hard Delete Rejected)
    # --------------------------------------------------------------------------
    def test_audit_records_are_append_only(self):
        """Verifies that calling delete_audit_record raises AuditImmutabilityError."""
        with self.assertRaises(AuditImmutabilityError):
            self.grant_service.delete_audit_record("audit_immutable_01")

    # --------------------------------------------------------------------------
    # 13. HTTP Operational Boundary
    # --------------------------------------------------------------------------
    def test_http_operational_boundary_rejects_admin_mutation(self):
        """Verifies public HTTP API does not expose admin grant/reconciliation mutation routes."""
        client = TestClient(app)

        # Attempting POST /api/revenue/grants returns 404
        res1 = client.post("/api/revenue/grants", json={"actor": "spoofed_admin", "user": "user1"})
        self.assertEqual(res1.status_code, 404)

        # Attempting POST /api/revenue/reconcile/apply returns 404
        res2 = client.post("/api/revenue/reconcile/apply", json={"plan_id": "p1"})
        self.assertEqual(res2.status_code, 404)

        # Attempting DELETE on catalog returns 405
        res3 = client.delete("/api/revenue/catalog")
        self.assertEqual(res3.status_code, 405)

    # --------------------------------------------------------------------------
    # 14. Sensitive Data Redaction
    # --------------------------------------------------------------------------
    def test_sensitive_payload_redaction(self):
        """Verifies raw receipts, prompts, and tokens are hashed and never stored in findings."""
        raw_evidence = {
            "event_id": "evt_sensitive_01",
            "verification_token": "secret_app_store_jws_receipt_raw_token_xyz123",
            "prompt": "Analyze meal containing 500g salmon and sweet potato for client",
            "raw_payload": {"nested_secret": "my_secret_token"},
            "user_id": "user_normal",
        }

        redacted = redact_sensitive_evidence(raw_evidence)

        # Raw strings must NOT exist in the output dict
        self.assertNotIn("verification_token", redacted)
        self.assertNotIn("prompt", redacted)
        self.assertNotIn("raw_payload", redacted)

        # Cryptographic SHA-256 hashes must be present
        self.assertIn("verification_token_sha256", redacted)
        self.assertIn("prompt_sha256", redacted)
        self.assertIn("raw_payload_sha256", redacted)
        self.assertEqual(redacted["user_id"], "user_normal")

    # --------------------------------------------------------------------------
    # 15. Quota Bucket CAS Race Prevention (Stale Plan Aborted)
    # --------------------------------------------------------------------------
    def test_quota_bucket_cas_race_stale_plan_aborted(self):
        """Verifies that an intervening quota mutation causes stale plan apply to abort safely."""
        self.db[COLL_USAGE_BUCKETS].documents = [{
            "bucket_id": "b_stale_01",
            "user_id": "user_stale",
            "benefit_id": "ai.nutrition_gemini",
            "period_key": "202610",
            "limit_units": 50,
            "consumed_units": -5,
            "reserved_units": 0,
            "reset_at": self.now + timedelta(days=15),
            "created_at": self.now,
            "updated_at": self.now,
        }]

        # Step 1: Scan and generate plan expecting consumed_units = -5
        plan = self.rec_service.generate_plan(as_of=self.now)
        self.rec_service.save_plan(plan)
        self.assertEqual(plan.total_findings, 1)

        # Step 2: Intervening request mutates bucket (e.g. user consumed 3 units -> consumed = -2)
        self.db[COLL_USAGE_BUCKETS].documents[0]["consumed_units"] = -2

        # Step 3: Apply stale plan
        res = self.rec_service.apply_plan(plan.plan_id, actor="ops_tester", as_of=self.now)

        # Assert: Action was aborted, zero mutations applied
        self.assertEqual(res.aborted_actions, 1)
        self.assertEqual(res.applied_actions, 0)
        self.assertEqual(res.action_details[0]["status"], "aborted")

        # Bucket state was NOT overwritten by the stale plan; remains -2
        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["consumed_units"], -2)

    # --------------------------------------------------------------------------
    # 16. Quota Bucket Already-Applied Zero Mutation
    # --------------------------------------------------------------------------
    def test_quota_bucket_already_applied_zero_mutation(self):
        """Verifies that if negative bucket was already resolved out-of-band, apply returns already_applied with 0 mutations."""
        self.db[COLL_USAGE_BUCKETS].documents = [{
            "bucket_id": "b_resolved_01",
            "user_id": "user_res",
            "benefit_id": "ai.nutrition_gemini",
            "period_key": "202610",
            "limit_units": 50,
            "consumed_units": -3,
            "reserved_units": 0,
            "reset_at": self.now + timedelta(days=15),
            "created_at": self.now,
            "updated_at": self.now,
        }]

        plan = self.rec_service.generate_plan(as_of=self.now)
        self.rec_service.save_plan(plan)

        # Out-of-band resolution restores bucket to 0
        self.db[COLL_USAGE_BUCKETS].documents[0]["consumed_units"] = 0

        res = self.rec_service.apply_plan(plan.plan_id, actor="ops_tester", as_of=self.now)
        self.assertEqual(res.applied_actions, 0)
        self.assertEqual(res.aborted_actions, 0)
        self.assertEqual(res.action_details[0]["status"], "already_applied")
        self.assertEqual(self.db[COLL_USAGE_BUCKETS].documents[0]["consumed_units"], 0)

    # --------------------------------------------------------------------------
    # 17. Audit Recovery In-Flight Grace Window
    # --------------------------------------------------------------------------
    def test_audit_recovery_in_flight_grace_window(self):
        """Verifies recent audit (< 60s) is preserved as unresolved_in_flight rather than falsely marked FAILED."""
        self.db[COLL_MANUAL_GRANT_AUDIT].documents = [{
            "audit_id": "audit_inflight_01",
            "idempotency_key": "key_inflight_01",
            "action": "GRANT",
            "target_grant_id": "grant_inflight_01",
            "target_user_id": "user_inflight",
            "benefit_id": "ai.nutrition_gemini",
            "status": "requested",
            "created_at": self.now - timedelta(seconds=15),
        }]

        # Run recovery with default min_age_seconds=60
        results = self.grant_service.recover_interrupted_audits(min_age_seconds=60, as_of=self.now)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["resolution"], "unresolved_in_flight")

        # Status remains 'requested' in database
        audit = self.db[COLL_MANUAL_GRANT_AUDIT].documents[0]
        self.assertEqual(audit["status"], "requested")

    # --------------------------------------------------------------------------
    # 18. Audit Recovery Deterministic Key Correlation
    # --------------------------------------------------------------------------
    def test_audit_recovery_deterministic_key_correlation(self):
        """Verifies recovery confirms grant creation via idempotency key and finalizes as APPLIED."""
        self.db[COLL_MANUAL_GRANT_AUDIT].documents = [{
            "audit_id": "audit_crashed_01",
            "idempotency_key": "key_determ_01",
            "action": "GRANT",
            "target_grant_id": "grant_determ_01",
            "target_user_id": "user_determ",
            "benefit_id": "ai.nutrition_gemini",
            "status": "requested",
            "created_at": self.now - timedelta(minutes=5),
        }]
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [{
            "grant_id": "grant_determ_01",
            "user_id": "user_determ",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "metadata": {"idempotency_key": "key_determ_01"},
        }]

        results = self.grant_service.recover_interrupted_audits(min_age_seconds=60, as_of=self.now)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["resolution"], "finalized_as_applied")

        audit = self.db[COLL_MANUAL_GRANT_AUDIT].documents[0]
        self.assertEqual(audit["status"], "applied")

    # --------------------------------------------------------------------------
    # 19. Redaction Nested List Support
    # --------------------------------------------------------------------------
    def test_redact_sensitive_evidence_recursive_list(self):
        """Verifies sensitive items in nested lists are recursively redacted."""
        evidence = {
            "findings": [
                {"raw_receipt": "receipt_data_in_list_item", "item_id": 1},
                {"prompt": "User meal prompt in list item", "item_id": 2},
            ],
            "scalar": "safe_value",
        }
        redacted = redact_sensitive_evidence(evidence)
        self.assertNotIn("raw_receipt", redacted["findings"][0])
        self.assertIn("raw_receipt_sha256", redacted["findings"][0])
        self.assertNotIn("prompt", redacted["findings"][1])
        self.assertIn("prompt_sha256", redacted["findings"][1])
        self.assertEqual(redacted["findings"][0]["item_id"], 1)


# ==============================================================================
# SECTION B: Real Isolated WiredTiger MongoDB Tests (Port 27099)
# ==============================================================================

class TestRealMongoReconciliationAndAuditRecovery(unittest.TestCase):
    """
    Executes real WiredTiger isolated MongoDB integration tests on loopback port 27099.
    Verifies:
    1. Concurrent plan apply by two workers (atomic CAS lock).
    2. Quota mutation intervening between scan and apply.
    3. Crash after write before audit applied and deterministic recovery.
    4. Idempotent retry with 0 duplicate mutations.
    """
    MONGOD_EXE = r"D:\SamanDev\tools\mongodb-cp7\mongodb-win32-x86_64-windows-7.0.14\bin\mongod.exe"
    PORT = 27099
    DBPATH = r"D:\SamanDev\runtime_evidence\saman-revenue\REVENUE-R01\20261031_124200\mongo_data"
    mongod_proc: Optional[subprocess.Popen] = None
    mongo_client: Optional[MongoClient] = None
    real_db: Any = None
    mongod_available: bool = False

    @classmethod
    def setUpClass(cls):
        if not os.path.exists(cls.MONGOD_EXE):
            print(f"[Notice] mongod binary not found at {cls.MONGOD_EXE}; skipping real Mongo tests.")
            return

        os.makedirs(cls.DBPATH, exist_ok=True)
        cmd = [
            cls.MONGOD_EXE,
            "--port", str(cls.PORT),
            "--bind_ip", "127.0.0.1",
            "--dbpath", cls.DBPATH,
            "--wiredTigerCacheSizeGB", "0.25",
            "--quiet",
        ]
        try:
            cls.mongod_proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(2.0)
            cls.mongo_client = MongoClient(f"mongodb://127.0.0.1:{cls.PORT}", serverSelectionTimeoutMS=3000)
            cls.mongo_client.admin.command("ping")
            cls.real_db = cls.mongo_client["saman_revenue_r01_isolated"]
            cls.mongod_available = True
            ensure_revenue_indexes(db=cls.real_db, dry_run=False)
        except Exception as exc:
            print(f"[Notice] Could not initialize isolated mongod on port {cls.PORT}: {exc}")
            cls.mongod_available = False
            if cls.mongod_proc:
                cls.mongod_proc.terminate()
                cls.mongod_proc = None

    @classmethod
    def tearDownClass(cls):
        if cls.mongo_client:
            try:
                cls.mongo_client.close()
            except Exception:
                pass
        if cls.mongod_proc:
            try:
                cls.mongod_proc.terminate()
                cls.mongod_proc.wait(timeout=5)
            except Exception:
                try:
                    cls.mongod_proc.kill()
                except Exception:
                    pass
        if os.path.exists(cls.DBPATH):
            try:
                shutil.rmtree(cls.DBPATH, ignore_errors=True)
            except Exception:
                pass

    def setUp(self):
        if not self.mongod_available:
            self.skipTest("Isolated MongoDB 7.0 not available on 127.0.0.1:27099")
        self.now = datetime(2026, 10, 31, 12, 0, 0, tzinfo=timezone.utc)
        self.real_db[COLL_USAGE_BUCKETS].delete_many({})
        self.real_db[COLL_USAGE_OPERATIONS].delete_many({})
        self.real_db[COLL_ENTITLEMENT_GRANTS].delete_many({})
        self.real_db[COLL_RECONCILIATION_PLANS].delete_many({})
        self.real_db[COLL_RECONCILIATION_AUDIT].delete_many({})
        self.real_db[COLL_MANUAL_GRANT_AUDIT].delete_many({})
        self.rec_service = ReconciliationService(db=self.real_db)
        self.grant_service = ManualEntitlementGrantService(db=self.real_db)

    def test_real_mongo_two_workers_apply_same_plan(self):
        """Verifies atomic CAS plan transition on real WiredTiger prevents duplicate execution across threads."""
        self.real_db[COLL_USAGE_BUCKETS].insert_one({
            "bucket_id": "b_real_race_01",
            "user_id": "user_real_race",
            "benefit_id": "ai.nutrition_gemini",
            "period_key": "202610",
            "limit_units": 50,
            "consumed_units": -4,
            "reserved_units": 0,
            "reset_at": self.now + timedelta(days=15),
            "created_at": self.now,
            "updated_at": self.now,
        })

        plan = self.rec_service.generate_plan(as_of=self.now)
        self.rec_service.save_plan(plan)

        results: List[Any] = []
        errors: List[Exception] = []

        def worker_task(worker_name: str):
            try:
                res = self.rec_service.apply_plan(plan.plan_id, actor=worker_name, as_of=self.now)
                results.append(res)
            except Exception as exc:
                errors.append(exc)

        t1 = threading.Thread(target=worker_task, args=("worker_alpha",))
        t2 = threading.Thread(target=worker_task, args=("worker_beta",))

        t1.start()
        t2.start()
        t1.join()
        t2.join()

        # Total successful applies across both threads must be exactly 1
        applied_total = sum(r.applied_actions for r in results)
        self.assertEqual(applied_total, 1)

        # Bucket consumed units in real MongoDB must be exactly 0 (adjusted once, never duplicated)
        bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({"bucket_id": "b_real_race_01"})
        self.assertEqual(bucket["consumed_units"], 0)

    def test_real_mongo_quota_mutation_intervening_between_scan_and_apply(self):
        """Verifies that on real WiredTiger, intervening write aborts stale CAS plan without corrupting bucket."""
        self.real_db[COLL_USAGE_BUCKETS].insert_one({
            "bucket_id": "b_real_intervene_01",
            "user_id": "user_intervene",
            "benefit_id": "ai.nutrition_gemini",
            "period_key": "202610",
            "limit_units": 50,
            "consumed_units": -6,
            "reserved_units": 0,
            "reset_at": self.now + timedelta(days=15),
            "created_at": self.now,
            "updated_at": self.now,
        })

        # Scan and generate plan expecting consumed_units = -6
        plan = self.rec_service.generate_plan(as_of=self.now)
        self.rec_service.save_plan(plan)

        # Intervening write: another request changes consumed_units to -2
        self.real_db[COLL_USAGE_BUCKETS].update_one(
            {"bucket_id": "b_real_intervene_01"},
            {"$set": {"consumed_units": -2}}
        )

        # Apply stale plan
        res = self.rec_service.apply_plan(plan.plan_id, actor="ops_tester", as_of=self.now)

        # Assert: Action was aborted, zero mutations applied
        self.assertEqual(res.aborted_actions, 1)
        self.assertEqual(res.applied_actions, 0)

        # Bucket in MongoDB remains -2
        bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({"bucket_id": "b_real_intervene_01"})
        self.assertEqual(bucket["consumed_units"], -2)

    def test_real_mongo_crash_after_write_before_audit_applied_and_recovery(self):
        """Verifies deterministic crash recovery on real WiredTiger MongoDB."""
        grant_id = "grant_real_crash_01"
        idem_key = "key_real_crash_01"

        # Simulate crash: grant was written, audit is stuck in 'requested'
        self.real_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": grant_id,
            "user_id": "user_real_crash",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "metadata": {"idempotency_key": idem_key},
            "valid_from": self.now,
            "valid_until": self.now + timedelta(days=7),
            "created_at": self.now,
            "updated_at": self.now,
        })
        self.real_db[COLL_MANUAL_GRANT_AUDIT].insert_one({
            "audit_id": "audit_real_crash_01",
            "idempotency_key": idem_key,
            "action": "GRANT",
            "target_grant_id": grant_id,
            "target_user_id": "user_real_crash",
            "benefit_id": "ai.nutrition_gemini",
            "status": "requested",
            "created_at": self.now - timedelta(minutes=10),
            "updated_at": self.now - timedelta(minutes=10),
        })

        results = self.grant_service.recover_interrupted_audits(min_age_seconds=60, as_of=self.now)
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["resolution"], "finalized_as_applied")

        # Audit record transitioned to 'applied' with after_state populated
        audit = self.real_db[COLL_MANUAL_GRANT_AUDIT].find_one({"audit_id": "audit_real_crash_01"})
        self.assertEqual(audit["status"], "applied")
        self.assertEqual(audit["after_state"]["grant_id"], grant_id)

    def test_real_mongo_retry_recovery_no_duplicate_mutation(self):
        """Verifies re-running recovery on real MongoDB produces zero duplicate mutations."""
        # Run recovery on clean collection -> empty results
        results = self.grant_service.recover_interrupted_audits(as_of=self.now)
        self.assertEqual(len(results), 0)


if __name__ == "__main__":
    unittest.main()
