# [File: backend/tests/test_chat_actions_final.py]
"""
Checkpoint 6 — Confirmed Actions (Log Water) tests.

TC-A1: Water-intent message → response has 'action' with status='pending' and unique ID.
TC-A2: confirm → water_col gets new entry; conversation status = 'confirmed'.
TC-A3: confirm twice same action_id → water amount NOT incremented again (idempotency).
TC-A4: cancel → status='cancelled', water_col unchanged.
"""
import os
import sys
import asyncio
import unittest
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from unittest.mock import MagicMock
from bson import ObjectId

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import backend.routers.chat as chat_module
from backend.routers.chat import (
    chat_with_ai,
    confirm_action,
    cancel_action,
    ChatRequest,
    ActionDecisionRequest,
)

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


# ─────────────────────────────────────────────────────────────
# Mock helpers
# ─────────────────────────────────────────────────────────────

class FakeCursor(list):
    def sort(self, *a, **kw):
        return self
    def limit(self, n):
        return FakeCursor(self[:n])


class MockCol:
    """Full read+write mock supporting the subset of operators used by the router."""

    def __init__(self, docs=None, allow_writes=True):
        self.docs = list(docs) if docs else []
        self.allow_writes = allow_writes
        self.write_calls = []

    # ── helpers ───────────────────────────────────────────────

    def _matches(self, doc, query):
        """Minimal $or / exact-match filter — handles ObjectId comparison and list membership."""
        if "$or" in query:
            branches = query["$or"]
            if not any(self._all_match(doc, b) for b in branches):
                return False
        for k, v in query.items():
            if k == "$or":
                continue
            if k.startswith("$"):
                continue
            # nested field (dot-notation)
            if "." in k:
                parts = k.split(".", 1)
                sub = doc.get(parts[0])
                if not isinstance(sub, dict) or sub.get(parts[1]) != v:
                    return False
                continue
            dv = doc.get(k)
            if isinstance(v, dict):
                # handle {"$ne": x}
                if "$ne" in v:
                    # $ne on a list: True if v["$ne"] not in the list
                    if isinstance(dv, list):
                        if v["$ne"] in dv:
                            return False
                    elif dv == v["$ne"]:
                        return False
                # skip other unknown operators
                continue
            # Support list membership: if doc field is a list, check if v is in it
            if isinstance(dv, list):
                if v not in dv:
                    return False
                continue
            if isinstance(v, ObjectId) and isinstance(dv, ObjectId):
                if dv != v:
                    return False
            elif dv != v:
                return False
        return True

    def _all_match(self, doc, branch):
        return all(doc.get(k) == v for k, v in branch.items())

    # ── read ops ──────────────────────────────────────────────

    def find(self, query=None):
        query = query or {}
        return FakeCursor([d for d in self.docs if self._matches(d, query)])

    def find_one(self, query=None):
        res = self.find(query)
        return dict(res[0]) if res else None

    # ── write ops ─────────────────────────────────────────────

    def insert_one(self, doc, *a, **kw):
        self.write_calls.append(("insert_one", dict(doc)))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed")
        d = dict(doc)
        d.setdefault("_id", ObjectId())
        self.docs.append(d)
        result = MagicMock()
        result.inserted_id = d["_id"]
        return result

    def update_one(self, query, update, upsert=False, *a, **kw):
        self.write_calls.append(("update_one", query, update, {"upsert": upsert}))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed")

        for i, doc in enumerate(self.docs):
            if self._matches(doc, query):
                self._apply_update(self.docs[i], update)
                result = MagicMock()
                result.matched_count = 1
                return result

        # upsert: no match found — seed new doc with scalar filter fields (MongoDB behavior)
        if upsert:
            new_doc = {"_id": ObjectId()}
            # Seed from filter fields (scalar, non-operator, non-nested)
            for k, v in query.items():
                if k.startswith("$") or "." in k:
                    continue
                if isinstance(v, dict):
                    continue  # operator — skip
                new_doc[k] = v
            self._apply_update(new_doc, update)
            # $setOnInsert already handled inside _apply_update; no double-apply needed
            self.docs.append(new_doc)
            result = MagicMock()
            result.matched_count = 0
            result.upserted_id = new_doc["_id"]
            return result

        result = MagicMock()
        result.matched_count = 0
        return result

    def _apply_update(self, doc, update):
        """Apply $set, $inc, $push, $addToSet, $setOnInsert operators."""
        for op, fields in update.items():
            if op == "$set":
                for k, v in fields.items():
                    if "." in k:
                        parts = k.split(".", 1)
                        if parts[0] not in doc:
                            doc[parts[0]] = {}
                        if isinstance(doc[parts[0]], dict):
                            doc[parts[0]][parts[1]] = v
                    else:
                        doc[k] = v
            elif op == "$inc":
                for k, v in fields.items():
                    doc[k] = doc.get(k, 0) + v
            elif op == "$push":
                for k, v in fields.items():
                    if isinstance(v, dict) and "$each" in v:
                        doc.setdefault(k, []).extend(v["$each"])
                    else:
                        doc.setdefault(k, []).append(v)
            elif op == "$addToSet":
                for k, v in fields.items():
                    lst = doc.setdefault(k, [])
                    if v not in lst:
                        lst.append(v)
            elif op == "$setOnInsert":
                # Only applied during upsert (insert); _apply_update is called for both
                # update and insert paths — caller decides when to invoke it.
                for k, v in fields.items():
                    doc.setdefault(k, v)

    def update_many(self, *a, **kw):
        self.write_calls.append(("update_many",))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed")

    def insert_many(self, *a, **kw):
        self.write_calls.append(("insert_many",))
        if not self.allow_writes:
            raise RuntimeError("Write not allowed")

    def delete_one(self, *a, **kw):
        raise RuntimeError("Delete not allowed")

    def delete_many(self, *a, **kw):
        raise RuntimeError("Delete not allowed")


# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

WATER_INTENT_MSG = "Tôi vừa uống 250ml nước"
USER = {"_id": "uid_test", "email": "water_user@saman.app"}


def _setup_mocks(conv_col, water_col=None, nutrition_col=None, workout_col=None, users_col=None):
    chat_module.conversations_col = conv_col
    chat_module.water_col = water_col or MockCol()
    chat_module.nutrition_col = nutrition_col or MockCol(allow_writes=False)
    chat_module.workout_history_col = workout_col or MockCol(allow_writes=False)
    chat_module.users_col = users_col or MockCol(allow_writes=False)


def _teardown():
    chat_module.conversations_col = None
    chat_module.water_col = None
    chat_module.nutrition_col = None
    chat_module.workout_history_col = None
    chat_module.users_col = None


# ─────────────────────────────────────────────────────────────
# Test Suite
# ─────────────────────────────────────────────────────────────

class TestChatActionsIdempotency(unittest.TestCase):

    def setUp(self):
        self.conv_col = MockCol()
        self.water_col = MockCol()
        _setup_mocks(self.conv_col, self.water_col)

    def tearDown(self):
        _teardown()

    # ─────────────────────────────────────────────────────────
    # TC-A1: Water-intent message → pending action in response
    # ─────────────────────────────────────────────────────────
    def test_tc_a1_water_intent_creates_pending_action(self):
        """Message with 250ml water intent must return action with status='pending'."""
        res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER,
        ))

        self.assertEqual(res["status"], "success")
        action = res.get("action")
        self.assertIsNotNone(action, "Expected 'action' in response")
        self.assertEqual(action["type"], "log_water")
        self.assertEqual(action["status"], "pending")
        self.assertEqual(action["amount_ml"], 250)
        self.assertIn("id", action)
        # ID must be a non-empty string
        self.assertTrue(bool(action["id"]))

        # Conversation was created with pending_action embedded
        saved_convs = self.conv_col.docs
        self.assertEqual(len(saved_convs), 1)
        saved_conv = saved_convs[0]
        self.assertIn("pending_action", saved_conv)
        self.assertEqual(saved_conv["pending_action"]["status"], "pending")
        self.assertEqual(saved_conv["pending_action"]["id"], action["id"])

        # conversation_id returned
        self.assertTrue(bool(res.get("conversation_id")))

    # ─────────────────────────────────────────────────────────
    # TC-A2: confirm → water_col written; conversation confirmed
    # ─────────────────────────────────────────────────────────
    def test_tc_a2_confirm_writes_water_and_updates_status(self):
        """Confirm action → water doc created + conversation status = 'confirmed'."""
        # Step 1: Create a pending action
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER,
        ))
        action = chat_res["action"]
        action_id = action["id"]
        conv_id = chat_res["conversation_id"]

        # Step 2: Confirm
        confirm_res = asyncio.run(confirm_action(
            ActionDecisionRequest(
                conversation_id=conv_id,
                action_id=action_id,
            ),
            current_user=USER,
        ))

        self.assertEqual(confirm_res["status"], "success")
        self.assertEqual(confirm_res["added_ml"], 250)
        self.assertEqual(confirm_res["action_id"], action_id)

        # water_col must have a document with the action marker
        water_doc = self.water_col.find_one({
            "user_email": USER["email"],
            "applied_actions": action_id,
        })
        self.assertIsNotNone(water_doc, "water_col must have a doc with the action marker")
        self.assertGreaterEqual(water_doc["amount_ml"], 250)

        # Conversation pending_action.status must be 'confirmed'
        saved_conv = self.conv_col.find_one({"_id": ObjectId(conv_id)})
        self.assertIsNotNone(saved_conv)
        self.assertEqual(saved_conv["pending_action"]["status"], "confirmed")

    # ─────────────────────────────────────────────────────────
    # TC-A3: confirm same action_id twice → water NOT incremented again
    # ─────────────────────────────────────────────────────────
    def test_tc_a3_confirm_twice_is_idempotent(self):
        """Second confirm with same action_id must NOT add 250ml a second time."""
        # Step 1: Create pending action
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        req = ActionDecisionRequest(conversation_id=conv_id, action_id=action_id)

        # Step 2: First confirm
        res1 = asyncio.run(confirm_action(req, current_user=USER))
        self.assertEqual(res1["status"], "success")

        # water amount after first confirm
        water_doc_1 = self.water_col.find_one({
            "user_email": USER["email"],
            "applied_actions": action_id,
        })
        amount_after_first = water_doc_1["amount_ml"]

        # Step 3: Second confirm (must succeed idempotently OR raise 409 — either is acceptable)
        from fastapi import HTTPException
        try:
            res2 = asyncio.run(confirm_action(req, current_user=USER))
            # If it doesn't raise, it must return success but water must NOT be incremented
            water_doc_2 = self.water_col.find_one({
                "user_email": USER["email"],
                "applied_actions": action_id,
            })
            amount_after_second = water_doc_2["amount_ml"]
            self.assertEqual(
                amount_after_first,
                amount_after_second,
                f"Water must not be incremented on retry: before={amount_after_first}, after={amount_after_second}",
            )
        except HTTPException as e:
            # 409 Conflict is also an acceptable idempotency guard
            self.assertIn(e.status_code, (409, 200),
                          f"Expected 409 Conflict or 200 OK, got {e.status_code}")

        # Final water amount must still be exactly 250
        final_doc = self.water_col.find_one({
            "user_email": USER["email"],
            "applied_actions": action_id,
        })
        self.assertEqual(
            final_doc["amount_ml"],
            250,
            f"Water amount must be exactly 250, got {final_doc['amount_ml']}",
        )

    # ─────────────────────────────────────────────────────────
    # TC-A4: cancel → status='cancelled', water_col unchanged
    # ─────────────────────────────────────────────────────────
    def test_tc_a4_cancel_leaves_water_unchanged(self):
        """Cancel action → conversation status='cancelled', water_col has no entry."""
        # Step 1: Create pending action
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # water_col must be empty before cancel
        self.assertEqual(len(self.water_col.docs), 0)

        # Step 2: Cancel
        cancel_res = asyncio.run(cancel_action(
            ActionDecisionRequest(
                conversation_id=conv_id,
                action_id=action_id,
            ),
            current_user=USER,
        ))

        self.assertEqual(cancel_res["status"], "cancelled")
        self.assertEqual(cancel_res["action_id"], action_id)

        # water_col must still be empty — no water written
        water_docs = [
            d for d in self.water_col.docs
            if action_id in d.get("applied_actions", [])
        ]
        self.assertEqual(len(water_docs), 0, "Cancel must not write to water_col")

        # Conversation status must be 'cancelled'
        saved_conv = self.conv_col.find_one({"_id": ObjectId(conv_id)})
        self.assertIsNotNone(saved_conv)
        self.assertEqual(saved_conv["pending_action"]["status"], "cancelled")

    # ─────────────────────────────────────────────────────────
    # TC-A5: cancel after confirm → 409 Conflict
    # ─────────────────────────────────────────────────────────
    def test_tc_a5_cancel_after_confirm_raises_conflict(self):
        """Cancelling an already-confirmed action must raise 409."""
        from fastapi import HTTPException

        # Create + confirm
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        asyncio.run(confirm_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER,
        ))

        # Attempt cancel
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(cancel_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER,
            ))
        self.assertEqual(ctx.exception.status_code, 409)

    # ─────────────────────────────────────────────────────────
    # TC-A6: Ownership — User B cannot confirm User A's action
    # ─────────────────────────────────────────────────────────
    def test_tc_a6_ownership_user_b_cannot_confirm_user_a_action(self):
        """User B must get 404 when confirming User A's action."""
        from fastapi import HTTPException

        user_b = {"_id": "uid_b", "email": "user_b@saman.app"}

        # User A creates pending action
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # User B tries to confirm
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(confirm_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=user_b,
            ))
        self.assertEqual(ctx.exception.status_code, 404)

        # water_col must still be empty
        self.assertEqual(len(self.water_col.docs), 0)


if __name__ == "__main__":
    unittest.main()
