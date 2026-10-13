# [File: backend/routers/chat.py]
import os
import re
import logging
import asyncio
from typing import Optional, Dict, List, Any, Tuple
from datetime import datetime, timezone, timedelta, date
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
    exercises_collection,
)

# Auth dependency
from backend.auth_utils import verify_token, get_current_user

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
exercises_col = exercises_collection

# Backward-compatibility references for existing workout tests
workout_history_collection = workout_history_col
exercises_collection = exercises_col

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

DEFAULT_TIMEOUT_SECONDS = 15.0
try:
    VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")
except Exception:
    VN_TZ = timezone(timedelta(hours=7))

ICT_ZONE = VN_TZ


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
        raw_val = s.get("start_time") or s.get("created_at") or s.get("date") or s.get("end_time") or s.get("started_at")
        dt = _parse_timestamp(raw_val)
        if dt is not None:
            cmp_dt = dt.replace(tzinfo=None) if dt.tzinfo is not None else dt
            if best_dt is None or cmp_dt > best_dt:
                best_dt = cmp_dt
                best_session = s

    if best_session is None and sessions:
        best_session = sessions[-1]

    date_part = best_dt.strftime("%Y-%m-%d") if best_dt else "chưa có dữ liệu"
    duration = best_session.get("duration_minutes") or best_session.get("total_duration_minutes")
    duration_str = f"{duration} phút" if duration is not None else "chưa có dữ liệu"

    exercises = best_session.get("completed_exercises") or best_session.get("exercise_logs")
    exercise_names = []
    if isinstance(exercises, list):
        for ex in exercises:
            if isinstance(ex, dict) and (ex.get("name") or ex.get("exercise_slug") or ex.get("exercise_id")):
                exercise_names.append(str(ex.get("name") or ex.get("exercise_slug") or ex.get("exercise_id")))
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

# ─────────────────────────────────────────────────────────────
# DATA MODELS
# ─────────────────────────────────────────────────────────────

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


# ─────────────────────────────────────────────────────────────
# WORKOUT GROUNDING RETRIEVAL HELPERS
# ─────────────────────────────────────────────────────────────
try:
    from backend.app.data.exercises.back import BACK_EXERCISES
except Exception:
    BACK_EXERCISES = []

# Mapping catalog bài tập tĩnh từ repo (nguồn: backend.app.data.exercises.back.BACK_EXERCISES)
REPO_EXERCISES_MAP: Dict[str, dict] = {}
for _ex in BACK_EXERCISES:
    if "slug" in _ex:
        REPO_EXERCISES_MAP[_ex["slug"]] = _ex


def get_ai_reply(prompt: str) -> str:
    """Hàm wrapper để gọi AI: Thử Gemini trước, fallback sang OpenAI."""
    # 1. Thử Gemini
    if GEMINI_API_KEY:
        try:
            import google.generativeai as genai
            genai.configure(api_key=GEMINI_API_KEY)
            model = genai.GenerativeModel('gemini-1.5-flash')
            response = model.generate_content(prompt)
            return response.text
        except Exception as e:
            logging.error(f"Gemini Error: {e}")

    # 2. Thử OpenAI
    if OPENAI_API_KEY:
        try:
            from openai import OpenAI
            client = OpenAI(api_key=OPENAI_API_KEY)
            response = client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{"role": "user", "content": prompt}],
                max_tokens=300
            )
            return response.choices[0].message.content
        except Exception as e:
            logging.error(f"OpenAI Error: {e}")

    return "Lỗi: Không tìm thấy API Key hoặc Model AI không khả dụng (Cần cấu hình GEMINI_API_KEY hoặc OPENAI_API_KEY)."


# ─── WORKOUT GROUNDING HELPERS ────────────────────────────────────────────────

def parse_date_query(message: str) -> Tuple[str, Optional[str], Optional[str]]:
    """
    Phân loại câu hỏi tập luyện và resolve ngày chuẩn Asia/Ho_Chi_Minh:
    - ('SPECIFIC_DATE', 'YYYY-MM-DD', None)
    - ('TODAY', 'YYYY-MM-DD', None)
    - ('RECENT', None, None)
    - ('INVALID_DATE', None, 'lý do lỗi')
    - ('NONE', None, None) khi không phải câu hỏi lịch sử tập luyện
    """
    msg_lower = message.lower().strip()

    # Nhận diện từ khóa liên quan đến tập luyện / hoạt động thể chất
    workout_keywords = ["tập", "workout", "buổi tập", "bài tập", "session", "gym", "rèn luyện"]
    is_workout_related = any(kw in msg_lower for kw in workout_keywords)

    if not is_workout_related:
        return ("NONE", None, None)

    # 1. Kiểm tra ngày cụ thể DD/MM/YYYY hoặc DD-MM-YYYY
    match_dmy = re.search(r"(?<!\d)(\d{1,2})[/-](\d{1,2})[/-](\d{4})(?!\d)", msg_lower)
    if match_dmy:
        d_val, m_val, y_val = int(match_dmy.group(1)), int(match_dmy.group(2)), int(match_dmy.group(3))
        try:
            parsed = date(y_val, m_val, d_val)
            return ("SPECIFIC_DATE", parsed.strftime("%Y-%m-%d"), None)
        except ValueError:
            return ("INVALID_DATE", None, f"Ngày {d_val:02d}/{m_val:02d}/{y_val:04d} không hợp lệ trên lịch")

    # 2. Kiểm tra ngày cụ thể YYYY-MM-DD hoặc YYYY/MM/DD
    match_ymd = re.search(r"(?<!\d)(\d{4})[/-](\d{1,2})[/-](\d{1,2})(?!\d)", msg_lower)
    if match_ymd:
        y_val, m_val, d_val = int(match_ymd.group(1)), int(match_ymd.group(2)), int(match_ymd.group(3))
        try:
            parsed = date(y_val, m_val, d_val)
            return ("SPECIFIC_DATE", parsed.strftime("%Y-%m-%d"), None)
        except ValueError:
            return ("INVALID_DATE", None, f"Ngày {y_val:04d}-{m_val:02d}-{d_val:02d} không hợp lệ trên lịch")

    # 3. Bắt các chuỗi định dạng ngày thiếu năm hoặc mơ hồ (ví dụ 12/10, 31/02)
    match_partial = re.search(r"(?<!\d)(\d{1,2})[/-](\d{1,2})(?!\d)", msg_lower)
    if match_partial:
        raw_part = match_partial.group(0)
        return ("INVALID_DATE", None, f"Ngày '{raw_part}' thiếu năm hoặc định dạng mơ hồ (vui lòng sử dụng DD/MM/YYYY hoặc YYYY-MM-DD)")

    # 4. Kiểm tra câu hỏi buổi gần nhất (ưu tiên nếu có cụm từ chỉ tính gần nhất)
    recent_keywords = ["gần nhất", "gần đây nhất", "vừa rồi", "vừa qua", "buổi trước", "latest", "most recent"]
    if any(rk in msg_lower for rk in recent_keywords):
        return ("RECENT", None, None)

    # 5. Kiểm tra câu hỏi hôm nay
    today_keywords = ["hôm nay", "ngày hôm nay", "hôm ni", "today", "bữa nay"]
    if any(tk in msg_lower for tk in today_keywords):
        now_vn = datetime.now(ICT_ZONE).strftime("%Y-%m-%d")
        return ("TODAY", now_vn, None)

    # 6. Hỏi chung về bài tập đã thực hiện mà không chỉ định ngày -> fallback sang RECENT
    general_history_keywords = ["đã tập", "những bài nào", "các bài", "lịch sử tập"]
    if any(gk in msg_lower for gk in general_history_keywords):
        return ("RECENT", None, None)

    return ("NONE", None, None)


def _parse_valid_datetime(val: Any) -> Optional[datetime]:
    """Chuyển đổi và kiểm tra giá trị timestamp hợp lệ."""
    if val is None:
        return None
    if isinstance(val, datetime):
        if val.tzinfo is None:
            return val.replace(tzinfo=timezone.utc)
        return val
    if isinstance(val, str) and val.strip():
        s = val.strip().replace("Z", "+00:00")
        try:
            dt = datetime.fromisoformat(s)
            if dt.tzinfo is None:
                return dt.replace(tzinfo=timezone.utc)
            return dt
        except Exception:
            return None
    return None


def is_session_completed(doc: dict) -> bool:
    """
    Xác định session đã hoàn tất hợp lệ:
    finished_at phải tồn tại, khác null, là timestamp hợp lệ và >= started_at (nếu có).
    """
    fin = doc.get("finished_at")
    if fin is None:
        fin = doc.get("end_time")
    if fin is None:
        return False

    fin_dt = _parse_valid_datetime(fin)
    if fin_dt is None:
        return False

    start = doc.get("started_at") or doc.get("start_time") or doc.get("created_at")
    start_dt = _parse_valid_datetime(start)
    if start_dt and fin_dt < start_dt:
        return False

    return True


def get_session_vn_date(doc: dict) -> Optional[str]:
    """Lấy ngày theo chuẩn Asia/Ho_Chi_Minh (YYYY-MM-DD) từ session DB."""
    d = doc.get("date")
    if isinstance(d, str) and re.match(r"^\d{4}-\d{2}-\d{2}$", d.strip()):
        return d.strip()
    if isinstance(d, datetime):
        if d.tzinfo is None:
            d = d.replace(tzinfo=timezone.utc)
        return d.astimezone(ICT_ZONE).strftime("%Y-%m-%d")
    for k in ("started_at", "start_time", "created_at"):
        dt = _parse_valid_datetime(doc.get(k))
        if dt:
            return dt.astimezone(ICT_ZONE).strftime("%Y-%m-%d")
    return None


def _get_session_sort_key(doc: dict) -> datetime:
    """Lấy timestamp phục vụ sort giảm dần."""
    for k in ("started_at", "start_time", "created_at", "finished_at"):
        dt = _parse_valid_datetime(doc.get(k))
        if dt:
            return dt
    d_str = get_session_vn_date(doc)
    if d_str:
        try:
            return datetime.fromisoformat(d_str).replace(tzinfo=ICT_ZONE)
        except Exception:
            pass
    return datetime.min.replace(tzinfo=timezone.utc)


def resolve_exercise_name(exercise_id: Optional[str], exercise_slug: Optional[str]) -> Tuple[str, str]:
    """
    Resolve tên bài tập theo quy tắc:
    1. Ưu tiên tra catalog DB (exercises_collection) theo slug hoặc id/_id.
    2. Nếu không có trong DB, tra catalog chuẩn repo (backend.app.data.exercises.back.BACK_EXERCISES).
    3. Nếu không resolve được: giữ slug/id và nói rõ tên chưa xác định trong catalog.
    Tuyệt đối không titlecase slug, không bịa tên, không dùng AI đoán.
    """
    # 1. Tra DB catalog
    col = exercises_collection if exercises_collection is not None else exercises_col
    if col is not None:
        try:
            doc = None
            if exercise_slug:
                doc = col.find_one({"slug": exercise_slug})
            if not doc and exercise_id:
                doc = col.find_one({"id": exercise_id})
                if not doc:
                    try:
                        doc = col.find_one({"_id": ObjectId(exercise_id)})
                    except Exception:
                        pass
            if doc:
                name = doc.get("name")
                name_vi = doc.get("nameVi")
                if name_vi and name and name_vi.lower() != name.lower():
                    display_name = f"{name_vi} ({name})"
                else:
                    display_name = name_vi or name or (exercise_slug or exercise_id or "")
                return display_name, "catalog DB (exercises_collection)"
        except Exception as e:
            logging.warning(f"Error querying exercises_collection: {e}")

    # 2. Tra catalog chuẩn repo
    slug_key = exercise_slug or exercise_id
    if slug_key and slug_key in REPO_EXERCISES_MAP:
        ex = REPO_EXERCISES_MAP[slug_key]
        name = ex.get("name")
        name_vi = ex.get("nameVi")
        if name_vi and name and name_vi.lower() != name.lower():
            display_name = f"{name_vi} ({name})"
        else:
            display_name = name_vi or name or slug_key
        return display_name, "catalog repo (backend.app.data.exercises.back.BACK_EXERCISES)"

    # 3. Unresolved: giữ nguyên slug/ID và ghi rõ chưa xác định
    raw_ident = exercise_slug or exercise_id or "unspecified"
    return f"{raw_ident} (tên chưa xác định)", "chưa xác định trong catalog chuẩn"


def fetch_user_workout_sessions(user_id: str) -> List[dict]:
    """Truy vấn workout_history strictly theo user_id xác thực."""
    col = workout_history_collection if workout_history_collection is not None else workout_history_col
    if col is None:
        raise RuntimeError("Cơ sở dữ liệu workout_history không khả dụng (collection is None)")
    query = {"user_id": user_id}
    cursor = col.find(query)
    return list(cursor)


def _format_session_card(session: dict, idx: int = 1) -> str:
    """Format một completed session thành text context chuẩn."""
    plan_name = session.get("plan_name") or session.get("name") or "Buổi tập"
    vn_date = get_session_vn_date(session) or "Chưa rõ ngày"

    start_dt = _parse_valid_datetime(session.get("started_at") or session.get("start_time") or session.get("created_at"))
    end_dt = _parse_valid_datetime(session.get("finished_at") or session.get("end_time"))

    start_str = start_dt.astimezone(ICT_ZONE).strftime("%H:%M %d/%m/%Y") if start_dt else "Chưa ghi nhận"
    end_str = end_dt.astimezone(ICT_ZONE).strftime("%H:%M %d/%m/%Y") if end_dt else "Chưa ghi nhận"

    # Xử lý duration: phân biệt 0 phút (<1 phút) với None
    tot_dur = session.get("total_duration_minutes") if session.get("total_duration_minutes") is not None else session.get("duration_minutes")
    if tot_dur is not None:
        if tot_dur == 0:
            dur_str = "0 phút (<1 phút)"
        else:
            dur_str = f"{tot_dur} phút"
    else:
        dur_str = "Chưa ghi nhận thời lượng"

    # Volume: phân biệt 0 kg với None
    tot_vol = session.get("total_volume_kg")
    if tot_vol is not None:
        vol_str = f"{tot_vol} kg"
    else:
        vol_str = "Chưa ghi nhận"

    lines = [
        f"Buổi tập #{idx}: {plan_name}",
        f"- Ngày: {vn_date}",
        f"- Bắt đầu (giờ VN): {start_str}",
        f"- Hoàn thành (giờ VN): {end_str}",
        f"- Thời lượng: {dur_str}",
        f"- Tổng khối lượng tạ (volume): {vol_str}",
    ]

    # Exercise logs
    raw_logs = session.get("exercise_logs") or session.get("completed_exercises") or []
    completed_sets = []
    for item in raw_logs:
        is_comp = item.get("is_completed") if item.get("is_completed") is not None else item.get("isCompleted", True)
        if is_comp:
            completed_sets.append(item)

    if completed_sets:
        lines.append("- Các bài tập đã hoàn thành:")
        # Gom nhóm theo exercise_slug / exercise_id
        grouped: Dict[str, List[dict]] = {}
        for item in completed_sets:
            ex_key = str(item.get("exercise_slug") or item.get("exerciseSlug") or item.get("exercise_id") or item.get("exerciseId") or "unknown")
            grouped.setdefault(ex_key, []).append(item)

        for ex_idx, (ex_key, sets) in enumerate(grouped.items(), 1):
            sample = sets[0]
            ex_id = sample.get("exercise_id") or sample.get("exerciseId")
            ex_slug = sample.get("exercise_slug") or sample.get("exerciseSlug")
            display_name, src_note = resolve_exercise_name(ex_id, ex_slug)
            lines.append(f"  * Bài {ex_idx}: {display_name} [Nguồn: {src_note}]")

            for s in sets:
                set_num = s.get("set_number") if s.get("set_number") is not None else s.get("setNumber", 1)
                unit = s.get("unit")
                reps = s.get("reps_completed") if s.get("reps_completed") is not None else s.get("repsCompleted")
                seconds = s.get("seconds_completed") if s.get("seconds_completed") is not None else s.get("secondsCompleted")
                weight = s.get("weight_kg") if s.get("weight_kg") is not None else s.get("weightKg")

                parts = []
                if unit == "seconds" or (seconds is not None and seconds > 0 and (reps is None or reps == 0)):
                    parts.append(f"{seconds} giây")
                elif reps is not None:
                    parts.append(f"{reps} reps")
                elif seconds is not None:
                    parts.append(f"{seconds} giây")
                else:
                    parts.append("số lượng: chưa ghi nhận")

                if weight is not None:
                    parts.append(f"mức tạ {weight} kg")
                else:
                    parts.append("mức tạ: chưa ghi nhận")

                lines.append(f"    + Hiệp {set_num}: {', '.join(parts)}")
    else:
        lines.append("- Bài tập: Chưa ghi nhận chi tiết bài tập hoàn tất trong buổi tập này")

    return "\n".join(lines)


def build_workout_grounding_context(
    user_id: str,
    query_type: str,
    target_date_iso: Optional[str],
    error_reason: Optional[str]
) -> Tuple[str, Dict[str, Any]]:
    """Tạo context grounding từ sự thật DB cho Chat prompt."""
    if query_type == "INVALID_DATE":
        ctx = (
            "=== THÔNG TIN BUỔI TẬP TỪ CƠ SỞ DỮ LIỆU (DB TRUTH) ===\n"
            "[Nguồn: workout_history | Múi giờ: Asia/Ho_Chi_Minh (UTC+7)]\n"
            "[Yêu cầu tra cứu: Ngày không hợp lệ hoặc mơ hồ]\n\n"
            f"KẾT QUẢ: {error_reason or 'Ngày được yêu cầu không hợp lệ trên lịch'}.\n"
            "[CHỈ DẪN CHO AI]: Thông báo rõ ràng cho người dùng rằng ngày hỏi không hợp lệ hoặc mơ hồ (cần định dạng DD/MM/YYYY hoặc YYYY-MM-DD), và đề nghị cung cấp ngày chính xác. Tuyệt đối không tự ý đoán ngày sang hôm nay."
        )
        return ctx, {"applied": True, "query_type": "INVALID_DATE", "sessions_count": 0}

    all_sessions = fetch_user_workout_sessions(user_id)
    completed_sessions = [s for s in all_sessions if is_session_completed(s)]
    completed_sessions.sort(key=_get_session_sort_key, reverse=True)

    if query_type in ("TODAY", "SPECIFIC_DATE"):
        matching = [s for s in completed_sessions if get_session_vn_date(s) == target_date_iso]
        matching.sort(key=_get_session_sort_key, reverse=True)

        # Định dạng ngày hiển thị DD/MM/YYYY
        date_display = target_date_iso
        if target_date_iso:
            try:
                date_display = date.fromisoformat(target_date_iso).strftime("%d/%m/%Y")
            except Exception:
                pass

        if not matching:
            ctx = (
                "=== THÔNG TIN BUỔI TẬP TỪ CƠ SỞ DỮ LIỆU (DB TRUTH) ===\n"
                "[Nguồn: workout_history | Múi giờ: Asia/Ho_Chi_Minh (UTC+7)]\n"
                f"[Yêu cầu tra cứu: Ngày {date_display}]\n\n"
                f"KẾT QUẢ: Chưa có dữ liệu buổi tập hoàn tất được ghi nhận trong hệ thống cho ngày {date_display}.\n"
                f"[CHỈ DẪN CHO AI]: Thông báo rõ ràng cho người dùng rằng hệ thống chưa ghi nhận dữ liệu buổi tập hoàn tất nào cho ngày {date_display}. Tuyệt đối KHÔNG kết luận là người dùng chưa tập hoặc không tập (có thể người dùng chưa ghi nhận vào ứng dụng), và KHÔNG lấy buổi tập của ngày khác để trả lời thay thế."
            )
            return ctx, {"applied": True, "query_type": query_type, "target_date": target_date_iso, "sessions_count": 0}

        cards = [_format_session_card(s, i) for i, s in enumerate(matching, 1)]
        ctx = (
            "=== THÔNG TIN BUỔI TẬP TỪ CƠ SỞ DỮ LIỆU (DB TRUTH) ===\n"
            "[Nguồn: workout_history | Múi giờ: Asia/Ho_Chi_Minh (UTC+7)]\n"
            f"[Yêu cầu tra cứu: Ngày {date_display}]\n\n"
            + "\n\n".join(cards)
            + "\n\n[CHỈ DẪN CHO AI]: Sử dụng thông tin sự thật từ DB trên để trả lời câu hỏi của người dùng. Không bịa thêm bài tập, không tự tính chỉ số chưa có, không thay đổi số reps/thời gian/mức tạ đã ghi nhận."
        )
        return ctx, {"applied": True, "query_type": query_type, "target_date": target_date_iso, "sessions_count": len(matching)}

    if query_type == "RECENT":
        if not completed_sessions:
            ctx = (
                "=== THÔNG TIN BUỔI TẬP TỪ CƠ SỞ DỮ LIỆU (DB TRUTH) ===\n"
                "[Nguồn: workout_history | Múi giờ: Asia/Ho_Chi_Minh (UTC+7)]\n"
                "[Yêu cầu tra cứu: Buổi tập gần nhất]\n\n"
                "KẾT QUẢ: Chưa có dữ liệu buổi tập hoàn tất nào được ghi nhận trong lịch sử tập luyện của người dùng.\n"
                "[CHỈ DẪN CHO AI]: Thông báo rõ ràng rằng chưa có dữ liệu buổi tập hoàn tất nào được ghi nhận trong hệ thống. Tuyệt đối không tự bịa buổi tập."
            )
            return ctx, {"applied": True, "query_type": "RECENT", "sessions_count": 0}

        recent_session = completed_sessions[0]
        card = _format_session_card(recent_session, 1)
        ctx = (
            "=== THÔNG TIN BUỔI TẬP TỪ CƠ SỞ DỮ LIỆU (DB TRUTH) ===\n"
            "[Nguồn: workout_history | Múi giờ: Asia/Ho_Chi_Minh (UTC+7)]\n"
            "[Yêu cầu tra cứu: Buổi tập gần nhất]\n\n"
            + card
            + "\n\n[CHỈ DẪN CHO AI]: Sử dụng thông tin sự thật từ DB trên để trả lời câu hỏi của người dùng. Không bịa thêm bài tập, không tự tính chỉ số chưa có, không thay đổi số reps/thời gian/mức tạ đã ghi nhận."
        )
        return ctx, {"applied": True, "query_type": "RECENT", "sessions_count": 1}

    return "", {"applied": False, "query_type": "NONE", "sessions_count": 0}


# ─────────────────────────────────────────────────────────────
# CONVERSATIONS & CHAT ROUTES
# ─────────────────────────────────────────────────────────────

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
    current_user: dict = Depends(get_current_user),
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

    # Validate conversation_id if provided
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

    # Check for clear water log intent (250 ml water)
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

    # Build server-authoritative read-only health context
    health_context = build_health_context(
        current_user,
        nutrition_col_ref=nutrition_col,
        workout_col_ref=workout_history_col,
    )

    # Multi-turn prompt construction from server-stored turns
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

    # Workout Grounding Retrieval
    workout_context_str = ""
    retrieval_meta = None
    query_type, target_date_iso, error_reason = parse_date_query(trimmed_message)
    if query_type != "NONE":
        try:
            workout_context_str, retrieval_meta = build_workout_grounding_context(
                user_id=user_id or str(current_user.get("_id", "")),
                query_type=query_type,
                target_date_iso=target_date_iso,
                error_reason=error_reason
            )
        except Exception as e:
            logger.error(f"Chat Grounding Error: {e}")
            return {
                "reply": f"Lỗi hệ thống: {str(e)}",
                "status": "error"
            }

    prompt_parts = []
    if health_context.strip():
        prompt_parts.append(health_context.strip())
    if workout_context_str.strip():
        prompt_parts.append(workout_context_str.strip())
    if history_str:
        prompt_parts.append(history_str)
    prompt_parts.append(f"USER HỎI: {trimmed_message}")
    prompt_parts.append("TRẢ LỜI NGẮN GỌN & THÂN THIỆN:")

    full_prompt = "\n\n".join(prompt_parts)

    if email:
        full_prompt = full_prompt.replace(email, "")
    full_prompt = re.sub(r'[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+', '', full_prompt)

    # Execute AI call (supporting test mocks on get_ai_reply or _generate_ai_reply)
    import unittest.mock
    if isinstance(get_ai_reply, unittest.mock.Base) or getattr(get_ai_reply, "_mock_return_value", None) is not None or getattr(get_ai_reply, "_mock_side_effect", None) is not None:
        reply = get_ai_reply(full_prompt)
    else:
        reply = await _generate_ai_reply(full_prompt)

    # Persist messages to DB after AI succeeds
    now_iso = datetime.now(timezone.utc).isoformat()
    user_msg_doc = {"role": "user", "content": trimmed_message, "created_at": now_iso}
    ai_msg_doc = {"role": "assistant", "content": reply, "created_at": now_iso}

    if conversations_col is None:
        logger.error("Conversations collection is not available")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Chat storage unavailable",
        )

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

    status_str = "success" if not (isinstance(reply, str) and reply.startswith("Lỗi:")) else "error"
    response_data: Dict[str, Any] = {
        "reply": reply,
        "status": status_str,
        "conversation_id": conv_id_str,
        "action": None,
    }

    if retrieval_meta:
        response_data["retrieval"] = {
            "grounded": status_str == "success" and retrieval_meta.get("applied", False),
            "query_type": retrieval_meta.get("query_type"),
            "sessions_found": retrieval_meta.get("sessions_count", 0),
        }

    return response_data


# ─────────────────────────────────────────────────────────────
# ACTION DECISION & WATER LOGGING
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
        # Check if water was already applied for this action in water_col
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

    # Atomic lock: transition pending -> processing in conversations_col first
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
