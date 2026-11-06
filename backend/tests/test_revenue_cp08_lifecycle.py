"""
Tests for CP-08 Subscription Lifecycle, Expiry, Revocation & Restore Foundation (Backend).

Coverage:
- Initial activation and Renewal (advances period_end, maintains entitlement)
- Duplicate / concurrent Renewal projection idempotency
- Quota Renewal Replay does NOT reset usage (consumed/reserved units preserved)
- Cancellation (cancel auto-renew keeps rights until current_period_end -> expired after period)
- Failed payment (BILLING_ISSUE) with injected GracePeriodPolicy (allowed during grace -> expired after grace)
- Missing Grace Policy does NOT fake grace or grant paid access
- Refund/Revocation targets specific transaction & grant (does NOT blanket revoke all user grants)
- Stale out-of-order Renewal after Revocation CANNOT reopen access
- Timestamp collision flagged as reconciliation_required without guessing access
- Crash / WAL replay recovery
- Restore Same Account idempotent (refreshes verified state, no new purchase, no fake expiry extension)
- Cross-account conflict returns 409 unresolved_conflict without transfer
- Background sweep utility
"""

from datetime import datetime, timezone, timedelta
import json
import unittest
from typing import Dict, Any, Optional

from fastapi.testclient import TestClient

from backend.main import app
from backend.auth_utils import verify_token
from backend.app.models.revenue import (
    PaymentProviderName,
    PaymentEnvironment,
    ProviderVerificationStatus,
    PurchaseVerificationOutcomeStatus,
    StoreProductMapping,
    PurchaseVerificationRequest,
    VerifiedProviderTransaction,
    VerifiedWebhookEvent,
    RestorePurchasesRequest,
    RestorePurchasesResponse,
    MembershipTier,
    BillingPeriod,
    SubscriptionStatus,
    EntitlementStatus,
    SubscriptionLifecycleEventType,
    ReceiptOwnershipStatus,
    GracePeriodPolicy,
)
from backend.app.database_revenue import (
    COLL_PROVIDER_EVENTS,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_SUBSCRIPTIONS,
    COLL_ENTITLEMENT_GRANTS,
    COLL_USAGE_BUCKETS,
)
from backend.app.services.payment_service import (
    IPaymentProviderAdapter,
    UnconfiguredPaymentProviderAdapter,
    ProductMappingRegistry,
    PaymentSettlementService,
    PaymentWebhookIngestionService,
    PaymentConfigurationNotReadyError,
    UnverifiedPurchasePayloadError,
    ProductMappingRejectedError,
    ReceiptOwnershipConflictError,
    WebhookVerificationError,
    PaymentStorageError,
    hash_sensitive_payload,
)
from backend.app.services.entitlement_service import EntitlementService
from backend.tests.test_revenue_entitlement_quota import MockDatabase as FakeDatabase


class FakeLifecyclePaymentAdapter(IPaymentProviderAdapter):
    """
    Deterministic fake provider adapter for isolated CP-08 lifecycle contract tests.
    """

    def __init__(
        self,
        provider: PaymentProviderName = PaymentProviderName.APPLE_APP_STORE,
        configured: bool = True,
    ):
        self._provider = provider
        self._configured = configured
        self.token_registry: Dict[str, VerifiedProviderTransaction] = {}

    @property
    def provider_name(self) -> PaymentProviderName:
        return self._provider

    def is_configured(self) -> bool:
        return self._configured

    def register_verified_token(self, token: str, tx: VerifiedProviderTransaction) -> None:
        self.token_registry[token] = tx

    def verify_purchase(
        self,
        request: PurchaseVerificationRequest,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedProviderTransaction:
        if not self._configured:
            raise PaymentConfigurationNotReadyError("Adapter unconfigured.")
        if request.verification_token not in self.token_registry:
            raise UnverifiedPurchasePayloadError("INVALID_TOKEN", "Receipt not found in test registry.")
        return self.token_registry[request.verification_token]

    def verify_and_parse_webhook(
        self,
        headers: Dict[str, str],
        raw_body: bytes,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedWebhookEvent:
        if not self._configured:
            raise PaymentConfigurationNotReadyError("Adapter unconfigured.")
        parsed = json.loads(raw_body.decode("utf-8"))
        tx_data = parsed["transaction"]
        tx = VerifiedProviderTransaction(
            provider=PaymentProviderName(tx_data["provider"]),
            environment=PaymentEnvironment(tx_data["environment"]),
            app_id=tx_data["app_id"],
            product_id=tx_data["product_id"],
            transaction_id=tx_data["transaction_id"],
            original_transaction_id=tx_data["original_transaction_id"],
            verification_status=ProviderVerificationStatus(tx_data["verification_status"]),
            purchase_date=datetime.fromisoformat(tx_data["purchase_date"]),
            expires_date=datetime.fromisoformat(tx_data["expires_date"]),
            raw_payload_hash=hash_sensitive_payload(tx_data["transaction_id"]),
        )
        return VerifiedWebhookEvent(
            event_id=parsed["event_id"],
            provider=PaymentProviderName(parsed["provider"]),
            environment=PaymentEnvironment(parsed["environment"]),
            event_type=parsed["event_type"],
            event_timestamp=datetime.fromisoformat(parsed["event_timestamp"]),
            user_id=parsed.get("user_id"),
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload(parsed["event_id"]),
        )


class TestRevenueCP08Lifecycle(unittest.TestCase):
    """Targeted Unit and Boundary Tests for Subscription Lifecycle and Restore (CP-08)."""

    def setUp(self):
        self.db = FakeDatabase()
        self.provider = PaymentProviderName.APPLE_APP_STORE
        self.environment = PaymentEnvironment.SANDBOX
        self.app_id = "ai.saman.app"
        self.adapter = FakeLifecyclePaymentAdapter(provider=self.provider, configured=True)

        self.mapping = StoreProductMapping(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            plan_id="plan_pro",
            price_id="price_pro_monthly_usd_1999",
            tier=MembershipTier.PRO,
            period=BillingPeriod.MONTHLY,
            amount_cents=1999,
            currency="USD",
            benefit_ids=["ai.nutrition_gemini", "workout.cv.ai"],
            quota_limits={"ai.nutrition_gemini": 300},
            enabled=True,
        )
        self.registry = ProductMappingRegistry(
            mappings=[self.mapping],
            expected_environment=self.environment,
            allowed_app_ids=[self.app_id],
        )
        self.settlement = PaymentSettlementService(
            db=self.db,
            adapter=self.adapter,
            mapping_registry=self.registry,
        )
        self.entitlement_svc = EntitlementService(db=self.db)

    def test_01_initial_activation_and_renewal_advances_period(self):
        """Scenario 1: Initial activation grants access, renewal advances period end and maintains entitlement."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        t0_end = t0 + timedelta(days=30)

        # 1. Initial purchase
        tx_init = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_1001",
            original_transaction_id="orig_1000",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t0_end,
            raw_payload_hash=hash_sensitive_payload("tx_1001"),
        )
        self.adapter.register_verified_token("token_1001", tx_init)

        req1 = PurchaseVerificationRequest(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            verification_token="token_1001",
        )
        res1 = self.settlement.verify_and_settle_purchase("alice@saman.ai", req1, as_of=t0)
        self.assertEqual(res1.outcome, PurchaseVerificationOutcomeStatus.CONFIRMED)
        self.assertEqual(res1.tier, MembershipTier.PRO)

        # Check initial entitlement
        dec1 = self.entitlement_svc.evaluate_entitlement("alice@saman.ai", "ai.nutrition_gemini", as_of=t0 + timedelta(days=5))
        self.assertEqual(dec1.status.value, "allowed")

        # 2. Renewal event 30 days later
        t1 = t0_end
        t1_end = t1 + timedelta(days=30)
        tx_renew = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_1002",
            original_transaction_id="orig_1000",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t1,
            expires_date=t1_end,
            raw_payload_hash=hash_sensitive_payload("tx_1002"),
        )
        evt_renew = VerifiedWebhookEvent(
            event_id="evt_renew_1002",
            provider=self.provider,
            environment=self.environment,
            event_type=SubscriptionLifecycleEventType.RENEWAL.value,
            event_timestamp=t1,
            user_id="alice@saman.ai",
            transaction=tx_renew,
            raw_payload_hash=hash_sensitive_payload("evt_renew_1002"),
        )
        renew_res = self.settlement.process_lifecycle_event(evt_renew, as_of=t1)
        self.assertTrue(renew_res["acknowledged"])
        self.assertEqual(renew_res["status"], "processed")

        # Verify subscription was advanced
        sub = self.db._collections[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_1000"})
        self.assertEqual(sub["latest_transaction_id"], "tx_1002")
        self.assertEqual(sub["current_period_end"], t1_end)
        self.assertEqual(sub["version"], 2)

        # Entitlement check in renewed period
        dec2 = self.entitlement_svc.evaluate_entitlement("alice@saman.ai", "ai.nutrition_gemini", as_of=t1 + timedelta(days=10))
        self.assertEqual(dec2.status.value, "allowed")

    def test_02_renewal_replay_does_not_reset_quota_usage(self):
        """Scenario 2: Replaying renewal event on the same period does NOT reset consumed quota units."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        t0_end = t0 + timedelta(days=30)

        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_quota_1",
            original_transaction_id="orig_quota_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t0_end,
            raw_payload_hash=hash_sensitive_payload("tx_quota_1"),
        )
        evt = VerifiedWebhookEvent(
            event_id="evt_quota_1",
            provider=self.provider,
            environment=self.environment,
            event_type="initial_purchase",
            event_timestamp=t0,
            user_id="bob@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_quota_1"),
        )
        self.settlement.process_lifecycle_event(evt, as_of=t0)

        # Simulate user consuming 15 AI units
        buckets_col = self.db._collections[COLL_USAGE_BUCKETS]
        bkt = buckets_col.find_one({"user_id": "bob@saman.ai"})
        self.assertIsNotNone(bkt)
        buckets_col.update_one({"bucket_id": bkt["bucket_id"]}, {"$set": {"consumed_units": 15, "reserved_units": 2}})

        # Now replay the renewal event for the same period
        evt_replay = VerifiedWebhookEvent(
            event_id="evt_quota_replay",
            provider=self.provider,
            environment=self.environment,
            event_type="renewal",
            event_timestamp=t0 + timedelta(hours=1),
            user_id="bob@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_quota_replay"),
        )
        self.settlement.process_lifecycle_event(evt_replay, as_of=t0 + timedelta(hours=1))

        # Assert consumed and reserved units are preserved!
        bkt_after = buckets_col.find_one({"user_id": "bob@saman.ai"})
        self.assertEqual(bkt_after["consumed_units"], 15, "Consumed quota must not be reset on renewal replay!")
        self.assertEqual(bkt_after["reserved_units"], 2, "Reserved quota must not be reset on renewal replay!")

    def test_03_cancel_auto_renew_maintains_access_until_period_end(self):
        """Scenario 3: Canceling auto-renew maintains access until current_period_end, and expires after."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        t_end = t0 + timedelta(days=30)

        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_cancel_1",
            original_transaction_id="orig_cancel_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t_end,
            raw_payload_hash=hash_sensitive_payload("tx_cancel_1"),
        )
        evt_init = VerifiedWebhookEvent(
            event_id="evt_cancel_init",
            provider=self.provider,
            environment=self.environment,
            event_type="initial_purchase",
            event_timestamp=t0,
            user_id="carol@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_cancel_init"),
        )
        self.settlement.process_lifecycle_event(evt_init, as_of=t0)

        # User cancels auto-renew on day 10
        t_cancel = t0 + timedelta(days=10)
        evt_cancel = VerifiedWebhookEvent(
            event_id="evt_cancel_action",
            provider=self.provider,
            environment=self.environment,
            event_type=SubscriptionLifecycleEventType.CANCELLATION.value,
            event_timestamp=t_cancel,
            user_id="carol@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_cancel_action"),
        )
        self.settlement.process_lifecycle_event(evt_cancel, as_of=t_cancel)

        # Check subscription record
        sub = self.db._collections[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_cancel_1"})
        self.assertTrue(sub["cancel_at_period_end"])
        self.assertFalse(sub["auto_renew_status"])
        self.assertEqual(sub["status"], SubscriptionStatus.ACTIVE.value, "Status must stay ACTIVE until period end.")

        # Entitlement check before period end (Day 20): STILL ALLOWED!
        dec_before = self.entitlement_svc.evaluate_entitlement("carol@saman.ai", "ai.nutrition_gemini", as_of=t0 + timedelta(days=20))
        self.assertEqual(dec_before.status.value, "allowed", "User must retain paid access until period end.")

        # Entitlement check after period end (Day 31): EXPIRED / NOT ALLOWED!
        dec_after = self.entitlement_svc.evaluate_entitlement("carol@saman.ai", "ai.nutrition_gemini", as_of=t0 + timedelta(days=31))
        self.assertNotEqual(dec_after.status.value, "allowed")

    def test_04_billing_issue_with_injected_grace_policy(self):
        """Scenario 4: Failed payment with injected GracePeriodPolicy preserves access during grace and expires after."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        t_end = t0 + timedelta(days=30)

        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_grace_1",
            original_transaction_id="orig_grace_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t_end,
            raw_payload_hash=hash_sensitive_payload("tx_grace_1"),
        )
        evt_init = VerifiedWebhookEvent(
            event_id="evt_grace_init",
            provider=self.provider,
            environment=self.environment,
            event_type="initial_purchase",
            event_timestamp=t0,
            user_id="dan@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_grace_init"),
        )
        self.settlement.process_lifecycle_event(evt_init, as_of=t0)

        # Billing retry failure at t_end with injected 3-day grace policy (259200 seconds)
        grace_policy = GracePeriodPolicy(enabled=True, grace_duration_seconds=259200)
        evt_fail = VerifiedWebhookEvent(
            event_id="evt_grace_fail",
            provider=self.provider,
            environment=self.environment,
            event_type=SubscriptionLifecycleEventType.BILLING_ISSUE.value,
            event_timestamp=t_end,
            user_id="dan@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_grace_fail"),
        )
        self.settlement.process_lifecycle_event(evt_fail, grace_policy=grace_policy, as_of=t_end)

        # Check subscription status is PAST_DUE and in_grace_period=True
        sub = self.db._collections[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_grace_1"})
        self.assertEqual(sub["status"], SubscriptionStatus.PAST_DUE.value)
        self.assertTrue(sub["in_grace_period"])
        self.assertIsNotNone(sub["grace_period_expires_at"])

        # Check access during grace (1 day into grace): ALLOWED!
        dec_grace = self.entitlement_svc.evaluate_entitlement("dan@saman.ai", "ai.nutrition_gemini", as_of=t_end + timedelta(days=1))
        self.assertEqual(dec_grace.status.value, "allowed")

        # Check access after grace (4 days into grace): NOT ALLOWED!
        dec_post_grace = self.entitlement_svc.evaluate_entitlement("dan@saman.ai", "ai.nutrition_gemini", as_of=t_end + timedelta(days=4))
        self.assertNotEqual(dec_post_grace.status.value, "allowed")

    def test_05_missing_grace_policy_does_not_fake_grace_access(self):
        """Scenario 5: Missing grace policy defaults to enabled=False; billing failure immediately cuts access."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        t_end = t0 + timedelta(days=30)

        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_no_grace_1",
            original_transaction_id="orig_no_grace_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t_end,
            raw_payload_hash=hash_sensitive_payload("tx_no_grace_1"),
        )
        evt_init = VerifiedWebhookEvent(
            event_id="evt_no_grace_init",
            provider=self.provider,
            environment=self.environment,
            event_type="initial_purchase",
            event_timestamp=t0,
            user_id="eve@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_no_grace_init"),
        )
        self.settlement.process_lifecycle_event(evt_init, as_of=t0)

        # Billing failure with default (None) grace policy
        evt_fail = VerifiedWebhookEvent(
            event_id="evt_no_grace_fail",
            provider=self.provider,
            environment=self.environment,
            event_type=SubscriptionLifecycleEventType.BILLING_ISSUE.value,
            event_timestamp=t_end,
            user_id="eve@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_no_grace_fail"),
        )
        self.settlement.process_lifecycle_event(evt_fail, grace_policy=None, as_of=t_end)

        sub = self.db._collections[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_no_grace_1"})
        self.assertFalse(sub["in_grace_period"])
        self.assertIsNone(sub["grace_period_expires_at"])

        # Access 1 hour after billing failure: NOT ALLOWED!
        dec = self.entitlement_svc.evaluate_entitlement("eve@saman.ai", "ai.nutrition_gemini", as_of=t_end + timedelta(hours=1))
        self.assertNotEqual(dec.status.value, "allowed")

    def test_06_revocation_targets_specific_grant_and_cannot_be_reopened_by_stale_renewal(self):
        """Scenario 6: Refund/revocation targets specific grant and stale out-of-order renewal CANNOT reopen access."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        t_end = t0 + timedelta(days=30)

        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_revoke_1",
            original_transaction_id="orig_revoke_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t_end,
            raw_payload_hash=hash_sensitive_payload("tx_revoke_1"),
        )
        evt_init = VerifiedWebhookEvent(
            event_id="evt_revoke_init",
            provider=self.provider,
            environment=self.environment,
            event_type="initial_purchase",
            event_timestamp=t0,
            user_id="frank@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_revoke_init"),
        )
        self.settlement.process_lifecycle_event(evt_init, as_of=t0)

        # Refund issued on Day 5
        t_revoke = t0 + timedelta(days=5)
        evt_revoke = VerifiedWebhookEvent(
            event_id="evt_revoke_refund",
            provider=self.provider,
            environment=self.environment,
            event_type=SubscriptionLifecycleEventType.REVOCATION.value,
            event_timestamp=t_revoke,
            user_id="frank@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_revoke_refund"),
        )
        self.settlement.process_lifecycle_event(evt_revoke, as_of=t_revoke)

        # Check transaction is marked refunded and grant is marked REVOKED
        tx_doc = self.db._collections[COLL_PAYMENT_TRANSACTIONS].find_one({"transaction_id": "tx_revoke_1"})
        self.assertEqual(tx_doc["status"], "refunded")

        grant_doc = self.db._collections[COLL_ENTITLEMENT_GRANTS].find_one({"grant_id": "grant_sub_apple_app_store_sandbox_orig_revoke_1_ai.nutrition_gemini"})
        self.assertEqual(grant_doc["status"], EntitlementStatus.REVOKED.value)

        # Entitlement check immediately after refund: REVOKED!
        dec_revoked = self.entitlement_svc.evaluate_entitlement("frank@saman.ai", "ai.nutrition_gemini", as_of=t_revoke + timedelta(hours=1))
        self.assertEqual(dec_revoked.status.value, "revoked")

        # Now simulate a stale out-of-order renewal event dated Day 2 arriving AFTER the revocation
        t_stale = t0 + timedelta(days=2)
        evt_stale_renew = VerifiedWebhookEvent(
            event_id="evt_stale_renew_delayed",
            provider=self.provider,
            environment=self.environment,
            event_type="renewal",
            event_timestamp=t_stale,
            user_id="frank@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_stale_renew_delayed"),
        )
        stale_res = self.settlement.process_lifecycle_event(evt_stale_renew, as_of=t_revoke + timedelta(hours=2))
        self.assertEqual(stale_res["status"], "ignored_out_of_order")

        # Invariant check: Subscription and grant remain REVOKED, NOT reopened!
        dec_still_revoked = self.entitlement_svc.evaluate_entitlement("frank@saman.ai", "ai.nutrition_gemini", as_of=t_revoke + timedelta(hours=3))
        self.assertEqual(dec_still_revoked.status.value, "revoked", "Stale renewal must NOT revive a revoked grant!")

    def test_07_timestamp_collision_marks_reconciliation_required(self):
        """Scenario 7: Identical timestamp collision from different event marks reconciliation_required without guessing access."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)

        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_coll_1",
            original_transaction_id="orig_coll_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t0 + timedelta(days=30),
            raw_payload_hash=hash_sensitive_payload("tx_coll_1"),
        )
        evt_1 = VerifiedWebhookEvent(
            event_id="evt_coll_1",
            provider=self.provider,
            environment=self.environment,
            event_type="initial_purchase",
            event_timestamp=t0,
            user_id="grace@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_coll_1"),
        )
        self.settlement.process_lifecycle_event(evt_1, as_of=t0)

        # Different event_id with identical timestamp
        evt_2 = VerifiedWebhookEvent(
            event_id="evt_coll_2",
            provider=self.provider,
            environment=self.environment,
            event_type="cancellation",
            event_timestamp=t0,
            user_id="grace@saman.ai",
            transaction=tx,
            raw_payload_hash=hash_sensitive_payload("evt_coll_2"),
        )
        res_2 = self.settlement.process_lifecycle_event(evt_2, as_of=t0)
        self.assertTrue(res_2["reconciliation_required"])

        sub = self.db._collections[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_coll_1"})
        self.assertTrue(sub["reconciliation_required"])

    def test_08_restore_same_account_idempotent_no_new_purchase(self):
        """Scenario 8: Restoring on same account is idempotent: refreshes verified state without new purchase or artificial expiry extension."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        t_end = t0 + timedelta(days=30)

        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_rest_1",
            original_transaction_id="orig_rest_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t_end,
            raw_payload_hash=hash_sensitive_payload("tx_rest_1"),
        )
        self.adapter.register_verified_token("token_rest_1", tx)

        # 1. User initially purchases
        req_buy = PurchaseVerificationRequest(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            verification_token="token_rest_1",
        )
        self.settlement.verify_and_settle_purchase("heidi@saman.ai", req_buy, as_of=t0)

        tx_count_before = len(self.db._collections[COLL_PAYMENT_TRANSACTIONS].documents)

        # 2. User reinstalls app and taps "Restore Purchases"
        req_restore = RestorePurchasesRequest(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            verification_token="token_rest_1",
        )
        t_restore = t0 + timedelta(days=10)
        res_restore = self.settlement.verify_and_settle_restore("heidi@saman.ai", req_restore, as_of=t_restore)

        self.assertEqual(res_restore.outcome, PurchaseVerificationOutcomeStatus.CONFIRMED)
        self.assertEqual(res_restore.ownership_status, ReceiptOwnershipStatus.VERIFIED_OWNER)
        self.assertTrue(res_restore.is_active_subscription)
        self.assertEqual(res_restore.current_period_end, t_end, "Restore must NOT extend expiry date!")
        self.assertTrue(res_restore.duplicate_ignored)

        # Invariant: No duplicate financial transactions created on restore!
        tx_count_after = len(self.db._collections[COLL_PAYMENT_TRANSACTIONS].documents)
        self.assertEqual(tx_count_before, tx_count_after, "Restore must not create a duplicate transaction record.")

    def test_09_restore_different_account_detects_conflict_without_transfer(self):
        """Scenario 9: Restoring on different account detects ownership conflict, returns 409 and does NOT transfer receipt."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        t_end = t0 + timedelta(days=30)

        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_hijack_1",
            original_transaction_id="orig_hijack_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t_end,
            raw_payload_hash=hash_sensitive_payload("tx_hijack_1"),
        )
        self.adapter.register_verified_token("token_hijack_1", tx)

        # Bound to owner_alice
        req_buy = PurchaseVerificationRequest(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            verification_token="token_hijack_1",
        )
        self.settlement.verify_and_settle_purchase("owner_alice@saman.ai", req_buy, as_of=t0)

        # Attacker/different account attempts to restore the same token
        req_restore_bad = RestorePurchasesRequest(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            verification_token="token_hijack_1",
        )

        with self.assertRaises(ReceiptOwnershipConflictError) as ctx:
            self.settlement.verify_and_settle_restore("other_bob@saman.ai", req_restore_bad, as_of=t0 + timedelta(days=2))

        self.assertEqual(ctx.exception.http_status, 409)
        self.assertEqual(ctx.exception.ownership_status, "unresolved_conflict")
        self.assertEqual(ctx.exception.first_owner_policy, "PROPOSED")

        # Verify other_bob was NOT granted Pro entitlement
        dec_bob = self.entitlement_svc.evaluate_entitlement("other_bob@saman.ai", "ai.nutrition_gemini", as_of=t0 + timedelta(days=2))
        self.assertNotEqual(dec_bob.status.value, "allowed", "Caller must NOT be granted rights on ownership conflict!")

    def test_10_sweep_expired_subscriptions_utility(self):
        """Scenario 10: sweep_expired_subscriptions marks past subscriptions and grants EXPIRED."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        t_end = t0 + timedelta(days=30)

        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_sweep_1",
            original_transaction_id="orig_sweep_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t_end,
            raw_payload_hash=hash_sensitive_payload("tx_sweep_1"),
        )
        self.adapter.register_verified_token("token_sweep_1", tx)

        req = PurchaseVerificationRequest(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            verification_token="token_sweep_1",
        )
        self.settlement.verify_and_settle_purchase("ivan@saman.ai", req, as_of=t0)

        # Sweep before expiration (Day 15) -> 0 swept
        res_before = self.settlement.sweep_expired_subscriptions(as_of=t0 + timedelta(days=15))
        self.assertEqual(res_before["swept"], 0)

        # Sweep after expiration (Day 31) -> 1 swept
        res_after = self.settlement.sweep_expired_subscriptions(as_of=t0 + timedelta(days=31))
        self.assertEqual(res_after["swept"], 1)

        sub = self.db._collections[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_sweep_1"})
        self.assertEqual(sub["status"], SubscriptionStatus.EXPIRED.value)


class TestRevenueCP08APIAndRecovery(unittest.TestCase):
    """Integration tests for Restore API and Crash Recovery."""

    def setUp(self):
        self.client = TestClient(app)
        self.db = FakeDatabase()
        self.provider = PaymentProviderName.APPLE_APP_STORE
        self.environment = PaymentEnvironment.SANDBOX
        self.app_id = "ai.saman.app"
        self.adapter = FakeLifecyclePaymentAdapter(provider=self.provider, configured=True)

        self.mapping = StoreProductMapping(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            plan_id="plan_pro",
            price_id="price_pro_monthly_usd_1999",
            tier=MembershipTier.PRO,
            period=BillingPeriod.MONTHLY,
            amount_cents=1999,
            currency="USD",
            benefit_ids=["ai.nutrition_gemini"],
            quota_limits={"ai.nutrition_gemini": 300},
            enabled=True,
        )
        self.registry = ProductMappingRegistry(
            mappings=[self.mapping],
            expected_environment=self.environment,
            allowed_app_ids=[self.app_id],
        )
        self.settlement = PaymentSettlementService(
            db=self.db,
            adapter=self.adapter,
            mapping_registry=self.registry,
        )

    def test_api_restore_unconfigured_provider_fails_closed_503(self):
        """API: Restore endpoint returns 503 when provider is unconfigured."""
        unconfigured_settlement = PaymentSettlementService(
            db=self.db,
            adapter=UnconfiguredPaymentProviderAdapter(),
            mapping_registry=self.registry,
        )
        app.dependency_overrides[verify_token] = lambda: "test_user@saman.ai"
        from unittest.mock import patch
        with patch("backend.routers.revenue.get_payment_settlement_service", return_value=unconfigured_settlement):
            resp = self.client.post(
                "/api/revenue/purchases/restore",
                json={
                    "provider": "unconfigured",
                    "environment": "sandbox",
                    "app_id": "ai.saman.app",
                    "verification_token": "any_tok",
                },
            )
            self.assertEqual(resp.status_code, 503)
            self.assertEqual(resp.json()["detail"]["code"], "PAYMENT_CONFIG_NOT_READY")
        app.dependency_overrides.clear()

    def test_api_restore_spoofed_user_id_fails_403(self):
        """API: Client-supplied user_id mismatch with JWT returns 403."""
        app.dependency_overrides[verify_token] = lambda: "real_user@saman.ai"
        from unittest.mock import patch
        with patch("backend.routers.revenue.get_payment_settlement_service", return_value=self.settlement):
            resp = self.client.post(
                "/api/revenue/purchases/restore",
                json={
                    "provider": "apple_app_store",
                    "environment": "sandbox",
                    "app_id": "ai.saman.app",
                    "verification_token": "any_tok",
                    "user_id": "hacker@saman.ai",
                },
            )
            self.assertEqual(resp.status_code, 403)
            self.assertEqual(resp.json()["detail"]["code"], "USER_IDENTITY_MISMATCH")
        app.dependency_overrides.clear()

    def test_api_restore_same_account_success(self):
        """API: Restore on same account returns 200 OK with confirmed status."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        tx = VerifiedProviderTransaction(
            provider=self.provider,
            environment=self.environment,
            app_id=self.app_id,
            product_id="saman_tier_pro_monthly",
            transaction_id="tx_api_rest_1",
            original_transaction_id="orig_api_rest_1",
            verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
            purchase_date=t0,
            expires_date=t0 + timedelta(days=30),
            raw_payload_hash=hash_sensitive_payload("tx_api_rest_1"),
        )
        self.adapter.register_verified_token("tok_api_1", tx)

        app.dependency_overrides[verify_token] = lambda: "karen@saman.ai"
        from unittest.mock import patch
        with patch("backend.routers.revenue.get_payment_settlement_service", return_value=self.settlement):
            resp = self.client.post(
                "/api/revenue/purchases/restore",
                json={
                    "provider": "apple_app_store",
                    "environment": "sandbox",
                    "app_id": "ai.saman.app",
                    "verification_token": "tok_api_1",
                },
            )
            self.assertEqual(resp.status_code, 200)
            data = resp.json()
            self.assertEqual(data["outcome"], "confirmed")
            self.assertEqual(data["user_id"], "karen@saman.ai")
            self.assertEqual(data["tier"], "pro")
            self.assertEqual(data["ownership_status"], "first_owner_proposed")
            self.assertTrue(data["is_active_subscription"])
        app.dependency_overrides.clear()

    def test_crash_recovery_resumes_incomplete_lifecycle_event(self):
        """Recovery: reconcile_incomplete_payment_events resumes received event and creates projection."""
        t0 = datetime(2026, 11, 1, 12, 0, 0, tzinfo=timezone.utc)
        snapshot = {
            "user_id": "leo@saman.ai",
            "provider": self.provider.value,
            "environment": self.environment.value,
            "app_id": self.app_id,
            "product_id": "saman_tier_pro_monthly",
            "transaction_id": "tx_crash_1",
            "original_transaction_id": "orig_crash_1",
            "verification_status": ProviderVerificationStatus.VERIFIED_ACTIVE.value,
            "purchase_date": t0,
            "expires_date": t0 + timedelta(days=30),
            "raw_payload_hash": hash_sensitive_payload("tx_crash_1"),
            "event_timestamp": t0,
            "mapping": self.mapping.model_dump(),
        }

        # Simulate system crash right after writing WAL event
        self.db[COLL_PROVIDER_EVENTS].insert_one({
            "event_id": "evt_crash_wal_1",
            "provider": self.provider.value,
            "environment": self.environment.value,
            "event_type": "initial_purchase",
            "processing_status": "received",
            "projection_snapshot": snapshot,
            "received_at": t0,
            "processed_at": None,
        })

        rec_res = self.settlement.reconcile_incomplete_payment_events(as_of=t0 + timedelta(minutes=5))
        self.assertEqual(rec_res["recovered"], 1)

        # Check event transitioned to processed
        evt_doc = self.db._collections[COLL_PROVIDER_EVENTS].find_one({"event_id": "evt_crash_wal_1"})
        self.assertEqual(evt_doc["processing_status"], "processed")

        # Check subscription was projected
        sub = self.db._collections[COLL_SUBSCRIPTIONS].find_one({"subscription_id": "sub_apple_app_store_sandbox_orig_crash_1"})
        self.assertIsNotNone(sub)
        self.assertEqual(sub["user_id"], "leo@saman.ai")


if __name__ == "__main__":
    unittest.main()
