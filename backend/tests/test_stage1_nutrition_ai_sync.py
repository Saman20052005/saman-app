"""Stage 1 Nutrition & AI Coach sync tests.

Covers:
1. GeminiFoodAnalyzer default model ("gemini-3.5-flash-lite"), deduplicated fallback chain,
   secondary fallback ("gemini-3.1-flash-lite"), and GEMINI_FOOD_MODEL env override.
2. core3_context day_resets filtering (datetime & ISO string with/without Z/+00:00),
   compact meals list in nutrition["summary"], edit/delete reflection, and token cap bounds.
"""

import asyncio
import os
from datetime import datetime, timezone
from unittest.mock import patch

import httpx

from backend.app.services.core3_context import _is_after_day_reset, build_core3_context
from backend.services.gemini_food_analyzer import GeminiFoodAnalyzer


class _Cursor(list):
    def sort(self, *_args, **_kwargs):
        return self

    def limit(self, value):
        return _Cursor(self[:value])


class _FakeCollection:
    def __init__(self, rows, database=None):
        self.rows = list(rows)
        self.database = database
        self.calls = []

    def find(self, query, projection=None):
        self.calls.append((query, projection))
        return _Cursor(self.rows)

    def find_one(self, query, projection=None):
        self.calls.append((query, projection))
        return self.rows[0] if self.rows else None


def _ok_gemini_response(food_name="Phở Bò", food_label="pho_bo"):
    class _OkResponse:
        status_code = 200
        text = ""

        def json(self):
            return {
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {
                                    "text": (
                                        '{"is_food": true, '
                                        f'"food_name": "{food_name}", '
                                        f'"food_label": "{food_label}", '
                                        '"confidence": 0.92, '
                                        '"per_100g": {"calories": 120, "protein": 8, "carbs": 15, "fat": 3}}'
                                    )
                                }
                            ]
                        }
                    }
                ]
            }

    return _OkResponse()


def test_gemini_food_analyzer_default_model_and_dedup_fallback_chain():
    with patch.dict(os.environ, {"GEMINI_FOOD_MODEL": "", "GEMINI_FOOD_FALLBACK_MODEL": "gemini-3.5-flash-lite"}, clear=False):
        analyzer = GeminiFoodAnalyzer(api_key="test-key")
        assert analyzer.model == "gemini-3.5-flash-lite"

        called_urls = []

        class _Client:
            def __init__(self, **_kwargs):
                pass

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_args):
                return None

            async def post(self, url, **_kwargs):
                called_urls.append(url)
                if "gemini-3.5-flash-lite" in url:
                    raise httpx.ReadTimeout("primary timed out")
                return _ok_gemini_response()

        with patch("backend.services.gemini_food_analyzer.httpx.AsyncClient", _Client):
            result = asyncio.run(analyzer.analyze(b"fake-image-bytes"))

        assert result["food_name"] == "Phở Bò"
        # Must NOT call gemini-3.5-flash-lite twice; must proceed directly to secondary fallback.
        assert len(called_urls) == 2
        assert "gemini-3.5-flash-lite:generateContent" in called_urls[0]
        assert "gemini-3.1-flash-lite:generateContent" in called_urls[1]


def test_gemini_food_analyzer_respects_env_override_and_constructor():
    with patch.dict(os.environ, {"GEMINI_FOOD_MODEL": "  gemini-3.6-flash  "}, clear=False):
        env_analyzer = GeminiFoodAnalyzer(api_key="test-key")
        assert env_analyzer.model == "gemini-3.6-flash"

        ctor_analyzer = GeminiFoodAnalyzer(api_key="test-key", model="gemini-custom-model")
        assert ctor_analyzer.model == "gemini-custom-model"


def test_core3_context_filters_pre_reset_logs_and_includes_meals():
    today = "2026-11-27"
    reset_at = datetime(2026, 11, 27, 4, 0, 0, tzinfo=timezone.utc)

    resets_col = _FakeCollection([{"date": today, "reset_at": reset_at}])
    nutrition_col = _FakeCollection(
        [
            {
                "date": today,
                "created_at": datetime(2026, 11, 27, 2, 0, 0, tzinfo=timezone.utc),
                "meal_type": "breakfast",
                "foods": [{"name": "Bánh mì thịt"}],
                "total_calories": 800,
                "total_protein": 20,
                "total_carbs": 90,
                "total_fat": 30,
            },
            {
                "date": today,
                "created_at": datetime(2026, 11, 27, 5, 30, 0, tzinfo=timezone.utc),
                "meal_type": "lunch",
                "foods": [{"name": "Phở bò"}, {"food_name": "Quẩy"}],
                "total_calories": 550,
                "total_protein": 32,
                "total_carbs": 62,
                "total_fat": 14,
            },
        ],
        database={"day_resets": resets_col},
    )

    ctx = build_core3_context(
        principal={"_id": "user-1", "email": "u1@saman.test"},
        nutrition_collection=nutrition_col,
        workout_collection=_FakeCollection([]),
        users_collection=_FakeCollection([]),
        now=datetime(2026, 11, 27, 6, 0, 0, tzinfo=timezone.utc),
    )

    assert ctx["nutrition"]["status"] == "available"
    summary = ctx["nutrition"]["summary"]
    assert len(summary) == 1
    day_entry = summary[0]
    assert day_entry["date"] == today
    assert day_entry["calories"] == 550
    assert day_entry["protein_g"] == 32.0
    assert day_entry["carbs_g"] == 62.0
    assert day_entry["fat_g"] == 14.0
    assert day_entry["meals"] == [
        {
            "meal_type": "lunch",
            "foods": ["Phở bò", "Quẩy"],
            "calories": 550,
            "protein_g": 32.0,
        }
    ]


def test_core3_context_reset_supports_datetime_and_iso_strings():
    today = "2026-11-27"
    # Direct helper checks for mixed naive/aware datetime and ISO string formats
    assert _is_after_day_reset("2026-11-27T05:00:00Z", datetime(2026, 11, 27, 4, 0, 0)) is True
    assert _is_after_day_reset("2026-11-27T03:59:59+00:00", "2026-11-27T04:00:00Z") is False
    assert _is_after_day_reset(datetime(2026, 11, 27, 4, 0, 1), "2026-11-27T04:00:00+00:00") is True
    assert _is_after_day_reset(None, "2026-11-27T04:00:00Z") is False
    assert _is_after_day_reset("not-a-timestamp", "2026-11-27T04:00:00Z") is False

    resets_col = _FakeCollection(
        [
            {"date": today, "reset_at": "2026-11-27T03:00:00Z"},
            {"date": today, "reset_at": "2026-11-27T04:00:00+00:00"},
        ]
    )
    nutrition_col = _FakeCollection(
        [
            {
                "date": today,
                "created_at": "2026-11-27T03:30:00Z",
                "meal_type": "breakfast",
                "foods": [{"name": "Xôi gà"}],
                "total_calories": 600,
                "total_protein": 18,
                "total_carbs": 80,
                "total_fat": 20,
            },
            {
                "date": today,
                "created_at": "2026-11-27T04:30:00",
                "meal_type": "lunch",
                "foods": [{"title": "Cơm ức gà"}],
                "total_calories": 480,
                "total_protein": 42,
                "total_carbs": 50,
                "total_fat": 10,
            },
            {
                "date": today,
                "created_at": None,
                "meal_type": "snack",
                "foods": [{"name": "Legacy log without created_at"}],
                "total_calories": 300,
                "total_protein": 5,
                "total_carbs": 40,
                "total_fat": 12,
            },
        ],
        database={"day_resets": resets_col},
    )

    ctx = build_core3_context(
        principal={"_id": "user-2", "email": "u2@saman.test"},
        nutrition_collection=nutrition_col,
        workout_collection=_FakeCollection([]),
        users_collection=_FakeCollection([]),
        now=datetime(2026, 11, 27, 6, 0, 0, tzinfo=timezone.utc),
    )

    summary = ctx["nutrition"]["summary"]
    assert len(summary) == 1
    assert summary[0]["calories"] == 480
    assert summary[0]["protein_g"] == 42.0
    assert summary[0]["meals"] == [
        {
            "meal_type": "lunch",
            "foods": ["Cơm ức gà"],
            "calories": 480,
            "protein_g": 42.0,
        }
    ]


def test_core3_context_reflects_edits_deletes_and_caps_meals_and_foods():
    today = "2026-11-27"
    # Simulate 10 meals logged in a day, each with 6 foods; verify cap of 8 meals & 4 foods/meal
    rows = [
        {
            "date": today,
            "created_at": datetime(2026, 11, 27, 1 + i, 0, 0, tzinfo=timezone.utc),
            "meal_type": f"meal_{i}",
            "foods": [{"name": f"Món {i}-{j}"} for j in range(6)],
            "total_calories": 100,
            "total_protein": 10,
            "total_carbs": 10,
            "total_fat": 2,
        }
        for i in range(10)
    ]
    nutrition_col = _FakeCollection(rows)

    ctx = build_core3_context(
        principal={"_id": "user-3", "email": "u3@saman.test"},
        nutrition_collection=nutrition_col,
        workout_collection=_FakeCollection([]),
        users_collection=_FakeCollection([]),
        now=datetime(2026, 11, 27, 12, 0, 0, tzinfo=timezone.utc),
    )

    entry = ctx["nutrition"]["summary"][0]
    assert entry["calories"] == 1000
    assert len(entry["meals"]) == 8
    assert all(len(m["foods"]) == 4 for m in entry["meals"])

    # Simulate deleting all but 1 edited meal
    nutrition_col.rows = [
        {
            "date": today,
            "created_at": datetime(2026, 11, 27, 12, 0, 0, tzinfo=timezone.utc),
            "meal_type": "dinner",
            "foods": [{"name": "Cá hồi áp chảo"}],
            "total_calories": 420,
            "total_protein": 38,
            "total_carbs": 5,
            "total_fat": 26,
        }
    ]
    ctx_after = build_core3_context(
        principal={"_id": "user-3", "email": "u3@saman.test"},
        nutrition_collection=nutrition_col,
        workout_collection=_FakeCollection([]),
        users_collection=_FakeCollection([]),
        now=datetime(2026, 11, 27, 13, 0, 0, tzinfo=timezone.utc),
    )

    entry_after = ctx_after["nutrition"]["summary"][0]
    assert entry_after["calories"] == 420
    assert entry_after["protein_g"] == 38.0
    assert entry_after["meals"] == [
        {
            "meal_type": "dinner",
            "foods": ["Cá hồi áp chảo"],
            "calories": 420,
            "protein_g": 38.0,
        }
    ]
