"""Recipe service managing recipes CRUD and logging recipe servings into nutrition plans."""

from datetime import datetime, timezone
import logging
from typing import Any, Dict, List, Optional
from bson import ObjectId

try:
    from backend.app.services.context_utils import (
        build_user_query,
        get_vn_date_str,
        normalize_email,
    )
except ImportError:
    from app.services.context_utils import (
        build_user_query,
        get_vn_date_str,
        normalize_email,
    )

logger = logging.getLogger(__name__)


def _format_recipe(doc: Dict[str, Any]) -> Dict[str, Any]:
    """Convert MongoDB _id to string id and return a clean dict."""
    recipe = dict(doc)
    if "_id" in recipe:
        recipe["id"] = str(recipe.pop("_id"))
    elif "id" in recipe and recipe["id"] is not None:
        recipe["id"] = str(recipe["id"])
    return recipe


def _normalize_target_date(date_str: Optional[str]) -> str:
    """Normalize date to YYYY-MM-DD or fall back to current Vietnam date string."""
    if not date_str:
        return get_vn_date_str()
    candidate = str(date_str).strip()
    try:
        return datetime.strptime(candidate, "%Y-%m-%d").strftime("%Y-%m-%d")
    except (TypeError, ValueError):
        return get_vn_date_str()


def create_recipe(
    collection,
    *,
    user_id: str,
    user_email: str,
    payload: dict,
) -> dict:
    """Validate payload, compute per-serving macros, and save recipe to MongoDB."""
    if not isinstance(payload, dict):
        raise ValueError("Payload must be a dictionary")

    raw_name = payload.get("name")
    if not isinstance(raw_name, str) or not raw_name.strip():
        raise ValueError("Recipe name cannot be empty")
    name = raw_name.strip()

    raw_servings = payload.get("servings")
    if raw_servings is None:
        raise ValueError("Servings must be greater than 0")
    try:
        servings_val = float(raw_servings)
    except (TypeError, ValueError):
        raise ValueError("Servings must be a positive number")
    if servings_val <= 0:
        raise ValueError("Servings must be greater than 0")

    ingredients = payload.get("ingredients")
    if not isinstance(ingredients, list) or len(ingredients) == 0:
        raise ValueError("Ingredients must be a non-empty list")

    total_calories = 0.0
    total_protein = 0.0
    total_carbs = 0.0
    total_fat = 0.0

    for item in ingredients:
        if isinstance(item, dict):
            total_calories += float(item.get("calories") or 0)
            total_protein += float(item.get("protein") or 0)
            total_carbs += float(item.get("carbs") or 0)
            total_fat += float(item.get("fat") or 0)
        else:
            total_calories += float(getattr(item, "calories", 0) or 0)
            total_protein += float(getattr(item, "protein", 0) or 0)
            total_carbs += float(getattr(item, "carbs", 0) or 0)
            total_fat += float(getattr(item, "fat", 0) or 0)

    calories_per_serving = int(round(total_calories / servings_val))
    protein_per_serving = round(total_protein / servings_val, 1)
    carbs_per_serving = round(total_carbs / servings_val, 1)
    fat_per_serving = round(total_fat / servings_val, 1)

    now_utc = datetime.utcnow()
    doc = dict(payload)
    doc["name"] = name
    doc["servings"] = int(servings_val) if servings_val.is_integer() else servings_val
    doc["ingredients"] = ingredients
    doc["calories_per_serving"] = calories_per_serving
    doc["protein_per_serving"] = protein_per_serving
    doc["carbs_per_serving"] = carbs_per_serving
    doc["fat_per_serving"] = fat_per_serving
    doc["user_id"] = str(user_id) if user_id is not None else ""
    doc["user_email"] = normalize_email(user_email)
    doc["date"] = _normalize_target_date(payload.get("date"))
    doc["created_at"] = now_utc
    doc["updated_at"] = now_utc

    doc.pop("_id", None)
    doc.pop("id", None)

    if collection is None:
        raise RuntimeError("Recipe collection is not initialized")

    result = collection.insert_one(doc)
    doc["id"] = str(result.inserted_id)
    doc.pop("_id", None)
    return doc


def list_recipes(
    collection,
    *,
    user_id: str,
    user_email: str,
    limit: int = 50,
) -> list[dict]:
    """Query user recipes sorted descending by updated_at / created_at."""
    if collection is None:
        return []

    query = build_user_query(user_id, user_email)
    safe_limit = max(1, int(limit)) if limit else 50
    cursor = (
        collection.find(query)
        .sort([("updated_at", -1), ("created_at", -1)])
        .limit(safe_limit)
    )

    return [_format_recipe(doc) for doc in cursor]


def get_recipe_by_id(
    collection,
    *,
    user_id: str,
    user_email: str,
    recipe_id: str,
) -> dict | None:
    """Fetch a single recipe scoped to the user by recipe_id."""
    if not recipe_id or not ObjectId.is_valid(str(recipe_id)):
        raise ValueError("Invalid recipe_id")

    if collection is None:
        return None

    query = {
        "$and": [
            build_user_query(user_id, user_email),
            {"_id": ObjectId(str(recipe_id))},
        ]
    }
    doc = collection.find_one(query)
    if not doc:
        return None
    return _format_recipe(doc)


def delete_recipe(
    collection,
    *,
    user_id: str,
    user_email: str,
    recipe_id: str,
) -> bool:
    """Delete a recipe scoped to the user by recipe_id."""
    if not recipe_id or not ObjectId.is_valid(str(recipe_id)):
        raise ValueError("Invalid recipe_id")

    if collection is None:
        return False

    query = {
        "$and": [
            build_user_query(user_id, user_email),
            {"_id": ObjectId(str(recipe_id))},
        ]
    }
    result = collection.delete_one(query)
    return bool(result.deleted_count > 0)


def log_recipe_serving(
    recipes_col,
    nutrition_col,
    *,
    user_id: str,
    user_email: str,
    recipe_id: str,
    date_str: str | None = None,
    meal_type: str = "snack",
    servings_consumed: float = 1.0,
) -> dict:
    """Log consumed recipe servings into nutrition plans collection."""
    recipe = get_recipe_by_id(
        recipes_col,
        user_id=user_id,
        user_email=user_email,
        recipe_id=recipe_id,
    )
    if recipe is None:
        raise LookupError("Recipe not found")

    target_date = _normalize_target_date(date_str)

    try:
        consumed = float(servings_consumed if servings_consumed is not None else 1.0)
    except (TypeError, ValueError):
        consumed = 1.0

    if consumed <= 0:
        raise ValueError("servings_consumed must be greater than 0")

    cal_per = float(recipe.get("calories_per_serving") or 0)
    pro_per = float(recipe.get("protein_per_serving") or 0)
    carbs_per = float(recipe.get("carbs_per_serving") or 0)
    fat_per = float(recipe.get("fat_per_serving") or 0)

    cals = int(round(cal_per * consumed))
    pro = round(pro_per * consumed, 1)
    carbs = round(carbs_per * consumed, 1)
    fat = round(fat_per * consumed, 1)

    now_utc = datetime.utcnow()
    clean_meal_type = str(meal_type or "snack").strip().lower() or "snack"

    meal_doc = {
        "user_id": str(user_id) if user_id is not None else "",
        "user_email": normalize_email(user_email),
        "date": target_date,
        "meal_type": clean_meal_type,
        "recipe_id": recipe["id"],
        "foods": [
            {
                "name": f"{recipe['name']} ({consumed:g} phần)",
                "calories": cals,
                "protein": pro,
                "carbs": carbs,
                "fat": fat,
                "recipe_id": recipe["id"],
                "servings": consumed,
            }
        ],
        "total_calories": cals,
        "total_protein": pro,
        "total_carbs": carbs,
        "total_fat": fat,
        "created_at": now_utc,
        "updated_at": now_utc,
    }

    if nutrition_col is None:
        raise RuntimeError("Nutrition collection is not initialized")

    result = nutrition_col.insert_one(meal_doc)
    meal = dict(meal_doc)
    meal["id"] = str(result.inserted_id)
    meal.pop("_id", None)

    return {
        "id": str(result.inserted_id),
        "status": "saved",
        "date": target_date,
        "meal": meal,
    }
