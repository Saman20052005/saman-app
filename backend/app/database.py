# [File: backend/app/database.py]
# PATCH: Thêm user_foods_collection + hướng dẫn đổi DB_NAME qua env var
import os
import certifi
from dotenv import load_dotenv
from pymongo import MongoClient

load_dotenv()


def _safe_print(msg: str) -> None:
    try:
        print(msg)
    except Exception:
        try:
            print(msg.encode("ascii", errors="replace").decode("ascii"))
        except Exception:
            pass


MONGO_URI = os.getenv("MONGO_URI") or os.getenv("MONGODB_URI") or "mongodb://localhost:27017"
# ✅ PATCH: Đổi default thành "health_ai_db" nếu muốn dùng DB đó
# Hoặc set env var DB_NAME=health_ai_db trên Render (khuyến nghị)
DB_NAME = os.getenv("DB_NAME", "saman_fitness")  # → đổi thành "health_ai_db" nếu cần

safe_uri = MONGO_URI.split("@")[-1] if "@" in MONGO_URI else MONGO_URI
_safe_print(f"🔌 Connecting to MongoDB: {safe_uri}")
_safe_print(f"📂 Database Name: {DB_NAME}")

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
weight_history_collection = None
journeys_collection = None
community_posts_collection = None
community_interactions_collection = None
community_follows_collection = None
shop_products_collection = None
journal_articles_collection = None
chat_training_logs_collection = None
food_barcodes_collection = None


def _bind_collections(database):
    global users_collection, foods_collection, nutrition_collection, story_logs_collection
    global workout_history_collection, custom_plans_collection, recipes_collection
    global water_collection, supplements_collection, user_foods_collection
    global exercises_collection, conversations_collection, messages_collection
    global weight_history_collection
    global journeys_collection, community_posts_collection, community_interactions_collection, community_follows_collection
    global shop_products_collection, journal_articles_collection, chat_training_logs_collection
    global food_barcodes_collection

    users_collection              = database["users"]
    foods_collection              = database["foods"]
    nutrition_collection          = database["nutrition_plans"]
    story_logs_collection         = database["story_logs"]
    workout_history_collection    = database["workout_history"]
    custom_plans_collection       = database["custom_plans"]
    recipes_collection            = database["recipes"]
    water_collection              = database["water_logs"]
    supplements_collection        = database["supplement_logs"]
    user_foods_collection         = database["user_foods"]   # ✅ NEW
    exercises_collection          = database["exercises"]     # ✅ NEW
    conversations_collection      = database["conversations"] # Checkpoint 3
    messages_collection           = database["messages"]      # Checkpoint 3
    weight_history_collection     = database["weight_history"]
    journeys_collection           = database["journeys"]
    community_posts_collection    = database["community_posts"]
    community_interactions_collection = database["community_interactions"]
    community_follows_collection  = database["community_follows"]
    shop_products_collection      = database["shop_products"]
    journal_articles_collection   = database["journal_articles"]
    chat_training_logs_collection = database["chat_training_logs"]
    food_barcodes_collection      = database["food_barcodes"]


def connect_db():
    """Establish or recover MongoDB connection lazily if initial connection failed or dropped."""
    global client, db
    global users_collection, foods_collection, nutrition_collection, story_logs_collection
    global workout_history_collection, custom_plans_collection, recipes_collection
    global water_collection, supplements_collection, user_foods_collection
    global exercises_collection, conversations_collection, messages_collection
    global weight_history_collection
    global journeys_collection, community_posts_collection, community_interactions_collection, community_follows_collection
    global shop_products_collection, journal_articles_collection, chat_training_logs_collection
    global food_barcodes_collection

    if db is not None and users_collection is not None:
        return db

    if db is not None and users_collection is None:
        _bind_collections(db)
        return db

    try:
        if "localhost" in MONGO_URI or "127.0.0.1" in MONGO_URI:
            _safe_print("⚠️  Detected Localhost. Disabling SSL.")
            client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
        else:
            _safe_print("☁️  Detected Cloud DB. Enabling SSL.")
            client = MongoClient(MONGO_URI, tlsCAFile=certifi.where(), serverSelectionTimeoutMS=5000)

        db = client[DB_NAME]
        _bind_collections(db)

        client.admin.command('ping')
        _safe_print("✅ Successfully connected to MongoDB!")
        return db

    except Exception as e:
        _safe_print(f"❌ MongoDB Connection Error: {e}")
        _safe_print("⚠️  Continuing without database connection (some features may not work)")
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
        conversations_collection = None
        messages_collection = None
        weight_history_collection = None
        journeys_collection = None
        community_posts_collection = None
        community_interactions_collection = None
        community_follows_collection = None
        shop_products_collection = None
        journal_articles_collection = None
        chat_training_logs_collection = None
        food_barcodes_collection = None
        return None


def get_db():
    """Return active database instance, attempting lazy reconnect if None."""
    if db is None:
        return connect_db()
    return db


def get_users_collection():
    """Return users_collection, attempting lazy reconnect if None."""
    if users_collection is None:
        connect_db()
    return users_collection


connect_db()


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
