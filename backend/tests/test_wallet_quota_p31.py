"""
Pytest suite for P3.1: Wallet Rewards -> QuotaService Bonus Integration.

Covers:
1. DEFAULT_REWARDS has rew_ai_credit_1 and rew_ai_credit_3 marked available.
2. redeem_reward deducts Saman Points, increments ai_credits, applies +bonus_units
   to today's daily buckets in QuotaService for ai.chat.core3, ai.chat.pro3, and
   ai.nutrition_gemini, and returns quota_bonus_applied=True.
3. Free user under ENABLE_AI_PAYWALL=true:
   - Before redeeming: _resolve_chat_quota_context raises 403 for core3/pro3.
   - After redeeming rew_ai_credit_1 (bonus_units=1): _resolve_chat_quota_context
     succeeds, 1st reserve succeeds, 2nd reserve raises 429 quota_exceeded.
   - Food Vision (ai.nutrition_gemini) gets 1 base + 1 bonus = 2 calls, 3rd raises 429.
"""

import asyncio
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
import sys
import threading
from typing import Any, Dict, List, Optional

import pytest
from bson import ObjectId
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
BACKEND_DIR = REPO_ROOT / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import backend.app.database as app_db
from backend.app.database_revenue import (
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
)
from backend.app.models.revenue import ReservationStatus
from backend.app.services.quota_service import QuotaService
from backend.app.services.revenue_guard import orchestrate_nutrition_analysis
from backend.auth_utils import get_current_user
import backend.routers.chat as chat_mod
from backend.routers.chat import (
    _reserve_chat_quota,
    _resolve_chat_quota_context,
    router as chat_router,
)
import backend.routers.journey as journey_mod


def _eval_expr_operand(doc: Dict[str, Any], expr: Any) -> Any:
    if isinstance(expr, (int, float)):
        return expr
    if isinstance(expr, str) and expr.startswith("$"):
        return doc.get(expr[1:], 0)
    if isinstance(expr, dict):
        if "$add" in expr:
            return sum(_eval_expr_operand(doc, item) for item in expr["$add"])
        if "$ifNull" in expr:
            field_ref, default_val = expr["$ifNull"]
            if isinstance(field_ref, str) and field_ref.startswith("$"):
                val = doc.get(field_ref[1:])
            else:
                val = field_ref
            return default_val if val is None else val
    return expr


class WalletQuotaMockCollection:
    def __init__(self, name: str):
        self.name = name
        self.docs: List[Dict[str, Any]] = []
        self._lock = threading.Lock()

    def _matches(self, doc: Dict[str, Any], query: Optional[Dict[str, Any]]) -> bool:
        if not query:
            return True
        for k, v in query.items():
            if k == "$expr":
                if "$lte" in v:
                    left, right = v["$lte"]
                    if _eval_expr_operand(doc, left) > _eval_expr_operand(doc, right):
                        return False
                continue
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

    def find(self, query: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        with self._lock:
            return [deepcopy(d) for d in self.docs if self._matches(d, query)]

    def find_one(self, query: Optional[Dict[str, Any]] = None, projection: Any = None) -> Optional[Dict[str, Any]]:
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    return deepcopy(d)
            return None

    def insert_one(self, doc: Dict[str, Any]):
        with self._lock:
            d = deepcopy(doc)
            if "_id" not in d:
                d["_id"] = ObjectId()
            if self.name == COLL_USAGE_OPERATIONS:
                for existing in self.docs:
                    if (
                        existing.get("user_id") == d.get("user_id")
                        and existing.get("benefit_id") == d.get("benefit_id")
                        and existing.get("idempotency_key") == d.get("idempotency_key")
                    ):
                        raise RuntimeError("DuplicateKeyError")
            self.docs.append(d)
            return type("InsertRes", (), {"inserted_id": d["_id"]})()

    def update_one(self, query: Dict[str, Any], update: Dict[str, Any], upsert: bool = False):
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    self._apply_update(d, update)
                    return type("UpdateRes", (), {"matched_count": 1, "modified_count": 1})()
            if upsert:
                new_doc: Dict[str, Any] = {}
                for k, v in query.items():
                    if not k.startswith("$") and not isinstance(v, dict):
                        new_doc[k] = deepcopy(v)
                if "$setOnInsert" in update:
                    new_doc.update(deepcopy(update["$setOnInsert"]))
                if "$set" in update:
                    new_doc.update(deepcopy(update["$set"]))
                if "$inc" in update:
                    for k, v in update["$inc"].items():
                        new_doc[k] = new_doc.get(k, 0) + v
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
        if "$inc" in update:
            for k, v in update["$inc"].items():
                doc[k] = doc.get(k, 0) + v
        if "$set" in update:
            for k, v in update["$set"].items():
                doc[k] = deepcopy(v)


class WalletQuotaMockDB:
    def __init__(self):
        self._cols: Dict[str, WalletQuotaMockCollection] = {}

    def __getitem__(self, name: str) -> WalletQuotaMockCollection:
        if name not in self._cols:
            self._cols[name] = WalletQuotaMockCollection(name)
        return self._cols[name]


class TestWalletQuotaP31:
    def test_default_rewards_ai_credits_available(self):
        rew1 = next(r for r in journey_mod.DEFAULT_REWARDS if r["id"] == "rew_ai_credit_1")
        rew3 = next(r for r in journey_mod.DEFAULT_REWARDS if r["id"] == "rew_ai_credit_3")
        assert rew1["is_available"] is True
        assert rew1["status_note"] == "Khả dụng · Cộng trực tiếp vào hạn mức AI hôm nay"
        assert rew3["is_available"] is True
        assert rew3["status_note"] == "Khả dụng · Cộng trực tiếp vào hạn mức AI hôm nay"

    def test_redeem_ai_credit_1_grants_bonus_units_to_all_three_buckets(self, monkeypatch):
        mock_db = WalletQuotaMockDB()
        user_oid = ObjectId()
        user_email = "WalletUser@Example.com"
        norm_email = user_email.strip().lower()
        canonical_uid = "acct_p31_001"

        mock_db["users"].insert_one({
            "_id": user_oid,
            "account_id": canonical_uid,
            "email": user_email,
            "saman_points": 400,
            "ai_credits": 0,
        })
        monkeypatch.setattr(journey_mod, "db", mock_db)

        current_user = {
            "_id": user_oid,
            "account_id": canonical_uid,
            "email": user_email,
        }
        res = asyncio.run(
            journey_mod.redeem_reward(
                journey_mod.RedeemRewardRequest(reward_id="rew_ai_credit_1"),
                current_user,
            )
        )

        assert res["status"] == "success"
        assert res["new_balance"] == 300
        assert res["ai_credits"] == 1
        assert res["quota_bonus_applied"] is True

        user_doc = mock_db["users"].find_one({"email": user_email})
        assert user_doc["saman_points"] == 300
        assert user_doc["ai_credits"] == 1

        q_svc = QuotaService(db=mock_db)
        now_utc = datetime.now(timezone.utc)
        for uid, benefit_id in [
            (canonical_uid, "ai.chat.core3"),
            (canonical_uid, "ai.chat.pro3"),
            (norm_email, "ai.nutrition_gemini"),
        ]:
            w_start, _, b_key = q_svc._get_window_bounds(now_utc, period_type="daily", benefit_id=benefit_id)
            bucket = mock_db[COLL_USAGE_BUCKETS].find_one({
                "user_id": uid,
                "bucket_key": b_key,
                "window_start": w_start,
            })
            assert bucket is not None, f"Missing bucket for {benefit_id}"
            assert bucket["bonus_units"] == 1

    def test_free_user_core3_and_pro3_blocked_403_before_redeem_then_allowed_1_turn_and_429_on_2nd(self, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        mock_db = WalletQuotaMockDB()
        user_oid = ObjectId()
        user_email = "free_p31@example.com"
        canonical_uid = str(user_oid)

        mock_db["users"].insert_one({
            "_id": user_oid,
            "email": user_email,
            "saman_points": 250,
            "ai_credits": 0,
        })
        monkeypatch.setattr(journey_mod, "db", mock_db)
        monkeypatch.setattr(app_db, "db", mock_db)

        current_user = {
            "_id": user_oid,
            "id": canonical_uid,
            "email": user_email,
        }

        # 1. Before redeem: core3 and pro3 must raise 403
        for mode in ("core3", "pro3"):
            with pytest.raises(HTTPException) as exc_info:
                _resolve_chat_quota_context(current_user, mode, mock_db)
            assert exc_info.value.status_code == 403
            assert exc_info.value.detail["code"] == "entitlement_required"

        # 2. Redeem rew_ai_credit_1 (+1 bonus_units)
        redeem_res = asyncio.run(
            journey_mod.redeem_reward(
                journey_mod.RedeemRewardRequest(reward_id="rew_ai_credit_1"),
                current_user,
            )
        )
        assert redeem_res["quota_bonus_applied"] is True
        assert redeem_res["new_balance"] == 150

        # 3. After redeem: core3 and pro3 resolve without 403, reserve 1 unit, and 2nd reserve raises 429 quota_exceeded
        q_svc = QuotaService(db=mock_db)
        for mode, expected_benefit in (("core3", "ai.chat.core3"), ("pro3", "ai.chat.pro3")):
            q_uid, benefit_id, period_type, limit_units = _resolve_chat_quota_context(
                current_user, mode, mock_db
            )
            assert q_uid == canonical_uid
            assert benefit_id == expected_benefit
            assert period_type == "daily"
            assert limit_units == 0

            res1 = _reserve_chat_quota(
                q_svc,
                q_uid,
                benefit_id,
                period_type,
                limit_units,
                idempotency_key=f"{mode}_turn_1",
            )
            assert res1.status == ReservationStatus.RESERVED
            assert q_svc.commit_quota(res1.operation_id, lease_token=res1.lease_token) is True

            with pytest.raises(HTTPException) as exc_429:
                _reserve_chat_quota(
                    q_svc,
                    q_uid,
                    benefit_id,
                    period_type,
                    limit_units,
                    idempotency_key=f"{mode}_turn_2",
                )
            assert exc_429.value.status_code == 429
            assert exc_429.value.detail["code"] == "quota_exceeded"

    def test_chat_endpoint_and_food_vision_integration_after_redeem(self, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        mock_db = WalletQuotaMockDB()
        user_oid = ObjectId()
        user_email = "free_e2e_p31@example.com"

        mock_db["users"].insert_one({
            "_id": user_oid,
            "email": user_email,
            "saman_points": 200,
            "ai_credits": 0,
        })
        monkeypatch.setattr(journey_mod, "db", mock_db)
        monkeypatch.setattr(app_db, "db", mock_db)
        monkeypatch.setattr(chat_mod, "conversations_col", mock_db["conversations"])
        monkeypatch.setattr(chat_mod, "nutrition_col", mock_db["nutrition"])
        monkeypatch.setattr(chat_mod, "workout_history_col", mock_db["workout_history"])
        monkeypatch.setattr(chat_mod, "users_col", mock_db["users"])
        monkeypatch.setattr(chat_mod, "water_col", mock_db["water"])

        async def ok_ai_reply(prompt: str) -> str:
            return "Phản hồi Core 3 từ bonus quota."

        monkeypatch.setattr(chat_mod, "_generate_ai_reply", ok_ai_reply)

        current_user = {"_id": user_oid, "email": user_email}
        app = FastAPI()
        app.include_router(chat_router)
        app.dependency_overrides[get_current_user] = lambda: current_user
        client = TestClient(app)

        # Before redeem -> /api/chat core3 returns 403
        r_before = client.post("/api/chat", json={"message": "Tư vấn tập lưng", "ai_mode": "core3"})
        assert r_before.status_code == 403

        # Redeem 1 AI credit
        redeem_res = asyncio.run(
            journey_mod.redeem_reward(
                journey_mod.RedeemRewardRequest(reward_id="rew_ai_credit_1"),
                current_user,
            )
        )
        assert redeem_res["quota_bonus_applied"] is True

        # After redeem -> /api/chat core3 succeeds once
        r_after = client.post("/api/chat", json={"message": "Tư vấn tập lưng", "ai_mode": "core3"})
        assert r_after.status_code == 200

        # Food Vision: Free base limit (1) + 1 bonus = 2 calls succeed, 3rd returns 429
        async def fake_vision(image_bytes: bytes, mime_type: str, grams: float):
            return {"food_name": "Bún bò", "nutrition": {"calories": 450}}

        for idx in range(2):
            fv_res = asyncio.run(
                orchestrate_nutrition_analysis(
                    image_bytes=f"img_{idx}".encode("utf-8"),
                    mime_type="image/jpeg",
                    grams=150.0,
                    email=user_email,
                    provider_callback=fake_vision,
                    db=mock_db,
                )
            )
            assert fv_res["food_name"] == "Bún bò"

        with pytest.raises(HTTPException) as fv_429:
            asyncio.run(
                orchestrate_nutrition_analysis(
                    image_bytes=b"img_3",
                    mime_type="image/jpeg",
                    grams=150.0,
                    email=user_email,
                    provider_callback=fake_vision,
                    db=mock_db,
                )
            )
        assert fv_429.value.status_code == 429
        assert fv_429.value.detail["code"] == "quota_exceeded"
