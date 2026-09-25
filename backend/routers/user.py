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
    """
    try:
        user_email = current_user["email"]
        logger.info("Updating profile for user=%s payload=%s", user_email, profile_input.dict())
        
        # 1. Gọi HealthEngine để tính toán (Logic nghiệp vụ)
        health_stats = HealthEngine.calculate_stats(profile_input)
        daily_calories = (
            getattr(health_stats, "daily_calories", None)
            or getattr(health_stats, "daily_calorie_needs", None)
            or getattr(health_stats, "tdee", 0)
            or 0
        )
        logger.info(
            "Health stats calculated for user=%s bmi=%.2f daily_calories=%d",
            user_email,
            health_stats.bmi or 0,
            int(daily_calories),
        )

        # 2. Update vào MongoDB thông qua Repository (Logic dữ liệu)
        update_result = user_repo.update_profile_stats(
            email=user_email,
            profile=profile_input,
            stats=health_stats
        )
        logger.info("Profile update completed for user=%s result=%s", user_email, update_result)

        # 3. Trả về cấu trúc giống get_profile
        return {
            "email": user_email,
            "full_name": current_user.get("full_name"),
            "avatar": current_user.get("avatar"),
            "profile": profile_input.dict(),
            "health_stats": health_stats.dict()
        }

    except ValueError as e:
        logger.warning(
            "Validation error updating profile for user=%s error=%s",
            current_user.get("email", "unknown"),
            str(e),
        )
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        logger.exception(
            "Error updating profile for user=%s error=%s",
            current_user.get("email", "unknown"),
            str(e),
        )
        raise HTTPException(status_code=500, detail="Internal Server Error")

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
        "email": current_user["email"],
        "full_name": current_user.get("full_name"),
        "avatar": current_user.get("avatar"),
        "profile": current_user.get("profile"),
        "health_stats": current_user.get("health_stats")
    }