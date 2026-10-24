# [File: backend/tests/test_chat_actions.py]
"""
Checkpoint 6 — Targeted Tests for Confirmed Actions (Log Water)
Verifies:
1. Proposed/cancelled action causes zero health-domain writes.
2. One confirmed water action changes the user's water total exactly once, including retry.
3. Another account cannot confirm or cancel the action (cross-account isolation).
4. Chat and Nutrition return consistent final water data.
5. Meal/workout support gap is verified (rejects non-water action types).
"""
import os
import sys
import asyncio
import unittest
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from unittest.mock import MagicMock
from bson import ObjectId
from fastapi import HTTPException

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import backend.routers.chat as chat_module
from backend.routers.chat import (
    chat_with_ai,
    confirm_action,
    cancel_action,
    _process_action_decision,
    _build_today_water_context,
    ChatRequest,
    ActionDecisionRequest,
)

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


# ─────────────────────────────────────────────────────────────
# In-memory Mongo Collection Mock
# ─────────────────────────────────────────────────────────────

class FakeCursor(list):
    def sort(self, *a, **kw):
        return self

    def limit(self, n):
        return FakeCursor(self[:n])


class MockCol:
    """Read+write mock for MongoDB collections, tracking write calls."""

    def __init__(self, docs=None, allow_writes=True):
        self.docs = [dict(d) for d in docs] if docs else []
        self.allow_writes = allow_writes
        self.write_calls = []

    def _matches(self, doc, query):
        if "$and" in query:
            if not all(self._matches(doc, b) for b in query["$and"]):
                return False
        if "$or" in query:
            branches = query["$or"]
            if not any(self._all_match(doc, b) for b in branches):
                return False
        for k, v in query.items():
            if k == "$or" or k == "$and" or k.startswith("$"):
                continue
            if "." in k:
                parts = k.split(".", 1)
                sub = doc.get(parts[0])
                if not isinstance(sub, dict) or sub.get(parts[1]) != v:
                    return False
                continue
            dv = doc.get(k)
            if isinstance(v, dict):
                if "$ne" in v:
                    if isinstance(dv, list):
                        if v["$ne"] in dv:
                            return False
                    elif dv == v["$ne"]:
                        return False
                continue
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
        if "$or" in branch:
            return any(self._all_match(doc, b) for b in branch["$or"])
        for k, v in branch.items():
            if k.startswith("$"):
                continue
            dv = doc.get(k)
            if isinstance(v, ObjectId) and isinstance(dv, ObjectId):
                if dv != v:
                    return False
            elif str(dv) == str(v):
                continue
            elif dv != v:
                return False
        return True

    def find(self, query=None):
        query = query or {}
        return FakeCursor([d for d in self.docs if self._matches(d, query)])

    def find_one(self, query=None):
        res = self.find(query)
        return dict(res[0]) if res else None

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

        if upsert:
            new_doc = {"_id": ObjectId()}
            for k, v in query.items():
                if k.startswith("$") or "." in k or isinstance(v, dict):
                    continue
                new_doc[k] = v
            self._apply_update(new_doc, update)
            self.docs.append(new_doc)
            result = MagicMock()
            result.matched_count = 0
            result.upserted_id = new_doc["_id"]
            return result

        result = MagicMock()
        result.matched_count = 0
        return result

    def _apply_update(self, doc, update):
        for op, fields in update.items():
            if op == "$set":
                for k, v in fields.items():
                    if "." in k:
                        parts = k.split(".", 1)
                        if parts[0] not in doc or not isinstance(doc[parts[0]], dict):
                            doc[parts[0]] = {}
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
                for k, v in fields.items():
                    doc.setdefault(k, v)


# ─────────────────────────────────────────────────────────────
# Test Fixtures & Setup
# ─────────────────────────────────────────────────────────────

WATER_INTENT_MSG = "Tôi vừa uống 250ml nước"
USER_A = {"_id": "uid_a", "email": "usera@saman.app"}
USER_B = {"_id": "uid_b", "email": "userb@saman.app"}


def _setup_all_mocks(conv_col, water_col, nutrition_col, workout_col, users_col, custom_plans_col=None):
    chat_module.conversations_col = conv_col
    chat_module.water_col = water_col
    chat_module.nutrition_col = nutrition_col
    chat_module.workout_history_col = workout_col
    chat_module.users_col = users_col
    chat_module.custom_plans_col = custom_plans_col


def _teardown_all_mocks():
    chat_module.conversations_col = None
    chat_module.water_col = None
    chat_module.nutrition_col = None
    chat_module.workout_history_col = None
    chat_module.users_col = None
    chat_module.custom_plans_col = None


class TestChatActionsTargeted(unittest.TestCase):

    def setUp(self):
        self.conv_col = MockCol()
        self.water_col = MockCol()
        self.nutrition_col = MockCol()
        self.workout_col = MockCol(allow_writes=False)
        self.users_col = MockCol([{"_id": "uid_a", "email": "usera@saman.app"}], allow_writes=False)
        self.custom_plans_col = MockCol()
        _setup_all_mocks(
            self.conv_col,
            self.water_col,
            self.nutrition_col,
            self.workout_col,
            self.users_col,
            self.custom_plans_col,
        )

    def tearDown(self):
        _teardown_all_mocks()

    # ─────────────────────────────────────────────────────────
    # 1. Propose causes ZERO health-domain writes
    # ─────────────────────────────────────────────────────────
    def test_tc_1_propose_causes_zero_health_domain_writes(self):
        """Merely proposing an action must write zero docs to water, nutrition, or workout."""
        res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER_A,
        ))

        self.assertEqual(res["status"], "success")
        self.assertIsNotNone(res.get("action"))
        self.assertEqual(res["action"]["status"], "pending")
        self.assertEqual(res["action"]["type"], "log_water")
        self.assertEqual(res["action"]["amount_ml"], 250)

        # Zero health-domain writes
        self.assertEqual(len(self.water_col.docs), 0, "water_col must have 0 documents")
        self.assertEqual(len(self.nutrition_col.write_calls), 0, "nutrition_col must have 0 write calls")
        self.assertEqual(len(self.workout_col.write_calls), 0, "workout_history_col must have 0 write calls")

    # ─────────────────────────────────────────────────────────
    # 2. Cancel causes ZERO health-domain writes
    # ─────────────────────────────────────────────────────────
    def test_tc_2_cancel_causes_zero_health_domain_writes(self):
        """Cancelling a pending action must write zero docs to water, nutrition, or workout."""
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        cancel_res = asyncio.run(cancel_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))

        self.assertEqual(cancel_res["status"], "cancelled")
        self.assertEqual(cancel_res["action_id"], action_id)

        # Zero health-domain writes
        self.assertEqual(len(self.water_col.docs), 0, "water_col must remain empty")
        self.assertEqual(len(self.nutrition_col.write_calls), 0, "nutrition_col must have 0 write calls")
        self.assertEqual(len(self.workout_col.write_calls), 0, "workout_history_col must have 0 write calls")

        # Conversation status is cancelled
        conv = self.conv_col.find_one({"_id": ObjectId(conv_id)})
        self.assertEqual(conv["pending_action"]["status"], "cancelled")

    # ─────────────────────────────────────────────────────────
    # 3. Cancel guards & conflict handling
    # ─────────────────────────────────────────────────────────
    def test_tc_3_cancel_already_cancelled_or_confirmed_raises_conflict(self):
        """Cancelling already-cancelled or already-confirmed action must raise 409 Conflict."""
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # Cancel once
        asyncio.run(cancel_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))

        # Cancel second time -> 409 Conflict
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(cancel_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_A,
            ))
        self.assertEqual(ctx.exception.status_code, 409)

    # ─────────────────────────────────────────────────────────
    # 4. Cross-account isolation: User B cannot confirm or cancel
    # ─────────────────────────────────────────────────────────
    def test_tc_4_cross_account_isolation_confirm_and_cancel(self):
        """User B cannot confirm or cancel User A's action; raises 404 and writes 0 records."""
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # User B tries to confirm User A's action
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(confirm_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_B,
            ))
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertEqual(len(self.water_col.docs), 0, "No water logged for User A or B")

        # User B tries to cancel User A's action
        with self.assertRaises(HTTPException) as ctx2:
            asyncio.run(cancel_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_B,
            ))
        self.assertEqual(ctx2.exception.status_code, 404)
        self.assertEqual(len(self.water_col.docs), 0, "No water logged for User A or B")

    # ─────────────────────────────────────────────────────────
    # 5. One confirmed water action changes total exactly once (including retry)
    # ─────────────────────────────────────────────────────────
    def test_tc_5_confirm_changes_water_total_once_including_retry(self):
        """Confirmed action writes 250ml once; subsequent retries do not add duplicate water."""
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        req = ActionDecisionRequest(conversation_id=conv_id, action_id=action_id)

        # First confirm
        res1 = asyncio.run(confirm_action(req, current_user=USER_A))
        self.assertEqual(res1["status"], "success")
        self.assertEqual(res1["amount_ml"], 250)
        self.assertEqual(res1["added_ml"], 250)

        # Retry confirm (e.g. client connection dropped and retried)
        try:
            res2 = asyncio.run(confirm_action(req, current_user=USER_A))
            self.assertEqual(res2["status"], "success")
            self.assertEqual(res2["amount_ml"], 250, "Retry must not increment water total")
        except HTTPException as e:
            self.assertEqual(e.status_code, 409, "If not 200, must be 409 Conflict")

        # Verify database record: total must be exactly 250ml
        water_doc = self.water_col.find_one({"user_email": USER_A["email"]})
        self.assertIsNotNone(water_doc)
        self.assertEqual(water_doc["amount_ml"], 250)
        self.assertIn(action_id, water_doc.get("applied_actions", []))

    # ─────────────────────────────────────────────────────────
    # 6. Timeout retry when in 'processing' state
    # ─────────────────────────────────────────────────────────
    def test_tc_6_timeout_retry_recovers_processing_state(self):
        """When an earlier request timed out in 'processing' state, retry safely completes."""
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # Simulate timeout before water write: status was transitioned to 'processing'
        self.conv_col.update_one(
            {"_id": ObjectId(conv_id)},
            {"$set": {"pending_action.status": "processing"}},
        )

        req = ActionDecisionRequest(conversation_id=conv_id, action_id=action_id)
        # Client retries
        res = asyncio.run(confirm_action(req, current_user=USER_A))
        self.assertEqual(res["status"], "success")
        self.assertEqual(res["amount_ml"], 250)

        # DB has exactly 250ml and conversation is confirmed
        water_doc = self.water_col.find_one({"user_email": USER_A["email"]})
        self.assertEqual(water_doc["amount_ml"], 250)
        conv = self.conv_col.find_one({"_id": ObjectId(conv_id)})
        self.assertEqual(conv["pending_action"]["status"], "confirmed")

    # ─────────────────────────────────────────────────────────
    # 7. Concurrent double confirm race condition
    # ─────────────────────────────────────────────────────────
    def test_tc_7_concurrent_confirm_adds_water_only_once(self):
        """Two concurrent confirm requests with the same action_id result in exactly 250ml total."""
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        req = ActionDecisionRequest(conversation_id=conv_id, action_id=action_id)

        # Run two confirms concurrently
        async def run_pair():
            results = await asyncio.gather(
                confirm_action(req, current_user=USER_A),
                confirm_action(req, current_user=USER_A),
                return_exceptions=True,
            )
            return results

        results = asyncio.run(run_pair())

        # At least one succeeded
        successful = [r for r in results if isinstance(r, dict) and r.get("status") == "success"]
        self.assertGreaterEqual(len(successful), 1)

        # Final water total in DB MUST be exactly 250ml (not 500ml)
        water_doc = self.water_col.find_one({"user_email": USER_A["email"]})
        self.assertIsNotNone(water_doc)
        self.assertEqual(water_doc["amount_ml"], 250)

    # ─────────────────────────────────────────────────────────
    # 8. Chat and Nutrition return consistent final water data
    # ─────────────────────────────────────────────────────────
    def test_tc_8_chat_and_nutrition_return_consistent_data(self):
        """Water logged via Chat confirmation is immediately reflected in Nutrition context."""
        today_vn = datetime.now(VN_TZ).strftime("%Y-%m-%d")

        # Seed existing Nutrition water: user already drank 500ml today
        self.water_col.docs.append({
            "_id": ObjectId(),
            "user_email": USER_A["email"],
            "date": today_vn,
            "amount_ml": 500,
            "version": 1,
            "applied_actions": [],
        })

        # User confirms additional 250ml in Chat
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        confirm_res = asyncio.run(confirm_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))
        self.assertEqual(confirm_res["amount_ml"], 750)

        # Nutrition collection record
        nutrition_water_doc = self.water_col.find_one({
            "user_email": USER_A["email"],
            "date": today_vn,
        })
        self.assertEqual(nutrition_water_doc["amount_ml"], 750)

        # Chat context builder also reflects 750ml
        chat_water_context = _build_today_water_context(USER_A["email"], self.water_col)
        self.assertIn("750 ml", chat_water_context)

    # ─────────────────────────────────────────────────────────
    # 9. Confirm uses server-stored action, never client params
    # ─────────────────────────────────────────────────────────
    def test_tc_9_confirm_uses_stored_action_identity(self):
        """Confirm derives amount, date, and user strictly from server-stored action."""
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=WATER_INTENT_MSG),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # ActionDecisionRequest does not even have amount or date fields
        req = ActionDecisionRequest(conversation_id=conv_id, action_id=action_id)
        self.assertFalse(hasattr(req, "amount_ml"))
        self.assertFalse(hasattr(req, "date"))

        res = asyncio.run(confirm_action(req, current_user=USER_A))
        self.assertEqual(res["added_ml"], 250)

    # ─────────────────────────────────────────────────────────
    # 10. Unsupported action type (e.g. workout) rejected
    # ─────────────────────────────────────────────────────────
    def test_tc_10_unsupported_action_type_rejected(self):
        """Unsupported action types like workout are rejected with 400 Bad Request."""
        conv_id = str(ObjectId())
        action_id = str(ObjectId())
        self.conv_col.docs.append({
            "_id": ObjectId(conv_id),
            "user_email": USER_A["email"],
            "user_id": USER_A["_id"],
            "pending_action": {
                "id": action_id,
                "type": "log_workout",  # Unsupported in CP6
                "status": "pending",
            },
        })

        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(confirm_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_A,
            ))
        self.assertEqual(ctx.exception.status_code, 400)
        self.assertIn("Unsupported action type", ctx.exception.detail)
        self.assertEqual(len(self.water_col.docs), 0)
        self.assertEqual(len(self.nutrition_col.docs), 0)

    # ─────────────────────────────────────────────────────────
    # MEAL ACTIONS (CHECKPOINT 6 - MEAL PORTION)
    # ─────────────────────────────────────────────────────────

    def test_meal_1_propose_causes_zero_health_domain_writes(self):
        """Proposing a meal action creates a pending action with exact fields and 0 nutrition writes."""
        meal_msg = "Log bữa sáng: Phở bò, 450 calo, 25g protein, 50g carbs, 12g fat"
        res = asyncio.run(chat_with_ai(
            ChatRequest(message=meal_msg),
            current_user=USER_A,
        ))

        self.assertEqual(res["status"], "success")
        action = res.get("action")
        self.assertIsNotNone(action, "Expected 'action' in response")
        self.assertEqual(action["type"], "log_meal")
        self.assertEqual(action["status"], "pending")
        self.assertEqual(action["meal_type"], "breakfast")
        self.assertEqual(action["total_calories"], 450)
        self.assertEqual(action["total_protein"], 25.0)
        self.assertEqual(action["total_carbs"], 50.0)
        self.assertEqual(action["total_fat"], 12.0)
        self.assertTrue(len(action["foods"]) > 0)
        self.assertEqual(action["foods"][0]["name"], "Phở bò")
        self.assertTrue(bool(action["id"]))

        # Zero health-domain writes
        self.assertEqual(len(self.nutrition_col.docs), 0, "nutrition_col must have 0 documents")
        self.assertEqual(len(self.nutrition_col.write_calls), 0, "nutrition_col must have 0 write calls")
        self.assertEqual(len(self.water_col.docs), 0, "water_col must have 0 documents")

    def test_meal_2_cancel_causes_zero_health_domain_writes(self):
        """Cancelling a pending meal action marks conversation cancelled and writes 0 nutrition records."""
        meal_msg = "Log bữa sáng: Phở bò, 450 calo, 25g protein, 50g carbs, 12g fat"
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=meal_msg),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        cancel_res = asyncio.run(cancel_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))

        self.assertEqual(cancel_res["status"], "cancelled")
        self.assertEqual(cancel_res["action_id"], action_id)

        # Zero health-domain writes
        self.assertEqual(len(self.nutrition_col.docs), 0, "nutrition_col must remain empty")
        self.assertEqual(len(self.nutrition_col.write_calls), 0, "nutrition_col must have 0 write calls")

        # Conversation status is cancelled
        conv = self.conv_col.find_one({"_id": ObjectId(conv_id)})
        self.assertEqual(conv["pending_action"]["status"], "cancelled")

    def test_meal_3_cross_account_isolation_confirm_and_cancel(self):
        """User B cannot confirm or cancel User A's meal action; raises 404 and writes 0 records."""
        meal_msg = "Log bữa trưa: Cơm gà, 600 kcal, 40g protein, 70g carbs, 10g fat"
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=meal_msg),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # User B tries to confirm
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(confirm_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_B,
            ))
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertEqual(len(self.nutrition_col.docs), 0)

        # User B tries to cancel
        with self.assertRaises(HTTPException) as ctx2:
            asyncio.run(cancel_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_B,
            ))
        self.assertEqual(ctx2.exception.status_code, 404)
        self.assertEqual(len(self.nutrition_col.docs), 0)

    def test_meal_4_confirm_writes_once_including_retry(self):
        """Confirmed meal action writes once to user's nutrition data; retries are idempotent."""
        meal_msg = "Log bữa tối: Cá hồi nướng, 500 kcal, 40g protein, 0g carbs, 25g fat"
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=meal_msg),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        req = ActionDecisionRequest(conversation_id=conv_id, action_id=action_id)

        # First confirm
        res1 = asyncio.run(confirm_action(req, current_user=USER_A))
        self.assertEqual(res1["status"], "success")
        self.assertEqual(res1["meal"]["total_calories"], 500)

        # DB has exactly 1 meal doc
        self.assertEqual(len(self.nutrition_col.docs), 1)
        doc = self.nutrition_col.docs[0]
        self.assertEqual(doc["user_email"], USER_A["email"])
        self.assertEqual(doc["total_calories"], 500)
        self.assertEqual(doc["action_id"], action_id)

        # Retry confirm (e.g. timeout / network drop)
        res2 = asyncio.run(confirm_action(req, current_user=USER_A))
        self.assertEqual(res2["status"], "success")

        # DB STILL has exactly 1 meal doc!
        self.assertEqual(len(self.nutrition_col.docs), 1, "Retry must not duplicate meal doc")

    def test_meal_5_concurrent_confirm_writes_meal_only_once(self):
        """Two concurrent confirm requests with same action_id write to nutrition_col exactly once."""
        meal_msg = "Log bữa phụ: Sữa chua Hy Lạp, 150 kcal, 15g protein, 10g carbs, 2g fat"
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=meal_msg),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        req = ActionDecisionRequest(conversation_id=conv_id, action_id=action_id)

        async def run_pair():
            results = await asyncio.gather(
                confirm_action(req, current_user=USER_A),
                confirm_action(req, current_user=USER_A),
                return_exceptions=True,
            )
            return results

        results = asyncio.run(run_pair())

        successful = [r for r in results if isinstance(r, dict) and r.get("status") == "success"]
        self.assertGreaterEqual(len(successful), 1)

        # DB has EXACTLY 1 document in nutrition_col
        self.assertEqual(len(self.nutrition_col.docs), 1, "Concurrent confirms must write exactly 1 doc")
        doc = self.nutrition_col.docs[0]
        self.assertEqual(doc["total_calories"], 150)
        self.assertEqual(doc["action_id"], action_id)

    def test_meal_6_timeout_retry_recovers_processing_state(self):
        """When an earlier request timed out in 'processing' state, retry safely completes."""
        meal_msg = "Log bữa sáng: Trứng ốp la, 200 kcal, 14g protein, 2g carbs, 15g fat"
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=meal_msg),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # Simulate timeout before write
        self.conv_col.update_one(
            {"_id": ObjectId(conv_id)},
            {"$set": {"pending_action.status": "processing"}},
        )

        req = ActionDecisionRequest(conversation_id=conv_id, action_id=action_id)
        res = asyncio.run(confirm_action(req, current_user=USER_A))
        self.assertEqual(res["status"], "success")

        # DB has exactly 1 meal doc
        self.assertEqual(len(self.nutrition_col.docs), 1)
        conv = self.conv_col.find_one({"_id": ObjectId(conv_id)})
        self.assertEqual(conv["pending_action"]["status"], "confirmed")

    def test_meal_7_cancel_after_confirm_raises_conflict(self):
        """Cancelling an already-confirmed meal action must raise 409 Conflict."""
        meal_msg = "Log bữa trưa: Bún chả, 550 calo, 30g protein, 60g carbs, 18g fat"
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=meal_msg),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # Confirm
        asyncio.run(confirm_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))

        # Attempt cancel -> 409 Conflict
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(cancel_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_A,
            ))
        self.assertEqual(ctx.exception.status_code, 409)

    def test_meal_8_chat_and_nutrition_return_consistent_data(self):
        """Meal logged via Chat confirmation is immediately reflected in nutrition context."""
        meal_msg = "Log bữa sáng: Phở bò, 450 calo, 25g protein, 50g carbs, 12g fat"
        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message=meal_msg),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        asyncio.run(confirm_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))

        from backend.routers.chat import _build_today_nutrition_context
        nutrition_context = _build_today_nutrition_context(USER_A["email"], self.nutrition_col)
        self.assertIn("450 kcal", nutrition_context)
        self.assertIn("Protein: 25.0g", nutrition_context)

    def test_meal_9_vague_text_does_not_create_action(self):
        """Vague food statements without explicit calories do not infer calories or create actions."""
        from unittest.mock import patch
        from backend.routers.chat import _detect_log_meal_intent
        self.assertIsNone(_detect_log_meal_intent("Tôi vừa ăn 1 bát phở bò"))

        with patch("backend.routers.chat._generate_ai_reply", return_value="Tôi hiểu rồi."):
            res = asyncio.run(chat_with_ai(
                ChatRequest(message="Tôi vừa ăn 1 bát phở bò"),
                current_user=USER_A,
            ))
            self.assertIsNone(res.get("action"))
            self.assertEqual(len(self.nutrition_col.docs), 0)

    def test_meal_10_explicit_structured_meal_in_request_creates_action(self):
        """Structured meal in ChatRequest creates pending meal action with exact fields."""
        req = ChatRequest(
            message="Confirm meal preview",
            meal={
                "name": "Bít tết bò",
                "calories": 400,
                "protein": 45.0,
                "carbs": 5.0,
                "fat": 20.0,
                "meal_type": "dinner",
            },
        )
        res = asyncio.run(chat_with_ai(req, current_user=USER_A))
        action = res.get("action")
        self.assertIsNotNone(action)
        self.assertEqual(action["type"], "log_meal")
        self.assertEqual(action["total_calories"], 400)
        self.assertEqual(action["meal_type"], "dinner")
        self.assertEqual(action["foods"][0]["name"], "Bít tết bò")
        self.assertEqual(len(self.nutrition_col.docs), 0)

    # ─────────────────────────────────────────────────────────
    # Workout Action Tests (CP6 Confirmed Actions: Adjust Workout)
    # ─────────────────────────────────────────────────────────

    def test_workout_1_propose_causes_zero_domain_writes(self):
        """Proposing workout adjustment must write zero docs to custom_plans, water, nutrition, or workout_history."""
        plan_id = ObjectId()
        self.custom_plans_col.docs.append({
            "_id": plan_id,
            "email": USER_A["email"],
            "name": "Leg Day",
            "duration_minutes": 45,
            "difficulty": "intermediate",
        })

        workout_msg = "Điều chỉnh kế hoạch tập Leg Day từ 45 phút xuống 30 phút"
        res = asyncio.run(chat_with_ai(
            ChatRequest(message=workout_msg),
            current_user=USER_A,
        ))

        self.assertEqual(res["status"], "success")
        action = res.get("action")
        self.assertIsNotNone(action)
        self.assertEqual(action["status"], "pending")
        self.assertEqual(action["type"], "adjust_workout")
        self.assertEqual(action["plan_name"], "Leg Day")
        self.assertEqual(action["plan_id"], str(plan_id))
        self.assertEqual(action["before"], {"duration_minutes": 45})
        self.assertEqual(action["after"], {"duration_minutes": 30})
        self.assertEqual(action["changes"], {"duration_minutes": 30})
        self.assertIn("Leg Day", res["reply"])
        self.assertIn("45 phút -> 30 phút", res["reply"])

        # Zero domain writes
        existing = self.custom_plans_col.find_one({"_id": plan_id})
        self.assertEqual(existing["duration_minutes"], 45, "Plan must remain unchanged on proposal")
        self.assertEqual(len(self.custom_plans_col.write_calls), 0, "custom_plans_col must have 0 write calls")
        self.assertEqual(len(self.workout_col.write_calls), 0, "workout_history_col must have 0 write calls")

    def test_workout_2_cancel_causes_zero_domain_writes(self):
        """Cancelling a workout adjustment must write zero docs to custom_plans and set status to cancelled."""
        plan_id = ObjectId()
        self.custom_plans_col.docs.append({
            "_id": plan_id,
            "email": USER_A["email"],
            "name": "Upper Body",
            "duration_minutes": 60,
            "difficulty": "intermediate",
        })

        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message="Điều chỉnh kế hoạch tập Upper Body từ 60 phút xuống 45 phút"),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        cancel_res = asyncio.run(cancel_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))
        self.assertEqual(cancel_res["status"], "cancelled")
        self.assertEqual(cancel_res["action_id"], action_id)

        # Plan unchanged
        plan_doc = self.custom_plans_col.find_one({"_id": plan_id})
        self.assertEqual(plan_doc["duration_minutes"], 60)
        self.assertEqual(len(self.custom_plans_col.write_calls), 0)

        # Conversation status updated to cancelled
        conv_doc = self.conv_col.find_one({"_id": ObjectId(conv_id)})
        self.assertEqual(conv_doc["pending_action"]["status"], "cancelled")

    def test_workout_3_confirm_updates_plan_and_marks_action(self):
        """Confirming workout adjustment modifies authenticated user's plan and marks action_id."""
        plan_id = ObjectId()
        self.custom_plans_col.docs.append({
            "_id": plan_id,
            "email": USER_A["email"],
            "name": "Full Body Cardio",
            "duration_minutes": 50,
            "difficulty": "intermediate",
        })

        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message="Điều chỉnh kế hoạch tập Full Body Cardio từ 50 phút xuống 35 phút"),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        confirm_res = asyncio.run(confirm_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))
        self.assertEqual(confirm_res["status"], "success")
        self.assertEqual(confirm_res["workout"]["duration_minutes"], 35)

        # Plan updated in custom_plans_col
        updated_plan = self.custom_plans_col.find_one({"_id": plan_id})
        self.assertEqual(updated_plan["duration_minutes"], 35)
        self.assertIn(action_id, updated_plan.get("applied_actions", []))

        # Conversation pending_action marked confirmed
        conv_doc = self.conv_col.find_one({"_id": ObjectId(conv_id)})
        self.assertEqual(conv_doc["pending_action"]["status"], "confirmed")

    def test_workout_4_idempotent_retry_and_concurrency(self):
        """Repeated or concurrent confirm calls perform exactly one effective mutation."""
        plan_id = ObjectId()
        self.custom_plans_col.docs.append({
            "_id": plan_id,
            "email": USER_A["email"],
            "name": "Core Blast",
            "duration_minutes": 40,
            "difficulty": "beginner",
        })

        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message="Điều chỉnh kế hoạch tập Core Blast từ 40 phút xuống 25 phút"),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # First confirm
        res1 = asyncio.run(confirm_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))
        self.assertEqual(res1["status"], "success")

        # Second confirm (retry/timeout replay)
        res2 = asyncio.run(confirm_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))
        self.assertEqual(res2["status"], "success")

        # Duration is 25, applied_actions contains action_id exactly once
        updated_plan = self.custom_plans_col.find_one({"_id": plan_id})
        self.assertEqual(updated_plan["duration_minutes"], 25)
        self.assertEqual(updated_plan.get("applied_actions", []).count(action_id), 1)

    def test_workout_5_cannot_cancel_after_confirm(self):
        """Cancelling an already confirmed workout adjustment raises 409 Conflict."""
        plan_id = ObjectId()
        self.custom_plans_col.docs.append({
            "_id": plan_id,
            "email": USER_A["email"],
            "name": "Morning Yoga",
            "duration_minutes": 30,
            "difficulty": "beginner",
        })

        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message="Điều chỉnh kế hoạch tập Morning Yoga từ 30 phút xuống 20 phút"),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        asyncio.run(confirm_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))

        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(cancel_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_A,
            ))
        self.assertEqual(ctx.exception.status_code, 409)

    def test_workout_6_cross_account_isolation(self):
        """USER_B cannot confirm or cancel USER_A's pending workout action."""
        plan_id = ObjectId()
        self.custom_plans_col.docs.append({
            "_id": plan_id,
            "email": USER_A["email"],
            "name": "Strength Day",
            "duration_minutes": 60,
            "difficulty": "advanced",
        })

        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message="Điều chỉnh kế hoạch tập Strength Day từ 60 phút xuống 45 phút"),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        # USER_B tries to confirm USER_A's action -> 404
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(confirm_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_B,
            ))
        self.assertEqual(ctx.exception.status_code, 404)

        # USER_B tries to cancel USER_A's action -> 404
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(cancel_action(
                ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
                current_user=USER_B,
            ))
        self.assertEqual(ctx.exception.status_code, 404)

        # Plan remains unchanged
        plan_doc = self.custom_plans_col.find_one({"_id": plan_id})
        self.assertEqual(plan_doc["duration_minutes"], 60)

    def test_workout_7_consistency_with_workout_plans(self):
        """Workout plan adjusted via Chat confirmation immediately reflects changes in custom_plans collection."""
        plan_id = ObjectId()
        self.custom_plans_col.docs.append({
            "_id": plan_id,
            "email": USER_A["email"],
            "name": "HIIT Sprint",
            "duration_minutes": 45,
            "difficulty": "advanced",
        })

        chat_res = asyncio.run(chat_with_ai(
            ChatRequest(message="Điều chỉnh kế hoạch tập HIIT Sprint từ 45 phút xuống 25 phút"),
            current_user=USER_A,
        ))
        action_id = chat_res["action"]["id"]
        conv_id = chat_res["conversation_id"]

        asyncio.run(confirm_action(
            ActionDecisionRequest(conversation_id=conv_id, action_id=action_id),
            current_user=USER_A,
        ))

        # Query custom_plans directly as workout read route does
        retrieved = self.custom_plans_col.find_one({"_id": plan_id, "email": USER_A["email"]})
        self.assertEqual(retrieved["duration_minutes"], 25)
        self.assertEqual(retrieved["name"], "HIIT Sprint")

    def test_workout_8_vague_text_does_not_create_action(self):
        """Vague statements or questions about workouts do not create pending actions."""
        from unittest.mock import patch

        vague_queries = [
            "Hôm nay tôi mệt quá",
            "Có nên tập 30 phút không?",
            "Tôi muốn tập nhẹ hơn được không?",
        ]
        with patch("backend.routers.chat._generate_ai_reply", return_value="Tôi hiểu rồi."):
            for q in vague_queries:
                res = asyncio.run(chat_with_ai(ChatRequest(message=q), current_user=USER_A))
                self.assertIsNone(res.get("action"), f"Query '{q}' should not create an action")

    def test_workout_9_explicit_structured_workout_in_request_creates_action(self):
        """Structured workout in ChatRequest creates pending workout action with exact fields."""
        plan_id = ObjectId()
        self.custom_plans_col.docs.append({
            "_id": plan_id,
            "email": USER_A["email"],
            "name": "Push Day",
            "duration_minutes": 50,
            "difficulty": "intermediate",
        })

        req = ChatRequest(
            message="Confirm workout preview",
            workout={
                "plan_id": str(plan_id),
                "plan_name": "Push Day",
                "before": {"duration_minutes": 50},
                "after": {"duration_minutes": 30},
                "changes": {"duration_minutes": 30},
            },
        )
        res = asyncio.run(chat_with_ai(req, current_user=USER_A))
        action = res.get("action")
        self.assertIsNotNone(action)
        self.assertEqual(action["type"], "adjust_workout")
        self.assertEqual(action["plan_id"], str(plan_id))
        self.assertEqual(action["plan_name"], "Push Day")
        self.assertEqual(action["changes"], {"duration_minutes": 30})
        self.assertEqual(len(self.custom_plans_col.write_calls), 0)


if __name__ == "__main__":
    unittest.main()
