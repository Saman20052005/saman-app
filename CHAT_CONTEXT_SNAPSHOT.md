# CHAT CONTEXT SNAPSHOT (Backend & Flutter Frontend)

Snapshot này thu thập toàn bộ ngữ cảnh kỹ thuật liên quan đến tính năng Chat (Backend FastAPI & Flutter Frontend) để nạp vào Tech Lead AI.
- **Thời điểm trích xuất**: 2026-09-28
- **Môi trường & Nền tảng**: FastAPI (Python 3.11), Flutter (Dart 3.4.0 / Flutter 3.22.0), MongoDB, Hugging Face Docker Space.

---

## 1. Project & Runtime Map

### 1.1 Cây thư mục thu gọn (Chat, Runtime Docker, Routes & Flutter Chat Models)

```text
project-root/
├── Dockerfile                         # Cấu hình container runtime triển khai Hugging Face Space
├── README.md                          # HF Space metadata (sdk: docker, app_port: 7860)
├── requirements.txt                   # Root requirements (Python dependencies)
├── backend/
│   ├── requirements.txt               # Backend dependencies (fastapi, uvicorn, google-generativeai, openai, pymongo, ...)
│   ├── main.py                        # Entry point FastAPI, CORS, Lifespan & Route registration
│   ├── auth_utils.py                  # JWT Auth & token verification logic
│   ├── app/
│   │   ├── database.py                # Kết nối MongoDB (conversations, messages, water_logs, ...)
│   │   └── repositories/
│   │       └── user_repository.py     # UserRepository (tra cứu hồ sơ người dùng)
│   └── routers/
│       ├── __init__.py                # Export router instances
│       └── chat.py                    # Router xử lý chính API /api/chat, context injection, action confirmation
└── frontend/
    └── lib/
        ├── config/
        │   └── api_config.dart        # Base URL (`https://nguyenvananan2005-saman-backend.hf.space`) và endpoints
        ├── services/
        │   ├── api_client.dart        # Dio client với Interceptor inject Bearer token
        │   └── nutrition_service.dart # Service phân tích ảnh đồ ăn /api/food/analyze
        ├── models/
        │   ├── ai_analysis_result.dart# Model kết quả AI phân tích thức ăn (ảnh chụp)
        │   └── saman_nudge.dart       # Model proactive coaching nudge trong Chat
        ├── controllers/
        │   └── chat_controller.dart   # ChatState, ChatMessage, ChatConversationSummary, Riverpod ChatController
        └── screens/
            ├── chat_screen.dart       # UI chính màn hình Chat (Saman Chat)
            └── chat/
                ├── tokens/
                │   └── saman_chat_tokens.dart # Design tokens (màu sắc, typography màn hình chat)
                └── widgets/
                    ├── saman_chat_drawer.dart
                    ├── saman_chat_header.dart
                    ├── saman_chat_composer.dart
                    ├── saman_chat_empty_state.dart
                    ├── saman_message_list.dart
                    ├── saman_action_row.dart
                    └── ...
```

---

### 1.2 Cấu hình Runtime Hugging Face & Dockerfile

#### File: `README.md` (Hugging Face Space Metadata)
```markdown
---
title: Saman Backend
emoji: 🏃
colorFrom: blue
colorTo: green
sdk: docker
pinned: false
---
```

#### File: `Dockerfile`
```dockerfile
FROM python:3.11-slim
RUN apt-get update && apt-get install -y \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
RUN mkdir -p models
EXPOSE 7860
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "7860"]
```

---

### 1.3 Entry Point Backend (`backend/main.py`)

File: `backend/main.py`
Khởi tạo FastAPI app, cấu hình CORS middleware, quản lý lifespan và đăng ký toàn bộ router bao gồm `chat_router`.

```python
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
    model_path = os.getenv("FOOD_MODEL_PATH", "models/checkpoint.pth")

    if Path(model_path).exists():
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
        filename="checkpoint.pth",
        local_dir=str(Path(model_path).parent),
        token=os.getenv("HF_TOKEN"),
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
    logger.info("Starting up application...")
    try:
        _download_model_if_needed()

        from backend.app.services.classification_provider_factory import create_classification_service
        model_path = os.getenv("FOOD_MODEL_PATH", "models/checkpoint.pth")
        service = create_classification_service(model_path=model_path)
        logger.info("Classification service initialized: %s", type(service).__name__)

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


@app.middleware("http")
async def log_headers(request: Request, call_next):
    if request.method == "OPTIONS":
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


@app.get("/")
def read_root():
    return {"status": "online", "message": "Backend updated to Clean Architecture!"}


@app.head("/")
def read_root_head() -> Response:
    return Response(status_code=200)


@app.get("/health")
def health_check():
    return {"status": "healthy"}
```

---

## 2. Backend Chat Current State

### 2.1 Dependencies liên quan đến AI/LLM/HTTP trong Backend (`backend/requirements.txt`)

- `fastapi>=0.95`
- `uvicorn[standard]>=0.22`
- `google-generativeai>=0.8.0` (Gemini API)
- `openai>=1.0.0` (OpenAI Fallback)
- `httpx>=0.25` / `requests>=2.28` (HTTP clients)
- `pymongo>=4.3` (MongoDB Driver)
- `pydantic[email]>=2.0`
- `python-jose[cryptography]>=3.0` & `PyJWT>=2.8` (Token parsing & verification)

---

### 2.2 Toàn bộ Code Router Chat Hiện Tại (`backend/routers/chat.py`)

File: `backend/routers/chat.py`
Xử lý các endpoint:
- `POST /api/chat`: Nhận tin nhắn, inject server-authoritative health context, lưu chat history vào MongoDB, gọi Gemini (fallback OpenAI), phát hiện action (vd: log 250ml nước).
- `GET /api/chat/conversations`: Liệt kê các cuộc trò chuyện của user.
- `GET /api/chat/conversations/{conversation_id}`: Lấy chi tiết lịch sử tin nhắn và trạng thái pending action.
- `POST /api/chat/actions/confirm`: Xác nhận action (ghi nhận nước nguyên tử vào MongoDB collection `water_logs`).
- `POST /api/chat/actions/cancel`: Hủy action đang chờ.

```python
# [File: backend/routers/chat.py]
import os
import re
import logging
import asyncio
from typing import Optional, Dict, List, Any
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from fastapi import APIRouter, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel

from bson import ObjectId
from bson.errors import InvalidId

# Repository & Database Collections
from backend.app.repositories.user_repository import UserRepository
from backend.app.database import (
    nutrition_collection,
    workout_history_collection,
    conversations_collection,
    messages_collection,
    water_collection,
)

# Auth dependency
from backend.auth_utils import verify_token

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/chat", tags=["AI Chat"])

user_repo = UserRepository()
chat_bearer = HTTPBearer(auto_error=False)

# Module-level references for testability and DI
nutrition_col = nutrition_collection
workout_history_col = workout_history_collection
conversations_col = conversations_collection
messages_col = messages_collection
water_col = water_collection

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

DEFAULT_TIMEOUT_SECONDS = 15.0
VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")


def _get_timeout() -> float:
    try:
        val = os.getenv("AI_TIMEOUT_SECONDS")
        if val:
            return float(val)
    except (ValueError, TypeError):
        pass
    return DEFAULT_TIMEOUT_SECONDS


def _is_timeout_error(exc: Exception) -> bool:
    if isinstance(exc, (asyncio.TimeoutError, TimeoutError)):
        return True
    exc_name = type(exc).__name__.lower()
    if "timeout" in exc_name or "deadline" in exc_name:
        return True
    exc_str = str(exc).lower()
    if "timed out" in exc_str or "deadline exceeded" in exc_str:
        return True
    return False


def get_current_chat_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(chat_bearer),
) -> dict:
    """
    Authenticate chat request:
    - Missing token -> 401
    - Invalid token -> 401
    - Non-existent user -> 401
    """
    if credentials is None or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        email = verify_token(credentials)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalid",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalid",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = user_repo.get_by_email(email)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


# ─────────────────────────────────────────────────────────────
# HEALTH CONTEXT BUILDER (CHECKPOINT 2: READ-ONLY)
# ─────────────────────────────────────────────────────────────

def _get_current_vn_date() -> str:
    """Return current date in Asia/Ho_Chi_Minh timezone as YYYY-MM-DD."""
    try:
        return datetime.now(VN_TZ).strftime("%Y-%m-%d")
    except Exception:
        vn_offset = timezone(timedelta(hours=7))
        return datetime.now(vn_offset).strftime("%Y-%m-%d")


def _build_user_profile_context(user: dict) -> str:
    raw_name = user.get("full_name")
    user_email = str(user.get("email") or "").strip().lower()
    if not raw_name or "@" in str(raw_name) or (user_email and str(raw_name).strip().lower() == user_email):
        full_name = "chưa có dữ liệu"
    else:
        full_name = str(raw_name).strip()
    profile = user.get("profile") if isinstance(user.get("profile"), dict) else {}
    stats = user.get("health_stats") if isinstance(user.get("health_stats"), dict) else {}

    weight = profile.get("weight") or user.get("weight")
    weight_str = f"{weight} kg" if weight is not None else "chưa có dữ liệu"

    goal = profile.get("goal") or user.get("goal")
    goal_str = str(goal) if goal else "chưa có dữ liệu"

    tdee = stats.get("tdee") or stats.get("daily_calories") or stats.get("daily_calorie_needs")
    tdee_str = f"{tdee} kcal" if tdee is not None else "chưa có dữ liệu"

    return (
        f"HỒ SƠ NGƯỜI DÙNG:\n"
        f"- Tên: {full_name}\n"
        f"- Cân nặng: {weight_str}\n"
        f"- Mục tiêu: {goal_str}\n"
        f"- TDEE: {tdee_str}"
    )


def _build_today_nutrition_context(email: str, col) -> str:
    today_str = _get_current_vn_date()
    if col is None or not email:
        return f"DINH DƯỠNG HÔM NAY ({today_str}): chưa có dữ liệu"

    try:
        logs = list(col.find({"user_email": email, "date": today_str}))
    except Exception as e:
        logger.warning("Failed to query nutrition logs: %s", type(e).__name__)
        return f"DINH DƯỠNG HÔM NAY ({today_str}): chưa có dữ liệu"

    if not logs:
        return f"DINH DƯỠNG HÔM NAY ({today_str}): chưa ghi nhận bữa ăn nào (chưa có dữ liệu)"

    try:
        total_cal = sum(float(l.get("total_calories") or 0) for l in logs)
        total_pro = round(sum(float(l.get("total_protein") or 0) for l in logs), 1)
        total_carbs = round(sum(float(l.get("total_carbs") or 0) for l in logs), 1)
        total_fat = round(sum(float(l.get("total_fat") or 0) for l in logs), 1)
        cal_display = int(total_cal) if total_cal.is_integer() else total_cal
        return (
            f"DINH DƯỠNG HÔM NAY ({today_str}):\n"
            f"- Đã ghi nhận: {len(logs)} bữa\n"
            f"- Tổng calo: {cal_display} kcal\n"
            f"- Protein: {total_pro}g, Carbs: {total_carbs}g, Fat: {total_fat}g"
        )
    except Exception as e:
        logger.warning("Failed to aggregate nutrition logs: %s", type(e).__name__)
        return f"DINH DƯỠNG HÔM NAY ({today_str}): chưa có dữ liệu"


def _parse_timestamp(val) -> Optional[datetime]:
    if isinstance(val, datetime):
        return val
    if isinstance(val, str):
        try:
            return datetime.fromisoformat(val.replace("Z", "+00:00"))
        except Exception:
            try:
                return datetime.strptime(val[:10], "%Y-%m-%d")
            except Exception:
                pass
    return None


def _build_latest_workout_context(email: str, user_id: Optional[str], col) -> str:
    if col is None or not email:
        return "TẬP LUYỆN GẦN NHẤT: chưa có dữ liệu"

    query_or = [{"email": email}]
    if user_id:
        query_or.append({"user_id": user_id})
    workout_query = {"$or": query_or}

    try:
        sessions = list(col.find(workout_query))
    except Exception as e:
        logger.warning("Failed to query workout sessions: %s", type(e).__name__)
        return "TẬP LUYỆN GẦN NHẤT: chưa có dữ liệu"

    if not sessions:
        return "TẬP LUYỆN GẦN NHẤT: chưa có dữ liệu"

    best_session = None
    best_dt = None

    for s in sessions:
        raw_val = s.get("start_time") or s.get("created_at") or s.get("date") or s.get("end_time")
        dt = _parse_timestamp(raw_val)
        if dt is not None:
            cmp_dt = dt.replace(tzinfo=None) if dt.tzinfo is not None else dt
            if best_dt is None or cmp_dt > best_dt:
                best_dt = cmp_dt
                best_session = s

    if best_session is None and sessions:
        best_session = sessions[-1]

    date_part = best_dt.strftime("%Y-%m-%d") if best_dt else "chưa có dữ liệu"
    duration = best_session.get("duration_minutes")
    duration_str = f"{duration} phút" if duration is not None else "chưa có dữ liệu"

    exercises = best_session.get("completed_exercises")
    exercise_names = []
    if isinstance(exercises, list):
        for ex in exercises:
            if isinstance(ex, dict) and ex.get("name"):
                exercise_names.append(str(ex["name"]))
            elif isinstance(ex, str):
                exercise_names.append(ex)

    plan_name = best_session.get("plan_id") or best_session.get("plan_name")
    plan_info = ""
    if exercise_names:
        plan_info = f", Bài tập: {', '.join(exercise_names[:5])}"
    elif plan_name:
        plan_info = f", Kế hoạch: {plan_name}"

    return (
        f"TẬP LUYỆN GẦN NHẤT:\n"
        f"- Ngày: {date_part}\n"
        f"- Thời lượng: {duration_str}{plan_info}"
    )


def build_health_context(user: dict, nutrition_col_ref=None, workout_col_ref=None) -> str:
    """Build concise, server-authoritative health context without leaking private fields."""
    email = user.get("email") or ""
    user_id = str(user.get("_id")) if user.get("_id") is not None else None

    ncol = nutrition_col_ref if nutrition_col_ref is not None else nutrition_col
    wcol = workout_col_ref if workout_col_ref is not None else workout_history_col

    profile_ctx = _build_user_profile_context(user)
    nutrition_ctx = _build_today_nutrition_context(email, ncol)
    workout_ctx = _build_latest_workout_context(email, user_id, wcol)

    return f"{profile_ctx}\n\n{nutrition_ctx}\n\n{workout_ctx}"


# ─────────────────────────────────────────────────────────────
# AI CALLERS
# ─────────────────────────────────────────────────────────────

def _call_gemini_sync(prompt: str, api_key: str, timeout_seconds: float) -> Optional[str]:
    import google.generativeai as genai
    genai.configure(api_key=api_key)
    model = genai.GenerativeModel("gemini-3.8-flash")
    try:
        response = model.generate_content(
            prompt,
            request_options={"timeout": timeout_seconds},
        )
    except TypeError:
        response = model.generate_content(prompt)

    if response and hasattr(response, "text"):
        return response.text
    return None


def _call_openai_sync(prompt: str, api_key: str, timeout_seconds: float) -> Optional[str]:
    from openai import OpenAI
    client = OpenAI(api_key=api_key, timeout=timeout_seconds)
    response = client.chat.completions.create(
        model="gpt-4o-mini",
        messages=[{"role": "user", "content": prompt}],
        max_tokens=300,
        timeout=timeout_seconds,
    )
    if response and response.choices and len(response.choices) > 0:
        msg = response.choices[0].message
        if msg and hasattr(msg, "content"):
            return msg.content
    return None


async def _generate_ai_reply(prompt: str) -> str:
    """
    Generate reply trying Gemini first, then OpenAI fallback.
    Limits provider call duration using SDK capabilities without blocking event loop.
    Timeout -> 504.
    Provider failure, missing config, or empty reply -> 503.
    """
    timeout_seconds = _get_timeout()
    timed_out = False

    # 1. Try Gemini
    gemini_key = os.getenv("GEMINI_API_KEY") or GEMINI_API_KEY
    if gemini_key:
        try:
            raw_reply = await asyncio.wait_for(
                asyncio.to_thread(_call_gemini_sync, prompt, gemini_key, timeout_seconds),
                timeout=timeout_seconds + 1.0,
            )
            if raw_reply and raw_reply.strip():
                return raw_reply.strip()
            logger.warning("Gemini returned empty reply")
        except Exception as e:
            if _is_timeout_error(e):
                logger.warning("Gemini request timed out")
                timed_out = True
            else:
                logger.warning("Gemini provider failed: %s", type(e).__name__)

    # 2. Fallback OpenAI
    openai_key = os.getenv("OPENAI_API_KEY") or OPENAI_API_KEY
    if openai_key:
        try:
            raw_reply = await asyncio.wait_for(
                asyncio.to_thread(_call_openai_sync, prompt, openai_key, timeout_seconds),
                timeout=timeout_seconds + 1.0,
            )
            if raw_reply and raw_reply.strip():
                return raw_reply.strip()
            logger.warning("OpenAI returned empty reply")
        except Exception as e:
            if _is_timeout_error(e):
                logger.warning("OpenAI request timed out")
                timed_out = True
            else:
                logger.warning("OpenAI provider failed: %s", type(e).__name__)

    if timed_out:
        raise HTTPException(
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            detail="AI service timed out",
        )

    raise HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="AI service unavailable",
    )


class ChatRequest(BaseModel):
    message: str
    conversation_id: Optional[str] = None
    context: Optional[Dict[str, Any]] = None
    history: Optional[List[Any]] = None


class ActionDecisionRequest(BaseModel):
    conversation_id: str
    action_id: str
    decision: Optional[str] = "confirm"


def _detect_log_water_intent(message: str) -> bool:
    """
    Chỉ nhận diện một yêu cầu rõ ràng muốn log thêm 250 ml nước.
    Câu nói mơ hồ, hỏi đáp, tư vấn hoặc lượng nước khác 250ml tuyệt đối không tạo action.
    """
    if not message:
        return False

    raw = message.strip().lower()

    # Phủ định hoặc hỏi đáp, tư vấn, so sánh
    inquiry_patterns = [
        r"\?",
        r"\bcó nên\b",
        r"\bbao nhiêu\b",
        r"\bđược không\b",
        r"\bphải không\b",
        r"\bthế nào\b",
        r"\btại sao\b",
        r"\blàm sao\b",
        r"\bnhỉ\b",
        r"\bkhông\s*\?",
        r"\bchưa\b",
    ]
    for pat in inquiry_patterns:
        if re.search(pat, raw):
            return False

    # Phải có số 250 (không phải 2500 hay 1250)
    has_250_amount = bool(
        re.search(r"\b250(?:\s*(?:ml|mili|milli|mililit|mili\s*lít|lít))?(?!\d)\b", raw)
        or re.search(r"\b250\s*ml\b", raw)
    )
    if not has_250_amount:
        return False

    has_water = any(w in raw for w in ["nước", "nuoc", "water"])
    if not has_water:
        return False

    # Phải có hành động log / thêm / uống rõ ràng
    action_keywords = [
        "uống", "thêm", "ghi", "log", "cộng", "lưu", "nhập", "note", "uong", "them", "ghi", "cong"
    ]
    if not any(kw in raw for kw in action_keywords):
        return False

    return True


@router.get("/conversations")
async def list_conversations(
    current_user: dict = Depends(get_current_chat_user),
):
    email = current_user.get("email") or ""
    user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else None

    query_or: List[Dict[str, Any]] = [{"user_email": email}]
    if user_id:
        query_or.append({"user_id": user_id})
    user_query = {"$or": query_or}

    results = []
    if conversations_col is not None:
        try:
            cursor = conversations_col.find(user_query).sort("updated_at", -1).limit(50)
            for c in cursor:
                c_id = str(c.get("_id"))
                results.append({
                    "id": c_id,
                    "title": c.get("title") or "Cuộc trò chuyện",
                    "created_at": c.get("created_at") or "",
                    "updated_at": c.get("updated_at") or c.get("created_at") or "",
                })
        except Exception as e:
            logger.warning("Failed to list conversations: %s", type(e).__name__)

    return {
        "conversations": results,
        "status": "success",
    }


@router.get("/conversations/{conversation_id}")
async def get_conversation_details(
    conversation_id: str,
    current_user: dict = Depends(get_current_chat_user),
):
    email = current_user.get("email") or ""
    user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else None

    try:
        obj_id = ObjectId(conversation_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    query_or: List[Dict[str, Any]] = [{"user_email": email}]
    if user_id:
        query_or.append({"user_id": user_id})

    query = {
        "_id": obj_id,
        "$or": query_or,
    }

    conv = None
    if conversations_col is not None:
        try:
            conv = conversations_col.find_one(query)
        except Exception as e:
            logger.warning("Failed to find conversation: %s", type(e).__name__)

    if not conv:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    messages = []
    for m in conv.get("messages", []):
        messages.append({
            "role": m.get("role", "user"),
            "content": m.get("content", ""),
            "created_at": m.get("created_at", ""),
        })

    res_dict = {
        "id": str(conv["_id"]),
        "title": conv.get("title") or "Cuộc trò chuyện",
        "messages": messages,
        "created_at": conv.get("created_at", ""),
        "updated_at": conv.get("updated_at", ""),
        "status": "success",
    }
    if conv.get("pending_action"):
        res_dict["pending_action"] = conv.get("pending_action")
    return res_dict


@router.post("")
async def chat_with_ai(
    request: ChatRequest,
    current_user: dict = Depends(get_current_chat_user),
):
    trimmed_message = request.message.strip() if request.message else ""
    if not trimmed_message:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Message cannot be empty",
        )

    email = current_user.get("email") or ""
    user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else None

    query_or: List[Dict[str, Any]] = [{"user_email": email}]
    if user_id:
        query_or.append({"user_id": user_id})

    conv = None
    if request.conversation_id:
        try:
            obj_id = ObjectId(request.conversation_id)
        except Exception:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Conversation not found",
            )

        query = {
            "_id": obj_id,
            "$or": query_or,
        }

        if conversations_col is not None:
            try:
                conv = conversations_col.find_one(query)
            except Exception as e:
                logger.warning("Failed to lookup conversation: %s", type(e).__name__)

        if not conv:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Conversation not found",
            )

    is_water_intent = _detect_log_water_intent(trimmed_message)
    if is_water_intent:
        if conversations_col is None:
            logger.error("Conversations collection is not available")
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Chat storage unavailable",
            )

        now_iso = datetime.now(timezone.utc).isoformat()
        action_id = str(ObjectId())
        action_date = datetime.now(VN_TZ).strftime("%Y-%m-%d")
        action_data = {
            "id": action_id,
            "type": "log_water",
            "amount_ml": 250,
            "status": "pending",
            "date": action_date,
            "created_at": now_iso,
        }
        reply = "Bạn có muốn thêm 250 ml nước không?"
        user_msg_doc = {"role": "user", "content": trimmed_message, "created_at": now_iso}
        ai_msg_doc = {"role": "assistant", "content": reply, "created_at": now_iso}

        conv_id_str = ""
        if conv:
            update_query = {
                "_id": conv["_id"],
                "$or": query_or,
            }
            try:
                update_res = conversations_col.update_one(
                    update_query,
                    {
                        "$push": {"messages": {"$each": [user_msg_doc, ai_msg_doc]}},
                        "$set": {
                            "updated_at": now_iso,
                            "pending_action": action_data,
                        },
                    },
                )
                matched_count = getattr(update_res, "matched_count", None)
                if matched_count is not None and matched_count == 0:
                    logger.warning("Conversation update matched 0 documents")
                    raise HTTPException(
                        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                        detail="Chat storage unavailable",
                    )
                conv_id_str = str(conv["_id"])
            except HTTPException:
                raise
            except Exception as e:
                logger.error("Failed to append message to conversation: %s", type(e).__name__)
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Chat storage unavailable",
                )
        else:
            title = trimmed_message[:40] + ("..." if len(trimmed_message) > 40 else "")
            new_conv_doc = {
                "user_email": email,
                "user_id": user_id,
                "title": title,
                "messages": [user_msg_doc, ai_msg_doc],
                "pending_action": action_data,
                "created_at": now_iso,
                "updated_at": now_iso,
            }
            try:
                res = conversations_col.insert_one(new_conv_doc)
                inserted_id = getattr(res, "inserted_id", None)
                if not res or not inserted_id:
                    raise RuntimeError("Failed to obtain inserted_id")
                conv_id_str = str(inserted_id)
            except HTTPException:
                raise
            except Exception as e:
                logger.error("Failed to insert new conversation: %s", type(e).__name__)
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Chat storage unavailable",
                )

        return {
            "reply": reply,
            "status": "success",
            "conversation_id": conv_id_str,
            "action": action_data,
        }

    health_context = build_health_context(
        current_user,
        nutrition_col_ref=nutrition_col,
        workout_col_ref=workout_history_col,
    )

    history_str = ""
    if conv:
        prior_msgs = conv.get("messages", [])
        if prior_msgs:
            recent_prior = prior_msgs[-6:]
            lines = []
            for m in recent_prior:
                role = "User" if m.get("role") == "user" else "Saman"
                content = (m.get("content") or "").strip()
                lines.append(f"- {role}: {content}")
            history_str = "LỊCH SỬ HỘI THOẠI TRƯỚC ĐÓ:\n" + "\n".join(lines)

    prompt_parts = [health_context]
    if history_str:
        prompt_parts.append(history_str)
    prompt_parts.append(f"USER HỎI: {trimmed_message}")
    prompt_parts.append("TRẢ LỜI NGẮN GỌN & THÂN THIỆN:")

    full_prompt = "\n\n".join(prompt_parts)

    if email:
        full_prompt = full_prompt.replace(email, "")
    full_prompt = re.sub(r'[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+', '', full_prompt)

    reply = await _generate_ai_reply(full_prompt)

    if conversations_col is None:
        logger.error("Conversations collection is not available")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Chat storage unavailable",
        )

    now_iso = datetime.now(timezone.utc).isoformat()
    user_msg_doc = {"role": "user", "content": trimmed_message, "created_at": now_iso}
    ai_msg_doc = {"role": "assistant", "content": reply, "created_at": now_iso}

    conv_id_str = ""
    if conv:
        update_query = {
            "_id": conv["_id"],
            "$or": query_or,
        }
        try:
            update_res = conversations_col.update_one(
                update_query,
                {
                    "$push": {"messages": {"$each": [user_msg_doc, ai_msg_doc]}},
                    "$set": {"updated_at": now_iso},
                },
            )
            matched_count = getattr(update_res, "matched_count", None)
            if matched_count is not None and matched_count == 0:
                logger.warning("Conversation update matched 0 documents")
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="Chat storage unavailable",
                )
            conv_id_str = str(conv["_id"])
        except HTTPException:
            raise
        except Exception as e:
            logger.error("Failed to append message to conversation: %s", type(e).__name__)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Chat storage unavailable",
            )
    else:
        title = trimmed_message[:40] + ("..." if len(trimmed_message) > 40 else "")
        new_conv_doc = {
            "user_email": email,
            "user_id": user_id,
            "title": title,
            "messages": [user_msg_doc, ai_msg_doc],
            "created_at": now_iso,
            "updated_at": now_iso,
        }
        try:
            res = conversations_col.insert_one(new_conv_doc)
            inserted_id = getattr(res, "inserted_id", None)
            if not res or not inserted_id:
                raise RuntimeError("Failed to obtain inserted_id")
            conv_id_str = str(inserted_id)
        except HTTPException:
            raise
        except Exception as e:
            logger.error("Failed to insert new conversation: %s", type(e).__name__)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Chat storage unavailable",
            )

    return {
        "reply": reply,
        "status": "success",
        "conversation_id": conv_id_str,
        "action": None,
    }


# ─────────────────────────────────────────────────────────────
# CHECKPOINT 4A: ACTION CONFIRMATION & CANCELLATION
# ─────────────────────────────────────────────────────────────

async def _process_action_decision(
    conversation_id: str,
    action_id: str,
    decision: str,
    current_user: dict,
) -> Dict[str, Any]:
    if not conversation_id or not action_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing conversation_id or action_id",
        )

    try:
        conv_obj_id = ObjectId(conversation_id)
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    if conversations_col is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Chat storage unavailable",
        )

    email = current_user.get("email") or ""
    user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else None
    query_or: List[Dict[str, Any]] = [{"user_email": email}]
    if user_id:
        query_or.append({"user_id": user_id})

    # 1. Verify conversation exists and belongs to owner
    conv = conversations_col.find_one({"_id": conv_obj_id, "$or": query_or})
    if not conv:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    # 2. Verify pending action exists and matches action_id
    pending = conv.get("pending_action")
    if not pending or pending.get("id") != action_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Action not found or expired",
        )

    current_status = pending.get("status")
    if current_status == "cancelled":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Action already cancelled",
        )

    today_vn = datetime.now(VN_TZ).strftime("%Y-%m-%d")
    target_date = pending.get("date") or today_vn
    now_utc = datetime.utcnow()
    now_iso = datetime.now(timezone.utc).isoformat()
    amount_to_add = int(pending.get("amount_ml") or 250)

    # 3. Handle Cancel
    if decision == "cancel":
        if current_status in ("processing", "confirmed"):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Action already confirmed",
            )
        if water_col is not None:
            already_applied = water_col.find_one({
                "user_email": email,
                "date": target_date,
                "applied_actions": action_id,
            })
            if already_applied:
                try:
                    conversations_col.update_one(
                        {"_id": conv_obj_id},
                        {"$set": {"pending_action.status": "confirmed"}}
                    )
                except Exception:
                    pass
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Action already confirmed",
                )

        update_cancel = conversations_col.update_one(
            {
                "_id": conv_obj_id,
                "$or": query_or,
                "pending_action.id": action_id,
                "pending_action.status": "pending",
            },
            {
                "$set": {
                    "pending_action.status": "cancelled",
                    "pending_action.cancelled_at": now_iso,
                    "updated_at": now_iso,
                }
            }
        )
        matched_count = getattr(update_cancel, "matched_count", None)
        if matched_count is not None and matched_count == 0:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Action already processed",
            )

        cancel_msg = "Đã hủy thao tác thêm nước."
        ai_msg_doc = {"role": "assistant", "content": cancel_msg, "created_at": now_iso}
        try:
            conversations_col.update_one(
                {"_id": conv_obj_id},
                {
                    "$push": {"messages": ai_msg_doc},
                    "$set": {"updated_at": now_iso},
                }
            )
        except Exception as e:
            logger.warning("Failed to record cancel message: %s", type(e).__name__)

        return {
            "status": "cancelled",
            "message": cancel_msg,
            "action_id": action_id,
            "conversation_id": str(conv_obj_id),
        }

    # 4. Handle Confirm: require water_col
    if water_col is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Water storage unavailable",
        )

    if current_status == "pending":
        try:
            update_lock = conversations_col.update_one(
                {
                    "_id": conv_obj_id,
                    "$or": query_or,
                    "pending_action.id": action_id,
                    "pending_action.status": "pending",
                },
                {
                    "$set": {
                        "pending_action.status": "processing",
                        "pending_action.processing_at": now_iso,
                        "updated_at": now_iso,
                    }
                }
            )
        except Exception as e:
            logger.error("Failed to update action lock: %s", type(e).__name__)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database error while confirming action",
            )
        matched_count = getattr(update_lock, "matched_count", None)
        if matched_count is not None and matched_count == 0:
            latest = conversations_col.find_one({"_id": conv_obj_id})
            latest_status = (latest.get("pending_action") or {}).get("status") if latest else None
            if latest_status == "cancelled":
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Action already cancelled",
                )
            if latest_status not in ("processing", "confirmed"):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Action already processed",
                )
    elif current_status not in ("processing", "confirmed"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"Action already {current_status}",
        )

    # Step A: Check if action_id marker already exists in water_col
    already_doc = water_col.find_one({
        "user_email": email,
        "date": target_date,
        "applied_actions": action_id,
    })

    write_error = None
    if not already_doc:
        # Step B: Atomic write with bounded retry for upsert / DuplicateKeyError race
        max_retries = 3
        for attempt in range(max_retries):
            try:
                already_check = water_col.find_one({
                    "user_email": email,
                    "date": target_date,
                    "applied_actions": action_id,
                })
                if already_check:
                    write_error = None
                    break

                doc = water_col.find_one({"user_email": email, "date": target_date})
                if doc:
                    res = water_col.update_one(
                        {
                            "_id": doc["_id"],
                            "applied_actions": {"$ne": action_id},
                        },
                        {
                            "$inc": {"amount_ml": amount_to_add, "version": 1},
                            "$addToSet": {"applied_actions": action_id},
                            "$set": {"updated_at": now_utc},
                        }
                    )
                    if getattr(res, "matched_count", 1) == 0:
                        if water_col.find_one({
                            "user_email": email,
                            "date": target_date,
                            "applied_actions": action_id,
                        }):
                            write_error = None
                            break
                        continue
                    write_error = None
                    break
                else:
                    water_col.update_one(
                        {
                            "user_email": email,
                            "date": target_date,
                            "applied_actions": {"$ne": action_id},
                        },
                        {
                            "$inc": {"amount_ml": amount_to_add, "version": 1},
                            "$addToSet": {"applied_actions": action_id},
                            "$setOnInsert": {
                                "created_at": now_utc,
                            },
                            "$set": {
                                "updated_at": now_utc,
                            },
                        },
                        upsert=True,
                    )
                    write_error = None
                    break
            except Exception as e:
                err_str = str(e).lower()
                if "duplicate key" in err_str or "e11000" in err_str:
                    logger.info("Upsert race caught DuplicateKeyError on attempt %d, retrying", attempt + 1)
                    continue
                logger.error("Error during water write attempt %d: %s", attempt + 1, type(e).__name__)
                write_error = e
                break

    if write_error is not None:
        logger.error("Water write encountered error without clean completion: %s", type(write_error).__name__)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database error while logging water",
        )

    # Step C: Verify marker in water_logs
    verified_doc = water_col.find_one({
        "user_email": email,
        "date": target_date,
        "applied_actions": action_id,
    })
    if not verified_doc:
        logger.error("Water marker verification failed for action_id=%s on date=%s", action_id, target_date)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database error while logging water",
        )

    # Step D: Marker verified, complete conversation status to confirmed
    try:
        conversations_col.update_one(
            {
                "_id": conv_obj_id,
                "$or": query_or,
                "pending_action.id": action_id,
            },
            {
                "$set": {
                    "pending_action.status": "confirmed",
                    "pending_action.confirmed_at": now_iso,
                    "updated_at": now_iso,
                }
            }
        )
    except Exception as e:
        logger.warning("Failed to update conversation status to confirmed: %s", type(e).__name__)

    # Step E: Record confirmation message in conversation history
    new_total = int(verified_doc.get("amount_ml") or amount_to_add)
    confirm_msg = f"Đã thêm {amount_to_add} ml nước vào nhật ký hôm nay của bạn. Tổng hiện tại: {new_total} ml."

    ai_msg_doc = {
        "role": "assistant",
        "content": confirm_msg,
        "action_id": action_id,
        "created_at": now_iso,
    }
    try:
        conversations_col.update_one(
            {
                "_id": conv_obj_id,
                "$or": query_or,
                "messages.action_id": {"$ne": action_id},
            },
            {
                "$push": {"messages": ai_msg_doc},
                "$set": {"updated_at": now_iso},
            }
        )
    except Exception as e:
        logger.warning("Failed to record confirmation message: %s", type(e).__name__)

    return {
        "status": "success",
        "message": confirm_msg,
        "amount_ml": new_total,
        "added_ml": amount_to_add,
        "action_id": action_id,
        "conversation_id": str(conv_obj_id),
    }


@router.post("/actions/confirm")
async def confirm_action(
    request: ActionDecisionRequest,
    current_user: dict = Depends(get_current_chat_user),
):
    return await _process_action_decision(request.conversation_id, request.action_id, "confirm", current_user)


@router.post("/actions/cancel")
async def cancel_action(
    request: ActionDecisionRequest,
    current_user: dict = Depends(get_current_chat_user),
):
    return await _process_action_decision(request.conversation_id, request.action_id, "cancel", current_user)


@router.post("/action")
async def handle_action(
    request: ActionDecisionRequest,
    current_user: dict = Depends(get_current_chat_user),
):
    decision = (request.decision or "confirm").lower().strip()
    return await _process_action_decision(request.conversation_id, request.action_id, decision, current_user)
```

---

## 3. Frontend Contract (Flutter)

### 3.1 Các Model, Entity, DTO Đại Diện Cho Chat Message, Request, Response & Nudge

#### File: `frontend/lib/controllers/chat_controller.dart` (Phần Model & State)
```dart
// --- 1. MODEL TIN NHẮN ---
class ChatMessage {
  final String role;
  final String content;
  final bool isTyping;

  ChatMessage({
    required this.role,
    required this.content,
    this.isTyping = false,
  });
}

// --- 1b. MODEL CONVERSATION SUMMARY ---
class ChatConversationSummary {
  final String id;
  final String title;
  final String updatedAt;
  final String createdAt;

  ChatConversationSummary({
    required this.id,
    required this.title,
    this.updatedAt = '',
    this.createdAt = '',
  });

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    return ChatConversationSummary(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Cuộc trò chuyện',
      updatedAt: json['updated_at']?.toString() ?? json['created_at']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

// --- 2. FOOD PHOTO ANALYSIS STATE ---
enum FoodAnalysisStatus {
  idle,
  analyzing,
  success,
  failure,
}

class ChatFoodAnalysisState {
  final FoodAnalysisStatus status;
  final String? imagePath;
  final XFile? imageFile;
  final String? userCaption;
  final AIAnalysisResult? result;
  final String? errorMessage;
  final bool isMealLogged;

  const ChatFoodAnalysisState({
    required this.status,
    this.imagePath,
    this.imageFile,
    this.userCaption,
    this.result,
    this.errorMessage,
    this.isMealLogged = false,
  });

  ChatFoodAnalysisState copyWith({
    FoodAnalysisStatus? status,
    String? imagePath,
    XFile? imageFile,
    String? userCaption,
    AIAnalysisResult? result,
    String? errorMessage,
    bool? isMealLogged,
  }) {
    return ChatFoodAnalysisState(
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      imageFile: imageFile ?? this.imageFile,
      userCaption: userCaption ?? this.userCaption,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      isMealLogged: isMealLogged ?? this.isMealLogged,
    );
  }
}

// --- 3. STATE ---
class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? errorMessage;
  final String? failedUserMessage;
  final ChatFoodAnalysisState? foodAnalysisState;
  final String? activeConversationId;
  final List<ChatConversationSummary> recentConversations;
  final bool isLoadingHistory;
  final Map<String, dynamic>? pendingAction;

  ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.errorMessage,
    this.failedUserMessage,
    this.foodAnalysisState,
    this.activeConversationId,
    this.recentConversations = const [],
    this.isLoadingHistory = false,
    this.pendingAction,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    String? failedUserMessage,
    bool clearFailedUserMessage = false,
    ChatFoodAnalysisState? foodAnalysisState,
    bool clearFoodAnalysis = false,
    String? activeConversationId,
    bool clearActiveConversation = false,
    List<ChatConversationSummary>? recentConversations,
    bool? isLoadingHistory,
    Map<String, dynamic>? pendingAction,
    bool clearPendingAction = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      failedUserMessage: clearFailedUserMessage
          ? null
          : (failedUserMessage ?? this.failedUserMessage),
      foodAnalysisState: clearFoodAnalysis
          ? null
          : (foodAnalysisState ?? this.foodAnalysisState),
      activeConversationId: clearActiveConversation
          ? null
          : (activeConversationId ?? this.activeConversationId),
      recentConversations: recentConversations ?? this.recentConversations,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      pendingAction: clearPendingAction
          ? null
          : (pendingAction ?? this.pendingAction),
    );
  }
}
```

#### File: `frontend/lib/models/saman_nudge.dart`
```dart
import 'package:flutter/foundation.dart';

/// Lightweight explicit model for a proactive coaching nudge or reminder in Saman Chat (State 04).
///
/// Designed to be presentation-only and transient. Never persisted or inserted into
/// persistent ChatMessage history, and never sent to /api/chat.
@immutable
class SamanNudge {
  final String id;
  final String message;
  final String? supportingLine;
  final DateTime? timestamp;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String secondaryLabel;
  final VoidCallback? onSecondary;
  final String? promptToSend;

  const SamanNudge({
    this.id = 'default_nudge',
    required this.message,
    this.supportingLine,
    this.timestamp,
    this.primaryLabel = 'Plan dinner',
    this.onPrimary,
    this.secondaryLabel = 'Later',
    this.onSecondary,
    this.promptToSend,
  });

  SamanNudge copyWith({
    String? id,
    String? message,
    String? supportingLine,
    DateTime? timestamp,
    String? primaryLabel,
    VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    String? promptToSend,
  }) {
    return SamanNudge(
      id: id ?? this.id,
      message: message ?? this.message,
      supportingLine: supportingLine ?? this.supportingLine,
      timestamp: timestamp ?? this.timestamp,
      primaryLabel: primaryLabel ?? this.primaryLabel,
      onPrimary: onPrimary ?? this.onPrimary,
      secondaryLabel: secondaryLabel ?? this.secondaryLabel,
      onSecondary: onSecondary ?? this.onSecondary,
      promptToSend: promptToSend ?? this.promptToSend,
    );
  }
}

/// Helper to build a safe, grounded Saman proactive nudge from real nutrition & workout targets.
class SamanNudgeHelper {
  const SamanNudgeHelper._();

  static SamanNudge? createNutritionNudge({
    required int consumedCalories,
    required int targetCalories,
    required int consumedProtein,
    required int targetProtein,
    String? tomorrowSession,
    DateTime? timestamp,
    VoidCallback? onPrimary,
    VoidCallback? onSecondary,
  }) {
    final remainingCalories = (targetCalories - consumedCalories).clamp(0, 9999);
    final remainingProtein = (targetProtein - consumedProtein).clamp(0, 9999);
    if (remainingCalories <= 0 && remainingProtein <= 0) return null;

    final sessionSuffix = tomorrowSession != null
        ? " before tomorrow’s $tomorrowSession session."
        : ".";

    return SamanNudge(
      id: 'nutrition_gap_nudge',
      message:
          'You still have $remainingCalories kcal and ${remainingProtein}g protein left today. A high-protein dinner would close most of the gap$sessionSuffix',
      supportingLine:
          '• $consumedCalories / $targetCalories kcal · ${remainingProtein}g protein remaining',
      timestamp: timestamp ?? DateTime.now(),
      primaryLabel: 'Plan dinner',
      secondaryLabel: 'Later',
      promptToSend:
          'Plan a high-protein dinner based on my remaining nutrition targets ($remainingCalories kcal, ${remainingProtein}g protein).',
      onPrimary: onPrimary,
      onSecondary: onSecondary,
    );
  }
}
```

#### File: `frontend/lib/models/ai_analysis_result.dart`
```dart
class FoodPrediction {
  final String label;
  final String foodName;
  final double confidence;

  const FoodPrediction({
    required this.label,
    required this.foodName,
    required this.confidence,
  });

  factory FoodPrediction.fromJson(Map<String, dynamic> json) => FoodPrediction(
        label: json['label'] as String,
        foodName: json['food_name'] as String,
        confidence: (json['confidence'] as num).toDouble(),
      );
}

class AIAnalysisResult {
  final String foodName;
  final String foodLabel;
  final double confidence;
  final bool lowConfidence;
  final double grams;
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final Map<String, dynamic> per100g;
  final String nutritionSource;
  final List<FoodPrediction> top3;

  const AIAnalysisResult({
    required this.foodName,
    required this.foodLabel,
    required this.confidence,
    required this.lowConfidence,
    required this.grams,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.per100g,
    required this.nutritionSource,
    required this.top3,
  });

  factory AIAnalysisResult.fromJson(Map<String, dynamic> json) {
    final nutrition = json['nutrition'] as Map<String, dynamic>? ?? {};
    final per100g = json['per_100g'] as Map<String, dynamic>? ?? {};

    return AIAnalysisResult(
      foodName: json['food_name'] as String? ?? 'Unknown',
      foodLabel: json['food_label'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      lowConfidence: json['low_confidence'] as bool? ?? false,
      grams: (json['grams'] as num?)?.toDouble() ?? 100.0,
      calories: (nutrition['calories'] as num?)?.toDouble() ?? 0.0,
      protein: (nutrition['protein'] as num?)?.toDouble() ?? 0.0,
      carbs: (nutrition['carbs'] as num?)?.toDouble() ?? 0.0,
      fat: (nutrition['fat'] as num?)?.toDouble() ?? 0.0,
      per100g: per100g,
      nutritionSource: json['nutrition_source'] as String? ?? 'unknown',
      top3: (json['top3_predictions'] as List<dynamic>? ?? [])
          .map((e) => FoodPrediction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  AIAnalysisResult withGrams(double newGrams) {
    if (per100g.isEmpty) return this;
    final ratio = newGrams / 100.0;
    return AIAnalysisResult(
      foodName: foodName,
      foodLabel: foodLabel,
      confidence: confidence,
      lowConfidence: lowConfidence,
      grams: newGrams,
      calories: ((per100g['calories'] as num?)?.toDouble() ?? calories) * ratio,
      protein: ((per100g['protein'] as num?)?.toDouble() ?? protein) * ratio,
      carbs: ((per100g['carbs'] as num?)?.toDouble() ?? carbs) * ratio,
      fat: ((per100g['fat'] as num?)?.toDouble() ?? fat) * ratio,
      per100g: per100g,
      nutritionSource: nutritionSource,
      top3: top3,
    );
  }

  AIAnalysisResult withLabel(FoodPrediction selected) {
    return AIAnalysisResult(
      foodName: selected.foodName,
      foodLabel: selected.label,
      confidence: selected.confidence,
      lowConfidence: selected.confidence < 0.40,
      grams: grams,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      per100g: per100g,
      nutritionSource: nutritionSource,
      top3: top3,
    );
  }
}
```

---

### 3.2 URL Endpoint, Headers & Toàn Bộ Logic Gọi API Bên Frontend

#### URL Endpoints Được Sử Dụng Cho Chat:
1. `POST ${ApiConfig.baseUrl}/api/chat`
   - **Payload**:
     ```json
     {
       "message": "string",
       "context": { "profile": {...}, "daily_stats": {...}, "system_instruction": "..." },
       "history": [ { "role": "user|assistant", "content": "..." } ],
       "conversation_id": "string (optional)"
     }
     ```
   - **Response**:
     ```json
     {
       "reply": "string",
       "conversation_id": "string",
       "status": "success",
       "action": { "id": "...", "type": "log_water", "amount_ml": 250, "status": "pending" } | null
     }
     ```
2. `GET ${ApiConfig.baseUrl}/api/chat/conversations`
   - Lấy danh sách cuộc trò chuyện gần đây.
3. `GET ${ApiConfig.baseUrl}/api/chat/conversations/{conversation_id}`
   - Lấy chi tiết lịch sử tin nhắn & pending action.
4. `POST ${ApiConfig.baseUrl}/api/chat/actions/confirm`
   - **Payload**: `{"conversation_id": "...", "action_id": "..."}`
5. `POST ${ApiConfig.baseUrl}/api/chat/actions/cancel`
   - **Payload**: `{"conversation_id": "...", "action_id": "..."}`

#### Headers (Do `frontend/lib/services/api_client.dart` inject qua Dio Interceptor):
- `Content-Type`: `application/json; charset=utf-8`
- `Authorization`: `Bearer <auth_token | jwt_token>` (lấy từ `FlutterSecureStorage`)
- `Cache-Control`: `no-cache`

#### File: `frontend/lib/controllers/chat_controller.dart` (Toàn Bộ Controller Implementation)
```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/ai_analysis_result.dart';
import '../services/api_client.dart';
import '../services/nutrition_service.dart';

// --- CONTROLLER TỐI ƯU ---
class ChatController extends StateNotifier<ChatState> {
  final Ref ref;
  final NutritionService _nutritionService;
  int _requestEpoch = 0;
  String? _currentAccountToken;

  ChatController(this.ref, {NutritionService? nutritionService})
      : _nutritionService = nutritionService ?? NutritionService(),
        super(ChatState(messages: []));

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final userMsg = ChatMessage(role: 'user', content: trimmed);
    state = state.copyWith(
      messages: [...state.messages, userMsg],
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
      clearPendingAction: true,
    );

    await _sendRequest(trimmed);
  }

  Future<void> retry() async {
    final textToRetry = state.failedUserMessage ??
        (state.messages.isNotEmpty && state.messages.last.role == 'user'
            ? state.messages.last.content
            : null);
    if (textToRetry == null) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
      clearPendingAction: true,
    );

    await _sendRequest(textToRetry);
  }

  void clearError() {
    state = state.copyWith(
      clearError: true,
      clearFailedUserMessage: true,
    );
  }

  Future<void> _sendRequest(String text) async {
    final epoch = ++_requestEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();

      final userContext = await _buildUserContext(prefs);

      final payload = <String, dynamic>{
        "message": text,
        "context": userContext,
        "history": _getLastMessages(5),
      };
      if (state.activeConversationId != null &&
          state.activeConversationId!.isNotEmpty) {
        payload["conversation_id"] = state.activeConversationId;
      }

      final response = await ApiClient.dio.post(
        "${ApiConfig.baseUrl}/api/chat",
        data: payload,
      );

      if (_requestEpoch != epoch || !mounted) return;

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final aiReply = data['reply'];
        final returnedConvId = data['conversation_id']?.toString();
        final returnedAction = data['action'] is Map
            ? Map<String, dynamic>.from(data['action'] as Map)
            : null;

        final botMsg = ChatMessage(role: 'assistant', content: aiReply);

        String? nextActiveId = state.activeConversationId;
        if (returnedConvId != null && returnedConvId.isNotEmpty) {
          nextActiveId = returnedConvId;
        }

        if (!mounted || _requestEpoch != epoch) return;
        state = state.copyWith(
          messages: [...state.messages, botMsg],
          activeConversationId: nextActiveId,
          pendingAction: returnedAction,
          clearPendingAction: returnedAction == null,
          isLoading: false,
          clearError: true,
          clearFailedUserMessage: true,
        );

        if (mounted) {
          loadConversations(loadLatest: false);
        }
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (_requestEpoch != epoch || !mounted) return;
      debugPrint("Chat Error: $e");
      state = state.copyWith(
        isLoading: false,
        errorMessage: "I couldn't complete that response.",
        failedUserMessage: text,
      );
    }
  }

  Future<void> _confirmAction(String conversationId, String actionId) async {
    if (conversationId.isEmpty || actionId.isEmpty) return;
    final epoch = ++_requestEpoch;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );

    try {
      final response = await ApiClient.dio.post(
        "${ApiConfig.baseUrl}/api/chat/actions/confirm",
        data: {
          "conversation_id": conversationId,
          "action_id": actionId,
        },
      );

      if (_requestEpoch != epoch || !mounted) return;

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final message = data['message']?.toString() ??
            "Đã thêm 250 ml nước vào nhật ký hôm nay của bạn.";

        final botMsg = ChatMessage(role: 'assistant', content: message);
        state = state.copyWith(
          messages: [...state.messages, botMsg],
          clearPendingAction: true,
          isLoading: false,
          clearError: true,
          clearFailedUserMessage: true,
        );
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (_requestEpoch != epoch || !mounted) return;
      debugPrint("Confirm Action Error: $e");
      state = state.copyWith(
        isLoading: false,
        errorMessage: "I couldn't confirm that action.",
      );
    }
  }

  Future<void> _cancelAction(String conversationId, String actionId) async {
    if (conversationId.isEmpty || actionId.isEmpty) return;
    final epoch = ++_requestEpoch;
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      clearFailedUserMessage: true,
    );

    try {
      final response = await ApiClient.dio.post(
        "${ApiConfig.baseUrl}/api/chat/actions/cancel",
        data: {
          "conversation_id": conversationId,
          "action_id": actionId,
        },
      );

      if (_requestEpoch != epoch || !mounted) return;

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        final message =
            data['message']?.toString() ?? "Đã hủy thao tác thêm nước.";

        final botMsg = ChatMessage(role: 'assistant', content: message);
        state = state.copyWith(
          messages: [...state.messages, botMsg],
          clearPendingAction: true,
          isLoading: false,
          clearError: true,
          clearFailedUserMessage: true,
        );
      } else {
        throw Exception("Server Error: ${response.statusCode}");
      }
    } catch (e) {
      if (_requestEpoch != epoch || !mounted) return;
      debugPrint("Cancel Action Error: $e");
      state = state.copyWith(
        isLoading: false,
        errorMessage: "I couldn't cancel that action.",
      );
    }
  }

  Future<void> loadConversations({bool loadLatest = false}) async {
    final epoch = ++_requestEpoch;
    try {
      const storage = FlutterSecureStorage();
      final token = await storage.read(key: 'auth_token') ??
          await storage.read(key: 'jwt_token');

      if (_currentAccountToken != token) {
        if (_currentAccountToken != null || state.messages.isNotEmpty) {
          if (!mounted) return;
          state = ChatState(messages: [], recentConversations: []);
        }
      }
      _currentAccountToken = token;

      final response = await ApiClient.dio.get(
        "${ApiConfig.baseUrl}/api/chat/conversations",
      );

      if (_requestEpoch != epoch || !mounted) return;

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        List rawList = [];
        if (data is List) {
          rawList = data;
        } else if (data is Map && data['conversations'] is List) {
          rawList = data['conversations'] as List;
        }

        final summaries = rawList
            .map((item) => ChatConversationSummary.fromJson(
                item is Map<String, dynamic>
                    ? item
                    : Map<String, dynamic>.from(item as Map)))
            .toList();

        if (!mounted || _requestEpoch != epoch) return;
        state = state.copyWith(recentConversations: summaries);

        if (loadLatest && state.activeConversationId == null && summaries.isNotEmpty) {
          await loadConversation(summaries.first.id);
        }
      }
    } catch (e) {
      debugPrint("Failed to load conversations: $e");
    }
  }

  Future<void> loadConversation(String conversationId) async {
    final epoch = ++_requestEpoch;
    if (!mounted) return;
    state = state.copyWith(
      activeConversationId: conversationId,
      isLoadingHistory: true,
      clearError: true,
      clearFailedUserMessage: true,
    );

    try {
      final response = await ApiClient.dio.get(
        "${ApiConfig.baseUrl}/api/chat/conversations/$conversationId",
      );

      if (_requestEpoch != epoch || !mounted) return;

      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;

        final rawMessages = data['messages'] as List? ?? [];
        final loadedMessages = rawMessages.map<ChatMessage>((m) {
          final role = m['role']?.toString() ?? 'user';
          final content = m['content']?.toString() ?? '';
          return ChatMessage(role: role, content: content);
        }).toList();

        final rawPendingAction = data['pending_action'] is Map
            ? Map<String, dynamic>.from(data['pending_action'] as Map)
            : null;

        if (!mounted || _requestEpoch != epoch) return;
        state = state.copyWith(
          messages: loadedMessages,
          activeConversationId: conversationId,
          pendingAction: rawPendingAction,
          clearPendingAction: rawPendingAction == null,
          isLoadingHistory: false,
          isLoading: false,
          clearError: true,
          clearFailedUserMessage: true,
        );
      } else {
        throw Exception("Status ${response.statusCode}");
      }
    } catch (e) {
      if (_requestEpoch != epoch || !mounted) return;
      debugPrint("Failed to load conversation details: $e");
      state = state.copyWith(
        isLoadingHistory: false,
        isLoading: false,
        errorMessage: "I couldn't load that conversation.",
      );
    }
  }

  void newConversation() {
    _requestEpoch++;
    state = state.copyWith(
      messages: [],
      clearActiveConversation: true,
      clearPendingAction: true,
      clearError: true,
      clearFailedUserMessage: true,
      clearFoodAnalysis: true,
      isLoading: false,
      isLoadingHistory: false,
    );
  }

  Future<void> analyzeFoodPhoto(XFile file, {String? caption}) async {
    state = state.copyWith(
      foodAnalysisState: ChatFoodAnalysisState(
        status: FoodAnalysisStatus.analyzing,
        imagePath: file.path,
        imageFile: file,
        userCaption: caption ?? 'Can I fit this into today?',
      ),
      clearError: true,
      clearFailedUserMessage: true,
    );

    try {
      final analysisResult = await _nutritionService.analyzeFoodImage(file);

      if (analysisResult == null ||
          (analysisResult.calories <= 0 && analysisResult.lowConfidence)) {
        state = state.copyWith(
          foodAnalysisState: ChatFoodAnalysisState(
            status: FoodAnalysisStatus.failure,
            imagePath: file.path,
            imageFile: file,
            userCaption: caption ?? 'Can I fit this into today?',
            errorMessage:
                "I couldn't estimate this meal confidently from the photo.",
          ),
        );
      } else {
        state = state.copyWith(
          foodAnalysisState: ChatFoodAnalysisState(
            status: FoodAnalysisStatus.success,
            imagePath: file.path,
            imageFile: file,
            userCaption: caption ?? 'Can I fit this into today?',
            result: analysisResult,
          ),
        );
      }
    } catch (e) {
      debugPrint("Food photo analysis error: $e");
      state = state.copyWith(
        foodAnalysisState: ChatFoodAnalysisState(
          status: FoodAnalysisStatus.failure,
          imagePath: file.path,
          imageFile: file,
          userCaption: caption ?? 'Can I fit this into today?',
          errorMessage:
              "I couldn't estimate this meal confidently from the photo.",
        ),
      );
    }
  }

  void markMealLogged() {
    if (state.foodAnalysisState != null) {
      state = state.copyWith(
        foodAnalysisState: state.foodAnalysisState!.copyWith(
          isMealLogged: true,
        ),
      );
    }
  }

  void clearFoodAnalysis() {
    state = state.copyWith(clearFoodAnalysis: true);
  }

  void clearChat() {
    newConversation();
  }

  Future<Map<String, dynamic>> _buildUserContext(
      SharedPreferences prefs) async {
    String name = prefs.getString('user_name') ?? "Bạn";

    int height = _safeParseInt(prefs.get('user_height'), 170);
    double weight = _safeParseDouble(prefs.get('user_weight'), 65.0);
    int age = _safeParseInt(prefs.get('user_age'), 25);
    String gender = prefs.getString('user_gender') ?? "Nam";

    double tdee = _safeParseDouble(prefs.get('user_tdee'), 2200.0);
    String goal = prefs.getString('user_goal') ?? "Duy trì cân nặng";

    double caloriesConsumed =
        _safeParseDouble(prefs.get('daily_calories_in'), 0.0);

    return {
      "profile": {
        "name": name,
        "biometrics": "$height cm, $weight kg, $age tuổi, $gender",
        "tdee": tdee,
        "goal": goal,
      },
      "daily_stats": {
        "eaten": caloriesConsumed,
        "remaining": tdee - caloriesConsumed,
      },
      "system_instruction": """
        YOU ARE:
You are **Saman AI Coach**, a personal trainer and nutrition expert dedicated exclusively to helping **$name** achieve their fitness goal efficiently and safely.

FIXED USER DATA (DO NOT OVERRIDE OR ASSUME):
- Height: $height cm
- Weight: $weight kg
- Age: $age
- Gender: $gender
- Daily TDEE: $tdee kcal
- Goal: $goal
- Calories consumed today: $caloriesConsumed kcal
- Remaining calories today: ${tdee - caloriesConsumed} kcal

CORE RULES (MANDATORY):
1. All advice MUST be strictly based on TDEE, remaining calories, and the stated goal.
2. Do NOT give generic, motivational, or vague advice.
3. Do NOT contradict or reinterpret provided data.
4. If information is missing, make a reasonable estimation and clearly state it as an estimate.

QUERY HANDLING LOGIC:
- Food-related questions:
  - Estimate calories and macronutrients (protein, carbs, fats).
  - State clearly whether the food fits the current goal and remaining calories.
- Training-related questions:
  - Recommend exercises aligned with the goal and current calorie status.
- If a choice would exceed TDEE:
  - Give a short warning.
  - Propose a better alternative.
- If remaining calories are high:
  - Suggest optimal food or meal options to use them effectively.

RESPONSE STYLE:
- Concise and direct.
- Professional and precise.
- No emojis, no storytelling, no unnecessary explanations.

OUTPUT PRIORITY ORDER:
1. Numbers and calculations
2. Clear judgment (good / acceptable / not recommended)
3. Actionable next step

      """
    };
  }

  int _safeParseInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    if (value is double) return value.toInt();
    return defaultValue;
  }

  double _safeParseDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  List<Map<String, String>> _getLastMessages(int count) {
    final msgs = state.messages;
    final startIndex = msgs.length > count ? msgs.length - count : 0;
    return msgs
        .sublist(startIndex)
        .map((m) => {"role": m.role, "content": m.content})
        .toList();
  }
}

// --- PROVIDER ---
final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) {
  return ChatController(ref);
});

// --- ACTION EXTENSION & DELEGATE ---
abstract class ChatActionDelegate {
  Future<void> handleConfirmAction(String conversationId, String actionId);
  Future<void> handleCancelAction(String conversationId, String actionId);
}

extension ChatControllerActionExtension on ChatController {
  Future<void> confirmAction(String conversationId, String actionId) {
    if (this is ChatActionDelegate) {
      return (this as ChatActionDelegate)
          .handleConfirmAction(conversationId, actionId);
    }
    return _confirmAction(conversationId, actionId);
  }

  Future<void> cancelAction(String conversationId, String actionId) {
    if (this is ChatActionDelegate) {
      return (this as ChatActionDelegate)
          .handleCancelAction(conversationId, actionId);
    }
    return _cancelAction(conversationId, actionId);
  }
}
```
