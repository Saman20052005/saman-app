# [File: routers/user.py]
from datetime import datetime, timezone
import math
import re
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Header, Query
from pydantic import BaseModel, Field, field_validator
import jwt
import sys
import os
import logging
from bson import ObjectId

# --- IMPORTS MỚI TỪ CẤU TRÚC REFACTOR ---
from backend.app.models.user import UserProfileInput, UserProfileResponse
from backend.app.repositories.user_repository import UserRepository
from backend.app.services.context_utils import normalize_email, build_user_query, get_vn_date_str

# Import service logic
from backend.services.health_engine import HealthEngine

from backend.auth.config import JWT_ALGORITHM, JWT_SECRET
from backend.auth.dependencies import get_token_header

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/user", tags=["User Profile"])

# Patchable reference; resolved dynamically from backend.app.database when None
weight_history_collection = None

# 🔥 KHỞI TẠO REPOSITORY (Thay thế việc gọi DB trực tiếp)
user_repo = UserRepository()


def get_user_repository() -> UserRepository:
    return user_repo


def _get_weight_history_collection():
    if weight_history_collection is not None:
        return weight_history_collection
    mod = sys.modules.get("backend.app.database")
    if mod is None:
        try:
            import backend.app.database as mod
        except Exception:
            return None
    col = getattr(mod, "weight_history_collection", None)
    if col is not None:
        return col
    database = getattr(mod, "db", None)
    if database is not None:
        return database["weight_history"]
    return None


def _upsert_weight_history(
    user_id: str,
    email: str,
    weight_kg: float,
    source: str,
    date_str: Optional[str] = None,
):
    col = _get_weight_history_collection()
    if col is None:
        return None
    target_date = date_str or get_vn_date_str()
    doc = {
        "user_id": str(user_id),
        "user_email": normalize_email(email),
        "weight_kg": float(weight_kg),
        "date": target_date,
        "recorded_at": datetime.now(timezone.utc),
        "source": source,
    }
    return col.update_one(
        {"user_id": str(user_id), "date": target_date},
        {"$set": doc},
        upsert=True,
    )


class WeightLogInput(BaseModel):
    weight_kg: float = Field(..., gt=0, le=500)
    date: Optional[str] = None

    @field_validator("weight_kg")
    @classmethod
    def validate_finite_weight(cls, v: float) -> float:
        if not math.isfinite(v) or v <= 0 or v > 500:
            raise ValueError("weight_kg must be a positive finite number <= 500")
        return v

    @field_validator("date")
    @classmethod
    def validate_date_format(cls, v: Optional[str]) -> Optional[str]:
        if v is None:
            return None
        v_clean = v.strip()
        if not v_clean:
            return None
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", v_clean):
            raise ValueError("date must be in YYYY-MM-DD format")
        try:
            datetime.strptime(v_clean, "%Y-%m-%d")
        except ValueError:
            raise ValueError("date must be a valid YYYY-MM-DD calendar date")
        return v_clean


def _extract_canonical_user_id(user: dict) -> str:
    """Resolve canonical string user_id from a user document or principal dict."""
    if not isinstance(user, dict):
        return ""
    raw_id = (
        user.get("_id")
        if user.get("_id") is not None
        else (user.get("user_id") if user.get("user_id") is not None else user.get("id"))
    )
    return str(raw_id) if raw_id is not None else ""


# --- DEPENDENCY: LẤY USER TỪ TOKEN ---
async def get_current_user(
    token: str = Depends(get_token_header),
    repo: UserRepository = Depends(get_user_repository),
):
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        email = payload.get("email")
        user_id_claim = payload.get("user_id") or payload.get("sub") or payload.get("id")

        # 🔥 REFACTOR: Dùng Repository để tìm user (hỗ trợ cả email và user_id claim)
        user = repo.get_by_email(email) if email else None
        if not user and user_id_claim and getattr(repo, "collection", None) is not None:
            uid_str = str(user_id_claim)
            user = repo.collection.find_one({"_id": uid_str})
            if not user and ObjectId.is_valid(uid_str):
                user = repo.collection.find_one({"_id": ObjectId(uid_str)})

        if not user:
            raise HTTPException(status_code=401, detail="User not found")
        return user

    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token Expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid Token")


# --- API UPDATE PROFILE (ĐỒNG BỘ HOÁ) ---
@router.post("/update-profile")
async def update_profile(
    profile_input: UserProfileInput,
    current_user: dict = Depends(get_current_user),
    repo: UserRepository = Depends(get_user_repository),
):
    """
    API này nhận chiều cao, cân nặng, mục tiêu...
    Sau đó TỰ ĐỘNG tính toán chỉ số sức khoẻ (HealthStats) và lưu vào DB.
    Bảo toàn extra fields, CAS chống concurrency conflict (409), validation 422.
    """
    user_email = current_user["email"]
    canonical_user_id = _extract_canonical_user_id(current_user)
    CALCULATION_FIELDS = ("age", "gender", "height", "weight", "activity_level", "goal")
    ALLOWED_PROFILE_FIELDS = ("full_name", "age", "gender", "height", "weight", "activity_level", "goal", "preferences")

    # 1. Kiểm tra explicit null trên 6 trường tính toán -> 422 (không silently bỏ null)
    for field_name in CALCULATION_FIELDS:
        if field_name in profile_input.model_fields_set and getattr(profile_input, field_name) is None:
            raise HTTPException(
                status_code=422,
                detail=f"Field '{field_name}' cannot be explicitly null",
            )

    # 2. Đọc snapshot DB hiện tại của user để merge
    raw_profile = current_user.get("profile")
    existing_profile = raw_profile if isinstance(raw_profile, dict) else None

    existing_data = {
        "age": existing_profile.get("age", current_user.get("age")) if existing_profile is not None else current_user.get("age"),
        "gender": existing_profile.get("gender", current_user.get("gender")) if existing_profile is not None else current_user.get("gender"),
        "height": existing_profile.get("height", current_user.get("height")) if existing_profile is not None else current_user.get("height"),
        "weight": existing_profile.get("weight", current_user.get("weight")) if existing_profile is not None else current_user.get("weight"),
        "activity_level": existing_profile.get("activity_level", current_user.get("activity_level")) if existing_profile is not None else current_user.get("activity_level"),
        "goal": existing_profile.get("goal", current_user.get("goal")) if existing_profile is not None else current_user.get("goal"),
        "full_name": existing_profile.get("full_name", current_user.get("full_name")) if existing_profile is not None else current_user.get("full_name"),
        "preferences": existing_profile.get("preferences", current_user.get("preferences")) if existing_profile is not None else current_user.get("preferences"),
    }

    # Track calculation input provenance (input vs nested vs root fallback)
    field_sources = {}
    for f in CALCULATION_FIELDS:
        if f in profile_input.model_fields_set and getattr(profile_input, f) is not None:
            field_sources[f] = "input"
        elif existing_profile is not None and existing_profile.get(f) is not None:
            field_sources[f] = "nested"
        elif current_user.get(f) is not None:
            field_sources[f] = "root"
        else:
            field_sources[f] = "none"

    # 3. Merge allowlisted input payload với snapshot DB
    merged = dict(existing_data)
    for k in ALLOWED_PROFILE_FIELDS:
        if k in profile_input.model_fields_set:
            val = getattr(profile_input, k)
            if hasattr(val, "value"):
                val = val.value
            if val is not None:
                merged[k] = val

    # 4. Kiểm tra sau merge: nếu chưa đủ 6 trường tính toán -> 422 trước khi ghi
    missing_calc_fields = [f for f in CALCULATION_FIELDS if merged.get(f) is None]
    if missing_calc_fields:
        if "preferences" in profile_input.model_fields_set and profile_input.preferences is not None:
            existing_top_prefs = current_user.get("preferences") if isinstance(current_user.get("preferences"), dict) else {}
            existing_prof_prefs = existing_profile.get("preferences") if (isinstance(existing_profile, dict) and isinstance(existing_profile.get("preferences"), dict)) else {}
            incoming_prefs = profile_input.preferences if isinstance(profile_input.preferences, dict) else {}
            merged_prefs = {**existing_prof_prefs, **existing_top_prefs, **incoming_prefs}
            if getattr(repo, "collection", None) is not None:
                repo.collection.update_one(
                    {"_id": current_user["_id"]},
                    {"$set": {"preferences": merged_prefs, "profile.preferences": merged_prefs}}
                )
            resp_prof = dict(existing_profile) if existing_profile else {}
            resp_prof["preferences"] = merged_prefs
            return {
                "user_id": canonical_user_id,
                "email": user_email,
                "full_name": profile_input.full_name or current_user.get("full_name"),
                "avatar": current_user.get("avatar"),
                "avatar_source": current_user.get("avatar_source", "none"),
                "can_use_google_avatar": current_user.get("can_use_google_avatar", False),
                "profile": resp_prof,
                "health_stats": current_user.get("health_stats"),
            }
        raise HTTPException(
            status_code=422,
            detail=f"Missing required profile field '{missing_calc_fields[0]}' after merge for stats calculation",
        )

    # 5. Tính toán chỉ số sức khoẻ (HealthEngine)
    try:
        health_stats = HealthEngine.calculate_stats(merged)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        logger.exception("Error calculating health stats for user=%s: %s", user_email, str(e))
        raise HTTPException(status_code=500, detail="Health stats calculation failed")

    # 6. Atomic CAS update vào MongoDB
    try:
        update_result = repo.update_profile_stats_cas(
            email=user_email,
            current_user=current_user,
            profile_input=profile_input,
            merged_profile=merged,
            stats=health_stats,
            field_sources=field_sources,
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Database write failure for user=%s: %s", user_email, str(e))
        raise HTTPException(status_code=500, detail="Database write error")

    if update_result.matched_count == 0:
        fresh_user = repo.get_by_email(user_email)
        if not fresh_user:
            raise HTTPException(status_code=404, detail="User not found")
        # Snapshot DB đã bị đổi bởi request khác -> 409 Conflict
        raise HTTPException(
            status_code=409,
            detail="Profile was modified concurrently. Please refresh and try again.",
        )

    if merged.get("weight") is not None:
        try:
            _upsert_weight_history(
                user_id=canonical_user_id,
                email=user_email,
                weight_kg=merged["weight"],
                source="profile_update",
            )
        except Exception as e:
            logger.warning("Failed to upsert weight history for user=%s: %s", user_email, str(e))

    # 7. Xây dựng profile trả về (bảo toàn extra fields của existing_profile)
    response_profile = dict(existing_profile) if existing_profile is not None else {}
    for k in ALLOWED_PROFILE_FIELDS:
        if k in merged and merged[k] is not None:
            response_profile[k] = merged[k]

    if "preferences" in profile_input.model_fields_set and profile_input.preferences is not None:
        existing_top_prefs = current_user.get("preferences") if isinstance(current_user.get("preferences"), dict) else {}
        existing_prof_prefs = existing_profile.get("preferences") if (isinstance(existing_profile, dict) and isinstance(existing_profile.get("preferences"), dict)) else {}
        incoming_prefs = profile_input.preferences if isinstance(profile_input.preferences, dict) else {}
        merged_prefs = {**existing_prof_prefs, **existing_top_prefs, **incoming_prefs}
        if getattr(repo, "collection", None) is not None:
            repo.collection.update_one(
                {"_id": current_user["_id"]},
                {"$set": {"preferences": merged_prefs, "profile.preferences": merged_prefs}}
            )
        response_profile["preferences"] = merged_prefs

    return {
        "user_id": canonical_user_id,
        "email": user_email,
        "full_name": profile_input.full_name or current_user.get("full_name"),
        "avatar": current_user.get("avatar"),
        "avatar_source": current_user.get("avatar_source", "none"),
        "can_use_google_avatar": current_user.get("can_use_google_avatar", False),
        "profile": response_profile,
        "health_stats": health_stats.model_dump() if hasattr(health_stats, "model_dump") else health_stats.dict(),
    }


# --- API UPDATE PROFILE (PUT METHOD FOR FRONTEND COMPATIBILITY) ---
@router.put("/update-profile")
async def update_profile_put(
    profile_input: UserProfileInput,
    current_user: dict = Depends(get_current_user),
    repo: UserRepository = Depends(get_user_repository),
):
    """
    PUT method for frontend compatibility.
    Delegates to the same logic as POST method.
    """
    return await update_profile(profile_input, current_user, repo)


@router.put("/profile")
async def put_profile_alias(
    profile_input: UserProfileInput,
    current_user: dict = Depends(get_current_user),
    repo: UserRepository = Depends(get_user_repository),
):
    """PUT /api/user/profile alias for updating user profile."""
    return await update_profile(profile_input, current_user, repo)


@router.post("/profile")
async def post_profile_alias(
    profile_input: UserProfileInput,
    current_user: dict = Depends(get_current_user),
    repo: UserRepository = Depends(get_user_repository),
):
    """POST /api/user/profile alias for updating user profile."""
    return await update_profile(profile_input, current_user, repo)


# --- API GET PROFILE (ĐỂ APP LOAD LÊN) ---
@router.get("/profile")
async def get_profile(current_user: dict = Depends(get_current_user)):
    # Trả về full data để App hiển thị kèm canonical user_id
    canonical_user_id = _extract_canonical_user_id(current_user)
    user_prof = current_user.get("profile")
    if isinstance(user_prof, dict):
        user_prof = dict(user_prof)
        if "preferences" not in user_prof and current_user.get("preferences"):
            user_prof["preferences"] = current_user.get("preferences")
    return {
        "user_id": canonical_user_id,
        "email": current_user["email"],
        "full_name": current_user.get("full_name"),
        "avatar": current_user.get("avatar"),
        "avatar_source": current_user.get("avatar_source", "none"),
        "can_use_google_avatar": current_user.get("can_use_google_avatar", False),
        "profile": user_prof,
        "health_stats": current_user.get("health_stats")
    }


@router.get("/weight-history")
async def get_weight_history(
    days: int = Query(30, ge=1, le=365),
    current_user: dict = Depends(get_current_user),
):
    col = _get_weight_history_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Weight history service unavailable")

    canonical_user_id = _extract_canonical_user_id(current_user)
    user_email = current_user.get("email", "")
    start_date = get_vn_date_str(offset_days=-(days - 1))

    query = {
        "$and": [
            build_user_query(canonical_user_id, user_email),
            {"date": {"$gte": start_date}},
        ]
    }
    cursor = col.find(query)
    if hasattr(cursor, "sort"):
        cursor = cursor.sort("date", 1)
    docs = list(cursor)
    docs.sort(key=lambda d: d.get("date") or "")

    entries = []
    for doc in docs:
        recorded_at = doc.get("recorded_at")
        recorded_at_val = (
            recorded_at.isoformat() if isinstance(recorded_at, datetime) else recorded_at
        )
        raw_weight = doc.get("weight_kg")
        entries.append(
            {
                "date": doc.get("date"),
                "weight_kg": float(raw_weight) if raw_weight is not None else None,
                "source": doc.get("source"),
                "recorded_at": recorded_at_val,
            }
        )

    latest_weight_kg = entries[-1]["weight_kg"] if entries else None
    delta_kg = None
    if entries and entries[0]["weight_kg"] is not None and latest_weight_kg is not None:
        delta_kg = round(latest_weight_kg - entries[0]["weight_kg"], 2)

    return {
        "days": days,
        "entries": entries,
        "latest_weight_kg": latest_weight_kg,
        "delta_kg": delta_kg,
    }


@router.post("/weight-history")
async def log_weight_history(
    payload: WeightLogInput,
    current_user: dict = Depends(get_current_user),
    repo: UserRepository = Depends(get_user_repository),
):
    col = _get_weight_history_collection()
    if col is None:
        raise HTTPException(status_code=503, detail="Weight history service unavailable")

    canonical_user_id = _extract_canonical_user_id(current_user)
    user_email = current_user.get("email", "")
    today_str = get_vn_date_str()
    target_date = payload.date or today_str

    _upsert_weight_history(
        user_id=canonical_user_id,
        email=user_email,
        weight_kg=payload.weight_kg,
        source="manual_log",
        date_str=target_date,
    )

    health_stats_out = current_user.get("health_stats")
    synced_profile = False

    if target_date == today_str:
        synced_profile = True
        new_weight = float(payload.weight_kg)
        raw_profile = current_user.get("profile")
        existing_profile = raw_profile if isinstance(raw_profile, dict) else None
        calc_fields = ("age", "gender", "height", "weight", "activity_level", "goal")
        merged = {
            f: (
                existing_profile.get(f, current_user.get(f))
                if existing_profile is not None
                else current_user.get(f)
            )
            for f in calc_fields
        }
        merged["weight"] = new_weight

        set_fields = {"weight": new_weight}
        if "profile" in current_user and current_user.get("profile") is None:
            set_fields["profile"] = {"weight": new_weight}
        else:
            set_fields["profile.weight"] = new_weight

        if all(merged.get(f) is not None for f in calc_fields):
            health_stats = HealthEngine.calculate_stats(merged)
            stats_dict = (
                health_stats.model_dump()
                if hasattr(health_stats, "model_dump")
                else health_stats.dict()
            )
            health_stats_out = stats_dict
            if isinstance(current_user.get("health_stats"), dict):
                for k, v in stats_dict.items():
                    if v is not None:
                        set_fields[f"health_stats.{k}"] = v
            else:
                set_fields["health_stats"] = stats_dict

        if getattr(repo, "collection", None) is not None:
            user_filter = (
                {"_id": current_user["_id"]}
                if "_id" in current_user
                else {"email": user_email}
            )
            repo.collection.update_one(user_filter, {"$set": set_fields})

    return {
        "status": "ok",
        "date": target_date,
        "weight_kg": float(payload.weight_kg),
        "source": "manual_log",
        "synced_profile": synced_profile,
        "health_stats": health_stats_out,
    }
