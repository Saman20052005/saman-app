"""
Script: backend/scripts/migrate_revenue_indexes.py

Manual migration script to create indexes for Revenue collections.
DOES NOT run automatically.

Usage:
    cd <repo root>
    python -m backend.scripts.migrate_revenue_indexes [--dry-run] [--audit]
"""

import sys
import os
import argparse
import logging

# Cho phép import từ root project
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.app.database import db
from backend.app.database_revenue import ensure_revenue_indexes, REVENUE_INDEX_SPECIFICATIONS

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("migrate_revenue_indexes")


def main():
    parser = argparse.ArgumentParser(description="Ensure indexes for Revenue collections safely.")
    parser.add_argument("--dry-run", action="store_true", help="Do not create indexes on MongoDB.")
    parser.add_argument("--audit", action="store_true", help="During dry-run, read collection to audit existing duplicates.")
    args = parser.parse_args()

    if db is None:
        logger.error("❌ MongoDB connection is unavailable. Cannot proceed.")
        sys.exit(1)

    logger.info("Starting revenue index migration (dry_run=%s, audit=%s)...", args.dry_run, args.audit)
    logger.info("Target database: %s", getattr(db, "name", "unknown"))
    logger.info("Total index specifications: %d", len(REVENUE_INDEX_SPECIFICATIONS))

    try:
        results = ensure_revenue_indexes(
            db=db,
            dry_run=args.dry_run,
            check_duplicates_in_dry_run=args.audit,
        )
        logger.info("✅ Revenue index migration operation completed successfully.")
        for coll, idxs in results.items():
            logger.info("  - %s: %s", coll, ", ".join(idxs))
    except Exception as exc:
        logger.error("❌ Migration failed: %s", exc)
        sys.exit(1)


if __name__ == "__main__":
    main()
