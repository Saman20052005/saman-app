# [File: backend/tests/test_chat_coaching.py]
"""
Checkpoint 5 — Proactive Coaching system instruction tests.

TC-C1: Prompt sent to AI must contain the 4-step coaching instruction.
TC-C2: User with severe protein deficit today → prompt contains deficit data
       that would guide AI to suggest high-protein food.
TC-C3: Medical guardrail — coaching instruction must forbid diagnosis/prescription.
TC-C4: "chưa có dữ liệu" fallback instruction is present in prompt.
TC-C5: Coaching instruction appears even in a multi-turn conversation.
"""
import os
import sys
import asyncio
import unittest
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
from unittest.mock import patch, MagicMock
from bson import ObjectId

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import backend.routers.chat as chat_module
from backend.routers.chat import chat_with_ai, ChatRequest

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


# ─────────────────────────────────────────────────────────────
# Shared mock helpers
# ─────────────────────────────────────────────────────────────

class FakeCursor(list):
    def sort(self, *a, **kw):
        return self

    def limit(self, n):
        return FakeCursor(self[:n])


class MockCol:
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
            if isinstance(v, ObjectId):
                if doc.get(k) != v:
                    return False
            elif doc.get(k) != v:
                return False
        return True

    def find(self, query=None):
        return FakeCursor([d for d in self.docs if self._matches(d, query or {})])

    def find_one(self, query=None):
        res = self.find(query)
        return res[0] if res else None

    def insert_one(self, *a, **kw):
        self.write_calls.append(("insert_one", a, kw))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed")
        doc = dict(a[0]) if a else {}
        doc.setdefault("_id", ObjectId())
        self.docs.append(doc)
        result = MagicMock()
        result.inserted_id = doc["_id"]
        return result

    def update_one(self, *a, **kw):
        self.write_calls.append(("update_one", a, kw))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed")
        result = MagicMock()
        result.matched_count = 1
        return result

    def update_many(self, *a, **kw):
        self.write_calls.append(("update_many", a, kw))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed")

    def insert_many(self, *a, **kw):
        self.write_calls.append(("insert_many", a, kw))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed")

    def delete_one(self, *a, **kw):
        raise RuntimeError("Write not allowed on health collection")

    def delete_many(self, *a, **kw):
        raise RuntimeError("Write not allowed on health collection")


def _vn_today():
    return datetime.now(VN_TZ).strftime("%Y-%m-%d")


# ─────────────────────────────────────────────────────────────
# Test Suite
# ─────────────────────────────────────────────────────────────

class TestChatCoaching(unittest.TestCase):

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

    def _run_chat(self, user, message, conv_id=None):
        """Helper: run chat_with_ai and return (result, captured_prompt)."""
        captured = []

        async def fake_reply(prompt):
            captured.append(prompt)
            return "Gợi ý của Saman Coach."

        with patch("backend.routers.chat._generate_ai_reply", side_effect=fake_reply):
            req = ChatRequest(message=message, conversation_id=conv_id)
            result = asyncio.run(chat_with_ai(req, current_user=user))
        return result, captured[0] if captured else ""

    # ─────────────────────────────────────────────────────────
    # TC-C1: System instruction sections present in every prompt
    # ─────────────────────────────────────────────────────────
    def test_tc_c1_coaching_instruction_in_prompt(self):
        """The 4-step coaching instruction must appear in the AI prompt."""
        user = {"_id": "uid_c1", "email": "coach_user@saman.app"}
        self.mock_users_col.docs = [user]

        _, prompt = self._run_chat(user, "Tôi nên làm gì hôm nay?")

        # Must contain coaching framework markers
        self.assertIn("Saman Coach", prompt)
        self.assertIn("NEXT STEP", prompt)
        self.assertIn("LÝ DO", prompt)
        self.assertIn("PHẢN HỒI", prompt)
        self.assertIn("TRẢ LỜI:", prompt)

    # ─────────────────────────────────────────────────────────
    # TC-C2: Protein-deficit user → deficit numbers in prompt
    # ─────────────────────────────────────────────────────────
    def test_tc_c2_protein_deficit_data_in_prompt(self):
        """When user has severe protein deficit today, prompt must contain exact protein numbers."""
        EMAIL = "deficit_user@saman.app"
        user = {
            "_id": "uid_c2",
            "email": EMAIL,
            "full_name": "Deficit User",
            "weight": 70.0,
            "goal": "muscle_gain",
            "health_stats": {"tdee": 2500},
        }
        self.mock_users_col.docs = [user]

        today = _vn_today()
        # Only 25g protein today out of goal → severe deficit
        self.mock_nutrition_col.docs = [
            {
                "user_email": EMAIL,
                "date": today,
                "meal_type": "breakfast",
                "total_calories": 400,
                "total_protein": 25.0,
                "total_carbs": 60.0,
                "total_fat": 10.0,
            }
        ]
        self.mock_workout_col.docs = []

        _, prompt = self._run_chat(user, "Tôi nên ăn gì bây giờ?")

        # Prompt must contain the protein number logged today so AI can reason
        self.assertIn("25.0g", prompt)
        self.assertIn("muscle_gain", prompt)

        # The coaching instruction to explain reasoning must be present
        self.assertIn("LÝ DO", prompt)
        self.assertIn("NEXT STEP", prompt)

        # No email leak
        self.assertNotIn(EMAIL, prompt)

    # ─────────────────────────────────────────────────────────
    # TC-C3: Medical guardrail in system instruction
    # ─────────────────────────────────────────────────────────
    def test_tc_c3_medical_guardrail_in_instruction(self):
        """Coaching instruction must contain the medical boundary guardrail."""
        user = {"_id": "uid_c3", "email": "guardrail_user@saman.app"}
        self.mock_users_col.docs = [user]

        _, prompt = self._run_chat(user, "Tôi bị đau dạ dày nên ăn thuốc gì?")

        # The medical no-diagnosis rule must be embedded in the instruction
        self.assertIn("Không chẩn đoán y khoa", prompt)
        self.assertIn("không kê đơn", prompt)

    # ─────────────────────────────────────────────────────────
    # TC-C4: Missing-data fallback instruction in prompt
    # ─────────────────────────────────────────────────────────
    def test_tc_c4_missing_data_fallback_instruction_present(self):
        """Coaching instruction must tell AI to say 'chưa có dữ liệu' not hallucinate."""
        user = {"_id": "uid_c4", "email": "nodata_user@saman.app"}
        self.mock_users_col.docs = [user]
        self.mock_nutrition_col.docs = []
        self.mock_workout_col.docs = []

        _, prompt = self._run_chat(user, "Xu hướng tuần này của tôi thế nào?")

        self.assertIn("chưa có dữ liệu", prompt)

    # ─────────────────────────────────────────────────────────
    # TC-C5: Coaching instruction present even in multi-turn conv
    # ─────────────────────────────────────────────────────────
    def test_tc_c5_coaching_instruction_present_in_multiturn(self):
        """Coaching instruction must appear even when a prior conversation exists."""
        EMAIL = "multiturn_user@saman.app"
        user = {"_id": "uid_c5", "email": EMAIL}
        self.mock_users_col.docs = [user]

        conv_id = ObjectId()
        existing_conv = {
            "_id": conv_id,
            "user_email": EMAIL,
            "user_id": "uid_c5",
            "title": "Prior chat",
            "messages": [
                {"role": "user", "content": "Chào Saman", "created_at": "2026-09-28T10:00:00"},
                {"role": "assistant", "content": "Chào bạn!", "created_at": "2026-09-28T10:00:05"},
            ],
            "created_at": "2026-09-28T10:00:00",
            "updated_at": "2026-09-28T10:00:05",
        }
        self.mock_conv_col.docs = [existing_conv]

        _, prompt = self._run_chat(
            user,
            "Tôi nên tập gì tiếp theo?",
            conv_id=str(conv_id),
        )

        # Prior history in prompt
        self.assertIn("LỊCH SỬ HỘI THOẠI TRƯỚC ĐÓ", prompt)
        self.assertIn("Chào Saman", prompt)

        # Coaching instruction still present after history section
        self.assertIn("Saman Coach", prompt)
        self.assertIn("NEXT STEP", prompt)
        self.assertIn("LÝ DO", prompt)
        self.assertIn("PHẢN HỒI", prompt)


if __name__ == "__main__":
    unittest.main()
