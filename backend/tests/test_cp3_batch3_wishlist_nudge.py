"""
Comprehensive pytest test suite for CP3.4 Backend:
1. Saman Shop Wishlist Sync (GET /api/shop/wishlist & PUT /api/shop/wishlist):
   - Unauthenticated requests (no auth token / invalid token) strictly return 401 Unauthorized.
   - PUT /api/shop/wishlist with duplicate IDs and leading/trailing whitespace:
     deduplicates while strictly preserving initial order, trims whitespace, drops empty strings,
     and persists into both users.preferences.saved_product_ids and profile.preferences.saved_product_ids,
     updating preferences.wishlist_updated_at.
   - Account Isolation: GET /api/shop/wishlist for User A returns exclusively User A's wishlist,
     never leaking or exposing items from User B.
   - Catalog Status Agnostic: IDs for hidden, drafted, discontinued, or non-public products
     are preserved completely intact during GET and PUT operations.
   - Legacy Fallback: GET /api/shop/wishlist gracefully falls back to profile.preferences.saved_product_ids
     when top-level preferences.saved_product_ids is omitted.

2. Daily Brief AI Nudge (GET /api/chat/daily-brief):
   - Active Journey Pending: When an active journey has pending tasks for today (not a rest day),
     triggers nudge.id == "journey_task_nudge" stating exact day_index/total_days and first pending task title.
   - Rest Day / Completed Journey Fallthrough: When today is a rest day or all daily tasks are completed,
     journey task nudge does not fire, falling through to nutrition/water/workout checks.
   - Protein Gap: When protein intake < 70% of daily target, triggers nudge.id == "protein_gap_nudge"
     with exact remaining protein (target - consumed) without hallucinated numbers.
   - Water Gap: When water intake < 50% of daily target (and protein >= 70%),
     triggers nudge.id == "water_gap_nudge" stating exact consumed ml / target ml.
   - Workout Pending: When hydration and protein criteria are met but worked_out_today is False,
     triggers nudge.id == "workout_pending_nudge".
   - On Track: When workout is completed and hydration/protein targets are satisfied,
     triggers nudge.id == "on_track_nudge".
   - Backward Compatibility: Preserves all legacy fields (status, date, brief, chips, metrics, nudge)
     with consistent schemas and valid values.
"""

from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
import re
import sys
from types import SimpleNamespace
from typing import Any, Dict, List, Optional

_repo_root = str(Path(__file__).parents[2].resolve())
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

# Compatibility aliases on models.shop before importing routers
import backend.app.models.shop as _shop_models

for _attr, _alias in [
    ("ActiveIngredient", "ActiveIngredientModel"),
    ("AllergenStatus", "AllergenStatusEnum"),
    ("ApparelAttributes", "ApparelAttributesModel"),
    ("ApparelColorSwatch", "ApparelColorSwatchModel"),
    ("EquipmentAttributes", "EquipmentAttributesModel"),
    ("FoodAttributes", "FoodAttributesModel"),
    ("LifestyleAttributes", "LifestyleAttributesModel"),
    ("MacroNutrients", "MacroNutrientsModel"),
    ("SupplementAttributes", "SupplementAttributesModel"),
    ("SupplementForm", "SupplementFormEnum"),
]:
    if not hasattr(_shop_models, _alias) and hasattr(_shop_models, _attr):
        setattr(_shop_models, _alias, getattr(_shop_models, _attr))

import jwt
import pytest
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.auth.config import JWT_ALGORITHM, JWT_SECRET
from backend.auth_utils import get_current_user
from backend.app.services.context_utils import get_vn_date_str
from backend.routers.shop import router as shop_router
import backend.routers.shop as shop_module
from backend.routers.chat import router as chat_router
import backend.routers.chat as chat_module
from backend.tests.test_cp3_batch1_context import (
    FakeCursor,
    _apply_projection,
    _field_value,
    _set_field,
)


# ---------------------------------------------------------------------------
# Robust In-Memory Mongo Collection with $regex and $set support
# ---------------------------------------------------------------------------

def _safe_matches(doc, query):
    if not isinstance(query, dict):
        return doc == query
    for field, expected in query.items():
        if field == "$and":
            if not all(_safe_matches(doc, clause) for clause in expected):
                return False
        elif field == "$or":
            if not any(_safe_matches(doc, clause) for clause in expected):
                return False
        elif field == "messages.operation_id":
            msgs = doc.get("messages") or []
            op_ids = [m.get("operation_id") for m in msgs if isinstance(m, dict)]
            if isinstance(expected, dict) and "$ne" in expected:
                if expected["$ne"] in op_ids:
                    return False
            elif expected not in op_ids:
                return False
        else:
            actual = _field_value(doc, field)
            if isinstance(expected, dict):
                for op, operand in expected.items():
                    if op == "$regex":
                        flags = re.IGNORECASE if expected.get("$options") == "i" else 0
                        if not re.search(operand, str(actual or ""), flags):
                            return False
                    elif op == "$options":
                        continue
                    elif op == "$gte" and (actual is None or actual < operand):
                        return False
                    elif op == "$lte" and (actual is None or actual > operand):
                        return False
                    elif op == "$gt" and (actual is None or actual <= operand):
                        return False
                    elif op == "$lt" and (actual is None or actual >= operand):
                        return False
                    elif op == "$ne":
                        if isinstance(actual, list):
                            if operand in actual or str(operand) in [str(x) for x in actual]:
                                return False
                        elif str(actual) == str(operand):
                            return False
                    elif op == "$in":
                        if actual not in operand and str(actual) not in [str(x) for x in operand]:
                            return False
                    elif op == "$nin":
                        if actual in operand or str(actual) in [str(x) for x in operand]:
                            return False
                    elif op == "$exists":
                        if (actual is not None) != operand:
                            return False
            elif isinstance(actual, list) and not isinstance(expected, list):
                if expected not in actual and str(expected) not in [str(x) for x in actual]:
                    return False
            else:
                if actual != expected and str(actual) != str(expected):
                    return False
    return True


class WishlistNudgeFakeCollection:
    def __init__(self, name="collection", documents=None):
        self.name = name
        self.documents = [deepcopy(doc) for doc in (documents or [])]

    def find(self, query=None, projection=None):
        matches = [deepcopy(doc) for doc in self.documents if _safe_matches(doc, query or {})]
        return FakeCursor(matches, projection)

    def find_one(self, query=None, projection=None):
        cursor = self.find(query, projection)
        results = list(cursor)
        return results[0] if results else None

    def insert_one(self, document):
        doc = deepcopy(document)
        doc.setdefault("_id", ObjectId())
        self.documents.append(doc)
        return SimpleNamespace(inserted_id=doc["_id"])

    def update_one(self, filter_query, update, upsert=False):
        matching_idx = None
        for idx, doc in enumerate(self.documents):
            if _safe_matches(doc, filter_query):
                matching_idx = idx
                break

        if matching_idx is not None:
            target = self.documents[matching_idx]
            modified = False
            if "$set" in update:
                for k, v in update["$set"].items():
                    _set_field(target, k, deepcopy(v))
                modified = True
            return SimpleNamespace(matched_count=1, modified_count=1 if modified else 0, upserted_id=None)

        if upsert:
            clean_doc = {}
            for k, v in filter_query.items():
                if not k.startswith("$") and not isinstance(v, dict):
                    clean_doc[k] = v
            clean_doc.setdefault("_id", ObjectId())
            if "$set" in update:
                for k, v in update["$set"].items():
                    _set_field(clean_doc, k, deepcopy(v))
            self.documents.append(clean_doc)
            return SimpleNamespace(matched_count=0, modified_count=0, upserted_id=clean_doc["_id"])

        return SimpleNamespace(matched_count=0, modified_count=0, upserted_id=None)


# ---------------------------------------------------------------------------
# Test Helpers & JWT Generator
# ---------------------------------------------------------------------------

def _generate_jwt_token(email: str) -> str:
    """Generate a real valid JWT token signed with backend secret for authentication."""
    return jwt.encode({"email": email}, JWT_SECRET, algorithm=JWT_ALGORITHM)


def _auth_headers(email: str) -> Dict[str, str]:
    """Return standard Authorization Bearer header for the given email."""
    token = _generate_jwt_token(email)
    return {"Authorization": f"Bearer {token}"}


# ===========================================================================
# SUITE 1: Shop Wishlist Sync (GET /api/shop/wishlist & PUT /api/shop/wishlist)
# ===========================================================================

class TestShopWishlistSync:
    """Tests for CP3.4 Shop Wishlist sync endpoints, security, deduplication, and isolation."""

    @pytest.fixture(autouse=True)
    def setup_shop_test(self, monkeypatch):
        """Configure isolated in-memory user collection and FastAPI client."""
        self.user_a_id = ObjectId("654321654321654321654321")
        self.user_b_id = ObjectId("654321654321654321654322")

        self.user_a_doc = {
            "_id": self.user_a_id,
            "email": "user_a@example.com",
            "full_name": "Nguyen Van A",
            "preferences": {
                "saved_product_ids": ["prod_alpha_01", "prod_alpha_02"],
                "wishlist_updated_at": "2026-11-01T10:00:00+00:00",
            },
            "profile": {
                "preferences": {
                    "saved_product_ids": ["prod_alpha_01", "prod_alpha_02"],
                }
            },
        }

        self.user_b_doc = {
            "_id": self.user_b_id,
            "email": "user_b@example.com",
            "full_name": "Tran Thi B",
            "preferences": {
                "saved_product_ids": ["prod_beta_10", "prod_beta_20"],
                "wishlist_updated_at": "2026-11-02T10:00:00+00:00",
            },
            "profile": {
                "preferences": {
                    "saved_product_ids": ["prod_beta_10", "prod_beta_20"],
                }
            },
        }

        self.users_collection = WishlistNudgeFakeCollection(
            "users",
            [deepcopy(self.user_a_doc), deepcopy(self.user_b_doc)],
        )

        # Wire users collection into shop router and database module
        monkeypatch.setattr(shop_module, "_get_users_collection", lambda: self.users_collection)
        monkeypatch.setattr("backend.app.database.users_collection", self.users_collection)

        # Mock auth_utils.users_collection so get_current_user resolves from fake DB
        monkeypatch.setattr("backend.auth_utils.users_collection", self.users_collection)

        self.app = FastAPI()
        self.app.include_router(shop_router)
        self.client = TestClient(self.app)

    # 1. Authentication Gate (401)
    def test_get_wishlist_unauthenticated_returns_401(self):
        """GET /api/shop/wishlist without authorization header returns 401."""
        response = self.client.get("/api/shop/wishlist")
        assert response.status_code == 401
        data = response.json()
        assert "detail" in data

    def test_put_wishlist_unauthenticated_returns_401(self):
        """PUT /api/shop/wishlist without authorization header returns 401."""
        payload = {"saved_product_ids": ["prod_alpha_01"]}
        response = self.client.put("/api/shop/wishlist", json=payload)
        assert response.status_code == 401
        data = response.json()
        assert "detail" in data

    def test_wishlist_invalid_token_returns_401(self):
        """GET and PUT /api/shop/wishlist with forged/invalid token return 401."""
        bad_headers = {"Authorization": "Bearer forged_invalid_jwt_token_12345"}
        get_res = self.client.get("/api/shop/wishlist", headers=bad_headers)
        assert get_res.status_code == 401

        put_res = self.client.put("/api/shop/wishlist", json={"saved_product_ids": []}, headers=bad_headers)
        assert put_res.status_code == 401

    def test_wishlist_nonexistent_user_token_returns_401(self):
        """GET /api/shop/wishlist with token for nonexistent user returns 401 User not found."""
        ghost_headers = _auth_headers("ghost_user@example.com")
        res = self.client.get("/api/shop/wishlist", headers=ghost_headers)
        assert res.status_code == 401
        assert "User not found" in res.json().get("detail", "")

    # 2. Deduplication, Whitespace Trimming & Dual-Persistence
    def test_put_wishlist_deduplicates_trims_whitespace_and_preserves_order(self):
        """
        PUT /api/shop/wishlist:
        - Strips whitespace.
        - Drops duplicates while preserving initial insertion order.
        - Ignores empty or whitespace-only items.
        - Saves to both users.preferences.saved_product_ids and profile.preferences.saved_product_ids.
        - Updates preferences.wishlist_updated_at.
        """
        headers = _auth_headers("user_a@example.com")
        raw_input_ids = [
            "  prod_whey_vanilla  ",
            "prod_creatine_mono",
            "prod_whey_vanilla",      # Duplicate
            "    ",                   # Empty whitespace string
            "prod_straps_lifting",
            "prod_creatine_mono  ",   # Duplicate with trailing space
            "  prod_foam_roller  ",
        ]

        expected_clean_ids = [
            "prod_whey_vanilla",
            "prod_creatine_mono",
            "prod_straps_lifting",
            "prod_foam_roller",
        ]

        response = self.client.put(
            "/api/shop/wishlist",
            json={"saved_product_ids": raw_input_ids},
            headers=headers,
        )

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "success"
        assert data["saved_product_ids"] == expected_clean_ids

        # Verify database document persistence
        db_user = self.users_collection.find_one({"email": "user_a@example.com"})
        assert db_user is not None

        # Check top-level preferences
        top_saved = db_user.get("preferences", {}).get("saved_product_ids")
        assert top_saved == expected_clean_ids

        # Check profile-level preferences
        profile_saved = db_user.get("profile", {}).get("preferences", {}).get("saved_product_ids")
        assert profile_saved == expected_clean_ids

        # Check wishlist_updated_at is updated with recent ISO timestamp
        updated_at = db_user.get("preferences", {}).get("wishlist_updated_at")
        assert updated_at is not None
        assert "T" in updated_at

    # 3. Account Isolation
    def test_wishlist_account_isolation_user_a_and_user_b(self):
        """
        Account Isolation:
        - User A's GET returns only User A's list, zero trace of User B's items.
        - User B's GET returns only User B's list, zero trace of User A's items.
        - Modifying User A's wishlist does not alter or bleed into User B's wishlist.
        """
        headers_a = _auth_headers("user_a@example.com")
        headers_b = _auth_headers("user_b@example.com")

        # GET User A
        res_a = self.client.get("/api/shop/wishlist", headers=headers_a)
        assert res_a.status_code == 200
        data_a = res_a.json()
        assert data_a["saved_product_ids"] == ["prod_alpha_01", "prod_alpha_02"]
        for b_item in ["prod_beta_10", "prod_beta_20"]:
            assert b_item not in data_a["saved_product_ids"]

        # GET User B
        res_b = self.client.get("/api/shop/wishlist", headers=headers_b)
        assert res_b.status_code == 200
        data_b = res_b.json()
        assert data_b["saved_product_ids"] == ["prod_beta_10", "prod_beta_20"]
        for a_item in ["prod_alpha_01", "prod_alpha_02"]:
            assert a_item not in data_b["saved_product_ids"]

        # User A updates wishlist
        new_ids_a = ["prod_new_item_x1", "prod_new_item_x2"]
        put_res_a = self.client.put(
            "/api/shop/wishlist",
            json={"saved_product_ids": new_ids_a},
            headers=headers_a,
        )
        assert put_res_a.status_code == 200
        assert put_res_a.json()["saved_product_ids"] == new_ids_a

        # Confirm User B is completely unaffected
        res_b_after = self.client.get("/api/shop/wishlist", headers=headers_b)
        assert res_b_after.status_code == 200
        assert res_b_after.json()["saved_product_ids"] == ["prod_beta_10", "prod_beta_20"]

    # 4. Preservation of Non-public / Hidden / Discontinued Product IDs
    def test_wishlist_preserves_hidden_draft_and_discontinued_product_ids(self):
        """
        Wishlist acts as a pure persistent bookmark collection:
        IDs for hidden, draft, unavailable, discontinued, or legacy items
        MUST be preserved intact without being stripped or pruned by the catalog.
        """
        headers = _auth_headers("user_a@example.com")
        special_ids = [
            "prod_hidden_archived_999",
            "prod_draft_unreleased_001",
            "prod_discontinued_model_v1",
            "prod_public_regular_active",
        ]

        # PUT special IDs
        put_res = self.client.put(
            "/api/shop/wishlist",
            json={"saved_product_ids": special_ids},
            headers=headers,
        )
        assert put_res.status_code == 200
        assert put_res.json()["saved_product_ids"] == special_ids

        # GET special IDs back
        get_res = self.client.get("/api/shop/wishlist", headers=headers)
        assert get_res.status_code == 200
        assert get_res.json()["saved_product_ids"] == special_ids

        # Verify DB directly
        db_user = self.users_collection.find_one({"email": "user_a@example.com"})
        assert db_user["preferences"]["saved_product_ids"] == special_ids
        assert db_user["profile"]["preferences"]["saved_product_ids"] == special_ids

    # 5. Legacy Fallback to profile.preferences
    def test_get_wishlist_falls_back_to_profile_preferences(self):
        """When top-level preferences is missing, GET reads from profile.preferences."""
        legacy_user = {
            "_id": ObjectId("654321654321654321654330"),
            "email": "legacy_user@example.com",
            # No top-level "preferences"
            "profile": {
                "preferences": {
                    "saved_product_ids": ["legacy_item_1", "legacy_item_2"],
                }
            },
        }
        self.users_collection.insert_one(legacy_user)

        headers = _auth_headers("legacy_user@example.com")
        res = self.client.get("/api/shop/wishlist", headers=headers)
        assert res.status_code == 200
        data = res.json()
        assert data["status"] == "success"
        assert data["saved_product_ids"] == ["legacy_item_1", "legacy_item_2"]

    # 6. Empty List Clears Wishlist
    def test_put_wishlist_empty_list_clears_saved_product_ids(self):
        """PUT with empty saved_product_ids list empties the saved wishlist safely."""
        headers = _auth_headers("user_a@example.com")
        res = self.client.put("/api/shop/wishlist", json={"saved_product_ids": []}, headers=headers)
        assert res.status_code == 200
        assert res.json()["saved_product_ids"] == []

        db_user = self.users_collection.find_one({"email": "user_a@example.com"})
        assert db_user["preferences"]["saved_product_ids"] == []
        assert db_user["profile"]["preferences"]["saved_product_ids"] == []


# ===========================================================================
# SUITE 2: Daily Brief AI Nudge (GET /api/chat/daily-brief)
# ===========================================================================

class TestChatDailyBriefAiNudge:
    """Tests for CP3.4 GET /api/chat/daily-brief AI Nudge priority ladder and calculations."""

    @pytest.fixture(autouse=True)
    def setup_chat_test(self, monkeypatch):
        """Configure mock collections and dependencies for Daily Brief endpoint."""
        self.user_id = ObjectId("654321654321654321654400")
        self.user_email = "nudge_tester@example.com"
        self.today_vn = get_vn_date_str()

        self.user_doc = {
            "_id": self.user_id,
            "identity_id": str(self.user_id),
            "email": self.user_email,
            "full_name": "Nudge Tester",
            "health_stats": {
                "tdee": 2000,
                "protein_target": 120,
                "water_target_ml": 2000,
            },
            "profile": {
                "weight": 70,
            },
        }

        self.users_col = WishlistNudgeFakeCollection("users", [deepcopy(self.user_doc)])
        self.water_col = WishlistNudgeFakeCollection("water", [])
        self.nutrition_col = WishlistNudgeFakeCollection("nutrition", [])
        self.workout_col = WishlistNudgeFakeCollection("workout_history", [])
        self.weight_col = WishlistNudgeFakeCollection("weight_history", [])
        self.journeys_col = WishlistNudgeFakeCollection("journeys", [])

        # Wire collections into chat_module
        monkeypatch.setattr(chat_module, "users_col", self.users_col)
        monkeypatch.setattr(chat_module, "water_col", self.water_col)
        monkeypatch.setattr(chat_module, "nutrition_col", self.nutrition_col)
        monkeypatch.setattr(chat_module, "workout_history_col", self.workout_col)
        monkeypatch.setattr(chat_module, "workout_history_collection", self.workout_col)
        monkeypatch.setattr(chat_module, "_get_weight_history_col", lambda: self.weight_col)

        # Wire journeys collection into optional collection resolver
        def _fake_get_optional_col(attr_name, db_col_name, db=None):
            if db_col_name == "journeys":
                return self.journeys_col
            return None

        monkeypatch.setattr(chat_module, "_get_optional_collection", _fake_get_optional_col)
        monkeypatch.setattr("backend.app.database.journeys_collection", self.journeys_col)

        # FastAPI app with dependency override for authenticated user
        self.app = FastAPI()
        self.app.include_router(chat_router)
        self.app.dependency_overrides[get_current_user] = lambda: deepcopy(self.user_doc)
        self.client = TestClient(self.app)

    # 1. Active Journey Pending Task Nudge (Highest Priority)
    def test_nudge_active_journey_pending_task_today(self):
        """
        When active_journey has an incomplete task for today:
        - nudge.id == "journey_task_nudge"
        - nudge.message states exact "Ngày {day_index}/{total_days}" and the first task title.
        - metrics["journey"] contains day_index, total_days, pending_count.
        """
        journey_doc = {
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "status": "active",
            "focus": "Tăng cơ giảm mỡ",
            "total_days": 14,
            "days": [
                {
                    "day_index": 5,
                    "date": self.today_vn,
                    "is_rest_day": False,
                    "is_completed": False,
                    "tasks": [
                        {
                            "title": "Chạy bộ 3km nhẹ nhàng",
                            "type": "cardio",
                            "is_completed": False,
                        },
                        {
                            "title": "Uống đủ 2 lít nước",
                            "type": "habit",
                            "is_completed": False,
                        },
                    ],
                }
            ],
        }
        self.journeys_col.insert_one(journey_doc)

        # Even with low protein & water, journey task has top priority
        response = self.client.get("/api/chat/daily-brief")
        assert response.status_code == 200
        data = response.json()

        assert data["status"] == "success"
        assert data["date"] == self.today_vn

        nudge = data["nudge"]
        assert nudge["id"] == "journey_task_nudge"
        assert "Ngày 5/14" in nudge["message"]
        assert "Chạy bộ 3km nhẹ nhàng" in nudge["message"]
        assert "Hoàn thành sớm để giữ chuỗi" in nudge["message"]
        assert "Hành trình: còn 2 nhiệm vụ hôm nay" in nudge["supporting_line"]
        assert nudge["primary_label"] == "Hỏi Saman"

        # Check metrics.journey
        metrics = data["metrics"]
        assert "journey" in metrics
        assert metrics["journey"]["day_index"] == 5
        assert metrics["journey"]["total_days"] == 14
        assert metrics["journey"]["pending_count"] == 2

    def test_nudge_journey_rest_day_or_completed_falls_through_to_other_nudges(self):
        """
        When today is a rest day or all tasks are finished:
        journey_task_nudge does NOT trigger, falling through to protein/water/workout.
        """
        # Rest day journey
        journey_rest_day = {
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "status": "active",
            "total_days": 14,
            "days": [
                {
                    "day_index": 6,
                    "date": self.today_vn,
                    "is_rest_day": True,
                    "is_completed": False,
                    "tasks": [],
                }
            ],
        }
        self.journeys_col.insert_one(journey_rest_day)

        # Protein is deficient: 20g / 120g target (< 70%)
        self.nutrition_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "total_calories": 400,
            "total_protein": 20.0,
        })

        response = self.client.get("/api/chat/daily-brief")
        assert response.status_code == 200
        data = response.json()

        # Must fall through to protein_gap_nudge, not journey_task_nudge
        assert data["nudge"]["id"] == "protein_gap_nudge"

    # 2. Protein Gap Nudge (< 70% target)
    def test_nudge_protein_gap_exact_calculation_no_hallucination(self):
        """
        When protein < 70% of target:
        - nudge.id == "protein_gap_nudge"
        - computes exact remaining protein: round(protein_target - consumed)
        - computes exact remaining calories: max(0, calories_target - calories)
        - does NOT invent or hallucinate arbitrary numbers.
        """
        # Target: 120g protein, 2000 kcal.
        # Consumed: 35g protein (< 120 * 0.7 = 84g), 600 kcal.
        self.nutrition_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "total_calories": 600,
            "total_protein": 35.0,
        })
        # Sufficient water so water_gap doesn't compete
        self.water_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "amount_ml": 1500,
        })

        expected_rem_protein = 120 - 35  # 85g
        expected_rem_calories = 2000 - 600  # 1400 kcal

        response = self.client.get("/api/chat/daily-brief")
        assert response.status_code == 200
        data = response.json()

        nudge = data["nudge"]
        assert nudge["id"] == "protein_gap_nudge"
        assert f"còn thiếu {expected_rem_protein}g đạm" in nudge["message"]
        assert f"{expected_rem_calories} kcal" in nudge["message"]
        assert f"Còn thiếu {expected_rem_protein}g đạm" in nudge["supporting_line"]
        assert f"({expected_rem_calories} kcal, {expected_rem_protein}g đạm)" in nudge["prompt_to_send"]
        assert nudge["primary_label"] == "Gợi ý bữa ăn"

        metrics = data["metrics"]
        assert metrics["protein"] == 35.0
        assert metrics["protein_target"] == 120
        assert metrics["calories"] == 600
        assert metrics["calories_target"] == 2000

    # 3. Water Gap Nudge (< 50% target)
    def test_nudge_water_gap_exact_calculation(self):
        """
        When protein is satisfied (>= 70%) but water < 50% of target:
        - nudge.id == "water_gap_nudge"
        - states exact consumed water / target water ml.
        - calculates exact additional water needed.
        """
        # Protein satisfied: 95g / 120g target (>= 84g)
        self.nutrition_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "total_calories": 1800,
            "total_protein": 95.0,
        })
        # Water deficient: 650ml / 2000ml target (< 1000ml)
        self.water_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "amount_ml": 650,
        })

        expected_rem_water = 2000 - 650  # 1350 ml

        response = self.client.get("/api/chat/daily-brief")
        assert response.status_code == 200
        data = response.json()

        nudge = data["nudge"]
        assert nudge["id"] == "water_gap_nudge"
        assert "650/2000 ml nước" in nudge["message"]
        assert f"khoảng {expected_rem_water} ml" in nudge["message"]
        assert "650 / 2000 ml" in nudge["supporting_line"]
        assert "650ml nước hôm nay" in nudge["prompt_to_send"]
        assert nudge["primary_label"] == "Nhắc bù nước"

        metrics = data["metrics"]
        assert metrics["water_ml"] == 650
        assert metrics["water_target_ml"] == 2000

    # 4. Workout Pending Nudge (not worked_out_today)
    def test_nudge_workout_pending_when_hydration_and_protein_met(self):
        """
        When protein >= 70%, water >= 50%, but user has not logged workout today:
        - nudge.id == "workout_pending_nudge"
        - prompt_to_send suggests an appropriate workout.
        - metrics["worked_out_today"] is False.
        """
        # Protein satisfied: 100g / 120g
        self.nutrition_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "total_calories": 1900,
            "total_protein": 100.0,
        })
        # Water satisfied: 1600ml / 2000ml
        self.water_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "amount_ml": 1600,
        })
        # Zero workouts logged today

        response = self.client.get("/api/chat/daily-brief")
        assert response.status_code == 200
        data = response.json()

        nudge = data["nudge"]
        assert nudge["id"] == "workout_pending_nudge"
        assert "Hôm nay bạn chưa ghi nhận buổi tập nào" in nudge["message"]
        assert "Chưa có buổi tập hôm nay" in nudge["supporting_line"]
        assert nudge["primary_label"] == "Gợi ý buổi tập"
        assert "Gợi ý cho tôi một buổi tập phù hợp cho hôm nay" in nudge["prompt_to_send"]

        assert data["metrics"]["worked_out_today"] is False

    # 5. On Track Nudge (All goals met and workout done)
    def test_nudge_on_track_when_workout_completed_and_targets_met(self):
        """
        When user worked out today and met nutrition/hydration thresholds:
        - nudge.id == "on_track_nudge"
        - metrics["worked_out_today"] is True.
        - brief highlights positive momentum.
        """
        # Protein satisfied: 125g / 120g
        self.nutrition_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "total_calories": 2050,
            "total_protein": 125.0,
        })
        # Water satisfied: 2200ml / 2000ml
        self.water_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "amount_ml": 2200,
        })
        # Workout session completed today
        self.workout_col.insert_one({
            "user_id": str(self.user_id),
            "user_email": self.user_email,
            "date": self.today_vn,
            "plan_name": "Full Body Hypertrophy",
            "duration_minutes": 55,
        })

        response = self.client.get("/api/chat/daily-brief")
        assert response.status_code == 200
        data = response.json()

        nudge = data["nudge"]
        assert nudge["id"] == "on_track_nudge"
        assert "Phong độ hôm nay rất tốt" in nudge["message"]
        assert "Đã tập hôm nay" in nudge["supporting_line"]
        assert nudge["primary_label"] == "Tối ưu phục hồi"

        assert data["metrics"]["worked_out_today"] is True

    # 6. Backward Compatibility for Legacy Fields
    def test_daily_brief_backward_compatibility_schema(self):
        """
        Ensures complete backward compatibility of GET /api/chat/daily-brief:
        Top-level keys status, date, brief, chips, metrics, nudge are all present.
        Chips format contains label, prompt, icon.
        Metrics format contains calories, calories_target, protein, protein_target,
        water_ml, water_target_ml, worked_out_today.
        """
        response = self.client.get("/api/chat/daily-brief")
        assert response.status_code == 200
        data = response.json()

        # Top-level required keys
        for key in ["status", "date", "brief", "chips", "metrics", "nudge"]:
            assert key in data, f"Missing required backward-compatibility key: {key}"

        assert data["status"] == "success"
        assert isinstance(data["date"], str)
        assert len(data["date"]) == 10  # YYYY-MM-DD
        assert isinstance(data["brief"], str) and len(data["brief"]) > 0

        # Chips validation
        assert isinstance(data["chips"], list)
        for chip in data["chips"]:
            assert "label" in chip
            assert "prompt" in chip
            assert "icon" in chip

        # Metrics validation
        metrics = data["metrics"]
        assert "calories" in metrics
        assert "calories_target" in metrics
        assert "protein" in metrics
        assert "protein_target" in metrics
        assert "water_ml" in metrics
        assert "water_target_ml" in metrics
        assert "worked_out_today" in metrics

        # Nudge structure validation
        nudge = data["nudge"]
        for nudge_key in ["id", "message", "supporting_line", "primary_label", "secondary_label", "prompt_to_send"]:
            assert nudge_key in nudge, f"Missing nudge field: {nudge_key}"
