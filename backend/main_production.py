# [File: main_production.py] - Production Ready FastAPI Application
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging
import os
from dotenv import load_dotenv

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events for production"""
    # Startup: Initialize services
    logger.info("Starting up Health AI Backend...")
    try:
        # Test critical imports
        from backend.services.meal_generator import MealGenerator
        from routers import auth_router, user_router, chat_router, food_analysis_router, nutrition_router, workout_router, health_router
        
        logger.info("✅ All imports successful")
        logger.info("Application startup completed successfully")
    except Exception as e:
        logger.error(f"Failed to initialize services during startup: {e}")
        raise e
    
    yield
    
    # Shutdown: Cleanup resources
    logger.info("Shutting down application...")

# Create FastAPI app with production settings
app = FastAPI(
    title="Health AI Backend",
    version="7.0 - Production Stable",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc"
)

_frontend_url = os.getenv("FRONTEND_URL", "").strip()
_cors_origins = [_frontend_url] if _frontend_url else []
_cors_allow_credentials = True
if not _cors_origins:
    _cors_origins = ["*"]
    _cors_allow_credentials = False

# CORS middleware for production
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=_cors_allow_credentials,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "PATCH"],
    allow_headers=["Authorization", "Content-Type", "Accept", "Cache-Control"],
)

@app.middleware("http")
async def cors_preflight(request: Request, call_next):
    if request.method == "OPTIONS":
        origin = request.headers.get("origin")
        acrh = request.headers.get("access-control-request-headers")

        allow_origin: str | None
        if not origin:
            allow_origin = "*" if "*" in _cors_origins else None
        elif "*" in _cors_origins or origin in _cors_origins:
            allow_origin = origin if _cors_allow_credentials else ("*" if "*" in _cors_origins else origin)
        else:
            allow_origin = None

        headers: dict[str, str] = {}
        if allow_origin:
            headers["Access-Control-Allow-Origin"] = allow_origin
            headers["Vary"] = "Origin"
            headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS, PATCH"
            headers["Access-Control-Allow-Headers"] = acrh or "Authorization, Content-Type, Accept, Cache-Control"
            if _cors_allow_credentials:
                headers["Access-Control-Allow-Credentials"] = "true"
            return Response(status_code=204, headers=headers)

    return await call_next(request)

# Include all routers with proper imports
try:
    from routers import auth_router, user_router, chat_router, food_analysis_router, nutrition_router, workout_router, health_router
    
    app.include_router(auth_router)
    app.include_router(user_router)
    app.include_router(chat_router)
    app.include_router(food_analysis_router)
    app.include_router(nutrition_router)
    app.include_router(workout_router)
    app.include_router(health_router)
    
    logger.info("✅ All routers included successfully")
    
except ImportError as e:
    logger.error(f"❌ Router import failed: {e}")
    raise e

# Root endpoint for health check
@app.get("/")
def read_root():
    return {
        "status": "online", 
        "message": "Health AI Backend Production Ready",
        "version": "7.0",
        "environment": os.getenv("ENVIRONMENT", "production")
    }

# Health check endpoint (no auth required)
@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "timestamp": "2026-03-03T10:27:00Z",
        "service": "health-ai-backend",
        "environment": os.getenv("ENVIRONMENT", "production")
    }

# Debug: Print all registered routes
if os.getenv("DEBUG_ROUTES", "false").lower() == "true":
    @app.on_event("startup")
    async def print_routes():
        print("\n=== REGISTERED ROUTES ===")
        for route in app.routes:
            if hasattr(route, 'path') and hasattr(route, 'methods'):
                methods = getattr(route, 'methods', set())
                print(f"{route.path} -> {route.name} [{','.join(methods)}]")
            else:
                print(f"{route} -> {type(route).__name__}")
        print("=== END ROUTES ===\n")

# Production server configuration
if __name__ == "__main__":
    import uvicorn
    
    # Production uvicorn settings
    uvicorn.run(
        "main_production:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", 8000)),
        reload=os.getenv("ENVIRONMENT", "production") == "development",
        log_level="info"
    )
