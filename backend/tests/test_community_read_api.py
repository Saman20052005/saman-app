"""
Unit and Contract Tests for Saman Community Remote Read API & Audience Enforcement.
Subsystem: Saman Community (JCOM-05-03).
"""

import base64
from datetime import datetime, timedelta, timezone
import unittest
from unittest.mock import MagicMock, patch
from bson import ObjectId
from fastapi.testclient import TestClient
import jwt

from backend.main import app
from backend.routers.community import JWT_ALGORITHM, JWT_SECRET


class MockCursor:
    def __init__(self, docs):
        self._docs = docs
        self._limit = None

    def sort(self, sort_order):
        # Sort in-memory if needed
        return self

    def limit(self, n):
        self._limit = n
        return self

    def __iter__(self):
        if self._limit is not None:
            return iter(self._docs[: self._limit])
        return iter(self._docs)


class TestCommunityReadApiContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

        cls.user_a_id = "user_a_12345"
        cls.user_b_id = "user_b_67890"

        cls.token_a = jwt.encode(
            {"email": "athlete_a@saman.test", "user_id": cls.user_a_id, "name": "Athlete A"},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )
        cls.token_b = jwt.encode(
            {"email": "athlete_b@saman.test", "user_id": cls.user_b_id, "name": "Athlete B"},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )

        cls.now = datetime.now(timezone.utc)

        # Synthetic test dataset with different privacy levels and archetypes
        cls.post_public_photo = {
            "_id": ObjectId("672400000000000000000001"),
            "id": "post_public_01",
            "type": "photo",
            "author_id": cls.user_a_id,
            "author": {
                "id": cls.user_a_id,
                "name": "Athlete A",
                "avatar_url": "https://example.com/avatar_a.jpg",
                "title": "Kip 2 Athlete",
                "is_verified": True,
                "follower_count": 12,
                # Dangerous fields that MUST NEVER leak:
                "email": "athlete_a@saman.test",
                "hashed_password": "super-secret-password-hash",
                "health_stats": {"vo2max": 54, "weight": 70},
            },
            "caption": "Buổi tập sáng công khai đầy năng lượng!",
            "photo_urls": ["https://example.com/photo1.jpg"],
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "like_count": 5,
            "created_at": cls.now - timedelta(minutes=30),
            "comments": [
                {
                    "id": "cmt_01",
                    "author": {
                        "id": cls.user_b_id,
                        "name": "Athlete B",
                        "avatar_url": "https://example.com/avatar_b.jpg",
                        "email": "athlete_b@saman.test",  # Sensitive
                    },
                    "content": "Tuyệt vời quá bạn ơi!",
                    "time_ago": "20 phút trước",
                    "replies": [],
                }
            ],
        }

        cls.post_private_user_a = {
            "_id": ObjectId("672400000000000000000002"),
            "id": "post_private_02",
            "type": "workout",
            "author_id": cls.user_a_id,
            "author": {
                "id": cls.user_a_id,
                "name": "Athlete A",
                "avatar_url": "https://example.com/avatar_a.jpg",
            },
            "caption": "Nhật ký riêng tư: Tập chân hôm nay",
            "photo_urls": [],
            "workout_attachment": {
                "title": "Leg Day Hypertrophy",
                "category": "Saman Kinetic",
                "duration_formatted": "45 phút",
                "exercise_count": 5,
                "set_count": 18,
                "include_duration": True,
                "include_exercises_or_foods": True,
                "exercises": [{"title": "Squat", "image_url": None}],
            },
            "privacy": "private",
            "status": "published",
            "is_deleted": False,
            "like_count": 0,
            "created_at": cls.now - timedelta(minutes=20),
            "comments": [],
        }

        cls.post_deleted = {
            "_id": ObjectId("672400000000000000000003"),
            "id": "post_deleted_03",
            "type": "photo",
            "author_id": cls.user_a_id,
            "caption": "Bài này đã bị xóa",
            "privacy": "public",
            "status": "published",
            "is_deleted": True,
            "created_at": cls.now - timedelta(minutes=15),
        }

        cls.post_qa = {
            "_id": ObjectId("672400000000000000000004"),
            "id": "post_qa_04",
            "type": "qa",
            "author_id": cls.user_b_id,
            "author": {
                "id": cls.user_b_id,
                "name": "Athlete B",
                "avatar_url": "https://example.com/avatar_b.jpg",
            },
            "caption": "Cần tham khảo lịch tập tuần sau",
            "qa_info": {
                "question": "Nên tập Upper/Lower hay Push/Pull/Legs khi bận rộn?",
                "category_tag": "#LịchTập",
                "details": "Mỗi tuần chỉ có 3 buổi tối 45 phút.",
                "respondent_count": 2,
                "respondents_summary": "2 người đã trả lời",
            },
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "created_at": cls.now - timedelta(minutes=10),
        }

        cls.answer_01 = {
            "_id": ObjectId("672400000000000000000005"),
            "id": "ans_01",
            "question_id": "post_qa_04",
            "author": {
                "id": cls.user_a_id,
                "name": "Athlete A",
                "avatar_url": "https://example.com/avatar_a.jpg",
                "email": "athlete_a@saman.test",  # Sensitive
            },
            "content": "Nếu 3 buổi thì Full Body hoặc Upper/Lower luân phiên là tối ưu nhất!",
            "time_ago": "5 phút trước",
            "upvote_count": 3,
            "is_pinned_best": True,
            "is_deleted": False,
            "created_at": cls.now - timedelta(minutes=5),
        }

    @patch("backend.routers.community.get_community_posts_collection")
    def test_feed_audience_anonymous_viewer_sees_only_public_posts(self, mock_get_col):
        mock_col = MagicMock()
        mock_get_col.return_value = mock_col

        def mock_find(query):
            # Assert query enforces public posts for anonymous viewers
            self.assertEqual(query.get("privacy"), {"$in": ["public", None]})
            self.assertEqual(query.get("is_deleted"), {"$ne": True})
            return MockCursor([self.post_public_photo, self.post_qa])

        mock_col.find.side_effect = mock_find

        res = self.client.get("/api/community/feed?tab=for_you")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(len(data["items"]), 2)
        post_ids = [p["id"] for p in data["items"]]
        self.assertIn("post_public_01", post_ids)
        self.assertNotIn("post_private_02", post_ids)

    @patch("backend.routers.community.get_community_posts_collection")
    def test_feed_audience_owner_can_see_own_private_post(self, mock_get_col):
        mock_col = MagicMock()
        mock_get_col.return_value = mock_col

        def mock_find(query):
            # Assert query permits public OR author_id == user_a_id
            or_clauses = query.get("$or", [])
            self.assertTrue(any(c.get("author_id") == self.user_a_id or c.get("author.id") == self.user_a_id for c in or_clauses))
            return MockCursor([self.post_public_photo, self.post_private_user_a])

        mock_col.find.side_effect = mock_find

        headers = {"Authorization": f"Bearer {self.token_a}"}
        res = self.client.get("/api/community/feed?tab=for_you", headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        post_ids = [p["id"] for p in data["items"]]
        self.assertIn("post_private_02", post_ids)

    @patch("backend.routers.community.get_community_posts_collection")
    def test_feed_following_tab_is_fail_closed_empty(self, mock_get_col):
        """Following tab returns an empty list since follow relationship graph is not yet implemented."""
        headers = {"Authorization": f"Bearer {self.token_a}"}
        res = self.client.get("/api/community/feed?tab=following", headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["items"], [])
        self.assertIsNone(data["next_cursor"])

    @patch("backend.routers.community.get_community_posts_collection")
    def test_feed_qa_tab_filters_qa_posts_only(self, mock_get_col):
        mock_col = MagicMock()
        mock_get_col.return_value = mock_col

        def mock_find(query):
            self.assertEqual(query.get("type"), "qa")
            return MockCursor([self.post_qa])

        mock_col.find.side_effect = mock_find

        res = self.client.get("/api/community/feed?tab=qa")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(len(data["items"]), 1)
        self.assertEqual(data["items"][0]["type"], "qa")
        self.assertEqual(data["items"][0]["qa_info"]["category_tag"], "#LịchTập")

    @patch("backend.routers.community.get_community_posts_collection")
    def test_post_detail_owner_can_read_private_post(self, mock_get_col):
        mock_col = MagicMock()
        mock_get_col.return_value = mock_col
        mock_col.find_one.return_value = self.post_private_user_a

        headers = {"Authorization": f"Bearer {self.token_a}"}
        res = self.client.get("/api/community/posts/post_private_02", headers=headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(data["id"], "post_private_02")
        self.assertEqual(data["workout_attachment"]["title"], "Leg Day Hypertrophy")

    @patch("backend.routers.community.get_community_posts_collection")
    def test_post_detail_non_owner_returns_404_fail_closed(self, mock_get_col):
        """Non-owner requesting a private post receives 404 (does not leak private post existence)."""
        mock_col = MagicMock()
        mock_get_col.return_value = mock_col
        mock_col.find_one.return_value = self.post_private_user_a

        headers = {"Authorization": f"Bearer {self.token_b}"}
        res = self.client.get("/api/community/posts/post_private_02", headers=headers)
        self.assertEqual(res.status_code, 404)
        self.assertEqual(res.json()["detail"], "Post not found")

    @patch("backend.routers.community.get_community_posts_collection")
    def test_post_detail_deleted_post_returns_404(self, mock_get_col):
        mock_col = MagicMock()
        mock_get_col.return_value = mock_col
        mock_col.find_one.return_value = self.post_deleted

        res = self.client.get("/api/community/posts/post_deleted_03")
        self.assertEqual(res.status_code, 404)
        self.assertEqual(res.json()["detail"], "Post not found")

    @patch("backend.routers.community.get_community_posts_collection")
    def test_public_author_projection_never_leaks_sensitive_fields(self, mock_get_col):
        """Security verification: Email, password hash, and health stats in User/Author document are excluded."""
        mock_col = MagicMock()
        mock_get_col.return_value = mock_col
        mock_col.find_one.return_value = self.post_public_photo

        res = self.client.get("/api/community/posts/post_public_01")
        self.assertEqual(res.status_code, 200)
        data = res.json()

        author = data["author"]
        self.assertEqual(author["name"], "Athlete A")
        self.assertEqual(author["title"], "Kip 2 Athlete")
        self.assertNotIn("email", author)
        self.assertNotIn("hashed_password", author)
        self.assertNotIn("health_stats", author)

        # Check comment author as well
        cmt_author = data["comments"][0]["author"]
        self.assertEqual(cmt_author["name"], "Athlete B")
        self.assertNotIn("email", cmt_author)

    @patch("backend.routers.community.get_community_answers_collection")
    @patch("backend.routers.community.get_community_posts_collection")
    def test_question_answers_ordered_and_projected_safely(self, mock_get_posts, mock_get_answers):
        mock_posts = MagicMock()
        mock_answers = MagicMock()
        mock_get_posts.return_value = mock_posts
        mock_get_answers.return_value = mock_answers

        mock_posts.find_one.return_value = self.post_qa
        mock_answers.find.return_value = MockCursor([self.answer_01])

        res = self.client.get("/api/community/questions/post_qa_04/answers")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertEqual(len(data["items"]), 1)
        ans = data["items"][0]
        self.assertEqual(ans["content"], "Nếu 3 buổi thì Full Body hoặc Upper/Lower luân phiên là tối ưu nhất!")
        self.assertTrue(ans["is_pinned_best"])
        self.assertNotIn("email", ans["author"])

    @patch("backend.routers.community.get_community_posts_collection")
    def test_invalid_cursor_returns_400(self, mock_get_col):
        mock_get_col.return_value = MagicMock()
        res = self.client.get("/api/community/feed?cursor=not-a-valid-base64-cursor!")
        self.assertEqual(res.status_code, 400)
        self.assertIn("Invalid pagination cursor", res.json()["detail"])

    @patch("backend.routers.community.get_community_posts_collection")
    def test_invalid_tab_returns_400(self, mock_get_col):
        mock_get_col.return_value = MagicMock()
        res = self.client.get("/api/community/feed?tab=unknown_tab_name")
        self.assertEqual(res.status_code, 400)
        self.assertIn("Invalid tab filter", res.json()["detail"])


if __name__ == "__main__":
    unittest.main()

