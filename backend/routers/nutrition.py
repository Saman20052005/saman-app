
from fastapi import APIRouter, Depends, HTTPException, Query, File, Form, UploadFile
from datetime import datetime, date, timedelta
from typing import Optional, List, Dict, Any
import pydantic as pd
import logging
import unicodedata          # ✅ PATCH B
import os
from bson import ObjectId
import cloudinary
import cloudinary.uploader

from backend.auth_utils import get_current_user
from backend.app.repositories.user_repository import UserRepository
from backend.app.database import (
    nutrition_collection,
    story_logs_collection,
    foods_collection,
    water_collection,
    user_foods_collection,  # ✅ PATCH C/D
    db,
)
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
# HELPER
# ─────────────────────────────────────────
def _normalize_text(text: str) -> str:
    """Strip diacritics cho fuzzy search tiếng Việt: phở → pho, bún → bun"""
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

async def _resolve_food_data(foods: list, user_email: str, db) -> list:
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
                # 1. Tìm trong user_foods trước
                found = db.user_foods_collection.find_one({
                    "_id": ObjectId(food_id),
                    "user_email": user_email
                })
                # 2. Fallback: tìm trong global foods
                if not found:
                    found = db.foods_collection.find_one({
                        "_id": ObjectId(food_id)
                    })
                
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
        
        resolved.append(food)
    return resolved


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
    amount_ml: int
    time: Optional[str] = None

class MealSwapRequest(pd.BaseModel):
    log_id: str
    food_index: int
    replacement_food_id: str

class DayResetRequest(pd.BaseModel):
    date: str  # "yyyy-MM-dd"


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
            foods_collection.find(mongo_query, {"_id": 0}).limit(limit)
        )
        for f in global_foods:
            f["source_type"] = "global"

        # 2. Search My Food của user
        my_foods = []
        if user_foods_collection is not None:
            my_query = {
                "user_email": current_user["email"],
                "$or": [
                    {"name":        {"$regex": q_raw,        "$options": "i"}},
                    {"name_search": {"$regex": q_normalized, "$options": "i"}},
                ],
            }
            my_foods = list(
                user_foods_collection.find(
                    my_query,
                    {"_id": 0, "user_email": 0},
                ).limit(10)
            )
            for f in my_foods:
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

        foods = list(
            user_foods_collection.find(
                {"user_email": current_user["email"]},
                {"_id": 0, "user_email": 0},
            ).sort("created_at", -1)
        )
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

        doc = {
            "user_email":       user["email"],
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
        logger.info("My Food created: user=%s food=%s", user["email"], food.name)

        return {
            "id":      str(result.inserted_id),
            "message": "Food saved to My Food",
            "food":    {k: v for k, v in doc.items() if k not in ("_id", "user_email", "created_at")},
            "status":  "saved",
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("create_food error: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


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

        # Resolve food data before saving
        resolved_foods = await _resolve_food_data(log.foods, user["email"], db)
        
        # Single source of truth for macro calculations – frontend must not recalculate
        t_pro = sum(float(f.get("protein", 0)) for f in resolved_foods)
        t_carb = sum(float(f.get("carbs", 0)) for f in resolved_foods)
        t_fat = sum(float(f.get("fat", 0)) for f in resolved_foods)
        
        doc = {
            "user_email":     user["email"],
            "date":           log.date,
            "meal_type":      log.meal_type,
            "foods":          resolved_foods,
            "total_calories": log.total_calories,
            "total_protein":  round(t_pro, 1),
            "total_carbs":    round(t_carb, 1),
            "total_fat":      round(t_fat, 1),
            "notes":          log.notes,
            "story_id":       log.story_id,
            "created_at":     datetime.utcnow(),
            "updated_at":     datetime.utcnow(),
        }
        result = nutrition_collection.insert_one(doc)
        return {
            "id":         str(result.inserted_id),
            "message":    "Nutrition log created successfully",
            "log":        log.dict(),
            "created_at": datetime.utcnow().isoformat(),
            "status":     "saved",
        }
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

        logs = list(
            nutrition_collection.find(
                {"user_email": user["email"], "date": date}
            ).sort("created_at", -1)
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

        log = nutrition_collection.find_one({
            "_id": ObjectId(log_id), "user_email": user["email"],
        })
        if not log:
            raise HTTPException(status_code=404, detail="Log not found")

        foods = log.get("foods", [])
        if request.food_index >= len(foods):
            raise HTTPException(status_code=400, detail="food_index out of range")

        # Tìm replacement food — user_foods trước, fallback global
        replacement = None
        for col in [user_foods_collection, foods_collection]:
            if col is None:
                continue
            try:
                replacement = col.find_one({"_id": ObjectId(request.replacement_food_id)})
                if replacement:
                    break
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

        nutrition_collection.update_one(
            {"_id": ObjectId(log_id)},
            {"$set": {
                "foods":          foods,
                "total_calories": new_total,
                "total_protein":  new_total_pro,
                "total_carbs":    new_total_carb,
                "total_fat":      new_total_fat,
                "updated_at":     datetime.utcnow()
            }},
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


@router.delete("/logs/{log_id}")
async def delete_nutrition_log(log_id: str, user: dict = Depends(get_current_user)):
    try:
        if nutrition_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")
        result = nutrition_collection.delete_one({
            "_id": ObjectId(log_id),
            "user_email": user["email"],
        })
        if result.deleted_count == 0:
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
    """Log water intake — persist to water_logs collection."""
    try:
        if water_collection is None:
            raise HTTPException(status_code=503, detail="Database not available")

        # Upsert: cộng dồn lượng nước trong ngày
        existing = water_collection.find_one({
            "user_email": user["email"],
            "date":       water_log.date,
        })

        if existing:
            # Overwrite với giá trị mới (Flutter gửi total, không phải delta)
            water_collection.update_one(
                {"_id": existing["_id"]},
                {"$set": {
                    "amount_ml":  water_log.amount_ml,
                    "updated_at": datetime.utcnow(),
                }},
            )
            doc_id = str(existing["_id"])
        else:
            result = water_collection.insert_one({
                "user_email": user["email"],
                "date":       water_log.date,
                "amount_ml":  water_log.amount_ml,
                "created_at": datetime.utcnow(),
                "updated_at": datetime.utcnow(),
            })
            doc_id = str(result.inserted_id)

        return {
            "id":        doc_id,
            "message":   "Water intake logged",
            "amount_ml": water_log.amount_ml,
            "date":      water_log.date,
            "status":    "saved",
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# ✅ PATCH A — GET /{date} (đọc từ DB)
# ─────────────────────────────────────────
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

        logs = list(
            nutrition_collection.find(
                {"user_email": current_user["email"], "date": date}
            ).sort("created_at", -1)
        )

        # Reset filter — chỉ hiển thị entries SAU reset timestamp
        reset_col = db["day_resets"]
        reset_doc = reset_col.find_one({"user_email": current_user["email"], "date": date})
        reset_at  = reset_doc["reset_at"] if reset_doc else None
        if reset_at:
            logs = [log for log in logs if log.get("created_at", datetime.min) > reset_at]

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
            
            # Create meal entry with foodsList
            entries.append({
                "food_name": primary_food.get("name", "Unknown Food"),
                "calories": meal_total_cal,
                "protein": meal_total_pro,
                "carbs": meal_total_carb,
                "fat": meal_total_fat,
                "meal_type": log.get("meal_type", ""),
                "log_id": log_id,
                "weight_g": primary_food.get("weight_grams", 100),
                "foodsList": foods_list,  # Add full foods list for UI
                "total_calories": meal_total_cal,  # Add meal-level total
                "total_protein": meal_total_pro,
                "total_carbs": meal_total_carb,
                "total_fat": meal_total_fat,
            })
            
            total_calories += meal_total_cal
            total_protein  += meal_total_pro
            total_carbs    += meal_total_carb
            total_fat      += meal_total_fat

        # Lấy water log trong ngày
        current_water = 0
        if water_collection is not None:
            water_doc = water_collection.find_one({
                "user_email": current_user["email"],
                "date":       date,
            })
            if water_doc:
                current_water = water_doc.get("amount_ml", 0)

        # Lấy water_target từ profile
        user_data    = user_repo.get_by_email(current_user["email"])
        health_stats = user_data.get("health_stats", {}) if user_data else {}
        water_target = health_stats.get("water_target_ml", 2000)

        # Lấy target_calories từ health_stats (đã có trong context)
        target_calories_today = health_stats.get("daily_calories", 2000)

        # ── Rollover: 50% deficit hôm qua ──────────────────────
        rollover_calories = 0
        try:
            yesterday = (
                datetime.strptime(date, "%Y-%m-%d") - timedelta(days=1)
            ).strftime("%Y-%m-%d")
            
            # Không bị ảnh hưởng bởi reset của hôm qua — đọc toàn bộ
            yesterday_logs = list(nutrition_collection.find({
                "user_email": current_user["email"],
                "date": yesterday,
            }))
            yesterday_cal = sum(
                sum(float(f.get("calories", 0)) for f in log.get("foods", []))
                for log in yesterday_logs
            )
            deficit = target_calories_today - yesterday_cal
            rollover_calories = max(0, int(deficit * 0.5))
        except Exception:
            pass
        # ───────────────────────────────────────────────────────

        return {
            "date":           date,
            "entries":        entries,
            "total_calories": round(total_calories),
            "total_protein":  round(total_protein,  1),
            "total_carbs":    round(total_carbs,    1),
            "total_fat":      round(total_fat,      1),
            "current_water":  current_water,
            "water_target":   water_target,
            "rollover_calories": rollover_calories,   # NEW — 0 if no deficit
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.exception("get_nutrition_by_date error: %s", e)
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# GENERATE PLAN (giữ nguyên logic, không thay đổi)
# ─────────────────────────────────────────
@router.post("/generate-plan")
async def generate_nutrition_plan(
    request: NutritionPlanRequest,
    current_user: dict = Depends(get_current_user),
):
    try:
        user = user_repo.get_by_email(current_user["email"])
        if not user:
            raise HTTPException(status_code=404, detail="User not found")

        health_stats = user.get("health_stats", {})
        profile      = user.get("profile", {})

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
            today = datetime.utcnow().strftime("%Y-%m-%d")
            try:
                from backend.services.meal_generator import MealGeneratorService
                meal_service = MealGeneratorService(nutrition_collection)
                today_logs = meal_service._get_today_logs(user)
                consumed = sum(log.get("total_calories", 0) for log in today_logs)
                remaining = max(500, target_calories - consumed)  # ensure min 500
            except Exception:
                remaining = max(500, target_calories)  # fallback

        plan = meal_generator.generate_plan(
            user=user,
            request=request
        )

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
        raise HTTPException(status_code=500, detail=str(e))


# ─────────────────────────────────────────
# WEEKLY REPORT (giữ nguyên)
# ─────────────────────────────────────────
@router.get("/report/weekly")
async def get_weekly_report(
    start_date: str,
    current_user: dict = Depends(get_current_user),
):
    try:
        user_email = current_user["email"]
        try:
            start = datetime.strptime(start_date, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(400, "start_date must be yyyy-MM-dd")

        end = start + timedelta(days=7)

        user         = user_repo.get_by_email(user_email)
        health_stats = user.get("health_stats", {}) if user else {}
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

        # story_logs
        if story_logs_collection is not None:
            for log in story_logs_collection.find({
                "user_email": user_email,
                "logged_at":  {"$gte": start_date, "$lt": end_str},
            }):
                day = str(log.get("logged_at", ""))[:10]
                if day in daily_map:
                    daily_map[day]["calories"]  += float(log.get("calories", 0))
                    daily_map[day]["protein"]   += float(log.get("protein",  0))
                    daily_map[day]["carbs"]     += float(log.get("carbs",    0))
                    daily_map[day]["fat"]       += float(log.get("fat",      0))
                    daily_map[day]["log_count"] += 1

        # nutrition_plans (manual logs)
        if nutrition_collection is not None:
            for plan in nutrition_collection.find({
                "user_email": user_email,
                "date":       {"$gte": start_date, "$lt": end_str},
            }):
                day = str(plan.get("date", ""))[:10]
                if day in daily_map:
                    # Single source of truth: use stored totals if available
                    if "total_calories" in plan and "total_protein" in plan:
                        daily_map[day]["calories"] += float(plan.get("total_calories", 0))
                        daily_map[day]["protein"]  += float(plan.get("total_protein",  0))
                        daily_map[day]["carbs"]    += float(plan.get("total_carbs",    0))
                        daily_map[day]["fat"]      += float(plan.get("total_fat",      0))
                    else:
                        # Fallback for old records
                        for food in plan.get("foods", []):
                            daily_map[day]["calories"] += float(food.get("calories", 0))
                            daily_map[day]["protein"]  += float(food.get("protein",  0))
                            daily_map[day]["carbs"]    += float(food.get("carbs",    0))
                            daily_map[day]["fat"]      += float(food.get("fat",      0))
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


# ===== STORY LOG (giữ nguyên) =====
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

        # Handle image upload to Cloudinary
        image_url = ""
        if file:
            try:
                contents = await file.read()
                result = cloudinary.uploader.upload(
                    contents,
                    folder="saman/stories",
                    public_id=f"{user['email']}_{datetime.utcnow().timestamp()}",
                    overwrite=True,
                )
                image_url = result.get("secure_url", "")
            except Exception as e:
                logger.warning("Cloudinary upload failed: %s", e)

        log_doc = {
            "user_email": user["email"],
            "meal_type":  meal_type,
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
        cursor = story_logs_collection.find({
            "user_email": user["email"],
            "logged_at":  {"$regex": f"^{date}"},
        }).sort("created_at", -1)
        logs = list(cursor)
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
        result = story_logs_collection.delete_one({"_id": obj_id, "user_email": user["email"]})
        if result.deleted_count == 0:
            raise HTTPException(status_code=404, detail="Log not found or not authorized")
        
        # ✅ NEW: Xoá đồng thời nutrition log entry gắn với story này
        if nutrition_collection is not None:
            try:
                nutrition_collection.delete_many({
                    "user_email": user["email"],
                    "story_id":   log_id,
                })
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
    reset_col = db["day_resets"]
    reset_at  = datetime.utcnow()
    reset_col.update_one(
        {"user_email": user["email"], "date": request.date},
        {"$set": {"reset_at": reset_at, "updated_at": reset_at}},
        upsert=True,
    )
    return {"status": "reset", "date": request.date, "reset_at": reset_at.isoformat()}


@router.post("/log")
async def log_nutrition_entry(entry: NutritionEntry, user: dict = Depends(get_current_user)):
    """Legacy endpoint."""
    return {"message": "Use POST /logs instead", "status": "deprecated"}
