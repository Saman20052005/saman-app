# [File: app/core/constants.py]

class Goal:
    WEIGHT_LOSS = "weight_loss"   # Giảm cân
    MUSCLE_GAIN = "muscle_gain"   # Tăng cơ
    MAINTAIN = "maintain"         # Giữ dáng

class FoodTag:
    HIGH_CARB = "HIGH_CARB"
    HIGH_FAT = "HIGH_FAT"
    HIGH_SUGAR = "HIGH_SUGAR"
    HIGH_PROTEIN = "HIGH_PROTEIN"

# Ngưỡng cảnh báo (tính trên 100g)
class Thresholds:
    HIGH_CARB = 40.0   # > 40g carb/100g là cao
    HIGH_FAT = 20.0    # > 20g fat/100g là cao
    HIGH_PROTEIN = 15.0 # > 15g protein/100g là cao
    HIGH_SUGAR = 15.0  # > 15g đường/100g là cao