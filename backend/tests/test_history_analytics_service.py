from datetime import datetime, timedelta, time, timezone
import uuid
from zoneinfo import ZoneInfo

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pymongo import MongoClient

from backend.app.services.core3_provider import GeminiCore3Provider
from backend.app.services.history_analytics_service import (
    MAX_WORKOUTS,
    build_bounded_history_context,
    ensure_history_analytics_indexes,
    preflight_estimate,
)

try:
    from backend.auth_utils import get_current_user
except ModuleNotFoundError as exc:
    if exc.name != "jwt":
        raise
    import sys
    from types import ModuleType

    auth_utils_test_stub = ModuleType("backend.auth_utils")

    def get_current_user():
        raise AssertionError("Test authentication dependency must be overridden")

    auth_utils_test_stub.get_current_user = get_current_user
    sys.modules["backend.auth_utils"] = auth_utils_test_stub

from backend.routers.analytics import (
    get_history_analytics_db,
    get_history_analytics_provider,
    router as analytics_router,
)


VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


@pytest.fixture
def isolated_history_db():
    client = MongoClient("mongodb://127.0.0.1:27017", serverSelectionTimeoutMS=1500)
    try:
        client.admin.command("ping")
    except Exception as exc:
        client.close()
        pytest.skip(f"Local isolated MongoDB is unavailable: {type(exc).__name__}")

    database = client["saman_test_core3_isolated"]
    ensure_history_analytics_indexes(database)
    suffix = uuid.uuid4().hex
    user_id = f"cp05a2_{suffix}"
    user_email = f"cp05a2_{suffix}@example.test"
    database["nutrition_plans"].delete_many({"user_email": user_email})
    database["workout_history"].delete_many({"user_id": user_id})
    try:
        yield database, user_id, user_email
    finally:
        database["nutrition_plans"].delete_many({"user_email": user_email})
        database["workout_history"].delete_many({"user_id": user_id})
        client.close()


def _test_client(database, user_id, user_email, provider=None):
    app = FastAPI()
    app.include_router(analytics_router)
    app.dependency_overrides[get_current_user] = lambda: {
        "_id": user_id,
        "email": user_email,
    }
    app.dependency_overrides[get_history_analytics_db] = lambda: database
    if provider is not None:
        app.dependency_overrides[get_history_analytics_provider] = lambda: provider
    return TestClient(app)


def _today_vn():
    return datetime.now(VN_TZ).date()


def _insert_workout(database, user_id, day, **fields):
    started_at = datetime.combine(day, time(hour=12), VN_TZ).astimezone(timezone.utc)
    database["workout_history"].insert_one(
        {
            "user_id": user_id,
            "email": f"{user_id}@example.test",
            "date": day.isoformat(),
            "started_at": started_at,
            "exercise_logs": [],
            **fields,
        }
    )


def _explain_has_ixscan(database, collection_name, query):
    plan = database.command(
        "explain",
        {
            "aggregate": collection_name,
            "pipeline": [{"$match": query}, {"$limit": 1}],
            "cursor": {},
        },
        verbosity="queryPlanner",
    )
    return "IXSCAN" in str(plan)


def test_indexes_ixscan_and_30_day_bounds(isolated_history_db):
    database, user_id, user_email = isolated_history_db
    indexes = ensure_history_analytics_indexes(database)
    assert set(indexes) == {"nutrition", "workout_date", "workout_started_at"}

    today = _today_vn()
    for offset in range(45):
        day = today - timedelta(days=offset)
        database["nutrition_plans"].insert_one(
            {
                "user_email": user_email,
                "date": day.isoformat(),
                "total_calories": 1800,
                "total_protein": 90,
                "total_carbs": 200,
                "total_fat": 60,
            }
        )
        _insert_workout(database, user_id, day, total_duration_minutes=30)

    context = build_bounded_history_context(database, user_id, user_email, 30)
    assert len(context["nutrition"]) == 30
    assert len(context["workouts"]) == 30
    assert context["nutrition"][0]["date"] == (today - timedelta(days=29)).isoformat()
    assert context["nutrition"][-1]["date"] == today.isoformat()

    start_date = (today - timedelta(days=29)).isoformat()
    end_date = today.isoformat()
    assert _explain_has_ixscan(
        database,
        "nutrition_plans",
        {"user_email": user_email, "date": {"$gte": start_date, "$lte": end_date}},
    )
    assert _explain_has_ixscan(
        database,
        "workout_history",
        {"user_id": user_id, "date": {"$gte": start_date, "$lte": end_date}},
    )
    assert _explain_has_ixscan(
        database,
        "workout_history",
        {
            "user_id": user_id,
            "started_at": {"$gte": datetime.combine(today - timedelta(days=29), time.min, VN_TZ).astimezone(timezone.utc)},
        },
    )


def test_schema_projection_and_legacy_mapping(isolated_history_db):
    database, user_id, user_email = isolated_history_db
    today = _today_vn()
    database["nutrition_plans"].insert_one(
        {
            "user_email": user_email,
            "date": today.isoformat(),
            "total_calories": 2100,
            "total_protein": 140,
            "total_carbs": 220,
            "total_fat": 65,
        }
    )
    _insert_workout(
        database,
        user_id,
        today,
        total_duration_minutes=42,
        exercise_logs=[
            {"exercise_slug": "barbell-bench-press"},
            {"exercise_slug": "cable-row"},
        ],
    )

    context = build_bounded_history_context(database, user_id, user_email, 7)
    assert context["nutrition"] == [
        {
            "date": today.isoformat(),
            "calories": 2100.0,
            "protein": 140.0,
            "carbs": 220.0,
            "fat": 65.0,
            "meals": 1,
        }
    ]
    assert context["workouts"][0]["duration_minutes"] == 42
    assert context["workouts"][0]["exercises"] == [
        "barbell-bench-press",
        "cable-row",
    ]


def test_dense_30_day_preflight_respects_3770_token_cap(isolated_history_db):
    database, user_id, user_email = isolated_history_db
    today = _today_vn()
    nutrition_rows = []
    workout_rows = []
    for offset in range(30):
        day = today - timedelta(days=offset)
        for _ in range(50):
            nutrition_rows.append(
                {
                    "user_email": user_email,
                    "date": day.isoformat(),
                    "total_calories": 500,
                    "total_protein": 25,
                    "total_carbs": 50,
                    "total_fat": 10,
                }
            )
    database["nutrition_plans"].insert_many(nutrition_rows)
    for offset in range(30):
        day = today - timedelta(days=offset)
        for _ in range(4):
            workout_rows.append(
                {
                    "user_id": user_id,
                    "date": day.isoformat(),
                    "started_at": datetime.combine(day, time(hour=12), VN_TZ).astimezone(timezone.utc),
                    "exercise_logs": [],
                }
            )
    database["workout_history"].insert_many(workout_rows)

    quote = preflight_estimate(database, user_id, user_email, 30)
    assert quote["raw_nutrition_count"] == 1500
    assert quote["active_days"] == 30
    assert quote["matched_workout_sessions"] == 120
    assert quote["included_workout_sessions"] == MAX_WORKOUTS[30] == 72
    assert quote["workout_truncated"] is True
    assert quote["estimated_tokens"] == 3770
    assert quote["estimated_tokens"] <= 3770


@pytest.mark.parametrize("range_days", [60, "all_time"])
def test_all_time_policy_is_forbidden(isolated_history_db, range_days):
    database, user_id, user_email = isolated_history_db
    client = _test_client(database, user_id, user_email)
    response = client.post(
        "/api/coach/analytics/preflight", json={"range_days": range_days}
    )
    assert response.status_code == 403
    assert response.json()["detail"]["code"] == "ALL_TIME_GATED_BY_POLICY"


def test_execute_requires_explicit_confirmation(isolated_history_db):
    database, user_id, user_email = isolated_history_db
    client = _test_client(database, user_id, user_email)
    response = client.post(
        "/api/coach/analytics/execute",
        json={"quote_id": "unused", "range_days": 7, "confirm": False},
    )
    assert response.status_code == 400
    assert "confirmation is required" in response.json()["detail"].lower()


def test_execute_dispatches_once_through_core3_adapter(isolated_history_db):
    database, user_id, user_email = isolated_history_db
    today = _today_vn()
    database["nutrition_plans"].insert_one(
        {
            "user_email": user_email,
            "date": today.isoformat(),
            "total_calories": 1900,
            "total_protein": 100,
            "total_carbs": 210,
            "total_fat": 55,
        }
    )

    class FakeGemini:
        def __init__(self):
            self.calls = []

        def generate_content(self, prompt, generation_config):
            self.calls.append((prompt, generation_config))
            return type("Result", (), {"text": "Xu hướng ổn định."})()

    engine = FakeGemini()
    client = _test_client(
        database, user_id, user_email, GeminiCore3Provider(engine=engine)
    )
    preflight = client.post(
        "/api/coach/analytics/preflight", json={"range_days": 7}
    )
    assert preflight.status_code == 200
    quote = preflight.json()

    request_body = {
        "quote_id": quote["quote_id"],
        "range_days": 7,
        "confirm": True,
        "operation_id": "cp05a2-test-operation-1",
    }
    response = client.post("/api/coach/analytics/execute", json=request_body)
    assert response.status_code == 200
    assert response.json()["report"] == "Xu hướng ổn định."
    assert response.json()["quote_id"] == quote["quote_id"]
    replay = client.post("/api/coach/analytics/execute", json=request_body)
    assert replay.status_code == 200
    assert replay.json() == response.json()
    assert len(engine.calls) == 1
    assert engine.calls[0][1]["max_output_tokens"] == 512
