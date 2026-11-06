"""End-to-end food analysis review/confirm flow against isolated MongoDB."""

import os
import sys
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

from fastapi import FastAPI
from fastapi.testclient import TestClient
from bson import ObjectId

os.environ["MONGO_URI"] = "mongodb://127.0.0.1:27017"
os.environ["DB_NAME"] = "saman_test_core3_isolated"

routers_package = ModuleType("backend.routers")
routers_package.__path__ = [str(Path(__file__).resolve().parents[1] / "routers")]
sys.modules.setdefault("backend.routers", routers_package)

auth_stub = ModuleType("backend.auth_utils")
auth_stub.verify_token = lambda: "food-e2e-test@saman.test"
auth_stub.get_current_user = lambda: {
    "email": "food-e2e-test@saman.test",
    "id": "food-e2e-test",
}
sys.modules.setdefault("backend.auth_utils", auth_stub)

cloudinary_stub = ModuleType("cloudinary")
cloudinary_stub.config = lambda **_kwargs: None
cloudinary_uploader_stub = ModuleType("cloudinary.uploader")
cloudinary_uploader_stub.upload = lambda *_args, **_kwargs: {}
cloudinary_stub.uploader = cloudinary_uploader_stub
sys.modules.setdefault("cloudinary", cloudinary_stub)
sys.modules.setdefault("cloudinary.uploader", cloudinary_uploader_stub)

user_repository_stub = ModuleType("backend.app.repositories.user_repository")
user_repository_stub.UserRepository = type("UserRepository", (), {"__init__": lambda self: None})
sys.modules.setdefault("backend.app.repositories.user_repository", user_repository_stub)
meal_generator_stub = ModuleType("backend.services.meal_generator")
meal_generator_stub.MealGeneratorService = type(
    "MealGeneratorService",
    (),
    {"__init__": lambda self, **_kwargs: None},
)
sys.modules.setdefault("backend.services.meal_generator", meal_generator_stub)

from backend.routers import food_analysis
from backend.routers import nutrition as nutrition_router
from backend.app.database import nutrition_collection


USER_EMAIL = "food-e2e-test@saman.test"
STORY_ID = "cp04b-e2e-advanced-meal-20261104"


def test_advanced_analysis_review_confirm_persists_to_isolated_nutrition_plans():
    assert nutrition_collection is not None, "isolated MongoDB must be reachable"
    assert nutrition_router.nutrition_collection is nutrition_collection

    advanced_result = {
        "food_name": "Chicken Rice Bowl",
        "food_label": "chicken_rice_bowl",
        "confidence": 0.94,
        "low_confidence": False,
        "grams": 350,
        "nutrition": {
            "calories": 525,
            "protein": 42,
            "carbs": 56,
            "fat": 14,
            "fiber": 7,
        },
        "fiber": 7,
        "total_weight_grams": 350,
        "total_nutrition": {
            "calories": 525,
            "protein": 42,
            "carbs": 56,
            "fat": 14,
            "fiber": 7,
        },
        "ingredients": [
            {
                "name": "Chicken",
                "portion_grams": 120,
                "calories": 198,
                "protein": 37,
                "carbs": 0,
                "fat": 4,
                "confidence": 0.91,
            },
            {
                "name": "Rice",
                "portion_grams": 180,
                "calories": 234,
                "protein": 4,
                "carbs": 52,
                "fat": 1,
                "confidence": 0.89,
            },
        ],
        "health_insights": ["Good protein source"],
        "nutrition_source": "gemini_estimate",
    }

    async def mocked_advanced_analysis(**_kwargs):
        return dict(advanced_result)

    revenue_guard_stub = ModuleType("backend.app.services.revenue_guard")
    revenue_guard_stub.orchestrate_nutrition_analysis = mocked_advanced_analysis
    app = FastAPI()
    app.include_router(food_analysis.router)
    app.include_router(nutrition_router.router)

    query = {"user_email": USER_EMAIL, "story_id": STORY_ID}
    nutrition_collection.delete_one(query)
    try:
        with patch.dict(
            sys.modules,
            {"backend.app.services.revenue_guard": revenue_guard_stub},
        ):
            with TestClient(app) as client:
                analysis = client.post(
                    "/api/food/analyze",
                    files={"image": ("meal.jpg", b"x" * 1200, "image/jpeg")},
                    data={"mode": "advanced", "grams": "100"},
                )
                assert analysis.status_code == 200, analysis.text
                result = analysis.json()
                assert result["fiber"] == 7
                assert len(result["ingredients"]) == 2
                assert nutrition_collection.count_documents(query) == 0

                reviewed_food = {
                    "name": result["food_name"],
                    "food_label": result["food_label"],
                    "weight_grams": result["grams"],
                    "calories": result["nutrition"]["calories"],
                    "protein": result["nutrition"]["protein"],
                    "carbs": result["nutrition"]["carbs"],
                    "fat": result["nutrition"]["fat"],
                    "fiber": result["fiber"],
                    "ingredients": result["ingredients"],
                    "food_id": "",
                }
                saved = client.post(
                    "/api/nutrition/logs",
                    json={
                        "date": "2026-11-04",
                        "meal_type": "lunch",
                        "foods": [reviewed_food],
                        "total_calories": 525,
                        "notes": "Reviewed and confirmed in CP-04B test",
                        "story_id": STORY_ID,
                    },
                )
                assert saved.status_code == 200, saved.text
                stored = nutrition_collection.find_one(
                    {"_id": ObjectId(saved.json()["id"]), **query}
                )
                assert stored is not None
                assert stored["foods"][0]["fiber"] == 7
                assert len(stored["foods"][0]["ingredients"]) == 2
                assert stored["user_email"] == USER_EMAIL
    finally:
        nutrition_collection.delete_one(query)
