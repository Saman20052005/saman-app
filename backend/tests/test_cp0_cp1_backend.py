import importlib.util
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
from types import ModuleType, SimpleNamespace

_repo_root = str(Path(__file__).parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

import pytest
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

# Prevent production database initialization while importing router dependencies.
_database_module = ModuleType("backend.app.database")
for _collection_name in (
    "users_collection",
    "foods_collection",
    "nutrition_collection",
    "story_logs_collection",
    "workout_history_collection",
    "custom_plans_collection",
    "exercises_collection",
    "water_collection",
    "user_foods_collection",
    "weight_history_collection",
):
    setattr(_database_module, _collection_name, None)
_database_module.db = None
_database_module.get_users_collection = lambda: None
sys.modules.setdefault("backend.app.database", _database_module)


def _load_router_module(name):
    router_path = Path(__file__).parents[1] / "routers" / f"{name}.py"
    module_name = f"_cp0_cp1_{name}_router"
    spec = importlib.util.spec_from_file_location(module_name, router_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


from backend.auth_utils import get_current_user
from backend.app.services.context_utils import (
    build_user_query,
    get_vn_date_str,
    get_vn_day_range_utc,
)

nutrition_router = _load_router_module("nutrition")
user_router = _load_router_module("user")
workout_router = _load_router_module("workout")


class MemoryCursor:
    def __init__(self, documents):
        self.documents = list(documents)

    def sort(self, key_or_spec, direction=None):
        sort_spec = (
            key_or_spec
            if isinstance(key_or_spec, list)
            else [(key_or_spec, direction or 1)]
        )
        for field, order in reversed(sort_spec):
            self.documents.sort(
                key=lambda doc: _field_value(doc, field),
                reverse=order < 0,
            )
        return self

    def limit(self, count):
        self.documents = self.documents[:count]
        return self

    def __iter__(self):
        return iter(self.documents)


def _field_value(document, field):
    value = document
    for part in field.split("."):
        value = value.get(part) if isinstance(value, dict) else None
    return value


def _matches(document, query):
    for field, expected in query.items():
        if field == "$and":
            if not all(_matches(document, clause) for clause in expected):
                return False
        elif field == "$or":
            if not any(_matches(document, clause) for clause in expected):
                return False
        else:
            actual = _field_value(document, field)
            if isinstance(expected, dict):
                for operator, operand in expected.items():
                    if operator == "$gte" and (actual is None or actual < operand):
                        return False
                    if operator == "$lte" and (actual is None or actual > operand):
                        return False
                    if operator == "$in" and actual not in operand:
                        return False
                    if operator == "$exists" and (actual is not None) != operand:
                        return False
            elif actual != expected:
                return False
    return True


class MemoryCollection:
    def __init__(self, documents=None):
        self.documents = [deepcopy(doc) for doc in (documents or [])]

    def find(self, query=None, projection=None):
        matches = [
            deepcopy(doc)
            for doc in self.documents
            if _matches(doc, query or {})
        ]
        return MemoryCursor(matches)

    def find_one(self, query=None, projection=None):
        return next(iter(self.find(query, projection)), None)

    def insert_one(self, document):
        stored = deepcopy(document)
        stored.setdefault("_id", ObjectId())
        self.documents.append(stored)
        return SimpleNamespace(inserted_id=stored["_id"])


class MemoryDatabase(dict):
    def __getitem__(self, name):
        if name not in self:
            self[name] = MemoryCollection()
        return super().__getitem__(name)


def _client_with_user(router, dependency, user):
    app = FastAPI()
    app.include_router(router)
    app.dependency_overrides[dependency] = lambda: user
    return TestClient(app)


def test_build_user_query_matches_id_and_normalized_email_variants():
    user_id = "650000000000000000000001"

    assert build_user_query(user_id, "  User@Example.COM ") == {
        "$or": [
            {"user_id": user_id},
            {"user_id": ObjectId(user_id)},
            {"user_email": "user@example.com"},
            {"email": "user@example.com"},
        ]
    }
    assert build_user_query("not-an-object-id", None) == {
        "$or": [{"user_id": "not-an-object-id"}]
    }
    assert build_user_query(None, None) == {"_id": None}


def test_vietnam_date_uses_local_day_at_utc_1730():
    now = datetime(2026, 4, 30, 17, 30, tzinfo=timezone.utc)

    assert get_vn_date_str(now=now) == "2026-05-01"


def test_vietnam_day_range_is_utc():
    start_utc, end_utc = get_vn_day_range_utc("2026-05-01")

    assert start_utc == datetime(2026, 4, 30, 17, 0, tzinfo=timezone.utc)
    assert end_utc == datetime(
        2026, 5, 1, 16, 59, 59, 999999, tzinfo=timezone.utc
    )


def _nutrition_client(monkeypatch, workouts=None, meals=None):
    user = {
        "_id": ObjectId("650000000000000000000001"),
        "email": "tester@example.com",
        "health_stats": {
            "daily_calories": 2000,
            "target_protein": 100,
            "target_carbs": 200,
            "target_fat": 60,
        },
        "profile": {},
    }
    meals_collection = MemoryCollection(meals)
    monkeypatch.setattr(nutrition_router, "nutrition_collection", meals_collection)
    monkeypatch.setattr(
        nutrition_router, "workout_history_collection", MemoryCollection(workouts)
    )
    monkeypatch.setattr(nutrition_router, "db", MemoryDatabase())
    monkeypatch.setattr(
        nutrition_router, "_get_user_record", lambda *_args: user
    )
    client = _client_with_user(
        nutrition_router.router, get_current_user, user
    )
    return client, meals_collection, user


def test_nutrition_date_uses_training_targets_and_rest_targets(monkeypatch):
    date_str = "2026-05-01"
    client, _, _ = _nutrition_client(
        monkeypatch,
        workouts=[
            {
                "user_id": "650000000000000000000001",
                "date": date_str,
                "calories_burned": 300,
            }
        ],
    )

    training = client.get(f"/api/nutrition/{date_str}")
    assert training.status_code == 200
    assert training.json()["day_mode"] == "training"
    assert training.json()["dynamic_target"]["calories"] == 2300
    assert training.json()["dynamic_target"]["carbs"] == 252

    monkeypatch.setattr(
        nutrition_router, "workout_history_collection", MemoryCollection()
    )
    rest = client.get(f"/api/nutrition/{date_str}")
    assert rest.status_code == 200
    assert rest.json()["day_mode"] == "rest"
    assert rest.json()["dynamic_target"]["calories"] == 2000
    assert rest.json()["dynamic_target"]["carbs"] == 200


def test_recent_meals_and_quick_relog_use_memory_collection(monkeypatch):
    today = get_vn_date_str()
    yesterday = get_vn_date_str(offset_days=-1)
    foods = [{"name": "Rice", "calories": 200, "protein": 4, "carbs": 45, "fat": 1}]
    client, collection, user = _nutrition_client(
        monkeypatch,
        meals=[
            {
                "_id": ObjectId(),
                "user_id": str(user_id := ObjectId("650000000000000000000001")),
                "date": yesterday,
                "meal_type": "lunch",
                "foods": foods,
                "created_at": datetime.now(timezone.utc) - timedelta(days=1),
            },
            {
                "_id": ObjectId(),
                "user_id": str(user_id),
                "date": today,
                "meal_type": "lunch",
                "foods": foods,
                "created_at": datetime.now(timezone.utc),
            },
        ],
    )

    recent = client.get("/api/nutrition/recent-meals?days=3")
    assert recent.status_code == 200
    assert recent.json()["total"] == 1
    assert recent.json()["meals"][0]["frequency"] == 2
    assert recent.json()["meals"][0]["foods"] == foods

    relog = client.post(
        "/api/nutrition/quick-relog",
        json={"date": today, "meal_type": "dinner", "foods": foods},
    )
    assert relog.status_code == 200
    assert relog.json()["status"] == "saved"
    assert relog.json()["meal"]["total_calories"] == 200
    assert relog.json()["meal"]["user_id"] == str(user["_id"])
    assert collection.documents[-1]["date"] == today


def _workout_client(monkeypatch, documents=None):
    user = {
        "_id": ObjectId("650000000000000000000001"),
        "email": "tester@example.com",
    }
    collection = MemoryCollection(documents)
    monkeypatch.setattr(workout_router, "workout_history_collection", collection)
    client = _client_with_user(workout_router.router, get_current_user, user)
    return client, collection, user


def test_workout_session_persists_and_serializes_cv_form_summary(monkeypatch):
    client, collection, _ = _workout_client(monkeypatch)
    summary = {
        "valid_reps": 1,
        "fast_reps": 1,
        "avg_elbow_angle_deg": 45.7,
        "avg_tempo_sec": 2.13,
        "abort_count": 2,
    }

    response = client.post(
        "/api/workouts/sessions",
        json={
            "planName": "Lat Pulldown",
            "startedAt": "2026-10-12T10:00:00Z",
            "exerciseLogs": [],
            "cvFormSummary": summary,
        },
    )

    assert response.status_code == 201
    assert collection.documents[0]["cv_form_summary"] == summary
    assert response.json()["session"]["cvFormSummary"] == summary


@pytest.mark.parametrize(
    ("is_completed", "reps_completed", "expected_weight"),
    [(True, 8, 22.5), (True, 7, 20.0), (False, 8, 20.0)],
)
def test_last_performance_suggests_weight_only_after_completed_target(
    monkeypatch, is_completed, reps_completed, expected_weight
):
    client, _, user = _workout_client(
        monkeypatch,
        documents=[
            {
                "user_id": "650000000000000000000001",
                "started_at": datetime(2026, 5, 1, tzinfo=timezone.utc),
                "exercise_logs": [
                    {
                        "exercise_slug": "lat-pulldown",
                        "set_number": 1,
                        "weight_kg": 20.0,
                        "reps_completed": reps_completed,
                        "is_completed": is_completed,
                    }
                ],
            }
        ],
    )

    response = client.get(
        "/api/workouts/last-performance",
        params={"exercise_ids": "lat-pulldown"},
    )

    assert response.status_code == 200, response.text
    performance = response.json()["items"]["lat-pulldown"]
    assert performance["last_weight_kg"] == 20.0
    assert performance["suggested_weight_kg"] == expected_weight


def test_weight_history_returns_ascending_entries_and_delta(monkeypatch):
    user = {
        "_id": ObjectId("650000000000000000000001"),
        "email": "tester@example.com",
    }
    today = datetime.strptime(get_vn_date_str(), "%Y-%m-%d").date()
    collection = MemoryCollection(
        [
            {
                "user_id": str(user["_id"]),
                "date": (today - timedelta(days=1)).isoformat(),
                "weight_kg": 71.25,
                "source": "manual_log",
            },
            {
                "user_id": str(user["_id"]),
                "date": (today - timedelta(days=3)).isoformat(),
                "weight_kg": 70.0,
                "source": "manual_log",
            },
        ]
    )
    monkeypatch.setattr(user_router, "_get_weight_history_collection", lambda: collection)
    client = _client_with_user(
        user_router.router, user_router.get_current_user, user
    )

    response = client.get("/api/user/weight-history?days=30")

    assert response.status_code == 200
    body = response.json()
    assert [entry["weight_kg"] for entry in body["entries"]] == [70.0, 71.25]
    assert body["delta_kg"] == 1.25
