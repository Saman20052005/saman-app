"""
Pytest test suite for CP4.3: Paywall gates for Pro 3 and 30-Day History Analytics.

Scope:
1. is_ai_paywall_enabled() defaults to False when unset, True when set to 'true'.
2. Pro 3 on /api/chat & _enforce_pro3_entitlement:
   - ENABLE_AI_PAYWALL=false -> user Free using ai_mode='pro3' proceeds normally (no 403).
   - ENABLE_AI_PAYWALL=true + user Free -> 403 with code == 'entitlement_required' and benefit_id == 'ai.advanced_thinking'.
   - ENABLE_AI_PAYWALL=true + user with revenue_entitlement_grants ('ai.advanced_thinking', 'granted') -> allowed (no 403).
   - ENABLE_AI_PAYWALL=true + EntitlementService STORAGE_UNAVAILABLE -> fail-closed returns 503.
3. History Analytics 30-day on /api/coach/analytics/preflight and /execute:
   - ENABLE_AI_PAYWALL=false -> range_days=30 not blocked by paywall.
   - ENABLE_AI_PAYWALL=true + user Free -> range_days=7 and 14 work normally; range_days=30 blocked 403
     (code == 'entitlement_required', benefit_id == 'ai.extended_memory') at both /preflight and /execute (0 LLM dispatch).
   - ENABLE_AI_PAYWALL=true + user with grant 'ai.extended_memory' -> range_days=30 passes paywall.
"""

import sys
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest
from bson import ObjectId
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

# Ensure repo root and backend directory are available in sys.path
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
BACKEND_DIR = REPO_ROOT / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import backend.app.database as app_db
from backend.app.models.revenue import (
    EntitlementDecision,
    EntitlementDecisionStatus,
    MembershipTier,
)
from backend.app.services.history_analytics_service import preflight_estimate
from backend.app.services.revenue_guard import (
    is_ai_paywall_enabled as revenue_guard_is_ai_paywall_enabled,
)
from backend.auth_utils import get_current_user
import backend.routers.analytics as analytics_mod
from backend.routers.analytics import (
    _enforce_analytics_range_paywall,
    get_history_analytics_db,
    get_history_analytics_provider,
    router as analytics_router,
)
import backend.routers.chat as chat_mod
from backend.routers.chat import (
    _enforce_pro3_entitlement,
    is_ai_paywall_enabled as chat_is_ai_paywall_enabled,
    router as chat_router,
)


# ---------------------------------------------------------------------------
# In-memory Mocks for Collections and Database
# ---------------------------------------------------------------------------

class MockCollection:
    def __init__(self, docs=None):
        self.docs = list(docs) if docs else []

    def find(self, query=None):
        query = query or {}
        results = []
        for d in self.docs:
            match = True
            for k, v in query.items():
                if k.startswith("$"):
                    continue
                if isinstance(v, dict):
                    if "$in" in v and d.get(k) not in v["$in"]:
                        match = False
                        break
                    continue
                if d.get(k) != v:
                    match = False
                    break
            if match:
                results.append(d)
        return results

    def find_one(self, query=None):
        res = self.find(query)
        return res[0] if res else None

    def insert_one(self, doc):
        d = dict(doc)
        if "_id" not in d:
            d["_id"] = ObjectId()
        self.docs.append(d)
        return MagicMock(inserted_id=d["_id"])

    def update_one(self, query, update, upsert=False):
        doc = self.find_one(query)
        if doc and "$set" in update:
            doc.update(update["$set"])
            return MagicMock(matched_count=1, modified_count=1)
        if not doc and upsert:
            new_doc = dict(query)
            if "$set" in update:
                new_doc.update(update["$set"])
            self.insert_one(new_doc)
            return MagicMock(matched_count=0, modified_count=1)
        return MagicMock(matched_count=1 if doc else 0, modified_count=0)

    def count_documents(self, query=None, hint=None):
        return len(self.find(query))

    def aggregate(self, pipeline=None, hint=None):
        return []

    def create_index(self, *args, **kwargs):
        return "mock_idx"


class MockDatabase(dict):
    def __getitem__(self, name):
        if name not in self:
            self[name] = MockCollection()
        return super().__getitem__(name)


# ---------------------------------------------------------------------------
# Test Suite 1: is_ai_paywall_enabled()
# ---------------------------------------------------------------------------

class TestAiPaywallFlag:
    def test_revenue_guard_is_ai_paywall_enabled_default_false(self, monkeypatch):
        monkeypatch.delenv("ENABLE_AI_PAYWALL", raising=False)
        assert revenue_guard_is_ai_paywall_enabled() is False

    def test_revenue_guard_is_ai_paywall_enabled_truthy(self, monkeypatch):
        for val in ("true", "1", "yes", "TRUE", "True"):
            monkeypatch.setenv("ENABLE_AI_PAYWALL", val)
            assert revenue_guard_is_ai_paywall_enabled() is True

    def test_revenue_guard_is_ai_paywall_enabled_falsy(self, monkeypatch):
        for val in ("false", "0", "no", "FALSE", ""):
            monkeypatch.setenv("ENABLE_AI_PAYWALL", val)
            assert revenue_guard_is_ai_paywall_enabled() is False

    def test_chat_router_is_ai_paywall_enabled_parity(self, monkeypatch):
        monkeypatch.delenv("ENABLE_AI_PAYWALL", raising=False)
        assert chat_is_ai_paywall_enabled() is False

        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        assert chat_is_ai_paywall_enabled() is True

        monkeypatch.setenv("ENABLE_AI_PAYWALL", "false")
        assert chat_is_ai_paywall_enabled() is False


# ---------------------------------------------------------------------------
# Test Suite 2: Pro 3 on /api/chat and _enforce_pro3_entitlement
# ---------------------------------------------------------------------------

class TestPro3PaywallEnforcement:
    @pytest.fixture
    def mock_env(self, monkeypatch):
        mock_db = MockDatabase()
        monkeypatch.setattr(app_db, "db", mock_db)
        monkeypatch.setattr(chat_mod, "conversations_col", mock_db["conversations"])
        monkeypatch.setattr(chat_mod, "_call_gemini_sync", lambda *a, **kw: "Mock AI reply")
        return mock_db

    # Unit tests for _enforce_pro3_entitlement
    def test_enforce_pro3_entitlement_free_user_raises_403(self, mock_env, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "free_user_001"
        with pytest.raises(HTTPException) as exc_info:
            _enforce_pro3_entitlement(user_id=user_id, email=f"{user_id}@example.com")

        assert exc_info.value.status_code == 403
        detail = exc_info.value.detail
        assert isinstance(detail, dict)
        assert detail.get("code") == "entitlement_required"
        assert detail.get("benefit_id") == "ai.advanced_thinking"

    def test_enforce_pro3_entitlement_granted_user_passes(self, mock_env, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "pro_user_001"
        # Insert active grant in revenue_entitlement_grants
        mock_env["revenue_entitlement_grants"].docs.append({
            "user_id": user_id,
            "benefit_id": "ai.advanced_thinking",
            "status": "granted",
        })

        # Must not raise any HTTPException
        _enforce_pro3_entitlement(user_id=user_id, email=f"{user_id}@example.com")

    def test_enforce_pro3_entitlement_storage_unavailable_fail_closed_503(self, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        # Set app_db.db to None so storage lookup fails-closed
        monkeypatch.setattr(app_db, "db", None)

        with pytest.raises(HTTPException) as exc_info:
            _enforce_pro3_entitlement(user_id="user_any", email="any@example.com")

        assert exc_info.value.status_code == 503

    # Router level integration tests for /api/chat
    def test_chat_router_paywall_disabled_free_user_pro3_allowed(self, mock_env, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "false")
        user_id = "free_user_002"
        user_email = f"{user_id}@example.com"

        app = FastAPI()
        app.include_router(chat_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}

        client = TestClient(app)
        response = client.post("/api/chat", json={"message": "Hello Pro3", "ai_mode": "pro3"})
        # Should not be blocked by 403 entitlement paywall
        assert response.status_code != 403

    def test_chat_router_paywall_enabled_free_user_pro3_blocked_403(self, mock_env, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "free_user_003"
        user_email = f"{user_id}@example.com"

        app = FastAPI()
        app.include_router(chat_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}

        client = TestClient(app)
        response = client.post("/api/chat", json={"message": "Hello Pro3", "ai_mode": "pro3"})

        assert response.status_code == 403
        data = response.json()
        detail = data.get("detail", {})
        assert detail.get("code") == "entitlement_required"
        assert detail.get("benefit_id") == "ai.advanced_thinking"

    def test_chat_router_paywall_enabled_granted_user_pro3_allowed(self, mock_env, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "pro_user_002"
        user_email = f"{user_id}@example.com"

        mock_env["revenue_entitlement_grants"].docs.append({
            "user_id": user_id,
            "benefit_id": "ai.advanced_thinking",
            "status": "granted",
        })

        app = FastAPI()
        app.include_router(chat_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}

        client = TestClient(app)
        response = client.post("/api/chat", json={"message": "Hello Pro3", "ai_mode": "pro3"})
        assert response.status_code != 403

    def test_chat_router_paywall_enabled_storage_unavailable_returns_503(self, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        monkeypatch.setattr(app_db, "db", None)

        user_id = "user_storage_err"
        app = FastAPI()
        app.include_router(chat_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": f"{user_id}@example.com"}

        client = TestClient(app)
        response = client.post("/api/chat", json={"message": "Hello Pro3", "ai_mode": "pro3"})
        assert response.status_code == 503


# ---------------------------------------------------------------------------
# Test Suite 3: History Analytics 30-Day Paywall on /preflight and /execute
# ---------------------------------------------------------------------------

class TestHistoryAnalytics30DayPaywall:
    @pytest.fixture
    def analytics_env(self, monkeypatch):
        mock_db = MockDatabase()
        mock_provider = MagicMock()
        mock_provider.generate = AsyncMock(return_value="Mock Analytics Report")

        # Adapter for evaluate_ai_feature_access that evaluates against mock_db grants
        def mock_eval_feature(benefit_id, user_id=None, email=None, account_id=None, **kwargs):
            uid = str(user_id or email or account_id or "")
            grants = mock_db["revenue_entitlement_grants"].find({"user_id": uid, "benefit_id": benefit_id})
            if any(g.get("status") == "granted" for g in grants):
                return EntitlementDecision(
                    status=EntitlementDecisionStatus.ALLOWED,
                    user_id=uid,
                    benefit_id=benefit_id,
                    tier=MembershipTier.PRO,
                )
            return EntitlementDecision(
                status=EntitlementDecisionStatus.ENTITLEMENT_REQUIRED,
                user_id=uid,
                benefit_id=benefit_id,
                reason="Subscription or grant required for 30-day extended memory",
            )

        monkeypatch.setattr(analytics_mod, "evaluate_ai_feature_access", mock_eval_feature)
        return mock_db, mock_provider

    # Unit tests for _enforce_analytics_range_paywall
    def test_enforce_analytics_range_paywall_disabled_allows_30_days(self, analytics_env, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "false")
        current_user = {"_id": "free_user_010", "email": "free10@example.com"}
        # Must not raise
        _enforce_analytics_range_paywall(current_user, 30)

    def test_enforce_analytics_range_paywall_free_user_allows_7_and_14_days(self, analytics_env, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        current_user = {"_id": "free_user_011", "email": "free11@example.com"}
        # 7 and 14 days should pass through without error
        _enforce_analytics_range_paywall(current_user, 7)
        _enforce_analytics_range_paywall(current_user, 14)
        _enforce_analytics_range_paywall(current_user, "7")
        _enforce_analytics_range_paywall(current_user, "14")

    def test_enforce_analytics_range_paywall_free_user_blocks_30_days_403(self, analytics_env, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        current_user = {"_id": "free_user_012", "email": "free12@example.com"}

        with pytest.raises(HTTPException) as exc_info:
            _enforce_analytics_range_paywall(current_user, 30)

        assert exc_info.value.status_code == 403
        detail = exc_info.value.detail
        assert isinstance(detail, dict)
        assert detail.get("code") == "entitlement_required"
        assert detail.get("benefit_id") == "ai.extended_memory"

    def test_enforce_analytics_range_paywall_granted_user_allows_30_days(self, analytics_env, monkeypatch):
        mock_db, _ = analytics_env
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "granted_user_010"
        current_user = {"_id": user_id, "email": f"{user_id}@example.com"}

        mock_db["revenue_entitlement_grants"].docs.append({
            "user_id": user_id,
            "benefit_id": "ai.extended_memory",
            "status": "granted",
        })

        # Must not raise
        _enforce_analytics_range_paywall(current_user, 30)
        _enforce_analytics_range_paywall(current_user, "30")

    # Router level tests: /api/coach/analytics/preflight
    def test_preflight_paywall_disabled_30_days_allowed(self, analytics_env, monkeypatch):
        mock_db, mock_provider = analytics_env
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "false")
        user_id = "free_user_020"
        user_email = f"{user_id}@example.com"

        app = FastAPI()
        app.include_router(analytics_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}
        app.dependency_overrides[get_history_analytics_db] = lambda: mock_db
        app.dependency_overrides[get_history_analytics_provider] = lambda: mock_provider

        client = TestClient(app)
        res = client.post("/api/coach/analytics/preflight", json={"range_days": 30})
        assert res.status_code == 200
        data = res.json()
        assert data.get("range_days") == 30

    def test_preflight_paywall_enabled_free_user_7_and_14_days_allowed(self, analytics_env, monkeypatch):
        mock_db, mock_provider = analytics_env
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "free_user_021"
        user_email = f"{user_id}@example.com"

        app = FastAPI()
        app.include_router(analytics_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}
        app.dependency_overrides[get_history_analytics_db] = lambda: mock_db
        app.dependency_overrides[get_history_analytics_provider] = lambda: mock_provider

        client = TestClient(app)

        res7 = client.post("/api/coach/analytics/preflight", json={"range_days": 7})
        assert res7.status_code == 200
        assert res7.json().get("range_days") == 7

        res14 = client.post("/api/coach/analytics/preflight", json={"range_days": 14})
        assert res14.status_code == 200
        assert res14.json().get("range_days") == 14

    def test_preflight_paywall_enabled_free_user_30_days_blocked_403(self, analytics_env, monkeypatch):
        mock_db, mock_provider = analytics_env
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "free_user_022"
        user_email = f"{user_id}@example.com"

        app = FastAPI()
        app.include_router(analytics_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}
        app.dependency_overrides[get_history_analytics_db] = lambda: mock_db
        app.dependency_overrides[get_history_analytics_provider] = lambda: mock_provider

        client = TestClient(app)
        res30 = client.post("/api/coach/analytics/preflight", json={"range_days": 30})

        assert res30.status_code == 403
        data = res30.json()
        detail = data.get("detail", {})
        assert detail.get("code") == "entitlement_required"
        assert detail.get("benefit_id") == "ai.extended_memory"

    def test_preflight_paywall_enabled_granted_user_30_days_allowed(self, analytics_env, monkeypatch):
        mock_db, mock_provider = analytics_env
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "granted_user_020"
        user_email = f"{user_id}@example.com"

        mock_db["revenue_entitlement_grants"].docs.append({
            "user_id": user_id,
            "benefit_id": "ai.extended_memory",
            "status": "granted",
        })

        app = FastAPI()
        app.include_router(analytics_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}
        app.dependency_overrides[get_history_analytics_db] = lambda: mock_db
        app.dependency_overrides[get_history_analytics_provider] = lambda: mock_provider

        client = TestClient(app)
        res = client.post("/api/coach/analytics/preflight", json={"range_days": 30})
        assert res.status_code == 200
        assert res.json().get("range_days") == 30

    # Router level tests: /api/coach/analytics/execute
    def test_execute_paywall_enabled_free_user_30_days_blocked_403_zero_llm_dispatch(
        self, analytics_env, monkeypatch
    ):
        mock_db, mock_provider = analytics_env
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "free_user_030"
        user_email = f"{user_id}@example.com"

        app = FastAPI()
        app.include_router(analytics_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}
        app.dependency_overrides[get_history_analytics_db] = lambda: mock_db
        app.dependency_overrides[get_history_analytics_provider] = lambda: mock_provider

        client = TestClient(app)
        res = client.post(
            "/api/coach/analytics/execute",
            json={
                "quote_id": "mock_quote_30",
                "range_days": 30,
                "confirm": True,
            },
        )

        assert res.status_code == 403
        data = res.json()
        detail = data.get("detail", {})
        assert detail.get("code") == "entitlement_required"
        assert detail.get("benefit_id") == "ai.extended_memory"

        # Invariant verification: Exactly 0 LLM provider dispatches
        mock_provider.generate.assert_not_called()

    def test_execute_paywall_disabled_30_days_allowed(self, analytics_env, monkeypatch):
        mock_db, mock_provider = analytics_env
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "false")
        user_id = "free_user_031"
        user_email = f"{user_id}@example.com"

        # Pre-seed a valid quote via preflight_estimate
        quote = preflight_estimate(mock_db, user_id, user_email, 30)
        quote_id = quote["quote_id"]

        app = FastAPI()
        app.include_router(analytics_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}
        app.dependency_overrides[get_history_analytics_db] = lambda: mock_db
        app.dependency_overrides[get_history_analytics_provider] = lambda: mock_provider

        client = TestClient(app)
        res = client.post(
            "/api/coach/analytics/execute",
            json={
                "quote_id": quote_id,
                "range_days": 30,
                "confirm": True,
            },
        )

        assert res.status_code == 200
        assert res.json().get("status") == "success"
        # LLM provider was dispatched
        assert mock_provider.generate.call_count == 1

    def test_execute_paywall_enabled_granted_user_30_days_allowed(self, analytics_env, monkeypatch):
        mock_db, mock_provider = analytics_env
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user_id = "granted_user_030"
        user_email = f"{user_id}@example.com"

        mock_db["revenue_entitlement_grants"].docs.append({
            "user_id": user_id,
            "benefit_id": "ai.extended_memory",
            "status": "granted",
        })

        # Pre-seed a valid quote via preflight_estimate
        quote = preflight_estimate(mock_db, user_id, user_email, 30)
        quote_id = quote["quote_id"]

        app = FastAPI()
        app.include_router(analytics_router)
        app.dependency_overrides[get_current_user] = lambda: {"_id": user_id, "email": user_email}
        app.dependency_overrides[get_history_analytics_db] = lambda: mock_db
        app.dependency_overrides[get_history_analytics_provider] = lambda: mock_provider

        client = TestClient(app)
        res = client.post(
            "/api/coach/analytics/execute",
            json={
                "quote_id": quote_id,
                "range_days": 30,
                "confirm": True,
            },
        )

        assert res.status_code == 200
        assert res.json().get("status") == "success"
        assert mock_provider.generate.call_count == 1
