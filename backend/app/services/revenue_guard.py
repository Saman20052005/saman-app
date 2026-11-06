"""
Revenue Guard & FastAPI Orchestration Service.
Subsystem: Saman Revenue — Membership, Billing & Entitlements (CP-04 / CP-05).

Provides:
- Feature flags: REVENUE_ENFORCEMENT_ENABLED, REVENUE_SHADOW_MODE, REVENUE_ENFORCEMENT_ALLOWLIST.
- Safe orchestration for Nutrition Advanced (Gemini) with zero dispatch on missing entitlement/quota/storage error.
- Idempotency checking, SHA-256 payload fingerprinting, and cache retrieval.
- Late result recovery and unknown state handling without blind release.
"""

from datetime import datetime, timezone
import asyncio
import hashlib
import json
import logging
import os
from typing import Any, Callable, Dict, Optional

from fastapi import Request, HTTPException, status

from backend.app.models.revenue import (
    EntitlementDecisionStatus,
    ReservationStatus,
    ReservationResult,
)
from backend.app.services.entitlement_service import EntitlementService
from backend.app.services.quota_service import QuotaService

logger = logging.getLogger(__name__)


def is_gemini_allowed(email: str) -> bool:
    """
    Check if the authenticated user's email is authorized for Gemini analysis.
    - Exact match after trimming and lowercase normalization.
    - If GEMINI_ALLOWED_EMAILS is missing or empty, returns False.
    """
    if not email or not isinstance(email, str):
        return False
    normalized_email = email.strip().lower()
    if not normalized_email:
        return False

    raw_allowed = os.getenv("GEMINI_ALLOWED_EMAILS", "")
    if not raw_allowed or not raw_allowed.strip():
        return False

    allowed_list = {e.strip().lower() for e in raw_allowed.split(",") if e.strip()}
    return normalized_email in allowed_list


def is_enforcement_enabled(email: Optional[str] = None) -> bool:
    """
    Checks if revenue enforcement is active.
    Defaults to False (Enforcement OFF).
    If REVENUE_ENFORCEMENT_ALLOWLIST is configured, only listed emails are enforced.
    """
    raw_enabled = os.getenv("REVENUE_ENFORCEMENT_ENABLED", "false").strip().lower()
    if raw_enabled not in ("true", "1", "yes"):
        return False

    raw_canary = os.getenv("REVENUE_ENFORCEMENT_ALLOWLIST", "").strip()
    if raw_canary:
        if not email:
            return False
        allowed = {e.strip().lower() for e in raw_canary.split(",") if e.strip()}
        return email.strip().lower() in allowed

    return True


def is_shadow_mode_enabled() -> bool:
    """
    Checks if shadow mode is enabled.
    In shadow mode: evaluates entitlements and logs telemetry, but does NOT block or consume quota.
    """
    return os.getenv("REVENUE_SHADOW_MODE", "false").strip().lower() in ("true", "1", "yes")


def should_consume_quota_on_non_food() -> bool:
    """
    PROPOSED policy for charging quota when an image contains no recognizable food.
    Defaults to False (do not charge user for rejected non-food images).
    """
    return os.getenv("CONSUME_QUOTA_ON_NON_FOOD", "false").strip().lower() in ("true", "1", "yes")


def compute_payload_hash(payload: Any) -> str:
    """Computes a deterministic SHA-256 fingerprint from request data."""
    if isinstance(payload, dict):
        serialized = json.dumps(payload, sort_keys=True, default=str)
    elif isinstance(payload, bytes):
        serialized = payload.hex()
    else:
        serialized = str(payload)
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()


def compute_nutrition_request_hash(
    image_bytes: bytes,
    grams: float = 100.0,
    mode: str = "advanced",
    mime_type: str = "image/jpeg",
) -> str:
    """
    Computes a deterministic SHA-256 fingerprint for food analysis requests,
    explicitly incorporating image bytes, analysis mode, portion grams, and MIME type.
    """
    norm_mode = (mode or "advanced").strip().lower()
    if norm_mode == "gemini":
        norm_mode = "advanced"
    elif norm_mode == "food101":
        norm_mode = "standard"
    norm_mime = (mime_type or "image/jpeg").strip().lower()
    norm_grams = f"{float(grams):.4f}"
    payload_to_hash = (
        image_bytes
        + f":mode={norm_mode}:grams={norm_grams}:mime={norm_mime}".encode("utf-8")
    )
    return hashlib.sha256(payload_to_hash).hexdigest()



class RevenueGuard:
    """
    FastAPI Dependency for evaluating entitlement and reserving quota.
    """

    def __init__(
        self,
        benefit_id: str,
        units: int = 1,
        default_limit: int = 30,
        entitlement_service: Optional[EntitlementService] = None,
        quota_service: Optional[QuotaService] = None,
    ):
        self.benefit_id = benefit_id
        self.units = units
        self.default_limit = default_limit
        self._entitlement_service = entitlement_service or EntitlementService()
        self._quota_service = quota_service or QuotaService()

    async def __call__(self, request: Request) -> ReservationResult:
        user_id = getattr(request.state, "user_id", None)
        if not user_id and hasattr(request.state, "user") and isinstance(request.state.user, dict):
            user_id = request.state.user.get("id") or request.state.user.get("user_id")

        if not user_id:
            user_id = request.headers.get("X-User-Id")

        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required: user identity could not be verified."
            )

        decision = self._entitlement_service.evaluate_entitlement(
            user_id=user_id,
            benefit_id=self.benefit_id,
        )

        if decision.status == EntitlementDecisionStatus.STORAGE_UNAVAILABLE:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Storage error evaluating entitlement: {decision.reason}"
            )

        if decision.status != EntitlementDecisionStatus.ALLOWED:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "error": "entitlement_required",
                    "benefit_id": self.benefit_id,
                    "reason": decision.reason,
                    "tier": decision.tier.value if decision.tier else None,
                }
            )

        client_key = request.headers.get("X-Client-Request-Id") or request.headers.get("Idempotency-Key", "")
        body_bytes = b""
        try:
            body_bytes = await request.body()
        except Exception:
            pass
        request_hash = compute_payload_hash(body_bytes) if body_bytes else None

        res = self._quota_service.reserve_quota(
            user_id=user_id,
            benefit_id=self.benefit_id,
            units=self.units,
            limit_units=self.default_limit,
            idempotency_key=client_key,
            request_hash=request_hash,
            client_request_id=client_key,
        )

        if res.status == ReservationStatus.STORAGE_UNAVAILABLE:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Storage error during quota reservation: {res.error_message}"
            )

        if res.status == ReservationStatus.QUOTA_EXHAUSTED:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail={
                    "error": "quota_exhausted",
                    "benefit_id": self.benefit_id,
                    "consumed_units": res.consumed_units,
                    "remaining_units": res.remaining_units,
                    "limit_units": res.limit_units,
                }
            )

        if res.status == ReservationStatus.OPERATION_CONFLICT:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "error": "operation_conflict",
                    "message": res.error_message,
                }
            )

        return res


async def orchestrate_nutrition_analysis(
    image_bytes: bytes,
    mime_type: str,
    grams: float,
    email: str,
    client_request_id: Optional[str] = None,
    idempotency_key: Optional[str] = None,
    mode: str = "advanced",
    provider_callback: Optional[Callable] = None,
    as_of: Optional[datetime] = None,
    db: Any = None,
    entitlement_service: Optional[EntitlementService] = None,
    quota_service: Optional[QuotaService] = None,
) -> Dict[str, Any]:

    """
    Safely orchestrates Nutrition Advanced (Gemini) analysis.
    
    Invariants Enforced:
    1. Enforcement OFF (default): Preserves existing behavior & allowlist check. 0 quota mutation.
    2. Shadow Mode: Evaluates entitlement & logs telemetry, but does NOT block or consume quota.
    3. Enforcement ON:
       - User MUST pass existing Gemini rollout allowlist (is_gemini_allowed).
       - Allowlist does NOT bypass entitlement: User MUST have ALLOWED entitlement.
       - Missing entitlement -> HTTP 403 (Zero dispatch).
       - Quota exhausted -> HTTP 429 (Zero dispatch).
       - Storage failure -> HTTP 503 (Zero dispatch: fail-closed).
       - Idempotency conflict -> HTTP 409 (Zero dispatch).
       - Replaying identical completed request -> Returns cached payload (0 quota, 0 inference).
       - Provider call: Wrapped with mark_dispatched(), atomic commit, or mark_unknown() on timeout.
    """
    enforced = is_enforcement_enabled(email)
    shadow = is_shadow_mode_enabled()

    # --------------------------------------------------------------------------
    # CASE 1: ENFORCEMENT OFF (Default Production State)
    # --------------------------------------------------------------------------
    if not enforced:
        # Existing behavior: check allowlist
        if not is_gemini_allowed(email):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Gemini food analysis is restricted to authorized test accounts",
            )

        # Shadow evaluation telemetry (if enabled)
        if shadow:
            try:
                ent_svc = entitlement_service or EntitlementService(db=db)
                decision = ent_svc.evaluate_entitlement(user_id=email, benefit_id="ai.nutrition_gemini", as_of=as_of)
                logger.info("[REVENUE-SHADOW] user=%s benefit=ai.nutrition_gemini status=%s reason=%s",
                            email, decision.status.value, decision.reason)
            except Exception as shadow_exc:
                logger.warning("[REVENUE-SHADOW-ERROR] Evaluation failed in shadow mode: %s", shadow_exc)

        # Dispatch directly to provider without quota reservation
        if provider_callback:
            return await provider_callback(image_bytes=image_bytes, mime_type=mime_type, grams=grams)

        from backend.services.gemini_food_analyzer import (
            get_gemini_food_analyzer,
            GeminiConfigurationError,
            GeminiAnalysisError,
        )
        try:
            analyzer = get_gemini_food_analyzer()
            return await analyzer.analyze(
                image_bytes=image_bytes,
                mime_type=mime_type,
                grams=grams,
            )
        except (GeminiConfigurationError, GeminiAnalysisError) as exc:
            logger.exception("Gemini food analysis failed: %s", exc)
            raise HTTPException(status_code=500, detail=str(exc))
        except Exception as exc:
            logger.exception("Unexpected error in Gemini food analysis: %s", exc)
            raise HTTPException(status_code=500, detail="Gemini food analysis failed")

    # --------------------------------------------------------------------------
    # CASE 2: ENFORCEMENT ON
    # --------------------------------------------------------------------------
    # Step A: Rollout Allowlist Check (Cannot bypass allowlist)
    if not is_gemini_allowed(email):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Gemini food analysis is restricted to authorized test accounts",
        )

    ent_svc = entitlement_service or EntitlementService(db=db)
    q_svc = quota_service or QuotaService(db=db)

    # Step B: Entitlement Evaluation
    decision = ent_svc.evaluate_entitlement(
        user_id=email,
        benefit_id="ai.nutrition_gemini",
        as_of=as_of,
    )

    if decision.status == EntitlementDecisionStatus.STORAGE_UNAVAILABLE:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "storage_unavailable", "message": f"Storage error evaluating entitlement: {decision.reason}"}
        )

    if decision.status != EntitlementDecisionStatus.ALLOWED:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "error": "entitlement_required",
                "benefit_id": "ai.nutrition_gemini",
                "reason": decision.reason,
                "tier": decision.tier.value if decision.tier else None,
            }
        )

    # Step C: Idempotency Key & Payload Fingerprint (includes mode, grams, mime_type, image_bytes)
    request_hash = compute_nutrition_request_hash(
        image_bytes=image_bytes,
        grams=grams,
        mode=mode,
        mime_type=mime_type,
    )
    effective_idemp_key = idempotency_key or client_request_id or f"img_{request_hash[:24]}"


    # Step D: Atomic Quota Reservation
    res = q_svc.reserve_quota(
        user_id=email,
        benefit_id="ai.nutrition_gemini",
        units=1,
        limit_units=30,
        idempotency_key=effective_idemp_key,
        request_hash=request_hash,
        client_request_id=client_request_id,
        as_of=as_of,
    )

    if res.status == ReservationStatus.STORAGE_UNAVAILABLE:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": "storage_unavailable", "message": res.error_message}
        )

    if res.status == ReservationStatus.QUOTA_EXHAUSTED:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "error": "quota_exhausted",
                "consumed_units": res.consumed_units,
                "remaining_units": res.remaining_units,
                "limit_units": res.limit_units,
                "message": res.error_message,
            }
        )

    if res.status == ReservationStatus.OPERATION_CONFLICT:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "operation_conflict", "message": res.error_message}
        )

    if res.status == ReservationStatus.ALREADY_COMPLETED:
        if res.cached_payload:
            return res.cached_payload
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "operation_already_completed", "message": "Operation already completed. Re-run requires a new request ID."}
        )

    if res.status == ReservationStatus.IN_PROGRESS:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "operation_in_progress", "operation_id": res.operation_id, "message": "An identical request is currently executing."}
        )

    # Step E: Provider Dispatch with Lifecycle Protection
    q_svc.mark_dispatched(operation_id=res.operation_id, lease_token=res.lease_token)

    raw_result = None
    try:
        if provider_callback:
            raw_result = await provider_callback(image_bytes=image_bytes, mime_type=mime_type, grams=grams)
        else:
            from backend.services.gemini_food_analyzer import get_gemini_food_analyzer
            analyzer = get_gemini_food_analyzer()
            raw_result = await analyzer.analyze(image_bytes=image_bytes, mime_type=mime_type, grams=grams)
    except Exception as exc:
        is_timeout = isinstance(exc, (asyncio.TimeoutError, TimeoutError)) or "timeout" in str(exc).lower() or "deadline" in str(exc).lower()
        if is_timeout:
            # Stalled dispatched operation: Held in unknown, NEVER released blindly
            q_svc.mark_unknown(res.operation_id, reason=f"Provider timeout: {exc}")
            raise HTTPException(
                status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                detail={"error": "provider_timeout", "operation_id": res.operation_id, "message": "Gemini food analysis timed out; operation status is unknown."}
            )

        # Check for non-food image rejection
        is_non_food = "not contain recognizable food" in str(exc).lower() or "not food" in str(exc).lower()
        if is_non_food:
            if should_consume_quota_on_non_food():
                q_svc.commit_quota(operation_id=res.operation_id, lease_token=res.lease_token, as_of=as_of)
            else:
                q_svc.release_quota(operation_id=res.operation_id, lease_token=res.lease_token, reason="non_food_rejected", as_of=as_of)
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail={"error": "not_food", "message": str(exc)})

        # Configuration or general provider error
        q_svc.release_quota(operation_id=res.operation_id, lease_token=res.lease_token, reason=f"provider_error: {exc}", as_of=as_of)
        raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail={"error": "provider_unavailable", "message": f"Gemini provider error: {exc}"})

    # Step F: Validate and Commit
    if not isinstance(raw_result, dict):
        q_svc.release_quota(operation_id=res.operation_id, lease_token=res.lease_token, reason="invalid_response_schema", as_of=as_of)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"error": "provider_invalid_response", "message": "Invalid response schema returned by provider."}
        )

    q_svc.commit_quota(
        operation_id=res.operation_id,
        lease_token=res.lease_token,
        response_payload=raw_result,
        as_of=as_of,
    )
    return raw_result
