#!/usr/bin/env python3
"""Controlled migration script to create unique index on water_logs (user_email, date).

Usage:
    python -m backend.scripts.create_water_index
"""
import sys
from backend.app.database import (
    ensure_water_logs_unique_index,
    check_water_logs_duplicates,
    water_collection,
)


def main():
    if water_collection is None:
        print("❌ Error: MongoDB connection is unavailable. Verify MONGO_URI.", file=sys.stderr)
        sys.exit(1)

    print("🔍 Checking for existing duplicates in water_logs (user_email, date)...")
    try:
        dups = check_water_logs_duplicates(water_collection)
    except Exception as e:
        print(f"❌ Error during duplicate check: {e}", file=sys.stderr)
        sys.exit(1)

    if dups:
        total_records = sum(d.get("count", 0) for d in dups)
        print(
            f"❌ BLOCKED: Found {len(dups)} duplicate group(s) with {total_records} records.",
            file=sys.stderr,
        )
        print("⚠️ Aborting index creation. Manual deduplication required.", file=sys.stderr)
        sys.exit(2)

    print("✅ 0 duplicate groups found. Proceeding with unique index creation...")
    try:
        idx_name = ensure_water_logs_unique_index(water_collection)
        print(f"🚀 Success: Unique index '{idx_name}' created on water_logs collection!")
    except Exception as e:
        print(f"❌ Failed to create unique index: {e}", file=sys.stderr)
        sys.exit(3)


if __name__ == "__main__":
    main()
