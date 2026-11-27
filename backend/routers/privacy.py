"""FastAPI Router for User Privacy & Legal Compliance (VN 2026).

Endpoints (all JWT-protected via get_current_user):
- GET    /api/user/consent  — Current consent status vs CURRENT_CONSENT_VERSION
- POST   /api/user/consent  — Record explicit 3-flag consent (+ immutable audit log)
- GET    /api/user/export   — Download scrubbed JSON export of user's personal data
- DELETE /api/user/account  — Confirmed full account & R2 media erasure across 37 collections
"""

from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from backend.app.services.user_privacy_service import (
    CURRENT_CONSENT_VERSION,
    UserPrivacyService,
)
from backend.routers.user import get_current_user

router = APIRouter(prefix="/api/user", tags=["Privacy & Compliance"])
privacy_router = router

VALID_DELETE_CONFIRMATIONS = frozenset({"DELETE", "XOA"})


# ---------------------------------------------------------------------------
# Pydantic Schemas
# ---------------------------------------------------------------------------


class ConsentSubmitIn(BaseModel):
    consent_version: str = Field(default=CURRENT_CONSENT_VERSION, min_length=1, max_length=64)
    accepted_health_data: bool
    accepted_ai_processing: bool
    acknowledged_medical_disclaimer: bool
    locale: str = Field(default="vi", min_length=2, max_length=16)


class ConsentStatusOut(BaseModel):
    has_consented: bool
    required_version: str
    consent_version: Optional[str] = None
    accepted_at: Optional[str] = None
    accepted_health_data: bool = False
    accepted_ai_processing: bool = False
    acknowledged_medical_disclaimer: bool = False


class DeleteAccountIn(BaseModel):
    confirm_text: str = Field(..., min_length=1, max_length=64)


class DeleteAccountOut(BaseModel):
    deleted: bool
    collections_cleaned: int
    total_documents_deleted: int
    r2_objects_deleted: int
    r2_objects_failed: int


# ---------------------------------------------------------------------------
# Dependency Providers
# ---------------------------------------------------------------------------


def get_privacy_db() -> Any:
    """Resolve active MongoDB database instance lazily."""
    import backend.app.database as db_mod

    active_db = getattr(db_mod, "db", None)
    if active_db is None and hasattr(db_mod, "get_db"):
        active_db = db_mod.get_db()
    if active_db is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database service unavailable",
        )
    return active_db


def get_privacy_service(db: Any = Depends(get_privacy_db)) -> UserPrivacyService:
    """Build UserPrivacyService bound to the active database."""
    return UserPrivacyService(db=db)


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.get("/consent", response_model=ConsentStatusOut)
async def get_user_consent(
    current_user: dict = Depends(get_current_user),
    service: UserPrivacyService = Depends(get_privacy_service),
) -> ConsentStatusOut:
    """Return user's current legal consent status compared to CURRENT_CONSENT_VERSION."""
    result = service.get_consent_status(current_user)
    return ConsentStatusOut(**result)


@router.post("/consent", response_model=ConsentStatusOut)
async def submit_user_consent(
    payload: ConsentSubmitIn,
    current_user: dict = Depends(get_current_user),
    service: UserPrivacyService = Depends(get_privacy_service),
) -> ConsentStatusOut:
    """Validate and record explicit legal consent for health data, AI processing, and medical disclaimer."""
    if not (
        payload.accepted_health_data
        and payload.accepted_ai_processing
        and payload.acknowledged_medical_disclaimer
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "All three mandatory acknowledgements "
                "(accepted_health_data, accepted_ai_processing, acknowledged_medical_disclaimer) "
                "must be true."
            ),
        )

    try:
        result = service.record_consent(
            current_user,
            consent_version=payload.consent_version,
            accepted_health_data=payload.accepted_health_data,
            accepted_ai_processing=payload.accepted_ai_processing,
            acknowledged_medical_disclaimer=payload.acknowledged_medical_disclaimer,
            locale=payload.locale,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return ConsentStatusOut(**result)


@router.get("/export")
async def export_user_data(
    current_user: dict = Depends(get_current_user),
    service: UserPrivacyService = Depends(get_privacy_service),
) -> JSONResponse:
    """Export all personal data of the authenticated user as a downloadable JSON attachment."""
    try:
        export_payload = service.export_user_data(current_user)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return JSONResponse(
        content=export_payload,
        headers={
            "Content-Disposition": 'attachment; filename="saman-user-export.json"',
        },
    )


@router.delete("/account", response_model=DeleteAccountOut)
async def delete_user_account(
    payload: DeleteAccountIn,
    current_user: dict = Depends(get_current_user),
    service: UserPrivacyService = Depends(get_privacy_service),
) -> DeleteAccountOut:
    """Permanently delete the authenticated user's account, R2 media, and data across all collections."""
    normalized_confirm = payload.confirm_text.strip().upper()
    if normalized_confirm not in VALID_DELETE_CONFIRMATIONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid confirmation text. Type 'DELETE' or 'XOA' to confirm permanent deletion.",
        )

    try:
        summary = service.delete_user_account(current_user)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    return DeleteAccountOut(**summary)
