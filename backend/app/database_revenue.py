"""
Module: backend.app.database_revenue

Revenue database collections and index specifications.
Designed for safe, idempotent migration.

SAFETY INVARIANTS:
1. NEVER executes automatically at startup or upon module import.
2. Checks for duplicates before creating unique indexes.
3. Does NOT alter, delete, or merge existing records.
4. Fully compatible with mock/test MongoDB collections.
5. Index identity is scoped to prevent cross-tenant and cross-provider collisions:
   - Subscription lineage is scoped by (provider, environment, original_transaction_id).
   - Usage operation idempotency is scoped by (user_id, benefit_id, idempotency_key).
   - Cache results are scoped by (user_id, client_request_id).
"""

from typing import Any, Dict, List, Optional, Tuple
import logging

logger = logging.getLogger(__name__)

# Collection Names
COLL_SUBSCRIPTIONS = "revenue_subscriptions"
COLL_ENTITLEMENT_GRANTS = "revenue_entitlement_grants"
COLL_USAGE_BUCKETS = "revenue_usage_buckets"
COLL_USAGE_OPERATIONS = "revenue_usage_operations"
COLL_PROVIDER_EVENTS = "revenue_provider_events"
COLL_FOOD_ANALYSIS_IDEMPOTENCY = "food_analysis_idempotency_cache"
COLL_PAYMENT_TRANSACTIONS = "revenue_payment_transactions"
COLL_RECONCILIATION_PLANS = "revenue_reconciliation_plans"
COLL_RECONCILIATION_AUDIT = "revenue_reconciliation_audit"
COLL_MANUAL_GRANT_AUDIT = "revenue_manual_grant_audit"
COLL_PROVIDER_CUSTOMERS = "revenue_provider_customers"


# Declarative Index Specifications
# Format: (collection_name, index_keys, options)
REVENUE_INDEX_SPECIFICATIONS: List[Tuple[str, List[Tuple[str, int]], Dict[str, Any]]] = [
    # 1. revenue_subscriptions
    (
        COLL_SUBSCRIPTIONS,
        [("user_id", 1), ("status", 1)],
        {"name": "idx_sub_user_status"},
    ),
    (
        COLL_SUBSCRIPTIONS,
        [("provider", 1), ("environment", 1), ("original_transaction_id", 1)],
        {
            "name": "uniq_sub_provider_env_orig_txn_id",
            "unique": True,
            "partialFilterExpression": {
                "original_transaction_id": {"$exists": True, "$type": "string"},
            },
        },
    ),
    # 2. revenue_entitlement_grants
    (
        COLL_ENTITLEMENT_GRANTS,
        [("user_id", 1), ("feature", 1), ("is_active", 1)],
        {"name": "idx_grant_user_feature_active"},
    ),
    (
        COLL_ENTITLEMENT_GRANTS,
        [("expires_at", 1)],
        {"name": "idx_grant_expires_at", "sparse": True},
    ),
    # 3. revenue_usage_buckets
    (
        COLL_USAGE_BUCKETS,
        [("user_id", 1), ("bucket_key", 1), ("window_start", 1)],
        {"name": "uniq_bucket_user_key_window", "unique": True},
    ),
    # 4. revenue_usage_operations
    (
        COLL_USAGE_OPERATIONS,
        [("user_id", 1), ("benefit_id", 1), ("idempotency_key", 1)],
        {"name": "uniq_op_user_benefit_idempotency_key", "unique": True},
    ),
    (
        COLL_USAGE_OPERATIONS,
        [("user_id", 1), ("created_at", -1)],
        {"name": "idx_op_user_created_at"},
    ),
    # 5. revenue_provider_events
    (
        COLL_PROVIDER_EVENTS,
        [("provider", 1), ("event_id", 1)],
        {"name": "uniq_provider_event", "unique": True},
    ),
    # 6. food_analysis_idempotency_cache
    (
        COLL_FOOD_ANALYSIS_IDEMPOTENCY,
        [("user_id", 1), ("client_request_id", 1)],
        {"name": "uniq_fa_user_client_req_id", "unique": True},
    ),
    (
        COLL_FOOD_ANALYSIS_IDEMPOTENCY,
        [("expires_at", 1)],
        {"name": "ttl_fa_expires_at", "expireAfterSeconds": 0},
    ),
]

# Payment Transaction Index Specifications (CP-07)
PAYMENT_TRANSACTION_INDEX_SPECIFICATIONS: List[Tuple[str, List[Tuple[str, int]], Dict[str, Any]]] = [
    (
        COLL_PAYMENT_TRANSACTIONS,
        [("provider", 1), ("environment", 1), ("transaction_id", 1)],
        {"name": "uniq_payment_provider_env_txn_id", "unique": True},
    ),
    (
        COLL_PAYMENT_TRANSACTIONS,
        [("user_id", 1), ("purchase_date", -1)],
        {"name": "idx_payment_user_time"},
    ),
    (
        COLL_ENTITLEMENT_GRANTS,
        [("grant_id", 1)],
        {"name": "uniq_grant_id", "unique": True},
    ),
]

# Reconciliation & Manual Grant Audit Index Specifications (CP-10)
RECONCILIATION_INDEX_SPECIFICATIONS: List[Tuple[str, List[Tuple[str, int]], Dict[str, Any]]] = [
    # 1. revenue_reconciliation_plans
    (
        COLL_RECONCILIATION_PLANS,
        [("plan_id", 1)],
        {"name": "uniq_reconciliation_plan_id", "unique": True},
    ),
    (
        COLL_RECONCILIATION_PLANS,
        [("created_at", -1)],
        {"name": "idx_reconciliation_plan_created_at"},
    ),
    # 2. revenue_reconciliation_audit
    (
        COLL_RECONCILIATION_AUDIT,
        [("plan_id", 1), ("finding_id", 1)],
        {"name": "uniq_rec_audit_plan_finding", "unique": True},
    ),
    (
        COLL_RECONCILIATION_AUDIT,
        [("executed_at", -1)],
        {"name": "idx_rec_audit_executed_at"},
    ),
    # 3. revenue_manual_grant_audit
    (
        COLL_MANUAL_GRANT_AUDIT,
        [("idempotency_key", 1)],
        {"name": "uniq_manual_grant_idempotency_key", "unique": True},
    ),
    (
        COLL_MANUAL_GRANT_AUDIT,
        [("target_user_id", 1), ("created_at", -1)],
        {"name": "idx_manual_grant_user_created_at"},
    ),
    (
        COLL_MANUAL_GRANT_AUDIT,
        [("actor", 1), ("created_at", -1)],
        {"name": "idx_manual_grant_actor_created_at"},
    ),
]

# Provider Customer Mapping Index Specifications (REVENUE-R02A)
PROVIDER_CUSTOMER_INDEX_SPECIFICATIONS: List[Tuple[str, List[Tuple[str, int]], Dict[str, Any]]] = [
    (
        COLL_PROVIDER_CUSTOMERS,
        [("provider", 1), ("project_id", 1), ("account_id", 1)],
        {"name": "uniq_prov_cust_provider_proj_account", "unique": True},
    ),
    (
        COLL_PROVIDER_CUSTOMERS,
        [("provider", 1), ("project_id", 1), ("app_user_id", 1)],
        {"name": "uniq_prov_cust_provider_proj_app_user", "unique": True},
    ),
    (
        COLL_PROVIDER_CUSTOMERS,
        [("account_id", 1)],
        {"name": "idx_prov_cust_account_id"},
    ),
]



def check_collection_duplicates(
    collection: Any,
    keys: List[Tuple[str, int]],
    sparse: bool = False,
    partial_filter: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    """
    Read-only check for duplicate key values in a MongoDB collection.
    Returns list of duplicate groups if found, empty list otherwise.
    Safe: Does NOT mutate any data.
    Applies exact partialFilterExpression / sparse filter matching index semantics.
    """
    if collection is None:
        raise ValueError("Collection instance must be provided.")

    # Build group _id specification
    group_id = {key: f"${key}" for key, _ in keys}
    match_stage: Dict[str, Any] = {}

    if partial_filter:
        match_stage = dict(partial_filter)
    elif sparse:
        or_conditions = [{key: {"$exists": True, "$ne": None}} for key, _ in keys]
        if or_conditions:
            match_stage["$or"] = or_conditions

    pipeline: List[Dict[str, Any]] = []
    if match_stage:
        pipeline.append({"$match": match_stage})

    pipeline.extend([
        {"$group": {"_id": group_id, "count": {"$sum": 1}}},
        {"$match": {"count": {"$gt": 1}}},
    ])

    try:
        return list(collection.aggregate(pipeline))
    except Exception as exc:
        logger.warning("Duplicate check via aggregate failed or unsupported: %s", exc)
        return []


def ensure_revenue_indexes(
    db: Any = None,
    dry_run: bool = False,
    check_duplicates_in_dry_run: bool = False,
    specifications: Optional[List[Tuple[str, List[Tuple[str, int]], Dict[str, Any]]]] = None,
) -> Dict[str, List[str]]:
    """
    Idempotent index creation helper for Revenue collections.
    
    Args:
        db: MongoDB database instance. If None, attempts to resolve from backend.app.database.db.
        dry_run: If True, does not execute create_index on MongoDB.
        check_duplicates_in_dry_run: If True during dry_run, reads the collection to audit
            existing duplicates without modifying anything.
        specifications: Optional custom list of index specifications to ensure. Defaults to REVENUE_INDEX_SPECIFICATIONS.
        
    Returns:
        Dict mapping collection names to list of created/verified index names.
        
    Raises:
        RuntimeError: If database is unavailable or duplicate keys are detected for a unique index.
    """
    if db is None:
        try:
            from backend.app.database import db as active_db
            db = active_db
        except ImportError:
            pass

    if db is None:
        raise RuntimeError("Database instance is unavailable. Cannot ensure revenue indexes.")

    results: Dict[str, List[str]] = {}
    specs = specifications if specifications is not None else REVENUE_INDEX_SPECIFICATIONS

    for coll_name, keys, options in specs:
        collection = db[coll_name]
        is_unique = options.get("unique", False)
        is_sparse = options.get("sparse", False)
        partial_filter = options.get("partialFilterExpression")
        idx_name = options.get("name", "")

        # Step 1: Pre-validation of uniqueness
        should_check_dups = is_unique and (not dry_run or check_duplicates_in_dry_run)
        if should_check_dups:
            duplicates = check_collection_duplicates(
                collection,
                keys,
                sparse=is_sparse,
                partial_filter=partial_filter,
            )
            if duplicates:
                total_dups = sum(d.get("count", 0) for d in duplicates)
                err_msg = (
                    f"Refusing to create unique index '{idx_name}' on collection '{coll_name}'. "
                    f"Found {len(duplicates)} duplicate group(s) with {total_dups} total conflicting records. "
                    "Manual conflict resolution is required before index creation."
                )
                if not dry_run:
                    raise RuntimeError(err_msg)
                else:
                    logger.warning("[DRY-RUN AUDIT ALERT] %s", err_msg)

        # Step 2: Index Creation / Verification
        if dry_run:
            mode_label = "audit-mode (DB read)" if check_duplicates_in_dry_run else "spec-only (no DB read)"
            logger.info(
                "[DRY-RUN: %s] Would ensure index '%s' on '%s': %s (%s)",
                mode_label, idx_name, coll_name, keys, options
            )
            created_name = idx_name or "dry_run_index"
        else:
            try:
                created_name = collection.create_index(keys, **options)
                logger.info("Ensured index '%s' on collection '%s'", created_name, coll_name)
            except Exception as exc:
                logger.error("Failed to create index '%s' on '%s': %s", idx_name, coll_name, exc)
                raise

        results.setdefault(coll_name, []).append(created_name)

    return results
