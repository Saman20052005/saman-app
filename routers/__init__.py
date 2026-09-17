# Production router exports - safe imports with error handling
try:
    from .auth import router as auth_router
except ImportError as e:
    print(f"Warning: Failed to import auth router: {e}")
    auth_router = None

try:
    from .user import router as user_router
except ImportError as e:
    print(f"Warning: Failed to import user router: {e}")
    user_router = None

try:
    from .chat import router as chat_router
except ImportError as e:
    print(f"Warning: Failed to import chat router: {e}")
    chat_router = None

try:
    from .food_analysis import router as food_analysis_router
except ImportError as e:
    print(f"Warning: Failed to import food_analysis router: {e}")
    food_analysis_router = None

try:
    from .nutrition import router as nutrition_router
except ImportError as e:
    print(f"Warning: Failed to import nutrition router: {e}")
    nutrition_router = None

try:
    from .workout import router as workout_router
except ImportError as e:
    print(f"Warning: Failed to import workout router: {e}")
    workout_router = None

try:
    from .health import router as health_router
except ImportError as e:
    print(f"Warning: Failed to import health router: {e}")
    health_router = None

__all__ = [
    "auth_router",
    "user_router", 
    "chat_router",
    "food_analysis_router",
    "nutrition_router",
    "workout_router",
    "health_router"
]