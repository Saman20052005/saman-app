"""
Script: backend/scripts/import_vietnam_foods.py

An toàn nạp/đồng bộ 204 món Việt từ VIETNAM_STANDARD_FOODS vào database runtime.
- Dùng upsert theo tên món chuẩn hóa
- Luôn tính name_search bằng chuẩn hóa đ/Đ -> d và bỏ dấu
- Không xóa data cũ (không dùng delete_many)
- Không đè user_foods
"""

import os
import sys
import unicodedata
from pymongo import MongoClient, UpdateOne

# Cho phép import từ root project
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.app.data.seeds import VIETNAM_STANDARD_FOODS


def normalize_text(text: str) -> str:
    """Chuẩn hóa tiếng Việt: đ/Đ -> d, bỏ dấu, lower, strip."""
    text = text.replace("đ", "d").replace("Đ", "d")
    return (
        unicodedata.normalize("NFD", text)
        .encode("ascii", "ignore")
        .decode("utf-8")
        .lower()
        .strip()
    )


def import_foods(mongo_uri: str = None, db_name: str = None):
    uri = mongo_uri or os.getenv("MONGO_URI") or os.getenv("MONGODB_URI") or "mongodb://127.0.0.1:27028"
    database_name = db_name or os.getenv("DB_NAME") or "saman_cp26_localtest"

    client = MongoClient(uri)
    db = client[database_name]
    foods_col = db["foods"]

    print(f"Connecting to MongoDB: {uri} (DB: {database_name})")
    print(f"Total foods in seed list: {len(VIETNAM_STANDARD_FOODS)}")

    operations = []
    for food in VIETNAM_STANDARD_FOODS:
        name = food["name"]
        name_search = normalize_text(name)
        doc = dict(food)
        doc["name_search"] = name_search

        operations.append(
            UpdateOne(
                {"name": name},
                {"$set": doc},
                upsert=True
            )
        )

    if operations:
        result = foods_col.bulk_write(operations)
        print(f"Upsert result: matched={result.matched_count}, modified={result.modified_count}, upserted={len(result.upserted_ids)}")

    count = foods_col.count_documents({})
    print(f"Total documents in foods collection: {count}")


if __name__ == "__main__":
    import_foods()

