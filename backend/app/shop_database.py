"""
Module: backend.app.shop_database
Subsystem: Saman Shop — Boutique Catalog & Curation (CP-SHOP-07).

MongoDB collections and declarative index specifications for Shop catalog.
SAFETY INVARIANTS:
1. NEVER executes migrations or destructive modifications upon module import.
2. Index identity is scoped to shop catalog collections.
3. Fully compatible with mock/test MongoDB collections.
4. Does NOT modify collections belonging to other features.
"""

from typing import Any, Dict, List, Optional, Tuple
import logging

logger = logging.getLogger(__name__)

COLL_SHOP_PRODUCTS = "shop_products"
COLL_SHOP_CATEGORIES = "shop_categories"
COLL_SHOP_COLLECTIONS = "shop_collections"

SHOP_INDEX_SPECIFICATIONS: List[Tuple[str, List[Tuple[str, int]], Dict[str, Any]]] = [
    # shop_products
    (
        COLL_SHOP_PRODUCTS,
        [("id", 1)],
        {"name": "uniq_shop_product_id", "unique": True},
    ),
    (
        COLL_SHOP_PRODUCTS,
        [("publishState", 1), ("curatedOrder", 1), ("id", 1)],
        {"name": "idx_shop_product_published_order"},
    ),
    (
        COLL_SHOP_PRODUCTS,
        [("publishState", 1), ("categoryId", 1), ("curatedOrder", 1), ("id", 1)],
        {"name": "idx_shop_product_cat_order"},
    ),
    (
        COLL_SHOP_PRODUCTS,
        [("publishState", 1), ("categoryId", 1), ("subcategoryId", 1), ("curatedOrder", 1), ("id", 1)],
        {"name": "idx_shop_product_cat_sub_order"},
    ),
    (
        COLL_SHOP_PRODUCTS,
        [("publishState", 1), ("collectionIds", 1), ("curatedOrder", 1), ("id", 1)],
        {"name": "idx_shop_product_col_order"},
    ),
    # shop_categories
    (
        COLL_SHOP_CATEGORIES,
        [("id", 1)],
        {"name": "uniq_shop_cat_id", "unique": True},
    ),
    (
        COLL_SHOP_CATEGORIES,
        [("sortOrder", 1), ("id", 1)],
        {"name": "idx_shop_cat_sort"},
    ),
    # shop_collections
    (
        COLL_SHOP_COLLECTIONS,
        [("id", 1)],
        {"name": "uniq_shop_col_id", "unique": True},
    ),
    (
        COLL_SHOP_COLLECTIONS,
        [("sortOrder", 1), ("id", 1)],
        {"name": "idx_shop_col_sort"},
    ),
]


def ensure_shop_indexes(db_instance, dry_run: bool = False) -> List[Dict[str, Any]]:
    """
    Safely creates declarative shop indexes.
    Returns audit summary list.
    """
    audit = []
    if db_instance is None:
        logger.warning("[Shop DB] No database instance provided for ensure_shop_indexes.")
        return audit

    for coll_name, keys, options in SHOP_INDEX_SPECIFICATIONS:
        spec_summary = {
            "collection": coll_name,
            "keys": keys,
            "options": options,
            "applied": False,
        }
        if dry_run:
            logger.info("[Shop DB Dry-Run] Would ensure index on '%s': %s (%s)", coll_name, keys, options)
        else:
            try:
                coll = db_instance[coll_name]
                idx_name = coll.create_index(keys, **options)
                spec_summary["applied"] = True
                spec_summary["name"] = idx_name
                logger.info("[Shop DB] Created/verified index '%s' on '%s'", idx_name, coll_name)
            except Exception as e:
                spec_summary["error"] = str(e)
                logger.error("[Shop DB] Failed creating index on '%s': %s", coll_name, e)
        audit.append(spec_summary)
    return audit

