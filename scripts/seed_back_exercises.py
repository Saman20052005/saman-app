# /backend/scripts/seed_back_exercises.py
# Chạy 1 lần để insert 10 bài lưng vào MongoDB
# Usage: python -m scripts.seed_back_exercises (từ thư mục /backend)

import sys
import os
from datetime import datetime, timezone

# Đảm bảo import được từ backend root
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import exercises_collection
from app.data.exercises.back import BACK_EXERCISES


def seed_back_exercises():
    if exercises_collection is None:
        print("❌ exercises_collection is None — kiểm tra lại database connection.")
        return

    inserted = 0
    skipped = 0
    failed = 0

    for exercise in BACK_EXERCISES:
        slug = exercise["slug"]

        # Idempotent: không insert nếu slug đã tồn tại
        existing = exercises_collection.find_one({"slug": slug})
        if existing:
            print(f"⏭️  Skipped (đã tồn tại): {slug}")
            skipped += 1
            continue

        try:
            doc = {
                **exercise,
                "createdAt": datetime.now(timezone.utc),
                "updatedAt": datetime.now(timezone.utc),
            }
            exercises_collection.insert_one(doc)
            print(f"✅ Inserted: {slug}")
            inserted += 1
        except Exception as e:
            print(f"❌ Failed: {slug} — {e}")
            failed += 1

    print(f"\n📊 Done: {inserted} inserted, {skipped} skipped, {failed} failed")


if __name__ == "__main__":
    seed_back_exercises()
