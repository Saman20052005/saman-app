"""
Unit and Integration Tests for Saman Community Demo Seeding & Cleaning Script.
Subsystem: Saman Community Demo Seed (seed_community_demo.py).

Covers:
1. `seed_demo_data`: seeds 6 users, 5 active stories, 10 posts (album, meal, workout, Q&A),
   answers, comments, 2 DM conversations + messages; all flagged `is_demo_seed: True`.
2. Idempotency: calling `seed_demo_data` twice produces identical document counts (0 duplicates).
3. Live Read APIs (`TestClient`):
   - `GET /api/community/feed`: returns seeded posts with valid schema.
   - `GET /api/community/stories`: returns seeded stories grouped by author.
   - `GET /api/community/discover`: returns visual grid with seeded photos and trending topics.
4. `clean_demo_data`: purges 100% of demo seeded records (`is_demo_seed: True`)
   while keeping 100% of real user documents (`is_demo_seed != True`) intact.
"""

from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional
import unittest
from unittest.mock import patch

from bson import ObjectId
from fastapi.testclient import TestClient
import jwt

from backend.main import app
from backend.routers import community as community_router_mod
from backend.routers import community_dm as community_dm_mod
from backend.routers.community import JWT_ALGORITHM, JWT_SECRET
from backend.scripts.seed_community_demo import (
    DEMO_COLLECTIONS,
    DEMO_USER_COACH_ID,
    DEMO_USER_GYM_ID,
    DEMO_USER_CHEF_ID,
    DEMO_USER_RUNNER_ID,
    DEMO_USER_YOGA_ID,
    DEMO_USER_NEWBIE_ID,
    clean_demo_data,
    seed_demo_data,
)


# ---------------------------------------------------------------------------
# In-Memory Database Mock matching test_community_ig_phase2.py convention
# ---------------------------------------------------------------------------


class MockDeleteResult:
    def __init__(self, deleted_count: int) -> None:
        self.deleted_count = deleted_count


class MockUpdateResult:
    def __init__(self, matched: int, modified: int, upserted_id: Any = None) -> None:
        self.matched_count = matched
        self.modified_count = modified
        self.upserted_id = upserted_id


class MockCursor:
    def __init__(self, docs: List[Dict[str, Any]]) -> None:
        self._docs = docs
        self._limit: Optional[int] = None

    def sort(self, key_or_list: Any, direction: Optional[int] = None) -> "MockCursor":
        return self

    def limit(self, n: int) -> "MockCursor":
        self._limit = n
        return self

    def __iter__(self):
        docs = self._docs[: self._limit] if self._limit is not None else self._docs
        return iter([copy.deepcopy(d) for d in docs])


def _norm_val(v: Any) -> Any:
    if isinstance(v, datetime):
        return v.replace(tzinfo=timezone.utc) if v.tzinfo is None else v.astimezone(timezone.utc)
    return v


def _match_field(doc_val: Any, exists: bool, cond: Any) -> bool:
    if isinstance(cond, dict) and any(k.startswith("$") for k in cond):
        for op, expected in cond.items():
            if op == "$exists":
                if bool(exists) != bool(expected):
                    return False
            elif op == "$ne":
                if exists and doc_val == expected:
                    return False
            elif op == "$in":
                if not exists:
                    if None not in expected:
                        return False
                elif isinstance(doc_val, list):
                    if not any(v in expected for v in doc_val):
                        return False
                elif doc_val not in expected and str(doc_val) not in [str(x) for x in expected if x is not None]:
                    return False
            elif op == "$nin":
                if exists:
                    if isinstance(doc_val, list):
                        if any(v in expected for v in doc_val):
                            return False
                    elif doc_val in expected or str(doc_val) in [str(x) for x in expected]:
                        return False
            elif op == "$gt":
                if not exists or doc_val is None or _norm_val(doc_val) <= _norm_val(expected):
                    return False
            elif op == "$gte":
                if not exists or doc_val is None or _norm_val(doc_val) < _norm_val(expected):
                    return False
            elif op == "$lt":
                if not exists or doc_val is None or _norm_val(doc_val) >= _norm_val(expected):
                    return False
            elif op == "$lte":
                if not exists or doc_val is None or _norm_val(doc_val) > _norm_val(expected):
                    return False
        return True
    if not exists:
        return cond is None
    if isinstance(doc_val, list) and not isinstance(cond, list):
        return cond in doc_val or str(cond) in [str(x) for x in doc_val]
    if isinstance(doc_val, ObjectId) or isinstance(cond, ObjectId):
        return str(doc_val) == str(cond)
    return doc_val == cond


def _matches_query(doc: Dict[str, Any], query: Optional[Dict[str, Any]]) -> bool:
    if not query:
        return True
    for k, v in query.items():
        if k == "$and":
            if not all(_matches_query(doc, sub) for sub in v):
                return False
        elif k == "$or":
            if not any(_matches_query(doc, sub) for sub in v):
                return False
        elif "." in k:
            parts = k.split(".")
            cur = doc
            exists = True
            for part in parts:
                if isinstance(cur, dict) and part in cur:
                    cur = cur[part]
                else:
                    exists = False
                    cur = None
                    break
            if not _match_field(cur, exists, v):
                return False
        else:
            exists = k in doc
            val = doc.get(k)
            if not _match_field(val, exists, v):
                return False
    return True


class MockCollection:
    def __init__(self, name: str) -> None:
        self.name = name
        self.docs: List[Dict[str, Any]] = []

    def index_information(self) -> Dict[str, Any]:
        return {}

    def find_one(self, query: Optional[Dict[str, Any]] = None) -> Optional[Dict[str, Any]]:
        for d in self.docs:
            if _matches_query(d, query):
                return copy.deepcopy(d)
        return None

    def find(self, query: Optional[Dict[str, Any]] = None) -> MockCursor:
        matched = [d for d in self.docs if _matches_query(d, query)]
        return MockCursor(matched)

    def count_documents(self, query: Optional[Dict[str, Any]] = None) -> int:
        return sum(1 for d in self.docs if _matches_query(d, query))

    def insert_one(self, doc: Dict[str, Any]) -> Any:
        d = copy.deepcopy(doc)
        if "_id" not in d:
            d["_id"] = ObjectId()
        self.docs.append(d)
        return type("InsertResult", (), {"inserted_id": d["_id"]})()

    def update_one(
        self,
        query: Dict[str, Any],
        update: Dict[str, Any],
        upsert: bool = False,
    ) -> MockUpdateResult:
        for idx, d in enumerate(self.docs):
            if _matches_query(d, query):
                target = self.docs[idx]
                if "$set" in update:
                    for k, v in update["$set"].items():
                        target[k] = copy.deepcopy(v)
                if "$inc" in update:
                    for k, v in update["$inc"].items():
                        target[k] = target.get(k, 0) + v
                return MockUpdateResult(1, 1)

        if upsert:
            new_doc = copy.deepcopy(query)
            # Flatten query to avoid dot-notation keys in base doc
            clean_new_doc: Dict[str, Any] = {}
            for qk, qv in new_doc.items():
                if not qk.startswith("$") and "." not in qk:
                    clean_new_doc[qk] = qv
            if "$setOnInsert" in update:
                clean_new_doc.update(copy.deepcopy(update["$setOnInsert"]))
            if "$set" in update:
                clean_new_doc.update(copy.deepcopy(update["$set"]))
            if "_id" not in clean_new_doc:
                clean_new_doc["_id"] = ObjectId()
            self.docs.append(clean_new_doc)
            return MockUpdateResult(0, 0, clean_new_doc["_id"])

        return MockUpdateResult(0, 0)

    def delete_one(self, query: Dict[str, Any]) -> MockDeleteResult:
        for idx, d in enumerate(self.docs):
            if _matches_query(d, query):
                del self.docs[idx]
                return MockDeleteResult(1)
        return MockDeleteResult(0)

    def delete_many(self, query: Dict[str, Any]) -> MockDeleteResult:
        init_len = len(self.docs)
        self.docs = [d for d in self.docs if not _matches_query(d, query)]
        return MockDeleteResult(init_len - len(self.docs))

    def aggregate(self, pipeline: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        # Lightweight in-memory aggregation support for $match + $group
        cur_docs = self.docs
        for stage in pipeline:
            if "$match" in stage:
                cur_docs = [d for d in cur_docs if _matches_query(d, stage["$match"])]
            elif "$group" in stage:
                grp = stage["$group"]
                key_field = grp["_id"].lstrip("$")
                grouped: Dict[str, int] = {}
                for d in cur_docs:
                    key_val = str(d.get(key_field, ""))
                    if key_val:
                        grouped[key_val] = grouped.get(key_val, 0) + 1
                return [{"_id": k, "count": v} for k, v in grouped.items()]
        return []


class InMemoryDatabase:
    def __init__(self) -> None:
        self.collections: Dict[str, MockCollection] = {}

    def __getitem__(self, name: str) -> MockCollection:
        if name not in self.collections:
            self.collections[name] = MockCollection(name)
        return self.collections[name]


# ---------------------------------------------------------------------------
# Test Suite
# ---------------------------------------------------------------------------


class TestSeedCommunityDemo(unittest.TestCase):
    def setUp(self) -> None:
        self.db = InMemoryDatabase()
        self.client = TestClient(app)

        # Seed a real user to test safety / non-destruction
        self.real_user_id = "real_user_athlete_01"
        self.real_user_email = "real.athlete@saman.app"
        self.db["users"].insert_one({
            "_id": self.real_user_id,
            "id": self.real_user_id,
            "email": self.real_user_email,
            "name": "Nguyễn Văn Thật",
            "full_name": "Nguyễn Văn Thật",
            "is_verified": False,
            "created_at": datetime.now(timezone.utc),
            "is_demo_seed": False,  # REAL USER
        })
        self.db["community_posts"].insert_one({
            "_id": "real_post_999",
            "id": "real_post_999",
            "type": "photo",
            "author_id": self.real_user_id,
            "caption": "Bài viết thật của người dùng thật!",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "is_demo_seed": False,  # REAL POST
        })

        self.token = jwt.encode(
            {"email": self.real_user_email, "user_id": self.real_user_id, "name": "Nguyễn Văn Thật"},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )
        self.headers = {"Authorization": f"Bearer {self.token}"}

    def test_01_seed_demo_data_counts_and_flag(self) -> None:
        """Test 1: seed_demo_data creates 6 users, 5 active stories, 10 posts, 2 DMs with is_demo_seed: True."""
        stats = seed_demo_data(self.db, for_user_id=self.real_user_id)

        # Verify users
        demo_users = list(self.db["users"].find({"is_demo_seed": True}))
        self.assertEqual(len(demo_users), 6)
        user_ids = {u["_id"] for u in demo_users}
        self.assertIn(DEMO_USER_COACH_ID, user_ids)
        self.assertIn(DEMO_USER_GYM_ID, user_ids)
        self.assertIn(DEMO_USER_CHEF_ID, user_ids)
        self.assertIn(DEMO_USER_RUNNER_ID, user_ids)
        self.assertIn(DEMO_USER_YOGA_ID, user_ids)
        self.assertIn(DEMO_USER_NEWBIE_ID, user_ids)

        # Verify stories (all active > now)
        now = datetime.now(timezone.utc)
        stories = list(self.db["community_stories"].find({"is_demo_seed": True}))
        self.assertEqual(len(stories), 5)
        for s in stories:
            self.assertTrue(s["is_demo_seed"])
            self.assertGreater(s["expires_at"], now)

        # Verify 10 posts with diverse archetypes
        posts = list(self.db["community_posts"].find({"is_demo_seed": True}))
        self.assertEqual(len(posts), 10)
        types = {p["type"] for p in posts}
        self.assertIn("photo", types)
        self.assertIn("meal", types)
        self.assertIn("workout", types)
        self.assertIn("qa", types)

        # Check album post has 4 photos
        post1 = self.db["community_posts"].find_one({"_id": "demo_post_01"})
        self.assertIsNotNone(post1)
        self.assertEqual(len(post1["photo_urls"]), 4)

        # Check Q&A post has answers
        post4 = self.db["community_posts"].find_one({"_id": "demo_post_04"})
        self.assertIsNotNone(post4)
        self.assertIn("qa_info", post4)
        answers = list(self.db["community_answers"].find({"question_id": "demo_post_04"}))
        self.assertEqual(len(answers), 2)
        for a in answers:
            self.assertTrue(a["is_demo_seed"])

        # Check DM conversations & messages exist
        convs = list(self.db["community_conversations"].find({"is_demo_seed": True}))
        # 2 base conversations + 2 targeted conversations with real_user
        self.assertGreaterEqual(len(convs), 2)
        messages = list(self.db["community_messages"].find({"is_demo_seed": True}))
        self.assertGreaterEqual(len(messages), 4)

    def test_02_idempotency_double_run(self) -> None:
        """Test 2: Calling seed_demo_data twice produces 0 duplicate records."""
        stats1 = seed_demo_data(self.db, for_user_id=self.real_user_id)
        count_users_1 = self.db["users"].count_documents({"is_demo_seed": True})
        count_stories_1 = self.db["community_stories"].count_documents({"is_demo_seed": True})
        count_posts_1 = self.db["community_posts"].count_documents({"is_demo_seed": True})
        count_convs_1 = self.db["community_conversations"].count_documents({"is_demo_seed": True})
        count_msgs_1 = self.db["community_messages"].count_documents({"is_demo_seed": True})

        # Run 2nd time
        stats2 = seed_demo_data(self.db, for_user_id=self.real_user_id)
        count_users_2 = self.db["users"].count_documents({"is_demo_seed": True})
        count_stories_2 = self.db["community_stories"].count_documents({"is_demo_seed": True})
        count_posts_2 = self.db["community_posts"].count_documents({"is_demo_seed": True})
        count_convs_2 = self.db["community_conversations"].count_documents({"is_demo_seed": True})
        count_msgs_2 = self.db["community_messages"].count_documents({"is_demo_seed": True})

        self.assertEqual(count_users_1, count_users_2)
        self.assertEqual(count_stories_1, count_stories_2)
        self.assertEqual(count_posts_1, count_posts_2)
        self.assertEqual(count_convs_1, count_convs_2)
        self.assertEqual(count_msgs_1, count_msgs_2)

    def test_03_live_api_read_seeded_data(self) -> None:
        """Test 3: Calling real API endpoints reads seeded data smoothly without schema errors."""
        seed_demo_data(self.db, for_user_id=self.real_user_id)

        with patch.object(community_router_mod, "db", self.db), \
             patch.object(community_dm_mod, "db", self.db):

            # 1. Feed API
            res_feed = self.client.get("/api/community/feed", headers=self.headers)
            self.assertEqual(res_feed.status_code, 200, res_feed.text)
            feed_data = res_feed.json()
            self.assertIn("items", feed_data)
            # At least 10 demo posts + 1 real post
            self.assertGreaterEqual(len(feed_data["items"]), 10)

            # 2. Stories API
            res_stories = self.client.get("/api/community/stories", headers=self.headers)
            self.assertEqual(res_stories.status_code, 200, res_stories.text)
            stories_data = res_stories.json()
            self.assertIn("items", stories_data)
            self.assertGreaterEqual(len(stories_data["items"]), 3)

            # 3. Discover API
            res_disc = self.client.get("/api/community/discover", headers=self.headers)
            self.assertEqual(res_disc.status_code, 200, res_disc.text)
            disc_data = res_disc.json()
            self.assertIn("grid_items", disc_data)
            self.assertIn("trending_topics", disc_data)
            self.assertIn("recommended_creators", disc_data)
            self.assertGreaterEqual(len(disc_data["trending_topics"]), 3)
            self.assertGreaterEqual(len(disc_data["recommended_creators"]), 3)

            # 4. DM Conversations API
            res_dm = self.client.get("/api/community/dm/conversations", headers=self.headers)
            self.assertEqual(res_dm.status_code, 200, res_dm.text)
            dm_data = res_dm.json()
            self.assertIn("items", dm_data)
            # Should have the 2 seeded conversations for this user
            self.assertEqual(len(dm_data["items"]), 2)

    def test_04_clean_demo_data_preserves_real_data(self) -> None:
        """Test 4: clean_demo_data purges 100% demo documents but preserves 100% real user data."""
        seed_demo_data(self.db, for_user_id=self.real_user_id)

        # Pre-clean check
        self.assertEqual(self.db["users"].count_documents({"is_demo_seed": True}), 6)
        self.assertEqual(self.db["community_posts"].count_documents({"is_demo_seed": True}), 10)
        self.assertEqual(self.db["users"].count_documents({"_id": self.real_user_id}), 1)
        self.assertEqual(self.db["community_posts"].count_documents({"_id": "real_post_999"}), 1)

        # Perform Clean
        deleted_stats = clean_demo_data(self.db)
        total_deleted = sum(deleted_stats.values())
        self.assertGreater(total_deleted, 0)

        # Post-clean check: ALL demo seed documents purged
        for coll_name in DEMO_COLLECTIONS:
            remaining_demo = self.db[coll_name].count_documents({"is_demo_seed": True})
            self.assertEqual(remaining_demo, 0, f"Collection {coll_name} still has demo documents!")

        # Verify Real User and Real Post are 100% PRESERVED
        real_user = self.db["users"].find_one({"_id": self.real_user_id})
        self.assertIsNotNone(real_user)
        self.assertEqual(real_user["name"], "Nguyễn Văn Thật")

        real_post = self.db["community_posts"].find_one({"_id": "real_post_999"})
        self.assertIsNotNone(real_post)
        self.assertEqual(real_post["caption"], "Bài viết thật của người dùng thật!")


if __name__ == "__main__":
    unittest.main()
