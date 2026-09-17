from app.database import foods_collection

foods = [
  {"name": "Grilled Chicken", "calories": 165, "protein": 31, "carbs": 0, "fat": 3.6, "tags": ["high_protein"], "group": "Protein"},
  {"name": "Brown Rice",      "calories": 216, "protein": 5, "carbs": 45, "fat": 1.8, "tags": ["carbs"],        "group": "Carbs"},
  {"name": "Oatmeal",         "calories": 158, "protein": 6, "carbs": 27, "fat": 3.2, "tags": ["fiber"],        "group": "Carbs"},
  {"name": "Salmon",          "calories": 208, "protein": 20, "carbs": 0, "fat": 13, "tags": ["omega3"],       "group": "Protein"},
  {"name": "Egg",             "calories": 78, "protein": 6, "carbs": 0.6,"fat": 5,   "tags": ["protein"],      "group": "Protein"},
  {"name": "Banana",          "calories": 89, "protein": 1, "carbs": 23, "fat": 0.3, "tags": ["fruit"],        "group": "Fruit"},
  {"name": "Sweet Potato",    "calories": 86, "protein": 2, "carbs": 20, "fat": 0.1, "tags": ["carbs"],        "group": "Carbs"},
  {"name": "Greek Yogurt",    "calories": 100, "protein": 17, "carbs": 6, "fat": 0.7, "tags": ["protein"],      "group": "Dairy"},
  {"name": "Avocado",         "calories": 160, "protein": 2, "carbs": 9, "fat": 15, "tags": ["healthy_fat"],  "group": "Fat"},
  {"name": "Broccoli",        "calories": 34, "protein": 3, "carbs": 7, "fat": 0.4, "tags": ["vegetable"],    "group": "Vegetable"},
  {"name": "White Rice",      "calories": 130, "protein": 2.7,"carbs": 28, "fat": 0.3, "tags": ["carbs"],        "group": "Carbs"},
  {"name": "Pho Bo",          "calories": 350, "protein": 25, "carbs": 45, "fat": 6,   "tags": ["vietnamese"],   "group": "Meal"},
  {"name": "Com Tam",         "calories": 480, "protein": 30, "carbs": 65, "fat": 10,  "tags": ["vietnamese"],   "group": "Meal"},
  {"name": "Banh Mi",         "calories": 350, "protein": 15, "carbs": 50, "fat": 9,   "tags": ["vietnamese"],   "group": "Meal"},
]

if foods_collection is not None:
    # Xóa data cũ nếu có
    foods_collection.delete_many({})
    result = foods_collection.insert_many(foods)
    print(f"✅ Inserted {len(result.inserted_ids)} foods")
else:
    print("❌ No DB connection")
