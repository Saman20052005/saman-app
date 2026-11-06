"""
Administrative Tool & CLI for Saman Shop Catalog.
Subsystem: Saman Shop — Boutique Catalog & Curation (CP-SHOP-07).

Usage:
    python -m backend.scripts.shop_admin seed [--force]
    python -m backend.scripts.shop_admin ensure-indexes [--dry-run]
    python -m backend.scripts.shop_admin list [--include-hidden]
    python -m backend.scripts.shop_admin hide <product_id>
    python -m backend.scripts.shop_admin publish <product_id>
    python -m backend.scripts.shop_admin add --json <json_string_or_filepath>
    python -m backend.scripts.shop_admin update <product_id> --json <json_string_or_filepath>

SAFETY INVARIANTS:
1. Validates all product inputs with Pydantic ShopProductAdminInput before write.
2. Prevents empty or fake URLs from being published without vetting.
3. Decouples publishState from availability (hiding an item preserves its record and wishlist references).
4. Idempotent seed protects existing modifications unless --force is specified.
"""

import argparse
import json
import os
from pathlib import Path
import re
import sys
from typing import Any, Dict

from pymongo import MongoClient

from backend.app.models.shop import (
    PublishState,
    ShopProductAdminInput,
)
from backend.app.services.shop_service import (
    ShopNotFoundException,
    ShopService,
)
from backend.app.shop_database import ensure_shop_indexes


def mask_uri(uri: str) -> str:
    """Masks credentials in MongoDB URI for safe logging without leaking secrets."""
    return re.sub(r"://([^:]+):([^@]+)@", r"://\1:***@", uri)


def get_target_db(args):
    """
    SAFETY INVARIANT:
    Strictly requires explicit target DB URI and name (via CLI args or env vars).
    Never silently falls back to active default 'saman_fitness' on port 27017.
    """
    db_uri = args.db_uri or os.getenv("SHOP_DB_URI")
    db_name = args.db_name or os.getenv("SHOP_DB_NAME")

    if not db_uri or not db_name:
        sys.stderr.write(
            "Lỗi bảo mật (Safety Guard): Bạn phải cung cấp rõ ràng --db-uri và --db-name "
            "(hoặc qua biến môi trường SHOP_DB_URI, SHOP_DB_NAME). "
            "Tuyệt đối không fallback ngầm về DB mặc định.\n"
        )
        sys.exit(1)

    # Prevent accidental modification of active production database on default port 27017
    if db_name == "saman_fitness" and (":27017" in db_uri or (("localhost" in db_uri or "127.0.0.1" in db_uri) and "27017" in db_uri)):
        sys.stderr.write(
            "Lỗi bảo mật (Safety Guard): Không được phép thao tác trực tiếp trên DB "
            "'saman_fitness' cổng 27017 của active workspace. Vui lòng chỉ định DB test riêng biệt.\n"
        )
        sys.exit(1)

    print(f"[Shop Admin] Target Database: {mask_uri(db_uri)} / {db_name}")
    try:
        client = MongoClient(db_uri, serverSelectionTimeoutMS=5000)
        # Ping database to confirm connectivity
        client.admin.command('ping')
        return client[db_name]
    except Exception as e:
        sys.stderr.write(f"Lỗi kết nối MongoDB ({mask_uri(db_uri)}): {e}\n")
        sys.exit(1)


def get_service(args) -> ShopService:
    db = get_target_db(args)
    return ShopService(db_instance=db)


def cmd_seed(args):
    service = get_service(args)
    res = service.seed_default_catalog(force_overwrite=args.force)
    print(f"Seed complete: {res['categories']} categories, {res['collections']} collections, {res['products']} products.")


def cmd_ensure_indexes(args):
    db = get_target_db(args)
    audit = ensure_shop_indexes(db, dry_run=args.dry_run)
    print(f"Index operations: {len(audit)}")
    for item in audit:
        status = "DRY-RUN" if args.dry_run else ("OK" if item.get("applied") else f"FAILED: {item.get('error')}")
        print(f" - {item['collection']}: {item['keys']} -> {status}")


def cmd_migrate_taxonomy(args):
    db = get_target_db(args)
    from backend.app.services.shop_service import migrate_catalog_taxonomy
    report = migrate_catalog_taxonomy(db, dry_run=args.dry_run)
    print(f"Taxonomy Migration {'[DRY-RUN]' if report['dryRun'] else '[APPLIED]'}:")
    print(f" - Total evaluated: {report['totalEvaluated']}")
    print(f" - Products requiring update: {report['productsToUpdateCount']}")
    if report['productsToUpdateIds']:
        sample_ids = ', '.join(report['productsToUpdateIds'][:10])
        more = '...' if len(report['productsToUpdateIds']) > 10 else ''
        print(f"   IDs: {sample_ids}{more}")
    print(f" - Products untouched: {report['productsUntouchedCount']}")
    print(f" - Retired hidden IDs: {', '.join(report['retiredHiddenIds'])}")


def cmd_list(args):
    service = get_service(args)
    products = service.list_admin_products(include_hidden=args.include_hidden)
    print(f"Total products: {len(products)}")
    for p in products:
        price_str = f"{p.get('priceVnd'):,} VND" if p.get("priceVnd") else "Chưa có giá"
        print(
            f"[{p.get('publishState', 'unknown').upper():9}] "
            f"ID: {p.get('id'):12} | "
            f"Order: {p.get('curatedOrder', 0):2} | "
            f"Avail: {p.get('availability', 'unknown'):12} | "
            f"Price: {price_str:15} | "
            f"Title: {p.get('title')}"
        )


def cmd_hide(args):
    service = get_service(args)
    try:
        res = service.set_product_publish_state(args.product_id, PublishState.hidden)
        print(f"Product '{args.product_id}' hidden successfully (State: {res['previousState']} -> {res['newState']}).")
    except ShopNotFoundException:
        print(f"Error: Product '{args.product_id}' not found.")
        sys.exit(1)


def cmd_publish(args):
    service = get_service(args)
    try:
        res = service.set_product_publish_state(args.product_id, PublishState.published)
        print(f"Product '{args.product_id}' published successfully (State: {res['previousState']} -> {res['newState']}).")
    except ShopNotFoundException:
        print(f"Error: Product '{args.product_id}' not found.")
        sys.exit(1)


def cmd_add_or_update(args, is_update: bool = False):
    raw_json = args.json
    if Path(raw_json).exists():
        payload = json.loads(Path(raw_json).read_text(encoding="utf-8"))
    else:
        payload = json.loads(raw_json)

    if is_update:
        payload["id"] = args.product_id

    try:
        validated = ShopProductAdminInput(**payload)
    except Exception as e:
        print(f"Validation error: {e}")
        sys.exit(1)

    service = get_service(args)
    res = service.create_or_update_product(validated)
    print(f"Product '{res['id']}' successfully {res['action']} with state '{res['publishState']}'.")


def main():
    parser = argparse.ArgumentParser(description="Saman Shop Catalog Administrative CLI")
    parser.add_argument("--db-uri", default=os.getenv("SHOP_DB_URI"), help="Target MongoDB connection URI (required, no default fallback)")
    parser.add_argument("--db-name", default=os.getenv("SHOP_DB_NAME"), help="Target MongoDB database name (required, no default fallback)")

    subparsers = parser.add_subparsers(dest="command", required=True)

    # Seed
    p_seed = subparsers.add_parser("seed", help="Idempotently seed categories, collections, and default products")
    p_seed.add_argument("--force", action="store_true", help="Force overwrite existing documents with defaults")
    p_seed.set_defaults(func=cmd_seed)

    # Ensure indexes
    p_idx = subparsers.add_parser("ensure-indexes", help="Ensure declarative indexes on shop collections")
    p_idx.add_argument("--dry-run", action="store_true", help="Print operations without executing")
    p_idx.set_defaults(func=cmd_ensure_indexes)

    # Migrate taxonomy
    p_mig = subparsers.add_parser("migrate-taxonomy", help="Controlled schema & taxonomy migration for Shop")
    p_mig.add_argument("--dry-run", action="store_true", default=False, help="Preview migration without modifying data")
    p_mig.set_defaults(func=cmd_migrate_taxonomy)

    # List
    p_list = subparsers.add_parser("list", help="List catalog products with administrative status")
    p_list.add_argument("--include-hidden", action="store_true", default=True, help="Include hidden/draft items")
    p_list.set_defaults(func=cmd_list)

    # Hide
    p_hide = subparsers.add_parser("hide", help="Hide a product from public catalog")
    p_hide.add_argument("product_id", help="Product ID to hide")
    p_hide.set_defaults(func=cmd_hide)

    # Publish
    p_pub = subparsers.add_parser("publish", help="Publish a previously hidden product")
    p_pub.add_argument("product_id", help="Product ID to publish")
    p_pub.set_defaults(func=cmd_publish)

    # Add
    p_add = subparsers.add_parser("add", help="Add a new product")
    p_add.add_argument("--json", required=True, help="JSON string or file path containing product payload")
    p_add.set_defaults(func=lambda args: cmd_add_or_update(args, is_update=False))

    # Update
    p_upd = subparsers.add_parser("update", help="Update an existing product")
    p_upd.add_argument("product_id", help="Product ID to update")
    p_upd.add_argument("--json", required=True, help="JSON string or file path containing update payload")
    p_upd.set_defaults(func=lambda args: cmd_add_or_update(args, is_update=True))

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

