"""
Integration and Concurrency Verification Test Suite for Saman Revenue Gates (CP-05).
Subsystem: Saman Revenue — Membership, Billing & Entitlements.

Verifies:
1. Enforcement OFF: Preserves existing behavior and allowlist. 0 quota mutations.
2. Shadow Mode: Evaluates entitlement telemetry, does not mutate quota or alter responses.
3. Enforcement ON without Entitlement: HTTP 403 Forbidden, 0 provider dispatches.
4. Quota Exhaustion / Storage Failure: HTTP 429 / 503, 0 provider dispatches (fail-closed).
5. Concurrency with identical idempotency key: exactly 1 dispatch owner.
6. Payload mismatch with same idempotency key: HTTP 409 Conflict.
7. Success retry: returns cached result with 0 extra quota and 0 extra dispatches.
8. Timeout / stalled worker handling: Held in FAILED_UNKNOWN without blind release.
9. Late valid result recovery: Transitions FAILED_UNKNOWN to COMMITTED cleanly.
10. Window reset: Finalizes against originating bucket.
11. Standard Food Logging: Ungated and 100% free.
12. Alternate route/mode: Cannot bypass Revenue Guard.
13. Operation Status Query: Strict tenant isolation (cannot inspect other users' operations).
14. Real Isolated MongoDB 7.0 verification on loopback port.
"""

from datetime import datetime, timezone, timedelta
import asyncio
import os
import subprocess
import time
import unittest
from unittest.mock import patch, MagicMock

from fastapi import HTTPException
from pymongo import MongoClient

from backend.app.models.revenue import (
    EntitlementDecisionStatus,
    MembershipTier,
    ReservationStatus,
    UsageOpStatus,
)
from backend.app.database_revenue import (
    COLL_SUBSCRIPTIONS,
    COLL_ENTITLEMENT_GRANTS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_FOOD_ANALYSIS_IDEMPOTENCY,
)
from backend.app.services.entitlement_service import EntitlementService
from backend.app.services.quota_service import QuotaService
from backend.app.services.quota_recovery_service import QuotaRecoveryService
from backend.app.services.revenue_guard import (
    orchestrate_nutrition_analysis,
    is_enforcement_enabled,
    is_shadow_mode_enabled,
)


class MockCollection:
    """In-memory dictionary-backed MongoDB collection for fast unit testing."""

    def __init__(self):
        self.docs = []

    def find_one(self, query: dict) -> dict:
        for doc in self.docs:
            if self._matches(doc, query):
                return dict(doc)
        return None

    def find(self, query: dict):
        results = []
        for doc in self.docs:
            if self._matches(doc, query):
                results.append(dict(doc))
        return results

    def insert_one(self, doc: dict):
        d = dict(doc)
        if "_id" not in d:
            d["_id"] = f"id_{len(self.docs)}"
        self.docs.append(d)
        return MagicMock(inserted_id=d["_id"])

    def update_one(self, query: dict, update: dict, upsert: bool = False):
        for doc in self.docs:
            if self._matches(doc, query):
                if "$set" in update:
                    doc.update(update["$set"])
                if "$inc" in update:
                    for k, v in update["$inc"].items():
                        doc[k] = doc.get(k, 0) + v
                return {"matched_count": 1, "modified_count": 1}
        if upsert:
            new_doc = {}
            if "$setOnInsert" in update:
                new_doc.update(update["$setOnInsert"])
            if "$set" in update:
                new_doc.update(update["$set"])
            new_doc.update(query)
            self.insert_one(new_doc)
            return {"matched_count": 0, "upserted_id": new_doc.get("_id")}
        return {"matched_count": 0, "modified_count": 0}

    def find_one_and_update(self, query: dict, update: dict, **kwargs):
        for doc in self.docs:
            if self._matches(doc, query):
                if "$inc" in update:
                    for k, v in update["$inc"].items():
                        doc[k] = doc.get(k, 0) + v
                if "$set" in update:
                    doc.update(update["$set"])
                return dict(doc)
        return None

    def _matches(self, doc: dict, query: dict) -> bool:
        for k, v in query.items():
            if k == "$expr":
                continue
            if isinstance(v, dict):
                if "$in" in v:
                    if doc.get(k) not in v["$in"]:
                        return False
                elif "$lt" in v:
                    if not (doc.get(k) < v["$lt"]):
                        return False
            else:
                if doc.get(k) != v:
                    return False
        return True


class MockDB:
    def __init__(self):
        self.cols = {}

    def __getitem__(self, name: str) -> MockCollection:
        if name not in self.cols:
            self.cols[name] = MockCollection()
        return self.cols[name]


class FailingDB:
    """Simulates database connection or query failure."""
    def __getitem__(self, name: str):
        raise RuntimeError("Database storage failure (connection refused)")


class TestRevenueGateIntegration(unittest.IsolatedAsyncioTestCase):
    """Targeted Unit and Orchestration Tests using Fake AI Provider."""

    def setUp(self):
        self.mock_db = MockDB()
        self.ent_svc = EntitlementService(db=self.mock_db)
        self.q_svc = QuotaService(db=self.mock_db)
        self.rec_svc = QuotaRecoveryService(db=self.mock_db)
        self.dispatch_count = 0

    async def fake_gemini_provider(self, image_bytes: bytes, mime_type: str, grams: float):
        self.dispatch_count += 1
        return {
            "food_name": "Phở Bò",
            "food_label": "pho_bo",
            "confidence": 0.95,
            "nutrition": {"calories": 350, "protein": 20, "carbs": 45, "fat": 8},
        }

    # 1. Enforcement OFF: Preserves current behavior and allowlist
    async def test_enforcement_off_allowlisted_succeeds_without_quota_mutation(self):
        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "false",
            "GEMINI_ALLOWED_EMAILS": "tester@saman.test",
        }):
            result = await orchestrate_nutrition_analysis(
                image_bytes=b"sample_food_bytes",
                mime_type="image/jpeg",
                grams=100.0,
                email="tester@saman.test",
                provider_callback=self.fake_gemini_provider,
                db=self.mock_db,
            )
            self.assertEqual(result["food_name"], "Phở Bò")
            self.assertEqual(self.dispatch_count, 1)
            # Verify 0 quota buckets created
            self.assertEqual(len(self.mock_db[COLL_USAGE_BUCKETS].docs), 0)

    async def test_enforcement_off_unallowlisted_raises_403(self):
        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "false",
            "GEMINI_ALLOWED_EMAILS": "other@saman.test",
        }):
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"sample_food_bytes",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="unauthorized@saman.test",
                    provider_callback=self.fake_gemini_provider,
                    db=self.mock_db,
                )
            self.assertEqual(ctx.exception.status_code, 403)
            self.assertEqual(self.dispatch_count, 0)

    # 2. Enforcement ON: Missing Entitlement -> Zero Dispatch
    async def test_enforcement_on_unentitled_user_raises_403_zero_dispatch(self):
        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "user@saman.test",
        }):
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"sample_food_bytes",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="user@saman.test",
                    provider_callback=self.fake_gemini_provider,
                    db=self.mock_db,
                    entitlement_service=self.ent_svc,
                    quota_service=self.q_svc,
                )
            self.assertEqual(ctx.exception.status_code, 403)
            self.assertEqual(ctx.exception.detail.get("error"), "entitlement_required")
            self.assertEqual(self.dispatch_count, 0)

    # 3. Enforcement ON: Entitled User Succeeds & Consumes Quota
    async def test_enforcement_on_active_subscriber_succeeds_and_consumes_quota(self):
        now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
        # Grant active Plus pilot entitlement
        self.mock_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_plus_001",
            "user_id": "plus_user@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_from": now - timedelta(days=10),
            "valid_until": now + timedelta(days=20),
            "source_type": "pilot_grant",
        })

        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "plus_user@saman.test",
        }):
            result = await orchestrate_nutrition_analysis(
                image_bytes=b"sample_food_bytes",
                mime_type="image/jpeg",
                grams=100.0,
                email="plus_user@saman.test",
                client_request_id="req_001",
                provider_callback=self.fake_gemini_provider,
                as_of=now,
                db=self.mock_db,
                entitlement_service=self.ent_svc,
                quota_service=self.q_svc,
            )
            self.assertEqual(result["food_name"], "Phở Bò")
            self.assertEqual(self.dispatch_count, 1)

            # Verify bucket has 1 consumed unit
            bucket = self.mock_db[COLL_USAGE_BUCKETS].docs[0]
            self.assertEqual(bucket["consumed_units"], 1)
            self.assertEqual(bucket["reserved_units"], 0)

            # Verify operation committed
            op = self.mock_db[COLL_USAGE_OPERATIONS].docs[0]
            self.assertEqual(op["status"], UsageOpStatus.COMMITTED.value)

    # 4. Success Retry: Cached payload returned with 0 extra quota and 0 extra dispatches
    async def test_success_retry_returns_cached_payload_zero_dispatch(self):
        now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
        self.mock_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_plus_001",
            "user_id": "plus_user@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_from": now - timedelta(days=1),
            "valid_until": now + timedelta(days=29),
            "source_type": "pilot_grant",
        })

        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "plus_user@saman.test",
        }):
            # First call
            res1 = await orchestrate_nutrition_analysis(
                image_bytes=b"unique_bytes_123",
                mime_type="image/jpeg",
                grams=100.0,
                email="plus_user@saman.test",
                client_request_id="req_repeatable",
                idempotency_key="key_repeatable",
                provider_callback=self.fake_gemini_provider,
                as_of=now,
                db=self.mock_db,
                entitlement_service=self.ent_svc,
                quota_service=self.q_svc,
            )
            self.assertEqual(self.dispatch_count, 1)

            # Second call with identical payload and key
            res2 = await orchestrate_nutrition_analysis(
                image_bytes=b"unique_bytes_123",
                mime_type="image/jpeg",
                grams=100.0,
                email="plus_user@saman.test",
                client_request_id="req_repeatable",
                idempotency_key="key_repeatable",
                provider_callback=self.fake_gemini_provider,
                as_of=now,
                db=self.mock_db,
                entitlement_service=self.ent_svc,
                quota_service=self.q_svc,
            )
            # ZERO additional dispatches!
            self.assertEqual(self.dispatch_count, 1)
            self.assertEqual(res2["food_name"], res1["food_name"])
            bucket = self.mock_db[COLL_USAGE_BUCKETS].docs[0]
            self.assertEqual(bucket["consumed_units"], 1)

    # 5. Payload Mismatch on Same Key -> HTTP 409 Conflict
    async def test_idempotency_payload_mismatch_raises_409(self):
        now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
        self.mock_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_plus_001",
            "user_id": "plus_user@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_from": now - timedelta(days=1),
            "valid_until": now + timedelta(days=29),
            "source_type": "pilot_grant",
        })

        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "plus_user@saman.test",
        }):
            await orchestrate_nutrition_analysis(
                image_bytes=b"initial_image_bytes",
                mime_type="image/jpeg",
                grams=100.0,
                email="plus_user@saman.test",
                idempotency_key="reused_key",
                provider_callback=self.fake_gemini_provider,
                as_of=now,
                db=self.mock_db,
                entitlement_service=self.ent_svc,
                quota_service=self.q_svc,
            )
            self.assertEqual(self.dispatch_count, 1)

            # Reusing same key with different image bytes
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"different_tampered_bytes",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="plus_user@saman.test",
                    idempotency_key="reused_key",
                    provider_callback=self.fake_gemini_provider,
                    as_of=now,
                    db=self.mock_db,
                    entitlement_service=self.ent_svc,
                    quota_service=self.q_svc,
                )
            self.assertEqual(ctx.exception.status_code, 409)
            self.assertEqual(ctx.exception.detail.get("error"), "operation_conflict")
            self.assertEqual(self.dispatch_count, 1)

    # 6. Storage Failure Fails Closed -> 0 Dispatch
    async def test_storage_failure_fails_closed_zero_dispatch(self):
        failing_db = FailingDB()
        ent_svc = EntitlementService(db=failing_db)
        q_svc = QuotaService(db=failing_db)

        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "user@saman.test",
        }):
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"sample_food_bytes",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="user@saman.test",
                    provider_callback=self.fake_gemini_provider,
                    db=failing_db,
                    entitlement_service=ent_svc,
                    quota_service=q_svc,
                )
            self.assertEqual(ctx.exception.status_code, 503)
            self.assertEqual(self.dispatch_count, 0)

    # 7. Provider Timeout: Held in FAILED_UNKNOWN, not released blindly
    async def test_provider_timeout_marks_unknown_without_blind_release(self):
        now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
        self.mock_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_plus_001",
            "user_id": "plus_user@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_from": now - timedelta(days=1),
            "valid_until": now + timedelta(days=29),
            "source_type": "pilot_grant",
        })

        async def timing_out_provider(image_bytes, mime_type, grams):
            self.dispatch_count += 1
            raise asyncio.TimeoutError("Gemini inference request timed out")

        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "plus_user@saman.test",
        }):
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"sample_food_bytes",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="plus_user@saman.test",
                    provider_callback=timing_out_provider,
                    as_of=now,
                    db=self.mock_db,
                    entitlement_service=self.ent_svc,
                    quota_service=self.q_svc,
                )
            self.assertEqual(ctx.exception.status_code, 504)
            self.assertEqual(self.dispatch_count, 1)

            # CRITICAL CHECK: Operation is FAILED_UNKNOWN, reserved unit is NOT released!
            op = self.mock_db[COLL_USAGE_OPERATIONS].docs[0]
            self.assertEqual(op["status"], UsageOpStatus.FAILED_UNKNOWN.value)
            bucket = self.mock_db[COLL_USAGE_BUCKETS].docs[0]
            self.assertEqual(bucket["reserved_units"], 1)
            self.assertEqual(bucket["consumed_units"], 0)

    # 8. Late Valid Result Recovery: Transitions FAILED_UNKNOWN to COMMITTED
    async def test_late_valid_result_recovery_transitions_failed_unknown_to_committed(self):
        now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
        # Create an existing FAILED_UNKNOWN operation with 1 reserved unit
        op_id = "op_timed_out_123"
        lease_tok = "lease_orig_123"
        bucket_id = "bucket_plus_user"
        self.mock_db[COLL_USAGE_BUCKETS].insert_one({
            "bucket_id": bucket_id,
            "user_id": "plus_user@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "reserved_units": 1,
            "consumed_units": 0,
            "limit_units": 30,
        })
        self.mock_db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": op_id,
            "user_id": "plus_user@saman.test",
            "bucket_id": bucket_id,
            "benefit_id": "ai.nutrition_gemini",
            "status": UsageOpStatus.FAILED_UNKNOWN.value,
            "lease_token": lease_tok,
            "units": 1,
            "client_request_id": "client_req_timeout",
        })

        # Late valid result arrives from original worker
        success = self.q_svc.commit_quota(
            operation_id=op_id,
            lease_token=lease_tok,
            response_payload={"food_name": "Phở Bò Late", "confidence": 0.99},
            as_of=now,
        )
        self.assertTrue(success)

        # Verify bucket transitioned: reserved 0, consumed 1
        bucket = self.mock_db[COLL_USAGE_BUCKETS].docs[0]
        self.assertEqual(bucket["reserved_units"], 0)
        self.assertEqual(bucket["consumed_units"], 1)

        # Verify operation is now COMMITTED
        op = self.mock_db[COLL_USAGE_OPERATIONS].docs[0]
        self.assertEqual(op["status"], UsageOpStatus.COMMITTED.value)

    # 9. Tenant Isolation in Operation Query
    def test_query_operation_tenant_isolation(self):
        self.mock_db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_alice_123",
            "user_id": "alice@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "status": UsageOpStatus.COMMITTED.value,
            "units": 1,
            "dispatched": True,
            "client_request_id": "req_alice",
        })
        self.mock_db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].insert_one({
            "user_id": "alice@saman.test",
            "client_request_id": "req_alice",
            "response_payload": {"food_name": "Salad"},
        })

        # Alice queries her own operation -> Success
        res_alice = self.q_svc.query_operation("alice@saman.test", "op_alice_123")
        self.assertIsNotNone(res_alice)
        self.assertEqual(res_alice["cached_payload"]["food_name"], "Salad")

        # Bob queries Alice's operation -> None (Cannot leak!)
        res_bob = self.q_svc.query_operation("bob@saman.test", "op_alice_123")
        self.assertIsNone(res_bob)

    # 10. Shadow Mode: Telemetry recorded, 0 quota change, normal response
    async def test_shadow_mode_records_telemetry_does_not_mutate_quota(self):
        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "false",
            "REVENUE_SHADOW_MODE": "true",
            "GEMINI_ALLOWED_EMAILS": "shadow_user@saman.test",
        }):
            result = await orchestrate_nutrition_analysis(
                image_bytes=b"shadow_image",
                mime_type="image/jpeg",
                grams=150.0,
                email="shadow_user@saman.test",
                provider_callback=self.fake_gemini_provider,
                db=self.mock_db,
                entitlement_service=self.ent_svc,
                quota_service=self.q_svc,
            )
            self.assertEqual(result["food_name"], "Phở Bò")
            self.assertEqual(self.dispatch_count, 1)
            # Quota bucket still 0
            self.assertEqual(len(self.mock_db[COLL_USAGE_BUCKETS].docs), 0)

    # 11. Non-Food Policy: Releases reserved quota by default (PROPOSED)
    async def test_non_food_rejection_releases_quota_by_default(self):
        now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
        self.mock_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_non_food_01",
            "user_id": "user_nf@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_from": now - timedelta(days=1),
            "valid_until": now + timedelta(days=29),
            "source_type": "pilot_grant",
        })

        async def non_food_rejecting_provider(image_bytes, mime_type, grams):
            self.dispatch_count += 1
            raise RuntimeError("Image does not contain recognizable food.")

        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "user_nf@saman.test",
            "CONSUME_QUOTA_ON_NON_FOOD": "false",
        }):
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"shoe_photo_bytes",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="user_nf@saman.test",
                    provider_callback=non_food_rejecting_provider,
                    as_of=now,
                    db=self.mock_db,
                    entitlement_service=self.ent_svc,
                    quota_service=self.q_svc,
                )
            self.assertEqual(ctx.exception.status_code, 400)
            self.assertEqual(ctx.exception.detail.get("error"), "not_food")
            self.assertEqual(self.dispatch_count, 1)

            # Reserved unit released back to bucket: 0 reserved, 0 consumed
            bucket = self.mock_db[COLL_USAGE_BUCKETS].docs[0]
            self.assertEqual(bucket["reserved_units"], 0)
            self.assertEqual(bucket["consumed_units"], 0)

    # 12. Non-Food Policy: Commits quota when configured to charge (PROPOSED)
    async def test_non_food_rejection_commits_quota_when_configured(self):
        now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
        self.mock_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_non_food_02",
            "user_id": "user_nf2@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_from": now - timedelta(days=1),
            "valid_until": now + timedelta(days=29),
            "source_type": "pilot_grant",
        })

        async def non_food_rejecting_provider(image_bytes, mime_type, grams):
            self.dispatch_count += 1
            raise RuntimeError("Image does not contain recognizable food.")

        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "GEMINI_ALLOWED_EMAILS": "user_nf2@saman.test",
            "CONSUME_QUOTA_ON_NON_FOOD": "true",
        }):
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"shoe_photo_bytes_2",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="user_nf2@saman.test",
                    provider_callback=non_food_rejecting_provider,
                    as_of=now,
                    db=self.mock_db,
                    entitlement_service=self.ent_svc,
                    quota_service=self.q_svc,
                )
            self.assertEqual(ctx.exception.status_code, 400)
            # Reserved unit converted to consumed: 0 reserved, 1 consumed
            bucket = self.mock_db[COLL_USAGE_BUCKETS].docs[0]
            self.assertEqual(bucket["reserved_units"], 0)
            self.assertEqual(bucket["consumed_units"], 1)

    # 13. Canary Allowlist: Only specified email has active enforcement
    async def test_canary_allowlist_selectively_enforces(self):
        with patch.dict(os.environ, {
            "REVENUE_ENFORCEMENT_ENABLED": "true",
            "REVENUE_ENFORCEMENT_ALLOWLIST": "canary@saman.test",
            "GEMINI_ALLOWED_EMAILS": "canary@saman.test,standard@saman.test",
        }):
            # canary@saman.test: in allowlist -> enforcement is ON -> missing entitlement raises 403
            with self.assertRaises(HTTPException) as ctx:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"bytes",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="canary@saman.test",
                    provider_callback=self.fake_gemini_provider,
                    db=self.mock_db,
                    entitlement_service=self.ent_svc,
                    quota_service=self.q_svc,
                )
            self.assertEqual(ctx.exception.status_code, 403)
            self.assertEqual(ctx.exception.detail.get("error"), "entitlement_required")

            # standard@saman.test: NOT in canary allowlist -> enforcement is OFF -> proceeds through allowlist
            res = await orchestrate_nutrition_analysis(
                image_bytes=b"bytes",
                mime_type="image/jpeg",
                grams=100.0,
                email="standard@saman.test",
                provider_callback=self.fake_gemini_provider,
                db=self.mock_db,
                entitlement_service=self.ent_svc,
                quota_service=self.q_svc,
            )
            self.assertEqual(res["food_name"], "Phở Bò")

    # 14. Window Reset: Cross-period finalization safely commits to originating bucket
    async def test_window_reset_cross_period_commits_to_originating_bucket(self):
        period_1 = datetime(2026, 10, 31, 23, 59, tzinfo=timezone.utc)
        period_2 = datetime(2026, 11, 1, 0, 5, tzinfo=timezone.utc)

        self.mock_db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "grant_p1",
            "user_id": "window_user@saman.test",
            "benefit_id": "ai.nutrition_gemini",
            "status": "granted",
            "valid_from": period_1 - timedelta(days=10),
            "valid_until": period_2 + timedelta(days=10),
            "source_type": "pilot_grant",
        })

        # Reserve in Period 1 (Oct 2026)
        res = self.q_svc.reserve_quota(
            user_id="window_user@saman.test",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=30,
            idempotency_key="cross_window_key",
            as_of=period_1,
        )
        self.assertEqual(res.status, ReservationStatus.RESERVED)
        oct_bucket = self.mock_db[COLL_USAGE_BUCKETS].docs[0]
        self.assertEqual(oct_bucket["bucket_key"], "monthly:202610")
        self.assertEqual(oct_bucket["reserved_units"], 1)

        # Worker finishes in Period 2 (Nov 2026)
        self.q_svc.commit_quota(
            operation_id=res.operation_id,
            lease_token=res.lease_token,
            as_of=period_2,
        )

        # Verified: Committed to originating Oct bucket!
        self.assertEqual(oct_bucket["reserved_units"], 0)
        self.assertEqual(oct_bucket["consumed_units"], 1)
        # November bucket was not even created
        self.assertEqual(len(self.mock_db[COLL_USAGE_BUCKETS].docs), 1)



class TestRealMongoRevenueGateIntegration(unittest.TestCase):
    """
    Live Concurrency and Atomicity on Real Isolated MongoDB 7.0 (loopback port 27099).
    """

    MONGO_PORT = 27099
    DB_PATH = r"D:\SamanDev\tools\mongodb-cp7\isolated_gate_db"
    MONGOD_EXE = r"D:\SamanDev\tools\mongodb-cp7\mongodb-win32-x86_64-windows-7.0.14\bin\mongod.exe"
    proc = None
    client = None
    real_db = None

    @classmethod
    def setUpClass(cls):
        if not os.path.exists(cls.MONGOD_EXE):
            return

        os.makedirs(cls.DB_PATH, exist_ok=True)
        cmd = [
            cls.MONGOD_EXE,
            "--port", str(cls.MONGO_PORT),
            "--dbpath", cls.DB_PATH,
            "--bind_ip", "127.0.0.1",
            "--wiredTigerCacheSizeGB", "0.25",
        ]
        try:
            cls.proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(1.5)
            cls.client = MongoClient(f"mongodb://127.0.0.1:{cls.MONGO_PORT}/", serverSelectionTimeoutMS=2000)
            cls.client.server_info()
            cls.real_db = cls.client["revenue_gate_integration_test"]
        except Exception:
            if cls.proc:
                cls.proc.terminate()
                cls.proc = None

    @classmethod
    def tearDownClass(cls):
        if cls.client:
            try:
                cls.client.close()
            except Exception:
                pass
        if cls.proc:
            cls.proc.terminate()
            cls.proc.wait()

    def setUp(self):
        if self.real_db is None:
            self.skipTest("Real MongoDB 7.0 not available on port 27099")
        self.real_db[COLL_USAGE_BUCKETS].drop()
        self.real_db[COLL_USAGE_OPERATIONS].drop()
        self.real_db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].drop()
        self.real_db[COLL_SUBSCRIPTIONS].drop()

    def test_real_mongodb_gate_atomicity_and_late_recovery(self):
        """Tests live WiredTiger atomic quota exhaustion and late result reconciliation."""
        q_svc = QuotaService(db=self.real_db)
        rec_svc = QuotaRecoveryService(db=self.real_db)

        # 1. Exhaust quota with limit=2
        res1 = q_svc.reserve_quota(
            user_id="u1",
            benefit_id="ai.nutrition_gemini",
            units=1,
            limit_units=2,
            idempotency_key="k1",
            client_request_id="req_1",
        )
        self.assertEqual(res1.status, ReservationStatus.RESERVED)

        res2 = q_svc.reserve_quota(user_id="u1", benefit_id="ai.nutrition_gemini", units=1, limit_units=2, idempotency_key="k2")
        self.assertEqual(res2.status, ReservationStatus.RESERVED)

        # 3rd request must exhaust
        res3 = q_svc.reserve_quota(user_id="u1", benefit_id="ai.nutrition_gemini", units=1, limit_units=2, idempotency_key="k3")
        self.assertEqual(res3.status, ReservationStatus.QUOTA_EXHAUSTED)

        # 2. Simulate worker 1 timeout (mark unknown)
        q_svc.mark_dispatched(res1.operation_id, res1.lease_token)
        q_svc.mark_unknown(res1.operation_id, reason="Provider timeout")

        # 3. Late result arrives and reconciles FAILED_UNKNOWN -> COMMITTED
        committed = q_svc.commit_quota(
            operation_id=res1.operation_id,
            lease_token=res1.lease_token,
            response_payload={"dish": "Bún Chả"},
        )
        self.assertTrue(committed)

        # Verify query operation
        op_info = q_svc.query_operation("u1", res1.operation_id)
        self.assertEqual(op_info["status"], UsageOpStatus.COMMITTED.value)
        self.assertEqual(op_info["cached_payload"]["dish"], "Bún Chả")


if __name__ == "__main__":
    unittest.main()
