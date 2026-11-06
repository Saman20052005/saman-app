"""JCOM-05-13 Community Subsystem Full Lifecycle E2E Integration Acceptance Test.

Validates the complete 7-stage interaction sequence between User A and User B:
- A1. Diverse Publishing: Text, Q&A, Activity Snapshot, Single Photo (via /media/upload).
- A2. Idempotency Protection: Re-publishing with same X-Idempotency-Key returns same post without duplication.
- B1. Audience Privacy & Follow Lifecycle:
      User A publishes followers_only post -> User B cannot view (feed excluded, detail 404) ->
      User B follows User A -> User B views post in feed & detail with photo URLs.
- B2. Multi-directional Interactions:
      User B comments on User A's post.
      User B answers User A's Q&A post and votes answer helpful.
- B3. Ownership Protection:
      User B attempts to delete User A's post -> HTTP 403 Forbidden.
- A3. Author Post Deletion Lifecycle:
      User A deletes own post -> removed from User B's feed and detail (404), soft-deleted in Mongo.
"""
import io
import os
import uuid
import unittest
from datetime import datetime, timezone
from bson import ObjectId
from PIL import Image
import jwt
from pymongo import MongoClient

os.environ['MONGO_URI'] = os.environ.get('MONGO_URI', 'mongodb://127.0.0.1:27017')
os.environ['DB_NAME'] = os.environ.get('DB_NAME', 'saman_jcom0513_test_e2e')
os.environ['LOG_AUTH_HEADER'] = '0'

from fastapi import FastAPI
from fastapi.testclient import TestClient
from backend.routers import community as r

LIVE_TEST_URL = "http://127.0.0.1:18090"


def validate_test_target(uri, name):
    from urllib.parse import urlparse
    target = urlparse(uri)
    if target.scheme != "mongodb" or target.hostname not in ("127.0.0.1", "localhost"):
        raise ValueError("Dedicated loopback MongoDB required")
    if not name.startswith("saman_jcom0513_test_"):
        raise ValueError("Independent JCOM0513 test DB required")


def setup_test_indexes(db):
    db.community_posts.create_index(
        [("user_id", 1), ("request_key", 1)],
        unique=True,
        partialFilterExpression={"request_key": {"$type": "string"}},
        name="publish_request_unique",
    )
    db.community_comments.create_index(
        [("user_id", 1), ("request_key", 1)],
        unique=True,
        name="comment_request_unique",
    )
    db.community_answers.create_index(
        [("user_id", 1), ("request_key", 1)],
        unique=True,
        name="answer_request_unique",
    )
    db.community_answer_votes.create_index(
        [("user_id", 1), ("answer_id", 1)],
        unique=True,
        name="answer_votes_unique",
    )
    db.community_follows.create_index(
        [("follower_id", 1), ("following_id", 1)],
        unique=True,
        name="unique_follow_relation",
    )


def create_test_image_bytes(format="PNG", size=(64, 64), color="forestgreen") -> bytes:
    buf = io.BytesIO()
    img = Image.new("RGB", size, color=color)
    img.save(buf, format=format)
    return buf.getvalue()


class LiveOrTestClient:
    """Wrapper routing requests either to the live 18090 server or in-process TestClient."""

    def __init__(self, test_client: TestClient, base_url: str):
        self.test_client = test_client
        self.base_url = base_url
        self.use_live = False
        try:
            import requests
            resp = requests.get(f"{base_url}/health", timeout=1.5)
            if resp.status_code == 200:
                self.use_live = True
                self.session = requests.Session()
        except Exception:
            self.use_live = False

    def get(self, path: str, **kwargs):
        if self.use_live:
            return self.session.get(f"{self.base_url}{path}", **kwargs)
        return self.test_client.get(path, **kwargs)

    def post(self, path: str, **kwargs):
        if self.use_live:
            return self.session.post(f"{self.base_url}{path}", **kwargs)
        return self.test_client.post(path, **kwargs)

    def put(self, path: str, **kwargs):
        if self.use_live:
            return self.session.put(f"{self.base_url}{path}", **kwargs)
        return self.test_client.put(path, **kwargs)

    def delete(self, path: str, **kwargs):
        if self.use_live:
            return self.session.delete(f"{self.base_url}{path}", **kwargs)
        return self.test_client.delete(path, **kwargs)


class CommunitySubsystemE2ELifecycleTest(unittest.TestCase):
    """End-to-End lifecycle validation for JCOM-05 milestone sign-off."""

    @classmethod
    def setUpClass(cls):
        validate_test_target(os.environ['MONGO_URI'], os.environ['DB_NAME'])
        cls.client_mongo = MongoClient(os.environ['MONGO_URI'], serverSelectionTimeoutMS=5000)
        cls.db = cls.client_mongo[os.environ['DB_NAME']]

        cls.app = FastAPI()
        cls.app.include_router(r.router)
        cls.raw_test_client = TestClient(cls.app)
        cls.client = LiveOrTestClient(cls.raw_test_client, LIVE_TEST_URL)

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
        self.db.users.drop()
        self.db.community_posts.drop()
        self.db.community_comments.drop()
        self.db.community_answers.drop()
        self.db.community_answer_votes.drop()
        self.db.community_interactions.drop()
        self.db.community_follows.drop()
        self.db.workout_history.drop()
        setup_test_indexes(self.db)

        # Seed authoritative User A and User B
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

    def test_complete_e2e_community_lifecycle(self):
        """Execute the full end-to-end journey across all 7 acceptance criteria."""
        client = self.client

        # =========================================================================
        # STAGE A1: Diverse Publishing by User A
        # =========================================================================

        # 1. Media Upload: User A uploads an image
        img_bytes = create_test_image_bytes(format="PNG", size=(80, 80), color="forestgreen")
        files = {"file": ("e2e_photo.png", img_bytes, "image/png")}
        upload_res = client.post(
            "/api/community/media/upload",
            headers=self.auth_a,
            files=files,
        )
        self.assertEqual(upload_res.status_code, 200, f"Upload failed: {upload_res.text}")
        upload_data = upload_res.json()
        photo_url = upload_data.get("media_url")
        self.assertIsNotNone(photo_url, f"Expected media_url in response: {upload_data}")
        self.assertTrue(photo_url.startswith("/static/community/"))

        # 2. Text Post by User A
        key_text = f"key_text_{uuid.uuid4().hex[:16]}"
        pub_text_res = client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key_text}),
            json={
                "type": "text",
                "content": "Hello Saman Athletes! Starting my Marathon Journey today.",
                "topic": "#ChiaSẻ",
                "privacy": "public",
            },
        )
        self.assertIn(pub_text_res.status_code, (200, 201), f"Text publish failed: {pub_text_res.text}")
        text_post = pub_text_res.json()
        text_post_id = text_post.get("id") or str(text_post.get("_id"))
        self.assertTrue(text_post_id)
        self.assertEqual(text_post.get("caption"), "Hello Saman Athletes! Starting my Marathon Journey today.")

        # 3. Q&A Post by User A
        key_qa = f"key_qa_{uuid.uuid4().hex[:16]}"
        pub_qa_res = client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key_qa}),
            json={
                "type": "qa",
                "title": "What is the optimal carbohydrate-to-protein ratio after tempo runs?",
                "body": "Looking for recovery meal timing advice.",
                "topic": "Dinh dưỡng",
                "privacy": "public",
            },
        )
        self.assertIn(pub_qa_res.status_code, (200, 201), f"QA publish failed: {pub_qa_res.text}")
        qa_post = pub_qa_res.json()
        qa_post_id = qa_post.get("id") or str(qa_post.get("_id"))
        self.assertTrue(qa_post_id)
        self.assertEqual(qa_post.get("type"), "qa")

        # 4. Activity Snapshot Post by User A (Workout Attachment)
        workout_doc = self.db.workout_history.insert_one({
            "user_id": self.user_a_id,
            "email": "athlete_a@saman.test",
            "plan_name": "Marathon Strength",
            "date": "2026-11-04",
            "finished_at": datetime.now(timezone.utc),
            "total_duration_minutes": 38,
            "total_volume_kg": 950,
            "exercises": [{"name": "Barbell Squat", "sets": 4}],
        })
        workout_id = str(workout_doc.inserted_id)

        preview_res = client.get(
            f"/api/community/attachment-sources/workout/{workout_id}",
            headers=self.auth_a,
            params={"include_duration": True},
        )
        self.assertEqual(preview_res.status_code, 200, f"Preview failed: {preview_res.text}")
        preview_data = preview_res.json()

        key_snap = f"key_snap_{uuid.uuid4().hex[:16]}"
        pub_snap_res = client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key_snap}),
            json={
                "type": "workout",
                "content": "Completed morning tempo run with strong cadence",
                "topic": "#TậpLuyện",
                "privacy": "public",
                "attachment": {
                    "source_id": preview_data["source_id"],
                    "preview_hash": preview_data["preview_hash"],
                    "include_duration": True,
                    "include_exercises_or_foods": True,
                    "include_load_or_macros": False,
                },
            },
        )
        self.assertIn(pub_snap_res.status_code, (200, 201), f"Snapshot publish failed: {pub_snap_res.text}")
        snap_post = pub_snap_res.json()
        snap_post_id = snap_post.get("id") or str(snap_post.get("_id"))
        self.assertTrue(snap_post_id)
        self.assertIsNotNone(snap_post.get("attachment_snapshot"))

        # 5. Single Photo Post by User A
        key_photo = f"key_photo_{uuid.uuid4().hex[:16]}"
        pub_photo_res = client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key_photo}),
            json={
                "type": "photo",
                "content": "Fueling up with fresh green recovery shake",
                "photo_urls": [photo_url],
                "topic": "#PhụcHồi",
                "privacy": "public",
            },
        )
        self.assertIn(pub_photo_res.status_code, (200, 201), f"Photo publish failed: {pub_photo_res.text}")
        photo_post = pub_photo_res.json()
        photo_post_id = photo_post.get("id") or str(photo_post.get("_id"))
        self.assertTrue(photo_post_id)
        self.assertEqual(photo_post.get("photo_urls"), [photo_url])

        # =========================================================================
        # STAGE A2: Idempotency Protection
        # =========================================================================
        retry_res = client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key_photo}),
            json={
                "type": "photo",
                "content": "Fueling up with fresh green recovery shake",
                "photo_urls": [photo_url],
                "topic": "#PhụcHồi",
                "privacy": "public",
            },
        )
        self.assertIn(retry_res.status_code, (200, 201))
        retry_post = retry_res.json()
        retry_id = retry_post.get("id") or str(retry_post.get("_id"))
        self.assertEqual(retry_id, photo_post_id, "Idempotency failed: generated different post ID")

        doc_count = self.db.community_posts.count_documents({"request_key": key_photo})
        self.assertEqual(doc_count, 1, "Idempotency failed: duplicate document inserted in Mongo")

        # =========================================================================
        # STAGE B1: Audience Privacy & Follow Lifecycle
        # =========================================================================
        key_fol = f"key_fol_{uuid.uuid4().hex[:16]}"
        pub_fol_res = client.post(
            "/api/community/posts",
            headers=dict(self.auth_a, **{"X-Idempotency-Key": key_fol}),
            json={
                "type": "photo",
                "content": "Exclusive training plan for my followers only",
                "photo_urls": [photo_url],
                "topic": "#KỷLuật",
                "privacy": "followers_only",
            },
        )
        self.assertIn(pub_fol_res.status_code, (200, 201))
        fol_post = pub_fol_res.json()
        fol_post_id = fol_post.get("id") or str(fol_post.get("_id"))

        # User B (NOT following yet):
        detail_unfol_res = client.get(
            f"/api/community/posts/{fol_post_id}",
            headers=self.auth_b,
        )
        self.assertEqual(detail_unfol_res.status_code, 404, "Audience leak: non-follower accessed detail")

        feed_unfol_res = client.get(
            "/api/community/feed?tab=for_you",
            headers=self.auth_b,
        )
        self.assertEqual(feed_unfol_res.status_code, 200)
        unfol_pids = [p.get("id") for p in feed_unfol_res.json().get("items", [])]
        self.assertNotIn(fol_post_id, unfol_pids, "Audience leak: followers_only post in non-follower feed")

        # User B follows User A
        follow_res = client.put(
            f"/api/community/authors/{self.user_a_id}/follow",
            headers=self.auth_b,
        )
        self.assertEqual(follow_res.status_code, 200)
        self.assertTrue(follow_res.json().get("is_following"))

        # User B re-checks after following:
        detail_fol_res = client.get(
            f"/api/community/posts/{fol_post_id}",
            headers=self.auth_b,
        )
        self.assertEqual(detail_fol_res.status_code, 200)
        fol_detail = detail_fol_res.json()
        self.assertEqual(fol_detail.get("photo_urls"), [photo_url])

        feed_fol_res = client.get(
            "/api/community/feed?tab=for_you",
            headers=self.auth_b,
        )
        self.assertEqual(feed_fol_res.status_code, 200)
        fol_pids = [p.get("id") for p in feed_fol_res.json().get("items", [])]
        self.assertIn(fol_post_id, fol_pids, "Follow sync failed: post missing from follower feed")

        # =========================================================================
        # STAGE B2: Multi-directional Interactions
        # =========================================================================
        key_com = f"key_com_{uuid.uuid4().hex[:16]}"
        comment_res = client.post(
            f"/api/community/posts/{text_post_id}/comments",
            headers=dict(self.auth_b, **{"X-Idempotency-Key": key_com}),
            json={"content": "Great goal Athlete A! Rooting for your marathon sub-3."},
        )
        self.assertIn(comment_res.status_code, (200, 201), f"Comment failed: {comment_res.text}")
        comment_data = comment_res.json()
        comment_item = comment_data.get("comment", {})
        self.assertEqual(comment_item.get("content"), "Great goal Athlete A! Rooting for your marathon sub-3.")

        # Verify comment list contains User B's comment
        comments_list_res = client.get(
            f"/api/community/posts/{text_post_id}/comments",
            headers=self.auth_b,
        )
        self.assertEqual(comments_list_res.status_code, 200)
        comments_items = comments_list_res.json().get("items", [])
        self.assertTrue(any("Rooting for your marathon" in c.get("content", "") for c in comments_items))

        # User B submits answer to User A's Q&A post
        key_ans = f"key_ans_{uuid.uuid4().hex[:16]}"
        answer_res = client.post(
            f"/api/community/questions/{qa_post_id}/answers",
            headers=dict(self.auth_b, **{"X-Idempotency-Key": key_ans}),
            json={"content": "Aim for a 3:1 or 4:1 carb to protein ratio within 45 minutes."},
        )
        self.assertIn(answer_res.status_code, (200, 201), f"Answer failed: {answer_res.text}")
        answer_data = answer_res.json()
        answer_id = answer_data.get("answer", {}).get("id")
        self.assertTrue(answer_id, f"Missing answer id: {answer_data}")

        # User A votes User B's answer helpful (cross-user peer interaction)
        vote_res = client.put(
            f"/api/community/questions/{qa_post_id}/answers/{answer_id}/helpful",
            headers=self.auth_a,
        )
        self.assertEqual(vote_res.status_code, 200, f"Vote failed: {vote_res.text}")
        vote_data = vote_res.json()
        self.assertTrue(vote_data.get("is_upvoted"))
        self.assertGreaterEqual(vote_data.get("upvote_count", 0), 1)

        # =========================================================================
        # STAGE B3: Ownership Protection (HTTP 403 Forbidden)
        # =========================================================================
        unauth_del_res = client.delete(
            f"/api/community/posts/{text_post_id}",
            headers=self.auth_b,
        )
        self.assertEqual(
            unauth_del_res.status_code,
            403,
            f"Security flaw: non-author delete did not return 403 (got {unauth_del_res.status_code})",
        )
        self.assertEqual(unauth_del_res.json().get("detail"), "community_delete_forbidden_not_author")

        post_in_db = self.db.community_posts.find_one({"_id": ObjectId(text_post_id)})
        self.assertIsNotNone(post_in_db)
        self.assertFalse(post_in_db.get("is_deleted", False))

        # =========================================================================
        # STAGE A3: Author Post Deletion Lifecycle
        # =========================================================================
        author_del_res = client.delete(
            f"/api/community/posts/{text_post_id}",
            headers=self.auth_a,
        )
        self.assertEqual(author_del_res.status_code, 200, f"Author delete failed: {author_del_res.text}")
        del_body = author_del_res.json()
        self.assertTrue(del_body.get("success"))
        self.assertEqual(del_body.get("post_id"), text_post_id)

        b_detail_deleted_res = client.get(
            f"/api/community/posts/{text_post_id}",
            headers=self.auth_b,
        )
        self.assertEqual(b_detail_deleted_res.status_code, 404)

        b_feed_res = client.get(
            "/api/community/feed?tab=for_you",
            headers=self.auth_b,
        )
        self.assertEqual(b_feed_res.status_code, 200)
        current_feed_ids = [p.get("id") for p in b_feed_res.json().get("items", [])]
        self.assertNotIn(text_post_id, current_feed_ids, "Deleted post still visible in community feed")

        deleted_doc = self.db.community_posts.find_one({"_id": ObjectId(text_post_id)})
        self.assertTrue(deleted_doc.get("is_deleted"))
        self.assertIsNotNone(deleted_doc.get("deleted_at"))


if __name__ == "__main__":
    unittest.main()
