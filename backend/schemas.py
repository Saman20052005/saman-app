from pydantic import BaseModel, BeforeValidator
from typing import Optional, List, Annotated # Thêm Annotated và BeforeValidator
from .common import Goal

# --- ADD THIS HELPER FUNCTION ---
def force_int(v):
    if isinstance(v, float):
        return int(round(v))
    return v
# --------------------------------

class ExerciseSet(BaseModel):
    set_index: int
    is_completed: bool
    reps_performed: str = ""

class ExerciseLog(BaseModel):
    name: str
    sets: List[ExerciseSet]

class WorkoutSession(BaseModel):
    user_email: Optional[str] = None
    plan_name: str
    start_time: str
    end_time: str
    duration_seconds: int
    # --- MODIFIED FIELD ---
    calories_burned: Annotated[int, BeforeValidator(force_int)] 
    # ----------------------
    exercises: List[ExerciseLog]

class CustomExercise(BaseModel):
    # ... (Giữ nguyên phần còn lại)
    name: str
    reps: str 
    set_count: int = 3
    tags: List[str] = [] 

class CustomWorkoutPlan(BaseModel):
    # ... (Giữ nguyên phần còn lại)
    id: Optional[str] = None
    title: str
    category: str
    level: str
    duration: str
    kcal: int
    image: Optional[str] = "https://images.unsplash.com/photo-1517836357463-d25dfeac3438?q=80&w=2070" 
    exercises: List[CustomExercise]
    recommended_for_goals: List[Goal] = []