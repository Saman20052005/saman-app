# [File: backend/app/database.py]
# PATCH: Thêm user_foods_collection + hướng dẫn đổi DB_NAME qua env var
import os
import certifi
from dotenv import load_dotenv
from pymongo import MongoClient

load_dotenv()

MONGO_URI = os.getenv("MONGO_URI") or os.getenv("MONGODB_URI") or "mongodb://localhost:27017"
# ✅ PATCH: Đổi default thành "health_ai_db" nếu muốn dùng DB đó
# Hoặc set env var DB_NAME=health_ai_db trên Render (khuyến nghị)
DB_NAME = os.getenv("DB_NAME", "saman_fitness")  # → đổi thành "health_ai_db" nếu cần

safe_uri = MONGO_URI.split("@")[-1] if "@" in MONGO_URI else MONGO_URI
print(f"🔌 Connecting to MongoDB: {safe_uri}")
print(f"📂 Database Name: {DB_NAME}")

client = None
db = None

users_collection = None
foods_collection = None
nutrition_collection = None
story_logs_collection = None
workout_history_collection = None
custom_plans_collection = None
recipes_collection = None
water_collection = None
supplements_collection = None
user_foods_collection = None   # ✅ NEW: My Food per-user
exercises_collection = None    # ✅ NEW: Exercise library
conversations_collection = None # Checkpoint 3
messages_collection = None      # Checkpoint 3

try:
    if "localhost" in MONGO_URI or "127.0.0.1" in MONGO_URI:
        print("⚠️  Detected Localhost. Disabling SSL.")
        client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
    else:
        print("☁️  Detected Cloud DB. Enabling SSL.")
        client = MongoClient(MONGO_URI, tlsCAFile=certifi.where(), serverSelectionTimeoutMS=5000)

    db = client[DB_NAME]

    users_collection              = db["users"]
    foods_collection              = db["foods"]
    nutrition_collection          = db["nutrition_plans"]
    story_logs_collection         = db["story_logs"]
    workout_history_collection    = db["workout_history"]
    custom_plans_collection       = db["custom_plans"]
    recipes_collection            = db["recipes"]
    water_collection              = db["water_logs"]
    supplements_collection        = db["supplement_logs"]
    user_foods_collection         = db["user_foods"]   # ✅ NEW
    exercises_collection          = db["exercises"]     # ✅ NEW
    video_analysis_collection     = db["video_analysis"]
    conversations_collection      = db["conversations"] # Checkpoint 3
    messages_collection           = db["messages"]      # Checkpoint 3

    client.admin.command('ping')
    print("✅ Successfully connected to MongoDB!")

except Exception as e:
    print(f"❌ MongoDB Connection Error: {e}")
    print("⚠️  Continuing without database connection (some features may not work)")
    client = None
    db = None
    users_collection = None
    foods_collection = None
    nutrition_collection = None
    story_logs_collection = None
    workout_history_collection = None
    custom_plans_collection = None
    recipes_collection = None
    water_collection = None
    supplements_collection = None
    user_foods_collection = None
    exercises_collection = None
    video_analysis_collection = None
    conversations_collection = None
    messages_collection = None


async def init_database_indexes():
    """Optional database index initialization hook for startup."""
    pass


def check_water_logs_duplicates(col=None) -> list:
    """Read-only check for duplicate (user_email, date) pairs in water_logs.

    Returns a list of duplicate groups without exposing private health data.
    """
    target = col if col is not None else water_collection
    if target is None:
        raise RuntimeError("MongoDB connection is unavailable")

    pipeline = [
        {"$group": {"_id": {"user_email": "$user_email", "date": "$date"}, "count": {"$sum": 1}}},
        {"$match": {"count": {"$gt": 1}}},
    ]
    return list(target.aggregate(pipeline))


def ensure_water_logs_unique_index(col=None) -> str:
    """Controlled migration to create unique compound index on water_logs (user_email, date).

    Does NOT run automatically at startup.
    Refuses to create index if duplicates exist without manual resolution.
    Does NOT silently delete, merge, or alter existing records.
    """
    target = col if col is not None else water_collection
    if target is None:
        raise RuntimeError("MongoDB connection is unavailable")

    dups = check_water_logs_duplicates(target)
    if dups:
        total_dup_records = sum(d.get("count", 0) for d in dups)
        raise RuntimeError(
            f"Cannot create unique index: found {len(dups)} duplicate group(s) "
            f"with {total_dup_records} records. Manual resolution required."
        )

    return target.create_index(
        [("user_email", 1), ("date", 1)],
        unique=True,
        name="uniq_water_user_email_date",
    )
