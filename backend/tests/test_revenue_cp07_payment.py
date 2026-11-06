"""
Tests for CP-07 Payment Integration Foundation, Webhook Boundary, Crash Recovery,
and CP-06A Verification Closure (Backend).
"""

from datetime import datetime, timezone, timedelta
import json
import os
import unittest
from unittest.mock import patch
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
    MembershipTier,
)
from backend.app.database_revenue import (
    COLL_PROVIDER_EVENTS,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_SUBSCRIPTIONS,
    COLL_ENTITLEMENT_GRANTS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_FOOD_ANALYSIS_IDEMPOTENCY,
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
from backend.app.services.revenue_guard import (
    orchestrate_nutrition_analysis,
    compute_nutrition_request_hash,
)
from backend.tests.test_revenue_entitlement_quota import MockDatabase as FakeDatabase, MockCollection as FakeCollection


class FakeVerifiedPaymentAdapter(IPaymentProviderAdapter):
    """
    Deterministic fake provider adapter for isolated CP-07 contract tests.
    Simulates cryptographic/server-to-server verification without external API calls.
    Never trusts client-supplied tier/price/expiry.
    """

    def __init__(
        self,
        provider: PaymentProviderName = PaymentProviderName.APPLE_APP_STORE,
        configured: bool = True,
        webhook_auth_token: str = "valid-jws-cert-chain",
    ):
        self._provider = provider
        self._configured = configured
        self._webhook_auth_token = webhook_auth_token
        self.token_registry: Dict[str, VerifiedProviderTransaction] = {}
        self.verify_calls = 0

    @property
    def provider_name(self) -> PaymentProviderName:
        return self._provider

    def is_configured(self) -> bool:
        return self._configured

    def register_token(self, token: str, tx: VerifiedProviderTransaction) -> None:
        self.token_registry[token] = tx

    def verify_purchase(
        self,
        request: PurchaseVerificationRequest,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedProviderTransaction:
        self.verify_calls += 1
        tx = self.token_registry.get(request.verification_token)
        if tx is None:
            return VerifiedProviderTransaction(
                provider=self._provider,
                environment=request.environment,
                app_id=request.app_id,
                product_id=request.product_id,
                transaction_id=request.transaction_id or "tx_invalid",
                original_transaction_id=request.original_transaction_id or "orig_invalid",
                verification_status=ProviderVerificationStatus.INVALID,
                purchase_date=datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc),
                expires_date=datetime(2026, 11, 29, 12, 0, tzinfo=timezone.utc),
                raw_payload_hash=hash_sensitive_payload(request.verification_token),
                error_code="INVALID_RECEIPT_PROOF",
                error_message="Verification token was rejected by provider.",
            )
        return tx

    def verify_and_parse_webhook(
        self,
        headers: Dict[str, str],
        raw_body: bytes,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedWebhookEvent:
        auth_header = headers.get("X-Provider-Auth") or headers.get("x-provider-auth")
        if auth_header != self._webhook_auth_token:
            raise WebhookVerificationError(
                code="WEBHOOK_AUTH_INVALID",
                message="Invalid provider webhook authentication proof.",
                http_status=401,
            )
        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except Exception as exc:
            raise WebhookVerificationError(
                code="WEBHOOK_SCHEMA_INVALID",
                message=f"Invalid JSON payload: {exc}",
                http_status=400,
            )

        required_fields = [
            "event_id",
            "event_type",
            "environment",
            "app_id",
            "product_id",
            "transaction_id",
            "original_transaction_id",
            "verification_status",
            "event_timestamp",
            "purchase_date",
            "expires_date",
        ]
        for field in required_fields:
            if field not in payload:
                raise WebhookVerificationError(
                    code="WEBHOOK_SCHEMA_INVALID",
                    message=f"Missing required field '{field}' in webhook payload.",
                    http_status=422,
                )

        env = PaymentEnvironment(payload["environment"])
        if env != expected_environment:
            raise ProductMappingRejectedError(
                code="PAYMENT_ENVIRONMENT_MISMATCH",
                message=f"Webhook environment '{env.value}' mismatches server '{expected_environment.value}'.",
                http_status=422,
            )

        tx = VerifiedProviderTransaction(
            provider=self._provider,
            environment=env,
            app_id=payload["app_id"],
            product_id=payload["product_id"],
            transaction_id=payload["transaction_id"],
            original_transaction_id=payload["original_transaction_id"],
            verification_status=ProviderVerificationStatus(payload["verification_status"]),
            purchase_date=datetime.fromisoformat(payload["purchase_date"]),
            expires_date=datetime.fromisoformat(payload["expires_date"]),
            provider_event_id=payload["event_id"],
            raw_payload_hash=hash_sensitive_payload(raw_body.decode("utf-8")),
        )
        return VerifiedWebhookEvent(
            event_id=payload["event_id"],
            provider=self._provider,
            environment=env,
            event_type=payload["event_type"],
            event_timestamp=datetime.fromisoformat(payload["event_timestamp"]),
            user_id=payload.get("user_id"),
            transaction=tx,
            raw_payload_hash=tx.raw_payload_hash,
        )


class CrashAfterEventPersistenceCollection(FakeCollection):
    """Simulates a crash or storage failure during subscription/entitlement projection."""

    def __init__(self, name: str, should_fail: bool = True):
        super().__init__(name)
        self.should_fail = should_fail

    def insert_one(self, doc: Dict[str, Any]):
        if self.should_fail:
            raise RuntimeError(f"Simulated crash/storage failure writing to {self.name}")
        return super().insert_one(doc)


def build_sandbox_registry(enabled: bool = True) -> ProductMappingRegistry:
    plus_mapping = StoreProductMapping(
        provider=PaymentProviderName.APPLE_APP_STORE,
        environment=PaymentEnvironment.SANDBOX,
        app_id="com.saman.health.ios",
        product_id="saman_plus_monthly_sandbox",
        plan_id="plan_plus",
        price_id="price_plus_monthly",
        tier=MembershipTier.PLUS,
        catalog_version="v1.0-preview",
        amount_cents=999,
        currency="USD",
        benefit_ids=[
            "ai.nutrition_gemini",
            "ai.Food_logging",
            "workout.adaptive_plan",
        ],
        quota_limits={"ai.nutrition_gemini": 100},
        enabled=enabled,
    )
    pro_mapping = StoreProductMapping(
        provider=PaymentProviderName.APPLE_APP_STORE,
        environment=PaymentEnvironment.SANDBOX,
        app_id="com.saman.health.ios",
        product_id="saman_pro_monthly_sandbox",
        plan_id="plan_pro",
        price_id="price_pro_monthly",
        tier=MembershipTier.PRO,
        catalog_version="v1.0-preview",
        amount_cents=1999,
        currency="USD",
        benefit_ids=[
            "ai.nutrition_gemini",
            "ai.Food_logging",
            "workout.adaptive_plan",
            "analytics.deep_insights",
        ],
        quota_limits={"ai.nutrition_gemini": 300},
        enabled=enabled,
    )
    return ProductMappingRegistry(
        mappings=[plus_mapping, pro_mapping],
        expected_environment=PaymentEnvironment.SANDBOX,
        allowed_app_ids=["com.saman.health.ios"],
    )


class TestCP06AClosureBackend(unittest.IsolatedAsyncioTestCase):
    """Section 5.A: Close CP-06A verification on backend routes, lookup, and payload identity."""

    def setUp(self):
        self.now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)

    def test_static_lookup_route_not_captured_by_dynamic_operation_id_route(self):
        """
        1. Static lookup route (/api/revenue/operations/lookup) must NOT be shadowed
           by /api/revenue/operations/{operation_id}.
        """
        fake_db = FakeDatabase()
        fake_db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_real_123",
            "user_id": "alice@saman.ai",
            "benefit_id": "ai.nutrition_gemini",
            "idempotency_key": "idem_static_route_test",
            "client_request_id": "req_static_route_test",
            "units": 1,
            "status": "committed",
            "dispatched": True,
            "created_at": self.now,
            "updated_at": self.now,
        })
        fake_db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].insert_one({
            "user_id": "alice@saman.ai",
            "client_request_id": "req_static_route_test",
            "response_payload": {"food_name": "Pho Bo", "nutrition": {"calories": 450}},
        })

        app.dependency_overrides[verify_token] = lambda: "alice@saman.ai"
        from backend.app.services import quota_service
        orig_get_db = quota_service.QuotaService._get_db
        quota_service.QuotaService._get_db = lambda self_svc: fake_db
        try:
            client = TestClient(app)
            resp = client.get(
                "/api/revenue/operations/lookup",
                params={
                    "idempotency_key": "idem_static_route_test",
                    "benefit_id": "ai.nutrition_gemini",
                },
            )
            self.assertEqual(resp.status_code, 200)
            body = resp.json()
            self.assertEqual(body["operation_id"], "op_real_123")
            self.assertEqual(body["status"], "committed")
            self.assertEqual(body["cached_payload"]["food_name"], "Pho Bo")
            self.assertEqual(body["cached_response"]["food_name"], "Pho Bo")
        finally:
            quota_service.QuotaService._get_db = orig_get_db
            app.dependency_overrides.clear()

    def test_lookup_returns_503_when_database_unavailable_not_404(self):
        """
        Lookup failure due to DB unavailability must return 503 Service Unavailable,
        never a false 404 Not Found that would trick clients into redispatching inference.
        """
        app.dependency_overrides[verify_token] = lambda: "alice@saman.ai"
        from backend.app.services import quota_service
        orig_get_db = quota_service.QuotaService._get_db
        quota_service.QuotaService._get_db = lambda self_svc: None
        try:
            client = TestClient(app)
            resp = client.get(
                "/api/revenue/operations/lookup",
                params={"idempotency_key": "idem_any"},
            )
            self.assertEqual(resp.status_code, 503)
        finally:
            quota_service.QuotaService._get_db = orig_get_db
            app.dependency_overrides.clear()

    async def test_pending_and_failed_unknown_operations_do_not_redispatch_inference(self):
        """
        2. Pending (reserved/executing) or failed_unknown operation state must NOT
           redispatch Gemini inference when retried with the same idempotency identity.
        """
        fake_db = FakeDatabase()
        fake_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_plus_1",
            "user_id": "alice@saman.ai",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "source_type": "subscription",
            "valid_from": self.now - timedelta(days=1),
            "valid_until": self.now + timedelta(days=29),
        })

        req_hash = compute_nutrition_request_hash(
            image_bytes=b"img_bytes_1",
            grams=100.0,
            mode="advanced",
            mime_type="image/jpeg",
        )
        fake_db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_inflight_1",
            "user_id": "alice@saman.ai",
            "benefit_id": "ai.nutrition_gemini",
            "bucket_key": "2026-10",
            "idempotency_key": "idem_inflight_1",
            "client_request_id": "req_inflight_1",
            "request_hash": req_hash,
            "units": 1,
            "status": "executing",
            "dispatched": True,
            "lease_token": "lease_1",
            "lease_expires_at": self.now + timedelta(minutes=5),
            "created_at": self.now,
            "updated_at": self.now,
        })

        dispatch_count = 0

        async def fake_gemini(image_bytes: bytes, mime_type: str, grams: float):
            nonlocal dispatch_count
            dispatch_count += 1
            return {"food_name": "Should Not Run"}

        from fastapi import HTTPException
        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "alice@saman.ai",
        }):
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"img_bytes_1",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="alice@saman.ai",
                    client_request_id="req_inflight_1",
                    idempotency_key="idem_inflight_1",
                    mode="advanced",
                    provider_callback=fake_gemini,
                    as_of=self.now,
                    db=fake_db,
                )
            self.assertEqual(ctx.exception.status_code, 409)
            self.assertEqual(dispatch_count, 0)

            # Transition operation to failed_unknown (e.g. after timeout) and retry:
            fake_db[COLL_USAGE_OPERATIONS].update_one(
                {"operation_id": "op_inflight_1"},
                {"$set": {"status": "failed_unknown"}},
            )
            with self.assertRaises(HTTPException) as ctx2:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"img_bytes_1",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="alice@saman.ai",
                    client_request_id="req_inflight_1",
                    idempotency_key="idem_inflight_1",
                    mode="advanced",
                    provider_callback=fake_gemini,
                    as_of=self.now,
                    db=fake_db,
                )
            self.assertEqual(ctx2.exception.status_code, 409)
            self.assertEqual(dispatch_count, 0)

    async def test_payload_identity_includes_mode_grams_mime_and_image_bytes(self):
        """
        3. Payload identity (request_hash) must distinguish mode, grams, mime_type,
           and image_bytes so reusing an idempotency key with different parameters
           is rejected with 409 Conflict instead of returning a wrong cached result.
        """
        h_std = compute_nutrition_request_hash(b"photo1", 100.0, "standard", "image/jpeg")
        h_adv = compute_nutrition_request_hash(b"photo1", 100.0, "advanced", "image/jpeg")
        h_250g = compute_nutrition_request_hash(b"photo1", 250.0, "advanced", "image/jpeg")
        h_png = compute_nutrition_request_hash(b"photo1", 100.0, "advanced", "image/png")
        h_photo2 = compute_nutrition_request_hash(b"photo2", 100.0, "advanced", "image/jpeg")

        self.assertEqual(len({h_std, h_adv, h_250g, h_png, h_photo2}), 5)

        fake_db = FakeDatabase()
        fake_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_plus_1",
            "user_id": "alice@saman.ai",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "source_type": "subscription",
            "valid_from": self.now - timedelta(days=1),
            "valid_until": self.now + timedelta(days=29),
        })

        async def fake_provider_100(image_bytes: bytes, mime_type: str, grams: float):
            return {"food_name": "Salad 100g", "nutrition": {"calories": 120}}

        async def fake_provider_250(image_bytes: bytes, mime_type: str, grams: float):
            return {"food_name": "Salad 250g", "nutrition": {"calories": 300}}

        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "alice@saman.ai",
        }):
            res1 = await orchestrate_nutrition_analysis(
                image_bytes=b"photo1",
                mime_type="image/jpeg",
                grams=100.0,
                email="alice@saman.ai",
                client_request_id="req_same_1",
                idempotency_key="idem_same_1",
                mode="advanced",
                provider_callback=fake_provider_100,
                as_of=self.now,
                db=fake_db,
            )
            self.assertEqual(res1["food_name"], "Salad 100g")

            # Second call reusing client_request_id/idempotency_key but changing grams to 250.0 -> 409 Conflict
            from fastapi import HTTPException
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"photo1",
                    mime_type="image/jpeg",
                    grams=250.0,
                    email="alice@saman.ai",
                    client_request_id="req_same_1",
                    idempotency_key="idem_same_1",
                    mode="advanced",
                    provider_callback=fake_provider_250,
                    as_of=self.now,
                    db=fake_db,
                )
            self.assertEqual(ctx.exception.status_code, 409)


class TestCP07PaymentBoundaryAndWebhook(unittest.TestCase):
    """Section 5.C, 5.D & 5.F: Payment Verification, Mapping, Idempotency, Crash Recovery, and Isolation."""

    def setUp(self):
        self.now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
        self.db = FakeDatabase()
        self.adapter = FakeVerifiedPaymentAdapter(
            provider=PaymentProviderName.APPLE_APP_STORE,
            configured=True,
        )
        self.registry = build_sandbox_registry(enabled=True)
        self.settlement = PaymentSettlementService(
            db=self.db,
            adapter=self.adapter,
            mapping_registry=self.registry,
        )
        self.webhook_service = PaymentWebhookIngestionService(
            settlement_service=self.settlement,
            adapter=self.adapter,
            mapping_registry=self.registry,
        )

    def _make_verified_tx(
        self,
        tx_id: str = "tx_1001",
        orig_tx_id: str = "orig_1001",
        product_id: str = "saman_plus_monthly_sandbox",
        app_id: str = "com.saman.health.ios",
        env: PaymentEnvironment = PaymentEnvironment.SANDBOX,
        status: ProviderVerificationStatus = ProviderVerificationStatus.VERIFIED_ACTIVE,
    ) -> VerifiedProviderTransaction:
        return VerifiedProviderTransaction(
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=env,
            app_id=app_id,
            product_id=product_id,
            transaction_id=tx_id,
            original_transaction_id=orig_tx_id,
            verification_status=status,
            purchase_date=self.now - timedelta(minutes=5),
            expires_date=self.now + timedelta(days=30),
            raw_payload_hash=hash_sensitive_payload(f"receipt_{tx_id}"),
        )

    def test_1_unverified_client_payload_and_spoofed_fields_never_grant_entitlement(self):
        """
        Scenario 1:
        - Missing or invalid verification token is rejected (400).
        - Client-supplied spoofed user_id is rejected (403).
        - Client-supplied untrusted tier ('pro'), amount_cents (0), or expires_date (year 2099)
          are completely ignored; only the verified provider product mapping ('plus') is granted.
        """
        # 1a. Invalid token rejected
        req_invalid = PurchaseVerificationRequest(
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=PaymentEnvironment.SANDBOX,
            app_id="com.saman.health.ios",
            product_id="saman_plus_monthly_sandbox",
            verification_token="forged_client_token",
            tier=MembershipTier.PRO,
            amount_cents=0,
        )
        with self.assertRaises(UnverifiedPurchasePayloadError):
            self.settlement.verify_and_settle_purchase(
                authenticated_user_id="user_a@saman.ai",
                request=req_invalid,
                as_of=self.now,
            )
        self.assertEqual(len(self.db[COLL_SUBSCRIPTIONS].documents), 0)
        self.assertEqual(len(self.db[COLL_ENTITLEMENT_GRANTS].documents), 0)

        # 1b. Client attempting to spoof another user_id is rejected with 403
        self.adapter.register_token("valid_tok_1", self._make_verified_tx())
        req_spoof_user = PurchaseVerificationRequest(
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=PaymentEnvironment.SANDBOX,
            app_id="com.saman.health.ios",
            product_id="saman_plus_monthly_sandbox",
            verification_token="valid_tok_1",
            user_id="victim_user@saman.ai",
        )
        with self.assertRaises(Exception) as ctx:
            self.settlement.verify_and_settle_purchase(
                authenticated_user_id="attacker@saman.ai",
                request=req_spoof_user,
                as_of=self.now,
            )
        self.assertEqual(getattr(ctx.exception, "code", None), "USER_IDENTITY_MISMATCH")
        self.assertEqual(len(self.db[COLL_SUBSCRIPTIONS].documents), 0)

        # 1c. Client claims tier=PRO and expires_date=2099 on a PLUS token -> only PLUS is granted
        req_spoof_tier = PurchaseVerificationRequest(
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=PaymentEnvironment.SANDBOX,
            app_id="com.saman.health.ios",
            product_id="saman_plus_monthly_sandbox",
            verification_token="valid_tok_1",
            tier=MembershipTier.PRO,
            amount_cents=1,
            expires_date=datetime(2099, 1, 1, tzinfo=timezone.utc),
        )
        resp = self.settlement.verify_and_settle_purchase(
            authenticated_user_id="user_a@saman.ai",
            request=req_spoof_tier,
            as_of=self.now,
        )
        self.assertEqual(resp.outcome, PurchaseVerificationOutcomeStatus.CONFIRMED)
        self.assertEqual(resp.tier, MembershipTier.PLUS)
        sub_doc = self.db[COLL_SUBSCRIPTIONS].find_one({"user_id": "user_a@saman.ai"})
        self.assertEqual(sub_doc["tier"], "plus")
        self.assertEqual(sub_doc["current_period_end"], self.now + timedelta(days=30))

    def test_2_unknown_product_wrong_app_and_wrong_environment_are_rejected(self):
        """
        Scenario 2:
        - Unknown product_id -> 422 UNKNOWN_STORE_PRODUCT
        - Wrong app_id -> 422 PAYMENT_APP_ID_MISMATCH
        - Wrong environment (production receipt sent to sandbox server) -> 422 PAYMENT_ENVIRONMENT_MISMATCH
        None of these may create subscriptions or entitlement grants.
        """
        # Unknown product
        self.adapter.register_token(
            "tok_unknown_prod",
            self._make_verified_tx(tx_id="tx_u1", product_id="arbitrary_hacker_sku"),
        )
        with self.assertRaises(ProductMappingRejectedError) as ctx_prod:
            self.settlement.verify_and_settle_purchase(
                authenticated_user_id="user_a@saman.ai",
                request=PurchaseVerificationRequest(
                    provider=PaymentProviderName.APPLE_APP_STORE,
                    environment=PaymentEnvironment.SANDBOX,
                    app_id="com.saman.health.ios",
                    product_id="arbitrary_hacker_sku",
                    verification_token="tok_unknown_prod",
                ),
                as_of=self.now,
            )
        self.assertEqual(ctx_prod.exception.code, "UNKNOWN_STORE_PRODUCT")

        # Wrong app_id
        self.adapter.register_token(
            "tok_wrong_app",
            self._make_verified_tx(tx_id="tx_u2", app_id="com.other.clone.app"),
        )
        with self.assertRaises(ProductMappingRejectedError) as ctx_app:
            self.settlement.verify_and_settle_purchase(
                authenticated_user_id="user_a@saman.ai",
                request=PurchaseVerificationRequest(
                    provider=PaymentProviderName.APPLE_APP_STORE,
                    environment=PaymentEnvironment.SANDBOX,
                    app_id="com.other.clone.app",
                    product_id="saman_plus_monthly_sandbox",
                    verification_token="tok_wrong_app",
                ),
                as_of=self.now,
            )
        self.assertEqual(ctx_app.exception.code, "PAYMENT_APP_ID_MISMATCH")

        # Wrong environment (Production receipt on Sandbox server)
        self.adapter.register_token(
            "tok_wrong_env",
            self._make_verified_tx(tx_id="tx_u3", env=PaymentEnvironment.PRODUCTION),
        )
        with self.assertRaises(ProductMappingRejectedError) as ctx_env:
            self.settlement.verify_and_settle_purchase(
                authenticated_user_id="user_a@saman.ai",
                request=PurchaseVerificationRequest(
                    provider=PaymentProviderName.APPLE_APP_STORE,
                    environment=PaymentEnvironment.PRODUCTION,
                    app_id="com.saman.health.ios",
                    product_id="saman_plus_monthly_sandbox",
                    verification_token="tok_wrong_env",
                ),
                as_of=self.now,
            )
        self.assertEqual(ctx_env.exception.code, "PAYMENT_ENVIRONMENT_MISMATCH")
        self.assertEqual(len(self.db[COLL_SUBSCRIPTIONS].documents), 0)
        self.assertEqual(len(self.db[COLL_ENTITLEMENT_GRANTS].documents), 0)

    def test_3_duplicate_and_concurrent_events_do_not_double_grant_or_reset_consumed_quota(self):
        """
        Scenario 3:
        - Duplicate verify calls and duplicate webhook deliveries with the same transaction/event
          are idempotent (`duplicate_ignored=True`).
        - Existing consumed_units and reserved_units in UsageBucket are preserved when upgrading
          limit_units from 30 -> 100.
        """
        # Seed existing Free usage bucket with 7 consumed and 1 reserved unit
        from backend.app.services.quota_service import QuotaService
        q_svc = QuotaService(db=self.db)
        w_start, w_end, b_key = q_svc._get_window_bounds(self.now)
        self.db[COLL_USAGE_BUCKETS].insert_one({
            "bucket_id": "bkt_initial",
            "user_id": "user_a@saman.ai",
            "benefit_id": "ai.nutrition_gemini",
            "bucket_key": b_key,
            "window_start": w_start,
            "window_end": w_end,
            "limit_units": 30,
            "consumed_units": 7,
            "reserved_units": 1,
            "reset_at": w_end,
        })

        self.adapter.register_token("tok_dup_1", self._make_verified_tx(tx_id="tx_dup_1", orig_tx_id="orig_dup_1"))
        req = PurchaseVerificationRequest(
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=PaymentEnvironment.SANDBOX,
            app_id="com.saman.health.ios",
            product_id="saman_plus_monthly_sandbox",
            verification_token="tok_dup_1",
        )

        first = self.settlement.verify_and_settle_purchase("user_a@saman.ai", req, as_of=self.now)
        self.assertFalse(first.duplicate_ignored)
        self.assertEqual(first.outcome, PurchaseVerificationOutcomeStatus.CONFIRMED)

        # Second identical verification call
        second = self.settlement.verify_and_settle_purchase("user_a@saman.ai", req, as_of=self.now)
        self.assertTrue(second.duplicate_ignored)
        self.assertEqual(second.outcome, PurchaseVerificationOutcomeStatus.CONFIRMED)

        # Webhook delivering the same transaction
        webhook_body = json.dumps({
            "event_id": "evt_webhook_dup_1",
            "event_type": "SUBSCRIBED",
            "environment": "sandbox",
            "app_id": "com.saman.health.ios",
            "product_id": "saman_plus_monthly_sandbox",
            "transaction_id": "tx_dup_1",
            "original_transaction_id": "orig_dup_1",
            "verification_status": "verified_active",
            "user_id": "user_a@saman.ai",
            "event_timestamp": self.now.isoformat(),
            "purchase_date": (self.now - timedelta(minutes=5)).isoformat(),
            "expires_date": (self.now + timedelta(days=30)).isoformat(),
        }).encode("utf-8")

        wh_res1 = self.webhook_service.ingest_webhook(
            headers={"X-Provider-Auth": "valid-jws-cert-chain"},
            raw_body=webhook_body,
            expected_app_id="com.saman.health.ios",
            as_of=self.now,
        )
        self.assertTrue(wh_res1["acknowledged"])

        wh_res2 = self.webhook_service.ingest_webhook(
            headers={"X-Provider-Auth": "valid-jws-cert-chain"},
            raw_body=webhook_body,
            expected_app_id="com.saman.health.ios",
            as_of=self.now,
        )
        self.assertTrue(wh_res2["duplicate_ignored"])

        # Verify exactly 1 subscription, 3 grants, and preserved bucket usage
        self.assertEqual(len(self.db[COLL_SUBSCRIPTIONS].documents), 1)
        self.assertEqual(len(self.db[COLL_ENTITLEMENT_GRANTS].documents), 3)
        b_doc = self.db[COLL_USAGE_BUCKETS].find_one({"user_id": "user_a@saman.ai", "bucket_key": b_key})
        self.assertEqual(b_doc["limit_units"], 100)
        self.assertEqual(b_doc["consumed_units"], 7)
        self.assertEqual(b_doc["reserved_units"], 1)

    def test_4_crash_after_event_persistence_before_projection_has_full_recovery(self):
        """
        Scenario 4 & 5:
        - Crash/storage error occurs AFTER ProviderEvent is durably written ('received')
          but BEFORE Subscription and EntitlementGrant projection completes.
        - ProviderEvent transitions to 'failed' (not 'processed') and raises 503 PaymentStorageError.
        - Running `reconcile_incomplete_payment_events()` (or retrying the request) recovers
          the incomplete event from its durable `projection_snapshot`, completes Subscription,
          EntitlementGrant, and UsageBucket projection, and marks the event 'processed'.
        """
        crashing_subs = CrashAfterEventPersistenceCollection(COLL_SUBSCRIPTIONS, should_fail=True)
        self.db._collections[COLL_SUBSCRIPTIONS] = crashing_subs

        self.adapter.register_token("tok_crash_1", self._make_verified_tx(tx_id="tx_crash_1", orig_tx_id="orig_crash_1"))
        req = PurchaseVerificationRequest(
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=PaymentEnvironment.SANDBOX,
            app_id="com.saman.health.ios",
            product_id="saman_plus_monthly_sandbox",
            verification_token="tok_crash_1",
        )

        # First attempt crashes mid-projection after event persistence
        with self.assertRaises(PaymentStorageError):
            self.settlement.verify_and_settle_purchase("user_crash@saman.ai", req, as_of=self.now)

        # Verify durable ProviderEvent exists in 'failed' state, while Subscription is still empty
        self.assertEqual(len(self.db[COLL_PROVIDER_EVENTS].documents), 1)
        evt_doc = self.db[COLL_PROVIDER_EVENTS].documents[0]
        self.assertEqual(evt_doc["processing_status"], "failed")
        self.assertIsNotNone(evt_doc["projection_snapshot"])
        self.assertEqual(len(self.db[COLL_SUBSCRIPTIONS].documents), 0)
        self.assertEqual(len(self.db[COLL_ENTITLEMENT_GRANTS].documents), 0)

        # Restore healthy storage and run crash recovery reconciliation
        crashing_subs.should_fail = False
        rec_summary = self.settlement.reconcile_incomplete_payment_events(as_of=self.now)
        self.assertEqual(rec_summary["scanned"], 1)
        self.assertEqual(rec_summary["recovered"], 1)
        self.assertEqual(rec_summary["failed"], 0)

        # Verify event is now 'processed' and all projections are complete
        evt_after = self.db[COLL_PROVIDER_EVENTS].documents[0]
        self.assertEqual(evt_after["processing_status"], "processed")
        sub_after = self.db[COLL_SUBSCRIPTIONS].find_one({"user_id": "user_crash@saman.ai"})
        self.assertIsNotNone(sub_after)
        self.assertEqual(sub_after["tier"], "plus")
        self.assertEqual(sub_after["status"], "active")
        grants_after = self.db[COLL_ENTITLEMENT_GRANTS].find({"user_id": "user_crash@saman.ai", "status": "granted"})
        self.assertEqual(len(grants_after), 3)

    def test_5_webhook_storage_failure_does_not_acknowledge_success(self):
        """
        Section 5.D & 5.F Scenario 5:
        - When storage fails during webhook event persistence or projection,
          `ingest_webhook` raises PaymentStorageError (503) and NEVER returns acknowledged=True.
        - When the provider retries webhook delivery after storage recovers, it succeeds cleanly.
        """
        crashing_subs = CrashAfterEventPersistenceCollection(COLL_SUBSCRIPTIONS, should_fail=True)
        self.db._collections[COLL_SUBSCRIPTIONS] = crashing_subs

        webhook_body = json.dumps({
            "event_id": "evt_wh_retry_1",
            "event_type": "SUBSCRIBED",
            "environment": "sandbox",
            "app_id": "com.saman.health.ios",
            "product_id": "saman_pro_monthly_sandbox",
            "transaction_id": "tx_wh_retry_1",
            "original_transaction_id": "orig_wh_retry_1",
            "verification_status": "verified_active",
            "user_id": "user_wh@saman.ai",
            "event_timestamp": self.now.isoformat(),
            "purchase_date": (self.now - timedelta(minutes=5)).isoformat(),
            "expires_date": (self.now + timedelta(days=30)).isoformat(),
        }).encode("utf-8")

        with self.assertRaises(PaymentStorageError):
            self.webhook_service.ingest_webhook(
                headers={"X-Provider-Auth": "valid-jws-cert-chain"},
                raw_body=webhook_body,
                expected_app_id="com.saman.health.ios",
                as_of=self.now,
            )

        # Restore storage and retry webhook delivery
        crashing_subs.should_fail = False
        ack = self.webhook_service.ingest_webhook(
            headers={"X-Provider-Auth": "valid-jws-cert-chain"},
            raw_body=webhook_body,
            expected_app_id="com.saman.health.ios",
            as_of=self.now,
        )
        self.assertTrue(ack["acknowledged"])
        self.assertEqual(ack["outcome"], "confirmed")
        sub = self.db[COLL_SUBSCRIPTIONS].find_one({"user_id": "user_wh@saman.ai"})
        self.assertEqual(sub["tier"], "pro")

    def test_6_pending_and_canceled_transactions_never_grant_entitlement(self):
        """
        Scenario 6:
        - Provider verification status PENDING or CANCELED returns corresponding outcome
          and does NOT create active subscriptions or entitlement grants.
        """
        self.adapter.register_token(
            "tok_pending",
            self._make_verified_tx(tx_id="tx_p1", status=ProviderVerificationStatus.PENDING),
        )
        self.adapter.register_token(
            "tok_canceled",
            self._make_verified_tx(tx_id="tx_c1", status=ProviderVerificationStatus.CANCELED),
        )

        res_pending = self.settlement.verify_and_settle_purchase(
            "user_p@saman.ai",
            PurchaseVerificationRequest(
                provider=PaymentProviderName.APPLE_APP_STORE,
                environment=PaymentEnvironment.SANDBOX,
                app_id="com.saman.health.ios",
                product_id="saman_plus_monthly_sandbox",
                verification_token="tok_pending",
            ),
            as_of=self.now,
        )
        self.assertEqual(res_pending.outcome, PurchaseVerificationOutcomeStatus.PENDING)
        self.assertFalse(res_pending.is_active_subscription)

        res_canceled = self.settlement.verify_and_settle_purchase(
            "user_p@saman.ai",
            PurchaseVerificationRequest(
                provider=PaymentProviderName.APPLE_APP_STORE,
                environment=PaymentEnvironment.SANDBOX,
                app_id="com.saman.health.ios",
                product_id="saman_plus_monthly_sandbox",
                verification_token="tok_canceled",
            ),
            as_of=self.now,
        )
        self.assertEqual(res_canceled.outcome, PurchaseVerificationOutcomeStatus.CANCELED)
        self.assertFalse(res_canceled.is_active_subscription)
        self.assertEqual(len(self.db[COLL_SUBSCRIPTIONS].documents), 0)
        self.assertEqual(len(self.db[COLL_ENTITLEMENT_GRANTS].documents), 0)

    def test_7_receipt_ownership_conflict_blocks_cross_account_transfer(self):
        """
        Scenario 7 & Invariant 7/9:
        - Once `original_transaction_id` is bound to `user_a@saman.ai`, if `user_b@saman.ai`
          attempts to verify or replay the same receipt (e.g., after an account switch on device),
          the backend refuses silent receipt transfer with 409 RECEIPT_OWNERSHIP_CONFLICT.
        """
        self.adapter.register_token(
            "tok_shared_receipt",
            self._make_verified_tx(tx_id="tx_own_1", orig_tx_id="orig_own_1"),
        )
        req = PurchaseVerificationRequest(
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=PaymentEnvironment.SANDBOX,
            app_id="com.saman.health.ios",
            product_id="saman_plus_monthly_sandbox",
            verification_token="tok_shared_receipt",
        )

        # User A binds the receipt
        res_a = self.settlement.verify_and_settle_purchase("user_a@saman.ai", req, as_of=self.now)
        self.assertEqual(res_a.outcome, PurchaseVerificationOutcomeStatus.CONFIRMED)

        # User B attempts to submit the same receipt -> 409 RECEIPT_OWNERSHIP_CONFLICT
        with self.assertRaises(ReceiptOwnershipConflictError) as ctx:
            self.settlement.verify_and_settle_purchase("user_b@saman.ai", req, as_of=self.now)
        self.assertEqual(ctx.exception.http_status, 409)
        self.assertIsNone(self.db[COLL_SUBSCRIPTIONS].find_one({"user_id": "user_b@saman.ai"}))

    def test_8_missing_config_or_disabled_mapping_returns_unavailable_503(self):
        """
        Scenario 8:
        - Default `UnconfiguredPaymentProviderAdapter` or disabled `StoreProductMapping`
          returns 503 `PAYMENT_CONFIG_NOT_READY` (never fake success).
        """
        unconfigured_svc = PaymentSettlementService(
            db=self.db,
            adapter=UnconfiguredPaymentProviderAdapter(),
            mapping_registry=ProductMappingRegistry(),
        )
        with self.assertRaises(PaymentConfigurationNotReadyError) as ctx:
            unconfigured_svc.verify_and_settle_purchase(
                "user_a@saman.ai",
                PurchaseVerificationRequest(
                    provider=PaymentProviderName.APPLE_APP_STORE,
                    environment=PaymentEnvironment.SANDBOX,
                    app_id="com.saman.health.ios",
                    product_id="saman_plus_monthly_sandbox",
                    verification_token="any_token",
                ),
                as_of=self.now,
            )
        self.assertEqual(ctx.exception.http_status, 503)
        self.assertEqual(ctx.exception.code, "PAYMENT_CONFIG_NOT_READY")

    def test_9_purchase_verify_http_endpoint_contract(self):
        """
        Verifies the HTTP endpoint POST /api/revenue/purchases/verify:
        - Returns 503 PAYMENT_CONFIG_NOT_READY by default when unconfigured.
        - Returns 200 CONFIRMED when configured with FakeVerifiedPaymentAdapter, and
          subsequent GET /api/revenue/membership/me reflects active Plus tier and 100 quota.
        """
        real_now = datetime.now(timezone.utc)
        app.dependency_overrides[verify_token] = lambda: "endpoint_user@saman.ai"
        from backend.app.services import payment_service, entitlement_service
        orig_default = payment_service._default_settlement_service
        orig_ent_db = entitlement_service.EntitlementService._get_db
        try:
            # 1. Default unconfigured -> 503
            payment_service._default_settlement_service = PaymentSettlementService(
                db=self.db,
                adapter=UnconfiguredPaymentProviderAdapter(),
                mapping_registry=ProductMappingRegistry(),
            )
            client = TestClient(app)
            resp_503 = client.post(
                "/api/revenue/purchases/verify",
                json={
                    "provider": "apple_app_store",
                    "environment": "sandbox",
                    "app_id": "com.saman.health.ios",
                    "product_id": "saman_plus_monthly_sandbox",
                    "verification_token": "tok_http_1",
                },
            )
            self.assertEqual(resp_503.status_code, 503)
            self.assertEqual(resp_503.json()["detail"]["code"], "PAYMENT_CONFIG_NOT_READY")

            # 2. Configured fake adapter -> 200 CONFIRMED + membership/me reflects Plus & 100 quota
            self.adapter.register_token(
                "tok_http_1",
                VerifiedProviderTransaction(
                    provider=PaymentProviderName.APPLE_APP_STORE,
                    environment=PaymentEnvironment.SANDBOX,
                    app_id="com.saman.health.ios",
                    product_id="saman_plus_monthly_sandbox",
                    transaction_id="tx_http_1",
                    original_transaction_id="orig_http_1",
                    verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
                    purchase_date=real_now - timedelta(minutes=5),
                    expires_date=real_now + timedelta(days=30),
                    raw_payload_hash=hash_sensitive_payload("tok_http_1"),
                ),
            )
            payment_service._default_settlement_service = self.settlement
            entitlement_service.EntitlementService._get_db = lambda self_svc: self.db

            resp_200 = client.post(
                "/api/revenue/purchases/verify",
                json={
                    "provider": "apple_app_store",
                    "environment": "sandbox",
                    "app_id": "com.saman.health.ios",
                    "product_id": "saman_plus_monthly_sandbox",
                    "verification_token": "tok_http_1",
                },
            )
            self.assertEqual(resp_200.status_code, 200)
            data = resp_200.json()
            self.assertEqual(data["outcome"], "confirmed")
            self.assertEqual(data["tier"], "plus")
            self.assertTrue(data["is_active_subscription"])

            me_resp = client.get("/api/revenue/membership/me")
            self.assertEqual(me_resp.status_code, 200)
            me_data = me_resp.json()
            self.assertEqual(me_data["user_id"], "endpoint_user@saman.ai")
            self.assertEqual(me_data["tier"], "plus")
            self.assertTrue(me_data["is_active_subscription"])
            self.assertEqual(me_data["usage"]["ai.nutrition_gemini"]["limit_units"], 100)
        finally:
            payment_service._default_settlement_service = orig_default
            entitlement_service.EntitlementService._get_db = orig_ent_db
            app.dependency_overrides.clear()


class TestRealMongoCP07PaymentSettlement(unittest.TestCase):
    """
    Isolated real MongoDB 7.0 test (task-spawned loopback mongod on port 27098)
    verifying payment indexes, durable event persistence, and concurrent settlement idempotency.
    """

    mongod_proc = None
    mongo_client = None
    real_db = None
    mongod_available = False
    dbpath = None

    @classmethod
    def setUpClass(cls):
        import subprocess
        import shutil
        import time
        from backend.app.database_revenue import (
            ensure_revenue_indexes,
            REVENUE_INDEX_SPECIFICATIONS,
            PAYMENT_TRANSACTION_INDEX_SPECIFICATIONS,
        )

        mongod_binary = r"D:\SamanDev\tools\mongodb-cp7\mongodb-win32-x86_64-windows-7.0.14\bin\mongod.exe"
        if not os.path.exists(mongod_binary):
            return

        cls.dbpath = os.path.abspath(
            r"D:\SamanDev\runtime_evidence\saman-revenue\CP-07\20261029_134600\mongo_cp07_data"
        )
        os.makedirs(cls.dbpath, exist_ok=True)

        cmd = [
            mongod_binary,
            "--port", "27098",
            "--bind_ip", "127.0.0.1",
            "--dbpath", cls.dbpath,
            "--wiredTigerCacheSizeGB", "0.25",
            "--quiet",
        ]
        try:
            cls.mongod_proc = subprocess.Popen(
                cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            time.sleep(2)
            from pymongo import MongoClient
            cls.mongo_client = MongoClient(
                "mongodb://127.0.0.1:27098", serverSelectionTimeoutMS=3000
            )
            cls.mongo_client.admin.command("ping")
            cls.real_db = cls.mongo_client["saman_revenue_cp07_isolated_test"]
            ensure_revenue_indexes(db=cls.real_db, dry_run=False)
            for col_name, keys, kwargs in PAYMENT_TRANSACTION_INDEX_SPECIFICATIONS:
                cls.real_db[col_name].create_index(keys, **kwargs)
            cls.mongod_available = True
        except Exception as exc:
            print(f"[Notice] Isolated mongod for CP-07 bypassed: {exc}")
            cls.mongod_available = False

    @classmethod
    def tearDownClass(cls):
        import shutil
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
        if cls.dbpath and os.path.exists(cls.dbpath):
            try:
                shutil.rmtree(cls.dbpath, ignore_errors=True)
            except Exception:
                pass

    def test_real_mongodb_concurrent_settlement_and_unique_indexes(self):
        if not self.mongod_available:
            self.skipTest("Isolated mongod not available on 127.0.0.1:27098")

        import threading
        now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
        adapter = FakeVerifiedPaymentAdapter()
        adapter.register_token(
            "tok_real_mongo_1",
            VerifiedProviderTransaction(
                provider=PaymentProviderName.APPLE_APP_STORE,
                environment=PaymentEnvironment.SANDBOX,
                app_id="com.saman.health.ios",
                product_id="saman_plus_monthly_sandbox",
                transaction_id="tx_real_mongo_1",
                original_transaction_id="orig_real_mongo_1",
                verification_status=ProviderVerificationStatus.VERIFIED_ACTIVE,
                purchase_date=now - timedelta(minutes=5),
                expires_date=now + timedelta(days=30),
                raw_payload_hash=hash_sensitive_payload("tok_real_mongo_1"),
            ),
        )
        settlement = PaymentSettlementService(
            db=self.real_db,
            adapter=adapter,
            mapping_registry=build_sandbox_registry(enabled=True),
        )
        req = PurchaseVerificationRequest(
            provider=PaymentProviderName.APPLE_APP_STORE,
            environment=PaymentEnvironment.SANDBOX,
            app_id="com.saman.health.ios",
            product_id="saman_plus_monthly_sandbox",
            verification_token="tok_real_mongo_1",
        )

        outcomes = []
        lock = threading.Lock()

        def worker():
            res = settlement.verify_and_settle_purchase(
                "real_mongo_buyer@saman.ai", req, as_of=now
            )
            with lock:
                outcomes.append(res)

        threads = [threading.Thread(target=worker) for _ in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(len(outcomes), 8)
        for o in outcomes:
            self.assertEqual(o.outcome, PurchaseVerificationOutcomeStatus.CONFIRMED)
            self.assertEqual(o.tier, MembershipTier.PLUS)

        # Verify exactly 1 subscription and 1 transaction exist in real WiredTiger storage
        self.assertEqual(
            self.real_db[COLL_SUBSCRIPTIONS].count_documents({"user_id": "real_mongo_buyer@saman.ai"}),
            1,
        )
        self.assertEqual(
            self.real_db[COLL_PAYMENT_TRANSACTIONS].count_documents({"transaction_id": "tx_real_mongo_1"}),
            1,
        )
        self.assertEqual(
            self.real_db[COLL_ENTITLEMENT_GRANTS].count_documents({"user_id": "real_mongo_buyer@saman.ai"}),
            3,
        )


if __name__ == "__main__":
    unittest.main()
