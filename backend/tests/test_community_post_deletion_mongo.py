"""JCOM-05-11 Post Deletion & Ownership Enforcement MongoDB Integration Tests."""
import os
import uuid
import unittest
from datetime import datetime, timezone
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient
import jwt

os.environ['MONGO_URI'] = os.environ.get('MONGO_URI', 'mongodb://127.0.0.1:27017')
os.environ['DB_NAME'] = 'saman_jcom0511_test_deletion'
os.environ['LOG_AUTH_HEADER'] = '0'

from pymongo import MongoClient
from backend.routers import community as r


def validate_test_target(uri, name):
    from urllib.parse import urlparse
    target = urlparse(uri)
    if target.scheme != "mongodb" or target.hostname not in ("127.0.0.1", "localhost"):
        raise ValueError("Dedicated loopback MongoDB required")
    if not name.startswith("saman_jcom0511_test_"):
        raise ValueError("Independent JCOM0511 test DB required")


def setup_test_indexes(db):
    db.community_posts.create_index(
        [("user_id", 1), ("request_key", 1)],
        unique=True,
        partialFilterExpression={"request_key": {"$type": "string"}},
        name="publish_request_unique"
    )


class CommunityPostDeletionMongoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        validate_test_target(os.environ['MONGO_URI'], os.environ['DB_NAME'])
        cls.client_mongo = MongoClient(os.environ['MONGO_URI'], serverSelectionTimeoutMS=5000)
        cls.db = cls.client_mongo[os.environ['DB_NAME']]

        cls.app = FastAPI()
        cls.app.include_router(r.router)
        cls.client = TestClient(cls.app)

        cls.user_a_id = str(ObjectId())
        cls.user_b_id = str(ObjectId())

        cls.token_a = jwt.encode(
            {"sub": cls.user_a_id, "email": "athlete_a@saman.test", "name": "Athlete A"},
            r.JWT_SECRET,
            algorithm=r.JWT_ALGORITHM,
        )
        cls.token_b = jwt.encode(
            {"sub": cls.user_b_id, "email": "athlete_b@saman.test", "name": "Athlete B"},
            r.JWT_SECRET,
            algorithm=r.JWT_ALGORITHM,
        )

        cls.auth_a = {"Authorization": f"Bearer {cls.token_a}"}
        cls.auth_b = {"Authorization": f"Bearer {cls.token_b}"}

    @classmethod
    def tearDownClass(cls):
        cls.client_mongo.close()

    def setUp(self):
        self.db.users.delete_many({})
        self.db.community_posts.delete_many({})
        self.db.community_comments.delete_many({})
        self.db.community_interactions.delete_many({})
        setup_test_indexes(self.db)

        self.db.users.insert_many([
            {
                "_id": ObjectId(self.user_a_id),
                "email": "athlete_a@saman.test",
                "name": "Athlete A",
                "avatar_url": "/static/avatars/a.jpg",
                "is_verified": True,
            },
            {
                "_id": ObjectId(self.user_b_id),
                "email": "athlete_b@saman.test",
                "name": "Athlete B",
                "avatar_url": "/static/avatars/b.jpg",
                "is_verified": False,
            },
        ])

    def test_author_can_delete_text_post_happy_path(self):
        """User A publishes a post, calls DELETE, post is soft-deleted and removed from feed/detail."""
        key = f"key_del_{uuid.uuid4().hex[:16]}"
        pub_res = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key}),
            json={
                "type": "text",
                "content": "This post will be deleted soon",
                "privacy": "public",
                "topic": "#KỷLuật",
                "allow_comments": True,
            },
        )
        self.assertEqual(pub_res.status_code, 200)
        post_id = pub_res.json()["id"]

        # 1. Detail returns 200 before deletion
        detail_before = self.client.get(f"/api/community/posts/{post_id}", headers=self.auth_a)
        self.assertEqual(detail_before.status_code, 200)

        # 2. Feed contains post before deletion
        feed_before = self.client.get("/api/community/feed?tab=for_you", headers=self.auth_a)
        self.assertEqual(feed_before.status_code, 200)
        feed_ids_before = [p["id"] for p in feed_before.json().get("items", [])]
        self.assertIn(post_id, feed_ids_before)

        # 3. User A deletes their own post
        del_res = self.client.delete(f"/api/community/posts/{post_id}", headers=self.auth_a)
        self.assertEqual(del_res.status_code, 200)
        self.assertEqual(del_res.json(), {"success": True, "post_id": post_id})

        # 4. Detail returns 404 after deletion
        detail_after = self.client.get(f"/api/community/posts/{post_id}", headers=self.auth_a)
        self.assertEqual(detail_after.status_code, 404)

        # 5. Feed does not contain deleted post
        feed_after = self.client.get("/api/community/feed?tab=for_you", headers=self.auth_a)
        self.assertEqual(feed_after.status_code, 200)
        feed_ids_after = [p["id"] for p in feed_after.json().get("items", [])]
        self.assertNotIn(post_id, feed_ids_after)

        # 6. Verify MongoDB document has is_deleted: True and deleted_at
        db_doc = self.db.community_posts.find_one({"_id": ObjectId(post_id)})
        self.assertIsNotNone(db_doc)
        self.assertTrue(db_doc.get("is_deleted"))
        self.assertIn("deleted_at", db_doc)

    def test_ownership_protection_non_author_forbidden(self):
        """User B attempts to delete User A's post, backend rejects with HTTP 403 Forbidden."""
        key = f"key_photo_{uuid.uuid4().hex[:16]}"
        pub_res = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key}),
            json={
                "type": "photo",
                "content": "A's private victory photo",
                "photo_urls": ["/static/community/photo_a.jpg"],
                "privacy": "public",
                "topic": "#BữaĂn",
                "allow_comments": True,
            },
        )
        self.assertEqual(pub_res.status_code, 200)
        post_id = pub_res.json()["id"]

        # User B attempts to DELETE User A's post
        del_res = self.client.delete(f"/api/community/posts/{post_id}", headers=self.auth_b)
        self.assertEqual(del_res.status_code, 403)
        self.assertEqual(del_res.json()["detail"], "community_delete_forbidden_not_author")

        # Verify DB document is intact and NOT deleted
        db_doc = self.db.community_posts.find_one({"_id": ObjectId(post_id)})
        self.assertIsNotNone(db_doc)
        self.assertNotEqual(db_doc.get("is_deleted"), True)

        # User A still sees the post
        detail_res = self.client.get(f"/api/community/posts/{post_id}", headers=self.auth_a)
        self.assertEqual(detail_res.status_code, 200)

    def test_delete_nonexistent_or_already_deleted_returns_404(self):
        """Calling DELETE on non-existent or already deleted post returns HTTP 404."""
        # 1. Non-existent post ID
        fake_id = str(ObjectId())
        res1 = self.client.delete(f"/api/community/posts/{fake_id}", headers=self.auth_a)
        self.assertEqual(res1.status_code, 404)

        # 2. Existing post deleted, then deleted a second time
        key = f"key_double_{uuid.uuid4().hex[:16]}"
        pub_res = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key}),
            json={
                "type": "text",
                "content": "Double delete target",
                "privacy": "public",
                "topic": "#KỷLuật",
                "allow_comments": True,
            },
        )
        post_id = pub_res.json()["id"]

        # First delete succeeds
        res_del1 = self.client.delete(f"/api/community/posts/{post_id}", headers=self.auth_a)
        self.assertEqual(res_del1.status_code, 200)

        # Second delete on same post returns 404
        res_del2 = self.client.delete(f"/api/community/posts/{post_id}", headers=self.auth_a)
        self.assertEqual(res_del2.status_code, 404)

    def test_author_can_delete_qa_post(self):
        """User A creates a Q&A question post, then successfully deletes it."""
        key = f"key_qa_{uuid.uuid4().hex[:16]}"
        pub_res = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key}),
            json={
                "type": "qa",
                "title": "Should I take creatine before or after workouts?",
                "body": "Looking for advice on optimal timing for recovery.",
                "topic": "Dinh dưỡng",
                "privacy": "public",
            },
        )
        self.assertEqual(pub_res.status_code, 200)
        qa_id = pub_res.json()["id"]

        # User A deletes QA post
        del_res = self.client.delete(f"/api/community/posts/{qa_id}", headers=self.auth_a)
        self.assertEqual(del_res.status_code, 200)
        self.assertEqual(del_res.json(), {"success": True, "post_id": qa_id})

        # Detail returns 404
        detail_res = self.client.get(f"/api/community/posts/{qa_id}", headers=self.auth_a)
        self.assertEqual(detail_res.status_code, 404)


if __name__ == "__main__":
    unittest.main()

