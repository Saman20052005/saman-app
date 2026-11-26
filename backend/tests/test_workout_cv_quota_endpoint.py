"""
Unit tests for POST /api/workouts/cv/authorize (workout.cv.ai weekly quota enforcement)
and regression check for POST /api/workouts/sessions with 5-key cv_form_summary.
"""

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import threading
from typing import Any, Dict, List, Optional

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
    COLL_SUBSCRIPTIONS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
)
from backend.app.models.revenue import MembershipTier, ReservationResult, ReservationStatus, SubscriptionStatus
from backend.app.services.quota_service import TIER_QUOTA_LIMITS, QuotaService
from backend.auth_utils import get_current_user
import backend.routers.workout as workout_mod


# ---------------------------------------------------------------------------
# In-memory Mongo mock supporting $expr ($lte, $add, $ifNull), $in, $inc, $set
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
            val = doc.get(field_ref[1:]) if isinstance(field_ref, str) and field_ref.startswith("$") else field_ref
            return default_val if val is None else val
    return expr


class FakeCollection:
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
            if k == "$and":
                if not all(self._matches(doc, clause) for clause in v):
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


class FakeDB:
    def __init__(self):
        self._cols: Dict[str, FakeCollection] = {}

    def __getitem__(self, name: str) -> FakeCollection:
        if name not in self._cols:
            self._cols[name] = FakeCollection(name)
        return self._cols[name]


def _seed_user_and_tier(db: FakeDB, email: str, account_id: str, tier: Optional[MembershipTier] = None) -> dict:
    uid = ObjectId()
    user_doc = {
        "_id": uid,
        "email": email,
        "account_id": account_id,
        "full_name": f"User {tier.value if tier else 'free'}",
    }
    db["users"].insert_one(user_doc)
    if tier is not None and tier != MembershipTier.FREE:
        now = datetime.now(timezone.utc)
        db[COLL_SUBSCRIPTIONS].insert_one({
            "subscription_id": f"sub_{account_id}",
            "user_id": account_id,
            "tier": tier.value,
            "status": SubscriptionStatus.ACTIVE.value,
            "current_period_start": now - timedelta(days=1),
            "current_period_end": now + timedelta(days=30),
        })
    return user_doc


@pytest.fixture
def cv_test_env(monkeypatch):
    fake_db = FakeDB()
    monkeypatch.setattr(app_db, "db", fake_db)
    monkeypatch.setattr(workout_mod._db_mod, "db", fake_db)

    app = FastAPI()
    app.include_router(workout_mod.router)

    state = {"user": None}
    app.dependency_overrides[get_current_user] = lambda: state["user"]
    client = TestClient(app)
    return fake_db, client, state


def test_cv_authorize_paywall_disabled_allows_without_consuming_quota(cv_test_env, monkeypatch):
    fake_db, client, state = cv_test_env
    monkeypatch.setenv("ENABLE_AI_PAYWALL", "false")
    state["user"] = _seed_user_and_tier(fake_db, "free_off@saman.test", "acct_" + "0" * 32)

    resp = client.post("/api/workouts/cv/authorize", json={})
    assert resp.status_code == 200
    body = resp.json()
    assert body["allowed"] is True
    assert body["paywall_enforced"] is False
    assert body["benefit_id"] == "workout.cv.ai"
    assert body["operation_id"] is None
    # Verify no quota bucket or operation was written
    assert len(fake_db[COLL_USAGE_BUCKETS].docs) == 0
    assert len(fake_db[COLL_USAGE_OPERATIONS].docs) == 0

    # Also verify empty body (no JSON) does not 422
    resp_empty = client.post("/api/workouts/cv/authorize")
    assert resp_empty.status_code == 200
    assert resp_empty.json()["allowed"] is True


def test_cv_authorize_free_tier_weekly_limit_blocks_on_third_call(cv_test_env, monkeypatch):
    fake_db, client, state = cv_test_env
    monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
    state["user"] = _seed_user_and_tier(fake_db, "free@saman.test", "acct_" + "1" * 32)

    # Call 1 -> 200, remaining 1 / limit 2
    r1 = client.post(
        "/api/workouts/cv/authorize",
        json={"exercise_slug": "lat-pulldown", "source_mode": "realtime"},
    )
    assert r1.status_code == 200
    b1 = r1.json()
    assert b1["allowed"] is True
    assert b1["paywall_enforced"] is True
    assert b1["tier"] == "free"
    assert b1["benefit_id"] == "workout.cv.ai"
    assert b1["limit_units"] == 2
    assert b1["remaining_units"] == 1
    assert b1["operation_id"] is not None

    # Call 2 -> 200, remaining 0 / limit 2
    r2 = client.post(
        "/api/workouts/cv/authorize",
        json={"exercise_slug": "lat-pulldown", "source_mode": "video_upload"},
    )
    assert r2.status_code == 200
    b2 = r2.json()
    assert b2["allowed"] is True
    assert b2["limit_units"] == 2
    assert b2["remaining_units"] == 0
    assert b2["operation_id"] != b1["operation_id"]

    # Call 3 -> 429 quota_exceeded
    r3 = client.post("/api/workouts/cv/authorize", json={})
    assert r3.status_code == 429
    detail = r3.json()["detail"]
    assert detail["code"] == "quota_exceeded"
    assert detail["benefit_id"] == "workout.cv.ai"
    assert detail["limit_units"] == 2
    assert detail["remaining_units"] == 0
    assert "Form Check AI" in detail["message"]


def test_cv_authorize_plus_tier_weekly_limit_five_blocks_on_sixth_call(cv_test_env, monkeypatch):
    fake_db, client, state = cv_test_env
    monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
    # Deterministic override for Plus tier weekly limit = 5 (reads dynamically from TIER_QUOTA_LIMITS)
    monkeypatch.setitem(TIER_QUOTA_LIMITS["plus"], "workout.cv.ai", ("weekly", 5))
    state["user"] = _seed_user_and_tier(fake_db, "plus@saman.test", "acct_" + "2" * 32, MembershipTier.PLUS)

    for expected_remaining in (4, 3, 2, 1, 0):
        resp = client.post("/api/workouts/cv/authorize", json={"exercise_slug": "squat"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["allowed"] is True
        assert body["paywall_enforced"] is True
        assert body["tier"] == "plus"
        assert body["benefit_id"] == "workout.cv.ai"
        assert body["limit_units"] == 5
        assert body["remaining_units"] == expected_remaining

    # Call 6 -> 429 quota_exceeded
    r6 = client.post("/api/workouts/cv/authorize", json={"exercise_slug": "squat"})
    assert r6.status_code == 429
    detail = r6.json()["detail"]
    assert detail["code"] == "quota_exceeded"
    assert detail["benefit_id"] == "workout.cv.ai"
    assert detail["limit_units"] == 5
    assert detail["remaining_units"] == 0


@pytest.mark.parametrize("tier,hex_char", [(MembershipTier.PRO, "3"), (MembershipTier.ULTRA, "4")])
def test_cv_authorize_pro_and_ultra_unlimited(cv_test_env, monkeypatch, tier, hex_char):
    fake_db, client, state = cv_test_env
    monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
    state["user"] = _seed_user_and_tier(fake_db, f"{tier.value}@saman.test", "acct_" + hex_char * 32, tier)

    for _ in range(8):
        resp = client.post("/api/workouts/cv/authorize", json={"exercise_slug": "lat-pulldown"})
        assert resp.status_code == 200
        body = resp.json()
        assert body["allowed"] is True
        assert body["paywall_enforced"] is True
        assert body["tier"] == tier.value
        assert body["benefit_id"] == "workout.cv.ai"
        assert body["limit_units"] == -1
        assert body["remaining_units"] == -1
        assert body["operation_id"] is not None


def test_cv_authorize_idempotency_key_does_not_double_deduct(cv_test_env, monkeypatch):
    fake_db, client, state = cv_test_env
    monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
    state["user"] = _seed_user_and_tier(fake_db, "idem@saman.test", "acct_" + "5" * 32)

    idem_key = "cv-session-retry-001"
    r1 = client.post(
        "/api/workouts/cv/authorize",
        json={"exercise_slug": "lat-pulldown", "idempotency_key": idem_key},
    )
    assert r1.status_code == 200
    b1 = r1.json()
    assert b1["limit_units"] == 2
    assert b1["remaining_units"] == 1

    # Replay with the exact same idempotency_key must NOT deduct a second unit
    r2 = client.post(
        "/api/workouts/cv/authorize",
        json={"exercise_slug": "lat-pulldown", "idempotency_key": idem_key},
    )
    assert r2.status_code == 200
    b2 = r2.json()
    assert b2["allowed"] is True
    assert b2["operation_id"] == b1["operation_id"]
    assert b2["limit_units"] == 2
    assert b2["remaining_units"] == 1

    # A new distinct idempotency_key should still succeed as the 2nd unit
    r3 = client.post(
        "/api/workouts/cv/authorize",
        json={"exercise_slug": "lat-pulldown", "idempotency_key": "cv-session-retry-002"},
    )
    assert r3.status_code == 200
    assert r3.json()["remaining_units"] == 0


def test_cv_authorize_storage_unavailable_returns_503(cv_test_env, monkeypatch):
    fake_db, client, state = cv_test_env
    monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
    state["user"] = _seed_user_and_tier(fake_db, "outage@saman.test", "acct_" + "6" * 32)

    def _fake_reserve_unavailable(self, *args, **kwargs):
        return ReservationResult(
            status=ReservationStatus.STORAGE_UNAVAILABLE,
            units=1,
            error_message="Simulated Mongo outage",
        )

    monkeypatch.setattr(QuotaService, "reserve_quota", _fake_reserve_unavailable)

    resp = client.post("/api/workouts/cv/authorize", json={"exercise_slug": "lat-pulldown"})
    assert resp.status_code == 503
    detail = resp.json()["detail"]
    assert detail["code"] == "storage_unavailable"
    assert detail["benefit_id"] == "workout.cv.ai"


def test_regression_post_workout_sessions_cv_form_summary_five_keys_preserved(cv_test_env, monkeypatch):
    fake_db, client, state = cv_test_env
    monkeypatch.setattr(workout_mod, "workout_history_collection", fake_db["workout_history"])
    state["user"] = _seed_user_and_tier(fake_db, "regression@saman.test", "acct_" + "7" * 32)

    five_key_summary = {
        "valid_reps": 10,
        "fast_reps": 1,
        "abort_count": 0,
        "min_angle": 52.4,
        "max_angle": 168.9,
    }
    payload = {
        "id": "ws-0123456789abcdef0123456789abcdef",
        "planName": "Back CV Session",
        "startedAt": "2026-11-26T10:00:00Z",
        "finishedAt": "2026-11-26T10:30:00Z",
        "exerciseLogs": [
            {
                "exerciseId": "lat-pulldown",
                "exerciseSlug": "lat-pulldown",
                "setNumber": 1,
                "repsCompleted": 11,
                "weightKg": 45.0,
                "isCompleted": True,
                "cvDetected": True,
                "cvFormSummary": five_key_summary,
            }
        ],
        "totalDurationMinutes": 30,
        "totalVolumeKg": 495,
        "cvFormSummary": five_key_summary,
    }

    resp = client.post("/api/workouts/sessions", json=payload)
    assert resp.status_code == 201
    body = resp.json()
    session_out = body["session"]
    assert session_out["cvFormSummary"] == five_key_summary
    assert set(session_out["cvFormSummary"].keys()) == {
        "valid_reps",
        "fast_reps",
        "abort_count",
        "min_angle",
        "max_angle",
    }
    assert session_out["exerciseLogs"][0]["cvDetected"] is True
    assert session_out["exerciseLogs"][0]["cvFormSummary"] == five_key_summary
