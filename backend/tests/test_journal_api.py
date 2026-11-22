"""
Comprehensive Unit and Contract Tests for Saman Journal API.
Subsystem: Saman Journal (JCOM-05-02 + W1 E2E extension).
"""

from datetime import datetime, timedelta, timezone
import unittest
from unittest.mock import MagicMock, patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
import jwt

from backend.app.database_journal import ensure_journal_indexes
from backend.app.models.journal import JournalArticleModel
from backend.auth.config import JWT_ALGORITHM, JWT_SECRET
from backend.routers.journal import SYNTHETIC_TEST_ARTICLES, router


def _make_jwt(
    email: str = "reader@saman.app",
    user_id: str = "user_001",
    expired: bool = False,
) -> str:
    now = datetime.now(timezone.utc)
    exp = now - timedelta(minutes=5) if expired else now + timedelta(hours=1)
    payload = {
        "sub": user_id,
        "email": email,
        "name": "Saman Reader",
        "exp": exp,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


class TestJournalApiContract(unittest.TestCase):
    def setUp(self):
        self.app = FastAPI()
        self.app.include_router(router)
        self.client = TestClient(self.app)

        # Mock collections for isolated testing
        self.mock_articles_col = MagicMock()
        self.mock_progress_col = MagicMock()
        self.mock_bookmarks_col = MagicMock()
        self.mock_users_col = MagicMock()
        self.mock_exercises_col = MagicMock()
        self.mock_foods_col = MagicMock()
        self.mock_recipes_col = MagicMock()

        self.mock_users_col.find_one.return_value = {
            "_id": "mongo_user_001",
            "email": "reader@saman.app",
            "name": "Saman Reader",
        }
        self.mock_db = {
            "users": self.mock_users_col,
            "journal_articles": self.mock_articles_col,
            "journal_reading_progress": self.mock_progress_col,
            "journal_bookmarks": self.mock_bookmarks_col,
        }

        # Wire up mock collections & db
        patcher_db = patch("backend.routers.journal.db", self.mock_db)
        self.addCleanup(patcher_db.stop)
        patcher_db.start()

        patcher_col = patch(
            "backend.routers.journal._get_journal_collection",
            return_value=self.mock_articles_col,
        )
        self.addCleanup(patcher_col.stop)
        patcher_col.start()

        patcher_progress = patch(
            "backend.routers.journal._get_reading_progress_collection",
            return_value=self.mock_progress_col,
        )
        self.addCleanup(patcher_progress.stop)
        patcher_progress.start()

        patcher_bookmarks = patch(
            "backend.routers.journal._get_bookmarks_collection",
            return_value=self.mock_bookmarks_col,
        )
        self.addCleanup(patcher_bookmarks.stop)
        patcher_bookmarks.start()

        patcher_ex = patch("backend.routers.journal.exercises_collection", self.mock_exercises_col)
        self.addCleanup(patcher_ex.stop)
        patcher_ex.start()

        patcher_foods = patch("backend.routers.journal.foods_collection", self.mock_foods_col)
        self.addCleanup(patcher_foods.stop)
        patcher_foods.start()

        patcher_recipes = patch("backend.routers.journal.recipes_collection", self.mock_recipes_col)
        self.addCleanup(patcher_recipes.stop)
        patcher_recipes.start()

    # ─── Existing Public Read Contract Tests ─────────────────────────────────

    def test_get_topics_returns_canonical_list(self):
        response = self.client.get("/api/journal/topics")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("topics", data)
        topic_ids = [t["id"] for t in data["topics"]]
        self.assertEqual(topic_ids, ["all", "workout", "nutrition", "recovery", "habits"])

    def test_get_featured_article_returns_featured_model(self):
        featured_doc = SYNTHETIC_TEST_ARTICLES[0]
        self.mock_articles_col.find_one.return_value = featured_doc

        response = self.client.get("/api/journal/featured")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("article", data)
        self.assertIsNotNone(data["article"])
        self.assertEqual(data["article"]["id"], "article_leg_day_recovery")
        self.assertEqual(data["article"]["topic"], "recovery")
        self.assertTrue(data["article"]["is_featured"])

    def test_get_featured_article_empty_database_returns_null(self):
        self.mock_articles_col.find_one.return_value = None

        response = self.client.get("/api/journal/featured")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("article", data)
        self.assertIsNone(data["article"])

    def test_get_articles_pagination_and_topic_filter(self):
        sample_docs = SYNTHETIC_TEST_ARTICLES[:3]
        mock_cursor = MagicMock()
        mock_cursor.sort.return_value = mock_cursor
        mock_cursor.limit.return_value = sample_docs
        self.mock_articles_col.find.return_value = mock_cursor
        self.mock_articles_col.count_documents.return_value = 5

        response = self.client.get("/api/journal/articles?topic=nutrition&limit=3")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("articles", data)
        self.assertIn("total", data)
        self.assertEqual(len(data["articles"]), 3)
        self.assertEqual(data["total"], 5)

    def test_get_articles_invalid_topic_returns_400(self):
        response = self.client.get("/api/journal/articles?topic=invalid_topic_xyz")
        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertIn("Invalid topic", data["detail"])

    def test_get_article_by_id_success(self):
        article_doc = SYNTHETIC_TEST_ARTICLES[1]
        self.mock_articles_col.find_one.return_value = article_doc

        response = self.client.get("/api/journal/articles/article_protein_basics")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["id"], "article_protein_basics")
        self.assertEqual(data["title"], "Hiểu protein trong bữa ăn hằng ngày")
        self.assertEqual(data["topic"], "nutrition")
        self.assertFalse(data["is_bookmarked"])

    def test_get_article_by_id_not_found_returns_404(self):
        self.mock_articles_col.find_one.return_value = None

        response = self.client.get("/api/journal/articles/non_existent_article")
        self.assertEqual(response.status_code, 404)
        data = response.json()
        self.assertIn("not found", data["detail"])

    def test_search_empty_query_returns_empty_response(self):
        response = self.client.get("/api/journal/search?q=")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["query"], "")
        self.assertEqual(data["items"], [])
        self.assertEqual(data["total"], 0)
        self.assertIsNone(data["advice_tip"])

    def test_search_invalid_category_returns_400(self):
        response = self.client.get("/api/journal/search?q=protein&category=invalid_category")
        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertIn("Invalid category", data["detail"])

    def test_search_across_all_categories_and_contextual_advice(self):
        # 1. Mock articles
        self.mock_articles_col.find.return_value.limit.return_value = [
            SYNTHETIC_TEST_ARTICLES[1],  # article_protein_basics
        ]
        # 2. Mock exercises
        self.mock_exercises_col.find.return_value.limit.return_value = [
            {
                "_id": "ex_01",
                "name": "Barbell Bench Press",
                "nameVi": "Đẩy ngực tạ đòn",
                "muscleGroup": "Ngực",
                "equipment": "Barbell",
                "difficulty": "Cơ bản",
                "thumbnailUrl": "assets/images/exercises/barbell-bench-press-thumb.jpg",
            }
        ]
        # 3. Mock foods
        self.mock_foods_col.find.return_value.limit.return_value = [
            {
                "_id": "food_01",
                "name": "Ức gà",
                "calories": 165,
                "protein": 31.0,
            }
        ]
        # 4. Mock recipes
        self.mock_recipes_col.find.return_value.limit.return_value = []

        response = self.client.get("/api/journal/search?q=protein&category=all")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["query"], "protein")
        self.assertGreaterEqual(len(data["items"]), 3)

        categories = {item["category"] for item in data["items"]}
        self.assertIn("articles", categories)
        self.assertIn("exercises", categories)
        self.assertIn("foods", categories)

        # Verify contextual advice tip
        self.assertIsNotNone(data["advice_tip"])
        self.assertEqual(data["advice_tip"]["id"], "tip_protein_window")
        self.assertIn("25-40g protein", data["advice_tip"]["content"])

    def test_search_recipes_empty_when_no_recipe_contract(self):
        self.mock_recipes_col.find.return_value.limit.return_value = []
        response = self.client.get("/api/journal/search?q=salad&category=recipes")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["items"], [])
        self.assertEqual(data["total"], 0)

    def test_public_endpoint_privacy_no_user_data_leaked(self):
        """Security invariant: Public journal endpoints never expose private user logs or auth headers."""
        self.mock_articles_col.find.return_value.limit.return_value = [SYNTHETIC_TEST_ARTICLES[0]]
        response = self.client.get("/api/journal/articles")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        for article in data["articles"]:
            self.assertNotIn("user_id", article)
            self.assertNotIn("email", article)
            self.assertNotIn("password", article)
            self.assertNotIn("health_stats", article)

    # ─── Synthetic Articles Content Enrichment Tests ─────────────────────────

    def test_synthetic_articles_enriched_content_and_invariants(self):
        self.assertEqual(len(SYNTHETIC_TEST_ARTICLES), 5)
        expected_ids = {
            "article_leg_day_recovery",
            "article_protein_basics",
            "article_calories_and_macros",
            "article_progressive_overload",
            "article_sleep_and_muscle",
        }
        actual_ids = {a["id"] for a in SYNTHETIC_TEST_ARTICLES}
        self.assertEqual(actual_ids, expected_ids)

        for article in SYNTHETIC_TEST_ARTICLES:
            self.assertEqual(article["provenance"], "synthetic_test_data")
            body = article.get("content_body") or ""
            self.assertIn("## ", body)
            self.assertGreaterEqual(body.count("\n\n"), 3)
            model = JournalArticleModel(**article)
            self.assertEqual(model.id, article["id"])

    # ─── Index Setup Tests ───────────────────────────────────────────────────

    def test_ensure_journal_indexes_creates_idempotent_indexes(self):
        mock_progress = MagicMock()
        mock_bookmarks = MagicMock()
        mock_progress.create_index.side_effect = [
            "idx_journal_progress_user_article",
            "idx_journal_progress_user_updated",
        ]
        mock_bookmarks.create_index.side_effect = [
            "idx_journal_bookmark_user_article",
            "idx_journal_bookmark_user_created",
        ]
        fake_db = {
            "journal_reading_progress": mock_progress,
            "journal_bookmarks": mock_bookmarks,
        }

        created = ensure_journal_indexes(fake_db)
        self.assertEqual(
            created["journal_reading_progress"],
            ["idx_journal_progress_user_article", "idx_journal_progress_user_updated"],
        )
        self.assertEqual(
            created["journal_bookmarks"],
            ["idx_journal_bookmark_user_article", "idx_journal_bookmark_user_created"],
        )

        mock_progress.create_index.assert_any_call(
            [("user_id", 1), ("article_id", 1)],
            unique=True,
            name="idx_journal_progress_user_article",
        )
        mock_progress.create_index.assert_any_call(
            [("user_id", 1), ("updated_at", -1)],
            name="idx_journal_progress_user_updated",
        )
        mock_bookmarks.create_index.assert_any_call(
            [("user_id", 1), ("article_id", 1)],
            unique=True,
            name="idx_journal_bookmark_user_article",
        )
        mock_bookmarks.create_index.assert_any_call(
            [("user_id", 1), ("created_at", -1)],
            name="idx_journal_bookmark_user_created",
        )

        with self.assertRaises(RuntimeError):
            ensure_journal_indexes(None)

    # ─── Reading Progress Endpoints Tests ────────────────────────────────────

    def test_get_reading_progress_anonymous_returns_null_not_401(self):
        response = self.client.get("/api/journal/reading-progress")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"progress": None})
        self.mock_progress_col.find.assert_not_called()

    def test_get_reading_progress_authenticated_returns_latest_entry(self):
        token = _make_jwt()
        progress_doc = {
            "user_id": "mongo_user_001",
            "article_id": "article_leg_day_recovery",
            "title": "Phục hồi tốt hơn sau buổi tập chân",
            "progress_percent": 0.65,
            "remaining_minutes": 2,
            "cover_image_asset": "assets/images/home_journal_recovery.jpg",
            "summary": "Chiến lược giảm đau nhức cơ bắp DOMS...",
            "updated_at": "2026-11-22T02:30:00Z",
        }
        mock_cursor = MagicMock()
        mock_cursor.sort.return_value = mock_cursor
        mock_cursor.limit.return_value = [progress_doc]
        self.mock_progress_col.find.return_value = mock_cursor

        response = self.client.get(
            "/api/journal/reading-progress",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIsNotNone(data["progress"])
        self.assertEqual(data["progress"]["article_id"], "article_leg_day_recovery")
        self.assertAlmostEqual(data["progress"]["progress_percent"], 0.65)
        self.assertEqual(data["progress"]["remaining_minutes"], 2)

        self.mock_progress_col.find.assert_called_once_with({"user_id": "mongo_user_001"})
        mock_cursor.sort.assert_called_once_with([("updated_at", -1)])
        mock_cursor.limit.assert_called_once_with(1)

    def test_get_reading_progress_authenticated_empty_returns_null(self):
        token = _make_jwt()
        mock_cursor = MagicMock()
        mock_cursor.sort.return_value = mock_cursor
        mock_cursor.limit.return_value = []
        self.mock_progress_col.find.return_value = mock_cursor

        response = self.client.get(
            "/api/journal/reading-progress",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"progress": None})

    def test_put_reading_progress_requires_auth_returns_401(self):
        response = self.client.put(
            "/api/journal/reading-progress/article_leg_day_recovery",
            json={"progress_percent": 0.5, "remaining_minutes": 2},
        )
        self.assertEqual(response.status_code, 401)

    def test_put_reading_progress_expired_token_returns_401(self):
        expired_token = _make_jwt(expired=True)
        response = self.client.put(
            "/api/journal/reading-progress/article_leg_day_recovery",
            json={"progress_percent": 0.5, "remaining_minutes": 2},
            headers={"Authorization": f"Bearer {expired_token}"},
        )
        self.assertEqual(response.status_code, 401)

    def test_put_reading_progress_article_not_found_returns_404(self):
        token = _make_jwt()
        self.mock_articles_col.find_one.return_value = None

        response = self.client.put(
            "/api/journal/reading-progress/non_existent_article",
            json={"progress_percent": 0.5, "remaining_minutes": 2},
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(response.status_code, 404)

    def test_put_reading_progress_out_of_range_returns_422(self):
        token = _make_jwt()
        headers = {"Authorization": f"Bearer {token}"}

        resp_high = self.client.put(
            "/api/journal/reading-progress/article_leg_day_recovery",
            json={"progress_percent": 1.5, "remaining_minutes": 2},
            headers=headers,
        )
        self.assertEqual(resp_high.status_code, 422)

        resp_low = self.client.put(
            "/api/journal/reading-progress/article_leg_day_recovery",
            json={"progress_percent": -0.1, "remaining_minutes": 2},
            headers=headers,
        )
        self.assertEqual(resp_low.status_code, 422)

        resp_minutes = self.client.put(
            "/api/journal/reading-progress/article_leg_day_recovery",
            json={"progress_percent": 0.4, "remaining_minutes": 150},
            headers=headers,
        )
        self.assertEqual(resp_minutes.status_code, 422)

    def test_put_reading_progress_upsert_idempotent(self):
        token = _make_jwt()
        headers = {"Authorization": f"Bearer {token}"}
        self.mock_articles_col.find_one.return_value = SYNTHETIC_TEST_ARTICLES[0]

        resp1 = self.client.put(
            "/api/journal/reading-progress/article_leg_day_recovery",
            json={"progress_percent": 0.4, "remaining_minutes": 3},
            headers=headers,
        )
        self.assertEqual(resp1.status_code, 200)
        p1 = resp1.json()["progress"]
        self.assertEqual(p1["article_id"], "article_leg_day_recovery")
        self.assertAlmostEqual(p1["progress_percent"], 0.4)
        self.assertEqual(p1["remaining_minutes"], 3)

        resp2 = self.client.put(
            "/api/journal/reading-progress/article_leg_day_recovery",
            json={"progress_percent": 0.9, "remaining_minutes": 1},
            headers=headers,
        )
        self.assertEqual(resp2.status_code, 200)
        p2 = resp2.json()["progress"]
        self.assertAlmostEqual(p2["progress_percent"], 0.9)
        self.assertEqual(p2["remaining_minutes"], 1)

        self.assertEqual(self.mock_progress_col.update_one.call_count, 2)
        last_call = self.mock_progress_col.update_one.call_args
        self.assertEqual(
            last_call.args[0],
            {"user_id": "mongo_user_001", "article_id": "article_leg_day_recovery"},
        )
        self.assertTrue(last_call.kwargs.get("upsert"))

    # ─── Bookmark Endpoints & Article Bookmark Status Tests ──────────────────

    def test_get_bookmarks_anonymous_returns_empty_list_not_401(self):
        response = self.client.get("/api/journal/bookmarks")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["articles"], [])
        self.assertEqual(data["total"], 0)
        self.mock_bookmarks_col.find.assert_not_called()

    def test_get_bookmarks_authenticated_returns_ordered_articles(self):
        token = _make_jwt()
        mock_bm_cursor = MagicMock()
        mock_bm_cursor.sort.return_value = [
            {"user_id": "mongo_user_001", "article_id": "article_sleep_and_muscle", "created_at": "2026-11-22T02:00:00Z"},
            {"user_id": "mongo_user_001", "article_id": "article_protein_basics", "created_at": "2026-11-22T01:00:00Z"},
        ]
        self.mock_bookmarks_col.find.return_value = mock_bm_cursor
        self.mock_articles_col.find.return_value = [
            SYNTHETIC_TEST_ARTICLES[1],  # article_protein_basics
            SYNTHETIC_TEST_ARTICLES[4],  # article_sleep_and_muscle
        ]

        response = self.client.get(
            "/api/journal/bookmarks",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["total"], 2)
        self.assertEqual(
            [a["id"] for a in data["articles"]],
            ["article_sleep_and_muscle", "article_protein_basics"],
        )
        self.assertTrue(all(a["is_bookmarked"] for a in data["articles"]))
        mock_bm_cursor.sort.assert_called_once_with([("created_at", -1)])

    def test_put_and_delete_bookmark_require_auth_returns_401(self):
        put_resp = self.client.put("/api/journal/bookmarks/article_protein_basics")
        self.assertEqual(put_resp.status_code, 401)

        del_resp = self.client.delete("/api/journal/bookmarks/article_protein_basics")
        self.assertEqual(del_resp.status_code, 401)

    def test_put_bookmark_article_not_found_returns_404(self):
        token = _make_jwt()
        self.mock_articles_col.find_one.return_value = None

        response = self.client.put(
            "/api/journal/bookmarks/missing_article",
            headers={"Authorization": f"Bearer {token}"},
        )
        self.assertEqual(response.status_code, 404)

    def test_put_and_delete_bookmark_idempotent(self):
        token = _make_jwt()
        headers = {"Authorization": f"Bearer {token}"}
        self.mock_articles_col.find_one.return_value = SYNTHETIC_TEST_ARTICLES[1]

        # Idempotent PUT twice
        for _ in range(2):
            resp = self.client.put(
                "/api/journal/bookmarks/article_protein_basics",
                headers=headers,
            )
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(
                resp.json(),
                {"article_id": "article_protein_basics", "is_bookmarked": True},
            )
        self.assertEqual(self.mock_bookmarks_col.update_one.call_count, 2)
        self.assertTrue(self.mock_bookmarks_col.update_one.call_args.kwargs.get("upsert"))

        # Idempotent DELETE twice
        for _ in range(2):
            resp = self.client.delete(
                "/api/journal/bookmarks/article_protein_basics",
                headers=headers,
            )
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(
                resp.json(),
                {"article_id": "article_protein_basics", "is_bookmarked": False},
            )
        self.assertEqual(self.mock_bookmarks_col.delete_one.call_count, 2)
        self.mock_bookmarks_col.delete_one.assert_called_with(
            {"user_id": "mongo_user_001", "article_id": "article_protein_basics"}
        )

    def test_get_article_by_id_reflects_bookmark_status_for_authenticated_user(self):
        token = _make_jwt()
        headers = {"Authorization": f"Bearer {token}"}
        self.mock_articles_col.find_one.return_value = SYNTHETIC_TEST_ARTICLES[1]

        # Bookmarked case
        self.mock_bookmarks_col.find_one.return_value = {
            "user_id": "mongo_user_001",
            "article_id": "article_protein_basics",
        }
        resp_bm = self.client.get(
            "/api/journal/articles/article_protein_basics",
            headers=headers,
        )
        self.assertEqual(resp_bm.status_code, 200)
        self.assertTrue(resp_bm.json()["is_bookmarked"])

        # Not bookmarked case
        self.mock_bookmarks_col.find_one.return_value = None
        resp_not_bm = self.client.get(
            "/api/journal/articles/article_protein_basics",
            headers=headers,
        )
        self.assertEqual(resp_not_bm.status_code, 200)
        self.assertFalse(resp_not_bm.json()["is_bookmarked"])

    # ─── Library Summary Endpoint Tests ──────────────────────────────────────

    def test_get_library_summary_counts_exercises_foods_and_recipes(self):
        self.mock_exercises_col.count_documents.return_value = 48
        self.mock_foods_col.count_documents.return_value = 120
        self.mock_recipes_col.count_documents.return_value = 15

        response = self.client.get("/api/journal/library-summary")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(len(data["entries"]), 2)

        by_id = {entry["id"]: entry for entry in data["entries"]}
        self.assertIn("library_exercises", by_id)
        self.assertIn("library_foods", by_id)
        self.assertEqual(by_id["library_exercises"]["count"], 48)
        self.assertEqual(by_id["library_exercises"]["category"], "exercises")
        self.assertIn("48", by_id["library_exercises"]["item_count_label"])

        self.assertEqual(by_id["library_foods"]["count"], 135)
        self.assertEqual(by_id["library_foods"]["category"], "foods")
        self.assertIn("135", by_id["library_foods"]["item_count_label"])

    def test_get_library_summary_handles_none_collections_safely(self):
        with (
            patch("backend.routers.journal.exercises_collection", None),
            patch("backend.routers.journal.foods_collection", None),
            patch("backend.routers.journal.recipes_collection", None),
        ):
            response = self.client.get("/api/journal/library-summary")
        self.assertEqual(response.status_code, 200)
        entries = response.json()["entries"]
        self.assertEqual(len(entries), 2)
        self.assertEqual(entries[0]["count"], 0)
        self.assertEqual(entries[1]["count"], 0)

    # ─── Guided Series Endpoint Tests ────────────────────────────────────────

    def test_get_guided_series_returns_foundation_series_with_lessons(self):
        mock_cursor = MagicMock()
        mock_cursor.sort.return_value = mock_cursor
        mock_cursor.limit.return_value = SYNTHETIC_TEST_ARTICLES
        self.mock_articles_col.find.return_value = mock_cursor

        response = self.client.get("/api/journal/guided-series")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        series = data["series"]
        self.assertIsNotNone(series)
        self.assertEqual(series["id"], "series_foundation")
        self.assertEqual(series["title"], "Bắt đầu cùng Saman")
        self.assertEqual(series["total_lessons"], 5)
        self.assertEqual(len(series["lessons"]), 5)
        self.assertEqual(series["lessons"][0]["id"], "article_leg_day_recovery")
        self.assertEqual(series["lessons"][-1]["id"], "article_sleep_and_muscle")
        mock_cursor.sort.assert_called_once_with([("created_at", 1), ("_id", 1)])

    def test_get_guided_series_empty_collection_returns_null(self):
        mock_cursor = MagicMock()
        mock_cursor.sort.return_value = mock_cursor
        mock_cursor.limit.return_value = []
        self.mock_articles_col.find.return_value = mock_cursor

        response = self.client.get("/api/journal/guided-series")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"series": None})


if __name__ == "__main__":
    unittest.main()
