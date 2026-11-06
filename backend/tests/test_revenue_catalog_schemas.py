"""
Unit and Integration Tests for Revenue Catalog Engine, Schemas, and Index Specifications.
Covers CP-03 / CP-03A invariants:
- Pydantic v2 integer minor units (cents) enforcement & validation.
- Frozen Pydantic models (mutation prevention).
- CatalogEngine immutability, draft isolation, and deepcopy mutation protection.
- Read-only FastAPI endpoints (/api/revenue/catalog, /api/revenue/catalog/versions).
- Scoped subscription identity: (provider, environment, original_transaction_id).
- Scoped operation idempotency: (user_id, benefit_id, idempotency_key).
- Scoped cache identity: (user_id, client_request_id).
- Partial filter semantics for optional/null transaction IDs.
- Declarative MongoDB index specifications tested against mock collections.
"""

import unittest
from datetime import datetime, timezone, timedelta
from typing import Any, Dict, List, Optional
from pydantic import ValidationError
from fastapi.testclient import TestClient

from backend.app.models.revenue import (
    Price,
    Plan,
    CatalogVersion,
    CatalogStatus,
    InclusionStatus,
    MembershipTier,
    BillingPeriod,
    Subscription,
    SubscriptionStatus,
    PaymentTransaction,
    PaymentStatus,
    ProviderEvent,
    EntitlementGrant,
    UsageBucket,
    UsageOperation,
    IdempotencyCacheRecord,
    MatrixFeatureDefinition,
)
from backend.app.services.catalog_engine import (
    CatalogEngine,
    CatalogImmutabilityError,
    CatalogNotFoundError,
    get_catalog_engine,
    _build_v1_preview_catalog,
)
from backend.app.database_revenue import (
    REVENUE_INDEX_SPECIFICATIONS,
    check_collection_duplicates,
    ensure_revenue_indexes,
    COLL_SUBSCRIPTIONS,
    COLL_ENTITLEMENT_GRANTS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_PROVIDER_EVENTS,
    COLL_FOOD_ANALYSIS_IDEMPOTENCY,
)
from backend.main import app


class TestRevenuePydanticSchemas(unittest.TestCase):
    """Verifies commercial domain schema validation rules and frozen immutability."""

    def test_price_requires_integer_cents(self):
        # Valid integer cents
        price = Price(
            price_id="price_plus_usd_monthly",
            plan_id="plan_plus",
            period=BillingPeriod.MONTHLY,
            amount_cents=1000,
            currency="USD",
            purchasable=False,
        )
        self.assertEqual(price.amount_cents, 1000)
        self.assertEqual(price.currency, "USD")

        # Rejection of float amount_cents
        with self.assertRaises(ValidationError):
            Price(
                price_id="price_invalid_float",
                plan_id="plan_plus",
                period=BillingPeriod.MONTHLY,
                amount_cents=9.99,  # type: ignore[arg-type]
                currency="USD",
            )

        # Rejection of negative amount_cents
        with self.assertRaises(ValidationError):
            Price(
                price_id="price_invalid_negative",
                plan_id="plan_plus",
                period=BillingPeriod.MONTHLY,
                amount_cents=-100,
                currency="USD",
            )

    def test_price_currency_normalization_and_validation(self):
        # Lowercase should be normalized to uppercase
        price = Price(
            price_id="price_vnd",
            plan_id="plan_plus",
            period=BillingPeriod.MONTHLY,
            amount_cents=19900000,
            currency="vnd",
        )
        self.assertEqual(price.currency, "VND")

        # Invalid currency length
        with self.assertRaises(ValidationError):
            Price(
                price_id="price_invalid_cur",
                plan_id="plan_plus",
                period=BillingPeriod.MONTHLY,
                amount_cents=1000,
                currency="TOOLONG",
            )

    def test_frozen_model_mutation_prevention(self):
        # Value objects are immutable: attribute mutation must raise ValidationError
        price = Price(
            price_id="price_frozen_test",
            plan_id="plan_plus",
            period=BillingPeriod.MONTHLY,
            amount_cents=1000,
            currency="USD",
        )
        with self.assertRaises(ValidationError):
            price.amount_cents = 2000  # type: ignore[misc]

        plan = Plan(
            plan_id="plan_frozen_test",
            tier=MembershipTier.PLUS,
            name="Saman Plus",
            subtitle="Coaching",
            hero_description="AI preview",
            icon_name="fitness_center",
            availability_notice="Preview mode.",
        )
        with self.assertRaises(ValidationError):
            plan.name = "Mutated Plan Name"  # type: ignore[misc]

    def test_subscription_model_scoped_identity(self):
        now = datetime.now(timezone.utc)
        sub = Subscription(
            subscription_id="sub_test_001",
            user_id="user_123",
            user_email="test@saman.app",
            plan_id="plan_plus",
            tier=MembershipTier.PLUS,
            price_id="price_plus_usd_monthly",
            status=SubscriptionStatus.ACTIVE,
            provider="apple_storekit",
            environment="sandbox",
            app_id="com.saman.app",
            original_transaction_id="apple_orig_100001",
            latest_transaction_id="apple_txn_200002",
            current_period_start=now,
            current_period_end=now,
            created_at=now,
            updated_at=now,
        )
        self.assertEqual(sub.status, SubscriptionStatus.ACTIVE)
        self.assertEqual(sub.environment, "sandbox")
        self.assertEqual(sub.original_transaction_id, "apple_orig_100001")
        self.assertEqual(sub.latest_transaction_id, "apple_txn_200002")

        # Optional original_transaction_id allowed (e.g. for trial or staff override)
        sub_no_receipt = Subscription(
            subscription_id="sub_trial_002",
            user_id="user_456",
            user_email="trial@saman.app",
            plan_id="plan_plus",
            tier=MembershipTier.PLUS,
            price_id="price_plus_usd_monthly",
            status=SubscriptionStatus.TRIALING,
            provider="manual_mock",
            original_transaction_id=None,
            current_period_start=now,
            current_period_end=now,
            created_at=now,
            updated_at=now,
        )
        self.assertIsNone(sub_no_receipt.original_transaction_id)

    def test_provider_event_schema(self):
        now = datetime.now(timezone.utc)
        event = ProviderEvent(
            event_id="evt_001",
            provider="revenuecat_candidate",
            provider_event_id="rc_event_12345",
            event_type="INITIAL_PURCHASE",
            event_timestamp=now,
            raw_payload={"product_id": "saman_plus_monthly"},
            created_at=now,
        )
        self.assertEqual(event.provider_event_id, "rc_event_12345")
        self.assertEqual(event.event_type, "INITIAL_PURCHASE")

    def test_usage_operation_with_fingerprint(self):
        now = datetime.now(timezone.utc)
        op = UsageOperation(
            operation_id="op_fa_001",
            user_id="user_123",
            bucket_id="bucket_user123_food_202610",
            benefit_id="ai.food_classifier.free",
            idempotency_key="client_uuid_abc_123",
            client_request_id="req_001",
            request_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            units=1,
            created_at=now,
            expires_at=now,
        )
        self.assertEqual(op.idempotency_key, "client_uuid_abc_123")
        self.assertEqual(op.client_request_id, "req_001")
        self.assertIsNotNone(op.request_hash)

    def test_idempotency_cache_record_schema(self):
        now = datetime.now(timezone.utc)
        record = IdempotencyCacheRecord(
            user_id="user_123",
            client_request_id="req_client_999",
            benefit_id="ai.food_classifier.free",
            request_hash="a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e",
            operation_id="op_fa_001",
            status="completed",
            response_payload={"food_name": "Phở Bò", "calories": 450},
            created_at=now,
            expires_at=now,
        )
        self.assertEqual(record.user_id, "user_123")
        self.assertEqual(record.client_request_id, "req_client_999")
        self.assertEqual(record.response_payload["calories"], 450)


class TestCatalogEngine(unittest.TestCase):
    """Verifies CatalogEngine versioning, immutability, draft isolation, and deepcopy protection."""

    def setUp(self):
        self.engine = CatalogEngine()

    def test_initial_published_version(self):
        catalog = self.engine.get_active_catalog()
        self.assertIsNotNone(catalog)
        self.assertEqual(catalog.version_id, "v1.0-preview")
        self.assertEqual(catalog.status, CatalogStatus.PUBLISHED)
        self.assertTrue(catalog.preview_mode)
        self.assertIn("Demo pricing", catalog.disclaimer)

        for price in catalog.prices:
            self.assertFalse(price.purchasable)

    def test_matrix_features_decoupled_from_tier(self):
        catalog = self.engine.get_active_catalog()
        feature_ids = [feat.id for feat in catalog.matrix_features]
        self.assertIn("nutrition_logging", feature_ids)
        self.assertIn("gemini_food_analysis", feature_ids)
        self.assertIn("workout_cv_ai", feature_ids)

        log_feat = next(f for f in catalog.matrix_features if f.id == "nutrition_logging")
        self.assertEqual(log_feat.status_for(MembershipTier.FREE), InclusionStatus.INCLUDED)
        self.assertEqual(log_feat.status_for(MembershipTier.PLUS), InclusionStatus.INCLUDED)

        gemini_feat = next(f for f in catalog.matrix_features if f.id == "gemini_food_analysis")
        self.assertEqual(gemini_feat.status_for(MembershipTier.FREE), InclusionStatus.NOT_INCLUDED)
        self.assertEqual(gemini_feat.status_for(MembershipTier.PLUS), InclusionStatus.PLANNED)

        cv_feat = next(f for f in catalog.matrix_features if f.id == "workout_cv_ai")
        self.assertEqual(cv_feat.status_for(MembershipTier.FREE), InclusionStatus.NOT_INCLUDED)
        self.assertEqual(cv_feat.status_for(MembershipTier.PLUS), InclusionStatus.NOT_INCLUDED)
        self.assertEqual(cv_feat.status_for(MembershipTier.PRO), InclusionStatus.PLANNED)

    def test_catalog_immutability_rejection(self):
        modified_catalog = _build_v1_preview_catalog()
        with self.assertRaises(CatalogImmutabilityError) as ctx:
            self.engine.register_version(modified_catalog)
        self.assertIn("is published and immutable", str(ctx.exception))

    def test_catalog_indirect_mutation_resistance(self):
        # Caller retrieves catalog and attempts to mutate the returned instance
        c1 = self.engine.get_active_catalog()
        self.assertIsNotNone(c1)
        original_plan_count = len(c1.plans)

        # Mutate the list on the retrieved copy
        c1.plans.clear()
        self.assertEqual(len(c1.plans), 0)

        # Fetch again from engine: must remain intact
        c2 = self.engine.get_active_catalog()
        self.assertIsNotNone(c2)
        self.assertEqual(len(c2.plans), original_plan_count)

    def test_draft_registration_and_promotion(self):
        draft_catalog = CatalogVersion(
            version_id="v2.0-draft",
            status=CatalogStatus.DRAFT,
            currency="USD",
            preview_mode=True,
            disclaimer="Draft catalog",
            plans=[],
            prices=[],
            matrix_features=[],
        )
        self.engine.register_version(draft_catalog)
        self.assertEqual(self.engine.get_catalog_by_version("v2.0-draft", include_drafts=True).status, CatalogStatus.DRAFT)

        # Active version should still be v1.0-preview
        self.assertEqual(self.engine.get_active_catalog().version_id, "v1.0-preview")

        # Promote draft to published
        published_cat = self.engine.publish_version("v2.0-draft")
        self.assertEqual(self.engine.get_active_catalog().version_id, "v2.0-draft")
        self.assertEqual(self.engine.get_active_catalog().status, CatalogStatus.PUBLISHED)


class TestRevenueRouterIntegration(unittest.TestCase):
    """Verifies HTTP endpoints for revenue catalog."""

    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def test_get_catalog_active(self):
        response = self.client.get("/api/revenue/catalog")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["version_id"], "v1.0-preview")
        self.assertEqual(data["status"], "published")
        self.assertTrue(data["preview_mode"])
        self.assertIn("disclaimer", data)
        self.assertIsInstance(data["plans"], list)
        self.assertIsInstance(data["prices"], list)
        self.assertIsInstance(data["matrix_features"], list)

        for price in data["prices"]:
            self.assertFalse(price["purchasable"])

    def test_get_catalog_by_version(self):
        response = self.client.get("/api/revenue/catalog?version=v1.0-preview")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["version_id"], "v1.0-preview")

    def test_get_catalog_non_existent_404(self):
        response = self.client.get("/api/revenue/catalog?version=non_existent_version_999")
        self.assertEqual(response.status_code, 404)
        self.assertIn("Published catalog version 'non_existent_version_999' not found.", response.json()["detail"])

    def test_get_catalog_draft_version_returns_404(self):
        # Register a draft directly in the engine
        engine = get_catalog_engine()
        draft = CatalogVersion(
            version_id="v9.9-draft-secret",
            status=CatalogStatus.DRAFT,
            currency="USD",
            preview_mode=True,
            disclaimer="Draft",
            plans=[],
            prices=[],
            matrix_features=[],
        )
        engine.register_version(draft)

        # Public API must NOT expose the draft
        response = self.client.get("/api/revenue/catalog?version=v9.9-draft-secret")
        self.assertEqual(response.status_code, 404)

    def test_get_catalog_versions_list_excludes_drafts(self):
        response = self.client.get("/api/revenue/catalog/versions")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("published_versions", data)
        self.assertIn("active_version", data)
        self.assertIn("v1.0-preview", data["published_versions"])
        # Ensure secret draft is not exposed in public version listing
        self.assertNotIn("v9.9-draft-secret", data["published_versions"])

    def test_revenue_endpoints_are_read_only(self):
        resp_post = self.client.post("/api/revenue/catalog", json={"dummy": True})
        self.assertIn(resp_post.status_code, [404, 405])

        resp_put = self.client.put("/api/revenue/catalog", json={"dummy": True})
        self.assertIn(resp_put.status_code, [404, 405])

        resp_delete = self.client.delete("/api/revenue/catalog")
        self.assertIn(resp_delete.status_code, [404, 405])

    def test_get_my_membership_unauthenticated_raises_401(self):
        resp = self.client.get("/api/revenue/membership/me")
        self.assertIn(resp.status_code, [401, 403])

    def test_get_my_membership_storage_unavailable_503(self):
        """When database connection is down, endpoint MUST fail closed with 503, never fake Free."""
        from backend.auth_utils import verify_token
        from unittest.mock import patch
        app.dependency_overrides[verify_token] = lambda: "test_member@saman.test"
        try:
            with patch("backend.app.services.entitlement_service.EntitlementService._get_db", return_value=None):
                resp = self.client.get("/api/revenue/membership/me")
                self.assertEqual(resp.status_code, 503)
                self.assertIn("unavailable", resp.json()["detail"].lower())
        finally:
            app.dependency_overrides.pop(verify_token, None)

    def test_get_my_membership_authenticated_authoritative_free(self):
        """Authoritative DB read confirms user has no paid subscription -> 200 Free."""
        from backend.auth_utils import verify_token
        from unittest.mock import patch
        from backend.app.database_revenue import COLL_SUBSCRIPTIONS, COLL_ENTITLEMENT_GRANTS, COLL_USAGE_BUCKETS
        app.dependency_overrides[verify_token] = lambda: "test_member@saman.test"
        mock_db = MockMongoDB()
        try:
            with patch("backend.app.services.entitlement_service.EntitlementService._get_db", return_value=mock_db):
                resp = self.client.get("/api/revenue/membership/me")
                self.assertEqual(resp.status_code, 200)
                data = resp.json()
                self.assertEqual(data["user_id"], "test_member@saman.test")
                self.assertEqual(data["tier"], "free")
                self.assertFalse(data["is_active_subscription"])
                self.assertIn("ai.nutrition_gemini", data["usage"])
                self.assertEqual(data["usage"]["ai.nutrition_gemini"]["limit_units"], 30)
                self.assertEqual(data["usage"]["ai.nutrition_gemini"]["remaining_units"], 30)
        finally:
            app.dependency_overrides.pop(verify_token, None)

    def test_get_my_membership_authenticated_with_plus_subscription(self):
        """Authoritative DB read finds active Plus subscription -> 200 Plus."""
        from backend.auth_utils import verify_token
        from unittest.mock import patch
        from backend.app.database_revenue import COLL_SUBSCRIPTIONS
        now = datetime.now(timezone.utc)
        app.dependency_overrides[verify_token] = lambda: "plus_member@saman.test"
        mock_db = MockMongoDB()
        mock_db[COLL_SUBSCRIPTIONS].insert_one({
            "user_id": "plus_member@saman.test",
            "tier": "plus",
            "status": "active",
            "current_period_start": now - timedelta(days=5),
            "current_period_end": now + timedelta(days=25),
        })
        try:
            with patch("backend.app.services.entitlement_service.EntitlementService._get_db", return_value=mock_db):
                resp = self.client.get("/api/revenue/membership/me")
                self.assertEqual(resp.status_code, 200)
                data = resp.json()
                self.assertEqual(data["user_id"], "plus_member@saman.test")
                self.assertEqual(data["tier"], "plus")
                self.assertTrue(data["is_active_subscription"])
        finally:
            app.dependency_overrides.pop(verify_token, None)

    def test_lookup_operation_by_idempotency_key(self):
        """Allows client to recover an operation by client idempotency key."""
        from backend.auth_utils import verify_token
        from unittest.mock import patch
        from backend.app.database_revenue import COLL_USAGE_OPERATIONS, COLL_FOOD_ANALYSIS_IDEMPOTENCY
        app.dependency_overrides[verify_token] = lambda: "recovery_user@saman.test"
        mock_db = MockMongoDB()
        mock_db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_recovery_123",
            "user_id": "recovery_user@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "idempotency_key": "idemp_rec_999",
            "client_request_id": "req_rec_999",
            "status": "committed",
            "units": 1,
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc),
        })
        mock_db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].insert_one({
            "user_id": "recovery_user@saman.test",
            "client_request_id": "req_rec_999",
            "response_payload": {"food_name": "Pho Bo", "nutrition": {"calories": 450, "protein": 25, "carbs": 55, "fat": 12}},
        })
        try:
            with patch("backend.app.services.quota_service.QuotaService._get_db", return_value=mock_db):
                resp = self.client.get("/api/revenue/operations/lookup?idempotency_key=idemp_rec_999&benefit_id=ai.nutrition_gemini")
                self.assertEqual(resp.status_code, 200)
                data = resp.json()
                self.assertEqual(data["operation_id"], "op_recovery_123")
                self.assertEqual(data["status"], "committed")
                self.assertIsNotNone(data["cached_payload"])
                self.assertEqual(data["cached_payload"]["food_name"], "Pho Bo")
        finally:
            app.dependency_overrides.pop(verify_token, None)



class MockMongoCollection:
    """
    Mock MongoDB collection to test index specifications and duplicate safety.
    Note: Explicitly a mock unit test fixture. Does NOT interact with live MongoDB.
    """

    def __init__(self, name: str, documents: List[Dict[str, Any]] = None):
        self.name = name
        self.documents = list(documents) if documents else []
        self.created_indexes: List[Dict[str, Any]] = []

    def find_one(self, filter_doc: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        filter_doc = filter_doc or {}
        for doc in self.documents:
            if self._matches_filter(doc, filter_doc):
                return doc
        return None

    def find(self, filter_doc: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        filter_doc = filter_doc or {}
        return [doc for doc in self.documents if self._matches_filter(doc, filter_doc)]

    def insert_one(self, doc: Dict[str, Any]):
        self.documents.append(doc)
        return doc

    def _matches_filter(self, doc: Dict[str, Any], filter_doc: Dict[str, Any]) -> bool:
        """Evaluates basic MongoDB match filters including $or and field type/exists checks."""
        for field, condition in filter_doc.items():
            if field == "$or":
                sub_conditions = condition
                if not any(self._matches_filter(doc, sub) for sub in sub_conditions):
                    return False
                continue

            val = doc.get(field)
            if isinstance(condition, dict):
                if "$exists" in condition:
                    should_exist = condition["$exists"]
                    if should_exist and field not in doc:
                        return False
                    if not should_exist and field in doc:
                        return False
                if "$type" in condition:
                    expected_type = condition["$type"]
                    if expected_type == "string" and not isinstance(val, str):
                        return False
                if "$ne" in condition:
                    if val == condition["$ne"]:
                        return False
            else:
                if val != condition:
                    return False
        return True

    def aggregate(self, pipeline: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Filter docs based on $match stages
        filtered_docs = list(self.documents)
        group_keys = {}

        for stage in pipeline:
            if "$match" in stage:
                filtered_docs = [d for d in filtered_docs if self._matches_filter(d, stage["$match"])]
            elif "$group" in stage:
                group_spec = stage["$group"]["_id"]
                group_keys = {k: v.lstrip("$") for k, v in group_spec.items()}

        counts: Dict[tuple, int] = {}
        for doc in filtered_docs:
            key_val = tuple(doc.get(field) for field in group_keys.values())
            counts[key_val] = counts.get(key_val, 0) + 1

        results = []
        for key_val, count in counts.items():
            if count > 1:
                results.append({"_id": dict(zip(group_keys.keys(), key_val)), "count": count})
        return results

    def create_index(self, keys, **kwargs):
        name = kwargs.get("name") or "_".join(f"{k}_{d}" for k, d in keys)
        self.created_indexes.append({"keys": keys, "name": name, "kwargs": kwargs})
        return name


class MockMongoDB:
    """Mock MongoDB database instance for unit tests."""

    def __init__(self):
        self.collections: Dict[str, MockMongoCollection] = {}

    def __getitem__(self, name: str) -> MockMongoCollection:
        if name not in self.collections:
            self.collections[name] = MockMongoCollection(name)
        return self.collections[name]


class TestRevenueDatabaseIndexesMock(unittest.TestCase):
    """
    Verifies database index specifications and duplicate safety using in-memory mock collections.
    NOTE: These are UNIT tests on specification contracts, NOT live MongoDB integration tests.
    """

    def test_specifications_cover_all_required_collections(self):
        colls = {coll_name for coll_name, _, _ in REVENUE_INDEX_SPECIFICATIONS}
        expected_colls = {
            COLL_SUBSCRIPTIONS,
            COLL_ENTITLEMENT_GRANTS,
            COLL_USAGE_BUCKETS,
            COLL_USAGE_OPERATIONS,
            COLL_PROVIDER_EVENTS,
            COLL_FOOD_ANALYSIS_IDEMPOTENCY,
        }
        self.assertEqual(colls, expected_colls)

    def test_subscription_scoped_identity_mock(self):
        mock_db = MockMongoDB()
        # Case A: Two different providers using the SAME transaction ID -> NO conflict!
        mock_db[COLL_SUBSCRIPTIONS].documents = [
            {"user_id": "u1", "provider": "apple_storekit", "environment": "production", "original_transaction_id": "TXN_SAME_123"},
            {"user_id": "u2", "provider": "google_play", "environment": "production", "original_transaction_id": "TXN_SAME_123"},
        ]
        # Should succeed because provider is part of the unique composite key
        ensure_revenue_indexes(db=mock_db, dry_run=False)

        # Case B: Two different environments with SAME provider and transaction ID -> NO conflict!
        mock_db[COLL_SUBSCRIPTIONS].documents = [
            {"user_id": "u1", "provider": "apple_storekit", "environment": "production", "original_transaction_id": "TXN_SAME_123"},
            {"user_id": "u2", "provider": "apple_storekit", "environment": "sandbox", "original_transaction_id": "TXN_SAME_123"},
        ]
        mock_db[COLL_SUBSCRIPTIONS].created_indexes.clear()
        ensure_revenue_indexes(db=mock_db, dry_run=False)

        # Case C: Multiple documents with original_transaction_id=None -> NO conflict!
        # partialFilterExpression excludes documents where original_transaction_id is not a string
        mock_db[COLL_SUBSCRIPTIONS].documents = [
            {"user_id": "u1", "provider": "manual_mock", "environment": "production", "original_transaction_id": None},
            {"user_id": "u2", "provider": "manual_mock", "environment": "production", "original_transaction_id": None},
        ]
        mock_db[COLL_SUBSCRIPTIONS].created_indexes.clear()
        ensure_revenue_indexes(db=mock_db, dry_run=False)

        # Case D: Duplicate within same provider + environment + transaction ID -> CONFLICT detected!
        mock_db[COLL_SUBSCRIPTIONS].documents = [
            {"user_id": "u1", "provider": "apple_storekit", "environment": "production", "original_transaction_id": "DUP_TXN_999"},
            {"user_id": "u2", "provider": "apple_storekit", "environment": "production", "original_transaction_id": "DUP_TXN_999"},
        ]
        mock_db[COLL_SUBSCRIPTIONS].created_indexes.clear()
        with self.assertRaises(RuntimeError) as ctx:
            ensure_revenue_indexes(db=mock_db, dry_run=False)
        self.assertIn("Refusing to create unique index", str(ctx.exception))
        self.assertIn("uniq_sub_provider_env_orig_txn_id", str(ctx.exception))

    def test_idempotency_scoped_identity_mock(self):
        mock_db = MockMongoDB()
        # Case A: User A and User B using the SAME client idempotency_key -> NO conflict!
        mock_db[COLL_USAGE_OPERATIONS].documents = [
            {"user_id": "user_A", "benefit_id": "ai.nutrition_gemini", "idempotency_key": "client_req_001"},
            {"user_id": "user_B", "benefit_id": "ai.nutrition_gemini", "idempotency_key": "client_req_001"},
        ]
        ensure_revenue_indexes(db=mock_db, dry_run=False)

        # Case B: Same User A using SAME idempotency_key for TWO DIFFERENT benefits -> NO conflict!
        mock_db[COLL_USAGE_OPERATIONS].documents = [
            {"user_id": "user_A", "benefit_id": "ai.nutrition_gemini", "idempotency_key": "client_req_001"},
            {"user_id": "user_A", "benefit_id": "ai.chat_coach", "idempotency_key": "client_req_001"},
        ]
        mock_db[COLL_USAGE_OPERATIONS].created_indexes.clear()
        ensure_revenue_indexes(db=mock_db, dry_run=False)

        # Case C: Same User, Same Benefit, Same Idempotency Key -> CONFLICT detected!
        mock_db[COLL_USAGE_OPERATIONS].documents = [
            {"user_id": "user_A", "benefit_id": "ai.nutrition_gemini", "idempotency_key": "client_req_001"},
            {"user_id": "user_A", "benefit_id": "ai.nutrition_gemini", "idempotency_key": "client_req_001"},
        ]
        mock_db[COLL_USAGE_OPERATIONS].created_indexes.clear()
        with self.assertRaises(RuntimeError) as ctx:
            ensure_revenue_indexes(db=mock_db, dry_run=False)
        self.assertIn("uniq_op_user_benefit_idempotency_key", str(ctx.exception))

    def test_food_analysis_cache_scoped_mock(self):
        mock_db = MockMongoDB()
        # Case A: User A and User B using SAME client_request_id in cache -> NO conflict!
        mock_db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].documents = [
            {"user_id": "user_A", "client_request_id": "img_upload_001"},
            {"user_id": "user_B", "client_request_id": "img_upload_001"},
        ]
        ensure_revenue_indexes(db=mock_db, dry_run=False)

        # Case B: Same user, same client_request_id -> CONFLICT detected!
        mock_db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].documents = [
            {"user_id": "user_A", "client_request_id": "img_upload_001"},
            {"user_id": "user_A", "client_request_id": "img_upload_001"},
        ]
        mock_db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].created_indexes.clear()
        with self.assertRaises(RuntimeError) as ctx:
            ensure_revenue_indexes(db=mock_db, dry_run=False)
        self.assertIn("uniq_fa_user_client_req_id", str(ctx.exception))

    def test_dry_run_modes(self):
        mock_db = MockMongoDB()
        # Spec-only dry-run: no DB reads
        results_spec = ensure_revenue_indexes(db=mock_db, dry_run=True, check_duplicates_in_dry_run=False)
        self.assertEqual(len(results_spec), 6)
        self.assertEqual(len(mock_db[COLL_SUBSCRIPTIONS].created_indexes), 0)

        # Audit dry-run: reads DB but does not create indexes
        results_audit = ensure_revenue_indexes(db=mock_db, dry_run=True, check_duplicates_in_dry_run=True)
        self.assertEqual(len(results_audit), 6)
        self.assertEqual(len(mock_db[COLL_SUBSCRIPTIONS].created_indexes), 0)


if __name__ == "__main__":
    unittest.main()
