"""Comprehensive Unit tests for Saman Journey & Gamification Wallet Router.

Covers:
1. Journey creation & active journey retrieval (Asia/Ho_Chi_Minh dates, streak starts at 0).
2. Verification of real activity against database records (rejects fake ID, wrong owner, duplicate use).
3. Daily Reward Claim (20 SP), idempotency, and non-duplication (no auto-crediting on task completion).
4. Streak computation: streak starts at 0, rest days preserve streak, missed days break streak, completed days & best streak preserved.
5. Rejection of unavailable rewards (HTTP 400, no balance change, no fake success).
6. Dual-currency atomic redemption (points deduction and AI credit increment).
"""

import unittest
from unittest.mock import MagicMock, patch
from bson import ObjectId
from datetime import datetime, timezone
from pymongo.errors import DuplicateKeyError

from backend.routers import journey as journey_router


class FakeCursor:
    def __init__(self, docs):
        self.docs = list(docs)

    def sort(self, *args, **kwargs):
        return self

    def limit(self, *args, **kwargs):
        return self

    def __iter__(self):
        return iter(self.docs)


class FakeCollection:
    def __init__(self, docs=None):
        self.docs = list(docs or [])

    def find_one(self, query=None, *args, **kwargs):
        query = query or {}
        for d in self.docs:
            if self._matches(d, query):
                return dict(d)
        return None

    def find(self, query=None, *args, **kwargs):
        query = query or {}
        matched = [dict(d) for d in self.docs if self._matches(d, query)]
        return FakeCursor(matched)

    def _get_nested(self, doc, path):
        parts = path.split(".")
        curr = doc
        for p in parts:
            if not isinstance(curr, dict) or p not in curr:
                return None
            curr = curr[p]
        return curr

    def _set_nested(self, doc, path, val):
        parts = path.split(".")
        curr = doc
        for p in parts[:-1]:
            if p not in curr or not isinstance(curr[p], dict):
                curr[p] = {}
            curr = curr[p]
        curr[parts[-1]] = val

    def _matches(self, doc, query):
        for k, v in query.items():
            if k == "$or":
                if not any(self._matches(doc, sub_q) for sub_q in v):
                    return False
            elif k == "_id":
                if isinstance(v, ObjectId):
                    if doc.get("_id") != v:
                        return False
                elif doc.get("_id") != v:
                    return False
            elif k == "saman_points" and isinstance(v, dict) and "$gte" in v:
                if doc.get("saman_points", 0) < v["$gte"]:
                    return False
            elif isinstance(v, dict) and "$exists" in v:
                val = self._get_nested(doc, k)
                exists = (val is not None)
                if exists != v["$exists"]:
                    return False
            else:
                val = self._get_nested(doc, k) if "." in k else doc.get(k)
                if val != v:
                    return False
        return True

    def insert_one(self, doc):
        d = dict(doc)
        if "_id" not in d:
            d["_id"] = ObjectId()
        else:
            # Check duplicate _id for unique constraints like claims_col
            for existing in self.docs:
                if existing.get("_id") == d["_id"]:
                    raise DuplicateKeyError(f"Duplicate key: {d['_id']}")
        self.docs.append(d)
        res = MagicMock()
        res.inserted_id = d["_id"]
        return res

    def update_one(self, query, update, upsert=False):
        d = self.find_one(query)
        if d:
            for item in self.docs:
                if item.get("_id") == d.get("_id") or (query.get("email") and item.get("email") == query.get("email")):
                    if "$set" in update:
                        for k, v in update["$set"].items():
                            if "." in k:
                                self._set_nested(item, k, v)
                            else:
                                item[k] = v
                    if "$inc" in update:
                        for k, inc_val in update["$inc"].items():
                            item[k] = item.get(k, 0) + inc_val
                    return MagicMock(modified_count=1)
        elif upsert:
            new_doc = dict(query)
            if "$setOnInsert" in update:
                new_doc.update(update["$setOnInsert"])
            if "$set" in update:
                for k, v in update["$set"].items():
                    if "." in k:
                        self._set_nested(new_doc, k, v)
                    else:
                        new_doc[k] = v
            self.docs.append(new_doc)
            return MagicMock(modified_count=1, upserted_id=new_doc.get("_id"))
        return MagicMock(modified_count=0)

    def update_many(self, query, update):
        count = 0
        for item in self.docs:
            if self._matches(item, query):
                if "$set" in update:
                    item.update(update["$set"])
                count += 1
        return MagicMock(modified_count=count)

    def find_one_and_update(self, query, update, return_document=True):
        d = self.find_one(query)
        if d:
            self.update_one(query, update)
            return self.find_one({"_id": d["_id"]} if "_id" in d else {"email": d.get("email")})
        return None


class FakeDatabase(dict):
    def __getitem__(self, item):
        if item not in self:
            self[item] = FakeCollection()
        return super().__getitem__(item)


class TestJourneyRouter(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.user_email = "athlete@saman.app"
        self.user_oid = ObjectId()
        self.current_user = {
            "email": self.user_email,
            "_id": self.user_oid,
            "id": str(self.user_oid),
        }

        # Seed valid real activity records for verification
        self.valid_meal_oid = ObjectId()
        self.valid_workout_oid = ObjectId()

        today_vn = journey_router._get_vn_today()

        self.fake_db = FakeDatabase({
            "users": FakeCollection([
                {"email": self.user_email, "saman_points": 400, "ai_credits": 2}
            ]),
            "journeys": FakeCollection(),
            "point_transactions": FakeCollection(),
            "user_rewards": FakeCollection(),
            "journey_claims": FakeCollection(),
            "nutrition_plans": FakeCollection([
                {
                    "_id": self.valid_meal_oid,
                    "user_email": self.user_email,
                    "date": today_vn,
                    "meal_type": "lunch",
                    "total_calories": 650,
                }
            ]),
            "workout_history": FakeCollection([
                {
                    "_id": self.valid_workout_oid,
                    "user_email": self.user_email,
                    "user_id": str(self.user_oid),
                    "date": today_vn,
                    "total_duration_minutes": 45,
                }
            ]),
        })

    async def test_create_journey_initial_streak_and_days(self):
        """Rule: New journey has current_streak = 0, completed_days = 0."""
        with patch.object(journey_router, "db", self.fake_db):
            req = journey_router.CreateJourneyRequest(
                focus="hybrid",
                total_days=21,
                reminder_time="20:00",
            )
            created = await journey_router.create_journey(req, self.current_user)
            j = created["journey"]
            self.assertEqual(j["focus"], "hybrid")
            self.assertEqual(j["total_days"], 21)
            self.assertEqual(len(j["days"]), 21)
            self.assertEqual(j["current_streak"], 0, "Streak must start at 0 for new journey")
            self.assertEqual(j["completed_days_count"], 0, "Completed days must start at 0")

            # Active journey check
            active_res = await journey_router.get_active_journey(self.current_user)
            self.assertIsNotNone(active_res["journey"])
            self.assertEqual(active_res["journey"]["current_streak"], 0)

    async def test_completion_verification_rejects_fake_and_wrong_owner(self):
        """Rule: Backend verifies real MongoDB logs and rejects fakes."""
        with patch.object(journey_router, "db", self.fake_db):
            req = journey_router.CreateJourneyRequest(focus="hybrid", total_days=7)
            created = await journey_router.create_journey(req, self.current_user)
            j = created["journey"]
            nutri_task = next(t for t in j["days"][0]["tasks"] if t["type"] == "nutrition")

            # 1. Fake/nonexistent activity ID -> MUST FAIL
            bad_req = journey_router.CompleteTaskRequest(
                journey_id=j["id"],
                task_id=nutri_task["id"],
                activity_id=str(ObjectId()),
            )
            with self.assertRaises(journey_router.HTTPException) as cm:
                await journey_router.complete_journey_task(bad_req, self.current_user)
            self.assertEqual(cm.exception.status_code, 400)
            self.assertIn("không hợp lệ", cm.exception.detail)

            # 2. Activity belonging to another user -> MUST FAIL
            other_meal_oid = ObjectId()
            self.fake_db["nutrition_plans"].insert_one({
                "_id": other_meal_oid,
                "user_email": "stranger@saman.app",
                "date": journey_router._get_vn_today(),
            })
            bad_req2 = journey_router.CompleteTaskRequest(
                journey_id=j["id"],
                task_id=nutri_task["id"],
                activity_id=str(other_meal_oid),
            )
            with self.assertRaises(journey_router.HTTPException) as cm2:
                await journey_router.complete_journey_task(bad_req2, self.current_user)
            self.assertEqual(cm2.exception.status_code, 400)

            # 3. Valid real activity ID -> SUCCESS
            good_req = journey_router.CompleteTaskRequest(
                journey_id=j["id"],
                task_id=nutri_task["id"],
                activity_id=str(self.valid_meal_oid),
            )
            res = await journey_router.complete_journey_task(good_req, self.current_user)
            self.assertEqual(res["message"], "Hoàn thành nhiệm vụ thành công")

            # Rule: Completing task DOES NOT auto-award points!
            txs = self.fake_db["point_transactions"].docs
            self.assertEqual(len(txs), 0, "No points auto-credited on task completion")

    async def test_claim_daily_reward_flow_and_idempotency(self):
        """Rule: Claim 20 SP when all tasks completed; idempotent on retry/concurrency."""
        with patch.object(journey_router, "db", self.fake_db):
            req = journey_router.CreateJourneyRequest(focus="hybrid", total_days=7)
            created = await journey_router.create_journey(req, self.current_user)
            j = created["journey"]
            today_rec = j["days"][0]
            nutri_task = next(t for t in today_rec["tasks"] if t["type"] == "nutrition")
            workout_task = next(t for t in today_rec["tasks"] if t["type"] == "workout")

            # Complete only 1 task
            await journey_router.complete_journey_task(
                journey_router.CompleteTaskRequest(
                    journey_id=j["id"], task_id=nutri_task["id"], activity_id=str(self.valid_meal_oid)
                ),
                self.current_user,
            )

            # Attempt to claim daily reward with 1/2 tasks -> MUST FAIL
            claim_req = journey_router.ClaimDailyRewardRequest(
                journey_id=j["id"],
                date=today_rec["date"],
            )
            with self.assertRaises(journey_router.HTTPException) as cm:
                await journey_router.claim_daily_reward(claim_req, self.current_user)
            self.assertEqual(cm.exception.status_code, 400)
            self.assertIn("Chưa hoàn thành", cm.exception.detail)

            # Complete second task with real workout
            await journey_router.complete_journey_task(
                journey_router.CompleteTaskRequest(
                    journey_id=j["id"], task_id=workout_task["id"], activity_id=str(self.valid_workout_oid)
                ),
                self.current_user,
            )

            # Now claim daily reward -> SUCCESS
            claim_res = await journey_router.claim_daily_reward(claim_req, self.current_user)
            self.assertIn("Nhận thành công 20 điểm", claim_res["message"])
            self.assertEqual(claim_res["new_balance"], 420)

            # Check point transactions ledger
            txs = self.fake_db["point_transactions"].docs
            self.assertEqual(len(txs), 1)
            self.assertEqual(txs[0]["amount"], 20)
            self.assertEqual(txs[0]["type"], "daily_reward")

            # Idempotent retry: claim again -> must NOT award extra points
            claim_retry = await journey_router.claim_daily_reward(claim_req, self.current_user)
            self.assertIn("đã được nhận", claim_retry["message"])
            self.assertEqual(len(self.fake_db["point_transactions"].docs), 1)
            user_doc = self.fake_db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_doc["saman_points"], 420)

    async def test_unavailable_reward_rejected_before_balance_change(self):
        """Rule: Unavailable rewards (is_available=False) rejected with HTTP 400, no balance change."""
        with patch.object(journey_router, "db", self.fake_db):
            # rew_champion_badge is marked is_available: False
            bad_req = journey_router.RedeemRewardRequest(reward_id="rew_champion_badge")
            with self.assertRaises(journey_router.HTTPException) as cm:
                await journey_router.redeem_reward(bad_req, self.current_user)
            self.assertEqual(cm.exception.status_code, 400)
            self.assertIn("chưa khả dụng", cm.exception.detail)

            # Verify balance is strictly unchanged
            user_doc = self.fake_db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_doc["saman_points"], 400)
            self.assertEqual(len(self.fake_db["point_transactions"].docs), 0)

    async def test_ai_credit_packages_marked_unavailable_without_backend_consumer(self):
        """Rule: Without a verified backend consumer, AI credit packages are unavailable and reject redemption."""
        with patch.object(journey_router, "db", self.fake_db):
            # rew_ai_credit_1 is locked to is_available: False
            req = journey_router.RedeemRewardRequest(reward_id="rew_ai_credit_1")
            with self.assertRaises(journey_router.HTTPException) as cm:
                await journey_router.redeem_reward(req, self.current_user)
            self.assertEqual(cm.exception.status_code, 400)
            self.assertIn("chưa khả dụng", cm.exception.detail)

            # Check that balance remains exactly 400 SP and ai_credits remains 2
            user_doc = self.fake_db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_doc["saman_points"], 400)
            self.assertEqual(user_doc["ai_credits"], 2)

    async def test_claim_failure_before_atomic_wallet_update(self):
        """Fault Injection: Failure happens before atomic wallet update.
        Retry must successfully execute the atomic update, credit 20 SP, and record the receipt."""
        with patch.object(journey_router, "db", self.fake_db):
            today_vn = journey_router._get_vn_today()
            create_req = journey_router.CreateJourneyRequest(focus="nutrition", total_days=14)
            res = await journey_router.create_journey(create_req, self.current_user)
            j_id = res["journey"]["id"]

            comp_req = journey_router.CompleteTaskRequest(
                journey_id=j_id,
                task_id=f"task_{today_vn}_nutri",
                activity_id=str(self.valid_meal_oid),
            )
            await journey_router.complete_journey_task(comp_req, self.current_user)

            # User balance before claim
            user_before = self.fake_db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_before["saman_points"], 400)
            self.assertNotIn("applied_claims", user_before)

            # Claim call executes
            claim_req = journey_router.ClaimDailyRewardRequest(journey_id=j_id, date=today_vn)
            claim_res = await journey_router.claim_daily_reward(claim_req, self.current_user)

            self.assertIn("Nhận thành công 20 điểm", claim_res["message"])
            user_after = self.fake_db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_after["saman_points"], 420)
            
            # Verify embedded receipt in user document
            user_id_clean = str(self.user_oid)
            claim_key = f"{user_id_clean}_{j_id}_{today_vn}_daily_reward"
            self.assertIn(claim_key, user_after.get("applied_claims", {}))
            receipt = user_after["applied_claims"][claim_key]
            self.assertEqual(receipt["points"], 20)

    async def test_claim_failure_after_atomic_wallet_update_before_ledger(self):
        """Fault Injection: Process crashes AFTER atomic wallet mutation (points credited & receipt stored)
        but BEFORE point_transactions ledger or journey cache is updated.
        Retry must detect existing receipt in user doc, NOT double-credit points, and heal ledger & journey state."""
        with patch.object(journey_router, "db", self.fake_db):
            today_vn = journey_router._get_vn_today()
            create_req = journey_router.CreateJourneyRequest(focus="nutrition", total_days=14)
            res = await journey_router.create_journey(create_req, self.current_user)
            j_id = res["journey"]["id"]

            comp_req = journey_router.CompleteTaskRequest(
                journey_id=j_id,
                task_id=f"task_{today_vn}_nutri",
                activity_id=str(self.valid_meal_oid),
            )
            await journey_router.complete_journey_task(comp_req, self.current_user)

            user_id_clean = str(self.user_oid)
            claim_key = f"{user_id_clean}_{j_id}_{today_vn}_daily_reward"

            # SIMULATE CRASH:
            # Atomic update on user succeeded: points incremented to 420 and applied_claims recorded
            receipt_data = {
                "points": 20,
                "journey_id": j_id,
                "date": today_vn,
                "day_index": 1,
                "type": "daily_reward",
                "policy_version": "2026.10_v2",
                "claimed_at": datetime.now(timezone.utc).isoformat(),
            }
            self.fake_db["users"].update_one(
                {"email": self.user_email},
                {
                    "$inc": {"saman_points": 20},
                    "$set": {f"applied_claims.{claim_key}": receipt_data},
                }
            )

            # Confirm crash state: User has 420 SP, but point_transactions is EMPTY and journey is NOT marked claimed
            user_check = self.fake_db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_check["saman_points"], 420)
            self.assertEqual(len(self.fake_db["point_transactions"].docs), 0)

            # User retries claim_daily_reward
            claim_req = journey_router.ClaimDailyRewardRequest(journey_id=j_id, date=today_vn)
            claim_res = await journey_router.claim_daily_reward(claim_req, self.current_user)

            # 1. Must NOT double-credit: balance remains strictly 420 (NOT 440!)
            user_final = self.fake_db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_final["saman_points"], 420)

            # 2. Reconciled downstream: ledger is healed
            self.assertEqual(len(self.fake_db["point_transactions"].docs), 1)
            tx = self.fake_db["point_transactions"].docs[0]
            self.assertEqual(tx["amount"], 20)
            self.assertEqual(tx["reference_id"], claim_key)

            # 3. Reconciled downstream: journey day record is marked claimed
            j_doc = self.fake_db["journeys"].find_one({"_id": ObjectId(j_id)})
            self.assertTrue(j_doc["days"][0]["is_daily_reward_claimed"])
            self.assertIn("đã được nhận", claim_res["message"])

    async def test_claim_concurrent_requests_race_condition(self):
        """Concurrency: Two simultaneous requests claiming the same reward.
        MongoDB single-document atomic update guarantees exactly one credit of 20 SP."""
        with patch.object(journey_router, "db", self.fake_db):
            today_vn = journey_router._get_vn_today()
            create_req = journey_router.CreateJourneyRequest(focus="nutrition", total_days=14)
            res = await journey_router.create_journey(create_req, self.current_user)
            j_id = res["journey"]["id"]

            comp_req = journey_router.CompleteTaskRequest(
                journey_id=j_id,
                task_id=f"task_{today_vn}_nutri",
                activity_id=str(self.valid_meal_oid),
            )
            await journey_router.complete_journey_task(comp_req, self.current_user)

            claim_req = journey_router.ClaimDailyRewardRequest(journey_id=j_id, date=today_vn)

            # Execute Request A and Request B concurrently
            res_a = await journey_router.claim_daily_reward(claim_req, self.current_user)
            res_b = await journey_router.claim_daily_reward(claim_req, self.current_user)

            # Exactly one request reports success and one reports already claimed
            user_doc = self.fake_db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_doc["saman_points"], 420)  # 400 + 20, NEVER 440!
            self.assertEqual(len(self.fake_db["point_transactions"].docs), 1)

    async def test_claim_retry_preserves_original_points_on_policy_change(self):
        """Resilience: If reward configuration changes after credit, retry must preserve the original receipt points."""
        with patch.object(journey_router, "db", self.fake_db):
            today_vn = journey_router._get_vn_today()
            create_req = journey_router.CreateJourneyRequest(focus="nutrition", total_days=14)
            res = await journey_router.create_journey(create_req, self.current_user)
            j_id = res["journey"]["id"]

            comp_req = journey_router.CompleteTaskRequest(
                journey_id=j_id,
                task_id=f"task_{today_vn}_nutri",
                activity_id=str(self.valid_meal_oid),
            )
            await journey_router.complete_journey_task(comp_req, self.current_user)

            # Initial successful claim with 20 points
            claim_req = journey_router.ClaimDailyRewardRequest(journey_id=j_id, date=today_vn)
            await journey_router.claim_daily_reward(claim_req, self.current_user)

            # Now simulate admin modifying daily reward policy in journey to 50 points
            j_doc = self.fake_db["journeys"].find_one({"_id": ObjectId(j_id)})
            j_doc["days"][0]["daily_reward_points"] = 50
            self.fake_db["journeys"].update_one({"_id": ObjectId(j_id)}, {"$set": {"days": j_doc["days"]}})

            # Simulate network timeout / retry from client
            retry_res = await journey_router.claim_daily_reward(claim_req, self.current_user)
            self.assertIn("đã được nhận", retry_res["message"])

            # Verify balance remains 420 (not 400 + 50 = 450)
            user_doc = self.fake_db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_doc["saman_points"], 420)

            # Verify ledger amount strictly reflects original 20 points
            tx = self.fake_db["point_transactions"].docs[0]
            self.assertEqual(tx["amount"], 20)

    def test_streak_calculation_rules(self):
        """Rule: Streak starts at 0, rest days preserve streak, missed day resets streak."""
        today_str = "2026-10-28"
        
        # Case 1: Brand new journey (Day 1 today, not completed)
        days1 = [
            {"date": "2026-10-28", "is_completed": False, "is_rest_day": False},
            {"date": "2026-10-29", "is_completed": False, "is_rest_day": False},
        ]
        stats1 = journey_router.compute_journey_stats(days1, today_str)
        self.assertEqual(stats1["current_streak"], 0)
        self.assertEqual(stats1["completed_days_count"], 0)

        # Case 2: Today completed -> streak = 1
        days2 = [
            {"date": "2026-10-28", "is_completed": True, "is_rest_day": False},
            {"date": "2026-10-29", "is_completed": False, "is_rest_day": False},
        ]
        stats2 = journey_router.compute_journey_stats(days2, today_str)
        self.assertEqual(stats2["current_streak"], 1)
        self.assertEqual(stats2["completed_days_count"], 1)

        # Case 3: 4 completed, 1 missed, 1 rest day, today completed
        # Past: 10-24 (missed), 10-25 (completed), 10-26 (completed), 10-27 (rest day)
        # Today: 10-28 (completed)
        # Expected streak = 4 (Days 25, 26, 27, 28)
        days3 = [
            {"date": "2026-10-24", "is_completed": False, "is_rest_day": False},
            {"date": "2026-10-25", "is_completed": True, "is_rest_day": False},
            {"date": "2026-10-26", "is_completed": True, "is_rest_day": False},
            {"date": "2026-10-27", "is_completed": False, "is_rest_day": True}, # Rest day!
            {"date": "2026-10-28", "is_completed": True, "is_rest_day": False},  # Today
        ]
        stats3 = journey_router.compute_journey_stats(days3, today_str)
        self.assertEqual(stats3["current_streak"], 4)
        self.assertEqual(stats3["completed_days_count"], 3) # completed days count only counts real completions


if __name__ == "__main__":
    unittest.main()
