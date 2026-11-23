"""
Tests for P0.5: Vietnam VND Commercial Catalog & PayOS / VietQR Payment Flow.
"""

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import threading
from typing import Any, Dict, List, Optional
from unittest.mock import patch

import httpx
import pytest
from bson import ObjectId
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
BACKEND_DIR = REPO_ROOT / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import backend.app.database as app_db
from backend.app.database_revenue import (
    COLL_ENTITLEMENT_GRANTS,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_SUBSCRIPTIONS,
)
from backend.app.models.revenue import BillingPeriod, MembershipTier
from backend.app.services.catalog_engine import CatalogEngine
from backend.app.services.payos_service import (
    COLL_PAYMENT_ORDERS,
    TIER_BENEFITS,
    activate_paid_order,
    sign_payos_create_request,
    sign_payos_webhook_data,
)
from backend.app.services.quota_service import resolve_user_tier_and_quota
from backend.auth_utils import verify_token
from backend.main import app


class MockCollection:
    def __init__(self, name: str):
        self.name = name
        self.docs: List[Dict[str, Any]] = []
        self._lock = threading.Lock()

    def _matches(self, doc: Dict[str, Any], query: Optional[Dict[str, Any]]) -> bool:
        if not query:
            return True
        for k, v in query.items():
            if k == "$or":
                if not any(self._matches(doc, clause) for clause in v):
                    return False
                continue
            doc_val = doc.get(k)
            if isinstance(v, dict):
                if "$in" in v and doc_val not in v["$in"]:
                    return False
                if "$lte" in v and not (doc_val is not None and doc_val <= v["$lte"]):
                    return False
                if "$lt" in v and not (doc_val is not None and doc_val < v["$lt"]):
                    return False
                if "$gte" in v and not (doc_val is not None and doc_val >= v["$gte"]):
                    return False
                if "$ne" in v and doc_val == v["$ne"]:
                    return False
            else:
                if doc_val != v:
                    return False
        return True

    def find_one(self, query: Optional[Dict[str, Any]] = None, projection: Any = None) -> Optional[Dict[str, Any]]:
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    return deepcopy(d)
            return None

    def find(self, query: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        with self._lock:
            return [deepcopy(d) for d in self.docs if self._matches(d, query)]

    def insert_one(self, doc: Dict[str, Any]):
        with self._lock:
            d = deepcopy(doc)
            if "_id" not in d:
                d["_id"] = ObjectId()
            self.docs.append(d)
            return type("InsertRes", (), {"inserted_id": d["_id"]})()

    def update_one(self, query: Dict[str, Any], update: Dict[str, Any], upsert: bool = False):
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    self._apply_update(d, update)
                    return type("UpdateRes", (), {"matched_count": 1, "modified_count": 1})()
            if upsert:
                new_doc = deepcopy(query)
                if "$setOnInsert" in update:
                    new_doc.update(deepcopy(update["$setOnInsert"]))
                if "$set" in update:
                    new_doc.update(deepcopy(update["$set"]))
                if "_id" not in new_doc:
                    new_doc["_id"] = ObjectId()
                self.docs.append(new_doc)
                return type("UpdateRes", (), {"matched_count": 0, "modified_count": 1, "upserted_id": new_doc["_id"]})()
            return type("UpdateRes", (), {"matched_count": 0, "modified_count": 0})()

    def find_one_and_update(self, query: Dict[str, Any], update: Dict[str, Any], **kwargs) -> Optional[Dict[str, Any]]:
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    self._apply_update(d, update)
                    return deepcopy(d)
            return None

    def _apply_update(self, doc: Dict[str, Any], update: Dict[str, Any]) -> None:
        if "$set" in update:
            for k, v in update["$set"].items():
                doc[k] = deepcopy(v)


class MockCollectionNoFindAndUpdate(MockCollection):
    """MockCollection without find_one_and_update to verify update_one fallback."""
    def __getattribute__(self, name: str):
        if name == "find_one_and_update":
            raise AttributeError("find_one_and_update not supported")
        return super().__getattribute__(name)


class MockMongoDB:
    def __init__(self, use_fallback_orders: bool = False):
        self._cols: Dict[str, Any] = {}
        if use_fallback_orders:
            self._cols[COLL_PAYMENT_ORDERS] = MockCollectionNoFindAndUpdate(COLL_PAYMENT_ORDERS)

    def __getitem__(self, name: str) -> Any:
        if name not in self._cols:
            self._cols[name] = MockCollection(name)
        return self._cols[name]


class _DummyAsyncClient:
    """Mock httpx.AsyncClient capturing outbound PayOS HTTP calls."""
    captured_requests: List[Dict[str, Any]] = []
    post_response: Dict[str, Any] = {}
    get_response: Dict[str, Any] = {}
    status_code: int = 200

    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def post(self, url: str, json: Optional[Dict[str, Any]] = None, headers: Optional[Dict[str, str]] = None):
        _DummyAsyncClient.captured_requests.append({"method": "POST", "url": url, "json": json, "headers": headers})
        return httpx.Response(
            status_code=_DummyAsyncClient.status_code,
            json=_DummyAsyncClient.post_response,
            request=httpx.Request("POST", url),
        )

    async def get(self, url: str, headers: Optional[Dict[str, str]] = None):
        _DummyAsyncClient.captured_requests.append({"method": "GET", "url": url, "headers": headers})
        return httpx.Response(
            status_code=_DummyAsyncClient.status_code,
            json=_DummyAsyncClient.get_response,
            request=httpx.Request("GET", url),
        )


@pytest.fixture
def payos_env(monkeypatch):
    monkeypatch.setenv("PAYOS_CLIENT_ID", "test_client_id")
    monkeypatch.setenv("PAYOS_API_KEY", "test_api_key")
    monkeypatch.setenv("PAYOS_CHECKSUM_KEY", "test_checksum_secret_key_12345")
    monkeypatch.setenv("PAYOS_RETURN_URL", "https://saman.app/payment/success")
    monkeypatch.setenv("PAYOS_CANCEL_URL", "https://saman.app/payment/cancel")
    monkeypatch.setenv("PAYOS_BASE_URL", "https://api-merchant.payos.vn")


@pytest.fixture
def mock_db_env(monkeypatch):
    db = MockMongoDB()
    monkeypatch.setattr(app_db, "db", db)
    _DummyAsyncClient.captured_requests = []
    _DummyAsyncClient.status_code = 200
    yield db
    app.dependency_overrides.clear()


class TestVietnamCommercialCatalog:
    def test_catalog_endpoint_returns_vnd_prices_purchasable(self):
        client = TestClient(app)
        resp = client.get("/api/revenue/catalog")
        assert resp.status_code == 200
        data = resp.json()

        assert data["version_id"] == "v1.0-vn"
        assert data["currency"] == "VND"
        assert data["preview_mode"] is False

        plans_by_id = {p["plan_id"]: p for p in data["plans"]}
        assert set(plans_by_id.keys()) == {"plan_free", "plan_plus", "plan_pro", "plan_ultra"}
        assert plans_by_id["plan_pro"]["is_recommended"] is True

        def _price(plan_id: str, period: str) -> Dict[str, Any]:
            return next(pr for pr in plans_by_id[plan_id]["prices"] if pr["period"] == period)

        assert _price("plan_free", "monthly")["amount_cents"] == 0
        assert _price("plan_free", "monthly")["purchasable"] is False

        assert _price("plan_plus", "monthly")["amount_cents"] == 59000
        assert _price("plan_plus", "monthly")["purchasable"] is True
        assert _price("plan_plus", "yearly")["amount_cents"] == 588000
        assert _price("plan_plus", "yearly")["yearly_equivalent_monthly_cents"] == 49000

        assert _price("plan_pro", "monthly")["amount_cents"] == 119000
        assert _price("plan_pro", "monthly")["purchasable"] is True
        assert _price("plan_pro", "yearly")["amount_cents"] == 1188000
        assert _price("plan_pro", "yearly")["yearly_equivalent_monthly_cents"] == 99000

        assert _price("plan_ultra", "monthly")["amount_cents"] == 199000
        assert _price("plan_ultra", "monthly")["purchasable"] is True
        assert _price("plan_ultra", "yearly")["amount_cents"] == 2028000
        assert _price("plan_ultra", "yearly")["yearly_equivalent_monthly_cents"] == 169000

        # Matrix features switched from PLANNED to INCLUDED
        matrix = {f["id"]: f["status_map"] for f in data["matrix_features"]}
        assert matrix["gemini_food_analysis"]["plus"] == "included"
        assert matrix["workout_cv_ai"]["pro"] == "included"
        assert matrix["extended_history_memory"]["ultra"] == "included"

    def test_v1_preview_catalog_still_accessible(self):
        client = TestClient(app)
        resp = client.get("/api/revenue/catalog?version=v1.0-preview")
        assert resp.status_code == 200
        data = resp.json()
        assert data["version_id"] == "v1.0-preview"
        assert data["currency"] == "USD"


class TestPayosQrCreationAndWebhook:
    def test_create_qr_fails_closed_when_env_missing(self, monkeypatch, mock_db_env):
        monkeypatch.delenv("PAYOS_CLIENT_ID", raising=False)
        monkeypatch.delenv("PAYOS_API_KEY", raising=False)
        monkeypatch.delenv("PAYOS_CHECKSUM_KEY", raising=False)
        app.dependency_overrides[verify_token] = lambda: "buyer@saman.vn"

        client = TestClient(app)
        resp = client.post(
            "/api/payments/create-qr",
            json={"plan_id": "plan_pro", "billing_period": "monthly"},
        )
        assert resp.status_code == 503
        assert resp.json()["detail"]["code"] == "PAYMENT_PROVIDER_NOT_CONFIGURED"

    def test_create_qr_uses_authoritative_catalog_price_and_signs_request(self, payos_env, mock_db_env):
        app.dependency_overrides[verify_token] = lambda: "buyer@saman.vn"
        _DummyAsyncClient.post_response = {
            "code": "00",
            "desc": "success",
            "data": {
                "bin": "970422",
                "accountNumber": "0388889999",
                "accountName": "SAMAN HEALTH",
                "amount": 119000,
                "description": "SAMAN PRO 123",
                "orderCode": 123,
                "currency": "VND",
                "paymentLinkId": "plink_123",
                "status": "PENDING",
                "checkoutUrl": "https://pay.payos.vn/web/plink_123",
                "qrCode": "00020101021238570010A0000007270127000697042201130388889999",
                "expiredAt": int((datetime.now(timezone.utc) + timedelta(minutes=15)).timestamp()),
            },
        }

        client = TestClient(app)
        with patch("backend.app.services.payos_service.httpx.AsyncClient", _DummyAsyncClient):
            # Even if client tries passing an arbitrary amount, Pydantic ignores/drops it
            resp = client.post(
                "/api/payments/create-qr",
                json={"plan_id": "plan_pro", "billing_period": "monthly", "amount": 1000},
            )

        assert resp.status_code == 200
        body = resp.json()
        assert body["amount"] == 119000
        assert body["currency"] == "VND"
        assert body["status"] == "pending"
        assert body["qr_code"].startswith("000201")
        assert body["checkout_url"] == "https://pay.payos.vn/web/plink_123"
        assert body["bin"] == "970422"
        assert body["account_number"] == "0388889999"

        # Verify outbound PayOS signature
        sent = _DummyAsyncClient.captured_requests[0]["json"]
        assert sent["amount"] == 119000
        expected_sig = sign_payos_create_request(
            amount=119000,
            cancel_url="https://saman.app/payment/cancel",
            description=sent["description"],
            order_code=sent["orderCode"],
            return_url="https://saman.app/payment/success",
            checksum_key="test_checksum_secret_key_12345",
        )
        assert sent["signature"] == expected_sig

        # Verify DB persistence
        saved = mock_db_env[COLL_PAYMENT_ORDERS].find_one({"order_code": body["order_code"]})
        assert saved is not None
        assert saved["status"] == "pending"
        assert saved["amount"] == 119000
        assert saved["tier"] == "pro"

    def test_webhook_rejects_invalid_hmac(self, payos_env, mock_db_env):
        client = TestClient(app)
        payload = {
            "code": "00",
            "desc": "success",
            "data": {"orderCode": 999001, "amount": 59000, "code": "00"},
            "signature": "deadbeefinvalid",
        }
        resp = client.post("/api/payments/payos-webhook", json=payload)
        assert resp.status_code == 401
        assert resp.json()["detail"]["code"] == "INVALID_WEBHOOK_SIGNATURE"

    @pytest.mark.parametrize(
        "plan_id,tier,period,expected_amount,expected_days",
        [
            ("plan_plus", MembershipTier.PLUS, BillingPeriod.MONTHLY, 59000, 30),
            ("plan_pro", MembershipTier.PRO, BillingPeriod.MONTHLY, 119000, 30),
            ("plan_ultra", MembershipTier.ULTRA, BillingPeriod.YEARLY, 2028000, 365),
        ],
    )
    def test_webhook_upgrades_subscription_and_grants_and_is_idempotent(
        self,
        payos_env,
        mock_db_env,
        plan_id,
        tier,
        period,
        expected_amount,
        expected_days,
    ):
        email = f"{tier.value}_user@saman.vn"
        app.dependency_overrides[verify_token] = lambda: email

        _DummyAsyncClient.post_response = {
            "code": "00",
            "desc": "success",
            "data": {
                "bin": "970422",
                "accountNumber": "0388889999",
                "accountName": "SAMAN HEALTH",
                "amount": expected_amount,
                "description": "SAMAN UPGRADE",
                "orderCode": 111,
                "currency": "VND",
                "paymentLinkId": "plink_ok",
                "status": "PENDING",
                "checkoutUrl": "https://pay.payos.vn/web/plink_ok",
                "qrCode": "qr_payload_data",
            },
        }

        client = TestClient(app)
        with patch("backend.app.services.payos_service.httpx.AsyncClient", _DummyAsyncClient):
            create_resp = client.post(
                "/api/payments/create-qr",
                json={"plan_id": plan_id, "billing_period": period.value},
            )
        assert create_resp.status_code == 200
        order_code = create_resp.json()["order_code"]

        webhook_data = {
            "orderCode": order_code,
            "amount": expected_amount,
            "description": "SAMAN UPGRADE",
            "accountNumber": "0388889999",
            "reference": "FT263240001",
            "transactionDateTime": "2026-11-20 20:30:00",
            "currency": "VND",
            "paymentLinkId": "plink_ok",
            "code": "00",
            "desc": "success",
        }
        sig = sign_payos_webhook_data(webhook_data, "test_checksum_secret_key_12345")
        webhook_payload = {"code": "00", "desc": "success", "data": webhook_data, "signature": sig}

        # First webhook call activates subscription and grants
        wh_resp_1 = client.post("/api/payments/payos-webhook", json=webhook_payload)
        assert wh_resp_1.status_code == 200
        assert wh_resp_1.json()["already_processed"] is False
        assert wh_resp_1.json()["tier"] == tier.value

        sub_doc = mock_db_env[COLL_SUBSCRIPTIONS].find_one({"tier": tier.value})
        assert sub_doc is not None
        assert sub_doc["provider"] == "payos"
        assert sub_doc["status"] == "active"
        delta = sub_doc["current_period_end"] - sub_doc["current_period_start"]
        assert delta == timedelta(days=expected_days)

        grants = mock_db_env[COLL_ENTITLEMENT_GRANTS].find({"user_id": sub_doc["user_id"], "status": "granted"})
        granted_benefits = {g["benefit_id"] for g in grants}
        assert granted_benefits == set(TIER_BENEFITS[tier])

        tx_docs = mock_db_env[COLL_PAYMENT_TRANSACTIONS].find({"user_id": sub_doc["user_id"]})
        assert len(tx_docs) == 1
        assert tx_docs[0]["amount_cents"] == expected_amount
        assert tx_docs[0]["currency"] == "VND"
        assert tx_docs[0]["provider"] == "payos"

        # Second webhook call (replay) MUST be idempotent: no period extension, no duplicate tx
        wh_resp_2 = client.post("/api/payments/payos-webhook", json=webhook_payload)
        assert wh_resp_2.status_code == 200
        assert wh_resp_2.json()["already_processed"] is True
        sub_doc_after = mock_db_env[COLL_SUBSCRIPTIONS].find_one({"subscription_id": sub_doc["subscription_id"]})
        assert sub_doc_after["current_period_end"] == sub_doc["current_period_end"]
        assert len(mock_db_env[COLL_PAYMENT_TRANSACTIONS].find({"user_id": sub_doc["user_id"]})) == 1

        # Verify /api/revenue/membership/me reflects upgraded tier & quota
        with patch("backend.app.services.entitlement_service.EntitlementService._get_db", return_value=mock_db_env):
            me_resp = client.get("/api/revenue/membership/me")
        assert me_resp.status_code == 200
        me_data = me_resp.json()
        assert me_data["tier"] == tier.value
        assert me_data["is_active_subscription"] is True

        resolved_tier, _, _ = resolve_user_tier_and_quota(
            mock_db_env, user_id=sub_doc["user_id"], email=email, benefit_id="ai.nutrition_gemini"
        )
        assert resolved_tier == tier

    def test_order_status_blocks_other_users_and_syncs_paid_on_poll(self, payos_env, mock_db_env):
        # User A creates order
        app.dependency_overrides[verify_token] = lambda: "user_a@saman.vn"
        _DummyAsyncClient.post_response = {
            "code": "00",
            "desc": "success",
            "data": {
                "amount": 59000,
                "description": "SAMAN PLUS",
                "orderCode": 555,
                "checkoutUrl": "https://pay.payos.vn/web/555",
                "qrCode": "qr_555",
            },
        }
        client = TestClient(app)
        with patch("backend.app.services.payos_service.httpx.AsyncClient", _DummyAsyncClient):
            create_resp = client.post(
                "/api/payments/create-qr",
                json={"plan_id": "plan_plus", "billing_period": "monthly"},
            )
        order_code = create_resp.json()["order_code"]

        # User B tries to inspect User A's order -> 403
        app.dependency_overrides[verify_token] = lambda: "user_b@saman.vn"
        forbidden_resp = client.get(f"/api/payments/orders/{order_code}")
        assert forbidden_resp.status_code == 403

        # User A polls status -> PayOS reports PAID -> auto-activates locally
        app.dependency_overrides[verify_token] = lambda: "user_a@saman.vn"
        _DummyAsyncClient.get_response = {
            "code": "00",
            "desc": "success",
            "data": {
                "orderCode": order_code,
                "amount": 59000,
                "amountPaid": 59000,
                "status": "PAID",
            },
        }
        with patch("backend.app.services.payos_service.httpx.AsyncClient", _DummyAsyncClient):
            poll_resp = client.get(f"/api/payments/orders/{order_code}")
        assert poll_resp.status_code == 200
        poll_data = poll_resp.json()
        assert poll_data["status"] == "paid"
        assert poll_data["tier"] == "plus"
        assert poll_data["amount"] == 59000
        assert poll_data["paid_at"] is not None

        order_doc = mock_db_env[COLL_PAYMENT_ORDERS].find_one({"order_code": order_code})
        assert order_doc["status"] == "paid"

    def test_activate_paid_order_fallback_without_find_one_and_update(self):
        db = MockMongoDB(use_fallback_orders=True)
        now = datetime(2026, 11, 20, 12, 0, 0, tzinfo=timezone.utc)
        db[COLL_PAYMENT_ORDERS].insert_one({
            "order_code": 777001,
            "account_id": "acct_fallback_user",
            "user_id": "acct_fallback_user",
            "email": "fallback@saman.vn",
            "plan_id": "plan_plus",
            "price_id": "price_plus_monthly_vnd_59000",
            "tier": "plus",
            "billing_period": "monthly",
            "amount": 59000,
            "currency": "VND",
            "status": "pending",
        })

        res1 = activate_paid_order(db, 777001, 59000, "sha256:abc123456789", as_of=now)
        assert res1["already_processed"] is False
        assert res1["status"] == "paid"

        res2 = activate_paid_order(db, 777001, 59000, "sha256:abc123456789", as_of=now + timedelta(days=5))
        assert res2["already_processed"] is True
        sub_doc = db[COLL_SUBSCRIPTIONS].find_one({"user_id": "acct_fallback_user"})
        assert sub_doc["current_period_end"] == now + timedelta(days=30)
