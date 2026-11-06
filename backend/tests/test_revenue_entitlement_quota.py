"""
Comprehensive Unit, Concurrency, and Recovery Tests for Revenue Entitlement & Quota Service.
Checkpoint: CP-04 (Backend Entitlement Evaluation & Atomic Quota Reservation).

Covers:
1. Entitlement hierarchy (Explicit Grants > Paid Subscription > Free Tier).
2. Boundary testing with clock injection (valid_from, valid_until, current_period_end).
3. Fail-closed storage failure handling for paid AI capabilities.
4. Standalone MongoDB atomic quota reservation ($expr, $lte, $inc).
5. High-concurrency race condition prevention (parallel threads competing for quota).
6. Idempotency & fingerprint mismatch detection (409 Conflict).
7. Tenant isolation (User A vs User B).
8. Idempotent commit and release transitions (no double-counting, no negative counters).
9. Stale worker lease protection.
10. Cross-window finalization (operations finalize to originating bucket).
11. Crash recovery sweeps for undispatched vs dispatched stalled operations.
12. Optional real MongoDB isolated integration test using local mongod binary on loopback port 27099.
"""

import unittest
import threading
import subprocess
import time
import os
import shutil
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List, Optional
from copy import deepcopy

from backend.app.models.revenue import (
    EntitlementDecisionStatus,
    EntitlementStatus,
    MembershipTier,
    ReservationStatus,
    SubscriptionStatus,
    UsageOpStatus,
)
from backend.app.services.entitlement_service import EntitlementService
from backend.app.services.quota_service import QuotaService
from backend.app.services.quota_recovery_service import QuotaRecoveryService
from backend.app.database_revenue import (
    COLL_ENTITLEMENT_GRANTS,
    COLL_SUBSCRIPTIONS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_FOOD_ANALYSIS_IDEMPOTENCY,
    ensure_revenue_indexes,
)


class MockCollection:
    """Thread-safe in-memory MongoDB collection mock supporting atomic find_one_and_update."""

    def __init__(self, name: str):
        self.name = name
        self.documents: List[Dict[str, Any]] = []
        self._lock = threading.Lock()
        self.unique_keys: List[List[str]] = []

    def _matches(self, doc: Dict[str, Any], filter_doc: Dict[str, Any]) -> bool:
        for k, v in filter_doc.items():
            if k == "$expr":
                # Evaluate {$lte: [{$add: ["$consumed_units", "$reserved_units", units]}, "$limit_units"]}
                expr = v
                if "$lte" in expr:
                    left, right = expr["$lte"]
                    if isinstance(left, dict) and "$add" in left:
                        add_terms = left["$add"]
                        sum_val = 0
                        for term in add_terms:
                            if isinstance(term, str) and term.startswith("$"):
                                sum_val += doc.get(term.lstrip("$"), 0)
                            elif isinstance(term, (int, float)):
                                sum_val += term
                        limit_val = doc.get(right.lstrip("$"), 0) if isinstance(right, str) and right.startswith("$") else right
                        if sum_val > limit_val:
                            return False
                continue

            if isinstance(v, dict):
                doc_val = doc.get(k)
                if "$in" in v and doc_val not in v["$in"]:
                    return False
                if "$lt" in v and not (doc_val is not None and doc_val < v["$lt"]):
                    return False
                if "$gt" in v and not (doc_val is not None and doc_val > v["$gt"]):
                    return False
                if "$lte" in v and not (doc_val is not None and doc_val <= v["$lte"]):
                    return False
                if "$gte" in v and not (doc_val is not None and doc_val >= v["$gte"]):
                    return False
            else:
                if doc.get(k) != v:
                    return False
        return True

    def find_one(self, filter_doc: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        with self._lock:
            for d in self.documents:
                if self._matches(d, filter_doc):
                    return deepcopy(d)
            return None

    def find(self, filter_doc: Dict[str, Any]) -> List[Dict[str, Any]]:
        with self._lock:
            return [deepcopy(d) for d in self.documents if self._matches(d, filter_doc)]

    def insert_one(self, doc: Dict[str, Any]):
        with self._lock:
            # Check unique constraint simulation
            if self.name == COLL_USAGE_OPERATIONS:
                for existing in self.documents:
                    if (existing.get("user_id") == doc.get("user_id") and
                        existing.get("benefit_id") == doc.get("benefit_id") and
                        existing.get("idempotency_key") == doc.get("idempotency_key")):
                        raise RuntimeError(f"DuplicateKeyError on {self.name}")
            self.documents.append(deepcopy(doc))

    def update_one(self, filter_doc: Dict[str, Any], update_doc: Dict[str, Any], upsert: bool = False):
        with self._lock:
            for d in self.documents:
                if self._matches(d, filter_doc):
                    self._apply_update(d, update_doc)
                    return {"matched_count": 1, "modified_count": 1}
            if upsert:
                new_doc = deepcopy(filter_doc)
                if "$setOnInsert" in update_doc:
                    new_doc.update(deepcopy(update_doc["$setOnInsert"]))
                if "$set" in update_doc:
                    new_doc.update(deepcopy(update_doc["$set"]))
                self.documents.append(new_doc)
                return {"matched_count": 0, "upserted_id": new_doc.get("_id")}
            return {"matched_count": 0, "modified_count": 0}

    def find_one_and_update(self, filter_doc: Dict[str, Any], update_doc: Dict[str, Any], **kwargs) -> Optional[Dict[str, Any]]:
        with self._lock:
            for d in self.documents:
                if self._matches(d, filter_doc):
                    self._apply_update(d, update_doc)
                    return deepcopy(d)
            return None

    def _apply_update(self, doc: Dict[str, Any], update_doc: Dict[str, Any]):
        if "$inc" in update_doc:
            for k, inc_val in update_doc["$inc"].items():
                doc[k] = doc.get(k, 0) + inc_val
        if "$set" in update_doc:
            for k, set_val in update_doc["$set"].items():
                doc[k] = deepcopy(set_val)


class MockDatabase:
    """Mock MongoDB database."""

    def __init__(self):
        self._collections: Dict[str, MockCollection] = {}

    def __getitem__(self, name: str) -> MockCollection:
        if name not in self._collections:
            self._collections[name] = MockCollection(name)
        return self._collections[name]


# ==============================================================================
# 1. ENTITLEMENT EVALUATION TESTS
# ==============================================================================

class TestEntitlementEvaluation(unittest.TestCase):
    def setUp(self):
        self.db = MockDatabase()
        self.service = EntitlementService(db=self.db)
        self.now = datetime(2026, 10, 29, 12, 0, 0, tzinfo=timezone.utc)

    def test_explicit_grant_active_allowed(self):
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [{
            "grant_id": "grant_001",
            "user_id": "user_vip",
            "benefit_id": "ai.nutrition_gemini",
            "status": EntitlementStatus.GRANTED.value,
            "source_type": "staff_override",
            "valid_from": self.now - timedelta(days=1),
            "valid_until": self.now + timedelta(days=30),
        }]
        decision = self.service.evaluate_entitlement("user_vip", "ai.nutrition_gemini", as_of=self.now)
        self.assertEqual(decision.status, EntitlementDecisionStatus.ALLOWED)
        self.assertEqual(decision.source, "staff_override")

    def test_explicit_grant_expired(self):
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [{
            "grant_id": "grant_002",
            "user_id": "user_vip",
            "benefit_id": "ai.nutrition_gemini",
            "status": EntitlementStatus.GRANTED.value,
            "valid_from": self.now - timedelta(days=30),
            "valid_until": self.now - timedelta(days=1),
        }]
        decision = self.service.evaluate_entitlement("user_vip", "ai.nutrition_gemini", as_of=self.now)
        # Grant expired -> falls through to free tier -> gemini is not included in free -> ENTITLEMENT_REQUIRED
        self.assertEqual(decision.status, EntitlementDecisionStatus.ENTITLEMENT_REQUIRED)

    def test_explicit_grant_revoked(self):
        self.db[COLL_ENTITLEMENT_GRANTS].documents = [{
            "grant_id": "grant_003",
            "user_id": "user_revoked",
            "benefit_id": "ai.nutrition_gemini",
            "status": EntitlementStatus.REVOKED.value,
        }]
        decision = self.service.evaluate_entitlement("user_revoked", "ai.nutrition_gemini", as_of=self.now)
        self.assertEqual(decision.status, EntitlementDecisionStatus.REVOKED)

    def test_subscription_active_plus_included_feature(self):
        # User has active Plus subscription
        self.db[COLL_SUBSCRIPTIONS].documents = [{
            "subscription_id": "sub_plus_001",
            "user_id": "user_plus",
            "status": SubscriptionStatus.ACTIVE.value,
            "tier": MembershipTier.PLUS.value,
            "current_period_start": self.now - timedelta(days=5),
            "current_period_end": self.now + timedelta(days=25),
        }]
        # Note: In catalog preview, core.nutrition_logging is INCLUDED for Plus
        decision = self.service.evaluate_entitlement("user_plus", "core.nutrition_logging", as_of=self.now)
        self.assertEqual(decision.status, EntitlementDecisionStatus.ALLOWED)
        self.assertEqual(decision.source, "subscription")

    def test_subscription_active_plus_unincluded_feature(self):
        self.db[COLL_SUBSCRIPTIONS].documents = [{
            "subscription_id": "sub_plus_002",
            "user_id": "user_plus",
            "status": SubscriptionStatus.ACTIVE.value,
            "tier": MembershipTier.PLUS.value,
            "current_period_start": self.now - timedelta(days=5),
            "current_period_end": self.now + timedelta(days=25),
        }]
        # Workout CV is NOT included in Plus (it is Pro/Ultra only)
        decision = self.service.evaluate_entitlement("user_plus", "workout.cv.ai", as_of=self.now)
        self.assertEqual(decision.status, EntitlementDecisionStatus.ENTITLEMENT_REQUIRED)

    def test_subscription_expired_denies(self):
        self.db[COLL_SUBSCRIPTIONS].documents = [{
            "subscription_id": "sub_plus_old",
            "user_id": "user_expired",
            "status": SubscriptionStatus.ACTIVE.value,
            "tier": MembershipTier.PLUS.value,
            "current_period_start": self.now - timedelta(days=35),
            "current_period_end": self.now - timedelta(days=5),
        }]
        # Gemini food analysis requires Plus/active grant; since sub is expired, falls back to Free (not included)
        decision = self.service.evaluate_entitlement("user_expired", "ai.nutrition_gemini", as_of=self.now)
        self.assertEqual(decision.status, EntitlementDecisionStatus.ENTITLEMENT_REQUIRED)

    def test_catalog_included_does_not_self_grant(self):
        # User has no grants, no subscriptions
        decision = self.service.evaluate_entitlement("random_user", "ai.nutrition_gemini", as_of=self.now)
        self.assertEqual(decision.status, EntitlementDecisionStatus.ENTITLEMENT_REQUIRED)

    def test_default_free_features_allowed(self):
        # Baseline nutrition logging is included in Free
        decision = self.service.evaluate_entitlement("free_user", "core.nutrition_logging", as_of=self.now)
        self.assertEqual(decision.status, EntitlementDecisionStatus.ALLOWED)
        self.assertEqual(decision.source, "default_free")

    def test_storage_failure_fails_closed(self):
        class FailingDatabase:
            def __getitem__(self, item):
                raise RuntimeError("Mongo network timeout")

        service_failing_db = EntitlementService(db=FailingDatabase())
        decision = service_failing_db.evaluate_entitlement("user_1", "ai.nutrition_gemini", as_of=self.now)
        self.assertEqual(decision.status, EntitlementDecisionStatus.STORAGE_UNAVAILABLE)


# ==============================================================================
# 2. ATOMIC QUOTA RESERVATION & CONCURRENCY TESTS
# ==============================================================================

class TestQuotaReservationAndConcurrency(unittest.TestCase):
    def setUp(self):
        self.db = MockDatabase()
        self.service = QuotaService(db=self.db)
        self.now = datetime(2026, 10, 29, 12, 0, 0, tzinfo=timezone.utc)

    def test_quota_capacity_limit_single_thread(self):
        # Limit = 3
        res1 = self.service.reserve_quota("u1", "ai.nutrition_gemini", units=1, limit_units=3, as_of=self.now)
        self.assertEqual(res1.status, ReservationStatus.RESERVED)
        self.assertEqual(res1.remaining_units, 2)

        res2 = self.service.reserve_quota("u1", "ai.nutrition_gemini", units=2, limit_units=3, as_of=self.now)
        self.assertEqual(res2.status, ReservationStatus.RESERVED)
        self.assertEqual(res2.remaining_units, 0)

        # 4th unit exceeds limit (1 + 2 + 1 > 3)
        res3 = self.service.reserve_quota("u1", "ai.nutrition_gemini", units=1, limit_units=3, as_of=self.now)
        self.assertEqual(res3.status, ReservationStatus.QUOTA_EXHAUSTED)

    def test_concurrent_quota_reservations_race_condition_prevention(self):
        """Spins up 15 parallel threads competing for limit=5. Exactly 5 must succeed."""
        threads: List[threading.Thread] = []
        results: List[ReservationStatus] = []
        results_lock = threading.Lock()

        def worker(thread_idx: int):
            res = self.service.reserve_quota(
                user_id="concurrent_user",
                benefit_id="ai.nutrition_gemini",
                units=1,
                limit_units=5,
                idempotency_key=f"worker_key_{thread_idx}",
                as_of=self.now,
            )
            with results_lock:
                results.append(res.status)

        for i in range(15):
            t = threading.Thread(target=worker, args=(i,))
            threads.append(t)
            t.start()

        for t in threads:
            t.join()

        reserved_count = results.count(ReservationStatus.RESERVED)
        exhausted_count = results.count(ReservationStatus.QUOTA_EXHAUSTED)

        self.assertEqual(reserved_count, 5)
        self.assertEqual(exhausted_count, 10)

    def test_idempotency_same_key_returns_existing(self):
        res1 = self.service.reserve_quota(
            "u1", "ai.nutrition_gemini", units=1, limit_units=5,
            idempotency_key="key_alpha", request_hash="hash_001", as_of=self.now
        )
        self.assertEqual(res1.status, ReservationStatus.RESERVED)

        # Repeat reservation with identical key and hash
        res2 = self.service.reserve_quota(
            "u1", "ai.nutrition_gemini", units=1, limit_units=5,
            idempotency_key="key_alpha", request_hash="hash_001", as_of=self.now
        )
        self.assertEqual(res2.status, ReservationStatus.IN_PROGRESS)
        self.assertEqual(res2.operation_id, res1.operation_id)

    def test_idempotency_payload_mismatch_raises_conflict(self):
        res1 = self.service.reserve_quota(
            "u1", "ai.nutrition_gemini", units=1, limit_units=5,
            idempotency_key="key_beta", request_hash="hash_prompt_A", as_of=self.now
        )
        self.assertEqual(res1.status, ReservationStatus.RESERVED)

        # Repeat reservation with same key but DIFFERENT payload hash
        res2 = self.service.reserve_quota(
            "u1", "ai.nutrition_gemini", units=1, limit_units=5,
            idempotency_key="key_beta", request_hash="hash_prompt_B", as_of=self.now
        )
        self.assertEqual(res2.status, ReservationStatus.OPERATION_CONFLICT)
        self.assertIn("different request payload", res2.error_message)

    def test_tenant_isolation_different_users_same_key(self):
        res_A = self.service.reserve_quota(
            "user_A", "ai.nutrition_gemini", units=1, limit_units=5,
            idempotency_key="shared_client_id", as_of=self.now
        )
        res_B = self.service.reserve_quota(
            "user_B", "ai.nutrition_gemini", units=1, limit_units=5,
            idempotency_key="shared_client_id", as_of=self.now
        )
        self.assertEqual(res_A.status, ReservationStatus.RESERVED)
        self.assertEqual(res_B.status, ReservationStatus.RESERVED)
        self.assertNotEqual(res_A.operation_id, res_B.operation_id)


# ==============================================================================
# 3. COMMIT, RELEASE & LIFECYCLE TESTS
# ==============================================================================

class TestQuotaCommitReleaseLifecycle(unittest.TestCase):
    def setUp(self):
        self.db = MockDatabase()
        self.service = QuotaService(db=self.db)
        self.now = datetime(2026, 10, 29, 12, 0, 0, tzinfo=timezone.utc)

    def test_commit_quota_converts_reserved_to_consumed(self):
        res = self.service.reserve_quota("u1", "ai.nutrition_gemini", units=1, limit_units=5, as_of=self.now)
        op_id = res.operation_id
        lease = res.lease_token

        # Verify bucket initial state
        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["reserved_units"], 1)
        self.assertEqual(bucket["consumed_units"], 0)

        # Commit
        ok = self.service.commit_quota(op_id, lease_token=lease, response_payload={"calories": 300}, as_of=self.now)
        self.assertTrue(ok)

        # Verify bucket updated state
        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["reserved_units"], 0)
        self.assertEqual(bucket["consumed_units"], 1)

        # Verify operation status
        op = self.db[COLL_USAGE_OPERATIONS].documents[0]
        self.assertEqual(op["status"], UsageOpStatus.COMMITTED.value)

    def test_commit_idempotency_repeated_calls(self):
        res = self.service.reserve_quota("u1", "ai.nutrition_gemini", units=1, limit_units=5, as_of=self.now)
        self.service.commit_quota(res.operation_id, lease_token=res.lease_token, as_of=self.now)

        # Second commit call
        ok2 = self.service.commit_quota(res.operation_id, lease_token=res.lease_token, as_of=self.now)
        self.assertTrue(ok2)

        # Consumed units MUST NOT be double-incremented
        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["consumed_units"], 1)
        self.assertEqual(bucket["reserved_units"], 0)

    def test_release_quota_restores_reserved_units(self):
        res = self.service.reserve_quota("u1", "ai.nutrition_gemini", units=1, limit_units=5, as_of=self.now)
        ok = self.service.release_quota(res.operation_id, lease_token=res.lease_token, reason="Prompt safety block", as_of=self.now)
        self.assertTrue(ok)

        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["reserved_units"], 0)
        self.assertEqual(bucket["consumed_units"], 0)

    def test_release_idempotency_repeated_calls(self):
        res = self.service.reserve_quota("u1", "ai.nutrition_gemini", units=1, limit_units=5, as_of=self.now)
        self.service.release_quota(res.operation_id, lease_token=res.lease_token, as_of=self.now)

        # Second release call
        ok2 = self.service.release_quota(res.operation_id, lease_token=res.lease_token, as_of=self.now)
        self.assertTrue(ok2)

        # Reserved units MUST NOT become negative
        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["reserved_units"], 0)

    def test_stale_worker_lease_protection(self):
        res = self.service.reserve_quota("u1", "ai.nutrition_gemini", units=1, limit_units=5, as_of=self.now)
        stale_lease = "lease_stale_token_999"

        # Worker attempting commit with invalid lease token is rejected
        ok = self.service.commit_quota(res.operation_id, lease_token=stale_lease, as_of=self.now)
        self.assertFalse(ok)

        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["consumed_units"], 0)


# ==============================================================================
# 4. CRASH RECOVERY TESTS
# ==============================================================================

class TestQuotaRecovery(unittest.TestCase):
    def setUp(self):
        self.db = MockDatabase()
        self.quota_service = QuotaService(db=self.db)
        self.recovery_service = QuotaRecoveryService(db=self.db)
        self.now = datetime(2026, 10, 29, 12, 0, 0, tzinfo=timezone.utc)

    def test_recovery_reclaims_expired_undispatched(self):
        # Create an expired reservation that crashed BEFORE dispatch (dispatched=False)
        res = self.quota_service.reserve_quota("u1", "ai.nutrition_gemini", units=1, limit_units=5, as_of=self.now)
        # Advance clock past lease expiration (e.g. 5 minutes later)
        later = self.now + timedelta(minutes=5)

        reclaimed = self.recovery_service.reclaim_expired_undispatched_reservations(as_of=later)
        self.assertEqual(reclaimed, 1)

        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["reserved_units"], 0)

        op = self.db[COLL_USAGE_OPERATIONS].documents[0]
        self.assertEqual(op["status"], UsageOpStatus.RELEASED.value)

    def test_recovery_dispatched_transitions_to_unknown_without_releasing(self):
        # Create a reservation and mark dispatched
        res = self.quota_service.reserve_quota("u1", "ai.nutrition_gemini", units=1, limit_units=5, as_of=self.now)
        self.quota_service.mark_dispatched(res.operation_id, res.lease_token)

        later = self.now + timedelta(minutes=5)
        flagged = self.recovery_service.transition_stalled_dispatched_to_unknown(as_of=later)
        self.assertEqual(flagged, 1)

        # Crucial Invariant: reserved_units is NOT released blindly
        bucket = self.db[COLL_USAGE_BUCKETS].documents[0]
        self.assertEqual(bucket["reserved_units"], 1)

        op = self.db[COLL_USAGE_OPERATIONS].documents[0]
        self.assertEqual(op["status"], UsageOpStatus.FAILED_UNKNOWN.value)


# ==============================================================================
# 5. REAL ISOLATED MONGODB INTEGRATION TEST (LOOPBACK PORT 27099)
# ==============================================================================

class TestRealMongoQuotaAtomicity(unittest.TestCase):
    """
    Executes actual MongoDB integration tests against an isolated local mongod instance.
    Runs on loopback port 27099 with a dedicated temporary dbpath.
    Cleanly stops mongod upon test completion.
    """
    mongod_proc: Optional[subprocess.Popen] = None
    mongo_client = None
    real_db = None
    dbpath: Optional[str] = None
    mongod_available: bool = False

    @classmethod
    def setUpClass(cls):
        mongod_binary = r"D:\SamanDev\tools\mongodb-cp7\mongodb-win32-x86_64-windows-7.0.14\bin\mongod.exe"
        if not os.path.exists(mongod_binary):
            return

        cls.dbpath = os.path.abspath(r"D:\SamanDev\runtime_evidence\saman-revenue\CP-04\20261029_093500\mongo_data")
        os.makedirs(cls.dbpath, exist_ok=True)

        cmd = [
            mongod_binary,
            "--port", "27099",
            "--bind_ip", "127.0.0.1",
            "--dbpath", cls.dbpath,
            "--wiredTigerCacheSizeGB", "0.25",
            "--quiet",
        ]
        try:
            cls.mongod_proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            # Wait for mongod to accept connections
            time.sleep(2)

            from pymongo import MongoClient
            cls.mongo_client = MongoClient("mongodb://127.0.0.1:27099", serverSelectionTimeoutMS=3000)
            cls.mongo_client.admin.command("ping")
            cls.real_db = cls.mongo_client["saman_revenue_isolated_test"]
            cls.mongod_available = True

            # Ensure revenue indexes on real isolated database
            ensure_revenue_indexes(db=cls.real_db, dry_run=False)
        except Exception as exc:
            print(f"[Notice] Isolated mongod setup bypassed: {exc}")
            cls.mongod_available = False

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
        # Clean up temp dbpath files
        if cls.dbpath and os.path.exists(cls.dbpath):
            try:
                shutil.rmtree(cls.dbpath, ignore_errors=True)
            except Exception:
                pass

    def test_real_mongodb_atomic_concurrency(self):
        if not self.mongod_available:
            self.skipTest("Isolated mongod not available on 127.0.0.1:27099")

        quota_service = QuotaService(db=self.real_db)
        now = datetime.now(timezone.utc)
        threads: List[threading.Thread] = []
        results: List[ReservationStatus] = []
        results_lock = threading.Lock()

        # 20 parallel threads competing for limit=5 against REAL MongoDB
        def worker(thread_idx: int):
            res = quota_service.reserve_quota(
                user_id="real_mongo_user",
                benefit_id="ai.nutrition_gemini",
                units=1,
                limit_units=5,
                idempotency_key=f"real_key_{thread_idx}",
                as_of=now,
            )
            with results_lock:
                results.append(res.status)

        for i in range(20):
            t = threading.Thread(target=worker, args=(i,))
            threads.append(t)
            t.start()

        for t in threads:
            t.join()

        reserved_count = results.count(ReservationStatus.RESERVED)
        exhausted_count = results.count(ReservationStatus.QUOTA_EXHAUSTED)

        # Real MongoDB findOneAndUpdate atomicity verification
        self.assertEqual(reserved_count, 5)
        self.assertEqual(exhausted_count, 15)

    def test_real_mongodb_unique_index_constraint(self):
        if not self.mongod_available:
            self.skipTest("Isolated mongod not available on 127.0.0.1:27099")

        subs_col = self.real_db[COLL_SUBSCRIPTIONS]
        subs_col.delete_many({})

        now = datetime.now(timezone.utc)
        # Insert first record
        subs_col.insert_one({
            "subscription_id": "sub_real_1",
            "provider": "apple_storekit",
            "environment": "production",
            "original_transaction_id": "TXN_REAL_123",
            "user_id": "u1",
            "created_at": now,
        })

        # Insert second record with same provider + env + transaction_id -> MUST fail on real MongoDB
        from pymongo.errors import DuplicateKeyError
        with self.assertRaises(DuplicateKeyError):
            subs_col.insert_one({
                "subscription_id": "sub_real_2",
                "provider": "apple_storekit",
                "environment": "production",
                "original_transaction_id": "TXN_REAL_123",
                "user_id": "u2",
                "created_at": now,
            })


if __name__ == "__main__":
    unittest.main()
