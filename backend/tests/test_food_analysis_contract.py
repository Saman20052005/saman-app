"""Focused contract checks for food photo uploads and Advanced Gemini output."""

import asyncio
import os
import sys
from pathlib import Path
from types import ModuleType
from unittest.mock import AsyncMock, patch

import pytest

os.environ["MONGO_URI"] = "mongodb://127.0.0.1:27017"
os.environ["DB_NAME"] = "saman_test_core3_isolated"

# Import only the target router module; unrelated application routers pull in
# optional services that are outside this isolated contract test.
routers_package = ModuleType("backend.routers")
routers_package.__path__ = [str(Path(__file__).resolve().parents[1] / "routers")]
sys.modules.setdefault("backend.routers", routers_package)
auth_stub = ModuleType("backend.auth_utils")
auth_stub.verify_token = lambda: "user@example.test"
auth_stub.get_current_user = lambda: {"email": "food-e2e-test@saman.test", "id": "food-e2e-test"}
sys.modules.setdefault("backend.auth_utils", auth_stub)
classifier_stub = ModuleType("backend.services.food_classifier")
classifier_stub.FoodClassifier = type("FoodClassifier", (), {"get_instance": staticmethod(lambda **_kwargs: None)})
sys.modules.setdefault("backend.services.food_classifier", classifier_stub)
lookup_stub = ModuleType("backend.services.nutrition_lookup")
lookup_stub.NutritionLookup = type(
    "NutritionLookup",
    (),
    {"__init__": lambda self: None, "lookup": lambda self, *_args: None},
)
sys.modules.setdefault("backend.services.nutrition_lookup", lookup_stub)

from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.routers import food_analysis
from backend.services.gemini_food_analyzer import GeminiFoodAnalyzer


def _mock_classifier():
    classifier = type("Classifier", (), {"ready": True})()
    classifier.predict = lambda _image: {
        "label": "rice_bowl",
        "food_name": "Rice Bowl",
        "confidence": 0.9,
        "low_confidence": False,
        "top3": [],
        "mock": False,
    }
    return classifier


@pytest.mark.parametrize("field", ["image", "file"])
def test_analyze_accepts_image_and_legacy_file_field(field, monkeypatch):
    async def lookup(_label, _grams):
        return {
            "calories": 180,
            "protein": 5,
            "carbs": 30,
            "fat": 4,
            "per_100g": {},
            "source": "test",
        }

    monkeypatch.setattr(food_analysis, "get_classifier", lambda: _mock_classifier())
    monkeypatch.setattr(
        food_analysis._nutrition_lookup,
        "lookup",
        AsyncMock(side_effect=lookup),
    )
    app = FastAPI()
    app.include_router(food_analysis.router)
    with TestClient(app) as client:
        response = client.post(
            "/api/food/analyze",
            files={field: ("meal.jpg", b"x" * 1200, "image/jpeg")},
            data={"mode": "standard", "grams": "100"},
        )
    assert response.status_code == 200
    assert response.json()["food_name"] == "Rice Bowl"


def test_analyze_without_upload_returns_http_400():
    app = FastAPI()
    app.include_router(food_analysis.router)
    with TestClient(app) as client:
        response = client.post("/api/food/analyze", data={"mode": "standard"})
    assert response.status_code == 400


def test_advanced_gemini_result_normalizes_fiber_ingredients_and_insights():
    response = {
        "candidates": [{"content": {"parts": [{"text": '''{
          "is_food": true,
          "food_name": "Chicken Bowl",
          "food_label": "chicken_bowl",
          "confidence": 0.94,
          "per_100g": {"calories": 150, "protein": 12, "carbs": 16, "fat": 4},
          "total_weight_grams": 350,
          "total_nutrition": {"calories": 525, "protein": 42, "carbs": 56, "fat": 14, "fiber": 7},
          "ingredients": [{"name": "Chicken", "portion_grams": 120, "calories": 198,
            "protein": 37, "carbs": 0, "fat": 4, "confidence": 0.9}],
          "health_insights": ["Good protein source"]
        }'''}]}}],
    }
    result = GeminiFoodAnalyzer(api_key="test", model="gemini-3.6-flash")._normalize_gemini_response(response, 350)
    assert result["fiber"] == 7
    assert result["grams"] == 350
    assert result["nutrition"]["calories"] == 525
    assert result["ingredients"][0]["portion_grams"] == 120
    assert result["health_insights"] == ["Good protein source"]


def test_gemini_request_uses_configured_default_and_minimal_thinking():
    with patch.dict(os.environ, {"GEMINI_FOOD_MODEL": ""}, clear=False):
        analyzer = GeminiFoodAnalyzer(api_key="test")
        assert analyzer.model == "gemini-3.6-flash"
    captured = {}

    class Response:
        status_code = 200

        def json(self):
            return {"candidates": [{"content": {"parts": [{"text": '''{
              "is_food": true, "food_name": "Meal", "food_label": "meal", "confidence": 0.8,
              "per_100g": {"calories": 100, "protein": 5, "carbs": 10, "fat": 2}
            }'''}]}}]}

    class Client:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return None

        async def post(self, _url, **kwargs):
            captured.update(kwargs)
            return Response()

    with patch("backend.services.gemini_food_analyzer.httpx.AsyncClient", Client):
        asyncio.run(analyzer.analyze(b"image-bytes"))
    config = captured["json"]["generationConfig"]
    assert config["thinkingConfig"] == {"thinkingLevel": "minimal"}
    assert "ingredients" in config["responseSchema"]["properties"]
