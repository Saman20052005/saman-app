from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime
from .common import Gender, ActivityLevel, Goal

class ExerciseSet(BaseModel):
    reps: int = Field(..., gt=0)
    weight: Optional[float] = Field(None, ge=0)
    distance: Optional[float] = Field(None, ge=0)
    duration: Optional[int] = Field(None, ge=0)  # in seconds

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
