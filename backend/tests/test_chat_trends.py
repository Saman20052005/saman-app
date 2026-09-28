# [File: backend/tests/test_chat_trends.py]
"""
Checkpoint 3 — 7-Day Trends context injection tests.

Tests:
  TC-T1: User with nutrition spread across 5 of 7 days and 3 workouts
         → avg_cal, avg_pro, workout_count are computed correctly.
  TC-T2: Brand-new user (zero logs) → context shows "chưa có dữ liệu".
  TC-T3: Account isolation — User B's logs must NOT appear in User A's trends.
  TC-T4: Workouts only (no nutrition) → partial trend (workout count shown).
"""
import os
import sys
import asyncio
import unittest
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from unittest.mock import patch

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import backend.routers.chat as chat_module
from backend.routers.chat import (
    _build_trends_context,
    build_health_context,
    ChatRequest,
    chat_with_ai,
)

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


# ─────────────────────────────────────────────────────────────
# Minimal mock helpers
# ─────────────────────────────────────────────────────────────

class FakeCursor(list):
    def sort(self, *args, **kwargs):
        return self


class MockCol:
    """Read-only mock MongoDB collection. Raises on any write attempt."""

    def __init__(self, docs=None, allow_writes=False):
        self.docs = list(docs) if docs else []
        self.allow_writes = allow_writes
        self.write_calls = []

    def _matches(self, doc, query):
        if "$or" in query:
            if not any(
                all(doc.get(k) == v for k, v in branch.items())
                for branch in query["$or"]
            ):
                return False
        for k, v in query.items():
            if k == "$or":
                continue
            if doc.get(k) != v:
                return False
        return True

    def find(self, query=None):
        query = query or {}
        return FakeCursor([d for d in self.docs if self._matches(d, query)])

    def find_one(self, query=None):
        res = self.find(query)
        return res[0] if res else None

    def insert_one(self, *a, **kw):
        self.write_calls.append(("insert_one", a, kw))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed on read-only health collection")
        from unittest.mock import MagicMock
        from bson import ObjectId
        doc = a[0] if a else {}
        inserted_id = doc.get("_id") or ObjectId()
        doc_copy = dict(doc)
        doc_copy["_id"] = inserted_id
        self.docs.append(doc_copy)
        result = MagicMock()
        result.inserted_id = inserted_id
        return result

    def insert_many(self, *a, **kw):
        self.write_calls.append(("insert_many", a, kw))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed on read-only health collection")

    def update_one(self, *a, **kw):
        self.write_calls.append(("update_one", a, kw))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed on read-only health collection")
        from unittest.mock import MagicMock
        result = MagicMock()
        result.matched_count = 1
        return result

    def update_many(self, *a, **kw):
        self.write_calls.append(("update_many", a, kw))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed on read-only health collection")

    def delete_one(self, *a, **kw):
        self.write_calls.append(("delete_one", a, kw))
        raise RuntimeError("Write not allowed on read-only health collection")

    def delete_many(self, *a, **kw):
        self.write_calls.append(("delete_many", a, kw))
        raise RuntimeError("Write not allowed on read-only health collection")


# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

def _vn_date(days_ago=0):
    return (datetime.now(VN_TZ).date() - timedelta(days=days_ago)).strftime("%Y-%m-%d")


def _nutrition_doc(email, days_ago, cal, pro, carbs=0.0, fat=0.0):
    return {
        "user_email": email,
        "date": _vn_date(days_ago),
        "meal_type": "lunch",
        "total_calories": cal,
        "total_protein": pro,
        "total_carbs": carbs,
        "total_fat": fat,
    }


def _workout_doc(email, days_ago, duration=45):
    return {
        "email": email,
        "date": _vn_date(days_ago),
        "duration_minutes": duration,
        "completed_exercises": [{"name": "Squat"}],
    }


# ─────────────────────────────────────────────────────────────
# Test Suite
# ─────────────────────────────────────────────────────────────

class TestChatTrends(unittest.TestCase):

    def setUp(self):
        self.mock_users_col = MockCol(allow_writes=False)
        self.mock_nutrition_col = MockCol(allow_writes=False)
        self.mock_workout_col = MockCol(allow_writes=False)
        self.mock_conv_col = MockCol(allow_writes=True)

        chat_module.users_col = self.mock_users_col
        chat_module.nutrition_col = self.mock_nutrition_col
        chat_module.workout_history_col = self.mock_workout_col
        chat_module.conversations_col = self.mock_conv_col

    def tearDown(self):
        chat_module.users_col = None
        chat_module.nutrition_col = None
        chat_module.workout_history_col = None
        chat_module.conversations_col = None

    # TC-T1 ─────────────────────────────────────────────────────
    def test_tc_t1_correct_averages_and_workout_count(self):
        """5 nutrition days + 3 workouts → correct avg and count."""
        EMAIL = "athlete@saman.app"

        self.mock_nutrition_col.docs = [
            _nutrition_doc(EMAIL, 0, cal=1800, pro=120),
            _nutrition_doc(EMAIL, 1, cal=2000, pro=150),
            _nutrition_doc(EMAIL, 2, cal=1600, pro=100),
            _nutrition_doc(EMAIL, 3, cal=2200, pro=160),
            _nutrition_doc(EMAIL, 4, cal=1900, pro=130),
            # day 8 — outside 7-day window, MUST be excluded
            _nutrition_doc(EMAIL, 8, cal=9999, pro=999),
        ]
        self.mock_workout_col.docs = [
            _workout_doc(EMAIL, 0),
            _workout_doc(EMAIL, 2),
            _workout_doc(EMAIL, 5),
            # day 9 — outside 7-day window, MUST be excluded
            _workout_doc(EMAIL, 9),
        ]

        ctx = _build_trends_context(
            email=EMAIL,
            user_id="user_t1",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )

        self.assertIn("XU HƯỚNG 7 NGÀY QUA", ctx)
        # logged_days = 5
        self.assertIn("5/7", ctx)
        # avg_cal = 9500/5 = 1900
        self.assertIn("1900 kcal", ctx)
        # avg_pro = 660/5 = 132.0
        self.assertIn("132.0g", ctx)
        # 3 workouts in window
        self.assertIn("3 buổi", ctx)
        # no email in output
        self.assertNotIn(EMAIL, ctx)
        # zero writes
        self.assertEqual(self.mock_nutrition_col.write_calls, [])
        self.assertEqual(self.mock_workout_col.write_calls, [])

    # TC-T1b ────────────────────────────────────────────────────
    def test_tc_t1b_trends_injected_into_full_prompt(self):
        """Trend block must appear in the AI prompt via chat_with_ai."""
        EMAIL = "athlete2@saman.app"
        user = {
            "_id": "user_t1b",
            "email": EMAIL,
            "full_name": "Athlete VN",
            "weight": 70.0,
            "goal": "muscle_gain",
            "health_stats": {"tdee": 2500},
        }
        self.mock_users_col.docs = [user]
        self.mock_nutrition_col.docs = [
            _nutrition_doc(EMAIL, 0, cal=2000, pro=140),
            _nutrition_doc(EMAIL, 1, cal=1800, pro=120),
        ]
        self.mock_workout_col.docs = [_workout_doc(EMAIL, 0)]

        captured = []

        async def fake_reply(prompt):
            captured.append(prompt)
            return "OK"

        with patch("backend.routers.chat._generate_ai_reply", side_effect=fake_reply):
            req = ChatRequest(message="Tôi cần tư vấn gì tiếp theo?")
            res = asyncio.run(chat_with_ai(req, current_user=user))

        self.assertEqual(res["status"], "success")
        prompt = captured[0]
        self.assertIn("XU HƯỚNG 7 NGÀY QUA", prompt)
        # avg_cal = (2000+1800)/2 = 1900
        self.assertIn("1900 kcal", prompt)
        self.assertNotIn(EMAIL, prompt)

    # TC-T2 ─────────────────────────────────────────────────────
    def test_tc_t2_new_user_empty_data_shows_fallback(self):
        """Zero logs → 'chưa có dữ liệu' with no division-by-zero crash."""
        EMAIL = "newbie@saman.app"
        self.mock_nutrition_col.docs = []
        self.mock_workout_col.docs = []

        ctx = _build_trends_context(
            email=EMAIL,
            user_id="uid_new",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )

        self.assertIn("chưa có dữ liệu", ctx)
        self.assertNotIn("1900 kcal", ctx)
        self.assertEqual(self.mock_nutrition_col.write_calls, [])
        self.assertEqual(self.mock_workout_col.write_calls, [])

    # TC-T3 ─────────────────────────────────────────────────────
    def test_tc_t3_account_isolation(self):
        """User A must never see User B trends and vice versa."""
        EMAIL_A = "alice@saman.app"
        EMAIL_B = "bob@saman.app"

        self.mock_nutrition_col.docs = [
            _nutrition_doc(EMAIL_A, 0, cal=1500, pro=100),
            _nutrition_doc(EMAIL_A, 1, cal=1700, pro=110),
            _nutrition_doc(EMAIL_B, 0, cal=3500, pro=250),
            _nutrition_doc(EMAIL_B, 1, cal=3200, pro=220),
        ]
        self.mock_workout_col.docs = [
            _workout_doc(EMAIL_A, 0),
            _workout_doc(EMAIL_B, 0),
            _workout_doc(EMAIL_B, 1),
        ]

        ctx_a = _build_trends_context(
            email=EMAIL_A, user_id="uid_a",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )
        ctx_b = _build_trends_context(
            email=EMAIL_B, user_id="uid_b",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )

        # Alice: avg_cal = (1500+1700)/2 = 1600, 1 workout
        self.assertIn("1600 kcal", ctx_a)
        self.assertIn("1 buổi", ctx_a)

        # Bob: avg_cal = (3500+3200)/2 = 3350, 2 workouts
        self.assertIn("3350 kcal", ctx_b)
        self.assertIn("2 buổi", ctx_b)

        # Cross-contamination: Alice must NOT see Bob's data
        self.assertNotIn("3500", ctx_a)
        self.assertNotIn("3200", ctx_a)
        self.assertNotIn("3350", ctx_a)
        self.assertNotIn("2 buổi", ctx_a)

        # Cross-contamination: Bob must NOT see Alice's data
        self.assertNotIn("1500", ctx_b)
        self.assertNotIn("1700", ctx_b)
        self.assertNotIn("1600", ctx_b)
        self.assertNotIn("1 buổi", ctx_b)

        # No email leaks in either context
        for email in (EMAIL_A, EMAIL_B):
            self.assertNotIn(email, ctx_a)
            self.assertNotIn(email, ctx_b)

        self.assertEqual(self.mock_nutrition_col.write_calls, [])
        self.assertEqual(self.mock_workout_col.write_calls, [])

    # TC-T4 ─────────────────────────────────────────────────────
    def test_tc_t4_workouts_only_no_nutrition(self):
        """Workout-only user: count shown, nutrition avg says 'chưa có dữ liệu'."""
        EMAIL = "runner@saman.app"
        self.mock_nutrition_col.docs = []
        self.mock_workout_col.docs = [
            _workout_doc(EMAIL, 0),
            _workout_doc(EMAIL, 3),
            _workout_doc(EMAIL, 6),
        ]

        ctx = _build_trends_context(
            email=EMAIL,
            user_id="uid_runner",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )

        # Should NOT be the full no-data fallback
        self.assertNotEqual(ctx, "XU HƯỚNG 7 NGÀY QUA: chưa có dữ liệu")
        self.assertIn("3 buổi", ctx)
        # Nutrition averages not available
        self.assertIn("chưa có dữ liệu", ctx)
        self.assertEqual(self.mock_nutrition_col.write_calls, [])
        self.assertEqual(self.mock_workout_col.write_calls, [])


if __name__ == "__main__":
    unittest.main()
