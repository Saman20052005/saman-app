"""
FastAPI Router for Saman Revenue & Catalog Engine.
Subsystem: Saman Revenue — Membership, Billing, Entitlements & Operations (CP-03 / CP-07 / CP-08 / CP-10).

Provides public read-only access to published, versioned catalog definitions and authenticated purchase verification.
Enforces that catalog definitions are preview/demo and not commercially purchasable.

ADMIN BOUNDARY NOTE:
As per repository governance (AGENTS.md & CP-10 specification),
because no secure administrative role boundary (RBAC) currently exists in the
user database or JWT authentication tokens, HTTP mutation endpoints (POST/PUT/DELETE)
for manual grants, revocations, and reconciliation apply are STRICTLY OMITTED from
the public HTTP router. This prevents arbitrary or spoofed administrative actions via HTTP.
Operational reconciliation and audited manual grants are exclusively managed through
the controlled offline operator CLI: `backend.scripts.revenue_admin`.
"""

from datetime import datetime, timezone
import logging
import os
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, HTTPException, Query, Depends, status, Request

from backend.app.models.revenue import (
    CatalogVersion,
    CatalogStatus,
    MembershipTier,
    AccountMembershipSummary,
    BenefitUsageSummary,
    PurchaseVerificationRequest,
    PurchaseVerificationResponse,
    RestorePurchasesRequest,
    RestorePurchasesResponse,
)
from backend.app.services.catalog_engine import get_catalog_engine, CatalogNotFoundError
from backend.app.services.payment_service import (
    get_payment_settlement_service,
    get_payment_webhook_service,
    PaymentBoundaryError,
    PaymentConfigurationNotReadyError,
    ProductMappingRejectedError,
    PaymentStorageError,
    ReceiptOwnershipConflictError,
    WebhookVerificationError,
)
from backend.app.services.revenuecat_adapter import (
    resolve_or_create_account_id,
    resolve_or_create_provider_customer_id,
    LegacyR02IdentityMigrationRequiredError,
)
from backend.auth_utils import verify_token

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/revenue", tags=["Revenue & Catalog"])


@router.get(
    "/catalog",
    response_model=CatalogVersion,
    summary="Get active or versioned membership catalog",
    description="Returns public published catalog definitions, tiers, prices, and feature comparison matrix.",
)
async def get_catalog(
    version: Optional[str] = Query(
        None,
        description="Optional specific catalog version ID (e.g. 'v1.0-preview'). If omitted, returns active version."
    ),
):
    """
    Public read-only catalog endpoint.
    - Does NOT require authentication (allows pre-login and onboarding exploration).
    - Returns only PUBLISHED catalog versions (internal drafts are filtered).
    - All plans and prices carry preview_mode=True and purchasable=False.
    """
    engine = get_catalog_engine()
    if version:
        cat = engine.get_catalog_by_version(version, include_drafts=False)
        if not cat:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Published catalog version '{version}' not found.",
            )
        return cat

    active = engine.get_active_catalog(include_drafts=False)
    if not active:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No active published catalog is currently available.",
        )
    return active


@router.get(
    "/catalog/versions",
    summary="List available published catalog versions",
)
async def list_catalog_versions() -> Dict[str, Any]:
    """Returns list of public published catalog versions."""
    engine = get_catalog_engine()
    published = engine.list_published_versions()
    active = engine.get_active_catalog()
    return {
        "published_versions": published,
        "active_version": active.version_id if active else None,
    }


@router.get(
    "/operations/lookup",
    summary="Lookup operation status and cached result by idempotency key",
    description="Allows clients to recover analysis outcome if the response was lost in transit before receiving operation ID.",
)
async def lookup_operation(
    idempotency_key: str = Query(..., description="Client idempotency key"),
    benefit_id: str = Query("ai.nutrition_gemini", description="Benefit identifier"),
    email: str = Depends(verify_token),
) -> Dict[str, Any]:
    from backend.app.services.quota_service import QuotaService, StorageUnavailableException
    quota_svc = QuotaService()
    try:
        op = quota_svc.query_operation_by_idempotency_key(
            user_id=email,
            benefit_id=benefit_id,
            idempotency_key=idempotency_key,
        )
    except StorageUnavailableException as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        )
    if not op:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Operation not found or access denied.",
        )
    return op


@router.get(
    "/operations/{operation_id}",
    summary="Query authenticated usage operation status",
    description="Returns the execution, reconciliation, or cached result of an operation owned by the authenticated user.",
)
async def get_operation_status(
    operation_id: str,
    email: str = Depends(verify_token),
) -> Dict[str, Any]:
    """
    Authenticated read-only operation status inquiry.
    Guarantees:
    - User ownership verified: Cannot inspect or leak another user's operation.
    - Read-only: Clients cannot transition or finalize operations arbitrarily.
    """
    from backend.app.services.quota_service import QuotaService, StorageUnavailableException
    quota_svc = QuotaService()
    try:
        op = quota_svc.query_operation(user_id=email, operation_id=operation_id)
    except StorageUnavailableException as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        )
    if not op:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Operation not found or access denied.",
        )
    return op


@router.get(
    "/membership/me",
    response_model=AccountMembershipSummary,
    summary="Get current authenticated account membership & usage summary",
    description="Returns active membership tier, subscription duration, explicit entitlement grants, and metered quota usage for the current user.",
)
async def get_my_membership(
    email: str = Depends(verify_token),
) -> AccountMembershipSummary:
    from backend.app.services.entitlement_service import EntitlementService
    from backend.app.services.quota_service import QuotaService
    from backend.app.database_revenue import COLL_SUBSCRIPTIONS, COLL_ENTITLEMENT_GRANTS, COLL_USAGE_BUCKETS

    now = datetime.now(timezone.utc)
    ent_svc = EntitlementService()
    db = ent_svc._get_db()

    if db is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Revenue database connection is unavailable.",
        )

    tier = MembershipTier.FREE
    sub_status = "none"
    is_active_sub = False
    sub_end = None
    auto_renew_status = True
    in_grace_period = False
    grace_period_expires_at = None
    cancel_at_period_end = False
    ownership_status = None
    entitlements = []
    usage_map = {}
    opaque_id = None
    canonical_account_id = email

    try:
        canonical_account_id = resolve_or_create_account_id(db, email)
        if hasattr(db["users"], "update_one"):
            settlement_svc = get_payment_settlement_service()
            proj_id = getattr(getattr(settlement_svc, "_adapter", None), "expected_project_id", None)
            opaque_id = resolve_or_create_provider_customer_id(
                db, canonical_account_id, project_id=proj_id
            )

        subs_col = db[COLL_SUBSCRIPTIONS]
        sub_doc = subs_col.find_one({
            "user_id": canonical_account_id,
            "status": {"$in": ["active", "trialing", "past_due"]},
            "current_period_start": {"$lte": now},
        })
        if sub_doc:
            p_end = sub_doc.get("current_period_end")
            norm_end = p_end.replace(tzinfo=timezone.utc) if p_end and p_end.tzinfo is None else p_end
            st = sub_doc.get("status", "none")
            in_grace = sub_doc.get("in_grace_period", False)
            grace_end = sub_doc.get("grace_period_expires_at")
            norm_grace_end = grace_end.replace(tzinfo=timezone.utc) if grace_end and grace_end.tzinfo is None else grace_end

            # Check validity
            is_valid = False
            if st in ["active", "trialing"] and (norm_end is None or now < norm_end):
                is_valid = True
            elif st == "past_due" and in_grace and norm_grace_end and now < norm_grace_end:
                is_valid = True

            if is_valid:
                try:
                    tier = MembershipTier(sub_doc.get("tier"))
                    sub_status = st
                    is_active_sub = True
                    sub_end = p_end
                    auto_renew_status = sub_doc.get("auto_renew_status", True)
                    in_grace_period = in_grace
                    grace_period_expires_at = grace_end
                    cancel_at_period_end = sub_doc.get("cancel_at_period_end", False)
                    ownership_status = sub_doc.get("ownership_status")
                except ValueError:
                    pass

        grants_col = db[COLL_ENTITLEMENT_GRANTS]
        raw_grants = list(grants_col.find({"user_id": canonical_account_id, "status": "granted"}))
        for g in raw_grants:
            v_from = g.get("valid_from")
            v_until = g.get("valid_until")
            if v_from and now < v_from:
                continue
            if v_until and now >= v_until:
                continue
            entitlements.append({
                "benefit_id": g.get("benefit_id"),
                "status": g.get("status"),
                "source_type": g.get("source_type", "pilot_grant"),
                "valid_until": v_until,
            })

        q_svc = QuotaService(db=db)
        w_start, w_end, b_key = q_svc._get_window_bounds(now)
        buckets_col = db[COLL_USAGE_BUCKETS]
        b_doc = buckets_col.find_one({
            "user_id": canonical_account_id,
            "bucket_key": b_key,
            "window_start": w_start,
        })
        if b_doc:
            consumed = b_doc.get("consumed_units", 0)
            reserved = b_doc.get("reserved_units", 0)
            limit = b_doc.get("limit_units")
            remaining = max(0, limit - (consumed + reserved)) if limit is not None else None
            reset_at = b_doc.get("reset_at", w_end)
            usage_map["ai.nutrition_gemini"] = BenefitUsageSummary(
                benefit_id="ai.nutrition_gemini",
                consumed_units=consumed,
                reserved_units=reserved,
                remaining_units=remaining,
                limit_units=limit,
                period_key=b_key,
                reset_at=reset_at,
            )
        elif not hasattr(db["users"], "update_one"):
            limit = 30
            usage_map["ai.nutrition_gemini"] = BenefitUsageSummary(
                benefit_id="ai.nutrition_gemini",
                consumed_units=0,
                reserved_units=0,
                remaining_units=limit,
                limit_units=limit,
                period_key=b_key,
                reset_at=w_end,
            )
        else:
            usage_map["ai.nutrition_gemini"] = BenefitUsageSummary(
                benefit_id="ai.nutrition_gemini",
                consumed_units=0,
                reserved_units=0,
                remaining_units=None,
                limit_units=None,
                period_key=b_key,
                reset_at=w_end,
            )
    except LegacyR02IdentityMigrationRequiredError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "code": exc.code,
                "message": exc.message,
            },
        )
    except Exception as exc:
        logger.error("Database error building membership summary for %s: %s", email, exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Database error building membership summary: {exc}",
        )

    return AccountMembershipSummary(
        user_id=email,
        account_id=canonical_account_id,
        tier=tier,
        status=sub_status,
        is_active_subscription=is_active_sub,
        current_period_end=sub_end,
        auto_renew_status=auto_renew_status,
        in_grace_period=in_grace_period,
        grace_period_expires_at=grace_period_expires_at,
        cancel_at_period_end=cancel_at_period_end,
        ownership_status=ownership_status,
        opaque_app_user_id=opaque_id,
        entitlements=entitlements,
        usage=usage_map,
        as_of=now,
    )


@router.post(
    "/purchases/verify",
    response_model=PurchaseVerificationResponse,
    summary="Verify a store purchase proof and project membership entitlements",
    description=(
        "Trusted payment boundary endpoint. Separates untrusted client input from verified "
        "provider data, validates (provider, environment, app_id, product_id) mapping, "
        "records durable write-ahead provider event, and projects subscription + entitlements."
    ),
)
async def verify_purchase(
    payload: PurchaseVerificationRequest,
    email: str = Depends(verify_token),
) -> PurchaseVerificationResponse:
    settlement_svc = get_payment_settlement_service()
    try:
        return settlement_svc.verify_and_settle_purchase(
            authenticated_user_id=email,
            request=payload,
        )
    except ReceiptOwnershipConflictError as exc:
        raise HTTPException(
            status_code=exc.http_status,
            detail={
                "code": exc.code,
                "message": exc.message,
                "ownership_status": exc.ownership_status,
                "first_owner_policy": exc.first_owner_policy,
            },
        )
    except PaymentBoundaryError as exc:
        raise HTTPException(
            status_code=exc.http_status,
            detail={
                "code": exc.code,
                "message": exc.message,
            },
        )


@router.post(
    "/purchases/restore",
    response_model=RestorePurchasesResponse,
    summary="Restore existing verified purchases across devices or reinstallations",
    description=(
        "Restores subscription entitlements using verified store receipt proof. "
        "Same account: refreshes state without creating duplicate transactions. "
        "Different account: detects ownership conflict (409) without unilateral transfer."
    ),
)
async def restore_purchases(
    payload: RestorePurchasesRequest,
    email: str = Depends(verify_token),
) -> RestorePurchasesResponse:
    settlement_svc = get_payment_settlement_service()
    try:
        return settlement_svc.verify_and_settle_restore(
            authenticated_user_id=email,
            request=payload,
        )
    except ReceiptOwnershipConflictError as exc:
        raise HTTPException(
            status_code=exc.http_status,
            detail={
                "code": exc.code,
                "message": exc.message,
                "ownership_status": exc.ownership_status,
                "first_owner_policy": exc.first_owner_policy,
            },
        )
    except PaymentBoundaryError as exc:
        raise HTTPException(
            status_code=exc.http_status,
            detail={
                "code": exc.code,
                "message": exc.message,
            },
        )


@router.post(
    "/webhooks/revenuecat",
    summary="RevenueCat server-to-server webhook ingestion",
    description=(
        "Authenticates and ingests asynchronous subscription lifecycle events from RevenueCat. "
        "Verifies Authorization Bearer token, validates schema and environment, records durable "
        "write-ahead event, and projects subscription state idempotently."
    ),
)
async def ingest_revenuecat_webhook(
    request: Request,
) -> Dict[str, Any]:
    headers = dict(request.headers)
    raw_body = await request.body()
    expected_app_id = (
        os.environ.get("REVENUECAT_APP_ID", "").strip()
        or os.environ.get("REVENUE_EXPECTED_APP_ID", "").strip()
        or "com.saman.health"
    )
    webhook_svc = get_payment_webhook_service()

    try:
        return webhook_svc.ingest_webhook(
            headers=headers,
            raw_body=raw_body,
            expected_app_id=expected_app_id,
        )
    except WebhookVerificationError as exc:
        raise HTTPException(
            status_code=exc.http_status,
            detail={"code": exc.code, "message": exc.message},
        )
    except ReceiptOwnershipConflictError as exc:
        raise HTTPException(
            status_code=exc.http_status,
            detail={
                "code": exc.code,
                "message": exc.message,
                "ownership_status": exc.ownership_status,
                "first_owner_policy": exc.first_owner_policy,
            },
        )
    except PaymentConfigurationNotReadyError as exc:
        raise HTTPException(
            status_code=exc.http_status,
            detail={"code": exc.code, "message": exc.message},
        )
    except ProductMappingRejectedError as exc:
        raise HTTPException(
            status_code=exc.http_status,
            detail={"code": exc.code, "message": exc.message},
        )
    except PaymentStorageError as exc:
        raise HTTPException(
            status_code=exc.http_status,
            detail={"code": exc.code, "message": exc.message},
        )
    except Exception as exc:
        logger.error("Unexpected error processing RevenueCat webhook: %s", exc, exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"code": "INTERNAL_WEBHOOK_ERROR", "message": "An unexpected error occurred during webhook processing."},
        )

