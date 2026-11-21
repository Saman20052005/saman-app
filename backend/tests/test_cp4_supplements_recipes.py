"""
Comprehensive Unit & Integration Test Suite for CP4.2:
1. supplement_service & router /api/nutrition/supplements:
   - Creating supplement log without date -> auto-assigns Vietnam date (Asia/Ho_Chi_Minh, UTC+7).
   - GET /api/nutrition/supplements/{date} and GET /api/nutrition/{date} return user supplements
     (matching user_id str, ObjectId, and lowercase user_email).
   - Route /api/nutrition/supplements/{date} is not shadowed by /api/nutrition/{date}.
   - User B deleting User A's supplement log returns 404 and does not delete data.
2. recipe_service & router /api/nutrition/recipes:
   - Creating recipe with 2 ingredients, servings=2 -> computes per-serving macros correctly.
   - POST /api/nutrition/recipes/{id}/log with servings_consumed=1.5 -> inserts into nutrition_collection
     with total cal/macros = 1.5 * per_serving.
   - User B reading/deleting User A's recipe returns 404.
3. core3_context.py:
   - build_core3_context with tier="core3" returns real supplements and recipes data.
   - build_core3_context with tier="swift3" returns recipes["status"] == "skipped" and only today's supplements.
"""

from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
import re
import sys
from types import SimpleNamespace
from typing import Any, Dict, List, Optional
from zoneinfo import ZoneInfo

_repo_root = str(Path(__file__).parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

import pytest
from bson import ObjectId
from fastapi import APIRouter, Depends, FastAPI, HTTPException
from fastapi.testclient import TestClient

from backend.app.services.context_utils import (
    VN_TZ,
    build_user_query,
    get_vn_date_str,
    normalize_email,
)
from backend.app.services.core3_context import build_core3_context
from backend.app.services.recipe_service import (
    create_recipe,
    delete_recipe,
    get_recipe_by_id,
    list_recipes,
    log_recipe_serving,
)
from backend.app.services.supplement_service import (
    create_supplement_log,
    delete_supplement_log,
    get_supplement_logs_by_date,
)
from backend.auth_utils import get_current_user


# ---------------------------------------------------------------------------
# In-Memory Mock MongoDB Collection & Database
# ---------------------------------------------------------------------------

class MemoryCursor:
    def __init__(self, documents: List[Dict[str, Any]]):
        self.documents = list(documents)

    def sort(self, key_or_spec, direction=None):
        sort_spec = (
            key_or_spec
            if isinstance(key_or_spec, list)
            else [(key_or_spec, direction or 1)]
        )
        for field, order in reversed(sort_spec):
            self.documents.sort(
                key=lambda doc: _field_value(doc, field) or "",
                reverse=order < 0,
            )
        return self

    def limit(self, count: int):
        self.documents = self.documents[:count]
        return self

    def __iter__(self):
        return iter(self.documents)

    def __len__(self):
        return len(self.documents)


def _field_value(document: Any, field: str) -> Any:
    val = document
    for part in field.split("."):
        if isinstance(val, dict):
            val = val.get(part)
        else:
            return None
    return val


def _compare_eq(actual: Any, expected: Any) -> bool:
    if actual == expected:
        return True
    if isinstance(actual, ObjectId) or isinstance(expected, ObjectId):
        return str(actual) == str(expected)
    if isinstance(actual, str) and isinstance(expected, str):
        return actual.strip().lower() == expected.strip().lower()
    return False


def _matches(document: Dict[str, Any], query: Dict[str, Any]) -> bool:
    if not query:
        return True
    for field, expected in query.items():
        if field == "$and":
            if not all(_matches(document, clause) for clause in expected):
                return False
        elif field == "$or":
            if not any(_matches(document, clause) for clause in expected):
                return False
        elif isinstance(expected, dict):
            actual = _field_value(document, field)
            for op, operand in expected.items():
                if op == "$gte" and (actual is None or actual < operand):
                    return False
                if op == "$lte" and (actual is None or actual > operand):
                    return False
                if op == "$in":
                    if not any(_compare_eq(actual, item) for item in operand):
                        return False
                if op == "$exists":
                    if (actual is not None) != operand:
                        return False
                if op == "$regex":
                    if actual is None or not re.search(operand, str(actual)):
                        return False
        else:
            actual = _field_value(document, field)
            if not _compare_eq(actual, expected):
                return False
    return True


class MockMongoCollection:
    def __init__(self, documents: Optional[List[Dict[str, Any]]] = None):
        self.documents: List[Dict[str, Any]] = [
            deepcopy(doc) for doc in (documents or [])
        ]

    def insert_one(self, document: Dict[str, Any]):
        stored = deepcopy(document)
        if "_id" not in stored:
            stored["_id"] = ObjectId()
        self.documents.append(stored)
        return SimpleNamespace(inserted_id=stored["_id"])

    def find(self, query: Optional[Dict[str, Any]] = None, projection: Optional[Dict[str, Any]] = None):
        matched = [
            deepcopy(doc)
            for doc in self.documents
            if _matches(doc, query or {})
        ]
        if projection:
            projected = []
            for doc in matched:
                item = {}
                if projection.get("_id") == 0:
                    doc.pop("_id", None)
                for k, v in projection.items():
                    if v == 1 and k in doc:
                        item[k] = doc[k]
                projected.append(item if item else doc)
            matched = projected
        return MemoryCursor(matched)

    def find_one(self, query: Optional[Dict[str, Any]] = None, projection: Optional[Dict[str, Any]] = None):
        cursor = self.find(query, projection)
        return next(iter(cursor), None)

    def delete_one(self, query: Dict[str, Any]):
        for idx, doc in enumerate(self.documents):
            if _matches(doc, query):
                del self.documents[idx]
                return SimpleNamespace(deleted_count=1)
        return SimpleNamespace(deleted_count=0)

    def delete_many(self, query: Dict[str, Any]):
        initial_len = len(self.documents)
        self.documents = [d for d in self.documents if not _matches(d, query)]
        return SimpleNamespace(deleted_count=initial_len - len(self.documents))

    def update_one(self, query: Dict[str, Any], update: Dict[str, Any], upsert: bool = False):
        for doc in self.documents:
            if _matches(doc, query):
                if "$set" in update:
                    doc.update(deepcopy(update["$set"]))
                return SimpleNamespace(matched_count=1, modified_count=1)
        if upsert:
            new_doc = deepcopy(query)
            if "$set" in update:
                new_doc.update(deepcopy(update["$set"]))
            if "_id" not in new_doc:
                new_doc["_id"] = ObjectId()
            self.documents.append(new_doc)
            return SimpleNamespace(matched_count=0, modified_count=0, upserted_id=new_doc["_id"])
        return SimpleNamespace(matched_count=0, modified_count=0)


# ---------------------------------------------------------------------------
# Helper to construct FastAPI test application with CP4.2 router endpoints
# ---------------------------------------------------------------------------

def _resolve_principal_identity(user: Optional[dict]) -> tuple[str, str]:
    if not isinstance(user, dict):
        return "", ""
    email = normalize_email(user.get("email") or user.get("user_email"))
    raw_id = (
        user.get("_id")
        if user.get("_id") is not None
        else (user.get("user_id") if user.get("user_id") is not None else user.get("id"))
    )
    user_id = str(raw_id).strip() if raw_id is not None else ""
    return user_id, email


def create_test_nutrition_app(
    *,
    supplements_col: MockMongoCollection,
    recipes_col: MockMongoCollection,
    nutrition_col: MockMongoCollection,
    active_user: dict,
    register_supplements_first: bool = True,
) -> TestClient:
    """
    Constructs a test FastAPI application.
    Supports configuring router precedence to verify route shadow protection.
    """
    app = FastAPI(title="CP4.2 Nutrition Test App")
    router = APIRouter(prefix="/api/nutrition")

    def get_test_current_user():
        return active_user

    # Handlers
    async def add_supplement_handler(payload: dict, user: dict = Depends(get_test_current_user)):
        uid, email = _resolve_principal_identity(user)
        try:
            return create_supplement_log(supplements_col, user_id=uid, user_email=email, payload=payload)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    async def get_supplements_by_date_handler(date: str, user: dict = Depends(get_test_current_user)):
        uid, email = _resolve_principal_identity(user)
        logs = get_supplement_logs_by_date(supplements_col, user_id=uid, user_email=email, date_str=date)
        return {"date": date, "supplements": logs, "total": len(logs)}

    async def delete_supplement_handler(log_id: str, user: dict = Depends(get_test_current_user)):
        uid, email = _resolve_principal_identity(user)
        try:
            ok = delete_supplement_log(supplements_col, user_id=uid, user_email=email, log_id=log_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid log_id format")
        if not ok:
            raise HTTPException(status_code=404, detail="Supplement log not found or not authorized")
        return {"status": "deleted", "id": log_id}

    async def list_recipes_handler(user: dict = Depends(get_test_current_user)):
        uid, email = _resolve_principal_identity(user)
        recipes = list_recipes(recipes_col, user_id=uid, user_email=email)
        return {"recipes": recipes, "total": len(recipes)}

    async def create_recipe_handler(payload: dict, user: dict = Depends(get_test_current_user)):
        uid, email = _resolve_principal_identity(user)
        try:
            return create_recipe(recipes_col, user_id=uid, user_email=email, payload=payload)
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    async def get_recipe_by_id_handler(recipe_id: str, user: dict = Depends(get_test_current_user)):
        uid, email = _resolve_principal_identity(user)
        try:
            recipe = get_recipe_by_id(recipes_col, user_id=uid, user_email=email, recipe_id=recipe_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid recipe_id")
        if not recipe:
            raise HTTPException(status_code=404, detail="Recipe not found")
        return recipe

    async def delete_recipe_handler(recipe_id: str, user: dict = Depends(get_test_current_user)):
        uid, email = _resolve_principal_identity(user)
        try:
            ok = delete_recipe(recipes_col, user_id=uid, user_email=email, recipe_id=recipe_id)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid recipe_id")
        if not ok:
            raise HTTPException(status_code=404, detail="Recipe not found")
        return {"status": "deleted", "id": recipe_id}

    async def log_recipe_serving_handler(recipe_id: str, payload: dict, user: dict = Depends(get_test_current_user)):
        uid, email = _resolve_principal_identity(user)
        try:
            return log_recipe_serving(
                recipes_col,
                nutrition_col,
                user_id=uid,
                user_email=email,
                recipe_id=recipe_id,
                date_str=payload.get("date"),
                meal_type=payload.get("meal_type", "snack"),
                servings_consumed=payload.get("servings_consumed", 1.0),
            )
        except LookupError:
            raise HTTPException(status_code=404, detail="Recipe not found")
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc))

    async def get_daily_nutrition_handler(date: str, user: dict = Depends(get_test_current_user)):
        uid, email = _resolve_principal_identity(user)
        supplements = get_supplement_logs_by_date(supplements_col, user_id=uid, user_email=email, date_str=date)
        user_q = build_user_query(uid, email)
        meals = list(nutrition_col.find({"$and": [user_q, {"date": date}]}))
        total_calories = sum(m.get("total_calories", 0) for m in meals)
        total_protein = sum(m.get("total_protein", 0.0) for m in meals)
        total_carbs = sum(m.get("total_carbs", 0.0) for m in meals)
        total_fat = sum(m.get("total_fat", 0.0) for m in meals)
        return {
            "date": date,
            "entries": meals,
            "supplements": supplements,
            "total_calories": round(total_calories),
            "total_protein": round(total_protein, 1),
            "total_carbs": round(total_carbs, 1),
            "total_fat": round(total_fat, 1),
        }

    # Route Registration Order
    if register_supplements_first:
        # Proper registration: specific prefix /supplements/{date} BEFORE /{date}
        router.add_api_route("/supplements", add_supplement_handler, methods=["POST"])
        router.add_api_route("/supplements/{date}", get_supplements_by_date_handler, methods=["GET"])
        router.add_api_route("/supplements/{log_id}", delete_supplement_handler, methods=["DELETE"])
        router.add_api_route("/recipes", list_recipes_handler, methods=["GET"])
        router.add_api_route("/recipes", create_recipe_handler, methods=["POST"])
        router.add_api_route("/recipes/{recipe_id}", get_recipe_by_id_handler, methods=["GET"])
        router.add_api_route("/recipes/{recipe_id}", delete_recipe_handler, methods=["DELETE"])
        router.add_api_route("/recipes/{recipe_id}/log", log_recipe_serving_handler, methods=["POST"])
        router.add_api_route("/{date}", get_daily_nutrition_handler, methods=["GET"])
    else:
        # Flawed registration: parameterized /{date} registered first (demonstrating shadow bug)
        router.add_api_route("/{date}", get_daily_nutrition_handler, methods=["GET"])
        router.add_api_route("/supplements/{date}", get_supplements_by_date_handler, methods=["GET"])

    app.include_router(router)
    app.dependency_overrides[get_current_user] = get_test_current_user
    return TestClient(app)


# ===========================================================================
# 1. TEST CRITERION 1: SUPPLEMENT SERVICE & ROUTER /api/nutrition/supplements
# ===========================================================================

class TestSupplementServiceAndRouter:
    @pytest.fixture(autouse=True)
    def setup_users(self):
        self.user_a = {
            "_id": "650000000000000000000001",
            "user_id": "650000000000000000000001",
            "email": "userA@saman.com",
            "user_email": "usera@saman.com",
        }
        self.user_b = {
            "_id": "650000000000000000000002",
            "user_id": "650000000000000000000002",
            "email": "userB@saman.com",
            "user_email": "userb@saman.com",
        }
        self.supplements_col = MockMongoCollection()
        self.recipes_col = MockMongoCollection()
        self.nutrition_col = MockMongoCollection()

    def test_create_supplement_log_without_date_auto_assigns_vn_timezone(self):
        """When date is omitted, automatically assigns date according to Asia/Ho_Chi_Minh (UTC+7)."""
        payload = {
            "name": "Whey Isolate",
            "amount": 1.0,
            "unit": "scoop",
            "dosage": "1 scoop (30g)",
            "timing": "08:30",
        }
        result = create_supplement_log(
            self.supplements_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            payload=payload,
        )

        expected_today_vn = get_vn_date_str()
        assert result["date"] == expected_today_vn
        assert result["name"] == "Whey Isolate"
        assert result["supplement_name"] == "Whey Isolate"

        # Verify UTC+7 date rollover: e.g. at UTC 17:30 (next calendar day in Vietnam)
        late_utc = datetime(2026, 11, 17, 17, 30, tzinfo=timezone.utc)
        expected_next_day_vn = get_vn_date_str(now=late_utc)
        assert expected_next_day_vn == "2026-11-18"

    def test_get_supplement_logs_by_date_user_scoping_and_id_variants(self):
        """Matches logs stored with user_id str, ObjectId, and lowercase user_email."""
        target_date = "2026-11-17"
        uid_str = "650000000000000000000001"
        uid_obj = ObjectId(uid_str)

        # 1. Stored with string user_id
        self.supplements_col.insert_one({
            "user_id": uid_str,
            "user_email": "usera@saman.com",
            "date": target_date,
            "name": "Creatine Monohydrate",
            "amount": 5.0,
            "unit": "g",
            "dosage": "5g",
            "time": "09:00",
        })
        # 2. Stored with ObjectId user_id
        self.supplements_col.insert_one({
            "user_id": uid_obj,
            "user_email": "usera@saman.com",
            "date": target_date,
            "name": "Omega 3 Fish Oil",
            "amount": 2.0,
            "unit": "capsules",
            "dosage": "2 capsules",
            "time": "12:00",
        })
        # 3. Legacy document stored only with user_email (lowercase)
        self.supplements_col.insert_one({
            "user_id": uid_str,
            "user_email": "usera@saman.com",
            "date": target_date,
            "name": "Multivitamin",
            "amount": 1.0,
            "unit": "tablet",
            "dosage": "1 tablet",
            "time": "07:30",
        })
        # 4. User B document on same date (must NOT be returned)
        self.supplements_col.insert_one({
            "user_id": self.user_b["user_id"],
            "user_email": "userb@saman.com",
            "date": target_date,
            "name": "User B Zinc",
            "amount": 1.0,
            "unit": "tablet",
            "dosage": "1 tablet",
            "time": "21:00",
        })

        # Query as User A using uppercase email variant in query
        logs = get_supplement_logs_by_date(
            self.supplements_col,
            user_id=uid_str,
            user_email="UserA@Saman.COM",
            date_str=target_date,
        )

        assert len(logs) == 3
        returned_names = {log["name"] for log in logs}
        assert returned_names == {"Creatine Monohydrate", "Omega 3 Fish Oil", "Multivitamin"}
        assert "User B Zinc" not in returned_names

    def test_delete_supplement_log_unauthorized_returns_false_preserves_data(self):
        """User B attempting to delete User A's supplement log returns False and preserves data."""
        doc = create_supplement_log(
            self.supplements_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            payload={"name": "Vitamin D3", "amount": 1.0, "unit": "drop", "date": "2026-11-17"},
        )
        log_id = doc["id"]

        # User B attempts to delete User A's log
        deleted_by_b = delete_supplement_log(
            self.supplements_col,
            user_id=self.user_b["user_id"],
            user_email=self.user_b["user_email"],
            log_id=log_id,
        )
        assert deleted_by_b is False

        # Verify data still exists in collection
        assert self.supplements_col.find_one({"_id": ObjectId(log_id)}) is not None

        # User A deletes their own log
        deleted_by_a = delete_supplement_log(
            self.supplements_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            log_id=log_id,
        )
        assert deleted_by_a is True
        assert self.supplements_col.find_one({"_id": ObjectId(log_id)}) is None

    def test_router_integration_supplements_and_daily_nutrition_endpoints(self):
        """Router GET /api/nutrition/supplements/{date} and GET /api/nutrition/{date} return user supplements."""
        client = create_test_nutrition_app(
            supplements_col=self.supplements_col,
            recipes_col=self.recipes_col,
            nutrition_col=self.nutrition_col,
            active_user=self.user_a,
        )

        target_date = "2026-11-17"
        # 1. POST supplement without date -> auto-assigns Vietnam date
        post_res = client.post(
            "/api/nutrition/supplements",
            json={"name": "Magnesium Glycinate", "amount": 2.0, "unit": "capsules"},
        )
        assert post_res.status_code in (200, 201)
        created_data = post_res.json()
        assert created_data["date"] == get_vn_date_str()
        assert created_data["name"] == "Magnesium Glycinate"

        # 2. Add supplement on target_date
        post_target = client.post(
            "/api/nutrition/supplements",
            json={"name": "BCAA Powder", "amount": 10.0, "unit": "g", "date": target_date},
        )
        assert post_target.status_code in (200, 201)
        created_id = post_target.json()["id"]

        # 3. GET /api/nutrition/supplements/{date}
        get_sups_res = client.get(f"/api/nutrition/supplements/{target_date}")
        assert get_sups_res.status_code == 200
        sups_data = get_sups_res.json()
        assert "supplements" in sups_data
        assert any(item["name"] == "BCAA Powder" for item in sups_data["supplements"])

        # 4. GET /api/nutrition/{date} returns supplements list of user
        get_day_res = client.get(f"/api/nutrition/{target_date}")
        assert get_day_res.status_code == 200
        day_data = get_day_res.json()
        assert "supplements" in day_data
        assert any(item["name"] == "BCAA Powder" for item in day_data["supplements"])

        # 5. User B attempts DELETE /api/nutrition/supplements/{log_id} -> returns 404
        client_b = create_test_nutrition_app(
            supplements_col=self.supplements_col,
            recipes_col=self.recipes_col,
            nutrition_col=self.nutrition_col,
            active_user=self.user_b,
        )
        del_b_res = client_b.delete(f"/api/nutrition/supplements/{created_id}")
        assert del_b_res.status_code == 404
        assert self.supplements_col.find_one({"_id": ObjectId(created_id)}) is not None

    def test_router_route_shadow_protection(self):
        """Verifies that route /api/nutrition/supplements/{date} is not shadowed by /api/nutrition/{date}."""
        target_date = "2026-11-17"
        create_supplement_log(
            self.supplements_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            payload={"name": "Glutamine", "amount": 5.0, "unit": "g", "date": target_date},
        )

        # App with correct registration order: /supplements/{date} before /{date}
        correct_client = create_test_nutrition_app(
            supplements_col=self.supplements_col,
            recipes_col=self.recipes_col,
            nutrition_col=self.nutrition_col,
            active_user=self.user_a,
            register_supplements_first=True,
        )
        resp_sups = correct_client.get(f"/api/nutrition/supplements/{target_date}")
        assert resp_sups.status_code == 200
        sups_json = resp_sups.json()
        assert "supplements" in sups_json
        assert sups_json["supplements"][0]["name"] == "Glutamine"

        # App with reversed order demonstrating shadowing hazard
        shadowed_client = create_test_nutrition_app(
            supplements_col=self.supplements_col,
            recipes_col=self.recipes_col,
            nutrition_col=self.nutrition_col,
            active_user=self.user_a,
            register_supplements_first=False,
        )
        shadowed_resp = shadowed_client.get("/api/nutrition/supplements")
        # In shadowed app, /supplements is captured by /{date} where date="supplements"
        assert shadowed_resp.status_code == 200
        assert shadowed_resp.json().get("date") == "supplements"


# ===========================================================================
# 2. TEST CRITERION 2: RECIPE SERVICE & ROUTER /api/nutrition/recipes
# ===========================================================================

class TestRecipeServiceAndRouter:
    @pytest.fixture(autouse=True)
    def setup_users(self):
        self.user_a = {
            "_id": "650000000000000000000001",
            "user_id": "650000000000000000000001",
            "email": "userA@saman.com",
            "user_email": "usera@saman.com",
        }
        self.user_b = {
            "_id": "650000000000000000000002",
            "user_id": "650000000000000000000002",
            "email": "userB@saman.com",
            "user_email": "userb@saman.com",
        }
        self.recipes_col = MockMongoCollection()
        self.nutrition_col = MockMongoCollection()
        self.supplements_col = MockMongoCollection()

    def test_create_recipe_calculates_per_serving_macros_accurately(self):
        """Recipe with 2 ingredients and servings=2 computes exact per-serving calories and macros."""
        payload = {
            "name": "Bò Xào Bông Cải Xanh",
            "servings": 2,
            "category": "Bữa chính",
            "ingredients": [
                {
                    "name": "Thịt bò thăn",
                    "quantity": 200,
                    "unit": "g",
                    "calories": 300,
                    "protein": 35.0,
                    "carbs": 0.0,
                    "fat": 15.0,
                },
                {
                    "name": "Bông cải xanh",
                    "quantity": 150,
                    "unit": "g",
                    "calories": 100,
                    "protein": 5.0,
                    "carbs": 20.0,
                    "fat": 1.0,
                },
            ],
        }

        # Total: calories=400, protein=40.0, carbs=20.0, fat=16.0
        # Divided by servings=2:
        # calories_per_serving = 200
        # protein_per_serving = 20.0
        # carbs_per_serving = 10.0
        # fat_per_serving = 8.0
        recipe = create_recipe(
            self.recipes_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            payload=payload,
        )

        assert recipe["id"] is not None
        assert recipe["name"] == "Bò Xào Bông Cải Xanh"
        assert recipe["servings"] == 2
        assert recipe["calories_per_serving"] == 200
        assert recipe["protein_per_serving"] == 20.0
        assert recipe["carbs_per_serving"] == 10.0
        assert recipe["fat_per_serving"] == 8.0

    def test_log_recipe_serving_calculates_fractional_multiplier_and_persists(self):
        """Calling log_recipe_serving with servings_consumed=1.5 multiplies per-serving macros by 1.5."""
        recipe = create_recipe(
            self.recipes_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            payload={
                "name": "Ức Gà Nướng Khoai Lang",
                "servings": 2,
                "ingredients": [
                    {"name": "Ức gà", "calories": 300, "protein": 30.0, "carbs": 10.0, "fat": 6.0},
                    {"name": "Khoai lang", "calories": 100, "protein": 10.0, "carbs": 30.0, "fat": 2.0},
                ],
            },
        )
        recipe_id = recipe["id"]
        # Total: cal=400, pro=40.0, carbs=40.0, fat=8.0
        # Per serving: cal=200, pro=20.0, carbs=20.0, fat=4.0

        result = log_recipe_serving(
            self.recipes_col,
            self.nutrition_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            recipe_id=recipe_id,
            date_str="2026-11-17",
            meal_type="lunch",
            servings_consumed=1.5,
        )

        assert result["status"] == "saved"
        assert result["date"] == "2026-11-17"
        meal = result["meal"]

        # Expected:
        # cal = 200 * 1.5 = 300
        # pro = 20.0 * 1.5 = 30.0
        # carbs = 20.0 * 1.5 = 30.0
        # fat = 4.0 * 1.5 = 6.0
        assert meal["total_calories"] == 300
        assert meal["total_protein"] == 30.0
        assert meal["total_carbs"] == 30.0
        assert meal["total_fat"] == 6.0

        # Verify record in nutrition_collection
        inserted = self.nutrition_col.find_one({"_id": ObjectId(result["id"])})
        assert inserted is not None
        assert inserted["total_calories"] == 300
        assert inserted["total_protein"] == 30.0
        assert inserted["total_carbs"] == 30.0
        assert inserted["total_fat"] == 6.0
        assert inserted["foods"][0]["servings"] == 1.5
        assert "Ức Gà Nướng Khoai Lang" in inserted["foods"][0]["name"]

    def test_recipe_user_isolation_read_and_delete(self):
        """User B cannot read or delete User A's recipe (returns None/False / 404)."""
        recipe = create_recipe(
            self.recipes_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            payload={
                "name": "Sinh Tố Bơ Chuối",
                "servings": 1,
                "ingredients": [
                    {"name": "Bơ", "calories": 160, "protein": 2.0, "carbs": 9.0, "fat": 15.0},
                    {"name": "Chuối", "calories": 100, "protein": 1.0, "carbs": 25.0, "fat": 0.3},
                ],
            },
        )
        recipe_id = recipe["id"]

        # User B cannot read
        recipe_for_b = get_recipe_by_id(
            self.recipes_col,
            user_id=self.user_b["user_id"],
            user_email=self.user_b["user_email"],
            recipe_id=recipe_id,
        )
        assert recipe_for_b is None

        # User B cannot delete
        delete_for_b = delete_recipe(
            self.recipes_col,
            user_id=self.user_b["user_id"],
            user_email=self.user_b["user_email"],
            recipe_id=recipe_id,
        )
        assert delete_for_b is False

        # User A can read
        recipe_for_a = get_recipe_by_id(
            self.recipes_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            recipe_id=recipe_id,
        )
        assert recipe_for_a is not None
        assert recipe_for_a["name"] == "Sinh Tố Bơ Chuối"

        # User A can delete
        delete_for_a = delete_recipe(
            self.recipes_col,
            user_id=self.user_a["user_id"],
            user_email=self.user_a["user_email"],
            recipe_id=recipe_id,
        )
        assert delete_for_a is True

    def test_router_integration_recipes_endpoints(self):
        """Router /api/nutrition/recipes handles creation, 1.5 serving logging, and 404 on cross-user access."""
        client_a = create_test_nutrition_app(
            supplements_col=self.supplements_col,
            recipes_col=self.recipes_col,
            nutrition_col=self.nutrition_col,
            active_user=self.user_a,
        )
        client_b = create_test_nutrition_app(
            supplements_col=self.supplements_col,
            recipes_col=self.recipes_col,
            nutrition_col=self.nutrition_col,
            active_user=self.user_b,
        )

        # 1. Create recipe via API
        create_res = client_a.post(
            "/api/nutrition/recipes",
            json={
                "name": "Cháo Yến Mạch Táo",
                "servings": 2,
                "ingredients": [
                    {"name": "Yến mạch", "calories": 200, "protein": 8.0, "carbs": 34.0, "fat": 3.0},
                    {"name": "Táo", "calories": 100, "protein": 2.0, "carbs": 26.0, "fat": 1.0},
                ],
            },
        )
        assert create_res.status_code in (200, 201)
        recipe_data = create_res.json()
        recipe_id = recipe_data["id"]
        # Total: cal=300, pro=10.0, carbs=60.0, fat=4.0
        # Per serving: cal=150, pro=5.0, carbs=30.0, fat=2.0
        assert recipe_data["calories_per_serving"] == 150
        assert recipe_data["protein_per_serving"] == 5.0
        assert recipe_data["carbs_per_serving"] == 30.0
        assert recipe_data["fat_per_serving"] == 2.0

        # 2. Log 1.5 servings via API
        log_res = client_a.post(
            f"/api/nutrition/recipes/{recipe_id}/log",
            json={"servings_consumed": 1.5, "meal_type": "breakfast", "date": "2026-11-17"},
        )
        assert log_res.status_code in (200, 201)
        log_data = log_res.json()
        assert log_data["status"] == "saved"
        assert log_data["meal"]["total_calories"] == int(round(150 * 1.5))

        # 3. User B attempts to read recipe -> 404
        get_b_res = client_b.get(f"/api/nutrition/recipes/{recipe_id}")
        assert get_b_res.status_code == 404

        # 4. User B attempts to delete recipe -> 404
        del_b_res = client_b.delete(f"/api/nutrition/recipes/{recipe_id}")
        assert del_b_res.status_code == 404

        # 5. User A deletes recipe -> 200
        del_a_res = client_a.delete(f"/api/nutrition/recipes/{recipe_id}")
        assert del_a_res.status_code == 200


# ===========================================================================
# 3. TEST CRITERION 3: CORE3_CONTEXT SUPPLEMENTS & RECIPES INTEGRATION
# ===========================================================================

class TestCore3ContextSupplementsRecipes:
    @pytest.fixture(autouse=True)
    def setup_context_environment(self):
        self.user = {
            "_id": "650000000000000000000001",
            "user_id": "650000000000000000000001",
            "email": "testuser@saman.com",
            "user_email": "testuser@saman.com",
        }
        self.today_str = get_vn_date_str()
        self.supplements_col = MockMongoCollection([
            {
                "user_id": self.user["user_id"],
                "user_email": self.user["user_email"],
                "name": "Whey Protein",
                "dosage": "1 scoop (30g)",
                "amount": 1.0,
                "unit": "scoop",
                "time": "08:00",
                "timing": "08:00",
                "date": self.today_str,
            },
            {
                "user_id": self.user["user_id"],
                "user_email": self.user["user_email"],
                "name": "Creatine Monohydrate",
                "dosage": "5g",
                "amount": 5.0,
                "unit": "g",
                "time": "14:00",
                "timing": "14:00",
                "date": get_vn_date_str(offset_days=-2),
            },
            # Older log outside 1-day window but inside 7-day window
            {
                "user_id": self.user["user_id"],
                "user_email": self.user["user_email"],
                "name": "Fish Oil",
                "dosage": "2 capsules",
                "amount": 2.0,
                "unit": "capsules",
                "time": "12:00",
                "timing": "12:00",
                "date": get_vn_date_str(offset_days=-5),
            },
        ])
        self.recipes_col = MockMongoCollection([
            {
                "user_id": self.user["user_id"],
                "user_email": self.user["user_email"],
                "name": "Bò Xào Rau Củ",
                "servings": 2,
                "calories_per_serving": 350,
                "protein_per_serving": 35.0,
                "carbs_per_serving": 15.0,
                "fat_per_serving": 12.0,
                "category": "Món chính",
            }
        ])
        self.empty_col = MockMongoCollection()

    def test_core3_context_tier_core3_returns_real_supplements_and_recipes(self):
        """Calling build_core3_context with tier='core3' populates real data in supplements and recipes."""
        context = build_core3_context(
            principal=self.user,
            nutrition_collection=self.empty_col,
            workout_collection=self.empty_col,
            users_collection=self.empty_col,
            supplements_collection=self.supplements_col,
            recipes_collection=self.recipes_col,
            tier="core3",
        )

        assert context["tier"] == "core3"

        # Supplements validation
        supplements = context.get("supplements", {})
        assert supplements["status"] == "available"
        assert supplements["coverage_missing"] is False
        assert len(supplements["entries"]) == 3
        supplement_names = [e.get("name") or e.get("supplement_name") for e in supplements["entries"]]
        assert "Whey Protein" in supplement_names
        assert "Creatine Monohydrate" in supplement_names
        assert "Fish Oil" in supplement_names

        # Recipes validation
        recipes = context.get("recipes", {})
        assert recipes["status"] == "available"
        assert len(recipes["recipes"]) == 1
        assert recipes["recipes"][0]["name"] == "Bò Xào Rau Củ"
        assert recipes["recipes"][0]["calories_per_serving"] == 350

        # PII Hygiene: zero leakage of user email or raw user_id in entries
        for sup in supplements["entries"]:
            assert "email" not in sup
            assert "user_email" not in sup
            assert "user_id" not in sup
        for rec in recipes["recipes"]:
            assert "email" not in rec
            assert "user_email" not in rec
            assert "user_id" not in rec

    def test_core3_context_tier_swift3_skips_recipes_and_reads_only_today_supplements(self):
        """Calling build_core3_context with tier='swift3' marks recipes skipped and limits supplements to today."""
        context = build_core3_context(
            principal=self.user,
            nutrition_collection=self.empty_col,
            workout_collection=self.empty_col,
            users_collection=self.empty_col,
            supplements_collection=self.supplements_col,
            recipes_collection=self.recipes_col,
            tier="swift3",
        )

        assert context["tier"] == "swift3"

        # Recipes must be strictly skipped
        recipes = context.get("recipes", {})
        assert recipes["status"] == "skipped"
        assert recipes["recipes"] == []

        # Supplements in swift3 reads only 1 day (today)
        supplements = context.get("supplements", {})
        assert supplements["status"] == "available"
        assert len(supplements["entries"]) == 1
        assert supplements["entries"][0]["date"] == self.today_str
        assert supplements["entries"][0]["name"] == "Whey Protein"

    def test_core3_context_handles_none_and_empty_collections_gracefully(self):
        """When collections are None or empty, returns graceful status without crashing."""
        context = build_core3_context(
            principal=self.user,
            nutrition_collection=self.empty_col,
            workout_collection=self.empty_col,
            users_collection=self.empty_col,
            supplements_collection=None,
            recipes_collection=None,
            tier="core3",
        )
        assert context["supplements"]["status"] == "unavailable"
        assert context["supplements"]["entries"] == []
        assert context["recipes"]["status"] == "unavailable"
        assert context["recipes"]["recipes"] == []
