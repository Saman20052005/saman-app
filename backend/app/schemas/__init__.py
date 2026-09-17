# [File: app/schemas/__init__.py]
from pydantic import BaseModel, Field, BeforeValidator
from typing import Optional, Annotated

# Helper: Chuyển ObjectId của Mongo thành string
PyObjectId = Annotated[str, BeforeValidator(str)]

# --- Base Model cho Món ăn ---
class FoodBase(BaseModel):
    name: str
    group: str
    calories: int
    protein: float
    carbs: float
    fat: float
    unit: str = "g"
    standard_serving: int = 100

# --- Model dùng để Trả về (Response) ---
class FoodResponse(FoodBase):
    # Map _id từ MongoDB sang id (string) cho Frontend dùng
    id: Optional[PyObjectId] = Field(alias="_id", default=None)

    class Config:
        populate_by_name = True
        json_schema_extra = {
            "example": {
                "_id": "65123abc...",
                "name": "Cơm trắng",
                "group": "Carb",
                "calories": 130,
                "protein": 2.7,
                "carbs": 28.0,
                "fat": 0.3
            }
        }

# --- 🔥 BỔ SUNG: Model dùng để Tạo món mới (Request) ---
class CreateFoodRequest(BaseModel):
    name: str = Field(..., min_length=2)
    group: str = "Other"
    calories: int
    protein: float = 0
    carbs: float = 0
    fat: float = 0