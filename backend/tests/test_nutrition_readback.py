"""Tests for Nutrition readback contract & photo URL resolution (CP-NUTRITION-PHOTO-02).

Verifies:
1. Linked story image is resolved and returned in `entries` when owned by current_user.
2. Account isolation: Linked story belonging to a different user is NEVER leaked.
3. Meals without story_id or without image do not include `image_url`.
4. Response structure, macro calculations, and `foodsList` are fully preserved.
"""

import asyncio
from datetime import datetime
import unittest
from unittest.mock import MagicMock, patch
from bson import ObjectId

# Import router handler
from backend.routers import nutrition as nutrition_router


class FakeCursor:
    def __init__(self, docs):
        self.docs = list(docs)

    def sort(self, *args, **kwargs):
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
                if k == "_id" and isinstance(v, dict) and "$in" in v:
                    if d.get("_id") not in v["$in"]:
                        match = False
                        break
                elif d.get(k) != v:
                    match = False
                    break
            if match:
                res = dict(d)
                matched.append(res)
        return FakeCursor(matched)

    def find_one(self, query=None, *args, **kwargs):
        query = query or {}
        for d in self.docs:
            match = True
            for k, v in query.items():
                if d.get(k) != v:
                    match = False
                    break
            if match:
                return dict(d)
        return None


class FakeDatabase(dict):
    def __getitem__(self, item):
        if item not in self:
            self[item] = FakeCollection()
        return super().__getitem__(item)


class TestNutritionReadback(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.fake_db = FakeDatabase({
            "users": FakeCollection(),
            "day_resets": FakeCollection(),
        })

    async def test_readback_with_linked_story_image_owned_by_user(self):
        user_email = "test_user@saman.app"
        date_str = "2026-10-27"
        story_oid = ObjectId("6ae061a7f98778c5af8fc5ef")
        plan_oid = ObjectId("6ae061a7f98778c5af8fc5f0")

        fake_nutrition_plans = FakeCollection([
            {
                "_id": plan_oid,
                "user_email": user_email,
                "date": date_str,
                "meal_type": "dinner",
                "total_calories": 125,
                "total_protein": 16.5,
                "total_carbs": 3.5,
                "total_fat": 4.2,
                "story_id": str(story_oid),
                "created_at": datetime.utcnow(),
                "foods": [
                    {
                        "name": "Grilled Chicken Salad",
                        "weight_grams": 100,
                        "calories": 125,
                        "protein": 16.5,
                        "carbs": 3.5,
                        "fat": 4.2,
                    }
                ],
            }
        ])

        fake_story_logs = FakeCollection([
            {
                "_id": story_oid,
                "user_email": user_email,
                "image_url": "https://res.cloudinary.com/saman/image/upload/v1/salad.jpg",
            }
        ])

        with patch.object(nutrition_router, "nutrition_collection", fake_nutrition_plans), \
             patch.object(nutrition_router, "story_logs_collection", fake_story_logs), \
             patch.object(nutrition_router, "water_collection", FakeCollection()), \
             patch.object(nutrition_router, "user_repo", MagicMock(get_by_email=MagicMock(return_value={}))), \
             patch.object(nutrition_router, "db", self.fake_db):

            res = await nutrition_router.get_nutrition_by_date(
                date=date_str,
                current_user={"email": user_email, "id": "u1"},
            )

            self.assertEqual(res["date"], date_str)
            self.assertEqual(len(res["entries"]), 1)
            entry = res["entries"][0]
            self.assertEqual(entry["food_name"], "Grilled Chicken Salad")
            self.assertEqual(entry["calories"], 125)
            self.assertEqual(entry["image_url"], "https://res.cloudinary.com/saman/image/upload/v1/salad.jpg")
            self.assertIn("foodsList", entry)
            self.assertEqual(len(entry["foodsList"]), 1)

    async def test_readback_story_different_owner_never_leaked(self):
        user_email = "test_user@saman.app"
        other_user = "attacker@other.com"
        date_str = "2026-10-27"
        story_oid = ObjectId("6ae061a7f98778c5af8fc5ef")
        plan_oid = ObjectId("6ae061a7f98778c5af8fc5f0")

        fake_nutrition_plans = FakeCollection([
            {
                "_id": plan_oid,
                "user_email": user_email,
                "date": date_str,
                "meal_type": "lunch",
                "total_calories": 300,
                "story_id": str(story_oid),
                "created_at": datetime.utcnow(),
                "foods": [{"name": "Rice", "calories": 300}],
            }
        ])

        # Story belongs to another user
        fake_story_logs = FakeCollection([
            {
                "_id": story_oid,
                "user_email": other_user,
                "image_url": "https://secret.com/private_other_user.jpg",
            }
        ])

        with patch.object(nutrition_router, "nutrition_collection", fake_nutrition_plans), \
             patch.object(nutrition_router, "story_logs_collection", fake_story_logs), \
             patch.object(nutrition_router, "water_collection", FakeCollection()), \
             patch.object(nutrition_router, "user_repo", MagicMock(get_by_email=MagicMock(return_value={}))), \
             patch.object(nutrition_router, "db", self.fake_db):

            res = await nutrition_router.get_nutrition_by_date(
                date=date_str,
                current_user={"email": user_email, "id": "u1"},
            )

            self.assertEqual(len(res["entries"]), 1)
            entry = res["entries"][0]
            # Must NOT contain image_url from another user
            self.assertNotIn("image_url", entry)

    async def test_readback_without_story_id(self):
        user_email = "test_user@saman.app"
        date_str = "2026-10-27"
        plan_oid = ObjectId("6ae061a7f98778c5af8fc5f1")

        fake_nutrition_plans = FakeCollection([
            {
                "_id": plan_oid,
                "user_email": user_email,
                "date": date_str,
                "meal_type": "breakfast",
                "total_calories": 250,
                "story_id": None,
                "created_at": datetime.utcnow(),
                "foods": [{"name": "Oatmeal", "calories": 250}],
            }
        ])

        with patch.object(nutrition_router, "nutrition_collection", fake_nutrition_plans), \
             patch.object(nutrition_router, "story_logs_collection", FakeCollection()), \
             patch.object(nutrition_router, "water_collection", FakeCollection()), \
             patch.object(nutrition_router, "user_repo", MagicMock(get_by_email=MagicMock(return_value={}))), \
             patch.object(nutrition_router, "db", self.fake_db):

            res = await nutrition_router.get_nutrition_by_date(
                date=date_str,
                current_user={"email": user_email, "id": "u1"},
            )

            self.assertEqual(len(res["entries"]), 1)
            entry = res["entries"][0]
            self.assertNotIn("image_url", entry)
            self.assertEqual(entry["calories"], 250)


if __name__ == "__main__":
    unittest.main()

