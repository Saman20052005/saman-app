"""
Offline unit tests for Phase 2 Quota Limits & Revenue Operation Account-ID Alignment.

Covers:
1. TIER_QUOTA_LIMITS["*"]["workout.cv.ai"] across free/plus/pro/ultra.
2. TIER_STORAGE_LIMITS_MB & get_video_story_storage_limit_mb (all tiers, normalization, unknown).
3. TIER_VIDEO_CITATION_DAYS & get_video_citation_days (all tiers, normalization, unknown).
4. /api/revenue/operations/lookup: account_id priority over email, legacy email fallback, 404/503 fail-safe.
5. /api/revenue/operations/{operation_id}: account_id lookup, legacy email fallback, tenant isolation, 503 fail-safe.
"""

from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
BACKEND_DIR = REPO_ROOT / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from backend.app.database_revenue import (
    COLL_FOOD_ANALYSIS_IDEMPOTENCY,
    COLL_USAGE_OPERATIONS,
)
from backend.app.services.quota_service import (
    TIER_QUOTA_LIMITS,
    TIER_STORAGE_LIMITS_MB,
    TIER_VIDEO_CITATION_DAYS,
    QuotaService,
    get_video_citation_days,
    get_video_story_storage_limit_mb,
)
from backend.auth_utils import verify_token
from backend.routers.revenue import router as revenue_router


# ---------------------------------------------------------------------------
# Lightweight offline in-memory MongoDB mock
# ---------------------------------------------------------------------------


class _MockCollection:
    def __init__(self, name: str):
        self.name = name
        self.docs: List[Dict[str, Any]] = []

    def _matches(self, doc: Dict[str, Any], query: Optional[Dict[str, Any]]) -> bool:
        if not query:
            return True
        for k, v in query.items():
            if doc.get(k) != v:
                return False
        return True

    def find_one(self, query: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        for d in self.docs:
            if self._matches(d, query):
                return deepcopy(d)
        return None

    def find(self, query: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        return [deepcopy(d) for d in self.docs if self._matches(d, query)]

    def insert_one(self, doc: Dict[str, Any]):
        d = deepcopy(doc)
        if "_id" not in d:
            d["_id"] = f"{self.name}_{len(self.docs) + 1}"
        self.docs.append(d)
        return type("InsertRes", (), {"inserted_id": d["_id"]})()

    def update_one(self, query: Dict[str, Any], update: Dict[str, Any], upsert: bool = False):
        for d in self.docs:
            if self._matches(d, query):
                if "$set" in update:
                    d.update(deepcopy(update["$set"]))
                return type("UpdateRes", (), {"matched_count": 1, "modified_count": 1})()
        if upsert:
            new_doc = deepcopy(query)
            if "$set" in update:
                new_doc.update(deepcopy(update["$set"]))
            self.insert_one(new_doc)
            return type("UpdateRes", (), {"matched_count": 0, "modified_count": 1})()
        return type("UpdateRes", (), {"matched_count": 0, "modified_count": 0})()


class _MockDB:
    def __init__(self):
        self._cols: Dict[str, _MockCollection] = {}

    def __getitem__(self, name: str) -> _MockCollection:
        if name not in self._cols:
            self._cols[name] = _MockCollection(name)
        return self._cols[name]


def _make_revenue_client(email: str) -> TestClient:
    app = FastAPI()
    app.include_router(revenue_router)
    app.dependency_overrides[verify_token] = lambda: email
    return TestClient(app)


# ---------------------------------------------------------------------------
# 1. Quota & Storage / Video Citation Constants and Helpers
# ---------------------------------------------------------------------------


class TestPhase2QuotaTablesAndHelpers:
    def test_workout_cv_ai_limits_all_four_tiers(self):
        assert TIER_QUOTA_LIMITS["free"]["workout.cv.ai"] == ("weekly", 2)
        assert TIER_QUOTA_LIMITS["plus"]["workout.cv.ai"] == ("weekly", 5)
        assert TIER_QUOTA_LIMITS["pro"]["workout.cv.ai"] == ("weekly", -1)
        assert TIER_QUOTA_LIMITS["ultra"]["workout.cv.ai"] == ("weekly", -1)

        # Ensure existing AI chat & nutrition limits remain untouched
        assert TIER_QUOTA_LIMITS["plus"]["ai.chat.swift3"] == ("daily", 30)
        assert TIER_QUOTA_LIMITS["plus"]["ai.chat.core3"] == ("daily", 10)
        assert TIER_QUOTA_LIMITS["plus"]["ai.chat.pro3"] == ("daily", 0)
        assert TIER_QUOTA_LIMITS["plus"]["ai.nutrition_gemini"] == ("daily", 5)

    def test_tier_storage_limits_mb_and_helper(self):
        assert TIER_STORAGE_LIMITS_MB == {
            "free": 0,
            "plus": 500,
            "pro": 5000,
            "ultra": 20000,
        }
        assert get_video_story_storage_limit_mb("free") == 0
        assert get_video_story_storage_limit_mb("plus") == 500
        assert get_video_story_storage_limit_mb("pro") == 5000
        assert get_video_story_storage_limit_mb("ultra") == 20000

        # Normalization: uppercase & surrounding whitespace
        assert get_video_story_storage_limit_mb("  PLUS  ") == 500
        assert get_video_story_storage_limit_mb("Pro\t") == 5000
        assert get_video_story_storage_limit_mb(" ULTRA\n") == 20000

        # Unknown / empty / None tier returns 0
        assert get_video_story_storage_limit_mb("enterprise") == 0
        assert get_video_story_storage_limit_mb("") == 0
        assert get_video_story_storage_limit_mb(None) == 0  # type: ignore[arg-type]

    def test_tier_video_citation_days_and_helper(self):
        assert TIER_VIDEO_CITATION_DAYS == {
            "free": 0,
            "plus": 7,
            "pro": 14,
            "ultra": 30,
        }
        assert get_video_citation_days("free") == 0
        assert get_video_citation_days("plus") == 7
        assert get_video_citation_days("pro") == 14
        assert get_video_citation_days("ultra") == 30

        # Normalization: uppercase & surrounding whitespace
        assert get_video_citation_days("  Plus ") == 7
        assert get_video_citation_days("PRO") == 14
        assert get_video_citation_days("  uLtRa  ") == 30

        # Unknown / empty / None tier returns 0
        assert get_video_citation_days("unknown_tier") == 0
        assert get_video_citation_days("") == 0
        assert get_video_citation_days(None) == 0  # type: ignore[arg-type]


# ---------------------------------------------------------------------------
# 2. Revenue Operations Lookup & Status with account_id + Legacy Fallback
# ---------------------------------------------------------------------------


class TestRevenueOperationsAccountIdAlignment:
    ACCOUNT_ID = "acct_0123456789abcdef0123456789abcdef"
    USER_EMAIL = "athlete@saman.test"

    def _seed_user(self, db: _MockDB) -> None:
        db["users"].insert_one({
            "email": self.USER_EMAIL,
            "account_id": self.ACCOUNT_ID,
        })

    def test_operations_lookup_prefers_account_id_over_email(self, monkeypatch):
        db = _MockDB()
        self._seed_user(db)
        now = datetime.now(timezone.utc)

        # Seed BOTH an account_id record and a legacy email record with same idempotency_key
        db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_canonical_acct",
            "user_id": self.ACCOUNT_ID,
            "benefit_id": "ai.nutrition_gemini",
            "idempotency_key": "idem_shared_key",
            "client_request_id": "req_acct",
            "status": "committed",
            "units": 1,
            "created_at": now,
            "updated_at": now,
        })
        db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].insert_one({
            "user_id": self.ACCOUNT_ID,
            "client_request_id": "req_acct",
            "response_payload": {"food_name": "Canonical Account Dish"},
        })
        db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_legacy_email",
            "user_id": self.USER_EMAIL,
            "benefit_id": "ai.nutrition_gemini",
            "idempotency_key": "idem_shared_key",
            "client_request_id": "req_email",
            "status": "committed",
            "units": 1,
            "created_at": now,
            "updated_at": now,
        })
        db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].insert_one({
            "user_id": self.USER_EMAIL,
            "client_request_id": "req_email",
            "response_payload": {"food_name": "Legacy Email Dish"},
        })

        monkeypatch.setattr(QuotaService, "_get_db", lambda self_svc: db)
        client = _make_revenue_client(self.USER_EMAIL)

        resp = client.get(
            "/api/revenue/operations/lookup",
            params={
                "idempotency_key": "idem_shared_key",
                "benefit_id": "ai.nutrition_gemini",
            },
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["operation_id"] == "op_canonical_acct"
        assert body["user_id"] == self.ACCOUNT_ID
        assert body["cached_payload"]["food_name"] == "Canonical Account Dish"

    def test_operations_lookup_falls_back_to_legacy_email(self, monkeypatch):
        db = _MockDB()
        self._seed_user(db)
        now = datetime.now(timezone.utc)

        # Only legacy email-keyed operation exists
        db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_legacy_only",
            "user_id": self.USER_EMAIL,
            "benefit_id": "ai.nutrition_gemini",
            "idempotency_key": "idem_legacy_only",
            "client_request_id": "req_legacy_only",
            "status": "committed",
            "units": 1,
            "created_at": now,
            "updated_at": now,
        })
        db[COLL_FOOD_ANALYSIS_IDEMPOTENCY].insert_one({
            "user_id": self.USER_EMAIL,
            "client_request_id": "req_legacy_only",
            "response_payload": {"food_name": "Legacy Pho"},
        })

        monkeypatch.setattr(QuotaService, "_get_db", lambda self_svc: db)
        client = _make_revenue_client(self.USER_EMAIL)

        resp = client.get(
            "/api/revenue/operations/lookup",
            params={
                "idempotency_key": "idem_legacy_only",
                "benefit_id": "ai.nutrition_gemini",
            },
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["operation_id"] == "op_legacy_only"
        assert body["user_id"] == self.USER_EMAIL
        assert body["cached_payload"]["food_name"] == "Legacy Pho"

    def test_get_operation_status_by_account_id_and_legacy_email_fallback(self, monkeypatch):
        db = _MockDB()
        self._seed_user(db)
        now = datetime.now(timezone.utc)

        # 1. Canonical operation stored under account_id
        db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_acct_001",
            "user_id": self.ACCOUNT_ID,
            "benefit_id": "ai.chat.core3",
            "status": "committed",
            "units": 1,
            "created_at": now,
            "updated_at": now,
        })
        # 2. Legacy operation stored under email
        db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_email_legacy_002",
            "user_id": self.USER_EMAIL,
            "benefit_id": "ai.nutrition_gemini",
            "status": "committed",
            "units": 1,
            "created_at": now,
            "updated_at": now,
        })
        # 3. Another user's operation (must remain isolated -> 404)
        db[COLL_USAGE_OPERATIONS].insert_one({
            "operation_id": "op_other_user_003",
            "user_id": "acct_ffffffffffffffffffffffffffffffff",
            "benefit_id": "ai.chat.core3",
            "status": "committed",
            "units": 1,
            "created_at": now,
            "updated_at": now,
        })

        monkeypatch.setattr(QuotaService, "_get_db", lambda self_svc: db)
        client = _make_revenue_client(self.USER_EMAIL)

        # Canonical account_id hit
        resp_acct = client.get("/api/revenue/operations/op_acct_001")
        assert resp_acct.status_code == 200
        assert resp_acct.json()["operation_id"] == "op_acct_001"
        assert resp_acct.json()["user_id"] == self.ACCOUNT_ID

        # Legacy email fallback hit
        resp_legacy = client.get("/api/revenue/operations/op_email_legacy_002")
        assert resp_legacy.status_code == 200
        assert resp_legacy.json()["operation_id"] == "op_email_legacy_002"
        assert resp_legacy.json()["user_id"] == self.USER_EMAIL

        # Cross-tenant isolation still returns 404
        resp_other = client.get("/api/revenue/operations/op_other_user_003")
        assert resp_other.status_code == 404

    def test_operation_endpoints_fail_safe_503_when_db_unavailable_or_resolver_errors(self, monkeypatch):
        # Case A: DB is None -> 503
        monkeypatch.setattr(QuotaService, "_get_db", lambda self_svc: None)
        client = _make_revenue_client(self.USER_EMAIL)

        r_lookup_none = client.get(
            "/api/revenue/operations/lookup",
            params={"idempotency_key": "idem_x"},
        )
        assert r_lookup_none.status_code == 503

        r_status_none = client.get("/api/revenue/operations/op_x")
        assert r_status_none.status_code == 503

        # Case B: resolve_or_create_account_id raises unexpected error -> 503
        db = _MockDB()
        monkeypatch.setattr(QuotaService, "_get_db", lambda self_svc: db)
        monkeypatch.setattr(
            "backend.routers.revenue.resolve_or_create_account_id",
            lambda _db, _email: (_ for _ in ()).throw(RuntimeError("DB timeout")),
        )

        r_lookup_err = client.get(
            "/api/revenue/operations/lookup",
            params={"idempotency_key": "idem_x"},
        )
        assert r_lookup_err.status_code == 503

        r_status_err = client.get("/api/revenue/operations/op_x")
        assert r_status_err.status_code == 503
