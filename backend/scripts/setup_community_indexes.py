"""
Script: backend/scripts/setup_community_indexes.py

Sets up MongoDB indexes for Saman Community subsystem:
1. `community_interactions`: unique compound index on (user_id, interaction_type, post_id).
2. `community_posts`: indexes on privacy, created_at, is_deleted.

Usage:
    python -m backend.scripts.setup_community_indexes
"""

import os
import sys
from pymongo import ASCENDING, DESCENDING

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.app.database import db


def setup_indexes():
    if db is None:
        print("[setup_community_indexes] Database connection not available.")
        return False

    print(f"[setup_community_indexes] Connected to db: {db.name}")

    # 1. Setup community_interactions unique compound index
    interactions_col = db["community_interactions"]
    index_name = "idx_user_interaction_post_unique"
    existing_indexes = interactions_col.index_information()

    if index_name not in existing_indexes:
        interactions_col.create_index(
            [
                ("user_id", ASCENDING),
                ("interaction_type", ASCENDING),
                ("post_id", ASCENDING),
            ],
            unique=True,
            name=index_name,
        )
        print(f"[setup_community_indexes] Created unique index '{index_name}' on community_interactions.")
    else:
        print(f"[setup_community_indexes] Index '{index_name}' already exists.")

    count_idx_name = "idx_post_interaction_count"
    if count_idx_name not in existing_indexes:
        interactions_col.create_index(
            [
                ("post_id", ASCENDING),
                ("interaction_type", ASCENDING),
            ],
            name=count_idx_name,
        )
        print(f"[setup_community_indexes] Created index '{count_idx_name}' on community_interactions.")

    # 2. Setup community_posts indexes for read performance
    posts_col = db["community_posts"]
    posts_col.create_index(
        [("created_at", DESCENDING), ("_id", DESCENDING)],
        name="idx_posts_created_at_desc",
    )
    posts_col.create_index(
        [("privacy", ASCENDING), ("is_deleted", ASCENDING)],
        name="idx_posts_privacy_deleted",
    )
    print("[setup_community_indexes] Created read indexes on community_posts.")

    # 3. Setup community_follows indexes
    follows_col = db["community_follows"]
    follow_unique_name = "idx_follow_unique"
    existing_follow_indexes = follows_col.index_information()
    if follow_unique_name not in existing_follow_indexes:
        follows_col.create_index(
            [
                ("follower_id", ASCENDING),
                ("following_id", ASCENDING),
            ],
            unique=True,
            name=follow_unique_name,
        )
        print(f"[setup_community_indexes] Created unique index '{follow_unique_name}' on community_follows.")
    else:
        print(f"[setup_community_indexes] Index '{follow_unique_name}' already exists.")

    follows_col.create_index(
        [("follower_id", ASCENDING), ("created_at", DESCENDING)],
        name="idx_follower_created",
    )
    follows_col.create_index(
        [("following_id", ASCENDING), ("created_at", DESCENDING)],
        name="idx_following_created",
    )
    print("[setup_community_indexes] Created query indexes on community_follows.")
    return True


if __name__ == "__main__":
    setup_indexes()

