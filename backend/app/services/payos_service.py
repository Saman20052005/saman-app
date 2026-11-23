"""
PayOS / VietQR Payment Service (P0.5).

Handles:
- PayOS v2 HMAC-SHA256 request signing and webhook signature verification.
- Creating VietQR payment orders from authoritative catalog prices (fail-closed on missing config).
- Atomic CAS transition (pending -> paid) to prevent double-grant on webhook replays.
- Upserting Subscription, EntitlementGrant, and PaymentTransaction records in MongoDB.
- Polling PayOS v2 order status when testing locally without a public webhook tunnel.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import json
import logging
import os
import secrets
import time
from typing import Any, Dict, List, Optional

from fastapi import HTTPException, status
import httpx

from backend.app.database_revenue import (
    COLL_ENTITLEMENT_GRANTS,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_SUBSCRIPTIONS,
)
from backend.app.models.revenue import (
    BillingPeriod,
    CreatePayosQrResponse,
    EntitlementStatus,
    MembershipTier,
    PaymentProviderName,
    PaymentStatus,
    PayosOrderStatusResponse,
    SubscriptionStatus,
)
from backend.app.services.catalog_engine import get_catalog_engine

logger = logging.getLogger(__name__)

COLL_PAYMENT_ORDERS = "payment_orders"

DEFAULT_PAYOS_RETURN_URL = "https://saman.app/payment/success"
DEFAULT_PAYOS_CANCEL_URL = "https://saman.app/payment/cancel"
DEFAULT_PAYOS_BASE_URL = "https://api-merchant.payos.vn"

TIER_BENEFITS: Dict[MembershipTier, List[str]] = {
    MembershipTier.PLUS: [
        "ai.nutrition_gemini",
        "ai.chat.swift3",
        "ai.chat.core3",
    ],
    MembershipTier.PRO: [
        "ai.nutrition_gemini",
        "ai.chat.swift3",
        "ai.chat.core3",
        "workout.cv.ai",
        "workout.cv.lat_pulldown",
        "workout.movement_rep_counting",
    ],
    MembershipTier.ULTRA: [
        "ai.nutrition_gemini",
        "ai.chat.swift3",
        "ai.chat.core3",
        "workout.cv.ai",
        "workout.cv.lat_pulldown",
        "workout.movement_rep_counting",
        "ai.chat.pro3",
        "ai.advanced_thinking",
        "ai.extended_memory",
    ],
}


def _get_payos_config() -> Dict[str, str]:
    return {
        "client_id": os.getenv("PAYOS_CLIENT_ID", "").strip(),
        "api_key": os.getenv("PAYOS_API_KEY", "").strip(),
        "checksum_key": os.getenv("PAYOS_CHECKSUM_KEY", "").strip(),
        "return_url": os.getenv("PAYOS_RETURN_URL", DEFAULT_PAYOS_RETURN_URL).strip() or DEFAULT_PAYOS_RETURN_URL,
        "cancel_url": os.getenv("PAYOS_CANCEL_URL", DEFAULT_PAYOS_CANCEL_URL).strip() or DEFAULT_PAYOS_CANCEL_URL,
        "base_url": (os.getenv("PAYOS_BASE_URL", DEFAULT_PAYOS_BASE_URL).strip() or DEFAULT_PAYOS_BASE_URL).rstrip("/"),
    }


def _require_payos_config() -> Dict[str, str]:
    cfg = _get_payos_config()
    if not cfg["client_id"] or not cfg["api_key"] or not cfg["checksum_key"]:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "PAYMENT_PROVIDER_NOT_CONFIGURED",
                "message": "PayOS payment provider credentials are not configured.",
            },
        )
    return cfg


def _format_payos_value(val: Any) -> str:
    if val is None:
        return ""
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, (dict, list)):
        return json.dumps(val, separators=(",", ":"), ensure_ascii=False, sort_keys=True)
    return str(val)


def sign_payos_create_request(
    *,
    amount: int,
    cancel_url: str,
    description: str,
    order_code: int,
    return_url: str,
    checksum_key: str,
) -> str:
    """Computes PayOS v2 create-payment-link HMAC-SHA256 signature."""
    raw = (
        f"amount={amount}"
        f"&cancelUrl={cancel_url}"
        f"&description={description}"
        f"&orderCode={order_code}"
        f"&returnUrl={return_url}"
    )
    return hmac.new(
        checksum_key.encode("utf-8"),
        raw.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def sign_payos_webhook_data(data: Dict[str, Any], checksum_key: str) -> str:
    """Computes PayOS v2 webhook HMAC-SHA256 signature over sorted keys of `data`."""
    parts = [f"{k}={_format_payos_value(data[k])}" for k in sorted(data.keys())]
    raw = "&".join(parts)
    return hmac.new(
        checksum_key.encode("utf-8"),
        raw.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def verify_payos_webhook_signature(
    data: Optional[Dict[str, Any]],
    signature: Optional[str],
    checksum_key: str,
) -> bool:
    """Constant-time verification of PayOS v2 webhook HMAC-SHA256 signature."""
    if not isinstance(data, dict) or not signature or not checksum_key:
        return False
    expected = sign_payos_webhook_data(data, checksum_key)
    return hmac.compare_digest(expected.lower(), str(signature).strip().lower())


def _generate_order_code(orders_col: Any) -> int:
    for _ in range(10):
        candidate = int(time.time()) * 1000 + secrets.randbelow(1000)
        if candidate <= 0:
            candidate = secrets.randbelow(900_000_000) + 100_000
        if orders_col.find_one({"order_code": candidate}) is None:
            return candidate
    return int(time.time() * 1000) + secrets.randbelow(100_000) + 1


def _parse_expired_at(raw_val: Any) -> Optional[datetime]:
    if raw_val is None:
        return None
    if isinstance(raw_val, datetime):
        return raw_val if raw_val.tzinfo else raw_val.replace(tzinfo=timezone.utc)
    if isinstance(raw_val, (int, float)) and raw_val > 0:
        return datetime.fromtimestamp(raw_val, tz=timezone.utc)
    if isinstance(raw_val, str) and raw_val.strip():
        try:
            dt = datetime.fromisoformat(raw_val.strip().replace("Z", "+00:00"))
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    return None


def _hash_payload(payload: Any) -> str:
    serialized = json.dumps(payload, sort_keys=True, default=str, ensure_ascii=False)
    return f"sha256:{hashlib.sha256(serialized.encode('utf-8')).hexdigest()}"


def _atomic_transition_order_to_paid(
    orders_col: Any,
    order_code: int,
    *,
    paid_amount: int,
    raw_payload_hash: str,
    now: datetime,
) -> bool:
    """
    Atomically transitions a payment_orders document from 'pending' -> 'paid'.
    Returns True only for the single caller that won the CAS transition.
    Uses find_one_and_update when available with a safe update_one fallback for mocks.
    """
    query = {"order_code": order_code, "status": "pending"}
    update = {
        "$set": {
            "status": "paid",
            "paid_amount": paid_amount,
            "paid_at": now,
            "raw_payload_hash": raw_payload_hash,
            "updated_at": now,
        }
    }

    if hasattr(orders_col, "find_one_and_update"):
        res = orders_col.find_one_and_update(query, update)
        return res is not None

    upd_res = orders_col.update_one(query, update)
    if hasattr(upd_res, "matched_count"):
        return int(getattr(upd_res, "matched_count", 0)) > 0
    if isinstance(upd_res, dict):
        return int(upd_res.get("matched_count", 0)) > 0
    return False


async def create_qr_order(
    db: Any,
    account_id: str,
    email: str,
    plan_id: str,
    billing_period: BillingPeriod,
) -> CreatePayosQrResponse:
    """Creates a PayOS VietQR payment link using authoritative catalog pricing."""
    cfg = _require_payos_config()
    if db is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "DATABASE_UNAVAILABLE", "message": "Database connection is unavailable."},
        )

    catalog = get_catalog_engine().get_active_catalog(include_drafts=False)
    if catalog is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "CATALOG_UNAVAILABLE", "message": "Active catalog is unavailable."},
        )

    plan = next((p for p in catalog.plans if p.plan_id == plan_id), None)
    if plan is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "PLAN_NOT_FOUND", "message": f"Plan '{plan_id}' not found in active catalog."},
        )

    price = next(
        (pr for pr in plan.prices if pr.period == billing_period and pr.purchasable),
        None,
    )
    if price is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "PRICE_NOT_PURCHASABLE",
                "message": f"Plan '{plan_id}' ({billing_period.value}) is not purchasable.",
            },
        )

    orders_col = db[COLL_PAYMENT_ORDERS]
    order_code = _generate_order_code(orders_col)
    amount = int(price.amount_cents)
    currency = price.currency
    description = f"SAMAN {plan.tier.value.upper()} {order_code}"[:25]

    signature = sign_payos_create_request(
        amount=amount,
        cancel_url=cfg["cancel_url"],
        description=description,
        order_code=order_code,
        return_url=cfg["return_url"],
        checksum_key=cfg["checksum_key"],
    )

    request_body = {
        "orderCode": order_code,
        "amount": amount,
        "description": description,
        "returnUrl": cfg["return_url"],
        "cancelUrl": cfg["cancel_url"],
        "signature": signature,
    }
    headers = {
        "x-client-id": cfg["client_id"],
        "x-api-key": cfg["api_key"],
        "Content-Type": "application/json",
    }

    try:
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.post(
                f"{cfg['base_url']}/v2/payment-requests",
                json=request_body,
                headers=headers,
            )
    except httpx.HTTPError as exc:
        logger.error("PayOS create-payment-request transport error: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"code": "PAYOS_UPSTREAM_ERROR", "message": "Unable to reach PayOS payment gateway."},
        )

    if resp.status_code != 200:
        logger.warning("PayOS returned HTTP %s: %s", resp.status_code, resp.text)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"code": "PAYOS_UPSTREAM_ERROR", "message": "PayOS rejected payment link creation."},
        )

    resp_json = resp.json()
    if resp_json.get("code") != "00" or not isinstance(resp_json.get("data"), dict):
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={
                "code": "PAYOS_CREATE_FAILED",
                "message": resp_json.get("desc") or "PayOS failed to generate QR code.",
            },
        )

    data = resp_json["data"]
    now = datetime.now(timezone.utc)
    expires_at = _parse_expired_at(data.get("expiredAt"))
    qr_code = str(data.get("qrCode") or "")
    checkout_url = str(data.get("checkoutUrl") or "")

    order_doc = {
        "order_code": order_code,
        "account_id": account_id,
        "user_id": account_id,
        "email": email,
        "plan_id": plan.plan_id,
        "price_id": price.price_id,
        "tier": plan.tier.value,
        "billing_period": billing_period.value,
        "amount": amount,
        "currency": currency,
        "description": str(data.get("description") or description),
        "qr_code": qr_code,
        "checkout_url": checkout_url,
        "bin": data.get("bin"),
        "account_number": data.get("accountNumber"),
        "account_name": data.get("accountName"),
        "payment_link_id": data.get("paymentLinkId"),
        "status": "pending",
        "expires_at": expires_at,
        "paid_at": None,
        "created_at": now,
        "updated_at": now,
    }
    orders_col.insert_one(order_doc)

    return CreatePayosQrResponse(
        order_code=order_code,
        amount=amount,
        currency=currency,
        description=order_doc["description"],
        qr_code=qr_code,
        checkout_url=checkout_url,
        bin=order_doc["bin"],
        account_number=order_doc["account_number"],
        account_name=order_doc["account_name"],
        status="pending",
        expires_at=expires_at,
    )


def activate_paid_order(
    db: Any,
    order_code: int,
    paid_amount: int,
    raw_payload_hash: str,
    as_of: Optional[datetime] = None,
) -> Dict[str, Any]:
    """
    Validates paid amount and atomically promotes an order from pending -> paid,
    then upserts Subscription, EntitlementGrants, and PaymentTransaction.
    Idempotent under concurrent or repeated webhook replays.
    """
    if db is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "DATABASE_UNAVAILABLE", "message": "Database connection is unavailable."},
        )

    now = as_of or datetime.now(timezone.utc)
    if now.tzinfo is None:
        now = now.replace(tzinfo=timezone.utc)

    orders_col = db[COLL_PAYMENT_ORDERS]
    order = orders_col.find_one({"order_code": order_code})
    if order is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "ORDER_NOT_FOUND", "message": f"Order {order_code} not found."},
        )

    if int(paid_amount) < int(order["amount"]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={
                "code": "INSUFFICIENT_PAYMENT_AMOUNT",
                "message": f"Paid amount {paid_amount} is less than order amount {order['amount']}.",
            },
        )

    if order.get("status") == "paid":
        return {
            "order_code": order_code,
            "status": "paid",
            "already_processed": True,
            "tier": order.get("tier"),
        }

    won_cas = _atomic_transition_order_to_paid(
        orders_col,
        order_code,
        paid_amount=int(paid_amount),
        raw_payload_hash=raw_payload_hash,
        now=now,
    )
    if not won_cas:
        return {
            "order_code": order_code,
            "status": "paid",
            "already_processed": True,
            "tier": order.get("tier"),
        }

    account_id = order.get("account_id") or order.get("user_id")
    email = order.get("email") or ""
    tier = MembershipTier(order["tier"])
    billing_period = BillingPeriod(order["billing_period"])
    duration_days = 365 if billing_period == BillingPeriod.YEARLY else 30
    period_end = now + timedelta(days=duration_days)
    env = os.getenv("REVENUE_PAYMENT_ENVIRONMENT", "production").strip() or "production"

    # 1. Upsert active Subscription in revenue_subscriptions
    subs_col = db[COLL_SUBSCRIPTIONS]
    sub_id = f"sub_payos_{account_id}"
    existing_sub = subs_col.find_one({"user_id": account_id, "provider": PaymentProviderName.PAYOS.value})
    sub_fields = {
        "subscription_id": sub_id,
        "user_id": account_id,
        "user_email": email,
        "plan_id": order["plan_id"],
        "price_id": order["price_id"],
        "tier": tier.value,
        "status": SubscriptionStatus.ACTIVE.value,
        "provider": PaymentProviderName.PAYOS.value,
        "environment": env,
        "original_transaction_id": f"payos_{order_code}",
        "latest_transaction_id": f"payos_{order_code}",
        "current_period_start": now,
        "current_period_end": period_end,
        "cancel_at_period_end": False,
        "auto_renew_status": False,
        "in_grace_period": False,
        "grace_period_expires_at": None,
        "catalog_version": "v1.0-vn",
        "version": (existing_sub.get("version", 1) + 1) if existing_sub else 1,
        "updated_at": now,
    }
    if existing_sub is None:
        subs_col.insert_one({**sub_fields, "created_at": now})
    else:
        subs_col.update_one(
            {"user_id": account_id, "provider": PaymentProviderName.PAYOS.value},
            {"$set": sub_fields},
        )

    # 2. Grant all EntitlementGrants for the purchased tier
    grants_col = db[COLL_ENTITLEMENT_GRANTS]
    benefits = TIER_BENEFITS.get(tier, [])
    for benefit_id in benefits:
        grant_id = f"grant_{sub_id}_{benefit_id}"
        grant_fields = {
            "grant_id": grant_id,
            "user_id": account_id,
            "benefit_id": benefit_id,
            "status": EntitlementStatus.GRANTED.value,
            "source_type": "subscription",
            "source_subscription_id": sub_id,
            "tier": tier.value,
            "valid_from": now,
            "valid_until": period_end,
            "updated_at": now,
        }
        existing_grant = grants_col.find_one({"grant_id": grant_id})
        if existing_grant is None:
            grants_col.insert_one({**grant_fields, "created_at": now})
        else:
            grants_col.update_one({"grant_id": grant_id}, {"$set": grant_fields})

    # 3. Record PaymentTransaction in revenue_payment_transactions
    tx_col = db[COLL_PAYMENT_TRANSACTIONS]
    txn_id = f"txn_payos_{order_code}"
    tx_doc = {
        "transaction_id": txn_id,
        "subscription_id": sub_id,
        "user_id": account_id,
        "status": PaymentStatus.VERIFIED.value,
        "amount_cents": int(paid_amount),
        "currency": order.get("currency", "VND"),
        "provider": PaymentProviderName.PAYOS.value,
        "environment": env,
        "provider_transaction_id": str(order_code),
        "transaction_time": now,
        "purchase_date": now,
        "raw_payload_hash": raw_payload_hash,
        "created_at": now,
        "updated_at": now,
    }
    existing_tx = tx_col.find_one({"transaction_id": txn_id})
    if existing_tx is None:
        tx_col.insert_one(tx_doc)
    else:
        tx_col.update_one({"transaction_id": txn_id}, {"$set": tx_doc})

    return {
        "order_code": order_code,
        "status": "paid",
        "already_processed": False,
        "tier": tier.value,
        "subscription_id": sub_id,
        "granted_benefits": benefits,
    }


async def process_payos_webhook(db: Any, payload: Dict[str, Any]) -> Dict[str, Any]:
    """Verifies PayOS v2 webhook HMAC-SHA256 signature and activates paid order."""
    cfg = _require_payos_config()
    data = payload.get("data")
    signature = payload.get("signature")

    if not verify_payos_webhook_signature(data, signature, cfg["checksum_key"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={
                "code": "INVALID_WEBHOOK_SIGNATURE",
                "message": "Invalid PayOS webhook signature.",
            },
        )

    assert isinstance(data, dict)
    code = str(payload.get("code") or data.get("code") or "")
    if code != "00":
        return {"received": True, "status": "ignored", "code": code}

    order_code_raw = data.get("orderCode")
    amount_raw = data.get("amount")
    if order_code_raw is None or amount_raw is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail={"code": "INVALID_WEBHOOK_DATA", "message": "Missing orderCode or amount in webhook data."},
        )

    result = activate_paid_order(
        db=db,
        order_code=int(order_code_raw),
        paid_amount=int(amount_raw),
        raw_payload_hash=_hash_payload(payload),
    )
    return {"received": True, **result}


async def get_order_status(
    db: Any,
    account_id: str,
    order_code: int,
) -> PayosOrderStatusResponse:
    """
    Retrieves order status for the owning user.
    If order is still pending and PayOS is configured, queries PayOS directly
    so local testing without a webhook tunnel still syncs PAID orders.
    """
    if db is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"code": "DATABASE_UNAVAILABLE", "message": "Database connection is unavailable."},
        )

    orders_col = db[COLL_PAYMENT_ORDERS]
    order = orders_col.find_one({"order_code": order_code})
    if order is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"code": "ORDER_NOT_FOUND", "message": f"Order {order_code} not found."},
        )

    owner_id = order.get("account_id") or order.get("user_id")
    if owner_id != account_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"code": "ORDER_ACCESS_DENIED", "message": "You do not have permission to view this order."},
        )

    if order.get("status") == "pending":
        cfg = _get_payos_config()
        if cfg["client_id"] and cfg["api_key"]:
            try:
                async with httpx.AsyncClient(timeout=10.0) as client:
                    resp = await client.get(
                        f"{cfg['base_url']}/v2/payment-requests/{order_code}",
                        headers={
                            "x-client-id": cfg["client_id"],
                            "x-api-key": cfg["api_key"],
                        },
                    )
                if resp.status_code == 200:
                    resp_json = resp.json()
                    data = resp_json.get("data")
                    if resp_json.get("code") == "00" and isinstance(data, dict):
                        payos_status = str(data.get("status") or "").upper()
                        if payos_status == "PAID":
                            paid_amount = int(data.get("amountPaid") or data.get("amount") or order["amount"])
                            activate_paid_order(
                                db=db,
                                order_code=order_code,
                                paid_amount=paid_amount,
                                raw_payload_hash=_hash_payload(resp_json),
                            )
                            order = orders_col.find_one({"order_code": order_code}) or order
            except httpx.HTTPError as exc:
                logger.warning("PayOS order status sync failed for %s: %s", order_code, exc)

    return PayosOrderStatusResponse(
        order_code=int(order["order_code"]),
        status=str(order.get("status") or "pending"),
        tier=MembershipTier(order["tier"]),
        billing_period=BillingPeriod(order["billing_period"]),
        amount=int(order["amount"]),
        currency=str(order.get("currency") or "VND"),
        paid_at=order.get("paid_at"),
    )
