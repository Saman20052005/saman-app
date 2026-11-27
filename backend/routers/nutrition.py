from fastapi import APIRouter, Body, Depends, HTTPException, Header, Query, File, Form, UploadFile, status
from datetime import datetime, date, timedelta, timezone
import asyncio
from typing import Optional, List, Dict, Any, Tuple
import pydantic as pd
import logging
import unicodedata          # ✅ PATCH B
import os
from bson import ObjectId
import cloudinary
import cloudinary.uploader

import importlib.util
from pathlib import Path
from backend.auth_utils import get_current_user
from backend.app.repositories.user_repository import UserRepository
import backend.app.database as _db_module
from backend.app.database import (
    nutrition_collection,
    story_logs_collection,
    foods_collection,
    water_collection,
    user_foods_collection,  # ✅ PATCH C/D
    db,
)
workout_history_collection = getattr(_db_module, "workout_history_collection", None)
supplements_collection = getattr(_db_module, "supplements_collection", None)
recipes_collection = getattr(_db_module, "recipes_collection", None)
food_barcodes_collection = getattr(_db_module, "food_barcodes_collection", None)


def _load_service_fallback(module_alias: str, filename: str):
    svc_path = Path(__file__).resolve().parents[1] / "app" / "services" / filename
    spec = importlib.util.spec_from_file_location(module_alias, svc_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


try:
    from backend.app.services.context_utils import (
        build_user_query,
        get_vn_date_str,
        get_vn_day_range_utc,
        normalize_email,
    )
except ImportError:
    _ctx_mod = _load_service_fallback("_nutrition_context_utils", "context_utils.py")
    build_user_query = _ctx_mod.build_user_query
    get_vn_date_str = _ctx_mod.get_vn_date_str
    get_vn_day_range_utc = _ctx_mod.get_vn_day_range_utc
    normalize_email = _ctx_mod.normalize_email

try:
    from backend.app.services.supplement_service import (
        create_supplement_log,
        get_supplement_logs_by_date,
        delete_supplement_log,
    )
except ImportError:
    _sup_mod = _load_service_fallback("_nutrition_supplement_service", "supplement_service.py")
    create_supplement_log = _sup_mod.create_supplement_log
    get_supplement_logs_by_date = _sup_mod.get_supplement_logs_by_date
    delete_supplement_log = _sup_mod.delete_supplement_log

try:
    from backend.app.services.recipe_service import (
        create_recipe,
        list_recipes,
        get_recipe_by_id,
        delete_recipe,
        log_recipe_serving,
    )
except ImportError:
    _rec_mod = _load_service_fallback("_nutrition_recipe_service", "recipe_service.py")
    create_recipe = _rec_mod.create_recipe
    list_recipes = _rec_mod.list_recipes
    get_recipe_by_id = _rec_mod.get_recipe_by_id
    delete_recipe = _rec_mod.delete_recipe
    log_recipe_serving = _rec_mod.log_recipe_serving

try:
    from backend.app.services.barcode_service import (
        format_barcode_food_doc,
        lookup_barcode,
        normalize_and_validate_barcode,
        upsert_barcode_food,
    )
except ImportError:
    _bc_mod = _load_service_fallback("_nutrition_barcode_service", "barcode_service.py")
    format_barcode_food_doc = _bc_mod.format_barcode_food_doc
    lookup_barcode = _bc_mod.lookup_barcode
    normalize_and_validate_barcode = _bc_mod.normalize_and_validate_barcode
    upsert_barcode_food = _bc_mod.upsert_barcode_food
from backend.services.meal_generator import MealGeneratorService

logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/api/nutrition",
    tags=["Nutrition"],
    dependencies=[Depends(get_current_user)],
)

user_repo    = UserRepository()
meal_generator = MealGeneratorService(db_collection=foods_collection)

# Configure Cloudinary
cloudinary.config(
    cloud_name = os.getenv("CLOUDINARY_CLOUD_NAME"),
    api_key    = os.getenv("CLOUDINARY_API_KEY"),
    api_secret = os.getenv("CLOUDINARY_API_SECRET"),
)


# ─────────────────────────────────────────
# IDENTITY & LEGACY FALLBACK / MIGRATION HELPERS
# ─────────────────────────────────────────
def _resolve_user_identity(user: Optional[dict]) -> Tuple[str, str]:
    """Extract canonical (user_id, user_email) from authenticated token principal / user dict."""
    if not isinstance(user, dict):
        return "", ""
    user_email = normalize_email(user.get("email") or user.get("user_email"))
    raw_id = (
        user.get("_id")
        if user.get("_id") is not None
        else (user.get("user_id") if user.get("user_id") is not None else user.get("id"))
    )
    if raw_id is None and user_email and user_repo is not None:
        try:
            if hasattr(user_repo, "get_by_email"):
                db_user = user_repo.get_by_email(user_email)
                if isinstance(db_user, dict):
                    raw_id = (
                        db_user.get("_id")
                        if db_user.get("_id") is not None
                        else (db_user.get("user_id") if db_user.get("user_id") is not None else db_user.get("id"))
                    )
        except Exception:
            pass
    user_id = str(raw_id).strip() if raw_id is not None else ""
    return user_id, normalize_email(user_email)


def _get_user_record(current_user: Optional[dict], user_id: str, user_email: str) -> Optional[dict]:
    """Lookup full user document by canonical user_id first, falling back to email."""
    col = getattr(user_repo, "collection", None) if user_repo is not None else None
    if user_id and col is not None and hasattr(col, "find_one"):
        try:
            found = col.find_one({"_id": user_id})
            if not isinstance(found, dict) and ObjectId.is_valid(user_id):
                found = col.find_one({"_id": ObjectId(user_id)})
            if isinstance(found, dict) and (found.get("_id") is not None or found.get("email") is not None):
                return found
        except Exception:
            pass
    if user_email and user_repo is not None and hasattr(user_repo, "get_by_email"):
        try:
            found = user_repo.get_by_email(user_email)
            if isinstance(found, dict):
                return found
        except Exception:
            pass
    if isinstance(current_user, dict):
        return current_user
    return None


def migrate_legacy_nutrition_records(
    user_id: str,
    user_email: str,
    target_db=None,
) -> int:
    """Backfill canonical user_id onto legacy email-keyed nutrition documents for this user."""
    if not user_id or not user_email:
        return 0
    modified_total = 0
    db_ref = target_db if target_db is not None else db
    day_resets_col = None
    if db_ref is not None:
        try:
            day_resets_col = db_ref["day_resets"]
        except Exception:
            day_resets_col = None

    collections = [
        nutrition_collection,
        user_foods_collection,
        water_collection,
        story_logs_collection,
        day_resets_col,
    ]
    for col in collections:
        if col is None:
            continue
        try:
            if hasattr(col, "update_many"):
                res = col.update_many(
                    {
                        "user_email": user_email,
                        "$or": [{"user_id": {"$exists": False}}, {"user_id": None}, {"user_id": ""}],
                    },
                    {"$set": {"user_id": user_id}},
                )
                modified_total += int(getattr(res, "modified_count", 0) or 0)
            elif hasattr(col, "find") and hasattr(col, "update_one"):
                for doc in list(col.find({"user_email": user_email})):
                    if not doc.get("user_id") and doc.get("_id") is not None:
                        res = col.update_one({"_id": doc["_id"]}, {"$set": {"user_id": user_id}})
                        modified_total += int(getattr(res, "modified_count", 0) or 0)
        except Exception:
            pass
    return modified_total


def _find_user_docs(
    collection,
    user_id: str,
    user_email: str,
    extra_filter: Optional[Dict[str, Any]] = None,
    projection: Optional[Dict[str, Any]] = None,
    sort_field: Optional[str] = None,
    sort_dir: int = -1,
    limit: Optional[int] = None,
) -> List[Dict[str, Any]]:
    """Query collection by canonical user_id first, with fallback/merge by user_email for legacy records."""
    if collection is None:
        return []
    base = dict(extra_filter or {})
    query = {"$and": [build_user_query(user_id, user_email), base]}
    cursor = collection.find(query, projection) if projection is not None else collection.find(query)
    if sort_field and hasattr(cursor, "sort"):
        cursor = cursor.sort(sort_field, sort_dir)
    results = list(cursor)

    # Fallback for simplified in-memory test collections that do not evaluate $and/$or
    if not results and not hasattr(collection, "database"):
        seen_ids = set()
        merged: List[Dict[str, Any]] = []
        fallback_queries = []
        if user_id:
            fallback_queries.append({"user_id": user_id, **base})
        if user_email:
            fallback_queries.append({"user_email": user_email, **base})
        for fq in fallback_queries:
            fc = collection.find(fq, projection) if projection is not None else collection.find(fq)
            if sort_field and hasattr(fc, "sort"):
                fc = fc.sort(sort_field, sort_dir)
            for doc in fc:
                doc_id = doc.get("_id")
                key = str(doc_id) if doc_id is not None else id(doc)
                if key not in seen_ids:
                    seen_ids.add(key)
                    merged.append(doc)
        results = merged

    results = [
        doc for doc in results
        if doc.get("user_id") in (None, "", user_id)
        or (user_id and str(doc.get("user_id")) == user_id)
    ]
    if limit is not None:
        results = results[:limit]
    return results


def _find_one_user_doc(
    collection,
    user_id: str,
    user_email: str,
    extra_filter: Optional[Dict[str, Any]] = None,
    projection: Optional[Dict[str, Any]] = None,
) -> Optional[Dict[str, Any]]:
    """Find a single document by canonical user_id first, falling back to user_email for legacy records."""
    if collection is None:
        return None
    base = dict(extra_filter or {})
    query = {"$and": [build_user_query(user_id, user_email), base]}
    doc = collection.find_one(query, projection) if projection is not None else collection.find_one(query)
    if not isinstance(doc, dict) and not hasattr(collection, "database"):
        if user_id:
            fq = {"user_id": user_id, **base}
            doc = collection.find_one(fq, projection) if projection is not None else collection.find_one(fq)
        if not isinstance(doc, dict) and user_email:
            fq = {"user_email": user_email, **base}
            doc = collection.find_one(fq, projection) if projection is not None else collection.find_one(fq)
    if not isinstance(doc, dict):
        return None
    doc_uid = doc.get("user_id")
    if user_id and doc_uid not in (None, "", user_id) and str(doc_uid) != user_id:
        return None
    return doc


def _delete_one_user_doc(
    collection,
    user_id: str,
    user_email: str,
    extra_filter: Optional[Dict[str, Any]] = None,
):
    """Delete a single document by canonical user_id first, falling back to user_email."""
    base = dict(extra_filter or {})
    res = None
    if user_id:
        res = collection.delete_one({"user_id": user_id, **base})
        if getattr(res, "deleted_count", 0) > 0:
            return res
    if user_email:
        res = collection.delete_one({"user_email": user_email, **base})
    return res


def _delete_many_user_docs(
    collection,
    user_id: str,
    user_email: str,
    extra_filter: Optional[Dict[str, Any]] = None,
):
    """Delete matching documents across both canonical user_id and legacy user_email keys."""
    base = dict(extra_filter or {})
    if user_id:
        collection.delete_many({"user_id": user_id, **base})
    if user_email:
        collection.delete_many({"user_email": user_email, **base})


# ─────────────────────────────────────────
# HELPER
# ─────────────────────────────────────────
def _normalize_text(text: str) -> str:
    """Strip diacritics cho fuzzy search tiếng Việt: phở → pho, bún → bun, đ → d"""
    text = text.replace("đ", "d").replace("Đ", "d")
    return (
        unicodedata.normalize("NFD", text)
        .encode("ascii", "ignore")
        .decode("utf-8")
        .lower()
        .strip()
    )

def _normalize_goal(raw: str) -> str:
    raw = str(raw).lower().strip()
    if raw in ("lose", "lose_weight", "weight_loss", "cut"):
        return "weight_loss"
    if raw in ("gain", "gain_muscle", "muscle_gain", "bulk"):
        return "muscle_gain"
    return "maintain"


def _valid_or_today_date(value: Optional[str]) -> str:
    candidate = (value or "").strip()
    try:
        return datetime.strptime(candidate, "%Y-%m-%d").strftime("%Y-%m-%d")
    except (TypeError, ValueError):
        return get_vn_date_str()

async def _resolve_food_data(foods: list, user_email: str, db, user_id: str = "") -> list:
    """Lookup food data từ user_foods hoặc foods collection nếu thiếu"""
    resolved = []
    for food in foods:
        food_id = food.get("food_id", "")
        name    = food.get("name", "")
        cal     = food.get("calories", 0)
        
        # Chỉ lookup nếu name trống/Unknown HOẶC calories = 0
        needs_lookup = (
            not name or name in ("Unknown", "unknown", "") or cal == 0
        ) and food_id
        
        if needs_lookup:
            try:
                from bson import ObjectId
                oid = ObjectId(food_id)
                found = None
                # 1. Tìm trong user_foods trước (ưu tiên user_id, fallback user_email)
                user_foods_col = getattr(db, "user_foods_collection", None)
                if user_foods_col is not None:
                    found = _find_one_user_doc(user_foods_col, user_id, user_email, {"_id": oid})
                # 2. Fallback: tìm trong global foods
                if not found:
                    global_foods_col = getattr(db, "foods_collection", None)
                    if global_foods_col is not None:
                        found = global_foods_col.find_one({"_id": oid})
                
                if found:
                    weight = food.get("weight_grams", 100)
                    ratio  = weight / 100.0
                    food = {
                        **food,
                        "name":     found.get("name", name or "Unknown"),
                        "calories": round((found.get("calories", 0) or 0) * ratio),
                        "protein":  round((found.get("protein",  0) or 0) * ratio, 1),
                        "carbs":    round((found.get("carbs",    0) or 0) * ratio, 1),
                        "fat":      round((found.get("fat",      0) or 0) * ratio, 1),
                    }
            except Exception as e:
                print(f"Food lookup error: {e}")
        
        # Ensure food_id string is normalized and present if provided
        if food_id:
            food["food_id"] = str(food_id)
        resolved.append(food)
    return resolved


def _recalculate_nutrition_totals(
    resolved_foods: List[Dict[str, Any]],
    fallback_calories: Optional[int] = None,
) -> Dict[str, Any]:
    """Server-side Single Source of Truth for meal calorie & macro totals."""
    t_pro = round(sum(float(f.get("protein") or 0) for f in resolved_foods), 1)
    t_carb = round(sum(float(f.get("carbs") or 0) for f in resolved_foods), 1)
    t_fat = round(sum(float(f.get("fat") or 0) for f in resolved_foods), 1)
    if resolved_foods and any(f.get("calories") is not None for f in resolved_foods):
        t_cal = int(round(sum(float(f.get("calories") or 0) for f in resolved_foods)))
    else:
        t_cal = int(fallback_calories or 0)
    return {
        "total_calories": t_cal,
        "total_protein": t_pro,
        "total_carbs": t_carb,
        "total_fat": t_fat,
    }


# ===== SCHEMAS =====
class FoodSearchResult(pd.BaseModel):
    id: str
    name: str
    calories: float
    protein: float
    carbs: float
    fat: float
    tags: List[str]

class FoodCreate(pd.BaseModel):
    name: str
    calories: float
    protein: float
    carbs: float
    fat: float
    tags: List[str] = []
    standard_serving: int = 100
    unit: str = "g"

class NutritionEntry(pd.BaseModel):
    food_name: str
    calories: int
    protein: float
    carbs: float
    fat: float
    meal_type: str

class DailyNutrition(pd.BaseModel):
    date: str
    entries: List[NutritionEntry]
    total_calories: int
    total_protein: float
    total_carbs: float
    total_fat: float

class NutritionPlanRequest(pd.BaseModel):
    target_calories: Optional[int] = None
    goal: Optional[str] = None
    dietary_preferences: Optional[List[str]] = []
    allergies: Optional[List[str]] = []
    meal_count: int = 4
    style: str = "optimal"  # "quick" | "optimal"
    remaining_only: bool = True

class NutritionLog(pd.BaseModel):
    date: str
    meal_type: str
    foods: List[Dict[str, Any]]
    total_calories: int
    total_protein: Optional[float] = 0.0
    total_carbs: Optional[float] = 0.0
    total_fat: Optional[float] = 0.0
    notes: Optional[str] = None
    story_id: Optional[str] = None  # ← NEW: Link tới story_logs_collection

class WaterLog(pd.BaseModel):
    date: str
    amount_ml: Optional[int] = None
    delta_ml: Optional[int] = None
    version: Optional[int] = None
    idempotency_key: Optional[str] = None
    time: Optional[str] = None

class MealSwapRequest(pd.BaseModel):
    log_id: str
    food_index: int
    replacement_food_id: str

class DayResetRequest(pd.BaseModel):
    date: str  # "yyyy-MM-dd"


class QuickRelogRequest(pd.BaseModel):
    source_log_id: Optional[str] = None
    meal_type: Optional[str] = None
    foods: Optional[List[Dict[str, Any]]] = None
    date: Optional[str] = None


class NutritionLogUpdate(pd.BaseModel):
    meal_type: Optional[str] = None
    foods: Optional[List[Dict[str, Any]]] = None
    portion_multiplier: Optional[float] = None
    total_grams: Optional[float] = None
    notes: Optional[str] = None


# ─────────────────────────────────────────
# ✅ PATCH B — FOODS SEARCH (Unicode fix)
# ─────────────────────────────────────────
@router.get("/foods/search")
async def search_foods(
    q: str,
    limit: int = 20,
    current_user: dict = Depends(get_current_user),
):
    """Search foods — hỗ trợ tiếng Việt có dấu và không dấu, kèm My Food của user."""
    try:
        if foods_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        user_id, user_email = _resolve_user_identity(current_user)
        q_raw        = q.strip()
        q_normalized = _normalize_text(q_raw)

        if not q_raw:
            return {"foods": [], "total": 0}

        # 1. Search global foods: cả tên gốc (có dấu) lẫn name_search (không dấu)
        mongo_query = {"$or": [
            {"name":        {"$regex": q_raw,        "$options": "i"}},
            {"name_search": {"$regex": q_normalized, "$options": "i"}},
        ]}
        global_foods = list(
            foods_collection.find(mongo_query).limit(limit)
        )
        for f in global_foods:
            f["id"] = str(f.pop("_id", ""))
            f["source_type"] = "global"

        # 2. Search My Food của user (ưu tiên user_id, fallback user_email)
        my_foods = []
        if user_foods_collection is not None:
            text_filter = {
                "$or": [
                    {"name":        {"$regex": q_raw,        "$options": "i"}},
                    {"name_search": {"$regex": q_normalized, "$options": "i"}},
                ],
            }
            my_foods = _find_user_docs(
                user_foods_collection,
                user_id,
                user_email,
                text_filter,
                projection={"user_email": 0},
                limit=10,
            )
            for f in my_foods:
                f["id"] = str(f.pop("_id", ""))
                f.pop("user_email", None)
                f.pop("user_id", None)
                f["source_type"] = "my_food"

        combined = my_foods + global_foods
        return {"foods": combined, "total": len(combined)}

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("search_foods error: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# ✅ PATCH D — GET /foods/mine
# ─────────────────────────────────────────
@router.get("/foods/mine")
async def get_my_foods(
    current_user: dict = Depends(get_current_user),
):
    """Lấy toàn bộ My Food của user hiện tại."""
    try:
        if user_foods_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        user_id, user_email = _resolve_user_identity(current_user)
        foods = _find_user_docs(
            user_foods_collection,
            user_id,
            user_email,
            {},
            projection={"user_email": 0},
            sort_field="created_at",
            sort_dir=-1,
        )
        for f in foods:
            f["id"] = str(f.pop("_id", ""))
            f.pop("user_email", None)
            f.pop("user_id", None)
            f["source_type"] = "my_food"
        return {"foods": foods, "total": len(foods)}

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("get_my_foods error: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# ✅ PATCH C — POST /foods (My Food — lưu DB)
# ─────────────────────────────────────────
@router.post("/foods")
async def create_food(
    food: FoodCreate,
    user: dict = Depends(get_current_user),
):
    """Tạo food mới → lưu vào My Food collection của user."""
    try:
        if user_foods_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        user_id, user_email = _resolve_user_identity(user)
        doc = {
            "user_id":          user_id,
            "user_email":       user_email,
            "date":             get_vn_date_str(),
            "name":             food.name,
            "name_search":      _normalize_text(food.name),
            "calories":         food.calories,
            "protein":          food.protein,
            "carbs":            food.carbs,
            "fat":              food.fat,
            "tags":             food.tags,
            "standard_serving": food.standard_serving,
            "unit":             food.unit,
            "source":           "user_created",
            "source_type":      "my_food",
            "created_at":       datetime.utcnow(),
        }
        result = user_foods_collection.insert_one(doc)
        logger.info("My Food created: user_id=%s email=%s food=%s", user_id, user_email, food.name)

        food_res = {k: v for k, v in doc.items() if k not in ("_id", "user_id", "user_email", "created_at")}
        food_res["id"] = str(result.inserted_id)
        food_res["source_type"] = "my_food"

        return {
            "id":      str(result.inserted_id),
            "message": "Food saved to My Food",
            "food":    food_res,
            "status":  "saved",
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("create_food error: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# ✅ STABLE IDENTITY — GET /foods/{food_id}
# ─────────────────────────────────────────
@router.get("/foods/{food_id}")
async def get_food_by_id(
    food_id: str,
    current_user: dict = Depends(get_current_user),
):
    """
    Lookup food detail by stable ID.
    - Public catalog: readable by any authenticated user.
    - My Food (user_foods_collection): readable ONLY if owned by current_user.
    - Other user's custom food or missing food: 404 (no ownership leaked).
    - Invalid ObjectId format: 400 Bad Request (never 500).
    """
    if foods_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")

    from bson.errors import InvalidId
    try:
        obj_id = ObjectId(food_id)
    except (InvalidId, TypeError, ValueError):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid food ID format",
        )

    # 1. Lookup in public catalog
    global_food = foods_collection.find_one({"_id": obj_id})
    if global_food:
        global_food["id"] = str(global_food.pop("_id", ""))
        global_food["source_type"] = "global"
        return global_food

    # 2. Lookup in user's custom foods (strictly isolated by user_id with fallback to user_email)
    if user_foods_collection is not None:
        user_id, user_email = _resolve_user_identity(current_user)
        user_food = _find_one_user_doc(user_foods_collection, user_id, user_email, {"_id": obj_id})
        if user_food:
            user_food["id"] = str(user_food.pop("_id", ""))
            user_food.pop("user_email", None)
            user_food.pop("user_id", None)
            user_food["source_type"] = "my_food"
            return user_food

    # 3. Fallback lookup in shared barcode foods cache
    if food_barcodes_collection is not None:
        barcode_food = food_barcodes_collection.find_one({"_id": obj_id})
        if barcode_food:
            return format_barcode_food_doc(barcode_food)

    # 4. Not found or belongs to another user -> 404
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Food not found")


# ===== LOGS ENDPOINTS =====
@router.post("/logs")
async def create_nutrition_log(
    log: NutritionLog,
    user: dict = Depends(get_current_user),
):
    """Create nutrition log entry → persist to DB."""
    try:
        if nutrition_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        user_id, user_email = _resolve_user_identity(user)
        target_date = _valid_or_today_date(log.date)

        # Resolve food data before saving
        resolved_foods = await _resolve_food_data(log.foods, user_email, db, user_id=user_id)

        # Single source of truth for calorie & macro calculations – server-side recalculation
        totals = _recalculate_nutrition_totals(
            resolved_foods,
            fallback_calories=log.total_calories,
        )
        now_utc = datetime.utcnow()

        doc = {
            "user_id":        user_id,
            "user_email":     user_email,
            "date":           target_date,
            "meal_type":      log.meal_type,
            "foods":          resolved_foods,
            "total_calories": totals["total_calories"],
            "total_protein":  totals["total_protein"],
            "total_carbs":    totals["total_carbs"],
            "total_fat":      totals["total_fat"],
            "notes":          log.notes,
            "story_id":       log.story_id,
            "created_at":     now_utc,
            "updated_at":     now_utc,
        }
        result = nutrition_collection.insert_one(doc)
        log_payload = log.model_dump() if hasattr(log, "model_dump") else log.dict()
        log_payload["date"] = target_date
        log_payload["foods"] = resolved_foods
        log_payload["total_calories"] = totals["total_calories"]
        log_payload["total_protein"] = totals["total_protein"]
        log_payload["total_carbs"] = totals["total_carbs"]
        log_payload["total_fat"] = totals["total_fat"]
        return {
            "id":         str(result.inserted_id),
            "message":    "Nutrition log created successfully",
            "log":        log_payload,
            "created_at": now_utc.isoformat(),
            "status":     "saved",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/logs/{date}")
async def get_nutrition_logs(
    date: str,
    user: dict = Depends(get_current_user),
):
    """Get nutrition logs for specific date."""
    try:
        if nutrition_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        user_id, user_email = _resolve_user_identity(user)
        logs = _find_user_docs(
            nutrition_collection,
            user_id,
            user_email,
            {"date": date},
            sort_field="created_at",
            sort_dir=-1,
        )
        for log in logs:
            log["_id"] = str(log["_id"])

        return {"date": date, "logs": logs, "total": len(logs)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/logs/{log_id}/confirm")
async def confirm_nutrition_log(log_id: str, user: dict = Depends(get_current_user)):
    return {"id": log_id, "status": "confirmed", "confirmed_at": datetime.now().isoformat()}


@router.put("/logs/{log_id}/swap")
async def swap_meal(
    log_id: str,
    request: MealSwapRequest,
    user: dict = Depends(get_current_user),
):
    try:
        if nutrition_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        user_id, user_email = _resolve_user_identity(user)
        log = _find_one_user_doc(
            nutrition_collection,
            user_id,
            user_email,
            {"_id": ObjectId(log_id)},
        )
        if not log:
            raise HTTPException(status_code=404, detail="Log not found")

        foods = log.get("foods", [])
        if request.food_index >= len(foods):
            raise HTTPException(status_code=400, detail="food_index out of range")

        # Tìm replacement food — user_foods trước (isolated by owner), fallback global
        replacement = None
        if user_foods_collection is not None:
            try:
                replacement = _find_one_user_doc(
                    user_foods_collection,
                    user_id,
                    user_email,
                    {"_id": ObjectId(request.replacement_food_id)},
                )
            except Exception:
                pass
        if not replacement and foods_collection is not None:
            try:
                replacement = foods_collection.find_one({"_id": ObjectId(request.replacement_food_id)})
            except Exception:
                pass
        if not replacement:
            raise HTTPException(status_code=404, detail="Replacement food not found")

        # Scale theo weight_grams của food gốc
        old_food     = foods[request.food_index]
        weight_grams = old_food.get("weight_grams", 100)
        factor       = weight_grams / 100.0

        new_food = {
            "name":         replacement.get("name", "Unknown"),
            "food_id":      request.replacement_food_id,
            "weight_grams": weight_grams,
            "calories":     round((replacement.get("calories", 0) or 0) * factor),
            "protein":      round((replacement.get("protein",  0) or 0) * factor, 1),
            "carbs":        round((replacement.get("carbs",    0) or 0) * factor, 1),
            "fat":          round((replacement.get("fat",      0) or 0) * factor, 1),
        }

        foods[request.food_index] = new_food
        
        # Single source of truth for macro calculations – frontend must not recalculate
        new_total = round(sum(float(f.get("calories", 0)) for f in foods))
        new_total_pro = round(sum(float(f.get("protein", 0)) for f in foods), 1)
        new_total_carb = round(sum(float(f.get("carbs", 0)) for f in foods), 1)
        new_total_fat = round(sum(float(f.get("fat", 0)) for f in foods), 1)

        update_fields = {
            "foods":          foods,
            "total_calories": new_total,
            "total_protein":  new_total_pro,
            "total_carbs":    new_total_carb,
            "total_fat":      new_total_fat,
            "updated_at":     datetime.utcnow(),
        }
        if user_id:
            update_fields["user_id"] = user_id

        nutrition_collection.update_one(
            {"_id": ObjectId(log_id)},
            {"$set": update_fields},
        )
        return {
            "id":             log_id,
            "message":        "Meal swapped",
            "old_food":       old_food.get("name"),
            "new_food":       new_food["name"],
            "new_calories":   new_total,
            "new_total_pro":  new_total_pro,
            "new_total_carb": new_total_carb,
            "new_total_fat":  new_total_fat,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.patch("/logs/{log_id}")
async def update_nutrition_log(
    log_id: str,
    payload: NutritionLogUpdate,
    user: dict = Depends(get_current_user),
):
    """Update an existing user-owned nutrition log and recalculate totals server-side."""
    try:
        if nutrition_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        from bson.errors import InvalidId
        try:
            obj_id = ObjectId(log_id)
        except (InvalidId, TypeError, ValueError):
            raise HTTPException(status_code=404, detail="Log not found or not authorized")

        user_id, user_email = _resolve_user_identity(user)
        existing_doc = _find_one_user_doc(
            nutrition_collection,
            user_id,
            user_email,
            {"_id": obj_id},
        )
        if not existing_doc:
            raise HTTPException(status_code=404, detail="Log not found or not authorized")

        if payload.foods is not None:
            if len(payload.foods) == 0:
                raise HTTPException(
                    status_code=400,
                    detail="foods cannot be empty; use DELETE to remove log",
                )
            final_foods: List[Dict[str, Any]] = []
            for raw_item in payload.foods:
                item = dict(raw_item)
                has_explicit_macros = all(
                    item.get(k) is not None for k in ("calories", "protein", "carbs", "fat")
                )
                item_name = str(item.get("name") or "").strip()
                if has_explicit_macros and item_name and item_name.lower() != "unknown":
                    if item.get("food_id"):
                        item["food_id"] = str(item["food_id"])
                    final_foods.append(item)
                else:
                    resolved = await _resolve_food_data([item], user_email, db, user_id=user_id)
                    final_foods.extend(resolved)
        elif payload.portion_multiplier is not None or payload.total_grams is not None:
            if payload.portion_multiplier is not None and payload.portion_multiplier <= 0:
                raise HTTPException(status_code=400, detail="portion_multiplier must be greater than 0")
            if payload.total_grams is not None and payload.total_grams <= 0:
                raise HTTPException(status_code=400, detail="total_grams must be greater than 0")

            existing_foods = [dict(f) for f in (existing_doc.get("foods") or [])]
            if payload.portion_multiplier is not None:
                multiplier = float(payload.portion_multiplier)
            else:
                current_total_grams = 0.0
                for food_item in existing_foods:
                    for gram_key in ("grams", "weight_grams", "portion_grams", "amount"):
                        val = food_item.get(gram_key)
                        if val is not None:
                            try:
                                g_val = float(val)
                                if g_val > 0:
                                    current_total_grams += g_val
                                    break
                            except (TypeError, ValueError):
                                pass
                if current_total_grams <= 0:
                    raise HTTPException(
                        status_code=400,
                        detail="Cannot scale by total_grams when existing foods have no positive gram values",
                    )
                multiplier = float(payload.total_grams) / current_total_grams

            final_foods = []
            for food_item in existing_foods:
                scaled = dict(food_item)
                if "calories" in scaled and scaled["calories"] is not None:
                    scaled["calories"] = int(round(float(scaled["calories"]) * multiplier))
                for macro_key in ("protein", "carbs", "fat"):
                    if macro_key in scaled and scaled[macro_key] is not None:
                        scaled[macro_key] = round(float(scaled[macro_key]) * multiplier, 1)
                for gram_key in ("grams", "weight_grams", "portion_grams", "amount"):
                    if gram_key in scaled and scaled[gram_key] is not None:
                        scaled[gram_key] = round(float(scaled[gram_key]) * multiplier, 1)
                final_foods.append(scaled)
        else:
            final_foods = [dict(f) for f in (existing_doc.get("foods") or [])]

        totals = _recalculate_nutrition_totals(
            final_foods,
            fallback_calories=existing_doc.get("total_calories"),
        )
        now_utc = datetime.utcnow()
        new_meal_type = payload.meal_type if payload.meal_type is not None else existing_doc.get("meal_type", "")
        new_notes = payload.notes if payload.notes is not None else existing_doc.get("notes")

        update_fields: Dict[str, Any] = {
            "meal_type": new_meal_type,
            "foods": final_foods,
            "total_calories": totals["total_calories"],
            "total_protein": totals["total_protein"],
            "total_carbs": totals["total_carbs"],
            "total_fat": totals["total_fat"],
            "notes": new_notes,
            "updated_at": now_utc,
        }
        if user_id and not existing_doc.get("user_id"):
            update_fields["user_id"] = user_id

        nutrition_collection.update_one(
            {"_id": existing_doc["_id"]},
            {"$set": update_fields},
        )
        return {
            "id": str(existing_doc["_id"]),
            "date": existing_doc.get("date", ""),
            "meal_type": new_meal_type,
            "foods": final_foods,
            "total_calories": totals["total_calories"],
            "total_protein": totals["total_protein"],
            "total_carbs": totals["total_carbs"],
            "total_fat": totals["total_fat"],
            "notes": new_notes,
            "updated_at": now_utc.isoformat(),
            "status": "updated",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/logs/{log_id}")
async def delete_nutrition_log(log_id: str, user: dict = Depends(get_current_user)):
    try:
        if nutrition_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")
        from bson.errors import InvalidId
        try:
            obj_id = ObjectId(log_id)
        except (InvalidId, TypeError, ValueError):
            raise HTTPException(status_code=404, detail="Log not found or not authorized")
        user_id, user_email = _resolve_user_identity(user)
        result = _delete_one_user_doc(
            nutrition_collection,
            user_id,
            user_email,
            {"_id": obj_id},
        )
        if not result or result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Log not found or not authorized")
        return {"id": log_id, "message": "Deleted", "deleted_at": datetime.now().isoformat()}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# ✅ PATCH E — WATER LOG (persist)
# ─────────────────────────────────────────
@router.post("/water")
async def log_water_intake(
    water_log: WaterLog,
    user: dict = Depends(get_current_user),
):
    """Log water intake — atomic delta addition or optimistic total update with version check."""
    if water_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")

    # Validation: must have either delta_ml or amount_ml
    if water_log.delta_ml is None and water_log.amount_ml is None:
        raise HTTPException(status_code=400, detail="Either amount_ml or delta_ml must be provided")

    now_utc = datetime.utcnow()
    user_id, email = _resolve_user_identity(user)
    target_date = _valid_or_today_date(water_log.date)

    # ─────────────────────────────────────────────────────────────
    # Case 1: Thao tác thêm nước (delta) kèm idempotency key
    # ─────────────────────────────────────────────────────────────
    if water_log.delta_ml is not None:
        delta = int(water_log.delta_ml)
        key = water_log.idempotency_key

        # Idempotency fast-path: check if key already applied
        if key:
            already = _find_one_user_doc(
                water_collection,
                user_id,
                email,
                {"date": target_date, "applied_actions": key},
            )
            if already:
                return {
                    "id": str(already["_id"]),
                    "message": "Water intake already logged",
                    "amount_ml": already.get("amount_ml", 0),
                    "date": target_date,
                    "version": already.get("version", 0),
                    "status": "saved",
                }

        max_retries = 3
        for attempt in range(max_retries):
            try:
                if key:
                    already = _find_one_user_doc(
                        water_collection,
                        user_id,
                        email,
                        {"date": target_date, "applied_actions": key},
                    )
                    if already:
                        break

                doc = _find_one_user_doc(
                    water_collection,
                    user_id,
                    email,
                    {"date": target_date},
                )
                if doc:
                    update_filter = {"_id": doc["_id"]}
                    if key:
                        update_filter["applied_actions"] = {"$ne": key}
                    set_payload = {
                        "updated_at": now_utc,
                        "user_id": user_id,
                        "user_email": email,
                        "date": target_date,
                    }
                    update_body = {
                        "$inc": {"amount_ml": delta, "version": 1},
                        "$set": set_payload,
                    }
                    if key:
                        update_body["$addToSet"] = {"applied_actions": key}
                    res = water_collection.update_one(update_filter, update_body)
                    if getattr(res, "matched_count", 1) == 0:
                        if key and _find_one_user_doc(
                            water_collection,
                            user_id,
                            email,
                            {"date": target_date, "applied_actions": key},
                        ):
                            break
                        continue
                    break
                else:
                    upsert_filter = {
                        "user_email": email,
                        "date": target_date,
                    }
                    if user_id:
                        upsert_filter["user_id"] = user_id
                    if key:
                        upsert_filter["applied_actions"] = {"$ne": key}
                    set_payload = {"updated_at": now_utc, "user_email": email}
                    if user_id:
                        set_payload["user_id"] = user_id
                    upsert_body = {
                        "$inc": {"amount_ml": delta, "version": 1},
                        "$setOnInsert": {
                            "created_at": now_utc,
                        },
                        "$set": set_payload,
                    }
                    if key:
                        upsert_body["$addToSet"] = {"applied_actions": key}
                    water_collection.update_one(upsert_filter, upsert_body, upsert=True)
                    break
            except Exception as e:
                err_str = str(e).lower()
                if "duplicate key" in err_str or "e11000" in err_str:
                    continue
                raise HTTPException(status_code=503, detail="Database error while logging water")

        if key:
            verified_doc = _find_one_user_doc(
                water_collection,
                user_id,
                email,
                {"date": target_date, "applied_actions": key},
            )
            if not verified_doc:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Database error while logging water: marker not verified",
                )
            return {
                "id": str(verified_doc["_id"]),
                "message": "Water intake logged",
                "amount_ml": verified_doc.get("amount_ml", 0),
                "date": target_date,
                "version": verified_doc.get("version", 0),
                "status": "saved",
            }

        latest = _find_one_user_doc(
            water_collection,
            user_id,
            email,
            {"date": target_date},
        )
        if not latest:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database error while logging water",
            )
        return {
            "id": str(latest["_id"]),
            "message": "Water intake logged",
            "amount_ml": latest.get("amount_ml", 0),
            "date": target_date,
            "version": latest.get("version", 0),
            "status": "saved",
        }

    # ─────────────────────────────────────────────────────────────
    # Case 2: Thao tác đặt/chỉnh tổng với optimistic locking (version)
    # ─────────────────────────────────────────────────────────────
    target_amount = max(0, int(water_log.amount_ml))
    expected_version = water_log.version

    doc = _find_one_user_doc(
        water_collection,
        user_id,
        email,
        {"date": target_date},
    )

    if doc:
        current_version = doc.get("version", 0)
        current_amount = doc.get("amount_ml", 0)
        applied_actions = doc.get("applied_actions") or []

        if expected_version is None:
            # Client cũ không gửi version:
            # 1. Nếu bản ghi ngày đó đã có applied_actions, trả 409 và không ghi đè
            if applied_actions:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "message": "Conflict: water log has applied chat actions",
                        "current_amount_ml": current_amount,
                        "current_version": current_version,
                    },
                )

            # 2. Nếu chưa có applied_actions: update có điều kiện trên version hiện tại
            filter_query = {"_id": doc["_id"]}
            has_version = "version" in doc and doc["version"] is not None
            if not has_version or doc.get("version") == 0:
                filter_query["$or"] = [
                    {"version": 0},
                    {"version": {"$exists": False}},
                ]
            else:
                filter_query["version"] = current_version
        else:
            # Client mới có gửi version:
            if expected_version != current_version:
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "message": "Conflict: water total has been updated",
                        "current_amount_ml": current_amount,
                        "current_version": current_version,
                    },
                )

            filter_query = {"_id": doc["_id"]}
            if expected_version == 0:
                filter_query["$or"] = [
                    {"version": 0},
                    {"version": {"$exists": False}},
                ]
            else:
                filter_query["version"] = expected_version

        set_payload = {
            "amount_ml": target_amount,
            "updated_at": now_utc,
            "user_id": user_id,
            "user_email": email,
            "date": target_date,
        }

        res = water_collection.update_one(
            filter_query,
            {
                "$set": set_payload,
                "$inc": {"version": 1},
            },
        )
        if getattr(res, "matched_count", 1) == 0:
            latest = water_collection.find_one({"_id": doc["_id"]})
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "message": "Conflict: water total was updated concurrently",
                    "current_amount_ml": latest.get("amount_ml", 0) if latest else 0,
                    "current_version": latest.get("version", 0) if latest else 0,
                },
            )
    else:
        if expected_version is not None and expected_version > 0:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "message": "Conflict: no existing record for specified version",
                    "current_amount_ml": 0,
                    "current_version": 0,
                },
            )
        try:
            new_water_doc = {
                "user_id": user_id,
                "user_email": email,
                "date": target_date,
                "amount_ml": target_amount,
                "version": 1,
                "applied_actions": [],
                "created_at": now_utc,
                "updated_at": now_utc,
            }
            water_collection.insert_one(new_water_doc)
        except Exception as e:
            err_str = str(e).lower()
            if "duplicate key" in err_str or "e11000" in err_str:
                latest = _find_one_user_doc(
                    water_collection,
                    user_id,
                    email,
                    {"date": target_date},
                )
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "message": "Conflict: record was created concurrently",
                        "current_amount_ml": latest.get("amount_ml", 0) if latest else 0,
                        "current_version": latest.get("version", 0) if latest else 0,
                    },
                )
            raise HTTPException(status_code=503, detail="Database error while logging water")

    latest = _find_one_user_doc(
        water_collection,
        user_id,
        email,
        {"date": target_date},
    )
    return {
        "id": str(latest["_id"]) if latest else None,
        "message": "Water intake logged",
        "amount_ml": latest.get("amount_ml", 0) if latest else target_amount,
        "date": target_date,
        "version": latest.get("version", 0) if latest else 1,
        "status": "saved",
    }


# ─────────────────────────────────────────
# ✅ PATCH A — GET /{date} (đọc từ DB)
# ─────────────────────────────────────────
def _is_created_after_reset(created_at, reset_at) -> bool:
    """Safe comparison of created_at > reset_at without raising TypeError.

    Returns True if created_at is a verified timestamp occurring strictly after reset_at.
    Returns False if created_at is None, missing, invalid, or <= reset_at.
    Handles naive vs aware datetimes safely without throwing.
    """
    if created_at is None or reset_at is None:
        return False
    if isinstance(created_at, str):
        try:
            created_at = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
        except (ValueError, TypeError):
            return False
    if isinstance(reset_at, str):
        try:
            reset_at = datetime.fromisoformat(reset_at.replace("Z", "+00:00"))
        except (ValueError, TypeError):
            return False
    if not isinstance(created_at, datetime) or not isinstance(reset_at, datetime):
        return False
    try:
        if (created_at.tzinfo is None) != (reset_at.tzinfo is None):
            c_utc = created_at.replace(tzinfo=timezone.utc) if created_at.tzinfo is None else created_at
            r_utc = reset_at.replace(tzinfo=timezone.utc) if reset_at.tzinfo is None else reset_at
            return c_utc > r_utc
        return created_at > reset_at
    except TypeError:
        return False


@router.get("/recent-meals")
async def get_recent_meals(
    days: int = Query(14, ge=1, le=60),
    limit: int = Query(10, ge=1, le=20),
    current_user: dict = Depends(get_current_user),
):
    if nutrition_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")

    user_id, user_email = _resolve_user_identity(current_user)
    start_date = get_vn_date_str(-(days - 1))
    end_date = get_vn_date_str(0)
    logs = _find_user_docs(
        nutrition_collection,
        user_id,
        user_email,
        {"date": {"$gte": start_date, "$lte": end_date}},
    )
    reset_docs = _find_user_docs(
        db["day_resets"],
        user_id,
        user_email,
        {"date": {"$gte": start_date, "$lte": end_date}},
    ) if db is not None else []
    reset_by_date = {item.get("date"): item.get("reset_at") for item in reset_docs}

    grouped = {}
    for log in logs:
        log_date = log.get("date") or ""
        reset_at = reset_by_date.get(log_date)
        if reset_at and not _is_created_after_reset(log.get("created_at"), reset_at):
            continue
        foods = log.get("foods") or []
        normalized_names = tuple(sorted(
            _normalize_text(str(food.get("name") or "")).strip()
            for food in foods
        ))
        meal_type = str(log.get("meal_type") or "")
        key = (meal_type.strip().lower(), normalized_names)
        sample = {
            "source_log_id": str(log.get("_id", "")),
            "meal_type": meal_type,
            "title": str(log.get("title") or " + ".join(
                str(food.get("name") or "") for food in foods if food.get("name")
            ) or meal_type),
            "foods": foods,
            "total_calories": int(round(float(log.get("total_calories") or sum(
                float(food.get("calories") or 0) for food in foods
            )))),
            "total_protein": round(float(log.get("total_protein") or sum(
                float(food.get("protein") or 0) for food in foods
            )), 1),
            "total_carbs": round(float(log.get("total_carbs") or sum(
                float(food.get("carbs") or 0) for food in foods
            )), 1),
            "total_fat": round(float(log.get("total_fat") or sum(
                float(food.get("fat") or 0) for food in foods
            )), 1),
            "frequency": 1,
            "last_date": log_date,
            "_created_at": log.get("created_at"),
        }
        existing = grouped.get(key)
        if existing is None:
            grouped[key] = sample
            continue
        frequency = existing["frequency"] + 1
        if (sample["last_date"], str(sample["_created_at"] or "")) > (
            existing["last_date"], str(existing["_created_at"] or "")
        ):
            sample["frequency"] = frequency
            grouped[key] = sample
        else:
            existing["frequency"] = frequency

    meals = sorted(
        grouped.values(),
        key=lambda item: (item["frequency"], item["last_date"]),
        reverse=True,
    )[:limit]
    for item in meals:
        item.pop("_created_at", None)
    return {"meals": meals, "total": len(grouped)}


@router.post("/quick-relog")
async def quick_relog(
    request: QuickRelogRequest,
    current_user: dict = Depends(get_current_user),
):
    if nutrition_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")

    user_id, user_email = _resolve_user_identity(current_user)
    source_log = None
    if request.source_log_id:
        if not ObjectId.is_valid(request.source_log_id):
            raise HTTPException(status_code=400, detail="Invalid source_log_id")
        source_log = _find_one_user_doc(
            nutrition_collection,
            user_id,
            user_email,
            {"_id": ObjectId(request.source_log_id)},
        )
        if not source_log:
            raise HTTPException(status_code=404, detail="Source nutrition log not found")

    foods = request.foods if request.foods is not None else (source_log or {}).get("foods")
    if not foods:
        raise HTTPException(status_code=400, detail="foods must be a non-empty list")
    copied_foods = [dict(food) for food in foods]
    meal_type = request.meal_type or (source_log or {}).get("meal_type") or "snack"
    target_date = _valid_or_today_date(request.date)
    total_calories = int(round(sum(float(food.get("calories") or 0) for food in copied_foods)))
    total_protein = round(sum(float(food.get("protein") or 0) for food in copied_foods), 1)
    total_carbs = round(sum(float(food.get("carbs") or 0) for food in copied_foods), 1)
    total_fat = round(sum(float(food.get("fat") or 0) for food in copied_foods), 1)
    now_utc = datetime.utcnow()
    meal = {
        "user_id": user_id,
        "user_email": user_email,
        "date": target_date,
        "meal_type": meal_type,
        "foods": copied_foods,
        "total_calories": total_calories,
        "total_protein": total_protein,
        "total_carbs": total_carbs,
        "total_fat": total_fat,
        "created_at": now_utc,
        "updated_at": now_utc,
    }
    result = nutrition_collection.insert_one(meal)
    meal.pop("_id", None)
    meal["id"] = str(result.inserted_id)
    return {"id": meal["id"], "status": "saved", "date": target_date, "meal": meal}


# ─────────────────────────────────────────
# SUPPLEMENTS (Batch 4.2A)
# ─────────────────────────────────────────
@router.post("/supplements")
async def add_supplement_log(
    payload: Dict[str, Any],
    current_user: dict = Depends(get_current_user),
):
    """Log a supplement intake entry (defaults to today in Asia/Ho_Chi_Minh)."""
    if supplements_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")
    user_id, user_email = _resolve_user_identity(current_user)
    try:
        return create_supplement_log(
            supplements_collection,
            user_id=user_id,
            user_email=user_email,
            payload=payload,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/supplements/{date}")
async def get_supplements_by_date(
    date: str,
    current_user: dict = Depends(get_current_user),
):
    """Get user-scoped supplement logs for a specific YYYY-MM-DD date."""
    if supplements_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")
    user_id, user_email = _resolve_user_identity(current_user)
    logs = get_supplement_logs_by_date(
        supplements_collection,
        user_id=user_id,
        user_email=user_email,
        date_str=date,
    )
    return {"date": date, "supplements": logs, "total": len(logs)}


@router.delete("/supplements/{log_id}")
async def remove_supplement_log(
    log_id: str,
    current_user: dict = Depends(get_current_user),
):
    """Delete a user-owned supplement log entry."""
    if supplements_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")
    user_id, user_email = _resolve_user_identity(current_user)
    try:
        deleted = delete_supplement_log(
            supplements_collection,
            user_id=user_id,
            user_email=user_email,
            log_id=log_id,
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid log_id format")
    if not deleted:
        raise HTTPException(status_code=404, detail="Supplement log not found or not authorized")
    return {"status": "deleted", "id": log_id}


# ─────────────────────────────────────────
# RECIPES (Batch 4.2A)
# ─────────────────────────────────────────
@router.get("/recipes")
async def get_user_recipes(
    limit: int = Query(default=50, ge=1, le=200),
    current_user: dict = Depends(get_current_user),
):
    """List saved recipes for the current user."""
    if recipes_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")
    user_id, user_email = _resolve_user_identity(current_user)
    recipes = list_recipes(
        recipes_collection,
        user_id=user_id,
        user_email=user_email,
        limit=limit,
    )
    return {"recipes": recipes, "total": len(recipes)}


@router.post("/recipes")
async def create_user_recipe(
    payload: Dict[str, Any],
    current_user: dict = Depends(get_current_user),
):
    """Create a user recipe and compute per-serving calories and macros."""
    if recipes_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")
    user_id, user_email = _resolve_user_identity(current_user)
    try:
        return create_recipe(
            recipes_collection,
            user_id=user_id,
            user_email=user_email,
            payload=payload,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/recipes/{recipe_id}")
async def get_user_recipe_detail(
    recipe_id: str,
    current_user: dict = Depends(get_current_user),
):
    """Get a single user-owned recipe by ID."""
    if recipes_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")
    user_id, user_email = _resolve_user_identity(current_user)
    try:
        recipe = get_recipe_by_id(
            recipes_collection,
            user_id=user_id,
            user_email=user_email,
            recipe_id=recipe_id,
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid recipe_id")
    if not recipe:
        raise HTTPException(status_code=404, detail="Recipe not found")
    return recipe


@router.delete("/recipes/{recipe_id}")
async def delete_user_recipe(
    recipe_id: str,
    current_user: dict = Depends(get_current_user),
):
    """Delete a user-owned recipe by ID."""
    if recipes_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")
    user_id, user_email = _resolve_user_identity(current_user)
    try:
        deleted = delete_recipe(
            recipes_collection,
            user_id=user_id,
            user_email=user_email,
            recipe_id=recipe_id,
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid recipe_id")
    if not deleted:
        raise HTTPException(status_code=404, detail="Recipe not found")
    return {"status": "deleted", "id": recipe_id}


@router.post("/recipes/{recipe_id}/log")
async def log_user_recipe_serving(
    recipe_id: str,
    payload: Dict[str, Any] = Body(default_factory=dict),
    current_user: dict = Depends(get_current_user),
):
    """Log consumed servings of a saved recipe into today's (or target date's) nutrition plan."""
    if recipes_collection is None or nutrition_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")
    user_id, user_email = _resolve_user_identity(current_user)
    try:
        return log_recipe_serving(
            recipes_collection,
            nutrition_collection,
            user_id=user_id,
            user_email=user_email,
            recipe_id=recipe_id,
            date_str=payload.get("date"),
            meal_type=payload.get("meal_type", "snack"),
            servings_consumed=payload.get("servings_consumed", 1.0),
        )
    except LookupError:
        raise HTTPException(status_code=404, detail="Recipe not found")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


# ─────────────────────────────────────────
# BARCODE LOOKUP & NUTRITION LABEL AI (P1.2)
# ─────────────────────────────────────────
@router.post("/barcode/analyze-label")
async def analyze_barcode_nutrition_label(
    barcode: str = Form(...),
    image: UploadFile = File(...),
    product_name: Optional[str] = Form(default=None),
    x_idempotency_key: Optional[str] = Header(default=None, alias="X-Idempotency-Key"),
    current_user: dict = Depends(get_current_user),
):
    """
    Extract nutrition facts from a product label photo using Gemini Vision,
    with paywall/quota control (`ai.nutrition_gemini`), and cache to `food_barcodes`.
    """
    if food_barcodes_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        cleaned_barcode = normalize_and_validate_barcode(barcode)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "invalid_barcode", "barcode": barcode, "message": str(exc)},
        )

    if (
        image.content_type
        and image.content_type not in ("image/jpeg", "image/png", "image/webp", "image/jpg")
        and not image.content_type.startswith("image/")
    ):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only JPEG/PNG/WEBP supported")

    image_bytes = await image.read()
    if len(image_bytes) > 10 * 1024 * 1024:
        raise HTTPException(status_code=413, detail="Image too large (max 10MB)")
    if len(image_bytes) < 1000:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Image too small or corrupted")

    mime_type = image.content_type or "image/jpeg"
    user_id, user_email = _resolve_user_identity(current_user)
    account_id = str((current_user or {}).get("account_id") or "").strip() if isinstance(current_user, dict) else ""
    quota_user_id = str(account_id or user_id or user_email or "").strip()

    from backend.app.models.revenue import EntitlementDecisionStatus, ReservationStatus
    from backend.app.services.entitlement_service import EntitlementService
    from backend.app.services.quota_service import (
        QuotaService,
        StorageUnavailableException,
        resolve_user_tier_and_quota,
    )
    from backend.app.services.revenue_guard import (
        compute_payload_hash,
        is_ai_paywall_enabled,
        is_enforcement_enabled,
        is_shadow_mode_enabled,
    )
    from backend.services.gemini_food_analyzer import (
        GeminiAnalysisError,
        GeminiConfigurationError,
        get_gemini_food_analyzer,
    )

    benefit_id = "ai.nutrition_gemini"
    paywall_on = is_ai_paywall_enabled()
    enforced = is_enforcement_enabled(user_email)
    active_db = db if db is not None else getattr(_db_module, "db", None)

    def _is_non_label_error(exc: Exception) -> bool:
        msg = str(exc).lower()
        return (
            "nutrition label" in msg
            or "not a label" in msg
            or "is_nutrition_label" in msg
        )

    def _is_timeout_error(exc: Exception) -> bool:
        msg = str(exc).lower()
        return (
            isinstance(exc, (asyncio.TimeoutError, TimeoutError))
            or "timeout" in msg
            or "timed out" in msg
            or "deadline" in msg
        )

    # CASE 1: Paywall & Revenue Enforcement OFF
    if not paywall_on and not enforced:
        if is_shadow_mode_enabled() and active_db is not None and quota_user_id:
            try:
                ent_svc = EntitlementService(db=active_db)
                decision = ent_svc.evaluate_entitlement(user_id=quota_user_id, benefit_id=benefit_id)
                logger.info(
                    "[REVENUE-SHADOW] user=%s benefit=%s status=%s reason=%s",
                    quota_user_id, benefit_id, decision.status.value, decision.reason,
                )
            except Exception as shadow_exc:
                logger.warning("[REVENUE-SHADOW-ERROR] Label evaluation failed: %s", shadow_exc)

        try:
            analyzer = get_gemini_food_analyzer()
            label_data = await analyzer.analyze_nutrition_label(
                image_bytes=image_bytes,
                mime_type=mime_type,
            )
        except GeminiConfigurationError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"error": "gemini_unavailable", "message": str(exc)},
            )
        except GeminiAnalysisError as exc:
            if _is_non_label_error(exc):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={"error": "not_nutrition_label", "code": "not_nutrition_label", "message": str(exc)},
                )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail={"error": "provider_unavailable", "message": str(exc)},
            )
        except Exception as exc:
            logger.exception("Unexpected error in analyze_barcode_nutrition_label: %s", exc)
            raise HTTPException(status_code=500, detail="Nutrition label analysis failed")

        resolved_name = (
            (product_name or "").strip()
            or str(label_data.get("product_name") or "").strip()
            or f"Sản phẩm {cleaned_barcode}"
        )
        saved_food = upsert_barcode_food(
            food_barcodes_collection,
            cleaned_barcode,
            name=resolved_name,
            brand=str(label_data.get("brand") or ""),
            serving_size=str(label_data.get("serving_size") or ""),
            serving_grams=label_data.get("serving_grams"),
            per_100g=label_data.get("per_100g") or {},
            source="gemini_label_community",
        )
        return {
            "found": True,
            "source": "gemini_label_community",
            "barcode": cleaned_barcode,
            "food": saved_food,
        }

    # CASE 2: Paywall or Revenue Enforcement ON
    q_svc = QuotaService(db=active_db)
    resolved_db = active_db if active_db is not None else q_svc._get_db()
    reserve_period_type = "monthly"
    reserve_limit_units = 30

    if paywall_on:
        try:
            _, reserve_period_type, reserve_limit_units = resolve_user_tier_and_quota(
                resolved_db,
                user_id=quota_user_id,
                email=user_email,
                benefit_id=benefit_id,
            )
        except StorageUnavailableException as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"error": "storage_unavailable", "message": str(exc)},
            )

        if reserve_limit_units == 0:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "error": "entitlement_required",
                    "code": "entitlement_required",
                    "benefit_id": benefit_id,
                    "message": "Tính năng này yêu cầu gói hội viên trả phí.",
                },
            )
    else:
        ent_svc = EntitlementService(db=resolved_db)
        decision = ent_svc.evaluate_entitlement(user_id=quota_user_id, benefit_id=benefit_id)
        if decision.status == EntitlementDecisionStatus.STORAGE_UNAVAILABLE:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"error": "storage_unavailable", "message": f"Storage error evaluating entitlement: {decision.reason}"},
            )
        if decision.status != EntitlementDecisionStatus.ALLOWED:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "error": "entitlement_required",
                    "code": "entitlement_required",
                    "benefit_id": benefit_id,
                    "reason": decision.reason,
                    "tier": decision.tier.value if decision.tier else None,
                },
            )

    request_hash = compute_payload_hash(
        image_bytes
        + f":barcode={cleaned_barcode}:mime={mime_type.lower()}:name={(product_name or '').strip()}".encode("utf-8")
    )
    cleaned_idemp = (x_idempotency_key or "").strip()
    effective_idemp_key = cleaned_idemp or f"lbl_{cleaned_barcode}_{request_hash[:24]}"

    res = q_svc.reserve_quota(
        user_id=quota_user_id,
        benefit_id=benefit_id,
        units=1,
        limit_units=reserve_limit_units,
        period_type=reserve_period_type,
        idempotency_key=effective_idemp_key,
        request_hash=request_hash,
        client_request_id=cleaned_idemp or None,
    )

    if res.status == ReservationStatus.STORAGE_UNAVAILABLE:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "storage_unavailable", "message": res.error_message},
        )
    if res.status == ReservationStatus.QUOTA_EXHAUSTED:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "error": "quota_exhausted",
                "code": "quota_exceeded",
                "benefit_id": benefit_id,
                "consumed_units": res.consumed_units,
                "remaining_units": res.remaining_units,
                "limit_units": res.limit_units,
                "message": res.error_message,
            },
        )
    if res.status == ReservationStatus.OPERATION_CONFLICT:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "operation_conflict", "message": res.error_message},
        )
    if res.status == ReservationStatus.ALREADY_COMPLETED:
        if res.cached_payload:
            return res.cached_payload
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error": "operation_already_completed",
                "message": "Operation already completed. Re-run requires a new request ID.",
            },
        )
    if res.status == ReservationStatus.IN_PROGRESS:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error": "operation_in_progress",
                "operation_id": res.operation_id,
                "message": "An identical request is currently executing.",
            },
        )

    q_svc.mark_dispatched(operation_id=res.operation_id, lease_token=res.lease_token)

    try:
        analyzer = get_gemini_food_analyzer()
        label_data = await analyzer.analyze_nutrition_label(
            image_bytes=image_bytes,
            mime_type=mime_type,
        )
    except Exception as exc:
        if _is_timeout_error(exc):
            q_svc.mark_unknown(res.operation_id, reason=f"Provider timeout: {exc}")
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail={
                    "error": "provider_timeout",
                    "operation_id": res.operation_id,
                    "message": "Gemini label analysis timed out; operation status is unknown.",
                },
            )
        if _is_non_label_error(exc):
            q_svc.release_quota(
                operation_id=res.operation_id,
                lease_token=res.lease_token,
                reason="non_label_rejected",
            )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail={
                    "error": "not_nutrition_label",
                    "code": "not_nutrition_label",
                    "message": str(exc),
                },
            )
        if isinstance(exc, GeminiConfigurationError):
            q_svc.release_quota(
                operation_id=res.operation_id,
                lease_token=res.lease_token,
                reason=f"gemini_unavailable: {exc}",
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"error": "gemini_unavailable", "message": str(exc)},
            )
        q_svc.release_quota(
            operation_id=res.operation_id,
            lease_token=res.lease_token,
            reason=f"provider_error: {exc}",
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"error": "provider_unavailable", "message": f"Gemini provider error: {exc}"},
        )

    if not isinstance(label_data, dict) or not isinstance(label_data.get("per_100g"), dict):
        q_svc.release_quota(
            operation_id=res.operation_id,
            lease_token=res.lease_token,
            reason="invalid_response_schema",
        )
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={
                "error": "provider_invalid_response",
                "message": "Invalid response schema returned by provider.",
            },
        )

    resolved_name = (
        (product_name or "").strip()
        or str(label_data.get("product_name") or "").strip()
        or f"Sản phẩm {cleaned_barcode}"
    )
    saved_food = upsert_barcode_food(
        food_barcodes_collection,
        cleaned_barcode,
        name=resolved_name,
        brand=str(label_data.get("brand") or ""),
        serving_size=str(label_data.get("serving_size") or ""),
        serving_grams=label_data.get("serving_grams"),
        per_100g=label_data.get("per_100g") or {},
        source="gemini_label_community",
    )

    response_payload = {
        "found": True,
        "source": "gemini_label_community",
        "barcode": cleaned_barcode,
        "food": saved_food,
    }
    q_svc.commit_quota(
        operation_id=res.operation_id,
        lease_token=res.lease_token,
        response_payload=response_payload,
    )
    return response_payload


@router.get("/barcode/{barcode}")
async def get_food_by_barcode(
    barcode: str,
    current_user: dict = Depends(get_current_user),
):
    """Lookup packaged food nutrition by barcode (MongoDB cache -> Open Food Facts)."""
    if food_barcodes_collection is None:
        raise HTTPException(status_code=503, detail="Database not available")

    try:
        cleaned_barcode = normalize_and_validate_barcode(barcode)
        result = await lookup_barcode(cleaned_barcode, food_barcodes_collection)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "invalid_barcode", "barcode": barcode, "message": str(exc)},
        )

    if not result:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={
                "code": "barcode_not_found",
                "barcode": cleaned_barcode,
                "message": "Chưa có dữ liệu mã vạch này.",
            },
        )
    return result


@router.get("/{date}")
async def get_nutrition_by_date(
    date: str,
    current_user: dict = Depends(get_current_user),
):
    """
    Tổng hợp dinh dưỡng cho một ngày.
    Đọc từ nutrition_plans (manual log) + water_logs.
    Không còn trả mock data.
    """
    try:
        if nutrition_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        user_id, user_email = _resolve_user_identity(current_user)

        logs = _find_user_docs(
            nutrition_collection,
            user_id,
            user_email,
            {"date": date},
            sort_field="created_at",
            sort_dir=-1,
        )

        # Reset filter — chỉ hiển thị entries SAU reset timestamp
        reset_col = db["day_resets"]
        reset_doc = _find_one_user_doc(reset_col, user_id, user_email, {"date": date})
        reset_at  = reset_doc["reset_at"] if reset_doc else None
        if reset_at:
            logs = [log for log in logs if _is_created_after_reset(log.get("created_at"), reset_at)]

        # Batch lookup story images for linked stories, bounded strictly to current_user
        story_images = {}
        story_query_ids = []
        for log in logs:
            sid = log.get("story_id")
            if sid:
                try:
                    story_query_ids.append(ObjectId(sid) if isinstance(sid, str) else sid)
                except Exception:
                    pass

        if story_query_ids and story_logs_collection is not None:
            try:
                story_docs = _find_user_docs(
                    story_logs_collection,
                    user_id,
                    user_email,
                    {"_id": {"$in": story_query_ids}},
                    projection={"_id": 1, "image_url": 1, "user_id": 1, "user_email": 1},
                )
                for sdoc in story_docs:
                    s_url = sdoc.get("image_url")
                    if s_url:
                        story_images[str(sdoc["_id"])] = s_url
            except Exception as e:
                logger.warning("Error fetching linked story images: %s", e)

        entries       = []
        total_calories = 0.0
        total_protein  = 0.0
        total_carbs    = 0.0
        total_fat      = 0.0

        for log in logs:
            log_id = str(log.get("_id", ""))
            
            # Extract foods list for the meal
            foods_list = log.get("foods", [])
            
            # Single source of truth for macro calculations – use stored values if available
            meal_total_cal = log.get("total_calories") or sum(float(f.get("calories", 0)) for f in foods_list)
            meal_total_pro = log.get("total_protein")  or sum(float(f.get("protein", 0)) for f in foods_list)
            meal_total_carb = log.get("total_carbs")   or sum(float(f.get("carbs", 0)) for f in foods_list)
            meal_total_fat = log.get("total_fat")      or sum(float(f.get("fat", 0)) for f in foods_list)
            
            # Use first food as primary display food
            primary_food = foods_list[0] if foods_list else {}
            
            # Lookup image from linked story owned by current user
            sid = str(log.get("story_id", ""))
            story_img = story_images.get(sid)

            entry_data = {
                "food_name": primary_food.get("name", "Unknown Food"),
                "food_id": str(primary_food.get("food_id", "") or ""),
                "calories": meal_total_cal,
                "protein": meal_total_pro,
                "carbs": meal_total_carb,
                "fat": meal_total_fat,
                "meal_type": log.get("meal_type", ""),
                "log_id": log_id,
                "weight_g": primary_food.get("weight_grams", 100),
                "foodsList": foods_list,  # Add full foods list for UI
                "foods": foods_list,      # Add foods for backward compatibility and MealDto
                "total_calories": meal_total_cal,  # Add meal-level total
                "total_protein": meal_total_pro,
                "total_carbs": meal_total_carb,
                "total_fat": meal_total_fat,
            }
            if story_img:
                entry_data["image_url"] = story_img

            entries.append(entry_data)
            
            total_calories += meal_total_cal
            total_protein  += meal_total_pro
            total_carbs    += meal_total_carb
            total_fat      += meal_total_fat

        # Lấy water log trong ngày
        current_water = 0
        water_version = 0
        if water_collection is not None:
            water_doc = _find_one_user_doc(water_collection, user_id, user_email, {"date": date})
            if water_doc:
                current_water = water_doc.get("amount_ml", 0)
                water_version = water_doc.get("version", 0)

        # Lấy water_target từ profile
        user_data    = _get_user_record(current_user, user_id, user_email)
        health_stats = user_data.get("health_stats", {}) if isinstance(user_data, dict) else {}
        if not isinstance(health_stats, dict):
            health_stats = {}
        water_target = health_stats.get("water_target_ml", 2000)

        # Lấy target_calories từ health_stats (đã có trong context)
        target_calories_today = health_stats.get("daily_calories", 2000)

        profile = user_data.get("profile", {}) if isinstance(user_data, dict) else {}
        if not isinstance(profile, dict):
            profile = {}
        base_cal = int(health_stats.get("daily_calories") or 2000)
        base_pro = float(health_stats.get("target_protein") or 0)
        base_carb = float(health_stats.get("target_carbs") or 0)
        base_fat = float(health_stats.get("target_fat") or 0)
        goal = str(profile.get("goal") or "").strip().lower()
        workouts = []
        if workout_history_collection is not None:
            start_utc, end_utc = get_vn_day_range_utc(date)
            workout_query = {
                "$and": [
                    build_user_query(user_id, user_email),
                    {"$or": [
                        {"date": date},
                        {"started_at": {"$gte": start_utc, "$lte": end_utc}},
                    ]},
                ]
            }
            workouts = list(workout_history_collection.find(workout_query))

        if workouts:
            day_mode = "training"
            burned_calories = sum(
                max(0, float(workout.get("calories_burned") or 0))
                for workout in workouts
            )
            if burned_calories > 0:
                raw_bonus = burned_calories
            else:
                total_duration = sum(
                    max(0, float(workout.get("total_duration_minutes") or 0))
                    for workout in workouts
                )
                raw_bonus = total_duration * 6 if total_duration > 0 else 250
            bonus_cal = min(500, max(150, raw_bonus))
            calorie_delta = int(round(bonus_cal))
            dynamic_cal = base_cal + calorie_delta
            dynamic_pro = base_pro + bonus_cal * 0.2 / 4
            dynamic_carb = base_carb + bonus_cal * 0.7 / 4
            dynamic_fat = base_fat + bonus_cal * 0.1 / 9
        else:
            day_mode = "rest"
            calorie_delta = -100 if goal in ("lose_weight", "weight_loss") else 0
            dynamic_cal = max(1200, base_cal + calorie_delta)
            dynamic_pro = base_pro
            dynamic_carb = base_carb + calorie_delta / 4
            dynamic_fat = base_fat

        # ── Rollover: 50% deficit hôm qua ──────────────────────
        rollover_calories = 0
        try:
            yesterday = (
                datetime.strptime(date, "%Y-%m-%d") - timedelta(days=1)
            ).strftime("%Y-%m-%d")
            
            # Không bị ảnh hưởng bởi reset của hôm qua — đọc toàn bộ
            yesterday_logs = _find_user_docs(
                nutrition_collection,
                user_id,
                user_email,
                {"date": yesterday},
            )
            yesterday_cal = sum(
                sum(float(f.get("calories", 0)) for f in log.get("foods", []))
                for log in yesterday_logs
            )
            deficit = target_calories_today - yesterday_cal
            rollover_calories = max(0, int(deficit * 0.5))
        except Exception:
            pass
        # ───────────────────────────────────────────────────────

        supplements: List[Dict[str, Any]] = []
        if supplements_collection is not None:
            try:
                supplements = get_supplement_logs_by_date(
                    supplements_collection,
                    user_id=user_id,
                    user_email=user_email,
                    date_str=date,
                )
            except Exception as e:
                logger.warning("Error fetching supplement logs for %s: %s", date, e)

        return {
            "date":           date,
            "entries":        entries,
            "supplements":    supplements,
            "total_calories": round(total_calories),
            "total_protein":  round(total_protein,  1),
            "total_carbs":    round(total_carbs,    1),
            "total_fat":      round(total_fat,      1),
            "current_water":  current_water,
            "water_version":  water_version,
            "water_target":   water_target,
            "rollover_calories": rollover_calories,   # NEW — 0 if no deficit
            "day_mode": day_mode,
            "dynamic_target": {
                "calories": int(round(dynamic_cal)),
                "protein": int(round(dynamic_pro)),
                "carbs": int(round(dynamic_carb)),
                "fat": int(round(dynamic_fat)),
                "calorie_delta": int(round(calorie_delta)),
                "base_calories": int(round(base_cal)),
            },
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("get_nutrition_by_date error: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# GENERATE PLAN
# ─────────────────────────────────────────
def _build_fallback_nutrition_plan(
    request: Optional[NutritionPlanRequest] = None,
    current_user: Optional[dict] = None,
) -> dict:
    """Return a valid static mock meal plan when LLM/API key or generator is unavailable."""
    today_str = get_vn_date_str()
    user_dict = current_user if isinstance(current_user, dict) else {}
    health_stats = (user_dict.get("health_stats") if isinstance(user_dict.get("health_stats"), dict) else {}) or {}
    profile = (user_dict.get("profile") if isinstance(user_dict.get("profile"), dict) else {}) or {}

    req_calories = getattr(request, "target_calories", None) if request else None
    req_goal = getattr(request, "goal", None) if request else None
    req_style = getattr(request, "style", None) or "optimal"
    req_meal_count = getattr(request, "meal_count", None) or 4
    req_remaining_only = bool(getattr(request, "remaining_only", True)) if request else True

    target_calories = int(
        health_stats.get("target_calories")
        or health_stats.get("daily_calories")
        or req_calories
        or 2000
    )
    raw_goal = profile.get("goal", "") or req_goal or "maintain"
    goal = _normalize_goal(raw_goal)
    activity_level = profile.get("activity_level", "moderate") or "moderate"

    default_meals = [
        {
            "meal_type": "Breakfast",
            "time": "07:00",
            "total_calories": 500,
            "total_protein": 30.0,
            "total_carbs": 55.0,
            "total_fat": 15.0,
            "foods": [
                {
                    "name": "Phở bò tái",
                    "grams": 250,
                    "weight_grams": 250,
                    "calories": 500,
                    "protein": 30.0,
                    "carbs": 55.0,
                    "fat": 15.0,
                    "group": "protein",
                }
            ],
        },
        {
            "meal_type": "Lunch",
            "time": "12:00",
            "total_calories": 650,
            "total_protein": 45.0,
            "total_carbs": 70.0,
            "total_fat": 18.0,
            "foods": [
                {
                    "name": "Ức gà áp chảo & Cơm gạo lứt",
                    "grams": 300,
                    "weight_grams": 300,
                    "calories": 650,
                    "protein": 45.0,
                    "carbs": 70.0,
                    "fat": 18.0,
                    "group": "protein",
                }
            ],
        },
        {
            "meal_type": "Snack",
            "time": "16:00",
            "total_calories": 250,
            "total_protein": 15.0,
            "total_carbs": 30.0,
            "total_fat": 7.0,
            "foods": [
                {
                    "name": "Sữa chua Hy Lạp & Chuối",
                    "grams": 180,
                    "weight_grams": 180,
                    "calories": 250,
                    "protein": 15.0,
                    "carbs": 30.0,
                    "fat": 7.0,
                    "group": "dairy",
                }
            ],
        },
        {
            "meal_type": "Dinner",
            "time": "19:00",
            "total_calories": 600,
            "total_protein": 35.0,
            "total_carbs": 60.0,
            "total_fat": 20.0,
            "foods": [
                {
                    "name": "Cá hồi áp chảo & Khoai lang",
                    "grams": 280,
                    "weight_grams": 280,
                    "calories": 600,
                    "protein": 35.0,
                    "carbs": 60.0,
                    "fat": 20.0,
                    "group": "protein",
                }
            ],
        },
    ]

    meals = default_meals[: max(1, min(len(default_meals), int(req_meal_count)))]
    total_cal = sum(m["total_calories"] for m in meals)
    total_pro = round(sum(m["total_protein"] for m in meals), 1)
    total_carb = round(sum(m["total_carbs"] for m in meals), 1)
    total_fat = round(sum(m["total_fat"] for m in meals), 1)

    return {
        "plan": {
            "date": today_str,
            "meals": meals,
            "total_calories": total_cal,
            "nutrition_summary": {
                "protein": total_pro,
                "carbs": total_carb,
                "fat": total_fat,
            },
        },
        "generated_at": datetime.utcnow().isoformat(),
        "macro_targets": {
            "calories": health_stats.get("daily_calories", target_calories),
            "protein": health_stats.get("target_protein", int(total_pro)),
            "carbs": health_stats.get("target_carbs", int(total_carb)),
            "fat": health_stats.get("target_fat", int(total_fat)),
        },
        "plan_meta": {
            "style": req_style,
            "meal_count": len(meals),
            "remaining_only": req_remaining_only,
            "calories_consumed_today": 0,
            "calories_remaining": target_calories,
        },
        "user_profile": {
            "goal": goal,
            "activity_level": activity_level,
        },
    }


@router.post("/generate-plan")
async def generate_nutrition_plan(
    request: NutritionPlanRequest,
    current_user: dict = Depends(get_current_user),
):
    try:
        gemini_key = (os.getenv("GEMINI_API_KEY") or "").strip()
        if gemini_key:
            try:
                import google.generativeai as genai
                genai.configure(api_key=gemini_key)
                _ = genai.GenerativeModel(os.getenv("GEMINI_MODEL", "gemini-1.5-flash"))
            except Exception as llm_err:
                logger.warning("Meal plan LLM client init fallback: %s", type(llm_err).__name__)
        else:
            logger.info("GEMINI_API_KEY missing or empty for generate-plan; using local/mock fallback.")

        user_id, user_email = _resolve_user_identity(current_user)
        user = _get_user_record(current_user, user_id, user_email)
        if not user:
            user = current_user if isinstance(current_user, dict) else {}

        health_stats = user.get("health_stats", {}) or {}
        profile      = user.get("profile", {}) or {}

        target_calories = (
            health_stats.get("target_calories")
            or health_stats.get("daily_calories")
            or request.target_calories
            or 2000
        )
        target_protein = health_stats.get("target_protein", 0)
        target_carbs   = health_stats.get("target_carbs",   0)
        target_fat     = health_stats.get("target_fat",     0)

        raw_goal = profile.get("goal", "") or request.goal or "maintain"
        goal     = _normalize_goal(raw_goal)

        # Calculate consumed and remaining calories for remaining_only mode
        consumed = 0
        remaining = target_calories
        
        if request.remaining_only:
            today = get_vn_date_str()
            try:
                today_logs = _find_user_docs(
                    nutrition_collection,
                    user_id,
                    user_email,
                    {"date": today},
                )
                consumed = sum(log.get("total_calories", 0) for log in today_logs)
                remaining = max(500, target_calories - consumed)  # ensure min 500
            except Exception:
                remaining = max(500, target_calories)  # fallback

        try:
            plan = meal_generator.generate_plan(
                user=user,
                request=request
            )
        except Exception as gen_err:
            logger.warning("meal_generator.generate_plan failed, returning mock plan: %s", gen_err)
            plan = None

        if not isinstance(plan, dict) or not plan.get("meals"):
            return _build_fallback_nutrition_plan(request=request, current_user=user)

        return {
            "plan":          plan,
            "generated_at":  datetime.utcnow().isoformat(),
            "macro_targets": {
                "calories": health_stats.get("daily_calories", target_calories),
                "protein":  health_stats.get("target_protein", 0),
                "carbs":    health_stats.get("target_carbs", 0),
                "fat":      health_stats.get("target_fat", 0),
            },
            "plan_meta": {
                "style":          request.style,
                "meal_count":     request.meal_count,
                "remaining_only": request.remaining_only,
                "calories_consumed_today": consumed if request.remaining_only else 0,
                "calories_remaining":      remaining if request.remaining_only else target_calories,
            },
            "user_profile": {
                "goal":           goal,
                "activity_level": profile.get("activity_level", "moderate"),
            },
        }
    except Exception as e:
        logger.warning("generate_nutrition_plan fallback triggered: %s", e)
        return _build_fallback_nutrition_plan(request=request, current_user=current_user)


# ─────────────────────────────────────────
# WEEKLY REPORT
# ─────────────────────────────────────────
@router.get("/report/weekly")
async def get_weekly_report(
    start_date: str,
    current_user: dict = Depends(get_current_user),
):
    try:
        user_id, user_email = _resolve_user_identity(current_user)
        try:
            start = datetime.strptime(start_date, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(400, "start_date must be yyyy-MM-dd")

        if nutrition_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        end = start + timedelta(days=7)

        user         = _get_user_record(current_user, user_id, user_email)
        health_stats = (user.get("health_stats") or {}) if isinstance(user, dict) else {}
        macro_targets = {
            "calories": health_stats.get("target_calories") or health_stats.get("daily_calories") or 2000,
            "protein":  health_stats.get("target_protein", 50),
            "carbs":    health_stats.get("target_carbs",   250),
            "fat":      health_stats.get("target_fat",     65),
        }

        daily_map = {}
        for i in range(7):
            day = (start + timedelta(days=i)).strftime("%Y-%m-%d")
            daily_map[day] = {"date": day, "calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0, "log_count": 0}

        end_str = end.strftime("%Y-%m-%d")

        reset_col = db["day_resets"]
        reset_map = {}
        for day in daily_map:
            reset_doc = _find_one_user_doc(reset_col, user_id, user_email, {"date": day})
            reset_map[day] = reset_doc["reset_at"] if reset_doc else None

        # nutrition_plans (single source of truth for consumed, matching Daily Summary)
        plans = _find_user_docs(
            nutrition_collection,
            user_id,
            user_email,
            {"date": {"$gte": start_date, "$lt": end_str}},
        )
        for plan in plans:
            day = str(plan.get("date", ""))[:10]
            if day in daily_map:
                reset_at = reset_map.get(day)
                if reset_at and not _is_created_after_reset(plan.get("created_at"), reset_at):
                    continue
                foods_list = plan.get("foods", [])
                daily_map[day]["calories"]  += float(plan.get("total_calories") or sum(float(f.get("calories", 0)) for f in foods_list))
                daily_map[day]["protein"]   += float(plan.get("total_protein")  or sum(float(f.get("protein", 0)) for f in foods_list))
                daily_map[day]["carbs"]     += float(plan.get("total_carbs")    or sum(float(f.get("carbs", 0)) for f in foods_list))
                daily_map[day]["fat"]       += float(plan.get("total_fat")      or sum(float(f.get("fat", 0)) for f in foods_list))
                daily_map[day]["log_count"] += 1

        daily_list = [
            {
                "date":      d["date"],
                "calories":  round(d["calories"], 1),
                "protein":   round(d["protein"],  1),
                "carbs":     round(d["carbs"],    1),
                "fat":       round(d["fat"],      1),
                "log_count": d["log_count"],
            }
            for d in daily_map.values()
        ]

        total_calories = sum(d["calories"] for d in daily_list)
        total_protein  = sum(d["protein"]  for d in daily_list)
        total_carbs    = sum(d["carbs"]    for d in daily_list)
        total_fat      = sum(d["fat"]      for d in daily_list)
        days_logged    = sum(1 for d in daily_list if d["log_count"] > 0)

        return {
            "start_date":    start_date,
            "end_date":      (end - timedelta(days=1)).strftime("%Y-%m-%d"),
            "days_logged":   days_logged,
            "daily":         daily_list,
            "weekly_totals": {
                "calories": round(total_calories, 1),
                "protein":  round(total_protein,  1),
                "carbs":    round(total_carbs,     1),
                "fat":      round(total_fat,       1),
            },
            "daily_average": {"calories": round(total_calories / 7, 1)},
            "macro_targets": macro_targets,
        }

    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, detail=str(e))


# ===== STORY LOG =====
@router.post("/log-story")
async def create_log_story(
    meal_type: str = Form(...),
    logged_at: str = Form(...),
    note: str = Form(default=""),
    food_name: str = Form(default=""),
    food_label: str = Form(default=""),
    calories: float = Form(default=0.0),
    protein: float = Form(default=0.0),
    carbs: float = Form(default=0.0),
    fat: float = Form(default=0.0),
    grams: float = Form(default=100.0),
    file: Optional[UploadFile] = File(default=None),
    user: dict = Depends(get_current_user),
):
    try:
        if story_logs_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        user_id, user_email = _resolve_user_identity(user)
        story_date = _valid_or_today_date(logged_at[:10] if logged_at else None)

        # Handle image upload to Cloudinary
        image_url = ""
        if file:
            try:
                contents = await file.read()
                owner_tag = user_id or user_email or "user"
                result = cloudinary.uploader.upload(
                    contents,
                    folder="saman/stories",
                    public_id=f"{owner_tag}_{datetime.utcnow().timestamp()}",
                    overwrite=True,
                )
                image_url = result.get("secure_url", "")
            except Exception as e:
                logger.warning("Cloudinary upload failed: %s", e)

        log_doc = {
            "user_id":    user_id,
            "user_email": user_email,
            "meal_type":  meal_type,
            "date":       story_date,
            "food_name":  food_name or "Unknown",
            "food_label": food_label,
            "grams":      grams,
            "calories":   calories,
            "protein":    protein,
            "carbs":      carbs,
            "fat":        fat,
            "note":       note,
            "logged_at":  logged_at,
            "source":     "story",
            "created_at": datetime.utcnow().isoformat(),
            "image_url":  image_url,  # ← THÊM
        }
        result = story_logs_collection.insert_one(log_doc)
        return {"log_id": str(result.inserted_id), "status": "saved", "message": "Story log saved"}
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("create_log_story error: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/log-story/{date}")
async def get_log_stories(date: str, user: dict = Depends(get_current_user)):
    try:
        if story_logs_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")
        user_id, user_email = _resolve_user_identity(user)
        logs = _find_user_docs(
            story_logs_collection,
            user_id,
            user_email,
            {"logged_at": {"$regex": f"^{date}"}},
            sort_field="created_at",
            sort_dir=-1,
        )
        for log in logs:
            log["_id"] = str(log["_id"])
        return {"date": date, "stories": logs, "total": len(logs)}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/log-story/{log_id}")
async def delete_log_story(log_id: str, user: dict = Depends(get_current_user)):
    try:
        if story_logs_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")
        try:
            obj_id = ObjectId(log_id)
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid log_id format")
        user_id, user_email = _resolve_user_identity(user)
        result = _delete_one_user_doc(
            story_logs_collection,
            user_id,
            user_email,
            {"_id": obj_id},
        )
        if not result or result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Log not found or not authorized")
        
        # ✅ NEW: Xoá đồng thời nutrition log entry gắn với story này
        if nutrition_collection is not None:
            try:
                _delete_many_user_docs(
                    nutrition_collection,
                    user_id,
                    user_email,
                    {"story_id": log_id},
                )
                logger.info("Successfully deleted linked nutrition logs for story_id=%s", log_id)
            except Exception as e:
                logger.warning("Failed to delete linked nutrition logs: %s", e)

        return {"status": "deleted", "log_id": log_id}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/reset-day")
async def reset_day(
    request: DayResetRequest,
    user: dict = Depends(get_current_user),
):
    """Mark reset timestamp. Daily view shows entries AFTER this point only."""
    user_id, user_email = _resolve_user_identity(user)
    target_date = _valid_or_today_date(request.date)
    reset_col = db["day_resets"]
    reset_at  = datetime.utcnow()
    existing_reset = _find_one_user_doc(reset_col, user_id, user_email, {"date": target_date})
    set_payload = {
        "reset_at": reset_at,
        "updated_at": reset_at,
        "user_id": user_id,
        "user_email": user_email,
        "date": target_date,
    }

    if existing_reset and existing_reset.get("_id") is not None:
        reset_col.update_one(
            {"_id": existing_reset["_id"]},
            {"$set": set_payload},
        )
    else:
        filter_q = {"date": target_date, "user_id": user_id, "user_email": user_email}
        reset_col.update_one(
            filter_q,
            {"$set": set_payload},
            upsert=True,
        )
    return {"status": "reset", "date": target_date, "reset_at": reset_at.isoformat()}


@router.post("/log")
async def log_nutrition_entry(entry: NutritionEntry, user: dict = Depends(get_current_user)):
    """Legacy endpoint."""
    return {"message": "Use POST /logs instead", "status": "deprecated"}
