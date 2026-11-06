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
        fail_preflight_quote,
        preflight_estimate,
        render_history_analytics_prompt,
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
        fail_preflight_quote,
        preflight_estimate,
        render_history_analytics_prompt,
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


@router.post("/preflight")
async def history_analytics_preflight(
    request: PreflightRequest,
    current_user: dict = Depends(get_current_user),
    database=Depends(get_history_analytics_db),
):
    user_id, user_email = _principal_identity(current_user)
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
