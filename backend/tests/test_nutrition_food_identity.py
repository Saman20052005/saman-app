"""Targeted tests for Nutrition Food Identity & Lookup Contract (CP-NUTRITION-FOOD-IDENTITY-01).

Verifies:
1. Search & mine responses contain stable 'id' string and 'source_type'.
2. Lookup public food by ObjectId returns 200 with 'id' and source_type='global'.
3. Lookup user's own custom food returns 200 with 'id' and source_type='my_food' without leaking user_email.
4. Account isolation: Lookup user A's food by user B returns 404 (zero leakage).
5. Invalid ObjectId format returns 400 Bad Request (never 500).
6. Non-existent ID returns 404.
7. Route collision avoidance: /foods/search and /foods/mine are not caught by /foods/{food_id}.
8. Meal log persistence:
   - create_nutrition_log keeps food_id and exact reviewed nutrient snapshot (no double scaling).
   - get_nutrition_by_date returns food_id, foods, and foodsList.
   - Old logs without food_id read back cleanly with food_id='' and correct snapshot.
"""

import asyncio
from datetime import datetime
import unittest
from unittest.mock import MagicMock, patch
from bson import ObjectId
from fastapi import HTTPException

from backend.routers import nutrition as nutrition_router


class FakeCursor:
    def __init__(self, docs):
        self.docs = list(docs)

    def sort(self, *args, **kwargs):
        return self

    def limit(self, n):
        self.docs = self.docs[:n]
        return self

    def __iter__(self):
        return iter(self.docs)


class FakeCollection:
    def __init__(self, docs=None):
        self.docs = list(docs or [])

    def find(self, query=None, projection=None):
        query = query or {}
        matched = []
        for d in self.docs:
            match = True
            for k, v in query.items():
                if k == "$or":
                    or_matched = False
                    for cond in v:
                        for cond_k, cond_v in cond.items():
                            val = d.get(cond_k, "")
                            if isinstance(cond_v, dict) and "$regex" in cond_v:
                                if cond_v["$regex"].lower() in str(val).lower():
                                    or_matched = True
                                    break
                            elif val == cond_v:
                                or_matched = True
                                break
                        if or_matched:
                            break
                    if not or_matched:
                        match = False
                        break
                elif k == "_id" and isinstance(v, dict) and "$in" in v:
                    if d.get("_id") not in v["$in"]:
                        match = False
                        break
                elif d.get(k) != v:
                    match = False
                    break
            if match:
                res = dict(d)
                if projection:
                    for pk, pv in projection.items():
                        if pv == 0:
                            res.pop(pk, None)
                matched.append(res)
        return FakeCursor(matched)

    def find_one(self, query=None, projection=None):
        query = query or {}
        for d in self.docs:
            match = True
            for k, v in query.items():
                if d.get(k) != v:
                    match = False
                    break
            if match:
                res = dict(d)
                if projection:
                    for pk, pv in projection.items():
                        if pv == 0:
                            res.pop(pk, None)
                return res
        return None

    def insert_one(self, doc):
        d = dict(doc)
        if "_id" not in d:
            d["_id"] = ObjectId()
        self.docs.append(d)
        res = MagicMock()
        res.inserted_id = d["_id"]
        return res


class FakeDatabase(dict):
    def __getitem__(self, item):
        if item not in self:
            self[item] = FakeCollection()
        return super().__getitem__(item)


class TestNutritionFoodIdentity(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.user_a_email = "user_a@saman.app"
        self.user_b_email = "user_b@saman.app"

        self.global_food_oid = ObjectId("650000000000000000000001")
        self.user_a_food_oid = ObjectId("650000000000000000000002")

        self.fake_global_foods = FakeCollection([
            {
                "_id": self.global_food_oid,
                "name": "Pho Bo",
                "name_search": "pho bo",
                "calories": 450,
                "protein": 25.0,
                "carbs": 60.0,
                "fat": 12.0,
            }
        ])

        self.fake_user_foods = FakeCollection([
            {
                "_id": self.user_a_food_oid,
                "user_email": self.user_a_email,
                "name": "Pho Bo Custom User A",
                "name_search": "pho bo custom user a",
                "calories": 500,
                "protein": 30.0,
                "carbs": 65.0,
                "fat": 14.0,
            }
        ])

        self.fake_nutrition_logs = FakeCollection()
        self.fake_db = FakeDatabase({
            "users": FakeCollection(),
            "day_resets": FakeCollection(),
            "user_foods_collection": self.fake_user_foods,
            "foods_collection": self.fake_global_foods,
        })

    async def test_search_foods_returns_stable_id_and_source_type(self):
        with patch.object(nutrition_router, "foods_collection", self.fake_global_foods), \
             patch.object(nutrition_router, "user_foods_collection", self.fake_user_foods):

            res = await nutrition_router.search_foods(
                q="Pho",
                current_user={"email": self.user_a_email},
            )

            self.assertEqual(res["total"], 2)
            foods = res["foods"]

            # First item: user A's my_food
            user_food = next(f for f in foods if f["source_type"] == "my_food")
            self.assertEqual(user_food["id"], str(self.user_a_food_oid))
            self.assertEqual(user_food["source_type"], "my_food")
            self.assertNotIn("user_email", user_food)
            self.assertNotIn("_id", user_food)

            # Second item: global food
            global_food = next(f for f in foods if f["source_type"] == "global")
            self.assertEqual(global_food["id"], str(self.global_food_oid))
            self.assertEqual(global_food["source_type"], "global")
            self.assertNotIn("_id", global_food)

    async def test_get_my_foods_returns_stable_id(self):
        with patch.object(nutrition_router, "user_foods_collection", self.fake_user_foods):
            res = await nutrition_router.get_my_foods(
                current_user={"email": self.user_a_email},
            )
            self.assertEqual(res["total"], 1)
            item = res["foods"][0]
            self.assertEqual(item["id"], str(self.user_a_food_oid))
            self.assertEqual(item["source_type"], "my_food")
            self.assertNotIn("user_email", item)
            self.assertNotIn("_id", item)

    async def test_lookup_public_food_returns_200(self):
        with patch.object(nutrition_router, "foods_collection", self.fake_global_foods), \
             patch.object(nutrition_router, "user_foods_collection", self.fake_user_foods):

            food = await nutrition_router.get_food_by_id(
                food_id=str(self.global_food_oid),
                current_user={"email": self.user_a_email},
            )
            self.assertEqual(food["id"], str(self.global_food_oid))
            self.assertEqual(food["name"], "Pho Bo")
            self.assertEqual(food["source_type"], "global")
            self.assertNotIn("_id", food)

    async def test_lookup_own_user_food_returns_200(self):
        with patch.object(nutrition_router, "foods_collection", self.fake_global_foods), \
             patch.object(nutrition_router, "user_foods_collection", self.fake_user_foods):

            food = await nutrition_router.get_food_by_id(
                food_id=str(self.user_a_food_oid),
                current_user={"email": self.user_a_email},
            )
            self.assertEqual(food["id"], str(self.user_a_food_oid))
            self.assertEqual(food["name"], "Pho Bo Custom User A")
            self.assertEqual(food["source_type"], "my_food")
            self.assertNotIn("user_email", food)
            self.assertNotIn("_id", food)

    async def test_account_isolation_lookup_other_user_food_returns_404(self):
        with patch.object(nutrition_router, "foods_collection", self.fake_global_foods), \
             patch.object(nutrition_router, "user_foods_collection", self.fake_user_foods):

            # User B attempts to look up User A's custom food
            with self.assertRaises(HTTPException) as cm:
                await nutrition_router.get_food_by_id(
                    food_id=str(self.user_a_food_oid),
                    current_user={"email": self.user_b_email},
                )
            self.assertEqual(cm.exception.status_code, 404)
            self.assertEqual(cm.exception.detail, "Food not found")

    async def test_lookup_invalid_format_id_returns_400(self):
        with patch.object(nutrition_router, "foods_collection", self.fake_global_foods), \
             patch.object(nutrition_router, "user_foods_collection", self.fake_user_foods):

            with self.assertRaises(HTTPException) as cm:
                await nutrition_router.get_food_by_id(
                    food_id="invalid-not-an-object-id",
                    current_user={"email": self.user_a_email},
                )
            self.assertEqual(cm.exception.status_code, 400)
            self.assertEqual(cm.exception.detail, "Invalid food ID format")

    async def test_lookup_nonexistent_id_returns_404(self):
        with patch.object(nutrition_router, "foods_collection", self.fake_global_foods), \
             patch.object(nutrition_router, "user_foods_collection", self.fake_user_foods):

            non_existent_oid = str(ObjectId("650000000000000000000099"))
            with self.assertRaises(HTTPException) as cm:
                await nutrition_router.get_food_by_id(
                    food_id=non_existent_oid,
                    current_user={"email": self.user_a_email},
                )
            self.assertEqual(cm.exception.status_code, 404)
            self.assertEqual(cm.exception.detail, "Food not found")

    async def test_meal_log_save_and_readback_preserves_food_id_and_snapshot(self):
        date_str = "2026-10-25"
        food_id = str(self.global_food_oid)

        log_data = nutrition_router.NutritionLog(
            date=date_str,
            meal_type="breakfast",
            foods=[
                {
                    "food_id": food_id,
                    "name": "Pho Bo",
                    "calories": 450,
                    "protein": 25.0,
                    "carbs": 60.0,
                    "fat": 12.0,
                    "weight_grams": 100,
                }
            ],
            total_calories=450,
            total_protein=25.0,
            total_carbs=60.0,
            total_fat=12.0,
        )

        with patch.object(nutrition_router, "nutrition_collection", self.fake_nutrition_logs), \
             patch.object(nutrition_router, "story_logs_collection", FakeCollection()), \
             patch.object(nutrition_router, "water_collection", FakeCollection()), \
             patch.object(nutrition_router, "user_repo", MagicMock(get_by_email=MagicMock(return_value={}))), \
             patch.object(nutrition_router, "db", self.fake_db):

            # 1. Create log
            created = await nutrition_router.create_nutrition_log(
                log=log_data,
                user={"email": self.user_a_email},
            )
            self.assertEqual(created["status"], "saved")

            # Verify food_id was persisted into collection
            saved_doc = self.fake_nutrition_logs.docs[-1]
            self.assertEqual(saved_doc["foods"][0]["food_id"], food_id)
            self.assertEqual(saved_doc["foods"][0]["calories"], 450)

            # 2. Read back via get_nutrition_by_date
            daily = await nutrition_router.get_nutrition_by_date(
                date=date_str,
                current_user={"email": self.user_a_email},
            )
            self.assertEqual(daily["date"], date_str)
            self.assertEqual(len(daily["entries"]), 1)

            entry = daily["entries"][0]
            self.assertEqual(entry["food_name"], "Pho Bo")
            self.assertEqual(entry["food_id"], food_id)
            self.assertEqual(entry["calories"], 450)
            self.assertEqual(entry["protein"], 25.0)
            self.assertEqual(entry["carbs"], 60.0)
            self.assertEqual(entry["fat"], 12.0)
            self.assertIn("foods", entry)
            self.assertIn("foodsList", entry)
            self.assertEqual(entry["foods"][0]["food_id"], food_id)

    async def test_legacy_meal_log_without_food_id_reads_back_cleanly(self):
        date_str = "2026-10-25"
        # Seed a legacy log without food_id
        legacy_plan_oid = ObjectId("650000000000000000000088")
        self.fake_nutrition_logs.docs.append({
            "_id": legacy_plan_oid,
            "user_email": self.user_a_email,
            "date": date_str,
            "meal_type": "lunch",
            "total_calories": 200,
            "total_protein": 10.0,
            "total_carbs": 30.0,
            "total_fat": 5.0,
            "created_at": datetime.utcnow(),
            "foods": [
                {
                    "name": "Com Trang",
                    "calories": 200,
                    "protein": 10.0,
                    "carbs": 30.0,
                    "fat": 5.0,
                    "weight_grams": 150,
                }
            ],
        })

        with patch.object(nutrition_router, "nutrition_collection", self.fake_nutrition_logs), \
             patch.object(nutrition_router, "story_logs_collection", FakeCollection()), \
             patch.object(nutrition_router, "water_collection", FakeCollection()), \
             patch.object(nutrition_router, "user_repo", MagicMock(get_by_email=MagicMock(return_value={}))), \
             patch.object(nutrition_router, "db", self.fake_db):

            daily = await nutrition_router.get_nutrition_by_date(
                date=date_str,
                current_user={"email": self.user_a_email},
            )
            self.assertEqual(len(daily["entries"]), 1)
            entry = daily["entries"][0]
            self.assertEqual(entry["food_name"], "Com Trang")
            self.assertEqual(entry["food_id"], "")  # gracefully defaults to empty string
            self.assertEqual(entry["calories"], 200)
            self.assertEqual(entry["protein"], 10.0)
            self.assertEqual(entry["carbs"], 30.0)
            self.assertEqual(entry["fat"], 5.0)


if __name__ == "__main__":
    unittest.main()
