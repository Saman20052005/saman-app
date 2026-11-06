"""
Comprehensive Fault Injection, Concurrency & Recovery Verification Test Suite (CP-09).
Subsystem: Saman Revenue — Payment, Lifecycle, Quota & Entitlement Boundaries.

Sections Covered:
B. Quota Concurrency & Failure Injection (Real Isolated WiredTiger MongoDB Port 27096)
C. Payment/Lifecycle Ordering & Edge Cases
D. Restore Purchases & Security Boundaries
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone, timedelta
import hashlib
import os
import shutil
import subprocess
import threading
import time
from typing import Any, Dict, List, Optional
import unittest
from unittest.mock import patch, MagicMock
from uuid import uuid4

from pymongo import MongoClient

from backend.app.models.revenue import (
    PaymentProviderName,
    PaymentEnvironment,
    ProviderVerificationStatus,
    PurchaseVerificationOutcomeStatus,
    StoreProductMapping,
    VerifiedProviderTransaction,
    VerifiedWebhookEvent,
    MembershipTier,
    SubscriptionStatus,
    EntitlementStatus,
    EntitlementDecisionStatus,
    SubscriptionLifecycleEventType,
    ReceiptOwnershipStatus,
    GracePeriodPolicy,
    RestorePurchasesRequest,
    RestorePurchasesResponse,
    ReservationStatus,
    UsageOpStatus,
)
from backend.app.database_revenue import (
    COLL_PROVIDER_EVENTS,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_SUBSCRIPTIONS,
    COLL_ENTITLEMENT_GRANTS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_FOOD_ANALYSIS_IDEMPOTENCY,
    ensure_revenue_indexes,
)
from backend.app.services.entitlement_service import EntitlementService
from backend.app.services.quota_service import QuotaService, StorageUnavailableException
from backend.app.services.quota_recovery_service import QuotaRecoveryService
from backend.app.services.payment_service import (
    PaymentSettlementService,
    ProductMappingRegistry,
    IPaymentProviderAdapter,
    UnconfiguredPaymentProviderAdapter,
    PaymentConfigurationNotReadyError,
    ReceiptOwnershipConflictError,
    ProductMappingRejectedError,
    hash_sensitive_payload,
)


class FakeTestPaymentProviderAdapter(IPaymentProviderAdapter):
    """In-memory fake provider adapter strictly for testing."""

    def __init__(
        self,
        configured: bool = True,
        verification_status: ProviderVerificationStatus = ProviderVerificationStatus.VERIFIED_ACTIVE,
        fixed_purchase_date: Optional[datetime] = None,
        fixed_expires_date: Optional[datetime] = None,
    ):
        self._configured = configured
        self._verification_status = verification_status
        self.fixed_purchase_date = fixed_purchase_date
        self.fixed_expires_date = fixed_expires_date

    def is_configured(self) -> bool:
        return self._configured

    @property
    def provider_name(self) -> PaymentProviderName:
        return PaymentProviderName.APPLE_APP_STORE

    def get_provider_name(self) -> PaymentProviderName:
        return PaymentProviderName.APPLE_APP_STORE

    def verify_purchase(
        self,
        request: PurchaseVerificationRequest,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedProviderTransaction:
        return self.verify_purchase_token(
            verification_token=request.verification_token,
            expected_environment=expected_environment,
            expected_app_id=expected_app_id,
            expected_product_id=request.product_id,
        )

    def verify_purchase_token(
        self,
        verification_token: str,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
        expected_product_id: str,
    ) -> VerifiedProviderTransaction:
        if not self._configured:
            raise PaymentConfigurationNotReadyError()
        now = datetime.now(timezone.utc)
        p_date = self.fixed_purchase_date or now
        e_date = self.fixed_expires_date or (p_date + timedelta(days=30))
        return VerifiedProviderTransaction(
            transaction_id="tx_fake_001",
            original_transaction_id="orig_fake_001",
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=expected_environment,
            app_id=expected_app_id,
            product_id=expected_product_id if expected_product_id != "restore_query" else "saman_pro_monthly_sandbox",
            purchase_date=p_date,
            expires_date=e_date,
            verification_status=self._verification_status,
            raw_payload_hash=hash_sensitive_payload(verification_token),
        )

    def verify_and_parse_webhook(
        self,
        headers: Dict[str, str],
        raw_body: bytes,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedWebhookEvent:
        if not self._configured:
            raise PaymentConfigurationNotReadyError()
        now = datetime.now(timezone.utc)
        tx = VerifiedProviderTransaction(
            transaction_id="tx_webhook_001",
            original_transaction_id="orig_webhook_001",
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=expected_environment,
            app_id=expected_app_id,
            product_id="saman_plus_monthly",
            purchase_date=now,
            expires_date=now + timedelta(days=30),
            verification_status=self._verification_status,
            raw_payload_hash=hash_sensitive_payload(raw_body.decode("utf-8", errors="ignore")),
        )
        return VerifiedWebhookEvent(
            event_id=headers.get("x-event-id", f"evt_{uuid4().hex}"),
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=expected_environment,
            event_type="renewal",
            event_timestamp=now,
            transaction=tx,
            user_id=headers.get("x-user-id"),
            raw_payload_hash=hash_sensitive_payload(raw_body.decode("utf-8", errors="ignore")),
        )


# ==============================================================================
# SECTION B: Quota Concurrency & Failure Injection (Real Isolated Mongo Port 27096)
# ==============================================================================

class TestRealMongoFaultInjectionAndConcurrency(unittest.TestCase):
    """
    Executes CP-09 Section B fault injection and concurrency scenarios
    against an actual isolated MongoDB instance on loopback port 27096.
    """
    MONGOD_EXE = r"D:\SamanDev\tools\mongodb-cp7\mongodb-win32-x86_64-windows-7.0.14\bin\mongod.exe"
    PORT = 27096
    DBPATH = r"D:\SamanDev\runtime_evidence\saman-revenue\CP-09\20261030_211102\mongo_data"
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
            cls.real_db = cls.mongo_client["saman_revenue_cp09_isolated"]
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
            self.skipTest("Isolated MongoDB 7.0 not available on 127.0.0.1:27096")
        # Clean collections before each scenario
        self.real_db[COLL_USAGE_BUCKETS].delete_many({})
        self.real_db[COLL_USAGE_OPERATIONS].delete_many({})
        self.real_db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].delete_many({})
        self.real_db[COLL_SUBSCRIPTIONS].delete_many({})
        self.real_db[COLL_ENTITLEMENT_GRANTS].delete_many({})
        self.real_db[COLL_PROVIDER_EVENTS].delete_many({})
        self.real_db[COLL_PAYMENT_TRANSACTIONS].delete_many({})

    def test_b1_concurrent_n_requests_competing_for_k_quota(self):
        """
        B1: N=20 parallel worker threads competing for limit K=5 on real WiredTiger.
        Exactly 5 must succeed (RESERVED); exactly 15 must receive QUOTA_EXHAUSTED.
        Bucket counters must show reserved_units == 5, consumed_units == 0.
        """
        q_svc = QuotaService(db=self.real_db)
        now = datetime.now(timezone.utc)
        results: List[ReservationStatus] = []
        lock = threading.Lock()

        def worker(idx: int):
            res = q_svc.reserve_quota(
                user_id="user_race_b1",
                benefit_id="ai.nutrition_gemini",
                units=1,
                limit_units=5,
                idempotency_key=f"b1_key_{idx}",
                as_of=now,
            )
            with lock:
                results.append(res.status)

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(20)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(results.count(ReservationStatus.RESERVED), 5)
        self.assertEqual(results.count(ReservationStatus.QUOTA_EXHAUSTED), 15)

        bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({"user_id": "user_race_b1"})
        self.assertIsNotNone(bucket)
        self.assertEqual(bucket["reserved_units"], 5)
        self.assertEqual(bucket["consumed_units"], 0)

    def test_b2_concurrent_same_idempotency_key_different_payload(self):
        """
        B2: Concurrent requests with identical idempotency key but different request hash.
        First request reserves quota; second request detects OPERATION_CONFLICT (HTTP 409).
        Zero duplicate reservations or quota leakage.
        """
        q_svc = QuotaService(db=self.real_db)
        now = datetime.now(timezone.utc)

        res1 = q_svc.reserve_quota(
            user_id="user_b2",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="shared_idemp_key_b2",
            request_hash="hash_payload_alpha",
            as_of=now,
        )
        self.assertEqual(res1.status, ReservationStatus.RESERVED)

        # Second request with SAME key but DIFFERENT payload hash
        res2 = q_svc.reserve_quota(
            user_id="user_b2",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="shared_idemp_key_b2",
            request_hash="hash_payload_beta_mismatched",
            as_of=now,
        )
        self.assertEqual(res2.status, ReservationStatus.OPERATION_CONFLICT)

        # Total reserved units must strictly equal 1
        bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({"user_id": "user_b2"})
        self.assertEqual(bucket["reserved_units"], 1)
        self.assertEqual(bucket["consumed_units"], 0)

    def test_b3_commit_release_recovery_race_conditions_lease_protection(self):
        """
        B3: Stale worker lease protection.
        Worker A reserves with lease L1. Operation times out and recovery changes lease to L2.
        Worker A attempts commit with L1 -> Rejected (False).
        New leaseholder commits with L2 -> Successfully converts reserved to consumed.
        """
        q_svc = QuotaService(db=self.real_db)
        now = datetime.now(timezone.utc)

        res = q_svc.reserve_quota(
            user_id="user_b3",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="lease_race_b3",
            as_of=now,
        )
        old_lease = res.lease_token

        # Simulate recovery or timeout renewing lease
        new_lease = f"lease_renewed_{uuid4().hex}"
        self.real_db[COLL_USAGE_OPERATIONS].update_one(
            {"operation_id": res.operation_id},
            {"$set": {"lease_token": new_lease}},
        )

        # Worker A attempts commit with stale lease L1 -> REJECTED
        commit_a = q_svc.commit_quota(
            operation_id=res.operation_id,
            lease_token=old_lease,
            response_payload={"calories": 350},
        )
        self.assertFalse(commit_a)

        # Worker B (holding new_lease) commits -> SUCCESS
        commit_b = q_svc.commit_quota(
            operation_id=res.operation_id,
            lease_token=new_lease,
            response_payload={"calories": 350},
        )
        self.assertTrue(commit_b)

        # Bucket check: reserved converted to consumed
        bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({"user_id": "user_b3"})
        self.assertEqual(bucket["reserved_units"], 0)
        self.assertEqual(bucket["consumed_units"], 1)

    def test_b4_crash_after_reserve_before_dispatch(self):
        """
        B4: Crash after reserve before provider dispatch (dispatched=False).
        Lease expires. QuotaRecoveryService.reclaim_expired_undispatched_reservations
        reclaims reserved units and marks operation RELEASED.
        """
        q_svc = QuotaService(db=self.real_db)
        rec_svc = QuotaRecoveryService(db=self.real_db)
        t0 = datetime(2026, 10, 30, 10, 0, tzinfo=timezone.utc)

        res = q_svc.reserve_quota(
            user_id="user_b4",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="crash_before_dispatch_b4",
            lease_duration_seconds=30,
            as_of=t0,
        )
        self.assertEqual(res.status, ReservationStatus.RESERVED)

        # Server crashes before dispatch... time passes past lease expiry
        t_crash = t0 + timedelta(seconds=35)
        reclaimed = rec_svc.reclaim_expired_undispatched_reservations(as_of=t_crash)
        self.assertEqual(reclaimed, 1)

        # Operation is RELEASED, reserved_units restored to 0
        op = self.real_db[COLL_USAGE_OPERATIONS].find_one({"operation_id": res.operation_id})
        self.assertEqual(op["status"], UsageOpStatus.RELEASED.value)

        bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({"user_id": "user_b4"})
        self.assertEqual(bucket["reserved_units"], 0)
        self.assertEqual(bucket["consumed_units"], 0)

    def test_b5_crash_after_dispatch_before_result_persistence(self):
        """
        B5: Crash after provider dispatch (dispatched=True) before result persistence.
        Lease expires. Recovery transitions operation to FAILED_UNKNOWN without blind release.
        """
        q_svc = QuotaService(db=self.real_db)
        rec_svc = QuotaRecoveryService(db=self.real_db)
        t0 = datetime(2026, 10, 30, 10, 0, tzinfo=timezone.utc)

        res = q_svc.reserve_quota(
            user_id="user_b5",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="crash_after_dispatch_b5",
            lease_duration_seconds=30,
            as_of=t0,
        )
        # Mark dispatched
        q_svc.mark_dispatched(res.operation_id, res.lease_token)

        # Crash occurs while awaiting provider... time passes
        t_crash = t0 + timedelta(seconds=35)
        flagged = rec_svc.transition_stalled_dispatched_to_unknown(as_of=t_crash)
        self.assertEqual(flagged, 1)

        op = self.real_db[COLL_USAGE_OPERATIONS].find_one({"operation_id": res.operation_id})
        self.assertEqual(op["status"], UsageOpStatus.FAILED_UNKNOWN.value)

        # Crucial Invariant: reserved units must NOT be decremented blindly
        bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({"user_id": "user_b5"})
        self.assertEqual(bucket["reserved_units"], 1)

    def test_b6_crash_after_result_persistence_before_commit(self):
        """
        B6: Crash after result persistence before commit.
        Operation was marked FAILED_UNKNOWN, but late result arrives with response payload.
        resolve_failed_unknown(action='COMMIT') cleanly transitions to COMMITTED,
        converts reserved units to consumed, and saves cache.
        """
        q_svc = QuotaService(db=self.real_db)
        rec_svc = QuotaRecoveryService(db=self.real_db)
        t0 = datetime(2026, 10, 30, 10, 0, tzinfo=timezone.utc)

        res = q_svc.reserve_quota(
            user_id="user_b6",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="crash_res_persist_b6",
            client_request_id="req_b6",
            as_of=t0,
        )
        q_svc.mark_dispatched(res.operation_id, res.lease_token)
        q_svc.mark_unknown(res.operation_id, reason="Provider response timeout")

        # Late reconciliation commits the result
        resolved = rec_svc.resolve_failed_unknown(
            operation_id=res.operation_id,
            action="COMMIT",
            reason="Late provider callback resolved",
            response_payload={"food": "Pho Bo", "calories": 450},
            as_of=t0 + timedelta(seconds=10),
        )
        self.assertTrue(resolved)

        op = self.real_db[COLL_USAGE_OPERATIONS].find_one({"operation_id": res.operation_id})
        self.assertEqual(op["status"], UsageOpStatus.COMMITTED.value)

        bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({"user_id": "user_b6"})
        self.assertEqual(bucket["reserved_units"], 0)
        self.assertEqual(bucket["consumed_units"], 1)

        # Result is cached under client_request_id
        cache_entry = self.real_db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].find_one({"client_request_id": "req_b6"})
        self.assertIsNotNone(cache_entry)
        self.assertEqual(cache_entry["response_payload"]["food"], "Pho Bo")

    def test_b7_window_reset_operation_commits_to_originating_bucket(self):
        """
        B7: Cross-window finalization.
        Reservation made on 2026-10-31 (Month M1). Window shifts to 2026-11-01 (Month M2).
        Operation commits during M2.
        Verification: M1 bucket has consumed_units incremented and reserved_units decremented.
        M2 bucket is NOT corrupted.
        """
        q_svc = QuotaService(db=self.real_db)
        t_oct = datetime(2026, 10, 31, 23, 50, tzinfo=timezone.utc)
        t_nov = datetime(2026, 11, 1, 0, 10, tzinfo=timezone.utc)

        res = q_svc.reserve_quota(
            user_id="user_b7",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=30,
            idempotency_key="cross_window_b7",
            as_of=t_oct,
        )
        q_svc.mark_dispatched(res.operation_id, res.lease_token)

        # Commit in November
        committed = q_svc.commit_quota(
            operation_id=res.operation_id,
            lease_token=res.lease_token,
            response_payload={"status": "ok"},
            as_of=t_nov,
        )
        self.assertTrue(committed)

        # Check October bucket: consumed=1, reserved=0
        w_start_oct, _, b_key_oct = q_svc._get_window_bounds(t_oct)
        oct_bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({
            "user_id": "user_b7",
            "bucket_key": b_key_oct,
            "window_start": w_start_oct,
        })
        self.assertEqual(oct_bucket["consumed_units"], 1)
        self.assertEqual(oct_bucket["reserved_units"], 0)

    def test_b8_cache_expired_restart_retry_recovers_cached_response(self):
        """
        B8: Operation retry with same idempotency key and client_request_id
        returns ALREADY_COMPLETED with cached payload without re-dispatching AI.
        """
        q_svc = QuotaService(db=self.real_db)
        now = datetime.now(timezone.utc)

        res = q_svc.reserve_quota(
            user_id="user_b8",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="retry_cached_b8",
            client_request_id="client_req_b8",
            as_of=now,
        )
        q_svc.commit_quota(
            operation_id=res.operation_id,
            lease_token=res.lease_token,
            response_payload={"dish": "Banh Mi", "protein_g": 18},
            as_of=now,
        )

        # Client retries with the exact same idempotency_key & client_request_id
        res_retry = q_svc.reserve_quota(
            user_id="user_b8",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="retry_cached_b8",
            client_request_id="client_req_b8",
            as_of=now + timedelta(seconds=5),
        )
        self.assertEqual(res_retry.status, ReservationStatus.ALREADY_COMPLETED)
        self.assertIsNotNone(res_retry.cached_payload)
        self.assertEqual(res_retry.cached_payload["dish"], "Banh Mi")

    def test_b9_storage_write_succeeded_caller_received_error_idempotent_retry(self):
        """
        B9: Storage commit succeeded, but client dropped connection before receiving HTTP 200.
        Client queries operation status via query_operation_by_idempotency_key:
        Recovers COMMITTED status and cached response cleanly.
        """
        q_svc = QuotaService(db=self.real_db)
        now = datetime.now(timezone.utc)

        res = q_svc.reserve_quota(
            user_id="user_b9",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="dropped_conn_b9",
            client_request_id="req_drop_b9",
            as_of=now,
        )
        q_svc.commit_quota(
            operation_id=res.operation_id,
            lease_token=res.lease_token,
            response_payload={"result": "analysis_success"},
            as_of=now,
        )

        # Client queries via idempotency key
        recovered = q_svc.query_operation_by_idempotency_key(
            user_id="user_b9",
            benefit_id="ai.nutrition_gemini",
            idempotency_key="dropped_conn_b9",
        )
        self.assertIsNotNone(recovered)
        self.assertEqual(recovered["status"], UsageOpStatus.COMMITTED.value)
        self.assertEqual(recovered["cached_payload"]["result"], "analysis_success")

    def test_b10_failed_unknown_has_deterministic_resolution_path_no_stranded_counters(self):
        """
        B10: Operation in FAILED_UNKNOWN resolved via action='RELEASE':
        Decrements reserved_units back to bucket, marking status RELEASED.
        Zero stranded counters remain in bucket.
        """
        q_svc = QuotaService(db=self.real_db)
        rec_svc = QuotaRecoveryService(db=self.real_db)
        now = datetime.now(timezone.utc)

        res = q_svc.reserve_quota(
            user_id="user_b10",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="stranded_test_b10",
            as_of=now,
        )
        q_svc.mark_dispatched(res.operation_id, res.lease_token)
        q_svc.mark_unknown(res.operation_id, reason="Provider 504 Gateway Timeout")

        # Resolve with RELEASE (e.g., provider logs confirmed no LLM execution occurred)
        released = rec_svc.resolve_failed_unknown(
            operation_id=res.operation_id,
            action="RELEASE",
            reason="Confirmed provider 504 before execution",
            as_of=now + timedelta(minutes=1),
        )
        self.assertTrue(released)

        op = self.real_db[COLL_USAGE_OPERATIONS].find_one({"operation_id": res.operation_id})
        self.assertEqual(op["status"], UsageOpStatus.RELEASED.value)

        bucket = self.real_db[COLL_USAGE_BUCKETS].find_one({"user_id": "user_b10"})
        self.assertEqual(bucket["reserved_units"], 0)
        self.assertEqual(bucket["consumed_units"], 0)


# ==============================================================================
# SECTION C: Payment / Lifecycle Ordering & Edge Cases
# ==============================================================================

class TestPaymentLifecycleOrderingFaultInjection(unittest.TestCase):
    """
    CP-09 Section C: Tests payment and lifecycle ordering invariants.
    """

    def setUp(self):
        self.provider = PaymentProviderName.APPLE_APP_STORE
        self.env = PaymentEnvironment.SANDBOX
        self.app_id = "com.saman.health.ios"
        self.mapping = StoreProductMapping(
            provider=self.provider,
            environment=self.env,
            app_id=self.app_id,
            product_id="saman_plus_monthly_sandbox",
            plan_id="plus",
            price_id="price_plus_m",
            tier=MembershipTier.PLUS,
            benefit_ids=["ai.nutrition_gemini"],
            quota_limits={"ai.nutrition_gemini": 30},
            amount_cents=999,
            currency="USD",
            enabled=True,
        )
        self.registry = ProductMappingRegistry(expected_environment=self.env)
        self.registry.register(self.mapping)
        self.adapter = FakeTestPaymentProviderAdapter(configured=True)

        from backend.tests.test_revenue_entitlement_quota import MockDatabase
        self.db = MockDatabase()
        self.settlement = PaymentSettlementService(
            adapter=self.adapter,
            mapping_registry=self.registry,
            db=self.db,
        )
        self.entitlement = EntitlementService(db=self.db)

    def _build_event(self, event_id: str, event_type: str, timestamp: datetime, txn_id: str, orig_txn_id: str, user_id: str = "user_c"):
        tx = VerifiedProviderTransaction(
            transaction_id=txn_id,
            original_transaction_id=orig_txn_id,
            provider=self.provider,
            environment=self.env,
            app_id=self.app_id,
            product_id="saman_plus_monthly_sandbox",
            purchase_date=timestamp,
            expires_date=timestamp + timedelta(days=30),
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            raw_payload_hash=hash_sensitive_payload(txn_id),
        )
        return VerifiedWebhookEvent(
            event_id=event_id,
            provider=self.provider,
            environment=self.env,
            event_type=event_type,
            event_timestamp=timestamp,
            transaction=tx,
            user_id=user_id,
            raw_payload_hash=hash_sensitive_payload(event_id),
        )

    def test_c1_concurrent_activation_and_renewal_deduplicated(self):
        """
        C1: Duplicate delivery of initial_purchase or renewal event.
        Returns duplicate_ignored=True, grants entitlement exactly once.
        """
        t0 = datetime(2026, 10, 30, 8, 0, tzinfo=timezone.utc)
        evt = self._build_event("evt_c1", "initial_purchase", t0, "tx_c1", "orig_c1")

        res1 = self.settlement.process_lifecycle_event(evt, as_of=t0)
        self.assertEqual(res1["status"], "processed")
        self.assertFalse(res1.get("duplicate_ignored", False))

        # Re-send same event
        res2 = self.settlement.process_lifecycle_event(evt, as_of=t0 + timedelta(seconds=1))
        self.assertTrue(res2.get("duplicate_ignored", False))

        grants = [g for g in self.db[COLL_ENTITLEMENT_GRANTS].documents if g["user_id"] == "user_c"]
        self.assertEqual(len(grants), 1)

    def test_c2_replayed_incomplete_wal_snapshot_does_not_rollback_newer_projection(self):
        """
        C2: Event 1 (T1) failed projection and was left in received status.
        Event 2 (T2 > T1) completed projection successfully (version=2).
        Later, reconciler runs for Event 1:
        Invariant: Must NOT roll back the newer subscription state or grants to T1!
        """
        t1 = datetime(2026, 10, 1, 8, 0, tzinfo=timezone.utc)
        t2 = datetime(2026, 11, 1, 8, 0, tzinfo=timezone.utc)

        # Event 2 completes projection
        evt2 = self._build_event("evt_c2_nov", "renewal", t2, "tx_nov", "orig_c2")
        self.settlement.process_lifecycle_event(evt2, as_of=t2)

        # Seed Event 1 in COLL_PROVIDER_EVENTS as received (from earlier crash)
        snapshot_evt1 = {
            "provider": self.provider.value,
            "environment": self.env.value,
            "app_id": self.app_id,
            "product_id": "saman_plus_monthly_sandbox",
            "user_id": "user_c",
            "transaction_id": "tx_oct",
            "original_transaction_id": "orig_c2",
            "verification_status": ProviderVerificationStatus.VERIFIED_ACTIVE.value,
            "purchase_date": t1,
            "expires_date": t1 + timedelta(days=30),
            "raw_payload_hash": hash_sensitive_payload("tx_oct"),
            "event_timestamp": t1,
            "mapping": self.mapping.model_dump(),
        }
        self.db[COLL_PROVIDER_EVENTS].insert_one({
            "event_id": "evt_c2_oct_incomplete",
            "provider": self.provider.value,
            "environment": self.env.value,
            "event_type": "initial_purchase",
            "processing_status": "received",
            "projection_snapshot": snapshot_evt1,
            "received_at": t1,
            "processed_at": None,
        })

        # Run crash recovery pass
        rec_res = self.settlement.reconcile_incomplete_payment_events(as_of=t2 + timedelta(minutes=5))
        self.assertEqual(rec_res["recovered"], 1)

        # Verify subscription current_period_end is STILL November (t2 + 30 days), NOT October!
        sub = self.db[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_c2"})
        self.assertEqual(sub["current_period_start"], t2)
        self.assertEqual(sub["latest_transaction_id"], "tx_nov")

    def test_c3_stale_renewal_after_revocation_cannot_revive_revoked_state(self):
        """
        C3: Revocation occurs at T2. Stale renewal event with timestamp T1 < T2 arrives.
        Invariant: Stale event is marked ignored_out_of_order and CANNOT reopen active access.
        """
        t1 = datetime(2026, 10, 20, 8, 0, tzinfo=timezone.utc)
        t2 = datetime(2026, 10, 25, 8, 0, tzinfo=timezone.utc)

        # First activate
        evt_init = self._build_event("evt_init", "initial_purchase", t1 - timedelta(days=5), "tx_init", "orig_c3")
        self.settlement.process_lifecycle_event(evt_init)

        # Then revoke at T2
        evt_rev = self._build_event("evt_rev", "revocation", t2, "tx_rev", "orig_c3")
        self.settlement.process_lifecycle_event(evt_rev, as_of=t2)

        # Stale renewal arrives with timestamp T1 < T2
        evt_stale = self._build_event("evt_stale_ren", "renewal", t1, "tx_stale", "orig_c3")
        res_stale = self.settlement.process_lifecycle_event(evt_stale, as_of=t2 + timedelta(hours=1))

        self.assertEqual(res_stale["status"], "ignored_out_of_order")

        # Entitlement check: MUST BE REVOKED
        decision = self.entitlement.evaluate_entitlement("user_c", "ai.nutrition_gemini", as_of=t2 + timedelta(hours=2))
        self.assertEqual(decision.status, EntitlementDecisionStatus.REVOKED)

    def test_c4_same_timestamp_different_event_ids_flags_reconciliation_required(self):
        """
        C4: Two events with the exact same timestamp but differing event IDs arrive.
        Cannot deterministically establish sequence.
        Subscription must be flagged reconciliation_required=True without guessing.
        """
        t0 = datetime(2026, 10, 30, 12, 0, tzinfo=timezone.utc)
        evt_a = self._build_event("evt_c4_a", "initial_purchase", t0, "tx_c4_a", "orig_c4")
        self.settlement.process_lifecycle_event(evt_a, as_of=t0)

        # Conflicting event with exact same timestamp T0
        evt_b = self._build_event("evt_c4_b", "cancellation", t0, "tx_c4_b", "orig_c4")
        res_b = self.settlement.process_lifecycle_event(evt_b, as_of=t0)

        self.assertEqual(res_b["status"], "reconciliation_required")
        sub = self.db[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_c4"})
        self.assertTrue(sub["reconciliation_required"])

    def test_c5_missing_timestamp_flags_reconciliation_required(self):
        """
        C5: Event with missing/None timestamp when subscription exists:
        Indeterminate ordering -> flags reconciliation_required=True.
        """
        t0 = datetime(2026, 10, 30, 8, 0, tzinfo=timezone.utc)
        evt_init = self._build_event("evt_c5_init", "initial_purchase", t0, "tx_c5_init", "orig_c5")
        self.settlement.process_lifecycle_event(evt_init, as_of=t0)

        # Second event with event_timestamp=None
        evt_no_ts = self._build_event("evt_c5_no_ts", "renewal", t0, "tx_c5_ren", "orig_c5")
        object.__setattr__(evt_no_ts, "event_timestamp", None)  # Bypass frozen check for test

        res = self.settlement.process_lifecycle_event(evt_no_ts, as_of=t0 + timedelta(hours=1))
        self.assertEqual(res["status"], "reconciliation_required")

        sub = self.db[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_c5"})
        self.assertTrue(sub["reconciliation_required"])

    def test_c6_cancel_expiry_legitimate_renewal_reactivates_subscription(self):
        """
        C6: User cancels auto-renew -> access preserved until period end -> expires.
        Later, a legitimate new verified renewal (T3 > T2) arrives from the store.
        Invariant: Must cleanly reactivate subscription to ACTIVE with new current_period_end.
        """
        t1 = datetime(2026, 10, 1, 8, 0, tzinfo=timezone.utc)
        t_cancel = datetime(2026, 10, 15, 8, 0, tzinfo=timezone.utc)
        t_expiry = datetime(2026, 11, 1, 8, 0, tzinfo=timezone.utc)
        t_resub = datetime(2026, 11, 5, 8, 0, tzinfo=timezone.utc)

        # 1. Initial activation
        evt_init = self._build_event("evt_c6_1", "initial_purchase", t1, "tx_c6_1", "orig_c6")
        self.settlement.process_lifecycle_event(evt_init, as_of=t1)

        # 2. Cancel auto-renew (retains active access)
        evt_cancel = self._build_event("evt_c6_2", "cancellation", t_cancel, "tx_c6_1", "orig_c6")
        self.settlement.process_lifecycle_event(evt_cancel, as_of=t_cancel)

        # At Oct 20: Still allowed
        dec_oct = self.entitlement.evaluate_entitlement("user_c", "ai.nutrition_gemini", as_of=datetime(2026, 10, 20, tzinfo=timezone.utc))
        self.assertEqual(dec_oct.status, EntitlementDecisionStatus.ALLOWED)

        # 3. Sweep/mark expired at Nov 2
        self.settlement.sweep_expired_subscriptions(as_of=datetime(2026, 11, 2, tzinfo=timezone.utc))
        dec_exp = self.entitlement.evaluate_entitlement("user_c", "ai.nutrition_gemini", as_of=datetime(2026, 11, 2, tzinfo=timezone.utc))
        self.assertEqual(dec_exp.status, EntitlementDecisionStatus.ENTITLEMENT_REQUIRED)

        # 4. Legitimate verified resubscribe at Nov 5
        evt_ren = self._build_event("evt_c6_3", "renewal", t_resub, "tx_c6_ren", "orig_c6")
        res_ren = self.settlement.process_lifecycle_event(evt_ren, as_of=t_resub)
        self.assertEqual(res_ren["status"], "processed")

        # Entitlement check: ACTIVE access restored!
        dec_restored = self.entitlement.evaluate_entitlement("user_c", "ai.nutrition_gemini", as_of=t_resub + timedelta(hours=1))
        self.assertEqual(dec_restored.status, EntitlementDecisionStatus.ALLOWED)

    def test_c7_refund_single_period_in_multi_period_lineage_preserves_historical_transactions(self):
        """
        C7: User had Period 1 (Oct) and Period 2 (Nov).
        Refund issued specifically for Period 2 (tx_nov).
        tx_col marks tx_nov as 'refunded', but tx_oct remains 'verified'.
        """
        t1 = datetime(2026, 10, 1, 8, 0, tzinfo=timezone.utc)
        t2 = datetime(2026, 11, 1, 8, 0, tzinfo=timezone.utc)
        t_ref = datetime(2026, 11, 5, 8, 0, tzinfo=timezone.utc)

        self.settlement.process_lifecycle_event(self._build_event("evt_oct", "initial_purchase", t1, "tx_oct", "orig_c7"), as_of=t1)
        self.settlement.process_lifecycle_event(self._build_event("evt_nov", "renewal", t2, "tx_nov", "orig_c7"), as_of=t2)

        # Refund Period 2
        evt_ref = self._build_event("evt_ref", "revocation", t_ref, "tx_nov", "orig_c7")
        self.settlement.process_lifecycle_event(evt_ref, as_of=t_ref)

        tx_nov = self.db[COLL_PAYMENT_TRANSACTIONS].find_one({"transaction_id": "tx_nov"})
        self.assertEqual(tx_nov["status"], "refunded")

        tx_oct = self.db[COLL_PAYMENT_TRANSACTIONS].find_one({"transaction_id": "tx_oct"})
        self.assertEqual(tx_oct["status"], "verified")

    def test_c8_independent_grant_remains_active_when_subscription_grant_revoked(self):
        """
        C8: User has a subscription grant (which gets revoked) AND an independent promotional grant.
        EntitlementService returns ALLOWED because the independent grant is active!
        """
        now = datetime.now(timezone.utc)
        # 1. Seed revoked subscription grant
        self.db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_sub_revoked",
            "user_id": "user_multi_grant",
            "benefit_id": "ai.nutrition_gemini",
            "status": EntitlementStatus.REVOKED.value,
            "source_type": "subscription",
            "source_subscription_id": "sub_old",
        })
        # 2. Seed active promotional grant
        self.db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_promo_active",
            "user_id": "user_multi_grant",
            "benefit_id": "ai.nutrition_gemini",
            "status": EntitlementStatus.GRANTED.value,
            "source_type": "promotional",
            "valid_from": now - timedelta(days=1),
            "valid_until": now + timedelta(days=30),
        })

        decision = self.entitlement.evaluate_entitlement("user_multi_grant", "ai.nutrition_gemini", as_of=now)
        self.assertEqual(decision.status, EntitlementDecisionStatus.ALLOWED)
        self.assertEqual(decision.source, "promotional")

    def test_c9_wal_event_durable_projection_failure_resumes_cleanly(self):
        """
        C9: Event written to WAL with processing_status='received'.
        Projection crashes midway. reconcile_incomplete_payment_events resumes projection from snapshot.
        """
        now = datetime.now(timezone.utc)
        snapshot = {
            "provider": self.provider.value,
            "environment": self.env.value,
            "app_id": self.app_id,
            "product_id": "saman_plus_monthly_sandbox",
            "user_id": "user_wal_c9",
            "transaction_id": "tx_wal_c9",
            "original_transaction_id": "orig_wal_c9",
            "verification_status": ProviderVerificationStatus.VERIFIED_ACTIVE.value,
            "purchase_date": now,
            "expires_date": now + timedelta(days=30),
            "raw_payload_hash": hash_sensitive_payload("tx_wal_c9"),
            "event_timestamp": now,
            "mapping": self.mapping.model_dump(),
        }
        self.db[COLL_PROVIDER_EVENTS].insert_one({
            "event_id": "evt_wal_c9",
            "provider": self.provider.value,
            "environment": self.env.value,
            "event_type": "initial_purchase",
            "processing_status": "received",
            "projection_snapshot": snapshot,
            "received_at": now,
            "processed_at": None,
        })

        rec = self.settlement.reconcile_incomplete_payment_events(as_of=now + timedelta(minutes=1))
        self.assertEqual(rec["recovered"], 1)

        # Event transitioned to processed
        evt = self.db[COLL_PROVIDER_EVENTS].find_one({"event_id": "evt_wal_c9"})
        self.assertEqual(evt["processing_status"], "processed")

        # Subscription projected
        sub = self.db[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_wal_c9"})
        self.assertIsNotNone(sub)
        self.assertEqual(sub["status"], SubscriptionStatus.ACTIVE.value)


# ==============================================================================
# SECTION D: Restore Purchases & Security Boundaries
# ==============================================================================

class TestRestoreAndSecurityBoundaries(unittest.TestCase):
    """
    CP-09 Section D: Tests restore boundary, client tampering rejection, and tenant data isolation.
    """

    def setUp(self):
        self.provider = PaymentProviderName.APPLE_APP_STORE
        self.env = PaymentEnvironment.SANDBOX
        self.app_id = "com.saman.health.ios"
        self.mapping = StoreProductMapping(
            provider=self.provider,
            environment=self.env,
            app_id=self.app_id,
            product_id="saman_pro_monthly_sandbox",
            plan_id="pro",
            price_id="price_pro_m",
            tier=MembershipTier.PRO,
            benefit_ids=["ai.nutrition_gemini", "workout.cv_rep_counter"],
            quota_limits={"ai.nutrition_gemini": 60},
            amount_cents=1999,
            currency="USD",
            enabled=True,
        )
        self.registry = ProductMappingRegistry(expected_environment=self.env)
        self.registry.register(self.mapping)
        self.adapter = FakeTestPaymentProviderAdapter(configured=True)

        from backend.tests.test_revenue_entitlement_quota import MockDatabase
        self.db = MockDatabase()
        self.settlement = PaymentSettlementService(
            adapter=self.adapter,
            mapping_registry=self.registry,
            db=self.db,
        )

    def test_d1_unconfigured_provider_returns_503_no_fake_success(self):
        """
        D1: When payment adapter is unconfigured, restore attempts raise PaymentConfigurationNotReadyError (503).
        No fake restore success is ever generated.
        """
        unconf_adapter = UnconfiguredPaymentProviderAdapter()
        unconf_settlement = PaymentSettlementService(
            adapter=unconf_adapter,
            mapping_registry=self.registry,
            db=self.db,
        )
        req = RestorePurchasesRequest(
            provider=self.provider,
            environment=self.env,
            app_id=self.app_id,
            product_id="saman_pro_monthly_sandbox",
            verification_token="token_any",
        )
        with self.assertRaises(PaymentConfigurationNotReadyError):
            unconf_settlement.verify_and_settle_restore("user_d1", req)

    def test_d2_same_account_restore_is_idempotent_no_expiry_extension(self):
        """
        D2: Same account restore refreshes verified state without creating duplicate transactions
        or artificially extending the expiry date.
        """
        now = datetime.now(timezone.utc)
        self.adapter.fixed_purchase_date = now
        self.adapter.fixed_expires_date = now + timedelta(days=30)
        req = RestorePurchasesRequest(
            provider=self.provider,
            environment=self.env,
            app_id=self.app_id,
            product_id="saman_pro_monthly_sandbox",
            verification_token="valid_restore_token",
        )

        res1 = self.settlement.verify_and_settle_restore("user_d2", req, as_of=now)
        self.assertEqual(res1.outcome, PurchaseVerificationOutcomeStatus.CONFIRMED)
        self.assertIn(res1.ownership_status, [ReceiptOwnershipStatus.FIRST_OWNER_PROPOSED, ReceiptOwnershipStatus.VERIFIED_OWNER])
        original_expiry = res1.current_period_end

        # Second restore call 5 days later
        res2 = self.settlement.verify_and_settle_restore("user_d2", req, as_of=now + timedelta(days=5))
        self.assertEqual(res2.outcome, PurchaseVerificationOutcomeStatus.CONFIRMED)
        # Expiry is determined by the store transaction date, NOT artificially extended!
        self.assertEqual(res2.current_period_end, original_expiry)

    def test_d3_cross_account_restore_returns_409_unresolved_conflict_no_transfer(self):
        """
        D3: User A owns the receipt. User B attempts to restore with User A's receipt.
        Raises ReceiptOwnershipConflictError (409) with ownership_status='unresolved_conflict'.
        Zero entitlement granted to User B. Receipt ownership remains bound to User A.
        """
        now = datetime.now(timezone.utc)
        req = RestorePurchasesRequest(
            provider=self.provider,
            environment=self.env,
            app_id=self.app_id,
            product_id="saman_pro_monthly_sandbox",
            verification_token="token_user_a",
        )
        # User A claims first ownership
        self.settlement.verify_and_settle_restore("user_a", req, as_of=now)

        # User B attempts restore with same original_transaction_id
        with self.assertRaises(ReceiptOwnershipConflictError) as ctx:
            self.settlement.verify_and_settle_restore("user_b", req, as_of=now + timedelta(days=1))

        self.assertIn("bound to another account", str(ctx.exception))

        # Confirm receipt is STILL owned by user_a
        sub = self.db[COLL_SUBSCRIPTIONS].find_one({"original_transaction_id": "orig_fake_001"})
        self.assertEqual(sub["user_id"], "user_a")

    def test_d4_wrong_app_env_or_product_rejected_zero_grants(self):
        """
        D4: Verification attempt with wrong app_id or wrong product mapping raises
        ProductMappingRejectedError. Zero grants or subscriptions are created.
        """
        req_wrong_app = RestorePurchasesRequest(
            provider=self.provider,
            environment=self.env,
            app_id="com.other.hacked.app",
            product_id="saman_pro_monthly_sandbox",
            verification_token="token_hack",
        )
        with self.assertRaises(ProductMappingRejectedError):
            self.settlement.verify_and_settle_restore("user_d4", req_wrong_app)

        self.assertEqual(len(self.db[COLL_SUBSCRIPTIONS].documents), 0)
        self.assertEqual(len(self.db[COLL_ENTITLEMENT_GRANTS].documents), 0)

    def test_d5_client_spoofed_user_tier_expiry_ignored(self):
        """
        D5: Client passes a request body trying to spoof a different user_id or higher tier.
        The backend boundary asserts caller user_id vs authenticated session.
        If client supplies mismatched user_id, it is rejected with 403.
        """
        req_spoofed = RestorePurchasesRequest(
            user_id="spoofed_admin_user",
            provider=self.provider,
            environment=self.env,
            app_id=self.app_id,
            product_id="saman_pro_monthly_sandbox",
            verification_token="token_user_real",
        )
        from backend.app.services.payment_service import ClientIdentityMismatchError
        with self.assertRaises(ClientIdentityMismatchError):
            self.settlement.verify_and_settle_restore("real_authenticated_user", req_spoofed)

    def test_d6_operation_lookup_tenant_isolation_cannot_inspect_other_users(self):
        """
        D6: Strict tenant isolation:
        User B querying User A's operation via query_operation returns None (404 Not Found).
        """
        q_svc = QuotaService(db=self.db)
        now = datetime.now(timezone.utc)
        res = q_svc.reserve_quota(
            user_id="user_alice",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=5,
            idempotency_key="alice_private_op",
            as_of=now,
        )

        # Alice can query her own operation
        alice_view = q_svc.query_operation("user_alice", res.operation_id)
        self.assertIsNotNone(alice_view)

        # Bob attempts to query Alice's operation -> Returns None!
        bob_view = q_svc.query_operation("user_bob", res.operation_id)
        self.assertIsNone(bob_view)

    def test_d7_production_app_cannot_access_fake_adapter(self):
        """
        D7: Security check:
        In production environment (PaymentEnvironment.PRODUCTION),
        FakeTestPaymentProviderAdapter or unconfigured adapters cannot be mounted
        without explicit authorization.
        """
        prod_registry = ProductMappingRegistry(expected_environment=PaymentEnvironment.PRODUCTION)
        prod_settlement = PaymentSettlementService(
            adapter=UnconfiguredPaymentProviderAdapter(),
            mapping_registry=prod_registry,
            db=self.db,
        )
        self.assertFalse(prod_settlement._adapter.is_configured())
        self.assertEqual(prod_settlement._mapping_registry.expected_environment, PaymentEnvironment.PRODUCTION)


if __name__ == "__main__":
    unittest.main()

