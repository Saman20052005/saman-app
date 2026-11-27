"""Stage 1 Nutrition CRUD tests (POST /logs, PATCH /logs/{log_id}, DELETE /logs/{log_id}).

Covers:
1. POST /api/nutrition/logs recalculates total_calories & macros server-side from resolved_foods.
2. POST /api/nutrition/logs safely falls back to client total_calories when foods is empty or lacks item calories.
3. PATCH /api/nutrition/logs/{log_id} updates meal_type, removes/edits foods, preserves edited values,
   and recalculates total_calories, total_protein, total_carbs, total_fat, and updated_at.
4. PATCH /api/nutrition/logs/{log_id} with portion_multiplier and total_grams scales grams & macros linearly,
   and rejects non-positive multipliers/grams with 400.
5. PATCH /api/nutrition/logs/{log_id} with foods=[] returns 400.
6. PATCH /api/nutrition/logs/{log_id} by another user, non-existent log_id, or invalid ObjectId returns 404.
7. DELETE /api/nutrition/logs/{log_id} deletes once (200), returns 404 on repeat delete,
   unauthorized user, or invalid ObjectId format.
"""

from datetime import datetime
from unittest.mock import MagicMock, patch
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.auth_utils import get_current_user
from backend.routers import nutrition as nutrition_router


def _matches_query(doc: dict, query: dict) -> bool:
    for key, val in (query or {}).items():
        if key == "$and":
            if not all(_matches_query(doc, clause) for clause in val):
                return False
        elif key == "$or":
            if not any(_matches_query(doc, clause) for clause in val):
                return False
        elif isinstance(val, dict):
            doc_val = doc.get(key)
            if "$in" in val and doc_val not in val["$in"]:
                return False
            if "$exists" in val and ((key in doc) != bool(val["$exists"])):
                return False
        else:
            if doc.get(key) != val:
                return False
    return True


class FakeCursor:
    def __init__(self, docs):
        self.docs = list(docs)

    def sort(self, *args, **kwargs):
        return self

    def __iter__(self):
        return iter(self.docs)


class FakeCollection:
    def __init__(self, docs=None):
        self.docs = [dict(d) for d in (docs or [])]

    def insert_one(self, doc):
        d = dict(doc)
        if "_id" not in d:
            d["_id"] = ObjectId()
        self.docs.append(d)
        res = MagicMock()
        res.inserted_id = d["_id"]
        return res

    def find(self, query=None, projection=None):
        matched = [dict(d) for d in self.docs if _matches_query(d, query or {})]
        return FakeCursor(matched)

    def find_one(self, query=None, projection=None):
        for d in self.docs:
            if _matches_query(d, query or {}):
                return dict(d)
        return None

    def update_one(self, query, update):
        res = MagicMock()
        res.matched_count = 0
        res.modified_count = 0
        for d in self.docs:
            if _matches_query(d, query or {}):
                res.matched_count = 1
                if "$set" in update:
                    d.update(update["$set"])
                    res.modified_count = 1
                break
        return res

    def delete_one(self, query):
        res = MagicMock()
        res.deleted_count = 0
        for idx, d in enumerate(self.docs):
            if _matches_query(d, query or {}):
                self.docs.pop(idx)
                res.deleted_count = 1
                break
        return res


class FakeDatabase(dict):
    def __getattr__(self, item):
        if item in self:
            return self[item]
        return None


def _build_client(active_user_holder: dict) -> TestClient:
    app = FastAPI()
    app.include_router(nutrition_router.router)
    app.dependency_overrides[get_current_user] = lambda: active_user_holder["user"]
    return TestClient(app)


USER_A = {"id": "user-a-id", "email": "user_a@saman.app"}
USER_B = {"id": "user-b-id", "email": "user_b@saman.app"}


def test_post_log_recalculates_calories_and_macros_server_side():
    fake_logs = FakeCollection()
    fake_db = FakeDatabase()
    active = {"user": USER_A}
    client = _build_client(active)

    payload = {
        "date": "2026-11-27",
        "meal_type": "lunch",
        "foods": [
            {
                "name": "Grilled Chicken Breast",
                "grams": 150,
                "calories": 250,
                "protein": 46.5,
                "carbs": 0.0,
                "fat": 5.4,
            },
            {
                "name": "Brown Rice",
                "grams": 200,
                "calories": 270,
                "protein": 5.5,
                "carbs": 56.0,
                "fat": 2.1,
            },
        ],
        "total_calories": 9999,
        "total_protein": 1.0,
        "total_carbs": 1.0,
        "total_fat": 1.0,
        "notes": "Post-workout lunch",
    }

    with patch.object(nutrition_router, "nutrition_collection", fake_logs), \
         patch.object(nutrition_router, "db", fake_db):
        resp = client.post("/api/nutrition/logs", json=payload)

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "saved"
    assert body["id"]
    assert body["log"]["total_calories"] == 520
    assert body["log"]["total_protein"] == 52.0
    assert body["log"]["total_carbs"] == 56.0
    assert body["log"]["total_fat"] == 7.5

    assert len(fake_logs.docs) == 1
    saved = fake_logs.docs[0]
    assert saved["total_calories"] == 520
    assert saved["total_protein"] == 52.0
    assert saved["total_carbs"] == 56.0
    assert saved["total_fat"] == 7.5


def test_post_log_fallback_to_client_calories_when_foods_empty_or_missing_calories():
    fake_logs = FakeCollection()
    fake_db = FakeDatabase()
    active = {"user": USER_A}
    client = _build_client(active)

    with patch.object(nutrition_router, "nutrition_collection", fake_logs), \
         patch.object(nutrition_router, "db", fake_db):
        resp_empty = client.post(
            "/api/nutrition/logs",
            json={
                "date": "2026-11-27",
                "meal_type": "snack",
                "foods": [],
                "total_calories": 310,
            },
        )
        resp_no_cal = client.post(
            "/api/nutrition/logs",
            json={
                "date": "2026-11-27",
                "meal_type": "snack",
                "foods": [{"name": "Quick Snack", "protein": 10.0, "carbs": 20.0, "fat": 5.0}],
                "total_calories": 165,
            },
        )

    assert resp_empty.status_code == 200
    assert resp_empty.json()["log"]["total_calories"] == 310
    assert fake_logs.docs[0]["total_calories"] == 310

    assert resp_no_cal.status_code == 200
    assert resp_no_cal.json()["log"]["total_calories"] == 165
    assert resp_no_cal.json()["log"]["total_protein"] == 10.0
    assert fake_logs.docs[1]["total_calories"] == 165


def test_patch_log_updates_meal_type_removes_item_and_recalculates_totals():
    food_oid = ObjectId()
    log_oid = ObjectId()
    old_updated_at = datetime(2026, 1, 1, 0, 0, 0)

    fake_logs = FakeCollection([
        {
            "_id": log_oid,
            "user_id": USER_A["id"],
            "user_email": USER_A["email"],
            "date": "2026-11-27",
            "meal_type": "lunch",
            "foods": [
                {
                    "food_id": str(food_oid),
                    "name": "Chicken Breast",
                    "grams": 100,
                    "calories": 165,
                    "protein": 31.0,
                    "carbs": 0.0,
                    "fat": 3.6,
                },
                {
                    "name": "White Rice",
                    "grams": 150,
                    "calories": 195,
                    "protein": 4.0,
                    "carbs": 42.0,
                    "fat": 0.4,
                },
            ],
            "total_calories": 360,
            "total_protein": 35.0,
            "total_carbs": 42.0,
            "total_fat": 4.0,
            "notes": "Original",
            "created_at": old_updated_at,
            "updated_at": old_updated_at,
        }
    ])
    # DB catalog has 100g=165 kcal; user edits item to 200g=330 kcal — must NOT be overwritten
    fake_global_foods = FakeCollection([
        {
            "_id": food_oid,
            "name": "Chicken Breast",
            "calories": 165,
            "protein": 31.0,
            "carbs": 0.0,
            "fat": 3.6,
        }
    ])
    fake_db = FakeDatabase({"foods_collection": fake_global_foods})
    active = {"user": USER_A}
    client = _build_client(active)

    with patch.object(nutrition_router, "nutrition_collection", fake_logs), \
         patch.object(nutrition_router, "db", fake_db):
        resp = client.patch(
            f"/api/nutrition/logs/{log_oid}",
            json={
                "meal_type": "dinner",
                "notes": "Removed rice, doubled chicken",
                "foods": [
                    {
                        "food_id": str(food_oid),
                        "name": "Chicken Breast",
                        "grams": 200,
                        "calories": 330,
                        "protein": 62.0,
                        "carbs": 0.0,
                        "fat": 7.2,
                    }
                ],
            },
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == str(log_oid)
    assert body["date"] == "2026-11-27"
    assert body["meal_type"] == "dinner"
    assert body["notes"] == "Removed rice, doubled chicken"
    assert len(body["foods"]) == 1
    assert body["foods"][0]["grams"] == 200
    assert body["total_calories"] == 330
    assert body["total_protein"] == 62.0
    assert body["total_carbs"] == 0.0
    assert body["total_fat"] == 7.2
    assert body["status"] == "updated"
    assert body["updated_at"] != old_updated_at.isoformat()

    updated_doc = fake_logs.docs[0]
    assert updated_doc["meal_type"] == "dinner"
    assert updated_doc["total_calories"] == 330
    assert updated_doc["total_protein"] == 62.0
    assert updated_doc["updated_at"] > old_updated_at


def test_patch_log_scales_with_portion_multiplier_and_total_grams():
    log_oid = ObjectId()
    fake_logs = FakeCollection([
        {
            "_id": log_oid,
            "user_id": USER_A["id"],
            "user_email": USER_A["email"],
            "date": "2026-11-27",
            "meal_type": "breakfast",
            "foods": [
                {
                    "name": "Oats",
                    "grams": 100,
                    "portion_grams": 100,
                    "calories": 380,
                    "protein": 13.2,
                    "carbs": 66.0,
                    "fat": 6.8,
                },
                {
                    "name": "Banana",
                    "amount": 100,
                    "calories": 90,
                    "protein": 1.0,
                    "carbs": 23.0,
                    "fat": 0.2,
                },
            ],
            "total_calories": 470,
            "total_protein": 14.2,
            "total_carbs": 89.0,
            "total_fat": 7.0,
        }
    ])
    fake_db = FakeDatabase()
    active = {"user": USER_A}
    client = _build_client(active)

    with patch.object(nutrition_router, "nutrition_collection", fake_logs), \
         patch.object(nutrition_router, "db", fake_db):
        resp_mult = client.patch(
            f"/api/nutrition/logs/{log_oid}",
            json={"portion_multiplier": 1.5},
        )
        assert resp_mult.status_code == 200
        body = resp_mult.json()
        assert body["foods"][0]["grams"] == 150.0
        assert body["foods"][0]["portion_grams"] == 150.0
        assert body["foods"][0]["calories"] == 570
        assert body["foods"][1]["amount"] == 150.0
        assert body["foods"][1]["calories"] == 135
        assert body["total_calories"] == 705
        assert body["total_protein"] == 21.3
        assert body["total_carbs"] == 133.5
        assert body["total_fat"] == 10.5

        # Now scale by total_grams from 300g -> 150g (multiplier = 0.5)
        resp_grams = client.patch(
            f"/api/nutrition/logs/{log_oid}",
            json={"total_grams": 150},
        )
        assert resp_grams.status_code == 200
        body_grams = resp_grams.json()
        assert body_grams["foods"][0]["grams"] == 75.0
        assert body_grams["foods"][1]["amount"] == 75.0
        assert body_grams["total_calories"] == 353  # 285 + 68 (round(67.5) = 68)

        # Invalid multiplier <= 0 -> 400
        resp_bad = client.patch(
            f"/api/nutrition/logs/{log_oid}",
            json={"portion_multiplier": 0},
        )
        assert resp_bad.status_code == 400


def test_patch_log_empty_foods_returns_400():
    log_oid = ObjectId()
    fake_logs = FakeCollection([
        {
            "_id": log_oid,
            "user_id": USER_A["id"],
            "user_email": USER_A["email"],
            "date": "2026-11-27",
            "meal_type": "snack",
            "foods": [{"name": "Apple", "calories": 95, "protein": 0.5, "carbs": 25.0, "fat": 0.3}],
            "total_calories": 95,
        }
    ])
    fake_db = FakeDatabase()
    active = {"user": USER_A}
    client = _build_client(active)

    with patch.object(nutrition_router, "nutrition_collection", fake_logs), \
         patch.object(nutrition_router, "db", fake_db):
        resp = client.patch(f"/api/nutrition/logs/{log_oid}", json={"foods": []})

    assert resp.status_code == 400
    assert "DELETE" in resp.json()["detail"]


def test_patch_log_unauthorized_nonexistent_and_invalid_id_return_404():
    log_oid = ObjectId()
    fake_logs = FakeCollection([
        {
            "_id": log_oid,
            "user_id": USER_A["id"],
            "user_email": USER_A["email"],
            "date": "2026-11-27",
            "meal_type": "lunch",
            "foods": [{"name": "Pho Bo", "calories": 450, "protein": 25.0, "carbs": 60.0, "fat": 12.0}],
            "total_calories": 450,
        }
    ])
    fake_db = FakeDatabase()
    active = {"user": USER_B}
    client = _build_client(active)

    with patch.object(nutrition_router, "nutrition_collection", fake_logs), \
         patch.object(nutrition_router, "db", fake_db):
        # Other user tries to patch User A's log
        resp_other = client.patch(f"/api/nutrition/logs/{log_oid}", json={"meal_type": "dinner"})
        assert resp_other.status_code == 404

        # Non-existent valid ObjectId
        resp_missing = client.patch(f"/api/nutrition/logs/{ObjectId()}", json={"meal_type": "dinner"})
        assert resp_missing.status_code == 404

        # Malformed ObjectId
        resp_invalid = client.patch("/api/nutrition/logs/not-a-valid-object-id", json={"meal_type": "dinner"})
        assert resp_invalid.status_code == 404

    # Original log remained untouched
    assert fake_logs.docs[0]["meal_type"] == "lunch"


def test_delete_log_succeeds_once_and_returns_404_on_repeat_or_invalid():
    log_oid = ObjectId()
    fake_logs = FakeCollection([
        {
            "_id": log_oid,
            "user_id": USER_A["id"],
            "user_email": USER_A["email"],
            "date": "2026-11-27",
            "meal_type": "dinner",
            "foods": [{"name": "Salad", "calories": 200, "protein": 10.0, "carbs": 15.0, "fat": 8.0}],
            "total_calories": 200,
        }
    ])
    active = {"user": USER_B}
    client = _build_client(active)

    with patch.object(nutrition_router, "nutrition_collection", fake_logs):
        # User B cannot delete User A's log
        resp_other = client.delete(f"/api/nutrition/logs/{log_oid}")
        assert resp_other.status_code == 404

        # Malformed ObjectId -> 404 (not 500)
        resp_invalid = client.delete("/api/nutrition/logs/bad-id-format")
        assert resp_invalid.status_code == 404

        # Switch to User A -> delete succeeds
        active["user"] = USER_A
        resp_first = client.delete(f"/api/nutrition/logs/{log_oid}")
        assert resp_first.status_code == 200
        assert resp_first.json()["id"] == str(log_oid)
        assert resp_first.json()["message"] == "Deleted"

        # Second delete -> 404
        resp_second = client.delete(f"/api/nutrition/logs/{log_oid}")
        assert resp_second.status_code == 404
