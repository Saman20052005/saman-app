"""
Pytest suite for P0.4: Tier Quota Limits (Asia/Ho_Chi_Minh daily/weekly),
Chat Rate Limits (Swift 3, Core 3, Pro 3 on /api/chat and /api/chat/stream),
Food Vision Daily Quota, LLM Error Release, and /api/revenue/membership/me summary.
"""

import asyncio
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import threading
from typing import Any, Dict, List, Optional
from zoneinfo import ZoneInfo

import pytest
from bson import ObjectId
from fastapi import FastAPI
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
    COLL_SUBSCRIPTIONS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
)
from backend.app.models.revenue import MembershipTier, ReservationStatus
from backend.app.services.quota_service import (
    TIER_QUOTA_LIMITS,
    QuotaService,
    resolve_user_tier_and_quota,
)
from backend.app.services.revenue_guard import orchestrate_nutrition_analysis
from backend.auth_utils import get_current_user, verify_token
import backend.routers.chat as chat_mod
from backend.routers.chat import router as chat_router
from backend.routers.revenue import router as revenue_router

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


# ---------------------------------------------------------------------------
# Thread-safe in-memory Mongo Mock supporting $expr, $add, $ifNull, $lte, $inc
# ---------------------------------------------------------------------------

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


class P04MockCollection:
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

    def create_index(self, *args, **kwargs):
        return "mock_idx"


class P04MockDB:
    def __init__(self):
        self._cols: Dict[str, P04MockCollection] = {}

    def __getitem__(self, name: str) -> P04MockCollection:
        if name not in self._cols:
            self._cols[name] = P04MockCollection(name)
        return self._cols[name]


# ---------------------------------------------------------------------------
# 1. QuotaService unit tests: window bounds, bonus_units, unlimited, resolver
# ---------------------------------------------------------------------------

class TestQuotaServiceP04:
    def test_tier_quota_limits_definition(self):
        assert TIER_QUOTA_LIMITS["free"]["ai.chat.swift3"] == ("daily", 5)
        assert TIER_QUOTA_LIMITS["free"]["ai.chat.core3"] == ("daily", 0)
        assert TIER_QUOTA_LIMITS["free"]["ai.chat.pro3"] == ("daily", 0)
        assert TIER_QUOTA_LIMITS["free"]["ai.nutrition_gemini"] == ("daily", 1)
        assert TIER_QUOTA_LIMITS["free"]["workout.cv.ai"] == ("weekly", 2)

        assert TIER_QUOTA_LIMITS["plus"]["ai.chat.core3"] == ("daily", 10)
        assert TIER_QUOTA_LIMITS["plus"]["ai.nutrition_gemini"] == ("daily", 5)
        assert TIER_QUOTA_LIMITS["pro"]["ai.nutrition_gemini"] == ("daily", 10)
        assert TIER_QUOTA_LIMITS["pro"]["workout.cv.ai"] == ("weekly", -1)
        assert TIER_QUOTA_LIMITS["ultra"]["ai.chat.pro3"] == ("daily", 15)
        assert TIER_QUOTA_LIMITS["ultra"]["ai.nutrition_gemini"] == ("daily", 20)
        assert TIER_QUOTA_LIMITS["ultra"]["workout.cv.ai"] == ("weekly", -1)

    def test_window_bounds_monthly_daily_weekly_vn_timezone(self):
        svc = QuotaService(db=P04MockDB())
        # 2026-11-20 23:59:00 +07:00 == 2026-11-20 16:59:00 UTC
        late_vn = datetime(2026, 11, 20, 16, 59, 0, tzinfo=timezone.utc)
        # 2026-11-21 00:01:00 +07:00 == 2026-11-20 17:01:00 UTC
        early_next_vn = datetime(2026, 11, 20, 17, 1, 0, tzinfo=timezone.utc)

        # Monthly (backward compatible)
        m_start, m_end, m_key = svc._get_window_bounds(late_vn)
        assert m_key == "monthly:202611"
        assert m_start == datetime(2026, 11, 1, 0, 0, 0, tzinfo=timezone.utc)
        assert m_end == datetime(2026, 12, 1, 0, 0, 0, tzinfo=timezone.utc)

        # Daily VN
        d_start1, d_end1, d_key1 = svc._get_window_bounds(late_vn, period_type="daily", benefit_id="ai.chat.swift3")
        assert d_key1 == "daily:2026-11-20:ai.chat.swift3"
        assert d_start1 == datetime(2026, 11, 19, 17, 0, 0, tzinfo=timezone.utc)
        assert d_end1 == datetime(2026, 11, 20, 17, 0, 0, tzinfo=timezone.utc)

        d_start2, d_end2, d_key2 = svc._get_window_bounds(early_next_vn, period_type="daily", benefit_id="ai.chat.swift3")
        assert d_key2 == "daily:2026-11-21:ai.chat.swift3"
        assert d_start2 == datetime(2026, 11, 20, 17, 0, 0, tzinfo=timezone.utc)
        assert d_end2 == datetime(2026, 11, 21, 17, 0, 0, tzinfo=timezone.utc)

        # Weekly ISO VN (2026-11-20 is Friday of ISO week 2026-W47, Monday is 2026-11-16)
        w_start, w_end, w_key = svc._get_window_bounds(late_vn, period_type="weekly", benefit_id="workout.cv.ai")
        assert w_key == "weekly:2026W47:workout.cv.ai"
        assert w_start == datetime(2026, 11, 15, 17, 0, 0, tzinfo=timezone.utc)
        assert w_end == datetime(2026, 11, 22, 17, 0, 0, tzinfo=timezone.utc)

    def test_add_bonus_quota_and_unlimited_capacity(self):
        db = P04MockDB()
        svc = QuotaService(db=db)
        now = datetime(2026, 11, 20, 10, 0, 0, tzinfo=timezone.utc)

        # Free user on ai.nutrition_gemini has limit=1/day -> add 2 bonus -> total 3/day
        ok_bonus = svc.add_bonus_quota("u_bonus", "ai.nutrition_gemini", bonus_units=2, period_type="daily", as_of=now)
        assert ok_bonus is True

        for i in range(3):
            res = svc.reserve_quota("u_bonus", "ai.nutrition_gemini", units=1, limit_units=1, period_type="daily", as_of=now)
            assert res.status == ReservationStatus.RESERVED, f"Call {i+1} should succeed with bonus"
            assert svc.commit_quota(res.operation_id, lease_token=res.lease_token, as_of=now)

        res4 = svc.reserve_quota("u_bonus", "ai.nutrition_gemini", units=1, limit_units=1, period_type="daily", as_of=now)
        assert res4.status == ReservationStatus.QUOTA_EXHAUSTED

        # Unlimited (-1) bypasses capacity cap
        for i in range(5):
            res_u = svc.reserve_quota("u_pro", "workout.cv.ai", units=1, limit_units=-1, period_type="weekly", as_of=now)
            assert res_u.status == ReservationStatus.RESERVED
            assert res_u.limit_units == -1
            assert res_u.remaining_units == -1

    def test_resolve_user_tier_and_quota_subscriptions_and_grants(self):
        db = P04MockDB()
        now = datetime(2026, 11, 20, 10, 0, 0, tzinfo=timezone.utc)

        # Free default
        tier, ptype, lim = resolve_user_tier_and_quota(db, "u_free", benefit_id="ai.chat.pro3", as_of=now)
        assert (tier, ptype, lim) == (MembershipTier.FREE, "daily", 0)

        # Grant ai.advanced_thinking elevates ai.chat.pro3 to 15/day
        db[COLL_ENTITLEMENT_GRANTS].insert_one({
            "grant_id": "g_adv",
            "user_id": "u_free",
            "benefit_id": "ai.advanced_thinking",
            "status": "granted",
        })
        tier_g, ptype_g, lim_g = resolve_user_tier_and_quota(db, "u_free", benefit_id="ai.chat.pro3", as_of=now)
        assert (tier_g, ptype_g, lim_g) == (MembershipTier.FREE, "daily", 15)

        # Active Ultra subscription
        db[COLL_SUBSCRIPTIONS].insert_one({
            "subscription_id": "sub_ultra_1",
            "user_id": "u_ultra",
            "tier": "ultra",
            "status": "active",
            "current_period_start": now - timedelta(days=1),
            "current_period_end": now + timedelta(days=29),
        })
        assert resolve_user_tier_and_quota(db, "u_ultra", benefit_id="ai.chat.pro3", as_of=now) == (MembershipTier.ULTRA, "daily", 15)
        assert resolve_user_tier_and_quota(db, "u_ultra", benefit_id="ai.nutrition_gemini", as_of=now) == (MembershipTier.ULTRA, "daily", 20)
        assert resolve_user_tier_and_quota(db, "u_ultra", benefit_id="workout.cv.ai", as_of=now) == (MembershipTier.ULTRA, "weekly", -1)


# ---------------------------------------------------------------------------
# 2. Chat Rate Limit & Paywall Integration Tests (/api/chat and /api/chat/stream)
# ---------------------------------------------------------------------------

class TestChatRateLimitP04:
    @pytest.fixture
    def chat_env(self, monkeypatch):
        mock_db = P04MockDB()
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        monkeypatch.setattr(app_db, "db", mock_db)
        monkeypatch.setattr(chat_mod, "conversations_col", mock_db["conversations"])
        monkeypatch.setattr(chat_mod, "nutrition_col", mock_db["nutrition"])
        monkeypatch.setattr(chat_mod, "workout_history_col", mock_db["workout_history"])
        monkeypatch.setattr(chat_mod, "users_col", mock_db["users"])
        monkeypatch.setattr(chat_mod, "water_col", mock_db["water"])

        async def ok_ai_reply(prompt: str) -> str:
            return "Đây là phản hồi từ Saman AI."

        monkeypatch.setattr(chat_mod, "_generate_ai_reply", ok_ai_reply)
        monkeypatch.setattr(chat_mod, "get_ai_reply", lambda p: "ignored", raising=False)
        return mock_db

    def _make_client(self, user_dict: Dict[str, Any]) -> TestClient:
        app = FastAPI()
        app.include_router(chat_router)
        app.dependency_overrides[get_current_user] = lambda: user_dict
        return TestClient(app)

    def test_free_user_swift3_blocked_on_6th_and_core3_pro3_403(self, chat_env):
        client = self._make_client({"_id": "free_u1", "email": "free_u1@example.com"})

        # Core 3 -> 403 entitlement_required
        r_core = client.post("/api/chat", json={"message": "Tư vấn tập ngực", "ai_mode": "core3"})
        assert r_core.status_code == 403
        assert r_core.json()["detail"]["code"] == "entitlement_required"
        assert r_core.json()["detail"]["benefit_id"] == "ai.chat.core3"

        # Pro 3 -> 403 entitlement_required with ai.advanced_thinking
        r_pro = client.post("/api/chat", json={"message": "Phân tích chuyên sâu", "ai_mode": "pro3"})
        assert r_pro.status_code == 403
        assert r_pro.json()["detail"]["code"] == "entitlement_required"
        assert r_pro.json()["detail"]["benefit_id"] == "ai.advanced_thinking"

        # Swift 3 -> 5 turns succeed, 6th returns 429
        for i in range(5):
            r = client.post("/api/chat", json={"message": f"Chào coach {i}", "ai_mode": "swift3"})
            assert r.status_code == 200, f"Swift3 turn {i+1} failed: {r.text}"

        r6 = client.post("/api/chat", json={"message": "Lượt thứ 6", "ai_mode": "swift3"})
        assert r6.status_code == 429
        detail = r6.json()["detail"]
        assert detail["code"] == "quota_exceeded"
        assert detail["benefit_id"] == "ai.chat.swift3"
        assert detail["limit_units"] == 5
        assert detail["remaining_units"] == 0

    def test_free_user_swift3_resets_at_00_01_next_vn_day(self, chat_env, monkeypatch):
        # Set clock to 2026-11-20 23:59:00 +07:00 (16:59 UTC)
        current_now = [datetime(2026, 11, 20, 16, 59, 0, tzinfo=timezone.utc)]

        class FakeDatetime(datetime):
            @classmethod
            def now(cls, tz=None):
                dt = current_now[0]
                return dt.astimezone(tz) if tz is not None else dt.replace(tzinfo=None)

        import backend.app.services.quota_service as qs_mod
        monkeypatch.setattr(qs_mod, "datetime", FakeDatetime)

        client = self._make_client({"_id": "free_reset_u", "email": "free_reset@example.com"})
        for i in range(5):
            r = client.post("/api/chat", json={"message": f"Tin nhắn {i}", "ai_mode": "swift3"})
            assert r.status_code == 200

        r6 = client.post("/api/chat", json={"message": "Lượt 6 hôm nay", "ai_mode": "swift3"})
        assert r6.status_code == 429

        # Advance clock to 2026-11-21 00:01:00 +07:00 (17:01 UTC) -> resets quota
        current_now[0] = datetime(2026, 11, 20, 17, 1, 0, tzinfo=timezone.utc)
        r_next_day = client.post("/api/chat", json={"message": "Chào ngày mới", "ai_mode": "swift3"})
        assert r_next_day.status_code == 200

    def test_ultra_user_pro3_15_per_day(self, chat_env):
        now = datetime.now(timezone.utc)
        chat_env[COLL_SUBSCRIPTIONS].insert_one({
            "subscription_id": "sub_ultra_chat",
            "user_id": "ultra_u1",
            "tier": "ultra",
            "status": "active",
            "current_period_start": now - timedelta(days=1),
            "current_period_end": now + timedelta(days=29),
        })
        client = self._make_client({"_id": "ultra_u1", "email": "ultra_u1@example.com"})

        for i in range(15):
            r = client.post("/api/chat", json={"message": f"Pro3 câu {i}", "ai_mode": "pro3"})
            assert r.status_code == 200, f"Ultra pro3 turn {i+1} failed: {r.text}"

        r16 = client.post("/api/chat", json={"message": "Pro3 câu 16", "ai_mode": "pro3"})
        assert r16.status_code == 429
        assert r16.json()["detail"]["benefit_id"] == "ai.chat.pro3"
        assert r16.json()["detail"]["limit_units"] == 15

    def test_llm_error_releases_quota_without_charging(self, chat_env, monkeypatch):
        async def failing_ai_reply(prompt: str) -> str:
            raise TimeoutError("Gemini request timed out")

        monkeypatch.setattr(chat_mod, "_generate_ai_reply", failing_ai_reply)

        client = self._make_client({"_id": "free_err_u", "email": "free_err@example.com"})
        r_err = client.post("/api/chat", json={"message": "Câu hỏi bị timeout", "ai_mode": "swift3"})
        assert r_err.status_code == 200
        assert r_err.json()["reply"] == chat_mod.AI_FALLBACK_REPLY

        # Bucket must have 0 consumed and 0 reserved
        buckets = chat_env[COLL_USAGE_BUCKETS].find({"user_id": "free_err_u"})
        assert len(buckets) == 1
        assert buckets[0]["consumed_units"] == 0
        assert buckets[0]["reserved_units"] == 0

        # Restore working LLM -> user still has all 5 turns
        async def ok_ai_reply(prompt: str) -> str:
            return "Phản hồi thành công"

        monkeypatch.setattr(chat_mod, "_generate_ai_reply", ok_ai_reply)
        for i in range(5):
            r = client.post("/api/chat", json={"message": f"Lượt hợp lệ {i}", "ai_mode": "swift3"})
            assert r.status_code == 200
        assert client.post("/api/chat", json={"message": "Lượt thứ 6", "ai_mode": "swift3"}).status_code == 429

    def test_chat_stream_enforces_403_429_and_releases_on_error(self, chat_env, monkeypatch):
        class FakeOpService:
            def __init__(self, **kwargs):
                self.fail_stream = False

            async def handle_stream(self, **kwargs):
                yield {"event": "meta", "data": {"ai_mode": kwargs.get("ai_mode")}}
                if kwargs.get("message") == "TRIGGER_STREAM_ERROR":
                    raise RuntimeError("Provider stream crashed")
                yield {"event": "delta", "data": {"text": "Xin chào"}}
                yield {"event": "done", "data": {"ai_mode": kwargs.get("ai_mode")}}

        monkeypatch.setattr(chat_mod, "_build_chat_operation_service", lambda cls, db: FakeOpService())
        client = self._make_client({"_id": "stream_u", "email": "stream_u@example.com"})

        # Free user on core3 stream -> 403
        r_403 = client.post("/api/chat/stream", json={"message": "Xin chào", "ai_mode": "core3"})
        assert r_403.status_code == 403

        # Stream error releases quota
        r_err = client.post("/api/chat/stream", json={"message": "TRIGGER_STREAM_ERROR", "ai_mode": "swift3"})
        assert r_err.status_code == 200
        assert "event: error" in r_err.text
        buckets = chat_env[COLL_USAGE_BUCKETS].find({"user_id": "stream_u"})
        assert len(buckets) == 1
        assert buckets[0]["consumed_units"] == 0
        assert buckets[0]["reserved_units"] == 0

        # 5 successful streams consume 5 units; 6th returns 429
        for i in range(5):
            r_ok = client.post("/api/chat/stream", json={"message": f"Stream {i}", "ai_mode": "swift3"})
            assert r_ok.status_code == 200
            assert "event: done" in r_ok.text

        r_429 = client.post("/api/chat/stream", json={"message": "Stream 6", "ai_mode": "swift3"})
        assert r_429.status_code == 429
        assert r_429.json()["detail"]["code"] == "quota_exceeded"


# ---------------------------------------------------------------------------
# 3. Food Vision Daily Quota Tests
# ---------------------------------------------------------------------------

class TestFoodVisionDailyQuotaP04:
    def test_free_blocked_on_2nd_image_and_resets_at_00_01_vn(self, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        db = P04MockDB()
        dispatches = [0]

        async def fake_provider(image_bytes: bytes, mime_type: str, grams: float):
            dispatches[0] += 1
            return {"food_name": "Cơm tấm", "nutrition": {"calories": 500}}

        day1_late_vn = datetime(2026, 11, 20, 16, 59, 0, tzinfo=timezone.utc)  # 23:59 +07:00
        day2_early_vn = datetime(2026, 11, 20, 17, 1, 0, tzinfo=timezone.utc)  # 00:01 +07:00 next day

        async def _run():
            # 1st image succeeds
            res1 = await orchestrate_nutrition_analysis(
                image_bytes=b"food_img_1",
                mime_type="image/jpeg",
                grams=200.0,
                email="free_fv@example.com",
                provider_callback=fake_provider,
                as_of=day1_late_vn,
                db=db,
            )
            assert res1["food_name"] == "Cơm tấm"
            assert dispatches[0] == 1

            # 2nd image same VN day -> 429, 0 extra dispatch
            from fastapi import HTTPException
            with pytest.raises(HTTPException) as exc_info:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"food_img_2",
                    mime_type="image/jpeg",
                    grams=200.0,
                    email="free_fv@example.com",
                    provider_callback=fake_provider,
                    as_of=day1_late_vn,
                    db=db,
                )
            assert exc_info.value.status_code == 429
            assert dispatches[0] == 1

            # Advance to 00:01 next day VN -> quota resets!
            res_next = await orchestrate_nutrition_analysis(
                image_bytes=b"food_img_3",
                mime_type="image/jpeg",
                grams=200.0,
                email="free_fv@example.com",
                provider_callback=fake_provider,
                as_of=day2_early_vn,
                db=db,
            )
            assert res_next["food_name"] == "Cơm tấm"
            assert dispatches[0] == 2

        asyncio.run(_run())

    def test_ultra_food_vision_20_per_day_and_error_release(self, monkeypatch):
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        db = P04MockDB()
        now = datetime(2026, 11, 20, 10, 0, 0, tzinfo=timezone.utc)
        db[COLL_SUBSCRIPTIONS].insert_one({
            "subscription_id": "sub_ultra_fv",
            "user_id": "ultra_fv@example.com",
            "tier": "ultra",
            "status": "active",
            "current_period_start": now - timedelta(days=1),
            "current_period_end": now + timedelta(days=29),
        })

        async def fake_provider(image_bytes: bytes, mime_type: str, grams: float):
            return {"food_name": "Phở", "nutrition": {"calories": 400}}

        async def failing_provider(image_bytes: bytes, mime_type: str, grams: float):
            raise RuntimeError("Upstream 500")

        async def _run():
            # Provider error releases quota
            from fastapi import HTTPException
            with pytest.raises(HTTPException) as err_exc:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"bad_call_img",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="ultra_fv@example.com",
                    provider_callback=failing_provider,
                    as_of=now,
                    db=db,
                )
            assert err_exc.value.status_code == 502
            bucket = db[COLL_USAGE_BUCKETS].find_one({"user_id": "ultra_fv@example.com"})
            assert bucket["consumed_units"] == 0
            assert bucket["reserved_units"] == 0

            # 20 valid images succeed; 21st raises 429
            for i in range(20):
                res = await orchestrate_nutrition_analysis(
                    image_bytes=f"ultra_img_{i}".encode("utf-8"),
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="ultra_fv@example.com",
                    provider_callback=fake_provider,
                    as_of=now,
                    db=db,
                )
                assert res["food_name"] == "Phở"

            with pytest.raises(HTTPException) as cap_exc:
                await orchestrate_nutrition_analysis(
                    image_bytes=b"ultra_img_21",
                    mime_type="image/jpeg",
                    grams=100.0,
                    email="ultra_fv@example.com",
                    provider_callback=fake_provider,
                    as_of=now,
                    db=db,
                )
            assert cap_exc.value.status_code == 429

        asyncio.run(_run())


# ---------------------------------------------------------------------------
# 4. /api/revenue/membership/me Usage Summary Tests
# ---------------------------------------------------------------------------

class TestMembershipMeUsageSummaryP04:
    def test_membership_me_returns_all_five_benefits_with_tier_limits(self, monkeypatch):
        mock_db = P04MockDB()
        monkeypatch.setattr("backend.app.services.entitlement_service.EntitlementService._get_db", lambda self: mock_db)

        app = FastAPI()
        app.include_router(revenue_router)
        app.dependency_overrides[verify_token] = lambda: "free_me@example.com"
        client = TestClient(app)

        # Free user summary
        res = client.get("/api/revenue/membership/me")
        assert res.status_code == 200
        data = res.json()
        assert data["tier"] == "free"
        usage = data["usage"]
        assert usage["ai.nutrition_gemini"]["limit_units"] == 1
        assert usage["ai.nutrition_gemini"]["remaining_units"] == 1
        assert usage["ai.chat.swift3"]["limit_units"] == 5
        assert usage["ai.chat.core3"]["limit_units"] == 0
        assert usage["ai.chat.pro3"]["limit_units"] == 0
        assert usage["workout.cv.ai"]["limit_units"] == 2

        # Upgrade user to Ultra via subscription and reserve/commit 2 pro3 units
        acct_id = data["account_id"]
        now = datetime.now(timezone.utc)
        mock_db[COLL_SUBSCRIPTIONS].insert_one({
            "subscription_id": "sub_ultra_me",
            "user_id": acct_id,
            "tier": "ultra",
            "status": "active",
            "current_period_start": now - timedelta(days=1),
            "current_period_end": now + timedelta(days=29),
        })
        q_svc = QuotaService(db=mock_db)
        for idx in range(2):
            r = q_svc.reserve_quota(
                user_id=acct_id,
                benefit_id="ai.chat.pro3",
                units=1,
                limit_units=15,
                period_type="daily",
                as_of=now,
            )
            q_svc.commit_quota(r.operation_id, lease_token=r.lease_token, as_of=now)

        res_ultra = client.get("/api/revenue/membership/me")
        assert res_ultra.status_code == 200
        u_data = res_ultra.json()
        assert u_data["tier"] == "ultra"
        u_usage = u_data["usage"]
        assert u_usage["ai.nutrition_gemini"]["limit_units"] == 20
        assert u_usage["ai.chat.swift3"]["limit_units"] == 50
        assert u_usage["ai.chat.core3"]["limit_units"] == 30
        assert u_usage["ai.chat.pro3"]["limit_units"] == 15
        assert u_usage["ai.chat.pro3"]["consumed_units"] == 2
        assert u_usage["ai.chat.pro3"]["remaining_units"] == 13
        assert u_usage["workout.cv.ai"]["limit_units"] == -1
        assert u_usage["workout.cv.ai"]["remaining_units"] == -1
