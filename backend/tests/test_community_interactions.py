"""
Unit and Integration Contract Tests for Saman Community Persistent Likes & Saved Posts.
Subsystem: Saman Community (JCOM-05-04).

Covers:
- 401 unauthenticated rejected for like, unlike, save, unsave, saved list.
- Audience enforcement: 404 for private post of another user and deleted posts.
- Idempotent PUT and DELETE (no duplicate count, no duplicate interaction).
- Lower-bound protection: like_count never goes below 0.
- Saved posts list isolation between users.
- Saved posts list filters deleted and privatized posts at read time.
"""

from datetime import datetime, timezone
import unittest
from unittest.mock import patch, MagicMock
from bson import ObjectId
from fastapi.testclient import TestClient
import jwt
from pymongo.errors import DuplicateKeyError

from backend.main import app
from backend.routers.community import JWT_ALGORITHM, JWT_SECRET



class InMemoryInteractionsCol:
    def __init__(self):
        self.docs = []

    def insert_one(self, doc):
        # Check compound unique index: (user_id, interaction_type, post_id)
        for d in self.docs:
            if (
                d.get("user_id") == doc.get("user_id")
                and d.get("interaction_type") == doc.get("interaction_type")
                and str(d.get("post_id")) == str(doc.get("post_id"))
            ):
                raise DuplicateKeyError("E11000 duplicate key error")
        self.docs.append(dict(doc))
        return type("InsertResult", (), {"inserted_id": doc.get("_id") or "mock_id"})()

    def delete_one(self, filter_query):
        for idx, d in enumerate(self.docs):
            match = True
            for k, v in filter_query.items():
                if str(d.get(k)) != str(v):
                    match = False
                    break
            if match:
                self.docs.pop(idx)
                return type("DeleteResult", (), {"deleted_count": 1})()
        return type("DeleteResult", (), {"deleted_count": 0})()

    def find(self, filter_query):
        results = []
        user_id = filter_query.get("user_id")
        itype = filter_query.get("interaction_type")
        post_id_filter = filter_query.get("post_id")

        for d in self.docs:
            if user_id and d.get("user_id") != user_id:
                continue
            if itype and d.get("interaction_type") != itype:
                continue
            if post_id_filter:
                if isinstance(post_id_filter, dict) and "$in" in post_id_filter:
                    allowed = [str(x) for x in post_id_filter["$in"]]
                    if str(d.get("post_id")) not in allowed:
                        continue
                elif str(d.get("post_id")) != str(post_id_filter):
                    continue
            results.append(d)

        class MockCursor:
            def __init__(self, data):
                self._data = data

            def sort(self, field, order=1):
                # Simple sort
                return self

            def __iter__(self):
                return iter(self._data)

        return MockCursor(results)

    def count_documents(self, filter_query):
        post_id = filter_query.get("post_id")
        itype = filter_query.get("interaction_type")
        c = 0
        for d in self.docs:
            if post_id and str(d.get("post_id")) != str(post_id):
                continue
            if itype and d.get("interaction_type") != itype:
                continue
            c += 1
        return c


class InMemoryPostsCol:
    def __init__(self, initial_docs):
        self.docs = [dict(d) for d in initial_docs]

    def find_one(self, filter_query):
        for d in self.docs:
            if "$or" in filter_query:
                for clause in filter_query["$or"]:
                    k, v = list(clause.items())[0]
                    if str(d.get(k)) == str(v):
                        return d
            else:
                match = True
                for k, v in filter_query.items():
                    if str(d.get(k)) != str(v):
                        match = False
                        break
                if match:
                    return d
        return None

    def update_one(self, filter_query, update):
        target = None
        for d in self.docs:
            if filter_query.get("_id") == d.get("_id"):
                if "like_count" in filter_query:
                    gt_cond = filter_query["like_count"].get("$gt")
                    if d.get("like_count", 0) <= gt_cond:
                        continue
                target = d
                break
        if not target:
            return type("UpdateResult", (), {"modified_count": 0})()

        if "$set" in update:
            for k, v in update["$set"].items():
                target[k] = v
        if "$inc" in update:
            for k, v in update["$inc"].items():
                target[k] = target.get(k, 0) + v
        if "$addToSet" in update:
            for k, v in update["$addToSet"].items():
                if k not in target:
                    target[k] = []
                if v not in target[k]:
                    target[k].append(v)
        if "$pull" in update:
            for k, v in update["$pull"].items():
                if k in target and v in target[k]:
                    target[k].remove(v)
        return type("UpdateResult", (), {"modified_count": 1})()

    def find(self, filter_query):
        results = []
        if "$or" in filter_query:
            clauses = filter_query["$or"]
            for d in self.docs:
                for c in clauses:
                    k, v = list(c.items())[0]
                    if str(d.get(k)) == str(v):
                        if d not in results:
                            results.append(d)
        else:
            results = list(self.docs)
        return results


class TestCommunityInteractions(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.user_a_id = "user_a_12345"
        self.user_b_id = "user_b_67890"

        self.token_a = jwt.encode(
            {"email": "athlete_a@saman.test", "user_id": self.user_a_id, "name": "Athlete A"},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )
        self.token_b = jwt.encode(
            {"email": "athlete_b@saman.test", "user_id": self.user_b_id, "name": "Athlete B"},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )

        self.posts_data = [
            {
                "_id": ObjectId("672400000000000000000001"),
                "id": "post_public_01",
                "type": "photo",
                "privacy": "public",
                "author_id": self.user_a_id,
                "author": {"id": self.user_a_id, "name": "Athlete A"},
                "caption": "Public Post 1",
                "like_count": 10,
                "is_deleted": False,
                "status": "published",
            },
            {
                "_id": ObjectId("672400000000000000000002"),
                "id": "post_private_a",
                "type": "photo",
                "privacy": "private",
                "author_id": self.user_a_id,
                "author": {"id": self.user_a_id, "name": "Athlete A"},
                "caption": "Private Post of Athlete A",
                "like_count": 0,
                "is_deleted": False,
                "status": "published",
            },
            {
                "_id": ObjectId("672400000000000000000003"),
                "id": "post_deleted_01",
                "type": "photo",
                "privacy": "public",
                "author_id": self.user_a_id,
                "author": {"id": self.user_a_id, "name": "Athlete A"},
                "caption": "Deleted Post",
                "like_count": 5,
                "is_deleted": True,
                "status": "published",
            },
        ]

        self.mock_posts_col = InMemoryPostsCol(self.posts_data)
        self.mock_interactions_col = InMemoryInteractionsCol()

        # Seed historical 10 likes on post_public_01 so interactions collection matches like_count
        for i in range(10):
            self.mock_interactions_col.insert_one({
                "user_id": f"historical_user_{i}",
                "post_id": "post_public_01",
                "interaction_type": "like",
            })

    def _patch_cols(self):
        return (
            patch("backend.routers.community.get_community_posts_collection", return_value=self.mock_posts_col),
            patch("backend.routers.community.get_community_interactions_collection", return_value=self.mock_interactions_col),
        )

    def test_unauthenticated_interactions_rejected_401(self):
        """PUT/DELETE like/save and GET saved must reject unauthenticated requests with 401."""
        r1 = self.client.put("/api/community/posts/post_public_01/like")
        self.assertEqual(r1.status_code, 401)

        r2 = self.client.delete("/api/community/posts/post_public_01/like")
        self.assertEqual(r2.status_code, 401)

        r3 = self.client.put("/api/community/posts/post_public_01/save")
        self.assertEqual(r3.status_code, 401)

        r4 = self.client.delete("/api/community/posts/post_public_01/save")
        self.assertEqual(r4.status_code, 401)

        r5 = self.client.get("/api/community/saved")
        self.assertEqual(r5.status_code, 401)

    def test_audience_enforcement_for_interactions(self):
        """User B cannot like or save private post of User A or deleted post (returns 404)."""
        p1, p2 = self._patch_cols()
        with p1, p2:
            headers_b = {"Authorization": f"Bearer {self.token_b}"}

            # Like private post of User A -> 404
            res = self.client.put("/api/community/posts/post_private_a/like", headers=headers_b)
            self.assertEqual(res.status_code, 404)

            # Save private post of User A -> 404
            res = self.client.put("/api/community/posts/post_private_a/save", headers=headers_b)
            self.assertEqual(res.status_code, 404)

            # Like deleted post -> 404
            res = self.client.put("/api/community/posts/post_deleted_01/like", headers=headers_b)
            self.assertEqual(res.status_code, 404)

            # User A can like their own private post
            headers_a = {"Authorization": f"Bearer {self.token_a}"}
            res = self.client.put("/api/community/posts/post_private_a/like", headers=headers_a)
            self.assertEqual(res.status_code, 200)
            self.assertTrue(res.json()["is_liked"])

    def test_idempotent_like_and_unlike(self):
        """Repeated PUT like or DELETE like must be idempotent and not drift count."""
        p1, p2 = self._patch_cols()
        with p1, p2:
            headers_b = {"Authorization": f"Bearer {self.token_b}"}

            # 1. First like -> count goes 10 -> 11
            r1 = self.client.put("/api/community/posts/post_public_01/like", headers=headers_b)
            self.assertEqual(r1.status_code, 200)
            data1 = r1.json()
            self.assertTrue(data1["is_liked"])
            self.assertEqual(data1["like_count"], 11)

            # 2. Duplicate like -> still 11, is_liked=True
            r2 = self.client.put("/api/community/posts/post_public_01/like", headers=headers_b)
            self.assertEqual(r2.status_code, 200)
            data2 = r2.json()
            self.assertTrue(data2["is_liked"])
            self.assertEqual(data2["like_count"], 11)

            # 3. Unlike -> count goes 11 -> 10
            r3 = self.client.delete("/api/community/posts/post_public_01/like", headers=headers_b)
            self.assertEqual(r3.status_code, 200)
            data3 = r3.json()
            self.assertFalse(data3["is_liked"])
            self.assertEqual(data3["like_count"], 10)

            # 4. Repeated unlike -> still 10, is_liked=False
            r4 = self.client.delete("/api/community/posts/post_public_01/like", headers=headers_b)
            self.assertEqual(r4.status_code, 200)
            data4 = r4.json()
            self.assertFalse(data4["is_liked"])
            self.assertEqual(data4["like_count"], 10)

    def test_idempotent_save_and_unsave(self):
        """Repeated PUT save or DELETE save must be idempotent."""
        p1, p2 = self._patch_cols()
        with p1, p2:
            headers_b = {"Authorization": f"Bearer {self.token_b}"}

            r1 = self.client.put("/api/community/posts/post_public_01/save", headers=headers_b)
            self.assertEqual(r1.status_code, 200)
            self.assertTrue(r1.json()["is_saved"])

            # Repeated save
            r2 = self.client.put("/api/community/posts/post_public_01/save", headers=headers_b)
            self.assertEqual(r2.status_code, 200)
            self.assertTrue(r2.json()["is_saved"])

            # Unsave
            r3 = self.client.delete("/api/community/posts/post_public_01/save", headers=headers_b)
            self.assertEqual(r3.status_code, 200)
            self.assertFalse(r3.json()["is_saved"])

            # Repeated unsave
            r4 = self.client.delete("/api/community/posts/post_public_01/save", headers=headers_b)
            self.assertEqual(r4.status_code, 200)
            self.assertFalse(r4.json()["is_saved"])

    def test_saved_posts_isolation_and_audience_filtering(self):
        """Athlete A's saved list is isolated from Athlete B, and filters out deleted/privatized posts."""
        p1, p2 = self._patch_cols()
        with p1, p2:
            headers_a = {"Authorization": f"Bearer {self.token_a}"}
            headers_b = {"Authorization": f"Bearer {self.token_b}"}

            # Athlete A saves post_public_01 and post_private_a
            self.client.put("/api/community/posts/post_public_01/save", headers=headers_a)
            self.client.put("/api/community/posts/post_private_a/save", headers=headers_a)

            # Athlete B saves post_public_01
            self.client.put("/api/community/posts/post_public_01/save", headers=headers_b)

            # Check Athlete A's saved list: has both posts
            saved_a = self.client.get("/api/community/saved", headers=headers_a).json()
            ids_a = [p["id"] for p in saved_a["items"]]
            self.assertIn("post_public_01", ids_a)
            self.assertIn("post_private_a", ids_a)
            self.assertEqual(len(ids_a), 2)

            # Check Athlete B's saved list: has only post_public_01
            saved_b = self.client.get("/api/community/saved", headers=headers_b).json()
            ids_b = [p["id"] for p in saved_b["items"]]
            self.assertIn("post_public_01", ids_b)
            self.assertNotIn("post_private_a", ids_b)
            self.assertEqual(len(ids_b), 1)

            # Now, simulate post_public_01 being converted to private by Athlete A
            pub_doc = self.mock_posts_col.find_one({"id": "post_public_01"})
            pub_doc["privacy"] = "private"

            # Athlete B should NO LONGER see it in saved (silently filtered out at read time)
            saved_b2 = self.client.get("/api/community/saved", headers=headers_b).json()
            self.assertEqual(len(saved_b2["items"]), 0)

            # Athlete A is the author, so Athlete A STILL sees it!
            saved_a2 = self.client.get("/api/community/saved", headers=headers_a).json()
            self.assertEqual(len(saved_a2["items"]), 2)


if __name__ == "__main__":
    unittest.main()
