from enum import Enum

class Gender(str, Enum):
    MALE = "male"
    FEMALE = "female"
    OTHER = "other"

class ActivityLevel(str, Enum):
    LOW = "low"         # Ít vận động (Sedentary)
    MEDIUM = "medium"   # Vừa phải (Moderate)
    HIGH = "high"       # Nhiều (Active/Athlete)

class Goal(str, Enum):
    LOSE_WEIGHT = "lose_weight"
    MAINTAIN = "maintain_weight"
    GAIN_MUSCLE = "gain_muscle"
    # Mapping cho logic cũ nếu cần
    WEIGHT_LOSS = "lose_weight" 
    MUSCLE_GAIN = "gain_muscle"

# Bổ sung Enum này vì meal_generator.py đang gọi mà chưa có
class FoodTag(str, Enum):
    HIGH_FAT = "High Fat"
    HIGH_CARB = "High Carb"
    HIGH_PROTEIN = "High Protein"
    VEGAN = "Vegan"