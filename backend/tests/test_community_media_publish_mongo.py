"""JCOM-05-10 Single Photo Post publication and media contract tests."""
import os
import io
import uuid
import unittest
from datetime import datetime, timezone, timedelta
from unittest.mock import patch
from PIL import Image

os.environ['MONGO_URI'] = os.environ.get('MONGO_URI', 'mongodb://127.0.0.1:27017')
os.environ['DB_NAME'] = 'saman_jcom0510_test_import'
os.environ['LOG_AUTH_HEADER'] = '0'

from pymongo import MongoClient
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient
import jwt

from backend.routers import community as r


def validate_test_target(uri, name):
    from urllib.parse import urlparse
    target = urlparse(uri)
    if target.scheme != "mongodb" or target.hostname not in ("127.0.0.1", "localhost"):
        raise ValueError("Dedicated loopback MongoDB required")
    if not name.startswith("saman_jcom0510_test_"):
        raise ValueError("Independent JCOM0510 test DB required")


def setup_test_indexes(db):
    db.community_posts.create_index(
        [("user_id", 1), ("request_key", 1)],
        unique=True,
        partialFilterExpression={"request_key": {"$type": "string"}},
        name="publish_request_unique"
    )


def create_test_image_bytes(format="PNG", size=(64, 64), color="blue") -> bytes:
    buf = io.BytesIO()
    img = Image.new("RGB", size, color=color)
    img.save(buf, format=format)
    return buf.getvalue()


class CommunityMediaPublishMongoTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.name = 'saman_jcom0510_test_' + uuid.uuid4().hex
        uri = os.environ['MONGO_URI']
        validate_test_target(uri, cls.name)
        cls.mongo = MongoClient(uri, serverSelectionTimeoutMS=2000)
        cls.mongo.admin.command('ping')
        cls.db = cls.mongo[cls.name]
        setup_test_indexes(cls.db)
        cls.app = FastAPI()
        cls.app.include_router(r.router)

    @classmethod
    def tearDownClass(cls):
        cls.mongo.close()

    def setUp(self):
        self.a = 'a_' + uuid.uuid4().hex
        self.b = 'b_' + uuid.uuid4().hex
        for uid in [self.a, self.b]:
            self.db.users.insert_one({
                '_id': uid,
                'email': uid + '@example.com',
                'name': 'Athlete ' + uid[:4],
                'password': 'synthetic-private',
                'health_stats': {'weight': 70},
                'is_verified': False
            })
        p = patch.object(r, 'db', self.db)
        p.start()
        self.addCleanup(p.stop)
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)
        self.auth = {
            uid: {
                'Authorization': 'Bearer ' + jwt.encode(
                    {'email': uid + '@example.com', 'exp': datetime.now(timezone.utc) + timedelta(minutes=15)},
                    r.JWT_SECRET,
                    algorithm=r.JWT_ALGORITHM
                )
            } for uid in [self.a, self.b]
        }

    def test_happy_path_upload_and_publish_single_photo(self):
        # 1. User A uploads valid PNG image
        png_bytes = create_test_image_bytes(format="PNG", color="red")
        files = {"file": ("workout_badge.png", png_bytes, "image/png")}
        upload_res = self.client.post("/api/community/media/upload", headers=self.auth[self.a], files=files)
        self.assertEqual(upload_res.status_code, 200)
        upload_data = upload_res.json()
        self.assertIn("media_url", upload_data)
        media_url = upload_data["media_url"]
        self.assertTrue(media_url.startswith("/static/community/"))
        self.assertTrue(media_url.endswith(".png"))

        # Verify static file is readable
        static_res = self.client.get(media_url)
        self.assertEqual(static_res.status_code, 200)
        self.assertEqual(static_res.headers.get("content-type"), "image/png")

        # 2. User A publishes single photo post
        key = uuid.uuid4().hex
        body = {
            "type": "photo",
            "content": "Post with my workout meal snapshot",
            "photo_urls": [media_url],
            "privacy": "public",
            "topic": "#BữaĂn",
            "allow_comments": True,
        }
        publish_res = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth[self.a], **{"X-Idempotency-Key": key}),
            json=body,
        )
        self.assertEqual(publish_res.status_code, 200)
        post_data = publish_res.json()
        self.assertEqual(post_data["type"], "photo")
        self.assertEqual(post_data["caption"], "Post with my workout meal snapshot")
        self.assertEqual(post_data["photo_urls"], [media_url])
        post_id = post_data["id"]

        # 3. Direct DB verification
        db_doc = self.db.community_posts.find_one({"_id": ObjectId(post_id)})
        self.assertIsNotNone(db_doc)
        self.assertEqual(db_doc["type"], "photo")
        self.assertEqual(db_doc["photo_urls"], [media_url])
        self.assertEqual(db_doc["author_id"], self.a)

    def test_validation_size_and_invalid_format(self):
        # 1. Upload fake non-image file
        fake_files = {"file": ("malicious.png", b"this is not an image", "image/png")}
        res = self.client.post("/api/community/media/upload", headers=self.auth[self.a], files=fake_files)
        self.assertEqual(res.status_code, 400)

        # 2. Upload file exceeding 5MB
        huge_bytes = b"0" * (5 * 1024 * 1024 + 10)
        huge_files = {"file": ("oversized.jpg", huge_bytes, "image/jpeg")}
        res_huge = self.client.post("/api/community/media/upload", headers=self.auth[self.a], files=huge_files)
        self.assertEqual(res_huge.status_code, 400)

        # 3. Upload empty file
        empty_files = {"file": ("empty.jpg", b"", "image/jpeg")}
        res_empty = self.client.post("/api/community/media/upload", headers=self.auth[self.a], files=empty_files)
        self.assertEqual(res_empty.status_code, 400)

        # 4. Multi-photo reject (Slice constraint: single photo only)
        key = uuid.uuid4().hex
        multi_body = {
            "type": "photo",
            "content": "Multiple photos attempt",
            "photo_urls": ["/static/community/img1.jpg", "/static/community/img2.jpg"],
            "privacy": "public",
            "topic": "#TậpLuyện",
        }
        multi_res = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth[self.a], **{"X-Idempotency-Key": key}),
            json=multi_body,
        )
        self.assertEqual(multi_res.status_code, 422)

    def test_idempotency_same_key_same_photo(self):
        key = uuid.uuid4().hex
        body = {
            "type": "photo",
            "content": "Idempotent photo post",
            "photo_urls": ["/static/community/single.jpg"],
            "privacy": "public",
            "topic": "#PhụcHồi",
            "allow_comments": True,
        }
        res1 = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth[self.a], **{"X-Idempotency-Key": key}),
            json=body,
        )
        self.assertEqual(res1.status_code, 200)
        post_id1 = res1.json()["id"]

        # Retry with same key and same payload
        res2 = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth[self.a], **{"X-Idempotency-Key": key}),
            json=body,
        )
        self.assertEqual(res2.status_code, 200)
        post_id2 = res2.json()["id"]
        self.assertEqual(post_id1, post_id2)

        # Ensure single document in DB
        matching = list(self.db.community_posts.find({"user_id": self.a, "request_key": key}))
        self.assertEqual(len(matching), 1)

        # Same key with different payload -> 409 Conflict
        conflicting_body = dict(body, content="Changed caption text")
        res3 = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth[self.a], **{"X-Idempotency-Key": key}),
            json=conflicting_body,
        )
        self.assertEqual(res3.status_code, 409)

    def test_audience_followers_only_isolation(self):
        # User A publishes followers_only post
        key = uuid.uuid4().hex
        body = {
            "type": "photo",
            "content": "Secret progress picture",
            "photo_urls": ["/static/community/progress.jpg"],
            "privacy": "followers_only",
            "topic": "#KỷLuật",
            "allow_comments": True,
        }
        pub_res = self.client.post(
            "/api/community/posts",
            headers=dict(self.auth[self.a], **{"X-Idempotency-Key": key}),
            json=body,
        )
        self.assertEqual(pub_res.status_code, 200)
        post_id = pub_res.json()["id"]

        # User B (not following A) cannot read detail (404 fail-closed)
        detail_res_b = self.client.get(f"/api/community/posts/{post_id}", headers=self.auth[self.b])
        self.assertEqual(detail_res_b.status_code, 404)

        # User B cannot see it in Feed
        feed_res_b = self.client.get("/api/community/feed?tab=for_you", headers=self.auth[self.b])
        self.assertEqual(feed_res_b.status_code, 200)
        feed_ids_b = [item["id"] for item in feed_res_b.json().get("items", [])]
        self.assertNotIn(post_id, feed_ids_b)

        # User B follows User A
        follow_res = self.client.put(f"/api/community/authors/{self.a}/follow", headers=self.auth[self.b])
        self.assertEqual(follow_res.status_code, 200)

        # Now User B can view post detail and receive photo_urls
        detail_res_b2 = self.client.get(f"/api/community/posts/{post_id}", headers=self.auth[self.b])
        self.assertEqual(detail_res_b2.status_code, 200)
        self.assertEqual(detail_res_b2.json()["photo_urls"], ["/static/community/progress.jpg"])


if __name__ == "__main__":
    unittest.main()

