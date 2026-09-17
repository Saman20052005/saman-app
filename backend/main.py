from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging
import os
from pathlib import Path
from dotenv import load_dotenv

# 1. Import các router
from backend.routers import (
    auth_router,
    user_router,
    chat_router,
    food_analysis_router,
    nutrition_router,
    workout_router,
    health_router,
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)

load_dotenv()


def _download_model_if_needed():
    # FIX 1: default fallback đổi sang checkpoint.pth cho nhất quán
    model_path = os.getenv("FOOD_MODEL_PATH", "models/checkpoint.pth")

    if Path(model_path).exists():
        # FIX 3: log để confirm model được load từ đâu khi debug
        logger.info("[Startup] Model already exists: %s", model_path)
        return

    hf_model_id = os.getenv("HF_MODEL_ID")
    if not hf_model_id:
        logger.warning("[Startup] HF_MODEL_ID not set — running mock mode")
        return

    logger.info("[Startup] Downloading model from %s ...", hf_model_id)
    Path(model_path).parent.mkdir(parents=True, exist_ok=True)

    from huggingface_hub import hf_hub_download

    hf_hub_download(
        repo_id=hf_model_id,
        filename="checkpoint.pth",  # FIX 1: đúng tên file trên HuggingFace
        local_dir=str(Path(model_path).parent),
        token=os.getenv("HF_TOKEN"),  # None nếu repo public
    )
    logger.info("[Startup] Model downloaded → %s", model_path)


def _parse_cors_origins() -> list[str]:
    raw = os.getenv("CORS_ORIGINS", "").strip()
    if raw:
        return [o.strip() for o in raw.split(",") if o.strip()]

    environment = os.getenv("ENVIRONMENT", "development")
    if environment == "development":
        return [
            "http://localhost:3000",
            "http://127.0.0.1:3000",
            "http://localhost:5173",
            "http://127.0.0.1:5173",
        ]

    frontend = os.getenv("FRONTEND_URL", "").strip()
    return [frontend] if frontend else []


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events for startup/shutdown."""
    # --- STARTUP ---
    logger.info("Starting up application...")
    try:
        _download_model_if_needed()

        from backend.app.services.classification_provider_factory import create_classification_service
        model_path = os.getenv("FOOD_MODEL_PATH", "models/checkpoint.pth")
        service = create_classification_service(model_path=model_path)
        logger.info("Classification service initialized: %s", type(service).__name__)

        # FIX 2: merge PORT + CORS log từ @on_event("startup") vào đây
        logger.info("PORT=%s", os.environ.get("PORT", "NOT SET"))
        logger.info(
            "CORS active — allow_origins=%s allow_credentials=%s",
            _cors_origins,
            _cors_allow_credentials,
        )
        logger.info("Application startup completed successfully")

    except Exception as e:
        logger.error("Failed to initialize services during startup: %s", e)

    yield

    # --- SHUTDOWN ---
    logger.info("Shutting down application...")


app = FastAPI(
    title="Health AI Backend",
    version="6.5 - Food Recognition Integration",
    lifespan=lifespan,
)

_cors_origins = _parse_cors_origins()
_cors_allow_credentials = True
if not _cors_origins:
    _cors_origins = ["*"]
    _cors_allow_credentials = False

app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=_cors_allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Length"],
)


# FIX 2: đã xóa @app.on_event("startup") — deprecated khi dùng lifespan


@app.middleware("http")
async def log_headers(request: Request, call_next):
    if request.method == "OPTIONS":
        logger.info(
            "CORS preflight — path=%s origin=%s acrm=%s acrh=%s",
            str(request.url.path),
            request.headers.get("origin"),
            request.headers.get("access-control-request-method"),
            request.headers.get("access-control-request-headers"),
        )

        origin = request.headers.get("origin")
        acrh = request.headers.get("access-control-request-headers")

        allow_origin: str | None
        if not origin:
            allow_origin = "*" if "*" in _cors_origins else None
        elif "*" in _cors_origins or origin in _cors_origins:
            allow_origin = (
                origin if _cors_allow_credentials else ("*" if "*" in _cors_origins else origin)
            )
        else:
            allow_origin = None

        headers: dict[str, str] = {}
        if allow_origin:
            headers["Access-Control-Allow-Origin"] = allow_origin
            headers["Vary"] = "Origin"
            headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS, PATCH"
            headers["Access-Control-Allow-Headers"] = (
                acrh or "Authorization, Content-Type, Accept, Cache-Control"
            )
            if _cors_allow_credentials:
                headers["Access-Control-Allow-Credentials"] = "true"
            return Response(status_code=204, headers=headers)

    if os.getenv("LOG_AUTH_HEADER", "0") == "1":
        print(f"DEBUG: Headers: {request.headers.get('authorization')}")

    return await call_next(request)


# Include các router
if "auth_router" in globals() and auth_router:
    app.include_router(auth_router)
if "user_router" in globals() and user_router:
    app.include_router(user_router)
if "chat_router" in globals() and chat_router:
    app.include_router(chat_router)
if "food_analysis_router" in globals() and food_analysis_router:
    app.include_router(food_analysis_router)
if "nutrition_router" in globals() and nutrition_router:
    app.include_router(nutrition_router)
if "workout_router" in globals() and workout_router:
    app.include_router(workout_router)
if "health_router" in globals() and health_router:
    app.include_router(health_router)

# DEBUG: Print all registered routes
print("\n=== REGISTERED ROUTES ===")
for route in app.routes:
    if hasattr(route, "path") and hasattr(route, "methods"):
        methods = getattr(route, "methods", set())
        print(f"{route.path} -> {route.name} [{','.join(methods)}]")
    else:
        print(f"{route} -> {type(route).__name__}")
print("=== END ROUTES ===\n")


@app.get("/")
def read_root():
    return {"status": "online", "message": "Backend updated to Clean Architecture!"}


@app.head("/")
def read_root_head() -> Response:
    return Response(status_code=200)


@app.get("/health")
def health_check():
    return {"status": "healthy"}