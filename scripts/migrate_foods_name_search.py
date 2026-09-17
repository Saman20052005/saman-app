"""
Script: backend/scripts/migrate_foods_name_search.py

Thêm field name_search (không dấu) vào 204 foods hiện có trong collection foods.
Chạy 1 lần trước khi deploy patch food search.

Usage:
    cd <repo root>
    python -m backend.scripts.migrate_foods_name_search
"""

import unicodedata
import sys
import os

# Cho phép import từ root project
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.app.database import foods_collection, user_foods_collection


def normalize(text: str) -> str:
    return (
        unicodedata.normalize("NFD", text)
        .encode("ascii", "ignore")
        .decode("utf-8")
        .lower()
        .strip()
    )


def migrate_foods():
    if foods_collection is None:
        print("❌ foods_collection is None — check database connection")
        return

    total    = foods_collection.count_documents({})
    updated  = 0
    skipped  = 0

    print(f"📦 Total foods: {total}")

    for food in foods_collection.find({}):
        if "name_search" in food and food["name_search"]:
            skipped += 1
            continue

        name = food.get("name", "")
        foods_collection.update_one(
            {"_id": food["_id"]},
            {"$set": {"name_search": normalize(name)}},
        )
        updated += 1

    print(f"✅ Updated: {updated} foods")
    print(f"⏭️  Skipped (already has name_search): {skipped}")


def verify():
    """Kiểm tra 5 documents đầu tiên sau migrate."""
    if foods_collection is None:
        return
    print("\n🔍 Sample after migration:")
    for food in foods_collection.find({}, {"name": 1, "name_search": 1, "_id": 0}).limit(5):
        print(f"  {food.get('name')} → {food.get('name_search')}")


if __name__ == "__main__":
    migrate_foods()
    verify()
    print("\n✅ Migration done. You can now search 'pho' and find 'Phở bò'.")

