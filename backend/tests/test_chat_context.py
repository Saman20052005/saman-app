# [File: backend/tests/test_chat_context.py]
import os
import sys
import asyncio
import unittest
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from unittest.mock import patch, MagicMock

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import backend.routers.chat as chat_module
from backend.routers.chat import (
    build_health_context,
    _get_current_vn_date,
    chat_with_ai,
    ChatRequest,
)

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


class FakeCursor(list):
    def sort(self, *args, **kwargs):
        return self


class MockMongoCollection:
    """Mock MongoDB collection supporting read queries and asserting read-only safety."""

    def __init__(self, docs=None, allow_writes=False):
        self.docs = list(docs) if docs else []
        self.allow_writes = allow_writes
        self.write_calls = []

    def find(self, query=None):
        query = query or {}
        results = []
        for doc in self.docs:
            match = True
            if "$or" in query:
                or_matches = False
                for branch in query["$or"]:
                    branch_match = True
                    for k, v in branch.items():
                        if doc.get(k) != v:
                            branch_match = False
                            break
                    if branch_match:
                        or_matches = True
                        break
                if not or_matches:
                    match = False
            # Check other top-level keys
            for k, v in query.items():
                if k != "$or":
                    if doc.get(k) != v:
                        match = False
                        break
            if match:
                results.append(doc)
        return FakeCursor(results)

    def find_one(self, query=None):
        res = self.find(query)
        return res[0] if res else None

    # Write operations must fail on health data to enforce strict read-only requirement
    def insert_one(self, doc, *args, **kwargs):
        self.write_calls.append(("insert_one", doc, kwargs))
        if not self.allow_writes:
            raise RuntimeError("Write operation not allowed in read-only health context")
        from bson import ObjectId
        doc_copy = dict(doc)
        if "_id" not in doc_copy:
            doc_copy["_id"] = ObjectId()
        self.docs.append(doc_copy)
        mock_res = MagicMock()
        mock_res.inserted_id = doc_copy["_id"]
        return mock_res

    def insert_many(self, *args, **kwargs):
        self.write_calls.append(("insert_many", args, kwargs))
        if not self.allow_writes:
            raise RuntimeError("Write operation not allowed in read-only health context")

    def update_one(self, *args, **kwargs):
        self.write_calls.append(("update_one", args, kwargs))
        if not self.allow_writes:
            raise RuntimeError("Write operation not allowed in read-only health context")

    def update_many(self, *args, **kwargs):
        self.write_calls.append(("update_many", args, kwargs))
        if not self.allow_writes:
            raise RuntimeError("Write operation not allowed in read-only health context")

    def delete_one(self, *args, **kwargs):
        self.write_calls.append(("delete_one", args, kwargs))
        raise RuntimeError("Write operation not allowed in read-only health context")

    def delete_many(self, *args, **kwargs):
        self.write_calls.append(("delete_many", args, kwargs))
        raise RuntimeError("Write operation not allowed in read-only health context")


class TestChatHealthContext(unittest.TestCase):
    """Test suite for Checkpoint 2: Real read-only health context injection in Chat AI."""

    def setUp(self):
        self.mock_users_col = MockMongoCollection(allow_writes=False)
        self.mock_nutrition_col = MockMongoCollection(allow_writes=False)
        self.mock_workout_col = MockMongoCollection(allow_writes=False)
        self.mock_conv_col = MockMongoCollection(allow_writes=True)

        # Patch module-level collection references
        chat_module.users_col = self.mock_users_col
        chat_module.nutrition_col = self.mock_nutrition_col
        chat_module.workout_history_col = self.mock_workout_col
        chat_module.conversations_col = self.mock_conv_col

    def tearDown(self):
        chat_module.users_col = None
        chat_module.nutrition_col = None
        chat_module.workout_history_col = None
        chat_module.conversations_col = None

    def test_case_1_user_with_full_data_populates_exact_metrics(self):
        """Test Case 1: User has full DB data -> Prompt/Context must contain exact numbers and no email."""
        vn_today = datetime.now(VN_TZ).strftime("%Y-%m-%d")

        user_data = {
            "_id": "user_full_001",
            "email": "athlete@saman.app",
            "full_name": "Nguyen Van An",
            "weight": 72.5,
            "goal": "muscle_gain",
            "health_stats": {
                "tdee": 2450,
                "daily_calories": 2450,
            },
        }
        self.mock_users_col.docs = [user_data]

        # 2 nutrition logs logged today in VN timezone
        self.mock_nutrition_col.docs = [
            {
                "user_email": "athlete@saman.app",
                "date": vn_today,
                "meal_type": "breakfast",
                "total_calories": 550,
                "total_protein": 42.0,
                "total_carbs": 60.0,
                "total_fat": 15.0,
            },
            {
                "user_email": "athlete@saman.app",
                "date": vn_today,
                "meal_type": "lunch",
                "total_calories": 780,
                "total_protein": 58.0,
                "total_carbs": 85.0,
                "total_fat": 22.0,
            },
        ]
        # Total nutrition: 1330 kcal, 100g pro, 145g carb, 37g fat

        # Latest workout
        self.mock_workout_col.docs = [
            {
                "email": "athlete@saman.app",
                "user_id": "user_full_001",
                "date": vn_today,
                "duration_minutes": 50,
                "completed_exercises": [
                    {"name": "Barbell Squat"},
                    {"name": "Leg Press"},
                    {"name": "Romanian Deadlift"},
                ],
            }
        ]

        # 1. Test build_health_context directly
        context = build_health_context(
            user_data,
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
            users_col_ref=self.mock_users_col,
        )

        # Profile checks
        self.assertIn("72.5 kg", context)
        self.assertIn("muscle_gain", context)
        self.assertIn("2450 kcal", context)

        # Nutrition checks
        self.assertIn(vn_today, context)
        self.assertIn("Đã ghi nhận: 2 bữa", context)
        self.assertIn("1330 kcal", context)
        self.assertIn("100.0g", context)
        self.assertIn("145.0g", context)
        self.assertIn("37.0g", context)

        # Workout checks
        self.assertIn("50 phút", context)
        self.assertIn("Barbell Squat", context)
        self.assertIn("Leg Press", context)
        self.assertIn("Romanian Deadlift", context)

        # Security check: User email must NOT leak into context
        self.assertNotIn("athlete@saman.app", context)

        # 2. Test full prompt injection via chat_with_ai with spoofing attempt
        captured_prompts = []

        async def fake_reply(prompt: str):
            captured_prompts.append(prompt)
            return "Chào An, hôm nay bạn đã ăn 1330 kcal và tập chân rất tốt!"

        with patch("backend.routers.chat._generate_ai_reply", side_effect=fake_reply):
            req = ChatRequest(
                message="Tôi nên ăn gì sau buổi tập hôm nay?",
                context={
                    "spoofed_weight": 999,
                    "fake_calories": 5000,
                    "fake_goal": "fake_goal",
                },
            )
            res = asyncio.run(chat_with_ai(req, current_user=user_data))
            self.assertEqual(res["status"], "success")

        self.assertEqual(len(captured_prompts), 1)
        prompt = captured_prompts[0]

        # Injected at top of prompt
        self.assertTrue(prompt.startswith("HỒ SƠ NGƯỜI DÙNG:"))

        # Exact numbers present in AI prompt
        self.assertIn("72.5 kg", prompt)
        self.assertIn("muscle_gain", prompt)
        self.assertIn("2450 kcal", prompt)
        self.assertIn("1330 kcal", prompt)
        self.assertIn("100.0g", prompt)
        self.assertIn("Barbell Squat", prompt)

        # Spoofed data ignored completely
        self.assertNotIn("999", prompt)
        self.assertNotIn("5000", prompt)
        self.assertNotIn("fake_goal", prompt)

        # No email in AI prompt
        self.assertNotIn("athlete@saman.app", prompt)

        # Verify zero writes performed to health collections
        self.assertEqual(len(self.mock_nutrition_col.write_calls), 0)
        self.assertEqual(len(self.mock_workout_col.write_calls), 0)

    def test_case_2_new_user_empty_data_shows_chua_co_du_lieu(self):
        """Test Case 2: New user (no data) -> Prompt must show 'chưa có dữ liệu' for missing fields."""
        new_user = {
            "_id": "user_empty_999",
            "email": "newbie@saman.app",
        }
        self.mock_users_col.docs = [new_user]
        self.mock_nutrition_col.docs = []
        self.mock_workout_col.docs = []

        # 1. Test build_health_context
        context = build_health_context(
            new_user,
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
            users_col_ref=self.mock_users_col,
        )

        self.assertIn("Cân nặng: chưa có dữ liệu", context)
        self.assertIn("Mục tiêu: chưa có dữ liệu", context)
        self.assertIn("TDEE: chưa có dữ liệu", context)
        self.assertIn("chưa có dữ liệu", context)
        self.assertIn("TẬP LUYỆN GẦN NHẤT: chưa có dữ liệu", context)

        # No user email leaked
        self.assertNotIn("newbie@saman.app", context)

        # 2. Test via chat_with_ai
        captured_prompts = []

        async def fake_reply(prompt: str):
            captured_prompts.append(prompt)
            return "Chào bạn, hãy cập nhật cân nặng và mục tiêu của bạn nhé!"

        with patch("backend.routers.chat._generate_ai_reply", side_effect=fake_reply):
            req = ChatRequest(message="Tư vấn cho tôi")
            res = asyncio.run(chat_with_ai(req, current_user=new_user))
            self.assertEqual(res["status"], "success")

        prompt = captured_prompts[0]
        self.assertIn("Cân nặng: chưa có dữ liệu", prompt)
        self.assertIn("Mục tiêu: chưa có dữ liệu", prompt)
        self.assertIn("TDEE: chưa có dữ liệu", prompt)
        self.assertIn("TẬP LUYỆN GẦN NHẤT: chưa có dữ liệu", prompt)
        self.assertNotIn("newbie@saman.app", prompt)

        # Verify zero writes performed to health collections
        self.assertEqual(len(self.mock_nutrition_col.write_calls), 0)
        self.assertEqual(len(self.mock_workout_col.write_calls), 0)

    def test_case_3_account_isolation_user_a_never_sees_user_b_data(self):
        """Test Case 3: Account Isolation -> User A must never see User B's metrics or email."""
        vn_today = datetime.now(VN_TZ).strftime("%Y-%m-%d")

        user_a = {
            "_id": "user_a_id",
            "email": "alice@saman.app",
            "full_name": "Alice Tran",
            "weight": 52.0,
            "goal": "lose_weight",
            "health_stats": {"tdee": 1650},
        }

        user_b = {
            "_id": "user_b_id",
            "email": "bob@saman.app",
            "full_name": "Bob Nguyen",
            "weight": 92.0,
            "goal": "heavy_bulk",
            "health_stats": {"tdee": 3200},
        }

        self.mock_users_col.docs = [user_a, user_b]

        # Nutrition records for both users
        self.mock_nutrition_col.docs = [
            {
                "user_email": "alice@saman.app",
                "date": vn_today,
                "meal_type": "lunch",
                "total_calories": 450,
                "total_protein": 30.0,
                "total_carbs": 50.0,
                "total_fat": 12.0,
            },
            {
                "user_email": "bob@saman.app",
                "date": vn_today,
                "meal_type": "lunch",
                "total_calories": 1800,
                "total_protein": 140.0,
                "total_carbs": 210.0,
                "total_fat": 45.0,
            },
        ]

        # Workout records for Bob only
        self.mock_workout_col.docs = [
            {
                "email": "bob@saman.app",
                "user_id": "user_b_id",
                "date": vn_today,
                "duration_minutes": 80,
                "completed_exercises": [{"name": "Heavy Bench Press"}],
            }
        ]

        # Generate context for Alice (User A)
        ctx_a = build_health_context(
            user_a,
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
            users_col_ref=self.mock_users_col,
        )

        # Alice's data must be present
        self.assertIn("52.0 kg", ctx_a)
        self.assertIn("lose_weight", ctx_a)
        self.assertIn("1650 kcal", ctx_a)
        self.assertIn("450 kcal", ctx_a)
        self.assertIn("30.0g", ctx_a)

        # Bob's data must NOT be in Alice's context
        self.assertNotIn("bob@saman.app", ctx_a)
        self.assertNotIn("Bob Nguyen", ctx_a)
        self.assertNotIn("92.0 kg", ctx_a)
        self.assertNotIn("heavy_bulk", ctx_a)
        self.assertNotIn("3200", ctx_a)
        self.assertNotIn("1800", ctx_a)
        self.assertNotIn("Heavy Bench Press", ctx_a)
        self.assertNotIn("80 phút", ctx_a)
        self.assertIn("TẬP LUYỆN GẦN NHẤT: chưa có dữ liệu", ctx_a)

        # Generate context for Bob (User B)
        ctx_b = build_health_context(
            user_b,
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
            users_col_ref=self.mock_users_col,
        )

        # Bob's data must be present
        self.assertIn("92.0 kg", ctx_b)
        self.assertIn("heavy_bulk", ctx_b)
        self.assertIn("3200 kcal", ctx_b)
        self.assertIn("1800 kcal", ctx_b)
        self.assertIn("Heavy Bench Press", ctx_b)
        self.assertIn("80 phút", ctx_b)

        # Alice's data must NOT be in Bob's context
        self.assertNotIn("alice@saman.app", ctx_b)
        self.assertNotIn("Alice Tran", ctx_b)
        self.assertNotIn("52.0 kg", ctx_b)
        self.assertNotIn("1650", ctx_b)
        self.assertNotIn("450 kcal", ctx_b)

        # Verify zero writes performed to health collections
        self.assertEqual(len(self.mock_nutrition_col.write_calls), 0)
        self.assertEqual(len(self.mock_workout_col.write_calls), 0)


if __name__ == "__main__":
    unittest.main()
