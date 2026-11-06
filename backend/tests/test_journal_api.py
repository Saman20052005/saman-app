"""
Comprehensive Unit and Contract Tests for Saman Journal Public Read API.
Subsystem: Saman Journal (JCOM-05-02).
"""

import unittest
from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient
from fastapi import FastAPI

from backend.app.models.journal import JournalArticleModel
from backend.routers.journal import router, SYNTHETIC_TEST_ARTICLES


class TestJournalApiContract(unittest.TestCase):
    def setUp(self):
        self.app = FastAPI()
        self.app.include_router(router)
        self.client = TestClient(self.app)

        # Mock collections for isolated testing
        self.mock_articles_col = MagicMock()
        self.mock_exercises_col = MagicMock()
        self.mock_foods_col = MagicMock()
        self.mock_recipes_col = MagicMock()

        # Wire up mock collections
        patcher_col = patch("backend.routers.journal._get_journal_collection", return_value=self.mock_articles_col)
        self.addCleanup(patcher_col.stop)
        patcher_col.start()

        patcher_ex = patch("backend.routers.journal.exercises_collection", self.mock_exercises_col)
        self.addCleanup(patcher_ex.stop)
        patcher_ex.start()

        patcher_foods = patch("backend.routers.journal.foods_collection", self.mock_foods_col)
        self.addCleanup(patcher_foods.stop)
        patcher_foods.start()

        patcher_recipes = patch("backend.routers.journal.recipes_collection", self.mock_recipes_col)
        self.addCleanup(patcher_recipes.stop)
        patcher_recipes.start()

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


if __name__ == "__main__":
    unittest.main()
