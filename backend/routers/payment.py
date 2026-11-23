"""
FastAPI Router for PayOS / VietQR Payments (P0.5).
"""

from typing import Any, Dict
from fastapi import APIRouter, Depends, HTTPException, Request, status

from backend.app.models.revenue import (
    CreatePayosQrRequest,
    CreatePayosQrResponse,
    PayosOrderStatusResponse,
)
from backend.app.services.payos_service import (
    create_qr_order,
    get_order_status,
    process_payos_webhook,
)
from backend.app.services.revenuecat_adapter import resolve_or_create_account_id
from backend.auth_utils import verify_token

router = APIRouter(prefix="/api/payments", tags=["Payments (PayOS / VietQR)"])


def _get_db() -> Any:
    import backend.app.database as app_db

    db = app_db.db
    if db is None and hasattr(app_db, "connect_db"):
        db = app_db.connect_db()
    if db is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "DATABASE_UNAVAILABLE", "message": "Database connection is unavailable."},
        )
    return db


@router.post(
    "/create-qr",
    response_model=CreatePayosQrResponse,
    summary="Create a PayOS VietQR payment order",
)
async def create_payos_qr(
    payload: CreatePayosQrRequest,
    email: str = Depends(verify_token),
) -> CreatePayosQrResponse:
    db = _get_db()
    account_id = resolve_or_create_account_id(db, email)
    return await create_qr_order(
        db=db,
        account_id=account_id,
        email=email,
        plan_id=payload.plan_id,
        billing_period=payload.billing_period,
    )


@router.post(
    "/payos-webhook",
    summary="PayOS server-to-server payment webhook",
)
async def payos_webhook(request: Request) -> Dict[str, Any]:
    try:
        payload = await request.json()
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "INVALID_JSON", "message": "Invalid JSON webhook payload."},
        )
    if not isinstance(payload, dict):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "INVALID_PAYLOAD", "message": "Webhook payload must be a JSON object."},
        )
    db = _get_db()
    return await process_payos_webhook(db=db, payload=payload)


@router.get(
    "/orders/{order_code}",
    response_model=PayosOrderStatusResponse,
    summary="Get PayOS order status for authenticated owner",
)
async def get_payos_order_status(
    order_code: int,
    email: str = Depends(verify_token),
) -> PayosOrderStatusResponse:
    db = _get_db()
    account_id = resolve_or_create_account_id(db, email)
    return await get_order_status(
        db=db,
        account_id=account_id,
        order_code=order_code,
    )
