"""Real MongoDB Integration & Concurrency Test for Saman Journey Claim Flow.

Connects to the active local MongoDB instance on port 27028 using an isolated test DB:
`saman_journey_test_db`.
Cleans up before and after test execution.
"""

import sys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

import asyncio
import unittest
from unittest.mock import patch
from bson import ObjectId
from datetime import datetime, timezone
import pymongo
from pymongo import MongoClient

from backend.routers import journey as journey_router


class TestJourneyRealMongo(unittest.IsolatedAsyncioTestCase):
    MONGO_URL = "mongodb://127.0.0.1:27028"
    TEST_DB_NAME = "saman_journey_test_db"

    @classmethod
    def setUpClass(cls):
        try:
            cls.client = MongoClient(cls.MONGO_URL, serverSelectionTimeoutMS=2000)
            cls.client.server_info()
            cls.db = cls.client[cls.TEST_DB_NAME]
            cls.db["users"].create_index([("email", 1)], unique=True)
            cls.mongo_available = True
        except Exception as e:
            cls.mongo_available = False
            cls.skip_reason = f"MongoDB not available on {cls.MONGO_URL}: {e}"

    @classmethod
    def tearDownClass(cls):
        if getattr(cls, "mongo_available", False):
            cls.client.drop_database(cls.TEST_DB_NAME)
            cls.client.close()

    def setUp(self):
        if not getattr(self, "mongo_available", False):
            self.skipTest(self.skip_reason)
        # Clean collections
        self.db["users"].delete_many({})
        self.db["journeys"].delete_many({})
        self.db["point_transactions"].delete_many({})
        self.db["journey_claims"].delete_many({})

        self.user_email = "real_athlete@saman.test"
        self.user_oid = ObjectId()
        self.db["users"].insert_one({
            "_id": self.user_oid,
            "email": self.user_email,
            "saman_points": 400,
            "ai_credits": 2,
        })
        self.current_user = {
            "_id": self.user_oid,
            "id": str(self.user_oid),
            "email": self.user_email,
        }

    async def test_real_mongo_concurrency_race_condition(self):
        """Rule: Two truly concurrent requests claiming the same day reward.
        Real MongoDB standalone atomic find_one_and_update guarantees exactly one +20 SP credit."""
        with patch.object(journey_router, "db", self.db):
            today_vn = journey_router._get_vn_today()
            create_req = journey_router.CreateJourneyRequest(focus="nutrition", total_days=14)
            res = await journey_router.create_journey(create_req, self.current_user)
            j_id = res["journey"]["id"]

            # Mock a valid completed activity log in nutrition_plans
            meal_oid = ObjectId()
            self.db["nutrition_plans"].insert_one({
                "_id": meal_oid,
                "user_email": self.user_email,
                "date": today_vn,
            })

            # Complete today task
            comp_req = journey_router.CompleteTaskRequest(
                journey_id=j_id,
                task_id=f"task_{today_vn}_nutri",
                activity_id=str(meal_oid),
            )
            await journey_router.complete_journey_task(comp_req, self.current_user)

            # Fire TWO simultaneous concurrent requests using asyncio.gather
            claim_req = journey_router.ClaimDailyRewardRequest(journey_id=j_id, date=today_vn)
            res1, res2 = await asyncio.gather(
                journey_router.claim_daily_reward(claim_req, self.current_user),
                journey_router.claim_daily_reward(claim_req, self.current_user),
                return_exceptions=False,
            )

            # Verify balance in real MongoDB is EXACTLY 420 (never 440!)
            user_doc = self.db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_doc["saman_points"], 420)

            # Verify exactly 1 ledger transaction was inserted
            tx_count = self.db["point_transactions"].count_documents({"user_email": self.user_email})
            self.assertEqual(tx_count, 1)

            # Verify embedded receipt is present
            clean_user_id = str(self.user_oid)
            claim_key = f"{clean_user_id}_{j_id}_{today_vn}_daily_reward"
            self.assertIn(claim_key, user_doc.get("applied_claims", {}))
            receipt = user_doc["applied_claims"][claim_key]
            self.assertEqual(receipt["points"], 20)

    async def test_real_mongo_crash_recovery_after_atomic_wallet_update(self):
        """Rule: If process crashes after user document was updated but before ledger was written,
        retry on real MongoDB heals ledger and presentation cache without re-crediting points."""
        with patch.object(journey_router, "db", self.db):
            today_vn = journey_router._get_vn_today()
            create_req = journey_router.CreateJourneyRequest(focus="nutrition", total_days=14)
            res = await journey_router.create_journey(create_req, self.current_user)
            j_id = res["journey"]["id"]

            meal_oid = ObjectId()
            self.db["nutrition_plans"].insert_one({
                "_id": meal_oid,
                "user_email": self.user_email,
                "date": today_vn,
            })
            comp_req = journey_router.CompleteTaskRequest(
                journey_id=j_id,
                task_id=f"task_{today_vn}_nutri",
                activity_id=str(meal_oid),
            )
            await journey_router.complete_journey_task(comp_req, self.current_user)

            # Simulate crash: execute the atomic update directly on MongoDB
            clean_user_id = str(self.user_oid)
            claim_key = f"{clean_user_id}_{j_id}_{today_vn}_daily_reward"
            receipt_data = {
                "points": 20,
                "journey_id": j_id,
                "date": today_vn,
                "day_index": 1,
                "type": "daily_reward",
                "policy_version": "2026.10_v2",
                "claimed_at": datetime.now(timezone.utc).isoformat(),
            }
            self.db["users"].update_one(
                {"email": self.user_email},
                {
                    "$inc": {"saman_points": 20},
                    "$set": {f"applied_claims.{claim_key}": receipt_data},
                }
            )

            # At this moment, point_transactions has 0 records and journey day is not marked claimed
            self.assertEqual(self.db["point_transactions"].count_documents({"user_email": self.user_email}), 0)

            # Client retries
            claim_req = journey_router.ClaimDailyRewardRequest(journey_id=j_id, date=today_vn)
            retry_res = await journey_router.claim_daily_reward(claim_req, self.current_user)

            # Verify balance is STILL 420 (NOT 440)
            user_doc = self.db["users"].find_one({"email": self.user_email})
            self.assertEqual(user_doc["saman_points"], 420)

            # Verify ledger transaction was healed
            tx = self.db["point_transactions"].find_one({"user_email": self.user_email})
            self.assertIsNotNone(tx)
            self.assertEqual(tx["amount"], 20)

            # Verify journey presentation cache is healed
            j_doc = self.db["journeys"].find_one({"_id": ObjectId(j_id)})
            self.assertTrue(j_doc["days"][0]["is_daily_reward_claimed"])
            self.assertIn("đã được nhận", retry_res["message"])


if __name__ == "__main__":
    unittest.main()
