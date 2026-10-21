from backend.app.models.user import UserProfileInput, UserHealthStats
from backend.app.models.common import Gender, ActivityLevel, Goal
from datetime import datetime


def calculate_tdee(profile: dict) -> dict:
    w = profile["weight"]
    h = profile["height"]
    a = profile["age"]
    g = profile["gender"]

    if g == "male":
        bmr = 10 * w + 6.25 * h - 5 * a + 5
    else:
        bmr = 10 * w + 6.25 * h - 5 * a - 161

    multipliers = {
        "sedentary": 1.2,
        "light": 1.375,
        "moderate": 1.55,
        "active": 1.725,
        "very_active": 1.9,
    }
    tdee = bmr * multipliers.get(profile["activity_level"], 1.55)

    goal = profile.get("goal")
    if goal in ("lose_weight", "LOSE_WEIGHT"):
        target = tdee * 0.8
    elif goal in ("gain_muscle", "GAIN_MUSCLE"):
        target = tdee * 1.1
    else:
        target = tdee

    protein_g = w * 2.0
    fat_g = target * 0.25 / 9
    carbs_g = (target - protein_g * 4 - fat_g * 9) / 4

    return {
        "tdee": round(tdee),
        "target_calories": round(target),
        "target_protein": round(protein_g),
        "target_carbs": round(carbs_g),
        "target_fat": round(fat_g),
    }

class HealthEngine:
    @staticmethod
    def calculate_stats(profile: UserProfileInput) -> UserHealthStats:
        """
        Tính toán tất cả chỉ số sức khoẻ dựa trên Profile đầu vào.
        Sử dụng công thức Mifflin-St Jeor (Chuẩn y khoa hiện nay).
        """
        
        import math

        weight = profile.get("weight") if isinstance(profile, dict) else getattr(profile, "weight", None)
        height = profile.get("height") if isinstance(profile, dict) else getattr(profile, "height", None)
        age = profile.get("age") if isinstance(profile, dict) else getattr(profile, "age", None)
        gender = profile.get("gender") if isinstance(profile, dict) else getattr(profile, "gender", None)
        activity_level = profile.get("activity_level") if isinstance(profile, dict) else getattr(profile, "activity_level", None)
        goal = profile.get("goal") if isinstance(profile, dict) else getattr(profile, "goal", None)

        if (
            weight is None
            or height is None
            or age is None
            or gender is None
            or activity_level is None
            or goal is None
        ):
            raise ValueError("Missing required profile fields for TDEE calculation")

        try:
            w_float = float(weight)
            h_float = float(height)
            a_int = int(age)
        except (ValueError, TypeError):
            raise ValueError("Invalid numeric values for profile fields")

        if not math.isfinite(w_float) or w_float <= 0:
            raise ValueError("Weight must be a positive finite number")
        if not math.isfinite(h_float) or h_float <= 0:
            raise ValueError("Height must be a positive finite number")
        if a_int < 13 or a_int > 120:
            raise ValueError("Age must be between 13 and 120")

        # 1. Tính BMI (Body Mass Index)
        height_m = h_float / 100
        bmi = round(w_float / (height_m ** 2), 1)

        gender_str = gender.value if hasattr(gender, "value") else str(gender)
        if gender_str not in ("male", "female"):
            gender_str = "female"

        act_str = activity_level.value if hasattr(activity_level, "value") else str(activity_level or "")
        activity_map = {
            "low": "sedentary",
            "medium": "moderate",
            "high": "active",
            "sedentary": "sedentary",
            "light": "light",
            "moderate": "moderate",
            "active": "active",
            "very_active": "very_active",
        }
        activity_level_norm = activity_map.get(act_str, "moderate")

        goal_val = goal.value if hasattr(goal, "value") else str(goal or "")
        goal_norm = goal_val
        if goal_norm == "maintain_weight":
            goal_norm = "maintain"

        tdee_result = calculate_tdee(
            {
                "weight": w_float,
                "height": h_float,
                "age": a_int,
                "gender": gender_str,
                "activity_level": activity_level_norm,
                "goal": goal_norm,
            }
        )

        bmr = None
        if gender_str == "male":
            bmr = 10 * w_float + 6.25 * h_float - 5 * a_int + 5
        else:
            bmr = 10 * w_float + 6.25 * h_float - 5 * a_int - 161

        # 6. Tính lượng nước cần uống (Water Intake)
        water_target = int(w_float * 35)

        return UserHealthStats(
            bmi=bmi,
            bmr=round(bmr) if bmr is not None else None,
            tdee=int(tdee_result["tdee"]),
            daily_calories=int(tdee_result["target_calories"]),
            daily_calorie_needs=int(tdee_result["target_calories"]),
            water_target_ml=water_target,
            target_protein=int(tdee_result["target_protein"]),
            target_carbs=int(tdee_result["target_carbs"]),
            target_fat=int(tdee_result["target_fat"]),
            updated_at=datetime.utcnow()
        )