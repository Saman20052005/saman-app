# [File: routers/user.py]
from fastapi import APIRouter, Depends, HTTPException, Header
import jwt
import sys
import os
import logging

# --- IMPORTS MỚI TỪ CẤU TRÚC REFACTOR ---
from backend.app.models.user import UserProfileInput
from backend.app.repositories.user_repository import UserRepository

# Import service logic
from backend.services.health_engine import HealthEngine

from backend.auth.config import JWT_ALGORITHM, JWT_SECRET
from backend.auth.dependencies import get_token_header

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/user", tags=["User Profile"])

# 🔥 KHỞI TẠO REPOSITORY (Thay thế việc gọi DB trực tiếp)
user_repo = UserRepository()

# --- DEPENDENCY: LẤY USER TỪ TOKEN ---
async def get_current_user(token: str = Depends(get_token_header)):
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        email = payload.get("email")
        
        # 🔥 REFACTOR: Dùng Repository để tìm user
        user = user_repo.get_by_email(email)
        
        if not user:
            raise HTTPException(status_code=401, detail="User not found")
        return user
        
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token Expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid Token")

# --- API UPDATE PROFILE (ĐỒNG BỘ HOÁ) ---
@router.post("/update-profile")
async def update_profile(profile_input: UserProfileInput, current_user: dict = Depends(get_current_user)):
    """
    API này nhận chiều cao, cân nặng, mục tiêu...
    Sau đó TỰ ĐỘNG tính toán chỉ số sức khoẻ (HealthStats) và lưu vào DB.
    Bảo toàn extra fields, CAS chống concurrency conflict (409), validation 422.
    """
    user_email = current_user["email"]
    CALCULATION_FIELDS = ("age", "gender", "height", "weight", "activity_level", "goal")
    ALLOWED_PROFILE_FIELDS = ("full_name", "age", "gender", "height", "weight", "activity_level", "goal")

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
    for field_name in CALCULATION_FIELDS:
        val = merged.get(field_name)
        if val is None:
            raise HTTPException(
                status_code=422,
                detail=f"Missing required profile field '{field_name}' after merge for stats calculation",
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
        update_result = user_repo.update_profile_stats_cas(
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
        fresh_user = user_repo.get_by_email(user_email)
        if not fresh_user:
            raise HTTPException(status_code=404, detail="User not found")
        # Snapshot DB đã bị đổi bởi request khác -> 409 Conflict
        raise HTTPException(
            status_code=409,
            detail="Profile was modified concurrently. Please refresh and try again.",
        )

    # 7. Xây dựng profile trả về (bảo toàn extra fields của existing_profile)
    response_profile = dict(existing_profile) if existing_profile is not None else {}
    for k in ALLOWED_PROFILE_FIELDS:
        if k in merged and merged[k] is not None:
            response_profile[k] = merged[k]

    return {
        "email": user_email,
        "full_name": profile_input.full_name or current_user.get("full_name"),
        "avatar": current_user.get("avatar"),
        "profile": response_profile,
        "health_stats": health_stats.dict(),
    }

# --- API UPDATE PROFILE (PUT METHOD FOR FRONTEND COMPATIBILITY) ---
@router.put("/update-profile")
async def update_profile_put(profile_input: UserProfileInput, current_user: dict = Depends(get_current_user)):
    """
    PUT method for frontend compatibility.
    Delegates to the same logic as POST method.
    """
    return await update_profile(profile_input, current_user)

# --- API GET PROFILE (ĐỂ APP LOAD LÊN) ---
@router.get("/profile")
async def get_profile(current_user: dict = Depends(get_current_user)):
    # Trả về full data để App hiển thị
    return {
        "user_id": str(current_user["_id"]),
        "email": current_user["email"],
        "full_name": current_user.get("full_name"),
        "avatar": current_user.get("avatar"),
        "profile": current_user.get("profile"),
        "health_stats": current_user.get("health_stats")
    }