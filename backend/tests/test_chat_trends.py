# [File: backend/tests/test_chat_trends.py]
"""
Checkpoint 3 — 7-Day Trends context injection tests.

Tests:
  TC-T1: User with nutrition spread across 5 of 7 days and 3 workouts
         → avg_cal, avg_pro, workout_count are computed correctly.
  TC-T1b: Trend block injected into full AI prompt.
  TC-T2: Brand-new user (zero logs) → context shows "chưa có dữ liệu".
  TC-T3: Account isolation — User B's logs must NOT appear in User A's trends.
  TC-T4: Workouts only (no nutrition) → partial trend (workout count shown).
  TC-T5: Compare displayed numbers with source logs and multiple meals/day.
  TC-T6: Sparse data states too few logs to conclude (<3 days logged).
  TC-T7: Vietnam day boundary workout timestamps normalization.
  TC-T8: Avoid counting the same workout session twice (deduplication).
  TC-T9: Two users isolation and distinct today vs trend contexts.
"""
import os
import sys
import asyncio
import unittest
from datetime import datetime, timedelta, timezone, date
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
        self.mock_water_col = MockCol(allow_writes=False)
        self.mock_conv_col = MockCol(allow_writes=True)

        chat_module.users_col = self.mock_users_col
        chat_module.nutrition_col = self.mock_nutrition_col
        chat_module.workout_history_col = self.mock_workout_col
        chat_module.water_col = self.mock_water_col
        chat_module.conversations_col = self.mock_conv_col

    def tearDown(self):
        chat_module.users_col = None
        chat_module.nutrition_col = None
        chat_module.workout_history_col = None
        chat_module.water_col = None
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

    # TC-T5 ─────────────────────────────────────────────────────
    def test_tc_t5_compare_displayed_numbers_with_source_logs_and_multiple_meals(self):
        """Displayed 7-day metrics match exact source log calculations across multiple meals/day."""
        EMAIL = "athlete5@saman.app"
        # User logs:
        # Day 0: 2 meals -> (650 kcal, 45.0g pro) + (850 kcal, 55.0g pro) = 1500 kcal, 100.0g pro
        # Day 1: 1 meal with foods list -> 400 + 500 = 900 kcal, 30.0 + 35.0 = 65.0g pro
        # Day 3: 1 meal -> 1700 kcal, 110.0g pro
        # Day 4: 1 meal -> 2300 kcal, 145.0g pro
        # Total cals across 4 days = 1500 + 900 + 1700 + 2300 = 6400 kcal
        # Total pro across 4 days = 100.0 + 65.0 + 110.0 + 145.0 = 420.0g
        # Expected avg_cal = 6400 / 4 = 1600 kcal
        # Expected avg_pro = 420.0 / 4 = 105.0g
        # 2 workouts on Day 0 and Day 3
        self.mock_nutrition_col.docs = [
            {
                "user_email": EMAIL,
                "date": _vn_date(0),
                "meal_type": "lunch",
                "total_calories": 650,
                "total_protein": 45.0,
            },
            {
                "user_email": EMAIL,
                "date": _vn_date(0),
                "meal_type": "dinner",
                "total_calories": 850,
                "total_protein": 55.0,
            },
            {
                "user_email": EMAIL,
                "date": _vn_date(1),
                "meal_type": "lunch",
                "foods": [
                    {"name": "Rice", "calories": 400, "protein": 30.0},
                    {"name": "Chicken", "calories": 500, "protein": 35.0},
                ],
            },
            {
                "user_email": EMAIL,
                "date": _vn_date(3),
                "meal_type": "lunch",
                "total_calories": 1700,
                "total_protein": 110.0,
            },
            {
                "user_email": EMAIL,
                "date": _vn_date(4),
                "meal_type": "dinner",
                "total_calories": 2300,
                "total_protein": 145.0,
            },
        ]
        self.mock_workout_col.docs = [
            {
                "email": EMAIL,
                "start_time": _vn_date(0) + "T09:00:00+07:00",
                "duration_minutes": 45,
                "completed_exercises": [{"name": "Bench Press"}],
            },
            {
                "email": EMAIL,
                "start_time": _vn_date(3) + "T18:00:00+07:00",
                "duration_minutes": 60,
                "completed_exercises": [{"name": "Deadlift"}],
            },
        ]

        ctx = _build_trends_context(
            email=EMAIL,
            user_id="uid_t5",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )

        self.assertIn("XU HƯỚNG 7 NGÀY QUA", ctx)
        self.assertIn("4/7", ctx)
        self.assertIn("1600 kcal", ctx)
        self.assertIn("105.0g", ctx)
        self.assertIn("2 buổi", ctx)
        self.assertIn("Đủ dữ liệu theo dõi xu hướng (4/7 ngày)", ctx)
        self.assertNotIn(EMAIL, ctx)
        self.assertEqual(self.mock_nutrition_col.write_calls, [])
        self.assertEqual(self.mock_workout_col.write_calls, [])

    # TC-T6 ─────────────────────────────────────────────────────
    def test_tc_t6_sparse_data_states_too_few_logs_to_conclude(self):
        """Sparse data (<3 days logged) states when there are too few logs to conclude."""
        EMAIL = "sparse@saman.app"

        # Case A: 1 logged day
        self.mock_nutrition_col.docs = [
            _nutrition_doc(EMAIL, 1, cal=1800, pro=120),
        ]
        self.mock_workout_col.docs = [_workout_doc(EMAIL, 1)]

        ctx1 = _build_trends_context(
            email=EMAIL,
            user_id="uid_sparse1",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )
        self.assertIn("1/7", ctx1)
        self.assertIn("1800 kcal", ctx1)
        self.assertIn("120.0g", ctx1)
        self.assertIn("1 buổi", ctx1)
        self.assertIn("Dữ liệu còn ít (1/7 ngày), chưa đủ để kết luận xu hướng", ctx1)

        # Case B: 2 logged days
        self.mock_nutrition_col.docs = [
            _nutrition_doc(EMAIL, 0, cal=1600, pro=100),
            _nutrition_doc(EMAIL, 2, cal=2000, pro=140),
        ]
        ctx2 = _build_trends_context(
            email=EMAIL,
            user_id="uid_sparse2",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )
        self.assertIn("2/7", ctx2)
        self.assertIn("1800 kcal", ctx2)
        self.assertIn("120.0g", ctx2)
        self.assertIn("Dữ liệu còn ít (2/7 ngày), chưa đủ để kết luận xu hướng", ctx2)

        # Case C: 0 nutrition logs + 1 workout
        self.mock_nutrition_col.docs = []
        self.mock_workout_col.docs = [_workout_doc(EMAIL, 0)]
        ctx3 = _build_trends_context(
            email=EMAIL,
            user_id="uid_sparse3",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )
        self.assertIn("0/7", ctx3)
        self.assertIn("1 buổi", ctx3)
        self.assertIn("chưa có dữ liệu", ctx3)
        self.assertIn("Chưa có dữ liệu dinh dưỡng trong 7 ngày qua, chưa đủ để kết luận xu hướng", ctx3)

        self.assertEqual(self.mock_nutrition_col.write_calls, [])
        self.assertEqual(self.mock_workout_col.write_calls, [])

    # TC-T7 ─────────────────────────────────────────────────────
    def test_tc_t7_vietnam_day_boundary_workout_timestamps(self):
        """Workout timestamps normalized with Asia/Ho_Chi_Minh across midnight and 7-day window boundary."""
        EMAIL = "tzathlete@saman.app"
        today_vn = datetime.now(VN_TZ).date()

        # Midnight start of today in VN timezone (00:00:00 VN)
        dt_today_start = datetime(today_vn.year, today_vn.month, today_vn.day, 0, 0, 0, tzinfo=VN_TZ)
        # 1 sec before midnight VN is 23:59:59 yesterday VN (16:59:59 UTC)
        dt_yesterday_late = dt_today_start - timedelta(seconds=1)
        # 1 sec after midnight VN is 00:00:01 today VN (17:00:01 UTC)
        dt_today_early = dt_today_start + timedelta(seconds=1)

        # 7-day window earliest day is 6 days ago (since window has 7 days: 0..6)
        day_oldest = today_vn - timedelta(days=6)
        dt_window_start = datetime(day_oldest.year, day_oldest.month, day_oldest.day, 0, 0, 0, tzinfo=VN_TZ)
        # 1 sec before window start: 23:59:59 on 7 days ago -> OUTSIDE window!
        dt_outside_window = dt_window_start - timedelta(seconds=1)
        # 1 sec after window start -> INSIDE window!
        dt_inside_oldest = dt_window_start + timedelta(seconds=1)

        self.mock_nutrition_col.docs = [_nutrition_doc(EMAIL, 0, cal=2000, pro=130)]
        self.mock_workout_col.docs = [
            # 1. Inside oldest boundary (valid day 6 ago)
            {"email": EMAIL, "start_time": dt_inside_oldest.astimezone(timezone.utc).isoformat()},
            # 2. Outside window (7 days ago in VN) -> MUST be excluded
            {"email": EMAIL, "start_time": dt_outside_window.astimezone(timezone.utc).isoformat()},
            # 3. Yesterday 23:59:59 VN -> INSIDE window (day 1 ago)
            {"email": EMAIL, "start_time": dt_yesterday_late.astimezone(timezone.utc).isoformat()},
            # 4. Today 00:00:01 VN -> INSIDE window (day 0)
            {"email": EMAIL, "start_time": dt_today_early.astimezone(timezone.utc).isoformat()},
        ]

        ctx = _build_trends_context(
            email=EMAIL,
            user_id="uid_tz",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )

        # Out of 4 sessions, exactly 3 fall inside the 7-day Vietnam window
        self.assertIn("3 buổi", ctx)
        self.assertEqual(self.mock_nutrition_col.write_calls, [])
        self.assertEqual(self.mock_workout_col.write_calls, [])

    # TC-T8 ─────────────────────────────────────────────────────
    def test_tc_t8_avoid_counting_same_workout_session_twice(self):
        """Workout sessions with both start_time and date or duplicated _ids are counted exactly once."""
        EMAIL = "dedup@saman.app"
        today_vn = datetime.now(VN_TZ).date()
        dt_today = datetime(today_vn.year, today_vn.month, today_vn.day, 8, 0, 0, tzinfo=VN_TZ)

        self.mock_nutrition_col.docs = [_nutrition_doc(EMAIL, 0, cal=1900, pro=120)]
        self.mock_workout_col.docs = [
            # Session A: Has BOTH start_time and date -> MUST NOT be counted twice
            {
                "_id": "sess_both_fields",
                "email": EMAIL,
                "start_time": dt_today.astimezone(timezone.utc).isoformat(),
                "date": today_vn.strftime("%Y-%m-%d"),
                "duration_minutes": 45,
            },
            # Session B: Duplicated document in collection (same _id) -> MUST NOT be counted twice
            {
                "_id": "sess_duplicate_id",
                "email": EMAIL,
                "date": today_vn.strftime("%Y-%m-%d"),
                "duration_minutes": 30,
            },
            {
                "_id": "sess_duplicate_id",
                "email": EMAIL,
                "date": today_vn.strftime("%Y-%m-%d"),
                "duration_minutes": 30,
            },
            # Session C & D: Two distinct sessions on the same day -> BOTH must be counted
            {
                "_id": "sess_morning",
                "email": EMAIL,
                "start_time": (dt_today + timedelta(hours=1)).astimezone(timezone.utc).isoformat(),
                "duration_minutes": 25,
            },
            {
                "_id": "sess_evening",
                "email": EMAIL,
                "start_time": (dt_today + timedelta(hours=10)).astimezone(timezone.utc).isoformat(),
                "duration_minutes": 50,
            },
        ]

        ctx = _build_trends_context(
            email=EMAIL,
            user_id="uid_dedup",
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
        )

        # Expected: 1 (Session A) + 1 (Session B) + 2 (Sessions C and D) = 4 sessions total
        self.assertIn("4 buổi", ctx)
        self.assertEqual(self.mock_workout_col.write_calls, [])

    # TC-T9 ─────────────────────────────────────────────────────
    def test_tc_t9_two_users_isolation_and_distinct_today_vs_trend(self):
        """User A and User B health contexts isolate data and distinguish today's values from 7-day trends."""
        EMAIL_A = "usera_full@saman.app"
        EMAIL_B = "userb_sparse@saman.app"

        user_a = {
            "_id": "uid_user_a",
            "email": EMAIL_A,
            "full_name": "User Alpha",
            "weight": 75.0,
            "goal": "muscle_gain",
            "health_stats": {"tdee": 2600},
        }
        user_b = {
            "_id": "uid_user_b",
            "email": EMAIL_B,
            "full_name": "User Beta",
            "weight": 60.0,
            "goal": "weight_loss",
            "health_stats": {"tdee": 1800},
        }

        # User A: 4 days of logs (Day 0: 2 meals totaling 1600 kcal, 110g pro; Days 1, 2, 3: 2000 cal, 130g pro)
        # 7-day avg cal = (1600 + 2000*3) / 4 = 7600 / 4 = 1900 kcal
        # User A workouts: 3 sessions
        # User B: 1 day of log (Day 2: 3000 kcal, 220g pro); today has no meals; 0 workouts
        self.mock_users_col.docs = [user_a, user_b]
        self.mock_nutrition_col.docs = [
            _nutrition_doc(EMAIL_A, 0, cal=700, pro=50),
            _nutrition_doc(EMAIL_A, 0, cal=900, pro=60),
            _nutrition_doc(EMAIL_A, 1, cal=2000, pro=130),
            _nutrition_doc(EMAIL_A, 2, cal=2000, pro=130),
            _nutrition_doc(EMAIL_A, 3, cal=2000, pro=130),
            _nutrition_doc(EMAIL_B, 2, cal=3000, pro=220),
        ]
        self.mock_workout_col.docs = [
            _workout_doc(EMAIL_A, 0),
            _workout_doc(EMAIL_A, 2),
            _workout_doc(EMAIL_A, 4),
        ]

        ctx_a = build_health_context(
            user_a,
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
            users_col_ref=self.mock_users_col,
            water_col_ref=self.mock_water_col,
        )
        ctx_b = build_health_context(
            user_b,
            nutrition_col_ref=self.mock_nutrition_col,
            workout_col_ref=self.mock_workout_col,
            users_col_ref=self.mock_users_col,
            water_col_ref=self.mock_water_col,
        )

        # User A: Today vs Trend distinction
        self.assertIn("DINH DƯỠNG HÔM NAY", ctx_a)
        self.assertIn("1600 kcal", ctx_a)  # Today's calories
        self.assertIn("110.0g", ctx_a)     # Today's protein
        self.assertIn("XU HƯỚNG 7 NGÀY QUA", ctx_a)
        self.assertIn("4/7", ctx_a)        # Trend logged days
        self.assertIn("1900 kcal", ctx_a)  # Trend avg calories
        self.assertIn("3 buổi", ctx_a)
        self.assertIn("Đủ dữ liệu theo dõi xu hướng (4/7 ngày)", ctx_a)

        # User A must NOT contain User B data
        self.assertNotIn("3000", ctx_a)
        self.assertNotIn("220", ctx_a)
        self.assertNotIn(EMAIL_B, ctx_a)
        self.assertNotIn(EMAIL_A, ctx_a)

        # User B: Today vs Trend distinction
        self.assertIn("DINH DƯỠNG HÔM NAY", ctx_b)
        self.assertIn("chưa ghi nhận bữa ăn nào", ctx_b)
        self.assertIn("XU HƯỚNG 7 NGÀY QUA", ctx_b)
        self.assertIn("1/7", ctx_b)
        self.assertIn("3000 kcal", ctx_b)
        self.assertIn("0 buổi", ctx_b)
        self.assertIn("Dữ liệu còn ít (1/7 ngày), chưa đủ để kết luận xu hướng", ctx_b)

        # User B must NOT contain User A data
        self.assertNotIn("1600", ctx_b)
        self.assertNotIn("1900", ctx_b)
        self.assertNotIn("3 buổi", ctx_b)
        self.assertNotIn(EMAIL_A, ctx_b)
        self.assertNotIn(EMAIL_B, ctx_b)

        # Strict read-only verification
        self.assertEqual(self.mock_nutrition_col.write_calls, [])
        self.assertEqual(self.mock_workout_col.write_calls, [])
        self.assertEqual(self.mock_users_col.write_calls, [])


if __name__ == "__main__":
    unittest.main()
