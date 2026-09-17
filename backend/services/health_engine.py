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
        
        # 1. Tính BMI (Body Mass Index)
        # Công thức: Cân nặng (kg) / (Chiều cao (m) ^ 2)
        height_m = profile.height / 100
        bmi = round(profile.weight / (height_m ** 2), 1)

        if profile.weight is None or profile.height is None or profile.age is None or profile.gender is None:
            raise ValueError("Missing required profile fields for TDEE calculation")

        gender_str = profile.gender.value if hasattr(profile.gender, "value") else str(profile.gender)
        if gender_str not in ("male", "female"):
            gender_str = "female"

        activity_level = profile.activity_level.value if hasattr(profile.activity_level, "value") else str(profile.activity_level or "")
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
        activity_level_norm = activity_map.get(activity_level, "moderate")

        goal_val = profile.goal.value if hasattr(profile.goal, "value") else str(profile.goal or "")
        goal_norm = goal_val
        if goal_norm == "maintain_weight":
            goal_norm = "maintain"

        tdee_result = calculate_tdee(
            {
                "weight": float(profile.weight),
                "height": float(profile.height),
                "age": int(profile.age),
                "gender": gender_str,
                "activity_level": activity_level_norm,
                "goal": goal_norm,
            }
        )

        bmr = None
        if gender_str == "male":
            bmr = 10 * float(profile.weight) + 6.25 * float(profile.height) - 5 * int(profile.age) + 5
        else:
            bmr = 10 * float(profile.weight) + 6.25 * float(profile.height) - 5 * int(profile.age) - 161

        # 6. Tính lượng nước cần uống (Water Intake)
        # Công thức: Cân nặng (kg) * 35ml
        water_target = int(profile.weight * 35)

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