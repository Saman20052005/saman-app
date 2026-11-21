"""Explicit, two-step history analytics endpoints for Saman Coach."""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel
from pymongo.errors import PyMongoError

try:
    from backend.app.database import db
    from backend.app.services.core3_provider import Core3PromptTooLarge, GeminiCore3Provider
    from backend.app.services.history_analytics_service import (
        HistoryAnalyticsPolicyError,
        HistoryAnalyticsQuoteError,
        build_bounded_history_context,
        claim_preflight_quote,
        complete_preflight_quote,
        ensure_history_analytics_indexes,
        fail_preflight_quote,
        preflight_estimate,
        render_history_analytics_prompt,
    )
    from backend.app.services.revenue_guard import (
        evaluate_ai_feature_access,
        is_ai_paywall_enabled,
    )
    from backend.auth_utils import get_current_user
except ImportError:
    from app.database import db
    from app.services.core3_provider import Core3PromptTooLarge, GeminiCore3Provider
    from app.services.history_analytics_service import (
        HistoryAnalyticsPolicyError,
        HistoryAnalyticsQuoteError,
        build_bounded_history_context,
        claim_preflight_quote,
        complete_preflight_quote,
        ensure_history_analytics_indexes,
        fail_preflight_quote,
        preflight_estimate,
        render_history_analytics_prompt,
    )
    from app.services.revenue_guard import (
        evaluate_ai_feature_access,
        is_ai_paywall_enabled,
    )
    from auth_utils import get_current_user


router = APIRouter(prefix="/api/coach/analytics", tags=["Coach History Analytics"])


class PreflightRequest(BaseModel):
    range_days: int | str


class ExecuteRequest(BaseModel):
    quote_id: str
    range_days: int | str
    confirm: bool
    operation_id: Optional[str] = None


def get_history_analytics_db():
    return db


def get_history_analytics_provider():
    return GeminiCore3Provider()


def _policy_http_error():
    return HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail={
            "code": "ALL_TIME_GATED_BY_POLICY",
            "message": "Phạm vi toàn thời gian bị khóa trong giai đoạn thử nghiệm. Vui lòng chọn 7, 14 hoặc 30 ngày.",
        },
    )


def _invalid_range_http_error():
    return HTTPException(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        detail={"code": "INVALID_RANGE", "message": "range_days phải là 7, 14 hoặc 30."},
    )


def _principal_identity(user):
    user_id = str(user.get("_id") or user.get("user_id") or "")
    user_email = str(user.get("email") or "")
    if not user_id or not user_email:
        raise HTTPException(status_code=401, detail="Authenticated user identity is incomplete")
    return user_id, user_email


def _normalize_range_days(range_days: int | str) -> Optional[int]:
    if isinstance(range_days, bool):
        return None
    if isinstance(range_days, int):
        return range_days
    if isinstance(range_days, str):
        clean = range_days.strip()
        if clean.isdigit():
            return int(clean)
    return None


def _enforce_analytics_range_paywall(current_user: dict, range_days: int | str) -> None:
    days = _normalize_range_days(range_days)
    if days != 30 or not is_ai_paywall_enabled():
        return

    decision = evaluate_ai_feature_access(
        benefit_id="ai.extended_memory",
        user_id=str(current_user.get("_id") or current_user.get("user_id") or ""),
        email=str(current_user.get("email") or ""),
        account_id=current_user.get("account_id"),
    )

    if isinstance(decision, bool):
        if not decision:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "entitlement_required",
                    "benefit_id": "ai.extended_memory",
                },
            )
        return

    if isinstance(decision, dict):
        if decision.get("allowed") is True or str(decision.get("status") or "").lower() == "allowed":
            return
        if str(decision.get("status") or "").lower() == "storage_unavailable":
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={
                    "code": "entitlement_unavailable",
                    "benefit_id": "ai.extended_memory",
                    "message": "Entitlement service is unavailable",
                },
            )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "entitlement_required",
                "benefit_id": "ai.extended_memory",
                "reason": decision.get("reason"),
                "tier": decision.get("tier"),
            },
        )

    decision_status = getattr(decision, "status", None)
    status_value = (
        decision_status.value
        if hasattr(decision_status, "value")
        else str(decision_status or "").lower()
    )
    if status_value == "storage_unavailable":
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={
                "code": "entitlement_unavailable",
                "benefit_id": "ai.extended_memory",
                "message": "Entitlement service is unavailable",
            },
        )
    if status_value != "allowed":
        tier = getattr(decision, "tier", None)
        tier_value = tier.value if hasattr(tier, "value") else tier
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "code": "entitlement_required",
                "benefit_id": "ai.extended_memory",
                "reason": getattr(decision, "reason", None),
                "tier": tier_value,
            },
        )


@router.post("/preflight")
async def history_analytics_preflight(
    request: PreflightRequest,
    current_user: dict = Depends(get_current_user),
    database=Depends(get_history_analytics_db),
):
    user_id, user_email = _principal_identity(current_user)
    _enforce_analytics_range_paywall(current_user, request.range_days)
    try:
        return await run_in_threadpool(
            preflight_estimate,
            database,
            user_id,
            user_email,
            request.range_days,
        )
    except HistoryAnalyticsPolicyError:
        raise _policy_http_error()
    except ValueError:
        raise _invalid_range_http_error()
    except PyMongoError:
        try:
            await run_in_threadpool(ensure_history_analytics_indexes, database)
            return await run_in_threadpool(
                preflight_estimate,
                database,
                user_id,
                user_email,
                request.range_days,
            )
        except PyMongoError:
            raise HTTPException(
                status_code=503,
                detail="History analytics database indexes or storage are unavailable",
            )
    except RuntimeError:
        raise HTTPException(status_code=503, detail="History analytics database is unavailable")


@router.post("/execute")
async def execute_history_analytics(
    request: ExecuteRequest,
    current_user: dict = Depends(get_current_user),
    database=Depends(get_history_analytics_db),
    provider=Depends(get_history_analytics_provider),
):
    if request.confirm is not True:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="User confirmation is required to execute analytics",
        )

    user_id, user_email = _principal_identity(current_user)
    _enforce_analytics_range_paywall(current_user, request.range_days)
    try:
        quote, cached_response = claim_preflight_quote(
            request.quote_id,
            user_id,
            user_email,
            request.range_days,
            request.operation_id or request.quote_id,
        )
    except HistoryAnalyticsPolicyError:
        raise _policy_http_error()
    except ValueError as exc:
        if str(exc) == "ALL_TIME_GATED_BY_POLICY":
            raise _policy_http_error()
        raise _invalid_range_http_error()
    except HistoryAnalyticsQuoteError as exc:
        raise HTTPException(status_code=409, detail=str(exc))

    if cached_response is not None:
        return cached_response

    try:
        context = await run_in_threadpool(
            build_bounded_history_context,
            database,
            user_id,
            user_email,
            quote["range_days"],
            quote["end_date"],
        )
        quote_fields = (
            "raw_nutrition_count",
            "active_days",
            "matched_workout_sessions",
            "included_workout_sessions",
            "estimated_tokens",
        )
        if any(context.get(field) != quote.get(field) for field in quote_fields):
            raise HTTPException(
                status_code=409,
                detail="History changed after preflight; request a new quote",
            )
        prompt, context = render_history_analytics_prompt(context)
        report = await provider.generate(prompt)
        response = {
            "status": "success",
            "report": str(report),
            "quote_id": request.quote_id,
            "range_days": quote["range_days"],
            "raw_nutrition_count": context["raw_nutrition_count"],
            "active_days": context["active_days"],
            "included_active_days": context["included_active_days"],
            "matched_workout_sessions": context["matched_workout_sessions"],
            "included_workout_sessions": context["included_workout_sessions"],
            "estimated_tokens": context["estimated_tokens"],
            "quota_cost": quote["quota_cost"],
            "truncated": context["truncated"],
        }
        complete_preflight_quote(request.quote_id, response)
        return response
    except HTTPException:
        fail_preflight_quote(request.quote_id)
        raise
    except Core3PromptTooLarge:
        fail_preflight_quote(request.quote_id)
        raise HTTPException(status_code=413, detail="History analytics prompt exceeds input budget")
    except PyMongoError:
        fail_preflight_quote(request.quote_id)
        raise HTTPException(status_code=503, detail="History analytics database is unavailable")
    except (RuntimeError, OSError):
        fail_preflight_quote(request.quote_id)
        raise HTTPException(status_code=503, detail="History analytics provider is unavailable")
    except Exception:
        fail_preflight_quote(request.quote_id)
        raise
