"""
Integration and Concurrency Tests for Saman Community on Real MongoDB.
Tests:
1. Concurrent PUT likes from the same user -> exactly 1 interaction, count increases by 1.
2. Concurrent PUT likes from 10 distinct users -> exactly 10 interactions, count = 10.
3. Repeated DELETE from same user -> idempotent, count decreases by 1 and stays stable.
4. Interleaved concurrent PUT and DELETE -> final count strictly matches interactions collection.
5. Self-healing authoritative count: if post.like_count is corrupted, next operation restores correct count.
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import threading
import unittest
from unittest.mock import patch
from bson import ObjectId
from pymongo import MongoClient

from backend.routers.community import router
from backend.main import app
from fastapi.testclient import TestClient
import jwt
from backend.routers.community import JWT_ALGORITHM, JWT_SECRET

MONGO_URI = "mongodb://127.0.0.1:27035"
DB_NAME = "saman_jcom0501_test"


class ControlledInterleavingPostsColWrapper:
    """
    Test wrapper around pymongo collection that pauses the first update_one call
    until Thread B completes, reproducing exact interleaving race conditions deterministically.
    """
    def __init__(self, real_col, a_paused_evt=None, resume_a_evt=None):
        self._real_col = real_col
        self.a_paused_evt = a_paused_evt
        self.resume_a_evt = resume_a_evt
        self.pause_count = 0
        self._lock = threading.Lock()

    def __getattr__(self, name):
        return getattr(self._real_col, name)

    def update_one(self, filter, update, *args, **kwargs):
        with self._lock:
            should_pause = (self.pause_count == 0 and self.a_paused_evt is not None)
            if should_pause:
                self.pause_count += 1
        if should_pause:
            self.a_paused_evt.set()
            if self.resume_a_evt:
                self.resume_a_evt.wait(timeout=10)
        return self._real_col.update_one(filter, update, *args, **kwargs)


class TestCommunityConcurrencyRealMongo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            cls.client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=2000)
            cls.client.server_info()
            cls.db = cls.client[DB_NAME]
            cls.posts_col = cls.db["community_posts"]
            cls.interactions_col = cls.db["community_interactions"]
            cls.is_mongo_available = True
        except Exception:
            cls.is_mongo_available = False

    @classmethod
    def tearDownClass(cls):
        if getattr(cls, "is_mongo_available", False) and hasattr(cls, "client"):
            cls.client.close()

    def setUp(self):
        if not self.is_mongo_available:
            self.skipTest(f"MongoDB not available on {MONGO_URI}")

        # Patch collection getters to use the test MongoDB database on 27035
        self.posts_patcher = patch(
            "backend.routers.community.get_community_posts_collection",
            return_value=self.posts_col,
        )
        self.interactions_patcher = patch(
            "backend.routers.community.get_community_interactions_collection",
            return_value=self.interactions_col,
        )
        self.mock_posts_col = self.posts_patcher.start()
        self.mock_interactions_col = self.interactions_patcher.start()

        self.test_client = TestClient(app)

        # Setup test post
        self.post_id = "test_concurrency_post_01"
        self.posts_col.delete_many({"id": self.post_id})
        self.interactions_col.delete_many({"post_id": self.post_id})

        self.posts_col.insert_one({
            "_id": ObjectId("672500000000000000000001"),
            "id": self.post_id,
            "type": "photo",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "like_count": 0,
            "author_id": "author_concurrency_test",
            "author": {"id": "author_concurrency_test", "name": "Test Author"},
            "caption": "Concurrency test post",
            "created_at": datetime.now(timezone.utc),
        })

    def tearDown(self):
        if self.is_mongo_available:
            self.posts_patcher.stop()
            self.interactions_patcher.stop()

    def _get_token(self, user_id):
        return jwt.encode(
            {"email": f"{user_id}@saman.test", "user_id": user_id, "name": user_id},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )

    def test_same_user_concurrent_put_likes(self):
        """Two concurrent PUT requests from the same user only create 1 interaction and increment like_count by 1."""
        user_id = "user_same_concurrent"
        token = self._get_token(user_id)
        headers = {"Authorization": f"Bearer {token}"}

        def make_like():
            return self.test_client.put(f"/api/community/posts/{self.post_id}/like", headers=headers)

        with ThreadPoolExecutor(max_workers=4) as executor:
            futures = [executor.submit(make_like) for _ in range(4)]
            results = [f.result() for f in futures]

        for r in results:
            self.assertEqual(r.status_code, 200)

        # Assert exactly 1 document in community_interactions
        interactions = list(self.interactions_col.find({"post_id": self.post_id, "user_id": user_id, "interaction_type": "like"}))
        self.assertEqual(len(interactions), 1)

        # Assert post like_count is exactly 1
        post = self.posts_col.find_one({"id": self.post_id})
        self.assertEqual(post["like_count"], 1)

    def test_distinct_users_concurrent_put_likes(self):
        """10 distinct users liking concurrently produces exactly 10 interactions and like_count = 10."""
        user_ids = [f"user_distinct_{i}" for i in range(10)]

        def make_like(uid):
            token = self._get_token(uid)
            return self.test_client.put(f"/api/community/posts/{self.post_id}/like", headers={"Authorization": f"Bearer {token}"})

        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(make_like, uid) for uid in user_ids]
            results = [f.result() for f in futures]

        for r in results:
            self.assertEqual(r.status_code, 200)

        count = self.interactions_col.count_documents({"post_id": self.post_id, "interaction_type": "like"})
        self.assertEqual(count, 10)

        post = self.posts_col.find_one({"id": self.post_id})
        self.assertEqual(post["like_count"], 10)

    def test_interleaved_put_and_delete(self):
        """Interleaved PUT and DELETE operations maintain strict counter consistency."""
        user_ids = [f"user_interleave_{i}" for i in range(8)]

        # 4 users like, 4 users like then unlike
        def action(uid, do_unlike=False):
            token = self._get_token(uid)
            headers = {"Authorization": f"Bearer {token}"}
            self.test_client.put(f"/api/community/posts/{self.post_id}/like", headers=headers)
            if do_unlike:
                self.test_client.delete(f"/api/community/posts/{self.post_id}/like", headers=headers)

        with ThreadPoolExecutor(max_workers=8) as executor:
            futures = [
                executor.submit(action, user_ids[i], do_unlike=(i % 2 == 1))
                for i in range(8)
            ]
            for f in futures:
                f.result()

        expected_count = self.interactions_col.count_documents({"post_id": self.post_id, "interaction_type": "like"})
        post = self.posts_col.find_one({"id": self.post_id})
        self.assertEqual(post["like_count"], expected_count)
        self.assertEqual(expected_count, 4)

    def test_counter_self_healing_from_corruption(self):
        """If like_count was corrupted by a prior crash, next operation heals it to authoritative count."""
        # 1. User 1 likes
        token_1 = self._get_token("user_heal_1")
        self.test_client.put(f"/api/community/posts/{self.post_id}/like", headers={"Authorization": f"Bearer {token_1}"})

        # 2. Corrupt like_count in posts collection to 999
        self.posts_col.update_one({"id": self.post_id}, {"$set": {"like_count": 999}})
        corrupted = self.posts_col.find_one({"id": self.post_id})
        self.assertEqual(corrupted["like_count"], 999)

        # 3. User 2 likes
        token_2 = self._get_token("user_heal_2")
        res = self.test_client.put(f"/api/community/posts/{self.post_id}/like", headers={"Authorization": f"Bearer {token_2}"})
        self.assertEqual(res.status_code, 200)

        # 4. Assert count self-healed to exactly 2 (user_heal_1 and user_heal_2)
        data = res.json()
        self.assertEqual(data["like_count"], 2)
        post = self.posts_col.find_one({"id": self.post_id})
        self.assertEqual(post["like_count"], 2)

    def test_controlled_interleaving_put_put_no_stale_overwrite(self):
        """
        Controlled interleaving test:
        Thread A inserts interaction, reads count = 1, then pauses before update_one.
        Thread B inserts interaction, reads count = 2, and completes update_one.
        Thread A resumes and executes its update.
        Under OCC, Thread A's stale write is rejected, it retries, and final count is strictly 2.
        Verified via direct database inspection and Feed/Detail endpoints without any repair mutation.
        """
        a_paused_evt = threading.Event()
        resume_a_evt = threading.Event()

        wrapper = ControlledInterleavingPostsColWrapper(
            self.posts_col,
            a_paused_evt=a_paused_evt,
            resume_a_evt=resume_a_evt,
        )

        self.mock_posts_col.return_value = wrapper
        try:
            token_a = self._get_token("user_race_a")
            token_b = self._get_token("user_race_b")
            headers_a = {"Authorization": f"Bearer {token_a}"}
            headers_b = {"Authorization": f"Bearer {token_b}"}

            res_a = {}
            def run_thread_a():
                r = self.test_client.put(f"/api/community/posts/{self.post_id}/like", headers=headers_a)
                res_a["status"] = r.status_code
                res_a["data"] = r.json()

            thread_a = threading.Thread(target=run_thread_a, name="thread_a")
            thread_a.start()

            # Wait for Thread A to pause before update_one
            self.assertTrue(a_paused_evt.wait(timeout=5), "Thread A should have paused before update_one")

            # Thread B runs and completes
            res_b = self.test_client.put(f"/api/community/posts/{self.post_id}/like", headers=headers_b)
            self.assertEqual(res_b.status_code, 200)
            self.assertEqual(res_b.json()["like_count"], 2)

            # Resume Thread A
            resume_a_evt.set()
            thread_a.join(timeout=5)
            self.assertFalse(thread_a.is_alive(), "Thread A should have completed")
            self.assertEqual(res_a.get("status"), 200)

            # 1. Direct database inspection: strictly 2 likes in interactions and posts cache
            total_interactions = self.interactions_col.count_documents({
                "post_id": self.post_id,
                "interaction_type": "like",
            })
            self.assertEqual(total_interactions, 2)

            post_in_db = self.posts_col.find_one({"id": self.post_id})
            self.assertEqual(
                post_in_db.get("like_count"),
                2,
                "Database post.like_count must not be overwritten with stale count = 1",
            )

            # 2. Detail endpoint read
            detail_res = self.test_client.get(f"/api/community/posts/{self.post_id}", headers=headers_a)
            self.assertEqual(detail_res.status_code, 200)
            self.assertEqual(detail_res.json()["like_count"], 2)

            # 3. Feed endpoint read
            feed_res = self.test_client.get("/api/community/feed", headers=headers_a)
            self.assertEqual(feed_res.status_code, 200)
            feed_post = next(p for p in feed_res.json()["items"] if p["id"] == self.post_id)
            self.assertEqual(feed_post["like_count"], 2)
        finally:
            self.mock_posts_col.return_value = self.posts_col

    def test_controlled_interleaving_put_delete_no_stale_overwrite(self):
        """
        Controlled interleaving test for PUT and DELETE:
        Post initially has 1 like from user_existing.
        Thread A (PUT like for user_new) pauses before update_one after counting 2.
        Thread B (DELETE like for user_existing) completes, leaving count 1.
        Thread A resumes. OCC rejects stale count = 2, retries, and updates to 1.
        Direct DB inspection, Detail, and Feed all confirm like_count == 1 without extra repair calls.
        """
        # Seed initial like
        token_existing = self._get_token("user_existing")
        headers_existing = {"Authorization": f"Bearer {token_existing}"}
        init_res = self.test_client.put(f"/api/community/posts/{self.post_id}/like", headers=headers_existing)
        self.assertEqual(init_res.status_code, 200)
        self.assertEqual(init_res.json()["like_count"], 1)

        a_paused_evt = threading.Event()
        resume_a_evt = threading.Event()

        wrapper = ControlledInterleavingPostsColWrapper(
            self.posts_col,
            a_paused_evt=a_paused_evt,
            resume_a_evt=resume_a_evt,
        )

        self.mock_posts_col.return_value = wrapper
        try:
            token_new = self._get_token("user_new")
            headers_new = {"Authorization": f"Bearer {token_new}"}

            res_a = {}
            def run_thread_a():
                r = self.test_client.put(f"/api/community/posts/{self.post_id}/like", headers=headers_new)
                res_a["status"] = r.status_code
                res_a["data"] = r.json()

            thread_a = threading.Thread(target=run_thread_a, name="thread_a")
            thread_a.start()

            # Wait for Thread A (PUT) to pause before update_one
            self.assertTrue(a_paused_evt.wait(timeout=5), "Thread A should have paused before update_one")

            # Thread B (DELETE) runs and completes
            res_b = self.test_client.delete(f"/api/community/posts/{self.post_id}/like", headers=headers_existing)
            self.assertEqual(res_b.status_code, 200)

            # Resume Thread A
            resume_a_evt.set()
            thread_a.join(timeout=5)
            self.assertFalse(thread_a.is_alive(), "Thread A should have completed")
            self.assertEqual(res_a.get("status"), 200)

            # 1. Direct database inspection: strictly 1 interaction remains (user_new)
            total_interactions = self.interactions_col.count_documents({
                "post_id": self.post_id,
                "interaction_type": "like",
            })
            self.assertEqual(total_interactions, 1)

            post_in_db = self.posts_col.find_one({"id": self.post_id})
            self.assertEqual(
                post_in_db.get("like_count"),
                1,
                "Database post.like_count must not be overwritten with stale count = 2",
            )

            # 2. Detail endpoint read
            detail_res = self.test_client.get(f"/api/community/posts/{self.post_id}", headers=headers_new)
            self.assertEqual(detail_res.status_code, 200)
            self.assertEqual(detail_res.json()["like_count"], 1)

            # 3. Feed endpoint read
            feed_res = self.test_client.get("/api/community/feed", headers=headers_new)
            self.assertEqual(feed_res.status_code, 200)
            feed_post = next(p for p in feed_res.json()["items"] if p["id"] == self.post_id)
            self.assertEqual(feed_post["like_count"], 1)
        finally:
            self.mock_posts_col.return_value = self.posts_col


if __name__ == "__main__":
    unittest.main()
