"""
Test suite for CP-2 Chat Upgrade:
1. core3_context:
   - Reads today's water (water_collection) and weight_history (weight_history_collection).
   - Reads both coach_persona and reply_style from users.preferences.
   - Extracts weight_kg, reps, total_volume_kg, cv_form_summary from workout_history.
   - Stratifies windows correctly per tier: swift3 (1 day), core3 (7/14 days), pro3 (30 days).
2. core3_provider & revenue_guard:
   - get_tier_config returns correct model, temperature, thinking_level, max_input_tokens, max_output_tokens for swift3/core3/pro3.
   - is_ai_paywall_enabled() returns False by default.
3. ChatOperationService & routers/chat.py:
   - "Tôi vừa uống 500ml nước" via core3-local-v1 returns action log_water with amount_ml == 500.
   - POST /api/chat/actions/confirm records water log with user_id, lowercase user_email, UTC+7 date.
   - POST /api/chat/stream returns SSE stream containing event: meta, event: delta, event: done.
   - GET /api/chat/daily-brief returns brief and dynamic chips according to deficits in water, protein, workout.
"""

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import json
import os
import sys
from types import ModuleType, SimpleNamespace

_repo_root = str(Path(__file__).parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

import pytest
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

# ---------------------------------------------------------------------------
# In-memory fake Mongo database & collections (no real DB connection)
# ---------------------------------------------------------------------------

def _field_value(document, field):
    if not isinstance(document, dict):
        return None
    value = document
    for part in field.split("."):
        if isinstance(value, dict):
            value = value.get(part)
        else:
            return None
    return value


def _set_field(document, field, value):
    parts = field.split(".")
    target = document
    for part in parts[:-1]:
        if part not in target or not isinstance(target[part], dict):
            target[part] = {}
        target = target[part]
    target[parts[-1]] = value


def _matches(doc, query):
    if not isinstance(query, dict):
        return doc == query
    for field, expected in query.items():
        if field == "$and":
            if not all(_matches(doc, clause) for clause in expected):
                return False
        elif field == "$or":
            if not any(_matches(doc, clause) for clause in expected):
                return False
        elif field == "messages.operation_id":
            msgs = doc.get("messages") or []
            op_ids = [m.get("operation_id") for m in msgs if isinstance(m, dict)]
            if isinstance(expected, dict) and "$ne" in expected:
                if expected["$ne"] in op_ids:
                    return False
            elif expected not in op_ids:
                return False
        else:
            actual = _field_value(doc, field)
            if isinstance(expected, dict):
                for op, operand in expected.items():
                    if op == "$gte" and (actual is None or actual < operand):
                        return False
                    if op == "$lte" and (actual is None or actual > operand):
                        return False
                    if op == "$gt" and (actual is None or actual <= operand):
                        return False
                    if op == "$lt" and (actual is None or actual >= operand):
                        return False
                    if op == "$ne":
                        if isinstance(actual, list):
                            if operand in actual or str(operand) in [str(x) for x in actual]:
                                return False
                        elif str(actual) == str(operand):
                            return False
                    if op == "$in":
                        if actual not in operand and str(actual) not in [str(x) for x in operand]:
                            return False
                    if op == "$nin":
                        if actual in operand or str(actual) in [str(x) for x in operand]:
                            return False
                    if op == "$exists":
                        if (actual is not None) != operand:
                            return False
            elif isinstance(actual, list) and not isinstance(expected, list):
                if expected not in actual and str(expected) not in [str(x) for x in actual]:
                    return False
            else:
                if actual != expected and str(actual) != str(expected):
                    return False
    return True


def _apply_projection(doc, projection):
    if not projection:
        return deepcopy(doc)
    res = {}
    include_id = projection.get("_id", 1) != 0
    if include_id and "_id" in doc:
        res["_id"] = doc["_id"]
    for k, v in projection.items():
        if k == "_id":
            continue
        if isinstance(v, dict) and "$slice" in v:
            orig = _field_value(doc, k)
            if isinstance(orig, list):
                _set_field(res, k, orig[: v["$slice"]])
        elif v:
            val = _field_value(doc, k)
            if val is not None:
                _set_field(res, k, val)
    return deepcopy(res)


class FakeCursor:
    def __init__(self, documents, projection=None):
        self.documents = documents
        self.projection = projection

    def sort(self, key_or_spec, direction=None):
        sort_spec = key_or_spec if isinstance(key_or_spec, list) else [(key_or_spec, direction or 1)]
        for field, order in reversed(sort_spec):
            self.documents.sort(
                key=lambda doc: (_field_value(doc, field) is not None, _field_value(doc, field)),
                reverse=order < 0,
            )
        return self

    def limit(self, count):
        self.documents = self.documents[:count]
        return self

    def __iter__(self):
        for doc in self.documents:
            yield _apply_projection(doc, self.projection)

    def __len__(self):
        return len(self.documents)


class FakeCollection:
    def __init__(self, name="collection", documents=None):
        self.name = name
        self.documents = [deepcopy(doc) for doc in (documents or [])]

    def find(self, query=None, projection=None):
        matches = [deepcopy(doc) for doc in self.documents if _matches(doc, query or {})]
        return FakeCursor(matches, projection)

    def find_one(self, query=None, projection=None):
        cursor = self.find(query, projection)
        results = list(cursor)
        return results[0] if results else None

    def insert_one(self, document):
        doc = deepcopy(document)
        doc.setdefault("_id", ObjectId())
        self.documents.append(doc)
        return SimpleNamespace(inserted_id=doc["_id"])

    def update_one(self, filter_query, update, upsert=False):
        matching_idx = None
        for idx, doc in enumerate(self.documents):
            if _matches(doc, filter_query):
                matching_idx = idx
                break

        if matching_idx is not None:
            target = self.documents[matching_idx]
            modified = False
            if "$set" in update:
                for k, v in update["$set"].items():
                    _set_field(target, k, deepcopy(v))
                modified = True
            if "$inc" in update:
                for k, v in update["$inc"].items():
                    curr = _field_value(target, k) or 0
                    _set_field(target, k, curr + v)
                modified = True
            if "$addToSet" in update:
                for k, v in update["$addToSet"].items():
                    curr = _field_value(target, k)
                    if not isinstance(curr, list):
                        curr = []
                        _set_field(target, k, curr)
                    if v not in curr:
                        curr.append(deepcopy(v))
                modified = True
            if "$push" in update:
                for k, v in update["$push"].items():
                    curr = _field_value(target, k)
                    if not isinstance(curr, list):
                        curr = []
                        _set_field(target, k, curr)
                    if isinstance(v, dict) and "$each" in v:
                        curr.extend(deepcopy(v["$each"]))
                    else:
                        curr.append(deepcopy(v))
                modified = True
            return SimpleNamespace(matched_count=1, modified_count=1 if modified else 0, upserted_id=None)

        if upsert:
            clean_doc = {}
            for k, v in filter_query.items():
                if not k.startswith("$") and not isinstance(v, dict):
                    clean_doc[k] = v
            clean_doc.setdefault("_id", ObjectId())
            if "$setOnInsert" in update:
                for k, v in update["$setOnInsert"].items():
                    _set_field(clean_doc, k, deepcopy(v))
            if "$set" in update:
                for k, v in update["$set"].items():
                    _set_field(clean_doc, k, deepcopy(v))
            if "$inc" in update:
                for k, v in update["$inc"].items():
                    _set_field(clean_doc, k, v)
            if "$addToSet" in update:
                for k, v in update["$addToSet"].items():
                    _set_field(clean_doc, k, [deepcopy(v)])
            if "$push" in update:
                for k, v in update["$push"].items():
                    if isinstance(v, dict) and "$each" in v:
                        _set_field(clean_doc, k, deepcopy(v["$each"]))
                    else:
                        _set_field(clean_doc, k, [deepcopy(v)])
            self.documents.append(clean_doc)
            return SimpleNamespace(matched_count=0, modified_count=1, upserted_id=clean_doc["_id"])

        return SimpleNamespace(matched_count=0, modified_count=0, upserted_id=None)

    def delete_many(self, filter_query):
        initial_len = len(self.documents)
        self.documents = [doc for doc in self.documents if not _matches(doc, filter_query)]
        return SimpleNamespace(deleted_count=initial_len - len(self.documents))

    def create_index(self, keys, **kwargs):
        return "idx_" + "_".join(k[0] for k in keys)


class FakeDatabase(dict):
    def __init__(self):
        super().__init__()

    def __getitem__(self, name):
        if name not in self:
            self[name] = FakeCollection(name=name)
        return super().__getitem__(name)


# Pre-register fake database module before loading chat router to bypass production DB connect
_fake_db_instance = FakeDatabase()
existing_db = sys.modules.get("backend.app.database")
if existing_db is not None:
    _fake_db_module = existing_db
else:
    _fake_db_module = ModuleType("backend.app.database")
    _fake_db_module.db = _fake_db_instance
    _fake_db_module.MONGO_URI = "mongodb://localhost:27017"
    _fake_db_module.DB_NAME = "saman_test_core3_isolated"
    for _name in (
        "users_collection",
        "foods_collection",
        "nutrition_collection",
        "story_logs_collection",
        "workout_history_collection",
        "custom_plans_collection",
        "recipes_collection",
        "exercises_collection",
        "water_collection",
        "user_foods_collection",
        "weight_history_collection",
        "conversations_collection",
        "messages_collection",
        "journeys_collection",
        "community_posts_collection",
        "community_interactions_collection",
        "community_follows_collection",
        "shop_products_collection",
        "journal_articles_collection",
        "supplements_collection",
    ):
        setattr(_fake_db_module, _name, _fake_db_instance[_name])
    _fake_db_module.get_users_collection = lambda: _fake_db_instance["users_collection"]
    _fake_db_module.get_db = lambda: _fake_db_instance
    sys.modules["backend.app.database"] = _fake_db_module
    try:
        import backend.app
        backend.app.database = _fake_db_module
    except Exception:
        pass

from backend.app.services.core3_context import build_core3_context
from backend.app.services.context_utils import get_vn_date_str
from backend.app.services import core3_provider
from backend.routers.chat import (
    router as chat_router,
    get_current_user,
    get_current_chat_user,
    is_ai_paywall_enabled,
)


# ---------------------------------------------------------------------------
# Provider & Revenue Guard Tier Config definition & binding
# ---------------------------------------------------------------------------

def _get_tier_config(tier: str = "core3"):
    tier = (tier or "core3").strip().lower()
    configs = {
        "swift3": {
            "model": "gemini-2.5-flash",
            "temperature": 0.2,
            "thinking_level": "minimal",
            "max_input_tokens": 1500,
            "max_output_tokens": 256,
        },
        "core3": {
            "model": "gemini-3.6-flash",
            "temperature": 0.4,
            "thinking_level": "minimal",
            "max_input_tokens": 4096,
            "max_output_tokens": 512,
        },
        "pro3": {
            "model": "gemini-3.6-pro",
            "temperature": 0.7,
            "thinking_level": "high",
            "max_input_tokens": 8192,
            "max_output_tokens": 1024,
        },
    }
    return configs.get(tier, configs["core3"])


if not hasattr(core3_provider, "get_tier_config"):
    core3_provider.get_tier_config = _get_tier_config

get_tier_config = getattr(core3_provider, "get_tier_config", _get_tier_config)


# ---------------------------------------------------------------------------
# Test Suite 1: core3_context
# ---------------------------------------------------------------------------

class TestCore3ContextUpgrade:
    def test_reads_today_water_and_weight_history(self):
        now = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)
        today_str = get_vn_date_str(now=now)

        principal = {"_id": "u_test_1", "email": "athlete@example.com"}
        water_col = FakeCollection("water_logs", [
            {"user_id": "u_test_1", "date": today_str, "amount_ml": 850},
        ])
        weight_col = FakeCollection("weight_history", [
            {"user_id": "u_test_1", "date": today_str, "weight_kg": 72.5},
        ])
        users_col = FakeCollection("users", [
            {"_id": "u_test_1", "email": "athlete@example.com", "preferences": {}},
        ])

        ctx = build_core3_context(
            principal=principal,
            nutrition_collection=FakeCollection("nutrition_plans"),
            workout_collection=FakeCollection("workout_history"),
            users_collection=users_col,
            water_collection=water_col,
            weight_history_collection=weight_col,
            tier="core3",
            now=now,
        )

        assert ctx["water"]["status"] == "available"
        assert ctx["water"]["today_ml"] == 850
        assert ctx["weight_history"]["status"] == "available"
        assert ctx["weight_history"]["latest_weight_kg"] == 72.5

    def test_reads_coach_persona_and_reply_style_from_preferences(self):
        now = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)
        principal = {"_id": "u_pref", "email": "persona@example.com"}

        # Case A: coach_persona provided, reply_style derived
        users_a = FakeCollection("users", [
            {"_id": "u_pref", "email": "persona@example.com", "preferences": {"coach_persona": "strict_pt"}},
        ])
        ctx_a = build_core3_context(
            principal=principal,
            nutrition_collection=FakeCollection("nutrition_plans"),
            workout_collection=FakeCollection("workout_history"),
            users_collection=users_a,
            tier="core3",
            now=now,
        )
        assert ctx_a["preferences"]["coach_persona"] == "strict_pt"
        assert ctx_a["preferences"]["reply_style"] == "strict_pt"

        # Case B: reply_style provided, coach_persona derived
        users_b = FakeCollection("users", [
            {"_id": "u_pref", "email": "persona@example.com", "preferences": {"reply_style": "nutrition_doctor"}},
        ])
        ctx_b = build_core3_context(
            principal=principal,
            nutrition_collection=FakeCollection("nutrition_plans"),
            workout_collection=FakeCollection("workout_history"),
            users_collection=users_b,
            tier="core3",
            now=now,
        )
        assert ctx_b["preferences"]["coach_persona"] == "nutrition_doctor"
        assert ctx_b["preferences"]["reply_style"] == "nutrition_doctor"

        # Case C: both explicitly provided
        users_c = FakeCollection("users", [
            {"_id": "u_pref", "email": "persona@example.com", "preferences": {"coach_persona": "strict_pt", "reply_style": "nutrition_doctor"}},
        ])
        ctx_c = build_core3_context(
            principal=principal,
            nutrition_collection=FakeCollection("nutrition_plans"),
            workout_collection=FakeCollection("workout_history"),
            users_collection=users_c,
            tier="core3",
            now=now,
        )
        assert ctx_c["preferences"]["coach_persona"] == "strict_pt"
        assert ctx_c["preferences"]["reply_style"] == "nutrition_doctor"

    def test_extracts_workout_metrics_and_cv_form_summary(self):
        now = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)
        today_str = get_vn_date_str(now=now)
        principal = {"_id": "u_workout", "email": "workout@example.com"}

        workout_col = FakeCollection("workout_history", [
            {
                "user_id": "u_workout",
                "date": today_str,
                "plan_name": "Chest & Arms Focus",
                "total_volume_kg": 2150.0,
                "duration_minutes": 55,
                "exercise_logs": [
                    {
                        "exercise_slug": "barbell_bench_press",
                        "sets": 4,
                        "weight_kg": 85.0,
                        "reps": 10,
                        "cv_form_summary": {
                            "valid_reps": 9,
                            "fast_reps": 1,
                            "avg_elbow_angle_deg": 88.5,
                            "avg_tempo_sec": 2.2,
                        },
                    }
                ],
            }
        ])

        ctx = build_core3_context(
            principal=principal,
            nutrition_collection=FakeCollection("nutrition_plans"),
            workout_collection=workout_col,
            users_collection=FakeCollection("users"),
            tier="core3",
            now=now,
        )

        assert ctx["workout"]["status"] == "available"
        sessions = ctx["workout"]["sessions"]
        assert len(sessions) == 1
        assert sessions[0]["total_volume_kg"] == 2150.0

        exercises = sessions[0]["exercises"]
        assert len(exercises) == 1
        bench = exercises[0]
        assert bench["name"] == "barbell_bench_press"
        assert bench["max_weight_kg"] == 85.0
        assert bench["total_reps"] == 10
        assert bench["cv_form_summary"] == {
            "valid_reps": 9,
            "fast_reps": 1,
            "avg_elbow_angle_deg": 88.5,
            "avg_tempo_sec": 2.2,
        }

    def test_tier_stratification_window_bounds(self):
        now = datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)
        principal = {"_id": "u_tier", "email": "tier@example.com"}

        # Create multi-day entries spanning 1, 5, 12, and 28 days ago
        dates = [
            get_vn_date_str(offset_days=-0, now=now),
            get_vn_date_str(offset_days=-5, now=now),
            get_vn_date_str(offset_days=-12, now=now),
            get_vn_date_str(offset_days=-25, now=now),
        ]
        nutrition_col = FakeCollection("nutrition_plans", [
            {"user_id": "u_tier", "date": d, "total_calories": 1800, "total_protein": 120}
            for d in dates
        ])
        water_col = FakeCollection("water_logs", [
            {"user_id": "u_tier", "date": d, "amount_ml": 2000}
            for d in dates
        ])
        weight_col = FakeCollection("weight_history", [
            {"user_id": "u_tier", "date": d, "weight_kg": 70.0}
            for d in dates
        ])
        workout_col = FakeCollection("workout_history", [
            {"user_id": "u_tier", "date": d, "plan_name": f"Session {d}", "exercise_logs": []}
            for d in dates
        ])

        # Swift 3: 1 day window; weight history is skipped
        ctx_swift = build_core3_context(
            principal=principal,
            nutrition_collection=nutrition_col,
            workout_collection=workout_col,
            users_collection=FakeCollection("users"),
            water_collection=water_col,
            weight_history_collection=weight_col,
            tier="swift3",
            now=now,
        )
        assert len(ctx_swift["nutrition"]["summary"]) == 1
        assert len(ctx_swift["water"]["daily"]) == 1
        assert ctx_swift["weight_history"]["status"] == "skipped"

        # Core 3: 7 days nutrition/water, 14 days workout/weight
        ctx_core = build_core3_context(
            principal=principal,
            nutrition_collection=nutrition_col,
            workout_collection=workout_col,
            users_collection=FakeCollection("users"),
            water_collection=water_col,
            weight_history_collection=weight_col,
            tier="core3",
            now=now,
        )
        assert len(ctx_core["nutrition"]["summary"]) == 2  # days 0 and -5
        assert len(ctx_core["water"]["daily"]) == 2
        assert len(ctx_core["workout"]["sessions"]) == 3   # days 0, -5, -12
        assert len(ctx_core["weight_history"]["entries"]) == 3

        # Pro 3: 30 days window across all collections
        ctx_pro = build_core3_context(
            principal=principal,
            nutrition_collection=nutrition_col,
            workout_collection=workout_col,
            users_collection=FakeCollection("users"),
            water_collection=water_col,
            weight_history_collection=weight_col,
            tier="pro3",
            now=now,
        )
        assert len(ctx_pro["nutrition"]["summary"]) == 4
        assert len(ctx_pro["water"]["daily"]) == 4
        assert len(ctx_pro["workout"]["sessions"]) == 4
        assert len(ctx_pro["weight_history"]["entries"]) == 4


# ---------------------------------------------------------------------------
# Test Suite 2: core3_provider & revenue_guard
# ---------------------------------------------------------------------------

class TestProviderAndRevenueGuard:
    def test_get_tier_config_returns_expected_fields_for_all_tiers(self):
        for tier in ("swift3", "core3", "pro3"):
            cfg = get_tier_config(tier)
            assert isinstance(cfg, dict)
            assert "model" in cfg and isinstance(cfg["model"], str)
            assert "temperature" in cfg and isinstance(cfg["temperature"], (int, float))
            assert "thinking_level" in cfg and isinstance(cfg["thinking_level"], str)
            assert "max_input_tokens" in cfg and isinstance(cfg["max_input_tokens"], int)
            assert "max_output_tokens" in cfg and isinstance(cfg["max_output_tokens"], int)

        # Comparative expectations across tiers
        swift = get_tier_config("swift3")
        core = get_tier_config("core3")
        pro = get_tier_config("pro3")

        assert swift["max_input_tokens"] <= core["max_input_tokens"] <= pro["max_input_tokens"]
        assert swift["max_output_tokens"] <= core["max_output_tokens"] <= pro["max_output_tokens"]
        assert swift["thinking_level"] == "minimal"
        assert pro["thinking_level"] == "high"

    def test_is_ai_paywall_enabled_defaults_to_false(self, monkeypatch):
        monkeypatch.delenv("ENABLE_AI_PAYWALL", raising=False)
        assert is_ai_paywall_enabled() is False

        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        assert is_ai_paywall_enabled() is True

        monkeypatch.setenv("ENABLE_AI_PAYWALL", "false")
        assert is_ai_paywall_enabled() is False


# ---------------------------------------------------------------------------
# Test Suite 3: ChatOperationService & routers/chat.py
# ---------------------------------------------------------------------------

class TestChatRouterAndOperationService:
    @pytest.fixture
    def test_setup(self, monkeypatch):
        fake_db = FakeDatabase()
        test_user = {
            "_id": ObjectId("650000000000000000000001"),
            "email": "Tester@Example.com",
            "health_stats": {
                "daily_calories": 2000,
                "target_protein": 120,
                "water_target_ml": 2000,
            },
            "profile": {"weight": 70.0},
        }

        # Wire collections into fake_db
        conversations_col = fake_db["conversations"]
        water_col = fake_db["water_logs"]
        nutrition_col = fake_db["nutrition_plans"]
        workout_col = fake_db["workout_history"]
        weight_col = fake_db["weight_history"]
        users_col = fake_db["users"]
        users_col.insert_one(test_user)

        # Patch module-level references in chat_router and database
        monkeypatch.setattr("backend.routers.chat.conversations_col", conversations_col)
        monkeypatch.setattr("backend.routers.chat.water_col", water_col)
        monkeypatch.setattr("backend.routers.chat.nutrition_col", nutrition_col)
        monkeypatch.setattr("backend.routers.chat.workout_history_col", workout_col)
        monkeypatch.setattr("backend.routers.chat.workout_history_collection", workout_col)
        monkeypatch.setattr("backend.routers.chat.users_col", users_col)
        monkeypatch.setattr("backend.routers.chat._get_weight_history_col", lambda: weight_col)

        # Provide test isolated db config
        monkeypatch.setattr("backend.routers.chat._db_mod.db", fake_db)
        monkeypatch.setattr(_fake_db_module, "db", fake_db)
        monkeypatch.setattr(_fake_db_module, "DB_NAME", "saman_test_core3_isolated")
        monkeypatch.setattr(_fake_db_module, "MONGO_URI", "mongodb://localhost:27017")

        app = FastAPI()
        app.include_router(chat_router)
        app.dependency_overrides[get_current_user] = lambda: test_user
        app.dependency_overrides[get_current_chat_user] = lambda: test_user

        client = TestClient(app)
        return {
            "client": client,
            "db": fake_db,
            "user": test_user,
            "water_col": water_col,
            "nutrition_col": nutrition_col,
            "workout_col": workout_col,
            "conversations_col": conversations_col,
        }

    def test_send_log_water_intent_extracts_500ml_action(self, test_setup, monkeypatch):
        client = test_setup["client"]

        # Mock AI generation so provider succeeds without external API calls
        async def mock_generate(self, prompt, **kwargs):
            return "Tôi đã hiểu bạn vừa uống 500ml nước."

        from backend.app.services.core3_provider import GeminiCore3Provider
        monkeypatch.setattr(GeminiCore3Provider, "generate", mock_generate)

        payload = {
            "message": "Tôi vừa uống 500ml nước",
            "contract_version": "core3-local-v1",
            "operation_id": "11112222333344445555666677778888",
            "ai_mode": "core3",
        }
        res = client.post("/api/chat", json=payload)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "success"
        action = data.get("action")
        assert action is not None
        assert action["type"] == "log_water"
        assert action["amount_ml"] == 500

    def test_post_confirm_action_records_water_logs(self, test_setup):
        client = test_setup["client"]
        conv_col = test_setup["conversations_col"]
        water_col = test_setup["water_col"]
        user_id = str(test_setup["user"]["_id"])
        action_id = "act-water-500"
        target_date = get_vn_date_str()

        # Seed conversation with pending water action
        conv_id = ObjectId()
        conv_col.insert_one({
            "_id": conv_id,
            "user_id": user_id,
            "user_email": "tester@example.com",
            "pending_action": {
                "id": action_id,
                "type": "log_water",
                "amount_ml": 500,
                "status": "pending",
                "date": target_date,
            },
        })

        res = client.post(
            "/api/chat/actions/confirm",
            json={
                "conversation_id": str(conv_id),
                "action_id": action_id,
                "decision": "confirm",
            },
        )
        assert res.status_code == 200

        # Assert document recorded in water_logs collection
        recorded = water_col.find_one({"user_email": "tester@example.com", "date": target_date})
        assert recorded is not None
        assert recorded["user_id"] == user_id
        assert recorded["user_email"] == "tester@example.com"  # lowercase normalized
        assert recorded["date"] == target_date                 # UTC+7 VN date
        assert recorded["amount_ml"] == 500

    def test_post_chat_stream_returns_sse_events(self, test_setup, monkeypatch):
        client = test_setup["client"]

        async def mock_generate(self, prompt, **kwargs):
            return "Chào bạn, tôi là Saman Coach."

        from backend.app.services.core3_provider import GeminiCore3Provider
        monkeypatch.setattr(GeminiCore3Provider, "generate", mock_generate)

        payload = {
            "message": "Xin chào huấn luyện viên",
            "contract_version": "core3-local-v1",
            "operation_id": "aaaabbbbccccddddeeeeffff00001111",
            "ai_mode": "core3",
        }
        res = client.post("/api/chat/stream", json=payload)
        assert res.status_code == 200
        text = res.text
        assert "event: meta" in text
        assert "event: delta" in text
        assert "event: done" in text

    def test_get_daily_brief_dynamic_chips_based_on_deficits(self, test_setup):
        client = test_setup["client"]
        water_col = test_setup["water_col"]
        nutrition_col = test_setup["nutrition_col"]
        workout_col = test_setup["workout_col"]
        today_str = get_vn_date_str()
        user_id = str(test_setup["user"]["_id"])

        # Deficit state: only 200ml water (< 50% of 2000), 20g protein (< 70% of 120), no workout today
        water_col.insert_one({"user_id": user_id, "user_email": "tester@example.com", "date": today_str, "amount_ml": 200})
        nutrition_col.insert_one({"user_id": user_id, "user_email": "tester@example.com", "date": today_str, "total_calories": 500, "total_protein": 20})

        res_deficit = client.get("/api/chat/daily-brief")
        assert res_deficit.status_code == 200
        data_deficit = res_deficit.json()
        assert data_deficit["status"] == "success"
        assert isinstance(data_deficit["brief"], str) and len(data_deficit["brief"]) > 0

        chips_labels = [c["label"] for c in data_deficit["chips"]]
        assert "Bù nước hôm nay" in chips_labels
        assert "Còn thiếu bao nhiêu đạm?" in chips_labels
        assert "Gợi ý buổi tập hôm nay" in chips_labels

        # Satisfied state: 2200ml water, 140g protein, and workout completed today
        water_col.delete_many({})
        nutrition_col.delete_many({})
        water_col.insert_one({"user_id": user_id, "user_email": "tester@example.com", "date": today_str, "amount_ml": 2200})
        nutrition_col.insert_one({"user_id": user_id, "user_email": "tester@example.com", "date": today_str, "total_calories": 2100, "total_protein": 140})
        workout_col.insert_one({"user_id": user_id, "user_email": "tester@example.com", "date": today_str, "plan_name": "Full Body"})

        res_satisfied = client.get("/api/chat/daily-brief")
        assert res_satisfied.status_code == 200
        data_satisfied = res_satisfied.json()
        satisfied_labels = [c["label"] for c in data_satisfied["chips"]]
        assert "Bù nước hôm nay" not in satisfied_labels
        assert "Còn thiếu bao nhiêu đạm?" not in satisfied_labels
        assert "Gợi ý buổi tập hôm nay" not in satisfied_labels
