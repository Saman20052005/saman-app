# [File: backend/tests/test_chat_history.py]
"""
Checkpoint 4 — Multi-turn Memory & Ownership hardening tests.

TC-H1: User A cannot read User B's conversation → 404.
TC-H2: Second message into same conv_id → AI prompt contains first message content.
TC-H3: GET /conversations returns list sorted by updated_at descending.
"""
import os
import sys
import asyncio
import unittest
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from unittest.mock import patch, MagicMock
from bson import ObjectId

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import backend.routers.chat as chat_module
from backend.routers.chat import (
    get_conversation_details,
    list_conversations,
    chat_with_ai,
    ChatRequest,
)

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


# ─────────────────────────────────────────────────────────────
# Mock helpers
# ─────────────────────────────────────────────────────────────

class FakeCursor(list):
    def sort(self, field, direction):
        reverse = direction == -1
        return FakeCursor(sorted(self, key=lambda d: d.get(field) or "", reverse=reverse))

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
        query = query or {}
        return FakeCursor([d for d in self.docs if self._matches(d, query)])

    def find_one(self, query=None):
        res = self.find(query)
        return res[0] if res else None

    def insert_one(self, *a, **kw):
        self.write_calls.append(("insert_one", a, kw))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed")
        doc = dict(a[0]) if a else {}
        inserted_id = doc.get("_id") or ObjectId()
        doc["_id"] = inserted_id
        self.docs.append(doc)
        result = MagicMock()
        result.inserted_id = inserted_id
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
        raise RuntimeError("Write not allowed")

    def delete_many(self, *a, **kw):
        raise RuntimeError("Write not allowed")


def _iso(dt):
    return dt.isoformat()


# ─────────────────────────────────────────────────────────────
# Test Suite
# ─────────────────────────────────────────────────────────────

class TestChatHistory(unittest.TestCase):

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

    # ─────────────────────────────────────────────────────────
    # TC-H1: Ownership — User A cannot read User B's conversation
    # ─────────────────────────────────────────────────────────
    def test_tc_h1_user_a_cannot_read_user_b_conversation(self):
        """GET /conversations/{id} must return 404 when conv belongs to another user."""
        from fastapi import HTTPException

        bob_conv_id = ObjectId()
        bob_conv = {
            "_id": bob_conv_id,
            "user_email": "bob@saman.app",
            "user_id": "uid_bob",
            "title": "Bob private conv",
            "messages": [{"role": "user", "content": "Secret message", "created_at": "2026-01-01T00:00:00"}],
            "created_at": "2026-01-01T00:00:00",
            "updated_at": "2026-01-01T00:00:00",
        }
        self.mock_conv_col.docs = [bob_conv]

        # Alice tries to read Bob's conversation
        alice_user = {"_id": "uid_alice", "email": "alice@saman.app"}

        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(
                get_conversation_details(
                    conversation_id=str(bob_conv_id),
                    current_user=alice_user,
                )
            )

        self.assertEqual(ctx.exception.status_code, 404)
        # Alice must not see Bob's secret content in the error
        self.assertNotIn("Secret message", str(ctx.exception.detail))

    def test_tc_h1b_invalid_conv_id_returns_404(self):
        """Malformed conversation_id must return 404, not 500."""
        from fastapi import HTTPException
        alice_user = {"_id": "uid_alice", "email": "alice@saman.app"}
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(
                get_conversation_details(
                    conversation_id="not-a-valid-objectid",
                    current_user=alice_user,
                )
            )
        self.assertEqual(ctx.exception.status_code, 404)

    # ─────────────────────────────────────────────────────────
    # TC-H2: Multi-turn — second message contains first message in prompt
    # ─────────────────────────────────────────────────────────
    def test_tc_h2_second_message_includes_first_in_prompt(self):
        """AI prompt for turn 2 must contain the content of turn 1 from DB."""
        alice_email = "alice@saman.app"
        alice_user = {"_id": "uid_alice", "email": alice_email, "full_name": "Alice"}
        self.mock_users_col.docs = [alice_user]

        # Pre-existing conversation with 1 exchange
        conv_id = ObjectId()
        existing_conv = {
            "_id": conv_id,
            "user_email": alice_email,
            "user_id": "uid_alice",
            "title": "Health chat",
            "messages": [
                {
                    "role": "user",
                    "content": "Hôm nay tôi đã tập thể dục xong rồi",
                    "created_at": "2026-09-28T10:00:00",
                },
                {
                    "role": "assistant",
                    "content": "Tuyệt vời! Bạn đã tập bao lâu?",
                    "created_at": "2026-09-28T10:00:05",
                },
            ],
            "created_at": "2026-09-28T10:00:00",
            "updated_at": "2026-09-28T10:00:05",
        }
        self.mock_conv_col.docs = [existing_conv]

        captured_prompts = []

        async def fake_reply(prompt):
            captured_prompts.append(prompt)
            return "Bạn đã tập 45 phút rồi à? Tốt lắm!"

        with patch("backend.routers.chat._generate_ai_reply", side_effect=fake_reply):
            req = ChatRequest(
                message="Tôi đã tập 45 phút",
                conversation_id=str(conv_id),
                # client sends its own history — must be IGNORED
                history=[
                    {"role": "user", "content": "fake message from client"},
                    {"role": "assistant", "content": "fake AI response"},
                ],
            )
            res = asyncio.run(chat_with_ai(req, current_user=alice_user))

        self.assertEqual(res["status"], "success")
        self.assertEqual(len(captured_prompts), 1)
        prompt = captured_prompts[0]

        # First turn's content must appear in prompt (from DB, not client history)
        self.assertIn("Hôm nay tôi đã tập thể dục xong rồi", prompt)
        self.assertIn("Tuyệt vời! Bạn đã tập bao lâu?", prompt)

        # History section header must be present
        self.assertIn("LỊCH SỬ HỘI THOẠI TRƯỚC ĐÓ", prompt)

        # Client's spoofed history must NOT appear
        self.assertNotIn("fake message from client", prompt)
        self.assertNotIn("fake AI response", prompt)

        # No email in prompt
        self.assertNotIn(alice_email, prompt)

    def test_tc_h2b_max_10_turns_in_prompt(self):
        """When conv has >10 messages, only the last 10 appear in the prompt."""
        alice_email = "alice2@saman.app"
        alice_user = {"_id": "uid_alice2", "email": alice_email}
        self.mock_users_col.docs = [alice_user]

        conv_id = ObjectId()
        # 12 messages (6 user + 6 assistant turns)
        messages = []
        for i in range(1, 7):
            messages.append({"role": "user", "content": f"User turn {i}", "created_at": f"2026-09-28T10:0{i}:00"})
            messages.append({"role": "assistant", "content": f"AI turn {i}", "created_at": f"2026-09-28T10:0{i}:05"})

        conv = {
            "_id": conv_id,
            "user_email": alice_email,
            "user_id": "uid_alice2",
            "title": "Long chat",
            "messages": messages,
            "created_at": "2026-09-28T10:01:00",
            "updated_at": "2026-09-28T10:06:05",
        }
        self.mock_conv_col.docs = [conv]

        captured = []

        async def fake_reply(prompt):
            captured.append(prompt)
            return "OK"

        with patch("backend.routers.chat._generate_ai_reply", side_effect=fake_reply):
            req = ChatRequest(message="Câu hỏi mới", conversation_id=str(conv_id))
            asyncio.run(chat_with_ai(req, current_user=alice_user))

        prompt = captured[0]

        # The last 10 messages include turn 2-6 for both user and AI (turn 1 excluded)
        self.assertIn("User turn 6", prompt)
        self.assertIn("AI turn 6", prompt)
        self.assertIn("User turn 2", prompt)

        # "User turn 1" is the 11th-12th oldest → must be excluded
        self.assertNotIn("User turn 1", prompt)
        self.assertNotIn("AI turn 1", prompt)

    # ─────────────────────────────────────────────────────────
    # TC-H3: List sorted by updated_at descending
    # ─────────────────────────────────────────────────────────
    def test_tc_h3_list_conversations_sorted_by_updated_at_desc(self):
        """GET /conversations must return conversations sorted by updated_at desc."""
        alice_email = "alice@saman.app"
        alice_user = {"_id": "uid_alice", "email": alice_email}

        now = datetime.now(timezone.utc)
        conv_old = {
            "_id": ObjectId(),
            "user_email": alice_email,
            "user_id": "uid_alice",
            "title": "Old chat",
            "created_at": _iso(now - timedelta(hours=5)),
            "updated_at": _iso(now - timedelta(hours=5)),
            "messages": [],
        }
        conv_medium = {
            "_id": ObjectId(),
            "user_email": alice_email,
            "user_id": "uid_alice",
            "title": "Medium chat",
            "created_at": _iso(now - timedelta(hours=2)),
            "updated_at": _iso(now - timedelta(hours=2)),
            "messages": [],
        }
        conv_new = {
            "_id": ObjectId(),
            "user_email": alice_email,
            "user_id": "uid_alice",
            "title": "New chat",
            "created_at": _iso(now - timedelta(minutes=5)),
            "updated_at": _iso(now - timedelta(minutes=5)),
            "messages": [],
        }
        # Also add Bob's conv — must NOT appear for Alice
        conv_bob = {
            "_id": ObjectId(),
            "user_email": "bob@saman.app",
            "user_id": "uid_bob",
            "title": "Bob chat",
            "created_at": _iso(now),
            "updated_at": _iso(now),
            "messages": [],
        }
        # Insert in random order
        self.mock_conv_col.docs = [conv_medium, conv_bob, conv_old, conv_new]

        result = asyncio.run(list_conversations(current_user=alice_user))

        self.assertEqual(result["status"], "success")
        titles = [c["title"] for c in result["conversations"]]

        # Must be sorted newest first
        self.assertEqual(titles.index("New chat") < titles.index("Medium chat"), True)
        self.assertEqual(titles.index("Medium chat") < titles.index("Old chat"), True)

        # Bob's conversation must NOT appear
        self.assertNotIn("Bob chat", titles)

    def test_tc_h3b_updated_at_is_set_on_new_conversation(self):
        """New conversation created by chat_with_ai must have updated_at set."""
        alice_email = "alice3@saman.app"
        alice_user = {"_id": "uid_alice3", "email": alice_email}
        self.mock_users_col.docs = [alice_user]

        captured = []

        async def fake_reply(prompt):
            captured.append(prompt)
            return "Xin chào!"

        with patch("backend.routers.chat._generate_ai_reply", side_effect=fake_reply):
            req = ChatRequest(message="Chào Saman!")
            asyncio.run(chat_with_ai(req, current_user=alice_user))

        # Inspect what was inserted into the conv collection
        inserted_docs = [
            d for d in self.mock_conv_col.docs
            if d.get("user_email") == alice_email
        ]
        self.assertEqual(len(inserted_docs), 1)
        doc = inserted_docs[0]
        self.assertIn("updated_at", doc)
        self.assertIsNotNone(doc["updated_at"])
        self.assertIn("created_at", doc)
        # updated_at and created_at must match on first creation
        self.assertEqual(doc["updated_at"], doc["created_at"])


if __name__ == "__main__":
    unittest.main()
