from pydantic import BaseModel, Field
from typing import Optional, List, Literal
from datetime import datetime
from .common import Gender, ActivityLevel, Goal

class ExerciseSet(BaseModel):
    reps: int = Field(..., gt=0)
    weight: Optional[float] = Field(None, ge=0)
    distance: Optional[float] = Field(None, ge=0)
    duration: Optional[int] = Field(None, ge=0)  # in seconds
    set_type: Literal["warmup", "normal", "drop", "failure"] = Field("normal")
    rpe: Optional[float] = Field(None, ge=1, le=10)
    note: Optional[str] = Field(None, max_length=300)
    superset_group_id: Optional[str] = None
    is_pr: bool = False

class ExerciseLog(BaseModel):
    exercise_id: str
    exercise_name: str
    sets: List[ExerciseSet]
    notes: Optional[str] = None

class WorkoutSession(BaseModel):
    id: Optional[str] = None
    user_id: str
    name: str
    date: datetime
    duration: int  # in minutes
    exercises: List[ExerciseLog]
    calories_burned: Optional[int] = None
    notes: Optional[str] = None
    created_at: Optional[datetime] = None

class CustomExercise(BaseModel):
    id: Optional[str] = None
    user_id: str
    name: str
    category: str
    muscle_groups: List[str]
    equipment: Optional[str] = None
    instructions: Optional[str] = None
    created_at: Optional[datetime] = None

class CustomWorkoutPlan(BaseModel):
    id: Optional[str] = None
    user_id: str
    name: str
    description: Optional[str] = None
    exercises: List[ExerciseLog]
    estimated_duration: int  # in minutes
    difficulty: str = Field(..., pattern="^(beginner|intermediate|advanced)$")
    created_at: Optional[datetime] = None
