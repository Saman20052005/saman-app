from pydantic import BaseModel, EmailStr, Field, field_validator
import math
from typing import Optional
from datetime import datetime
from .common import Gender, ActivityLevel, Goal

class UserProfileInput(BaseModel):
    email: Optional[EmailStr] = None  # Make optional for updates
    full_name: Optional[str] = Field(None, min_length=2, max_length=100)
    age: Optional[int] = Field(None, ge=13, le=120)
    gender: Optional[Gender] = None
    height: Optional[float] = Field(None, gt=0)
    weight: Optional[float] = Field(None, gt=0)
    activity_level: Optional[ActivityLevel] = None
    goal: Optional[Goal] = None

    @field_validator("height", "weight")
    @classmethod
    def validate_finite_positive(cls, v):
        if v is not None:
            if not math.isfinite(v) or v <= 0:
                raise ValueError("Must be a positive finite number")
        return v

class UserHealthStats(BaseModel):
    bmi: Optional[float] = None
    bmr: Optional[int] = None
    tdee: Optional[int] = None
    daily_calories: Optional[int] = None
    daily_calorie_needs: Optional[int] = None
    water_target_ml: Optional[int] = None
    target_protein: Optional[int] = None
    target_carbs: Optional[int] = None
    target_fat: Optional[int] = None
    updated_at: Optional[datetime] = None

class UserDB(BaseModel):
    id: str
    email: EmailStr
    full_name: str
    age: int
    gender: Gender
    height: float
    weight: float
    activity_level: ActivityLevel
    goal: Goal
    created_at: datetime
    updated_at: datetime
    health_stats: Optional[UserHealthStats] = None

class UserAuth(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8)

class ProfileUpdateRequest(BaseModel):
    full_name: Optional[str] = Field(None, min_length=2, max_length=100)
    age: Optional[int] = Field(None, ge=13, le=120)
    gender: Optional[Gender] = None
    height: Optional[float] = Field(None, gt=0)
    weight: Optional[float] = Field(None, gt=0)
    activity_level: Optional[ActivityLevel] = None
    goal: Optional[Goal] = None
