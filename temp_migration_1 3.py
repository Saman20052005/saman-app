import os, certifi
from pymongo import MongoClient
uri = os.environ["MONGO_URI"]
client = MongoClient(uri, tlsCAFile=certifi.where())
src = client["saman_fitness"]
dst = client["health_ai_db"]
# Migrate nutrition_plans
plans = list(src["nutrition_plans"].find({}))
if plans:
    for p in plans:
        exists = dst["nutrition_plans"].find_one({
            "user_email": p.get("user_email"),
            "date": p.get("date"),
            "meal_type": p.get("meal_type"),
        })
        if not exists:
            dst["nutrition_plans"].insert_one(p)
    print(f"✅ nutrition_plans migrated: {len(plans)} docs")
else:
    print("⏭️  No nutrition_plans to migrate")
# Migrate story_logs
stories = list(src["story_logs"].find({}))
if stories:
    for s in stories:
        exists = dst["story_logs"].find_one({
            "user_email": s.get("user_email"),
            "logged_at": s.get("logged_at"),
        })
        if not exists:
            dst["story_logs"].insert_one(s)
    print(f"✅ story_logs migrated: {len(stories)} docs")
else:
    print("⏭️  No story_logs to migrate")
# Verify
print("
📊 health_ai_db after migration:")
for col in ["users", "foods", "nutrition_plans", "story_logs"]:
    print(f"  {col}: {dst[col].count_documents({})} docs")