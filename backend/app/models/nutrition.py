from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime

class ChatRequest(BaseModel):
    message: str
    user_id: Optional[str] = None
    context: Optional[Dict[str, Any]] = None

class MealItem(BaseModel):
    name: str
    calories: int
    protein: float
    carbs: float
    fat: float
    fiber: Optional[float] = None
    sugar: Optional[float] = None
    sodium: Optional[int] = None
    quantity: float
    unit: str

class SupplementItem(BaseModel):
    name: str
    dosage: str
    timing: str
    purpose: Optional[str] = None

class NutritionDailyPlan(BaseModel):
    date: datetime
    meals: List[MealItem]
    supplements: Optional[List[SupplementItem]] = None
    total_calories: int
    total_protein: float
    total_carbs: float
    total_fat: float
    notes: Optional[str] = None

class RecipeIngredient(BaseModel):
    name: str
    quantity: float
    unit: str
    calories: int
    protein: float
    carbs: float
    fat: float

class CreateRecipeRequest(BaseModel):
    name: str
    description: Optional[str] = None
    ingredients: List[RecipeIngredient]
    instructions: Optional[str] = None
    prep_time: Optional[int] = None  # in minutes
    cook_time: Optional[int] = None  # in minutes
    servings: int = Field(..., gt=0)
    category: Optional[str] = None

class RecipeDB(BaseModel):
    id: Optional[str] = None
    user_id: Optional[str] = None
    name: str
    description: Optional[str] = None
    ingredients: List[RecipeIngredient]
    instructions: Optional[str] = None
    prep_time: Optional[int] = None
    cook_time: Optional[int] = None
    servings: int
    category: Optional[str] = None
    calories_per_serving: Optional[int] = None
    protein_per_serving: Optional[float] = None
    carbs_per_serving: Optional[float] = None
    fat_per_serving: Optional[float] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

class MealPlanRequest(BaseModel):
    date: datetime
    meals: List[MealItem]
    target_calories: Optional[int] = None
    dietary_restrictions: Optional[List[str]] = None
    preferences: Optional[Dict[str, Any]] = None

class WaterLogRequest(BaseModel):
    amount: int = Field(..., gt=0)  # in ml
    time: Optional[datetime] = None

class SupplementLogRequest(BaseModel):
    supplement_name: str
    dosage: str
    time: Optional[datetime] = None
    notes: Optional[str] = None
