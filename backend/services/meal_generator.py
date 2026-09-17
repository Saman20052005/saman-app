import random
from datetime import datetime
from typing import List, Optional, Dict, Any

# Safe imports - remove dependency on app.models
try:
    from bson import ObjectId
    from backend.app.models.common import Goal, FoodTag
except ImportError:
    ObjectId = str
    # Fallback definitions if imports fail
    class Goal:
        MAINTAIN = "maintain_weight"
        WEIGHT_LOSS = "lose_weight"
        MUSCLE_GAIN = "gain_muscle"
    
    class FoodTag:
        HIGH_FAT = "High Fat"
        HIGH_CARB = "High Carb"
        HIGH_PROTEIN = "High Protein"

class MealGenerator:
    """Mock MealGenerator for deployment without database dependency"""
    
    def __init__(self, config=None):
        self.config = config or {}
    
    def generate_daily_plan(self, target_calories: int, dietary_preferences: List[str] = [], 
                          allergies: List[str] = [], goal: str = "maintain") -> Dict[str, Any]:
        """Generate daily meal plan (mock implementation)"""
        return {
            "date": datetime.utcnow().strftime("%Y-%m-%d"),
            "target_calories": target_calories,
            "meals": [
                {
                    "meal_type": "Breakfast",
                    "time": "07:00",
                    "foods": [
                        {"name": "Oatmeal", "calories": int(target_calories * 0.15), "protein": 10.0, "carbs": 30.0, "fat": 5.0}
                    ]
                },
                {
                    "meal_type": "Lunch", 
                    "time": "12:00",
                    "foods": [
                        {"name": "Grilled Chicken", "calories": int(target_calories * 0.35), "protein": 35.0, "carbs": 25.0, "fat": 10.0}
                    ]
                },
                {
                    "meal_type": "Dinner",
                    "time": "19:00", 
                    "foods": [
                        {"name": "Salmon", "calories": int(target_calories * 0.35), "protein": 30.0, "carbs": 20.0, "fat": 15.0}
                    ]
                }
            ],
            "total_calories": target_calories,
            "nutrition_summary": {
                "protein": 75.0,
                "carbs": 75.0, 
                "fat": 30.0
            }
        }

# Legacy class for backward compatibility
class MealGeneratorService:
    """Legacy MealGeneratorService for backward compatibility"""
    
    def __init__(self, db_collection=None):
        self.db = db_collection
    
    def generate_plan(self, request_data: dict) -> List[dict]:
        """Generate meal plan (legacy implementation)"""
        target_calories = request_data.get("target_calories", 2000)
        allergies = request_data.get("allergies", [])
        goal = request_data.get("goal", "maintain")
        
        # Use the new MealGenerator
        generator = MealGenerator()
        plan = generator.generate_daily_plan(target_calories, [], allergies, goal)
        
        # Convert to expected format
        return plan.get("meals", [])

class MealGeneratorService:
    def __init__(self, db_collection):
        self.db = db_collection
        
        # Meal catalogs with Vietnamese names and macro bases
        self.QUICK_MEALS = {
            "Breakfast": [
                {"name": "Bánh mì trứng", "base_protein": 12, "base_carbs": 45, "base_fat": 8},
                {"name": "Phở bò", "base_protein": 20, "base_carbs": 40, "base_fat": 12},
                {"name": "Bún chả", "base_protein": 18, "base_carbs": 42, "base_fat": 10}
            ],
            "Lunch": [
                {"name": "Cơm gà luộc", "base_protein": 35, "base_carbs": 50, "base_fat": 8},
                {"name": "Bún bò Huế", "base_protein": 25, "base_carbs": 55, "base_fat": 15},
                {"name": "Phở cuốn", "base_protein": 15, "base_carbs": 40, "base_fat": 12}
            ],
            "Dinner": [
                {"name": "Cá kho tộ", "base_protein": 30, "base_carbs": 35, "base_fat": 18},
                {"name": "Thịt kho trứng", "base_protein": 28, "base_carbs": 30, "base_fat": 20},
                {"name": "Lẩu thập cẩm", "base_protein": 25, "base_carbs": 40, "base_fat": 15}
            ],
            "Snack": [
                {"name": "Chuối", "base_protein": 1, "base_carbs": 25, "base_fat": 0},
                {"name": "Sữa chua", "base_protein": 10, "base_carbs": 15, "base_fat": 3},
                {"name": "Táo", "base_protein": 0, "base_carbs": 20, "base_fat": 0}
            ]
        }
        
        self.OPTIMAL_MEALS = {
            "Breakfast": [
                {"name": "Yến mạch chuối", "base_protein": 8, "base_carbs": 35, "base_fat": 6},
                {"name": "Bánh mì ức gà", "base_protein": 25, "base_carbs": 40, "base_fat": 8},
                {"name": "Phở bò tái", "base_protein": 22, "base_carbs": 38, "base_fat": 10}
            ],
            "Lunch": [
                {"name": "Cơm gà nướng", "base_protein": 40, "base_carbs": 45, "base_fat": 10},
                {"name": "Bún cá nướng", "base_protein": 32, "base_carbs": 48, "base_fat": 12},
                {"name": "Salad bò lúc lắc", "base_protein": 35, "base_carbs": 25, "base_fat": 15}
            ],
            "Dinner": [
                {"name": "Cá hồi áp chảo", "base_protein": 35, "base_carbs": 30, "base_fat": 20},
                {"name": "Ức gà nướng rau củ", "base_protein": 38, "base_carbs": 28, "base_fat": 12},
                {"name": "Bò bít tết", "base_protein": 42, "base_carbs": 32, "base_fat": 18}
            ],
            "Snack": [
                {"name": "Protein shake", "base_protein": 25, "base_carbs": 10, "base_fat": 3},
                {"name": "Hạt óc chó", "base_protein": 6, "base_carbs": 8, "base_fat": 20},
                {"name": "Trứng luộc", "base_protein": 12, "base_carbs": 2, "base_fat": 10}
            ]
        }
        
        self.FOOD_DB = {
            "Dish": [
                {"name": "Cơm gà luộc", "calories": 280, "protein": 35, "carbs": 50, "fat": 8},
                {"name": "Bún chả", "calories": 300, "protein": 18, "carbs": 42, "fat": 10},
                {"name": "Phở bò", "calories": 320, "protein": 20, "carbs": 40, "fat": 12},
                {"name": "Cá kho tộ", "calories": 350, "protein": 30, "carbs": 35, "fat": 18},
                {"name": "Thịt kho trứng", "calories": 380, "protein": 28, "carbs": 30, "fat": 20},
                {"name": "Cơm gà nướng", "calories": 400, "protein": 40, "carbs": 45, "fat": 10},
                {"name": "Bún cá nướng", "calories": 360, "protein": 32, "carbs": 48, "fat": 12},
                {"name": "Salad bò lúc lắc", "calories": 320, "protein": 35, "carbs": 25, "fat": 15},
                {"name": "Cá hồi áp chảo", "calories": 380, "protein": 35, "carbs": 30, "fat": 20},
                {"name": "Ức gà nướng rau củ", "calories": 340, "protein": 38, "carbs": 28, "fat": 12},
                {"name": "Bò bít tết", "calories": 420, "protein": 42, "carbs": 32, "fat": 18}
            ],
            "Carb": [
                {"name": "Bánh mì trứng", "calories": 260, "protein": 12, "carbs": 45, "fat": 8},
                {"name": "Yến mạch chuối", "calories": 220, "protein": 8, "carbs": 35, "fat": 6},
                {"name": "Bánh mì ức gà", "calories": 300, "protein": 25, "carbs": 40, "fat": 8},
                {"name": "Phở bò tái", "calories": 280, "protein": 22, "carbs": 38, "fat": 10}
            ],
            "Vitamin": [
                {"name": "Chuối", "calories": 100, "protein": 1, "carbs": 25, "fat": 0},
                {"name": "Sữa chua", "calories": 120, "protein": 10, "carbs": 15, "fat": 3},
                {"name": "Táo", "calories": 80, "protein": 0, "carbs": 20, "fat": 0},
                {"name": "Protein shake", "calories": 150, "protein": 25, "carbs": 10, "fat": 3},
                {"name": "Hạt óc chó", "calories": 200, "protein": 6, "carbs": 8, "fat": 20},
                {"name": "Trứng luộc", "calories": 140, "protein": 12, "carbs": 2, "fat": 10}
            ]
        }
        
        self.MACRO_RATIO_BY_GOAL = {
            "maintain": {"protein": 0.25, "carbs": 0.45, "fat": 0.30},
            "weight_loss": {"protein": 0.35, "carbs": 0.35, "fat": 0.30},
            "muscle_gain": {"protein": 0.30, "carbs": 0.45, "fat": 0.25}
        }
        
        self.MEAL_GROUPS = {
            "Breakfast": ["Dish", "Carb"],
            "Lunch": ["Dish"],
            "Dinner": ["Dish"],
            "Snack": ["Vitamin"]
        }
        
        # Map group → MongoDB food group names
        self.GROUP_TO_DB = {
            "protein": ["Protein"],
            "carb":    ["Carb"],
            "fiber":   ["Fiber"],
            "fat":     ["Fat"],
        }

    def _get_meal_food(self, meal_type: str, style: str, index: int = 0) -> dict:
        """Get meal food from catalog based on meal type and style"""
        source = self.OPTIMAL_MEALS if style == "optimal" else self.QUICK_MEALS
        options = source.get(meal_type, source.get("Lunch", []))
        if not options:
            return {"name": meal_type, "base_protein": 20, "base_carbs": 40, "base_fat": 10}
        return options[index % len(options)]

    def _normalize_text(self, text: str) -> str:
        return text.lower().strip() if text else ""

    def _calculate_score(self, food: dict, goal: str) -> float:
        score = 0.0
        p = food.get("protein", 0)
        c = food.get("carbs", 0)
        f = food.get("fat", 0)
        tags = food.get("tags", [])

        if goal == Goal.WEIGHT_LOSS:
            score += p * 2.0
            score -= c * 1.0
            score -= f * 1.5
            if FoodTag.HIGH_FAT in tags: score -= 50
            if FoodTag.HIGH_CARB in tags: score -= 30
            
        elif goal == Goal.MUSCLE_GAIN:
            score += p * 2.0
            score += c * 1.0
            score -= f * 0.5
            if FoodTag.HIGH_PROTEIN in tags: score += 20

        else: # MAINTAIN
            score += p * 1.0
            score -= abs(c - 30) * 0.5
            
        return score

    def _fetch_candidates(self, group: str, allergies: List[str], goal: str = Goal.MAINTAIN) -> List[dict]:
        query = {"group": group}
        if allergies:
            safe_allergies = [self._normalize_text(a) for a in allergies if a.strip()]
            if safe_allergies:
                pattern = "|".join(safe_allergies)
                query["name"] = {"$not": {"$regex": pattern, "$options": "i"}}

        projection = {
            "name": 1, "calories": 1, "protein": 1, "carbs": 1, "fat": 1, 
            "image": 1, "tags": 1, "_id": 1
        }
        
        candidates = list(self.db.find(query, projection))
        if not candidates: return []

        for food in candidates:
            food["_score"] = self._calculate_score(food, goal)

        candidates.sort(key=lambda x: x["_score"], reverse=True)
        top_n = max(5, int(len(candidates) * 0.2))
        return candidates[:top_n]

    def _calculate_serving(self, food: dict, target_cal: int) -> dict:
        base_cal = food.get("calories", 0)
        if base_cal <= 0: return food 
        
        ratio = target_cal / base_cal
        ratio = max(0.5, min(ratio, 4.0))
        
        return {
            "name": food["name"],
            "calories": int(base_cal * ratio),
            "protein": round(food.get("protein", 0) * ratio, 1),
            "carbs": round(food.get("carbs", 0) * ratio, 1),
            "fat": round(food.get("fat", 0) * ratio, 1),
            "tags": food.get("tags", []),
            "weight_grams": int(100 * ratio),
            "food_id": str(food["_id"]),
            "image": food.get("image", None)
        }

    def _pick_food_from_db(self, group: str, meal_type: str, style: str) -> dict:
        """Random chọn 1 food từ MongoDB theo nhóm, tránh trùng trong session"""
        import random
        
        if self.db is None:
            # Fallback về hardcoded nếu không có DB
            return self._fallback_food(group)
        
        db_groups = self.GROUP_TO_DB.get(group, ["Protein"])
        
        try:
            candidates = list(self.db.find(
                {"group": {"$in": db_groups}, "source_type": "global"},
                {"name": 1, "calories": 1, "protein": 1, "carbs": 1, "fat": 1}
            ))
            
            if not candidates:
                return self._fallback_food(group)
            
            # Tránh trùng trong cùng 1 plan (dùng session cache)
            if not hasattr(self, '_used_foods'):
                self._used_foods = set()
            
            available = [f for f in candidates if str(f.get("_id")) not in self._used_foods]
            if not available:
                available = candidates  # reset nếu hết
            
            chosen = random.choice(available)
            self._used_foods.add(str(chosen.get("_id")))
            return chosen
            
        except Exception as e:
            print(f"DB food lookup error: {e}")
            return self._fallback_food(group)

    def _fallback_food(self, group: str) -> dict:
        """Fallback hardcoded nếu DB unavailable"""
        fallbacks = {
            "protein": {"name": "Ức gà luộc",    "calories": 165, "protein": 31, "carbs": 0,  "fat": 3.6},
            "carb":    {"name": "Cơm trắng",      "calories": 130, "protein": 2.7,"carbs": 28, "fat": 0.3},
            "fiber":   {"name": "Rau muống xào",  "calories": 25,  "protein": 3,  "carbs": 3,  "fat": 0.5},
            "fat":     {"name": "Bơ (avocado)",   "calories": 160, "protein": 2,  "carbs": 9,  "fat": 15},
        }
        return fallbacks.get(group, fallbacks["protein"])

    # --- LOGIC MỚI CHO STEP 2 ---
    def swap_single_meal(self, swap_data: dict) -> Optional[dict]:
        """
        Đổi 1 món cụ thể, giữ nguyên calories target của slot đó.
        Input: swap_data (từ SwapMealRequest)
        """
        meal_type = swap_data.get("meal_type")
        old_id = swap_data.get("old_food_id")
        allergies = swap_data.get("allergies", [])
        goal = swap_data.get("goal", Goal.MAINTAIN)
        target_calories = swap_data.get("target_calories", 500)

        # 1. Map Meal Type -> Food Group
        # Logic: Sáng ăn Carb/Dish, Trưa Tối ăn Dish, Snack ăn Vitamin
        if meal_type == "Breakfast":
            # Random chọn nhóm Dish hoặc Carb cho phong phú
            group = random.choice(["Dish", "Carb"])
        elif meal_type == "Snack":
            group = "Vitamin"
        else: # Lunch / Dinner
            group = "Dish"

        # 2. Fetch Candidates (đã sort theo Goal Score)
        candidates = self._fetch_candidates(group, allergies, goal)
        
        # 3. Filter món cũ ra
        filtered = [c for c in candidates if str(c["_id"]) != old_id]

        if not filtered:
            # Nếu lọc xong không còn gì (hiếm), thử tìm group khác
            # Fallback: Nếu thiếu Dish thì tìm Carb đỡ
            if group == "Dish": 
                candidates = self._fetch_candidates("Carb", allergies, goal)
                filtered = [c for c in candidates if str(c["_id"]) != old_id]

        if not filtered:
            return None # Không tìm thấy món thay thế

        # 4. Chọn món thay thế (Random trong top candidates còn lại)
        choice = random.choice(filtered)

        # 5. Tính toán Serving để khớp calories cũ
        new_meal = self._calculate_serving(choice, target_calories)
        new_meal["meal_type"] = meal_type
        
        # Giữ nguyên time nếu cần (Frontend tự handle hoặc gán default)
        return new_meal

    def generate_plan(self, user: dict, request) -> dict:
        """Generate meal plan with new logic for remaining calories and meal distribution"""
        self._used_foods = set()  # ← reset để tránh trùng món giữa các bữa
        calories_target = user.get("health_stats", {}).get("daily_calories", 2000)
        
        if getattr(request, 'remaining_only', False):
            today_logs = self._get_today_logs(user)
            consumed = sum(log.get("total_calories", 0) for log in today_logs)
            remaining = max(500, calories_target - consumed)  # ensure min 500
        else:
            remaining = calories_target
        
        style = getattr(request, 'style', 'optimal')
        meal_count = getattr(request, 'meal_count', 4)
        
        # Map user goal to internal goal
        goal = user.get("profile", {}).get("goal", "maintain")
        goal_map = {
            "gain_muscle": "muscle_gain",
            "muscle_gain": "muscle_gain",
            "lose_weight": "weight_loss",
            "weight_loss": "weight_loss",
            "maintain_weight": "maintain",
            "maintain": "maintain",
        }
        self._current_goal = goal_map.get(goal, "maintain")
        
        if style == "quick":
            distribution = self._distribute_quick(remaining, meal_count)
        else:
            distribution = self._distribute_optimal(remaining, meal_count, user)
        
        return self._build_plan(distribution, style=style)
    
    def _get_today_logs(self, user: dict) -> List[dict]:
        """Get today's nutrition logs for the user"""
        from datetime import datetime
        today = datetime.utcnow().strftime("%Y-%m-%d")
        user_email = user.get("email", "")
        
        try:
            from backend.app.database import nutrition_collection
            if nutrition_collection is not None:
                logs = list(
                    nutrition_collection.find({
                        "user_email": user_email,
                        "date": today
                    })
                )
                return logs
        except Exception:
            pass
        
        return []
    
    def _distribute_quick(self, remaining_calories: int, meal_count: int) -> List[dict]:
        """Quick distribution - equal calories per meal"""
        calories_per_meal = remaining_calories // meal_count
        
        distribution = []
        meal_types = ["Breakfast", "Lunch", "Dinner", "Snack"]
        times = ["07:00", "12:00", "19:00", "15:30"]
        
        for i in range(meal_count):
            distribution.append({
                "meal_type": meal_types[i % len(meal_types)],
                "time": times[i % len(times)],
                "calories": calories_per_meal
            })
        
        return distribution
    
    def _distribute_optimal(self, remaining_calories: int, meal_count: int, user: dict) -> List[dict]:
        """Optimal distribution - balanced macro ratios with 5-meal support for gain_muscle"""
        goal = user.get("health_stats", {}).get("goal", "maintain_weight")
        
        # Standard distribution ratios
        if meal_count == 3:
            ratios = [0.3, 0.4, 0.3]  # Breakfast, Lunch, Dinner
        elif meal_count == 4:
            ratios = [0.25, 0.35, 0.3, 0.1]  # Breakfast, Lunch, Dinner, Snack
        elif meal_count == 5:
            if goal == "gain_muscle":
                ratios = [0.2, 0.25, 0.3, 0.15, 0.1]  # Breakfast, Lunch, Dinner, Snack1, Snack2
            else:
                ratios = [0.2, 0.3, 0.25, 0.15, 0.1]  # Standard 5-meal distribution
        else:
            # Equal distribution for other counts
            ratio = 1.0 / meal_count
            ratios = [ratio] * meal_count
        
        distribution = []
        meal_types = ["Breakfast", "Lunch", "Dinner", "Snack", "Snack"]
        times = ["07:00", "12:00", "19:00", "15:30", "20:00"]
        
        for i in range(meal_count):
            calories = int(remaining_calories * ratios[i])
            distribution.append({
                "meal_type": meal_types[i % len(meal_types)],
                "time": times[i % len(times)],
                "calories": calories
            })
        
        return distribution
    
    def _build_plan(self, meal_distribution: List[dict], style: str = "optimal") -> dict:
        import random
        
        goal   = getattr(self, '_current_goal', 'maintain')
        ratios = self.MACRO_RATIO_BY_GOAL.get(goal, self.MACRO_RATIO_BY_GOAL["maintain"])
        
        meals         = []
        total_calories = 0
        total_protein  = total_carbs = total_fat = 0.0

        for meal_info in meal_distribution:
            target_cal = meal_info["calories"]
            meal_type  = meal_info["meal_type"]
            
            # Nhóm thực phẩm cho từng loại bữa
            is_main = meal_type in ("Breakfast", "Lunch", "Dinner")
            groups  = (
                ["protein", "carb", "fiber", "fat"] if is_main
                else ["protein", "carb"]             # snack/pre/post
            )
            
            # Tính calories mỗi nhóm theo ratio
            active = {g: ratios.get(g, 0.25) for g in groups}
            total_r = sum(active.values())
            norm    = {g: v / total_r for g, v in active.items()}
            
            foods_in_meal = []
            meal_cal = meal_pro = meal_carbs = meal_fat = 0.0
            
            for group in groups:
                group_target = target_cal * norm[group]
                
                # --- Lấy food từ MongoDB ---
                food_data = self._pick_food_from_db(group, meal_type, style)
                if not food_data:
                    continue
                
                fname        = food_data.get("name", group)
                cal_per_100  = food_data.get("calories", 0) or 0
                pro_per_100  = food_data.get("protein",  0) or 0
                carb_per_100 = food_data.get("carbs",    0) or 0
                fat_per_100  = food_data.get("fat",      0) or 0
                
                if cal_per_100 <= 0:
                    continue
                
                grams = round((group_target / cal_per_100) * 100)
                grams = max(30, min(grams, 350))
                ratio = grams / 100.0
                
                fc  = round(cal_per_100  * ratio)
                fp  = round(pro_per_100  * ratio, 1)
                fcb = round(carb_per_100 * ratio, 1)
                ff  = round(fat_per_100  * ratio, 1)
                
                foods_in_meal.append({
                    "name":         fname,
                    "grams":        grams,
                    "calories":     fc,
                    "protein":      fp,
                    "carbs":        fcb,
                    "fat":          ff,
                    "group":        group,
                    "weight_grams": grams,
                })
                
                meal_cal   += fc
                meal_pro   += fp
                meal_carbs += fcb
                meal_fat   += ff
            
            total_calories += meal_cal
            total_protein  += meal_pro
            total_carbs    += meal_carbs
            total_fat      += meal_fat
            
            meals.append({
                "meal_type":      meal_type,
                "time":           meal_info["time"],
                "total_calories": round(meal_cal),
                "total_protein":  round(meal_pro, 1),
                "total_carbs":    round(meal_carbs, 1),
                "total_fat":      round(meal_fat, 1),
                "foods":          foods_in_meal,
            })
        
        return {
            "date":            datetime.utcnow().strftime("%Y-%m-%d"),
            "meals":           meals,
            "total_calories":  round(total_calories),
            "nutrition_summary": {
                "protein": round(total_protein, 1),
                "carbs":   round(total_carbs,   1),
                "fat":     round(total_fat,     1),
            }
        }
    