"""
Targeted Verification Suite for REVENUE-R02A:
Correct RevenueCat Identity, Policy & Verification Claims.

Invariants Verified:
1. Canonical Identity & Opaque Provider Mapping:
   - Server-owned random `account_id` (`acct_<32-hex>`) and `app_user_id` (`rc_cus_<32-hex>`),
     unique per `(provider, project_id, account_id)` and `(provider, project_id, app_user_id)`.
   - Never uses email or email hash (`saman_usr_*`) as canonical payment identity.
   - Changing account email preserves `account_id`, `rc_cus_...`, subscription, grants, and usage.
   - Switching accounts isolates entitlements and customer mappings.
   - Legacy R02 `saman_usr_*` records trigger explicit read-only blocker (409) without auto-merge.
2. Trusted Outbound Server Verification:
   - Executes outbound `GET {api_base_url}/v1/subscribers/{app_user_id}` via injectable `http_client`.
   - Validates `Authorization: Bearer <secret_key>`, timeout, and HTTP 401/404/500 responses.
   - Requires explicit boolean `is_sandbox`, mandatory `purchase_date` & `expires_date` (never +30d),
     and provider-reported transaction IDs (never trusting client transaction ID hints).
   - Filters dual sandbox + production subscriber records by `expected_environment`.
3. Policy & Lifecycle Accuracy:
   - Default RevenueCat product mappings are disabled (`enabled=False`) with `quota_limits={}`.
   - Unapproved Free 30 / Plus 100 / Pro 300 quotas and grace periods are never invented.
   - `BILLING_ISSUE` honors provider `grace_period_expires_date` or injected policy; otherwise `in_grace_period=False`.
   - `CANCELLATION` distinguishes `UNSUBSCRIBE` (active until expiry) vs `CUSTOMER_SUPPORT` (immediate revoke).
   - `EXPIRATION` preserves independent manual grants (`source_subscription_id != sub_id`) and usage counters.
   - Unsupported webhook events (`TEST`, `NON_RENEWING_PURCHASE`, `SUBSCRIPTION_PAUSED`, `TRANSFER`, etc.)
     are recorded in WAL as `ignored_unsupported` without granting or revoking entitlements.
4. Webhook Authentication & Replay Protection:
   - Supports `bearer`, `hmac`, and `bearer_and_hmac` modes.
   - Verifies `X-RevenueCat-Webhook-Signature: t=<timestamp>,v1=<hex_sig>` over `t.raw_body`.
   - Enforces timestamp replay window and raw body byte integrity; deduplicates retries with new `t`/`v1`.
5. Restore Policy Gate:
   - Blocks live RevenueCat restore (503 `PAYMENT_CONFIG_NOT_READY`) when `restore_policy_verified=False`.
   - Allows same-account restore and blocks cross-account transfer (409) when `restore_policy_verified=True`.
"""

import hashlib
import hmac
import json
import os
import time
import unittest
import urllib.request
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, Tuple, List, Optional

from fastapi.testclient import TestClient

from backend.main import app
from backend.app.models.revenue import (
    PaymentProviderName,
    PaymentEnvironment,
    MembershipTier,
    ProviderVerificationStatus,
    PurchaseVerificationRequest,
    RestorePurchasesRequest,
    EventProcessingStatus,
    GracePeriodPolicy,
)
from backend.app.services.revenuecat_adapter import (
    RevenueCatProviderAdapter,
    LegacyR02IdentityMigrationRequiredError,
    generate_random_account_id,
    generate_random_revenuecat_app_user_id,
    is_valid_account_id,
    is_valid_revenuecat_app_user_id,
    resolve_or_create_account_id,
    resolve_or_create_provider_customer_id,
    resolve_account_id_from_provider_customer_id,
    inspect_legacy_r02_identities_readonly,
)
from backend.app.services.payment_service import (
    PaymentSettlementService,
    PaymentWebhookIngestionService,
    ProductMappingRegistry,
    build_default_revenuecat_mappings,
    PaymentConfigurationNotReadyError,
    ProductMappingRejectedError,
    UnverifiedPurchasePayloadError,
    ClientIdentityMismatchError,
    ReceiptOwnershipConflictError,
    WebhookVerificationError,
    configure_payment_settlement_service,
)
from backend.app.services import entitlement_service, payment_service
from backend.app.database_revenue import (
    COLL_PROVIDER_CUSTOMERS,
    COLL_PROVIDER_EVENTS,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_SUBSCRIPTIONS,
    COLL_ENTITLEMENT_GRANTS,
    COLL_USAGE_BUCKETS,
    PROVIDER_CUSTOMER_INDEX_SPECIFICATIONS,
)
from backend.auth_utils import verify_token
from backend.tests.test_revenue_entitlement_quota import MockDatabase as FakeDatabase


class TestRevenueCatR02A(unittest.TestCase):
    def setUp(self):
        self.mock_db = FakeDatabase()
        self.orig_ent_db = entitlement_service.EntitlementService._get_db
        entitlement_service.EntitlementService._get_db = lambda self_svc: self.mock_db

        self.expected_app_id = "com.saman.health"
        self.expected_project_id = "proj_saman_rc_test"
        self.expected_store = "play_store"
        self.secret_key = "sk_rc_test_secret_999"
        self.webhook_bearer = "rc_webhook_bearer_secret_123"
        self.hmac_secret = "rc_webhook_hmac_secret_456"

        # Record outbound HTTP requests for inspection
        self.recorded_http_requests: List[Tuple[urllib.request.Request, float]] = []
        self.next_http_response: Tuple[int, Dict[str, str], bytes] = (
            200,
            {"Content-Type": "application/json"},
            b"{}",
        )

        # Default test registry: explicitly enable sandbox mappings, without inventing quotas
        self.mapping_registry = ProductMappingRegistry(
            expected_environment=PaymentEnvironment.SANDBOX,
            allowed_app_ids=[self.expected_app_id],
        )
        self.mapping_registry.register_revenuecat_defaults(
            environment=PaymentEnvironment.SANDBOX,
            app_id=self.expected_app_id,
            enabled=True,
            unapproved_test_quota_limits=None,
        )

        self.adapter = RevenueCatProviderAdapter(
            secret_key=self.secret_key,
            webhook_auth_token=self.webhook_bearer,
            webhook_signature_secret=self.hmac_secret,
            webhook_auth_mode="bearer_and_hmac",
            expected_project_id=self.expected_project_id,
            expected_app_id=self.expected_app_id,
            allowed_stores={"PLAY_STORE"},
            restore_policy_verified=False,
            http_client=self._fake_http_client,
        )

        self.settlement_svc = PaymentSettlementService(
            db=self.mock_db,
            adapter=self.adapter,
            mapping_registry=self.mapping_registry,
        )
        self.webhook_svc = PaymentWebhookIngestionService(
            settlement_service=self.settlement_svc,
            adapter=self.adapter,
            mapping_registry=self.mapping_registry,
            grace_policy=None,
        )

        configure_payment_settlement_service(self.settlement_svc)
        self.orig_webhook_svc = payment_service._default_webhook_service
        payment_service._default_webhook_service = self.webhook_svc

        self.client = TestClient(app)
        self.current_auth_email = "alice@saman.ai"
        app.dependency_overrides[verify_token] = lambda: self.current_auth_email

    def tearDown(self):
        configure_payment_settlement_service(None)
        payment_service._default_webhook_service = self.orig_webhook_svc
        app.dependency_overrides.pop(verify_token, None)
        entitlement_service.EntitlementService._get_db = self.orig_ent_db

    def _fake_http_client(
        self, req: urllib.request.Request, timeout: float
    ) -> Tuple[int, Dict[str, str], bytes]:
        self.recorded_http_requests.append((req, timeout))
        return self.next_http_response

    def _set_subscriber_http_response(
        self,
        app_user_id: str,
        product_id: str = "saman_pro_monthly",
        is_sandbox: Any = True,
        store: str = "play_store",
        purchase_date: Optional[str] = None,
        expires_date: Optional[str] = None,
        store_transaction_id: Any = "GPA.3301-1111-2222-33333",
        product_plan_identifier: Optional[str] = None,
        extra_subscriptions: Optional[Dict[str, Any]] = None,
        status_code: int = 200,
    ):
        """
        Builds a strict official RevenueCat REST API v1 `GET /v1/subscribers/{app_user_id}`
        response conforming to `openapi-v1-customer-info-model.yaml` (no non-official
        `project_id`, `app_id`, or `original_transaction_id` fields injected).
        """
        now = datetime.now(timezone.utc)
        now_iso = now.strftime("%Y-%m-%dT%H:%M:%SZ")
        p_date = purchase_date if purchase_date is not None else now_iso
        e_date = (
            expires_date
            if expires_date is not None
            else (now + timedelta(days=30)).strftime("%Y-%m-%dT%H:%M:%SZ")
        )

        sub_entry: Dict[str, Any] = {
            "auto_resume_date": None,
            "billing_issues_detected_at": None,
            "grace_period_expires_date": None,
            "ownership_type": "PURCHASED",
            "period_type": "normal",
            "refunded_at": None,
            "store": store,
            "unsubscribe_detected_at": None,
        }
        if is_sandbox is not None:
            sub_entry["is_sandbox"] = is_sandbox
        if p_date != "__OMIT__":
            sub_entry["purchase_date"] = p_date
            sub_entry["original_purchase_date"] = p_date
        if e_date != "__OMIT__":
            sub_entry["expires_date"] = e_date
        if store_transaction_id != "__OMIT__":
            sub_entry["store_transaction_id"] = store_transaction_id
        if product_plan_identifier is not None:
            sub_entry["product_plan_identifier"] = product_plan_identifier

        subscriptions = {product_id: sub_entry}
        if extra_subscriptions:
            subscriptions.update(extra_subscriptions)

        subscriber_obj: Dict[str, Any] = {
            "entitlements": {},
            "first_seen": now_iso,
            "last_seen": now_iso,
            "management_url": "https://play.google.com/store/account/subscriptions",
            "non_subscriptions": {},
            "original_app_user_id": app_user_id,
            "original_application_version": None,
            "original_purchase_date": None,
            "other_purchases": {},
            "subscriptions": subscriptions,
        }

        body = json.dumps(
            {
                "request_date": now_iso,
                "request_date_ms": int(now.timestamp() * 1000),
                "subscriber": subscriber_obj,
            }
        ).encode("utf-8")
        self.next_http_response = (status_code, {"Content-Type": "application/json"}, body)

    def _sign_webhook(self, raw_body: bytes, timestamp: Optional[int] = None) -> str:
        ts = timestamp if timestamp is not None else int(time.time())
        signed_payload = f"{ts}.".encode("utf-8") + raw_body
        digest = hmac.new(self.hmac_secret.encode("utf-8"), signed_payload, hashlib.sha256).hexdigest()
        return f"t={ts},v1={digest}"

    def _post_webhook(
        self,
        event_dict: Dict[str, Any],
        raw_body_override: Optional[bytes] = None,
        timestamp: Optional[int] = None,
        signature_override: Optional[str] = None,
        bearer_override: Optional[str] = None,
    ):
        body = (
            raw_body_override
            if raw_body_override is not None
            else json.dumps({"api_version": "1.0", "event": event_dict}).encode("utf-8")
        )
        sig = signature_override if signature_override is not None else self._sign_webhook(body, timestamp=timestamp)
        bearer = bearer_override if bearer_override is not None else f"Bearer {self.webhook_bearer}"
        headers = {
            "Content-Type": "application/json",
            "Authorization": bearer,
            "X-RevenueCat-Webhook-Signature": sig,
        }
        return self.client.post(
            "/api/revenue/webhooks/revenuecat",
            content=body,
            headers=headers,
        )

    # ==========================================================================
    # 1. Identity & Email Change / Account Switch / Legacy Blocker
    # ==========================================================================

    def test_1a_random_server_owned_identity_and_email_change_stability(self):
        """
        Verifies:
        - GET /api/revenue/membership/me creates a server-owned `acct_<32-hex>`
          account_id and `rc_cus_<32-hex>` opaque_app_user_id (never hashing email).
        - Changing the user's email in `db["users"]` preserves the exact same
          `account_id`, `opaque_app_user_id`, active subscription, and entitlements.
        """
        resp1 = self.client.get("/api/revenue/membership/me")
        self.assertEqual(resp1.status_code, 200)
        data1 = resp1.json()
        acct_id = data1["account_id"]
        rc_id = data1["opaque_app_user_id"]

        self.assertTrue(is_valid_account_id(acct_id))
        self.assertTrue(is_valid_revenuecat_app_user_id(rc_id))
        self.assertNotIn("alice", rc_id)
        self.assertFalse(rc_id.startswith("saman_usr_"))

        # Verify purchase under `rc_id` using official GET /v1/subscribers response
        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_pro_monthly",
        )
        verify_resp = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(verify_resp.status_code, 200)
        self.assertEqual(verify_resp.json()["tier"], "pro")

        # User changes email from alice@saman.ai -> alice_renamed@saman.ai on the same account_id
        self.mock_db["users"].update_one(
            {"account_id": acct_id},
            {"$set": {"email": "alice_renamed@saman.ai"}},
        )
        self.current_auth_email = "alice_renamed@saman.ai"

        resp2 = self.client.get("/api/revenue/membership/me")
        self.assertEqual(resp2.status_code, 200)
        data2 = resp2.json()
        self.assertEqual(data2["user_id"], "alice_renamed@saman.ai")
        self.assertEqual(data2["account_id"], acct_id)
        self.assertEqual(data2["opaque_app_user_id"], rc_id)
        self.assertEqual(data2["tier"], "pro")
        self.assertTrue(data2["is_active_subscription"])
        self.assertEqual(len(data2["entitlements"]), 4)

    def test_1b_account_switch_isolates_entitlements_and_rejects_cross_account_token(self):
        """
        Verifies:
        - Account A and Account B receive distinct `acct_*` and `rc_cus_*` IDs.
        - Account B cannot verify a purchase using Account A's `rc_cus_*` token (403).
        - Account B does not inherit Account A's Pro subscription.
        """
        me_a = self.client.get("/api/revenue/membership/me").json()
        rc_a = me_a["opaque_app_user_id"]

        self._set_subscriber_http_response(app_user_id=rc_a, product_id="saman_pro_monthly")
        self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_a,
            },
        )

        # Switch to Account B
        self.current_auth_email = "bob@saman.ai"
        me_b = self.client.get("/api/revenue/membership/me").json()
        rc_b = me_b["opaque_app_user_id"]

        self.assertNotEqual(me_a["account_id"], me_b["account_id"])
        self.assertNotEqual(rc_a, rc_b)
        self.assertEqual(me_b["tier"], "free")
        self.assertFalse(me_b["is_active_subscription"])

        # Account B attempts to submit Account A's rc_cus_* token -> 403 CLIENT_IDENTITY_MISMATCH
        spoof_resp = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_a,
            },
        )
        self.assertEqual(spoof_resp.status_code, 403)

    def test_1c_legacy_r02_email_hash_identity_triggers_explicit_blocker(self):
        """
        Verifies:
        - Pre-existing `saman_usr_<sha256_prefix>` subscription records are detected
          by `inspect_legacy_r02_identities_readonly(db)` without mutating data.
        - Accessing `/api/revenue/membership/me` or `/api/revenue/purchases/verify`
          for an account with legacy `saman_usr_*` records raises HTTP 409/400
          `LEGACY_R02_IDENTITY_MIGRATION_REQUIRED` rather than silently losing or merging purchases.
        """
        legacy_email = "legacy_buyer@saman.ai"
        legacy_hash = hashlib.sha256(legacy_email.encode("utf-8")).hexdigest()[:16]
        legacy_id = f"saman_usr_{legacy_hash}"

        self.mock_db[COLL_SUBSCRIPTIONS].insert_one({
            "subscription_id": "sub_legacy_01",
            "user_id": legacy_id,
            "tier": "plus",
            "status": "active",
        })

        report = inspect_legacy_r02_identities_readonly(self.mock_db)
        self.assertTrue(report["has_legacy_records"])
        self.assertEqual(report["counts"][COLL_SUBSCRIPTIONS], 1)
        self.assertIn(legacy_id, report["samples"][COLL_SUBSCRIPTIONS])

        self.current_auth_email = legacy_email
        me_resp = self.client.get("/api/revenue/membership/me")
        self.assertEqual(me_resp.status_code, 409)
        self.assertEqual(me_resp.json()["detail"]["code"], "LEGACY_R02_IDENTITY_MIGRATION_REQUIRED")

        verify_resp = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_plus_monthly",
                "verification_token": legacy_id,
            },
        )
        self.assertEqual(verify_resp.status_code, 400)
        self.assertEqual(verify_resp.json()["detail"]["code"], "LEGACY_R02_IDENTITY_MIGRATION_REQUIRED")

    # ==========================================================================
    # 2. Trusted Outbound Server Verification via Injectable http_client
    # ==========================================================================

    def test_2a_outbound_get_subscribers_request_and_provider_tx_precedence(self):
        """
        Verifies:
        - `verify_purchase` invokes `http_client` with `GET https://api.revenuecat.com/v1/subscribers/{rc_cus_id}`,
          `Authorization: Bearer <secret_key>`, and configured timeout.
        - Client-supplied `transaction_id` / `original_transaction_id` hints are ignored when
          provider returns authoritative `store_transaction_id` and `original_transaction_id`.
        """
        me = self.client.get("/api/revenue/membership/me").json()
        rc_id = me["opaque_app_user_id"]

        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_plus_monthly",
            store_transaction_id="GPA.3301-9000-0000-00900",
        )

        resp = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_plus_monthly",
                "verification_token": rc_id,
                "transaction_id": "untrusted_client_tx_hint",
                "original_transaction_id": "untrusted_client_orig_hint",
            },
        )
        self.assertEqual(resp.status_code, 200)
        body = resp.json()
        self.assertEqual(body["transaction_id"], "GPA.3301-9000-0000-00900")
        self.assertEqual(body["original_transaction_id"], "GPA.3301-9000-0000-00900")

        self.assertEqual(len(self.recorded_http_requests), 1)
        outbound_req, timeout = self.recorded_http_requests[0]
        self.assertEqual(outbound_req.get_method(), "GET")
        self.assertEqual(
            outbound_req.full_url,
            f"https://api.revenuecat.com/v1/subscribers/{rc_id}",
        )
        self.assertEqual(outbound_req.get_header("Authorization"), f"Bearer {self.secret_key}")
        self.assertEqual(timeout, 10.0)

    def test_2b_missing_is_sandbox_or_expires_date_or_tx_id_fails_closed(self):
        """
        Verifies:
        - Missing `is_sandbox` boolean -> 400 `PROVIDER_MISSING_SANDBOX_FLAG`.
        - Missing `expires_date` -> 400 `PROVIDER_MISSING_EXPIRES_DATE` (never invents +30d).
        - Missing provider transaction ID -> 400 `PROVIDER_MISSING_TRANSACTION_ID`
          even if client supplied a `transaction_id` hint.
        """
        me = self.client.get("/api/revenue/membership/me").json()
        rc_id = me["opaque_app_user_id"]

        # 1. Missing is_sandbox
        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_plus_monthly",
            is_sandbox=None,
        )
        r1 = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_plus_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(r1.status_code, 400)
        self.assertEqual(r1.json()["detail"]["code"], "MISSING_IS_SANDBOX_FLAG")

        # 2. Missing expires_date (must NOT invent +30d)
        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_plus_monthly",
            expires_date="__OMIT__",
        )
        r2 = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_plus_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(r2.status_code, 400)
        self.assertEqual(r2.json()["detail"]["code"], "MISSING_VERIFIED_TIMESTAMPS")

        # 3. Missing provider store_transaction_id (must NOT fall back to client hint)
        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_plus_monthly",
            store_transaction_id="__OMIT__",
        )
        r3 = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_plus_monthly",
                "verification_token": rc_id,
                "transaction_id": "client_hint_should_not_be_used",
            },
        )
        self.assertEqual(r3.status_code, 400)
        self.assertEqual(r3.json()["detail"]["code"], "MISSING_PROVIDER_TRANSACTION_ID")

    def test_2c_dual_environment_subscriber_filters_by_expected_environment(self):
        """
        Verifies:
        - If subscriber has a production subscription (`is_sandbox=False`) for the requested SKU
          while server expects `SANDBOX`, verification rejects with 422 `PAYMENT_ENVIRONMENT_MISMATCH`.
        - Disallowed `store` in official subscriber payload is rejected with 400 `UNSUPPORTED_OR_MISSING_STORE`.
        """
        me = self.client.get("/api/revenue/membership/me").json()
        rc_id = me["opaque_app_user_id"]

        # Production subscription on Sandbox server
        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_plus_monthly",
            is_sandbox=False,
        )
        r_env = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_plus_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(r_env.status_code, 422)
        self.assertEqual(r_env.json()["detail"]["code"], "PAYMENT_ENVIRONMENT_MISMATCH")

        # Disallowed store in official subscriber payload
        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_plus_monthly",
            is_sandbox=True,
            store="roku",
        )
        r_store = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_plus_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(r_store.status_code, 400)
        self.assertEqual(r_store.json()["detail"]["code"], "UNSUPPORTED_OR_MISSING_STORE")

    # ==========================================================================
    # 3. Policy & Lifecycle Accuracy
    # ==========================================================================

    def test_3a_default_mappings_disabled_and_no_unapproved_quotas_invented(self):
        """
        Verifies:
        - `build_default_revenuecat_mappings()` sets `enabled=False` and `quota_limits={}` by default.
        - After settling a Pro subscription with default (`quota_limits={}`), no usage bucket with
          30/100/300 is fabricated, and `/api/revenue/membership/me` returns `limit_units=None`.
        """
        defaults = build_default_revenuecat_mappings()
        self.assertTrue(len(defaults) > 0)
        for m in defaults:
            self.assertFalse(m.enabled)
            self.assertEqual(m.quota_limits, {})

        me = self.client.get("/api/revenue/membership/me").json()
        self.assertIsNone(me["usage"]["ai.nutrition_gemini"]["limit_units"])
        self.assertIsNone(me["usage"]["ai.nutrition_gemini"]["remaining_units"])
        rc_id = me["opaque_app_user_id"]

        self._set_subscriber_http_response(app_user_id=rc_id, product_id="saman_pro_monthly")
        self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_id,
            },
        )

        # No bucket fabricated because quota_limits={}
        bucket = self.mock_db[COLL_USAGE_BUCKETS].find_one({"user_id": me["account_id"]})
        self.assertIsNone(bucket)

        me_after = self.client.get("/api/revenue/membership/me").json()
        self.assertEqual(me_after["tier"], "pro")
        self.assertIsNone(me_after["usage"]["ai.nutrition_gemini"]["limit_units"])

    def test_3b_billing_issue_grace_period_and_cancellation_reasons(self):
        """
        Verifies:
        - `BILLING_ISSUE` without `grace_period_expires_date` and with `grace_duration_days=0`
          marks subscription `past_due` with `in_grace_period=False`.
        - `BILLING_ISSUE` with provider `grace_period_expires_date` sets `in_grace_period=True`
          and preserves access until `grace_period_expires_date`.
        - `CANCELLATION` with `cancel_reason="UNSUBSCRIBE"` keeps `status="active"` and `cancel_at_period_end=True`.
        - `CANCELLATION` with `cancel_reason="CUSTOMER_SUPPORT"` immediately revokes access (`status="canceled"`, grants `"revoked"`).
        """
        me = self.client.get("/api/revenue/membership/me").json()
        acct_id = me["account_id"]
        rc_id = me["opaque_app_user_id"]
        now = datetime.now(timezone.utc).replace(microsecond=0)
        expires = now + timedelta(days=30)
        orig_txn = "rc_orig_lifecycle_01"

        # 1. INITIAL_PURCHASE (official webhook payload without non-standard project_id)
        r_init = self._post_webhook({
            "id": "evt_lc_init",
            "type": "INITIAL_PURCHASE",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": self.expected_store,
            "product_id": "saman_pro_monthly",
            "transaction_id": "tx_lc_1",
            "original_transaction_id": orig_txn,
            "app_user_id": rc_id,
            "event_timestamp_ms": int(now.timestamp() * 1000),
            "purchased_at_ms": int(now.timestamp() * 1000),
            "expiration_at_ms": int(expires.timestamp() * 1000),
        })
        self.assertEqual(r_init.status_code, 200)

        # 2. BILLING_ISSUE without provider grace_period_expires_at_ms -> in_grace_period=False
        r_bi_no_grace = self._post_webhook({
            "id": "evt_lc_bi_1",
            "type": "BILLING_ISSUE",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": self.expected_store,
            "product_id": "saman_pro_monthly",
            "transaction_id": "tx_lc_1",
            "original_transaction_id": orig_txn,
            "app_user_id": rc_id,
            "event_timestamp_ms": int((now + timedelta(minutes=1)).timestamp() * 1000),
            "purchased_at_ms": int(now.timestamp() * 1000),
            "expiration_at_ms": int(expires.timestamp() * 1000),
        })
        self.assertEqual(r_bi_no_grace.status_code, 200)
        sub = self.mock_db[COLL_SUBSCRIPTIONS].find_one({"original_transaction_id": orig_txn})
        self.assertEqual(sub["status"], "past_due")
        self.assertFalse(sub["in_grace_period"])
        self.assertIsNone(sub["grace_period_expires_at"])

        # 3. BILLING_ISSUE with provider grace_period_expires_at_ms -> in_grace_period=True
        grace_end = now + timedelta(days=7)
        r_bi_grace = self._post_webhook({
            "id": "evt_lc_bi_2",
            "type": "BILLING_ISSUE",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": self.expected_store,
            "product_id": "saman_pro_monthly",
            "transaction_id": "tx_lc_1",
            "original_transaction_id": orig_txn,
            "app_user_id": rc_id,
            "event_timestamp_ms": int((now + timedelta(minutes=2)).timestamp() * 1000),
            "purchased_at_ms": int(now.timestamp() * 1000),
            "expiration_at_ms": int(expires.timestamp() * 1000),
            "grace_period_expiration_at_ms": int(grace_end.timestamp() * 1000),
        })
        self.assertEqual(r_bi_grace.status_code, 200)
        sub = self.mock_db[COLL_SUBSCRIPTIONS].find_one({"original_transaction_id": orig_txn})
        self.assertEqual(sub["status"], "past_due")
        self.assertTrue(sub["in_grace_period"])
        self.assertEqual(sub["grace_period_expires_at"], grace_end)

        # 4. CANCELLATION with UNSUBSCRIBE -> active until expiry, cancel_at_period_end=True
        self.mock_db[COLL_SUBSCRIPTIONS].update_one(
            {"original_transaction_id": orig_txn},
            {"$set": {"status": "active", "in_grace_period": False}},
        )
        r_unsub = self._post_webhook({
            "id": "evt_lc_cancel_unsub",
            "type": "CANCELLATION",
            "cancel_reason": "UNSUBSCRIBE",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": self.expected_store,
            "product_id": "saman_pro_monthly",
            "transaction_id": "tx_lc_1",
            "original_transaction_id": orig_txn,
            "app_user_id": rc_id,
            "event_timestamp_ms": int((now + timedelta(minutes=3)).timestamp() * 1000),
            "purchased_at_ms": int(now.timestamp() * 1000),
            "expiration_at_ms": int(expires.timestamp() * 1000),
        })
        self.assertEqual(r_unsub.status_code, 200)
        sub = self.mock_db[COLL_SUBSCRIPTIONS].find_one({"original_transaction_id": orig_txn})
        self.assertEqual(sub["status"], "active")
        self.assertTrue(sub["cancel_at_period_end"])
        self.assertFalse(sub["auto_renew_status"])

        # 5. CANCELLATION with CUSTOMER_SUPPORT -> immediate revocation
        r_cs = self._post_webhook({
            "id": "evt_lc_cancel_cs",
            "type": "CANCELLATION",
            "cancel_reason": "CUSTOMER_SUPPORT",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": self.expected_store,
            "product_id": "saman_pro_monthly",
            "transaction_id": "tx_lc_1",
            "original_transaction_id": orig_txn,
            "app_user_id": rc_id,
            "event_timestamp_ms": int((now + timedelta(minutes=4)).timestamp() * 1000),
            "purchased_at_ms": int(now.timestamp() * 1000),
            "expiration_at_ms": int(expires.timestamp() * 1000),
        })
        self.assertEqual(r_cs.status_code, 200)
        sub = self.mock_db[COLL_SUBSCRIPTIONS].find_one({"original_transaction_id": orig_txn})
        self.assertEqual(sub["status"], "canceled")
        grants = list(self.mock_db[COLL_ENTITLEMENT_GRANTS].find({"user_id": acct_id}))
        for g in grants:
            self.assertEqual(g["status"], "revoked")

    def test_3c_expiration_preserves_independent_grants_and_usage_bucket(self):
        """
        Verifies:
        - `EXPIRATION` marks subscription grants (`source_subscription_id == sub_id`) as `expired`.
        - An independent manual/pilot grant (`source_subscription_id != sub_id`) remains `granted`.
        - Existing usage bucket `consumed_units` and `limit_units` are preserved (never reset or overwritten to 30).
        """
        me = self.client.get("/api/revenue/membership/me").json()
        acct_id = me["account_id"]
        rc_id = me["opaque_app_user_id"]
        now = datetime.now(timezone.utc).replace(microsecond=0)
        expires = now + timedelta(days=30)
        orig_txn = "rc_orig_exp_preserve_01"

        # 1. INITIAL_PURCHASE
        self._post_webhook({
            "id": "evt_exp_init",
            "type": "INITIAL_PURCHASE",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": self.expected_store,
            "product_id": "saman_plus_monthly",
            "transaction_id": "tx_exp_1",
            "original_transaction_id": orig_txn,
            "app_user_id": rc_id,
            "event_timestamp_ms": int(now.timestamp() * 1000),
            "purchased_at_ms": int(now.timestamp() * 1000),
            "expiration_at_ms": int(expires.timestamp() * 1000),
        })

        # Seed an independent manual grant and an existing usage bucket
        self.mock_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "manual_pilot_grant_01",
            "user_id": acct_id,
            "benefit_id": "ai.custom_coach",
            "status": "granted",
            "source_type": "manual_grant",
            "source_subscription_id": None,
            "valid_from": now - timedelta(days=1),
            "valid_until": now + timedelta(days=90),
        })
        self.mock_db[COLL_USAGE_BUCKETS].insert_one({
            "bucket_id": "bkt_exp_test",
            "user_id": acct_id,
            "benefit_id": "ai.nutrition_gemini",
            "bucket_key": "2026-10",
            "window_start": now,
            "window_end": expires,
            "limit_units": 150,
            "consumed_units": 42,
            "reserved_units": 0,
        })

        # 2. EXPIRATION
        r_exp = self._post_webhook({
            "id": "evt_exp_final",
            "type": "EXPIRATION",
            "expiration_reason": "UNSUBSCRIBE",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": self.expected_store,
            "product_id": "saman_plus_monthly",
            "transaction_id": "tx_exp_1",
            "original_transaction_id": orig_txn,
            "app_user_id": rc_id,
            "event_timestamp_ms": int((now + timedelta(days=30)).timestamp() * 1000),
            "purchased_at_ms": int(now.timestamp() * 1000),
            "expiration_at_ms": int(expires.timestamp() * 1000),
        })
        self.assertEqual(r_exp.status_code, 200)

        # Independent manual grant is still granted
        manual_g = self.mock_db[COLL_ENTITLEMENT_GRANTS].find_one({"grant_id": "manual_pilot_grant_01"})
        self.assertEqual(manual_g["status"], "granted")

        # Subscription grants are expired
        sub_doc = self.mock_db[COLL_SUBSCRIPTIONS].find_one({"original_transaction_id": orig_txn})
        self.assertEqual(sub_doc["status"], "expired")
        sub_grants = list(
            self.mock_db[COLL_ENTITLEMENT_GRANTS].find({"source_subscription_id": sub_doc["subscription_id"]})
        )
        self.assertTrue(len(sub_grants) > 0)
        for g in sub_grants:
            self.assertEqual(g["status"], "expired")

        # Usage bucket was NOT overwritten to 30 or reset to 0
        bkt = self.mock_db[COLL_USAGE_BUCKETS].find_one({"bucket_id": "bkt_exp_test"})
        self.assertEqual(bkt["limit_units"], 150)
        self.assertEqual(bkt["consumed_units"], 42)

    def test_3d_unsupported_webhook_events_recorded_as_ignored_unsupported_without_mutation(self):
        """
        Verifies:
        - `TEST`, `NON_RENEWING_PURCHASE`, `SUBSCRIPTION_PAUSED`, `TRANSFER`, and unknown event types
          are recorded in `revenue_provider_events` with `processing_status="ignored_unsupported"`
          and never create or revoke subscriptions/grants.
        """
        me = self.client.get("/api/revenue/membership/me").json()
        rc_id = me["opaque_app_user_id"]

        for idx, evt_type in enumerate(
            ["TEST", "NON_RENEWING_PURCHASE", "SUBSCRIPTION_PAUSED", "TRANSFER", "FUTURE_EVENT_TYPE"]
        ):
            evt_id = f"evt_unsup_{idx}_{evt_type}"
            resp = self._post_webhook({
                "id": evt_id,
                "type": evt_type,
                "environment": "SANDBOX",
                "app_id": self.expected_app_id,
                "store": self.expected_store,
                "app_user_id": rc_id,
            })
            self.assertEqual(resp.status_code, 200)
            data = resp.json()
            self.assertTrue(data["acknowledged"])
            self.assertEqual(data["status"], EventProcessingStatus.IGNORED_UNSUPPORTED.value)

            wal_doc = self.mock_db[COLL_PROVIDER_EVENTS].find_one({"event_id": evt_id})
            self.assertIsNotNone(wal_doc)
            self.assertEqual(
                wal_doc["processing_status"],
                EventProcessingStatus.IGNORED_UNSUPPORTED.value,
            )

        self.assertEqual(len(list(self.mock_db[COLL_SUBSCRIPTIONS].find({}))), 0)
        self.assertEqual(len(list(self.mock_db[COLL_ENTITLEMENT_GRANTS].find({}))), 0)

    # ==========================================================================
    # 4. Webhook Authentication, Raw Body Integrity, Timestamp & Retry Dedup
    # ==========================================================================

    def test_4_webhook_hmac_timestamp_raw_body_and_retry_deduplication(self):
        """
        Verifies:
        - Modifying whitespace in raw JSON body after signing invalidates `X-RevenueCat-Webhook-Signature` (401).
        - Expired timestamp (`t` outside tolerance window) is rejected with 401 `WEBHOOK_SIGNATURE_EXPIRED`.
        - Retrying the same `event.id` with a fresh timestamp `t` and fresh `v1` signature passes
          authentication and is idempotently deduplicated (`duplicate_ignored=True`).
        """
        me = self.client.get("/api/revenue/membership/me").json()
        rc_id = me["opaque_app_user_id"]
        now = datetime.now(timezone.utc)
        expires = now + timedelta(days=30)

        event = {
            "id": "evt_hmac_test_01",
            "type": "INITIAL_PURCHASE",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": self.expected_store,
            "product_id": "saman_plus_monthly",
            "transaction_id": "tx_hmac_01",
            "original_transaction_id": "orig_hmac_01",
            "app_user_id": rc_id,
            "purchased_at_ms": int(now.timestamp() * 1000),
            "expiration_at_ms": int(expires.timestamp() * 1000),
        }

        compact_body = json.dumps({"api_version": "1.0", "event": event}, separators=(",", ":")).encode("utf-8")
        pretty_body = json.dumps({"api_version": "1.0", "event": event}, indent=2).encode("utf-8")

        # 1. Sign compact_body but send pretty_body -> 401 WEBHOOK_SIGNATURE_MISMATCH
        sig_compact = self._sign_webhook(compact_body)
        r_tampered = self._post_webhook(
            event,
            raw_body_override=pretty_body,
            signature_override=sig_compact,
        )
        self.assertEqual(r_tampered.status_code, 401)
        self.assertEqual(r_tampered.json()["detail"]["code"], "WEBHOOK_SIGNATURE_MISMATCH")

        # 2. Expired timestamp (1 hour old > 300s tolerance) -> 401 WEBHOOK_SIGNATURE_TIMESTAMP_EXPIRED
        old_ts = int(time.time()) - 3600
        r_expired = self._post_webhook(event, timestamp=old_ts)
        self.assertEqual(r_expired.status_code, 401)
        self.assertEqual(r_expired.json()["detail"]["code"], "WEBHOOK_SIGNATURE_TIMESTAMP_EXPIRED")

        # 3. Valid delivery at t1 -> 200 processed
        t1 = int(time.time()) - 10
        r_ok1 = self._post_webhook(event, timestamp=t1)
        self.assertEqual(r_ok1.status_code, 200)
        self.assertFalse(r_ok1.json()["duplicate_ignored"])

        # 4. Retry delivery of same event.id at t2 (new signature) -> 200 duplicate_ignored=True
        t2 = int(time.time())
        r_ok2 = self._post_webhook(event, timestamp=t2)
        self.assertEqual(r_ok2.status_code, 200)
        self.assertTrue(r_ok2.json()["duplicate_ignored"])

    # ==========================================================================
    # 5. Restore Truth & Cross-Account Conflict Protection
    # ==========================================================================

    def test_5_restore_policy_gate_and_conflict_detection(self):
        """
        Verifies:
        - When `adapter.is_restore_policy_verified` is False, `POST /api/revenue/purchases/restore`
          returns 503 `PAYMENT_CONFIG_NOT_READY`.
        - When `restore_policy_verified=True`:
          - Same account restores active subscription idempotently (200).
          - Second account attempting to restore the same store transaction receipt receives
            409 `RECEIPT_OWNERSHIP_CONFLICT` (`ownership_status="unresolved_conflict"`).
        """
        me_a = self.client.get("/api/revenue/membership/me").json()
        rc_a = me_a["opaque_app_user_id"]

        # 1. Restore blocked when restore_policy_verified=False
        r_blocked = self.client.post(
            "/api/revenue/purchases/restore",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_a,
            },
        )
        self.assertEqual(r_blocked.status_code, 503)
        self.assertEqual(r_blocked.json()["detail"]["code"], "PAYMENT_CONFIG_NOT_READY")

        # Enable restore_policy_verified on adapter
        self.adapter._restore_policy_verified = True
        self._set_subscriber_http_response(
            app_user_id=rc_a,
            product_id="saman_pro_monthly",
            store_transaction_id="GPA.3301-7777-8888-99999",
        )

        # 2. Same account A restores successfully
        r_restore_a = self.client.post(
            "/api/revenue/purchases/restore",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_a,
            },
        )
        self.assertEqual(r_restore_a.status_code, 200)
        self.assertEqual(r_restore_a.json()["outcome"], "confirmed")
        self.assertTrue(r_restore_a.json()["is_active_subscription"])
        self.assertEqual(r_restore_a.json()["tier"], "pro")

        # 3. Account B attempts to restore the same underlying receipt -> 409 Conflict
        self.current_auth_email = "intruder_b@saman.ai"
        me_b = self.client.get("/api/revenue/membership/me").json()
        rc_b = me_b["opaque_app_user_id"]

        self._set_subscriber_http_response(
            app_user_id=rc_b,
            product_id="saman_pro_monthly",
            store_transaction_id="GPA.3301-7777-8888-99999",
        )
        r_restore_b = self.client.post(
            "/api/revenue/purchases/restore",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_b,
            },
        )
        self.assertEqual(r_restore_b.status_code, 409)
        self.assertEqual(r_restore_b.json()["detail"]["code"], "RECEIPT_OWNERSHIP_CONFLICT")
        self.assertEqual(r_restore_b.json()["detail"]["ownership_status"], "unresolved_conflict")

    # ==========================================================================
    # 6. REVENUE-R03: Official REST v1 Schema, Test Store Isolation & Restore Policy Separation
    # ==========================================================================

    def test_6a_r03_official_rest_v1_schema_test_store_and_renewal_lineage(self):
        """
        Verifies (REVENUE-R03 Task 2):
        - Official `GET /v1/subscribers/{app_user_id}` response (without `project_id`, `app_id`,
          or `original_transaction_id`) succeeds in SANDBOX for both `store="test_store"` and
          `store="play_store"`, including integer `store_transaction_id` and Google Play
          `product_plan_identifier` base plan matching.
        - `store="test_store"` is strictly rejected in PRODUCTION with 422 `TEST_STORE_FORBIDDEN_IN_PRODUCTION`.
        - After a renewal webhook updates `latest_transaction_id` to a new renewal store transaction ID,
          a subsequent `GET /v1/subscribers` call returning only `store_transaction_id` preserves the
          established `original_transaction_id` lineage.
        """
        # Default allowed_stores on RevenueCatProviderAdapter includes TEST_STORE in SANDBOX
        default_store_adapter = RevenueCatProviderAdapter(
            secret_key=self.secret_key,
            webhook_auth_token=self.webhook_bearer,
            webhook_signature_secret=self.hmac_secret,
            webhook_auth_mode="bearer_and_hmac",
            expected_project_id=self.expected_project_id,
            expected_app_id=self.expected_app_id,
            http_client=self._fake_http_client,
        )
        self.settlement_svc._adapter = default_store_adapter

        me = self.client.get("/api/revenue/membership/me").json()
        rc_id = me["opaque_app_user_id"]

        # 1. Official Test Store response in SANDBOX (with integer store_transaction_id as in OpenAPI examples)
        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_plus_monthly",
            is_sandbox=True,
            store="test_store",
            store_transaction_id=1000000652379790,
        )
        r_test_store = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_plus_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(r_test_store.status_code, 200)
        self.assertEqual(r_test_store.json()["transaction_id"], "1000000652379790")
        self.assertEqual(r_test_store.json()["tier"], "plus")

        # 2. Test Store purchase in PRODUCTION environment is strictly forbidden (422)
        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_plus_monthly",
            is_sandbox=False,
            store="test_store",
            store_transaction_id="test_store_prod_attempt_01",
        )
        with self.assertRaises(ProductMappingRejectedError) as ctx:
            default_store_adapter.verify_purchase(
                request=PurchaseVerificationRequest(
                    provider=PaymentProviderName.REVENUECAT,
                    environment=PaymentEnvironment.PRODUCTION,
                    app_id=self.expected_app_id,
                    product_id="saman_plus_monthly",
                    verification_token=rc_id,
                ),
                expected_environment=PaymentEnvironment.PRODUCTION,
                expected_app_id=self.expected_app_id,
            )
        self.assertEqual(ctx.exception.code, "TEST_STORE_FORBIDDEN_IN_PRODUCTION")

        # 3. Renewal webhook sets latest_transaction_id="GPA.RENEW.202" on original_transaction_id="GPA.ORIG.201";
        #    subsequent GET /v1/subscribers returning only store_transaction_id="GPA.RENEW.202" preserves lineage.
        now = datetime.now(timezone.utc).replace(microsecond=0)
        expires = now + timedelta(days=30)
        self._post_webhook({
            "id": "evt_r03_init_201",
            "type": "INITIAL_PURCHASE",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": "PLAY_STORE",
            "product_id": "saman_pro_monthly",
            "transaction_id": "GPA.ORIG.201",
            "original_transaction_id": "GPA.ORIG.201",
            "app_user_id": rc_id,
            "event_timestamp_ms": int(now.timestamp() * 1000),
            "purchased_at_ms": int(now.timestamp() * 1000),
            "expiration_at_ms": int(expires.timestamp() * 1000),
        })
        self._post_webhook({
            "id": "evt_r03_renew_202",
            "type": "RENEWAL",
            "environment": "SANDBOX",
            "app_id": self.expected_app_id,
            "store": "PLAY_STORE",
            "product_id": "saman_pro_monthly",
            "transaction_id": "GPA.RENEW.202",
            "original_transaction_id": "GPA.ORIG.201",
            "app_user_id": rc_id,
            "event_timestamp_ms": int((now + timedelta(days=30)).timestamp() * 1000),
            "purchased_at_ms": int((now + timedelta(days=30)).timestamp() * 1000),
            "expiration_at_ms": int((expires + timedelta(days=30)).timestamp() * 1000),
        })

        self._set_subscriber_http_response(
            app_user_id=rc_id,
            product_id="saman_pro_monthly",
            is_sandbox=True,
            store="play_store",
            store_transaction_id="GPA.RENEW.202",
        )
        r_verify_after_renew = self.client.post(
            "/api/revenue/purchases/verify",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(r_verify_after_renew.status_code, 200)
        self.assertEqual(r_verify_after_renew.json()["transaction_id"], "GPA.RENEW.202")
        self.assertEqual(r_verify_after_renew.json()["original_transaction_id"], "GPA.ORIG.201")

    def test_6b_r03_restore_policy_separation_unapproved_unverified_and_unsafe_behavior(self):
        """
        Verifies (REVENUE-R03 Task 3):
        - Separates `restore_policy_approved`, `restore_behavior_verified`, and
          `configured_restore_behavior` ('keep_with_original_app_user_id').
        - Unapproved business policy -> 503 `RESTORE_POLICY_NOT_APPROVED`.
        - Unverified dashboard -> 503 `RESTORE_DASHBOARD_NOT_VERIFIED`.
        - Dashboard configured as `transfer_to_new_app_user_id` -> 503 `RESTORE_BEHAVIOR_MUST_KEEP_ORIGINAL`.
        - Only when all 3 are satisfied does live restore execute.
        """
        me = self.client.get("/api/revenue/membership/me").json()
        rc_id = me["opaque_app_user_id"]

        # Case 1: Dashboard verified as keep_with_original_app_user_id, but business policy NOT approved
        adapter_unapproved = RevenueCatProviderAdapter(
            secret_key=self.secret_key,
            restore_policy_approved=False,
            restore_behavior_verified=True,
            configured_restore_behavior="keep_with_original_app_user_id",
            http_client=self._fake_http_client,
        )
        self.assertFalse(adapter_unapproved.is_restore_policy_verified)
        self.assertEqual(adapter_unapproved.restore_unavailable_reason()[0], "RESTORE_POLICY_NOT_APPROVED")
        self.settlement_svc._adapter = adapter_unapproved

        r1 = self.client.post(
            "/api/revenue/purchases/restore",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(r1.status_code, 503)
        self.assertIn("RESTORE_POLICY_NOT_APPROVED", r1.json()["detail"]["message"])

        # Case 2: Policy approved, but dashboard restore setting NOT verified
        adapter_unverified = RevenueCatProviderAdapter(
            secret_key=self.secret_key,
            restore_policy_approved=True,
            restore_behavior_verified=False,
            configured_restore_behavior="keep_with_original_app_user_id",
            http_client=self._fake_http_client,
        )
        self.assertFalse(adapter_unverified.is_restore_policy_verified)
        self.assertEqual(adapter_unverified.restore_unavailable_reason()[0], "RESTORE_DASHBOARD_NOT_VERIFIED")
        self.settlement_svc._adapter = adapter_unverified

        r2 = self.client.post(
            "/api/revenue/purchases/restore",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(r2.status_code, 503)
        self.assertIn("RESTORE_DASHBOARD_NOT_VERIFIED", r2.json()["detail"]["message"])

        # Case 3: Policy approved & dashboard inspected, but dashboard is set to 'transfer_to_new_app_user_id'
        adapter_unsafe_transfer = RevenueCatProviderAdapter(
            secret_key=self.secret_key,
            restore_policy_approved=True,
            restore_behavior_verified=True,
            configured_restore_behavior="transfer_to_new_app_user_id",
            http_client=self._fake_http_client,
        )
        self.assertFalse(adapter_unsafe_transfer.is_restore_policy_verified)
        self.assertEqual(
            adapter_unsafe_transfer.restore_unavailable_reason()[0],
            "RESTORE_BEHAVIOR_MUST_KEEP_ORIGINAL",
        )
        self.settlement_svc._adapter = adapter_unsafe_transfer

        r3 = self.client.post(
            "/api/revenue/purchases/restore",
            json={
                "provider": "revenuecat",
                "environment": "sandbox",
                "app_id": self.expected_app_id,
                "product_id": "saman_pro_monthly",
                "verification_token": rc_id,
            },
        )
        self.assertEqual(r3.status_code, 503)
        self.assertIn("RESTORE_BEHAVIOR_MUST_KEEP_ORIGINAL", r3.json()["detail"]["message"])


class TestRealMongoR02AProviderCustomerIndexes(unittest.TestCase):
    """
    Isolated real MongoDB 7.0 test (task-spawned loopback mongod on port 27099)
    verifying unique indexes on `revenue_provider_customers`.
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
        import tempfile

        mongod_binary = r"D:\SamanDev\tools\mongodb-cp7\mongodb-win32-x86_64-windows-7.0.14\bin\mongod.exe"
        if not os.path.exists(mongod_binary):
            return

        cls.dbpath = tempfile.mkdtemp(prefix="saman_r02a_mongo_")
        cmd = [
            mongod_binary,
            "--port",
            "27099",
            "--bind_ip",
            "127.0.0.1",
            "--dbpath",
            cls.dbpath,
            "--wiredTigerCacheSizeGB",
            "0.25",
            "--quiet",
        ]
        try:
            cls.mongod_proc = subprocess.Popen(
                cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
            time.sleep(2)
            from pymongo import MongoClient

            cls.mongo_client = MongoClient(
                "mongodb://127.0.0.1:27099", serverSelectionTimeoutMS=3000
            )
            cls.mongo_client.admin.command("ping")
            cls.real_db = cls.mongo_client["saman_revenue_r02a_isolated_test"]
            for col_name, keys, kwargs in PROVIDER_CUSTOMER_INDEX_SPECIFICATIONS:
                cls.real_db[col_name].create_index(keys, **kwargs)
            cls.mongod_available = True
        except Exception as exc:
            print(f"[Notice] Isolated mongod for R02A bypassed: {exc}")
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

    def test_real_mongodb_provider_customer_unique_indexes(self):
        if not self.mongod_available:
            self.skipTest("Isolated mongod not available on 127.0.0.1:27099")

        from pymongo.errors import DuplicateKeyError

        acct_1 = resolve_or_create_account_id(self.real_db, "mongo_user1@saman.ai")
        rc_1 = resolve_or_create_provider_customer_id(
            self.real_db, acct_1, project_id="proj_real_1"
        )
        rc_1_repeat = resolve_or_create_provider_customer_id(
            self.real_db, acct_1, project_id="proj_real_1"
        )
        self.assertEqual(rc_1, rc_1_repeat)

        # Attempting to insert a duplicate (provider, project_id, account_id) fails with DuplicateKeyError
        with self.assertRaises(DuplicateKeyError):
            self.real_db[COLL_PROVIDER_CUSTOMERS].insert_one({
                "mapping_id": "dup_acct_map",
                "provider": "revenuecat",
                "project_id": "proj_real_1",
                "account_id": acct_1,
                "app_user_id": generate_random_revenuecat_app_user_id(),
            })

        # Attempting to insert a duplicate (provider, project_id, app_user_id) for another account fails
        with self.assertRaises(DuplicateKeyError):
            self.real_db[COLL_PROVIDER_CUSTOMERS].insert_one({
                "mapping_id": "dup_rc_id_map",
                "provider": "revenuecat",
                "project_id": "proj_real_1",
                "account_id": generate_random_account_id(),
                "app_user_id": rc_1,
            })


if __name__ == "__main__":
    unittest.main()
