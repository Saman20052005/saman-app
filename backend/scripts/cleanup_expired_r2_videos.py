"""CLI script to clean up expired workout video stories from Cloudflare R2 / S3.

Usage:
    python -m backend.scripts.cleanup_expired_r2_videos [--dry-run] [--limit 200]
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from typing import Optional, Sequence

# Allow execution both as `python -m backend.scripts.cleanup_expired_r2_videos`
# and directly as `python backend/scripts/cleanup_expired_r2_videos.py`.
_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

import backend.app.database as _db_mod
from backend.app.services.r2_retention_service import cleanup_expired_r2_videos

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("cleanup_expired_r2_videos")


def _positive_int(value: str) -> int:
    parsed = int(value)
    if parsed < 1:
        raise argparse.ArgumentTypeError("--limit must be a positive integer")
    return parsed


def _resolve_video_stories_collection():
    col = getattr(_db_mod, "workout_video_stories_collection", None)
    if col is not None:
        return col
    db_target = _db_mod.get_db() if hasattr(_db_mod, "get_db") else getattr(_db_mod, "db", None)
    if db_target is not None:
        return db_target["workout_video_stories"]
    return None


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Clean up expired workout video stories from object storage and mark them deleted."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Scan and count eligible expired videos without deleting objects or updating MongoDB.",
    )
    parser.add_argument(
        "--limit",
        type=_positive_int,
        default=200,
        help="Maximum number of expired video story records to process in this run (default: 200).",
    )
    args = parser.parse_args(argv)

    col = _resolve_video_stories_collection()
    if col is None:
        logger.error("MongoDB workout_video_stories collection is unavailable. Aborting.")
        return 1

    try:
        summary = cleanup_expired_r2_videos(
            col,
            dry_run=args.dry_run,
            batch_limit=args.limit,
        )
    except Exception as exc:
        logger.error("R2 retention cleanup failed: %s", exc)
        return 1

    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
