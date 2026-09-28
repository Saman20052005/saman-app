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
    users_collection,
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
users_col = users_collection
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
    # Bỏ email khỏi thông tin gửi AI
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
        if not logs:
            logs = list(col.find({"email": email, "date": today_str}))
    except Exception as e:
        logger.warning("Failed to query nutrition logs: %s", type(e).__name__)
        return f"DINH DƯỠNG HÔM NAY ({today_str}): chưa có dữ liệu"

    if not logs:
        return f"DINH DƯỠNG HÔM NAY ({today_str}): chưa ghi nhận bữa ăn nào (chưa có dữ liệu)"

    try:
        total_cal = sum(float(l.get("total_calories") or l.get("calories") or sum(float(f.get("calories", 0)) for f in l.get("foods", []))) for l in logs)
        total_pro = round(sum(float(l.get("total_protein") or l.get("protein") or sum(float(f.get("protein", 0)) for f in l.get("foods", []))) for l in logs), 1)
        total_carbs = round(sum(float(l.get("total_carbs") or l.get("carbs") or sum(float(f.get("carbs", 0)) for f in l.get("foods", []))) for l in logs), 1)
        total_fat = round(sum(float(l.get("total_fat") or l.get("fat") or sum(float(f.get("fat", 0)) for f in l.get("foods", []))) for l in logs), 1)
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

    query_or = [{"email": email}, {"user_email": email}]
    if user_id:
        query_or.append({"user_id": user_id})
    workout_query = {"$or": query_or}

    try:
        sessions = list(col.find(workout_query))
    except Exception as e:
        logger.warning("Failed to query workout sessions: %s", type(e).__name__)
        sessions = []

    if not sessions:
        try:
            sessions = list(col.find({"email": email}))
        except Exception:
            pass
    if not sessions:
        try:
            sessions = list(col.find({"user_email": email}))
        except Exception:
            pass
    if not sessions and user_id:
        try:
            sessions = list(col.find({"user_id": user_id}))
        except Exception:
            pass

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

    date_part = best_dt.strftime("%Y-%m-%d") if best_dt else (best_session.get("date") or "chưa có dữ liệu")
    duration = best_session.get("duration_minutes") or best_session.get("duration")
    duration_str = f"{duration} phút" if duration is not None else "chưa có dữ liệu"

    exercises = best_session.get("completed_exercises") or best_session.get("exercises")
    exercise_names = []
    if isinstance(exercises, list):
        for ex in exercises:
            if isinstance(ex, dict) and ex.get("name"):
                exercise_names.append(str(ex["name"]))
            elif isinstance(ex, str):
                exercise_names.append(ex)

    plan_name = best_session.get("plan_id") or best_session.get("plan_name") or best_session.get("workout_name")
    if exercise_names:
        exercises_str = ", ".join(exercise_names[:5])
    elif plan_name:
        exercises_str = str(plan_name)
    else:
        exercises_str = "chưa có dữ liệu"

    return (
        f"TẬP LUYỆN GẦN NHẤT:\n"
        f"- Ngày: {date_part}\n"
        f"- Thời lượng: {duration_str}\n"
        f"- Bài tập: {exercises_str}"
    )


# ─────────────────────────────────────────────────────────────
# CHECKPOINT 3: 7-DAY TREND AGGREGATOR (READ-ONLY)
# ─────────────────────────────────────────────────────────────

def _build_trends_context(
    email: str,
    user_id: Optional[str],
    nutrition_col_ref,
    workout_col_ref,
) -> str:
    """Return a 7-day trend summary (avg calories, avg protein, workout count).

    All date boundaries are computed in Asia/Ho_Chi_Minh timezone.
    Strictly read-only — no insert/update on any collection.
    """
    LABEL = "XU HƯỚNG 7 NGÀY QUA"
    NO_DATA = f"{LABEL}: chưa có dữ liệu"

    if not email:
        return NO_DATA

    try:
        today_vn = datetime.now(VN_TZ).date()
        dates_7 = [(today_vn - timedelta(days=i)).strftime("%Y-%m-%d") for i in range(7)]
    except Exception:
        return NO_DATA

    # ── Nutrition: aggregate per day ──────────────────────────
    daily_cals: List[float] = []
    daily_pros: List[float] = []
    try:
        ncol = nutrition_col_ref
        if ncol is not None:
            logs = list(ncol.find({"$or": [{"user_email": email}, {"email": email}]}))
            logs = [l for l in logs if l.get("date") in dates_7]
            # Group by date, sum macros
            by_date: dict = {}
            for l in logs:
                d = l.get("date")
                if d not in by_date:
                    by_date[d] = {"cal": 0.0, "pro": 0.0}
                cal = float(
                    l.get("total_calories")
                    or l.get("calories")
                    or sum(float(f.get("calories", 0)) for f in l.get("foods", []))
                    or 0
                )
                pro = float(
                    l.get("total_protein")
                    or l.get("protein")
                    or sum(float(f.get("protein", 0)) for f in l.get("foods", []))
                    or 0
                )
                by_date[d]["cal"] += cal
                by_date[d]["pro"] += pro
            for day in dates_7:
                if day in by_date:
                    daily_cals.append(by_date[day]["cal"])
                    daily_pros.append(by_date[day]["pro"])
    except Exception as e:
        logger.warning("7-day nutrition trend query failed: %s", type(e).__name__)

    # ── Workout: count sessions in 7 days ─────────────────────
    workout_count = 0
    try:
        wcol = workout_col_ref
        if wcol is not None:
            query_or = [{"email": email}, {"user_email": email}]
            if user_id:
                query_or.append({"user_id": user_id})
            sessions = list(wcol.find({"$or": query_or}))
            for s in sessions:
                s_date = s.get("date")
                if isinstance(s_date, str) and s_date in dates_7:
                    workout_count += 1
                elif isinstance(s_date, datetime):
                    s_date_str = s_date.astimezone(VN_TZ).strftime("%Y-%m-%d")
                    if s_date_str in dates_7:
                        workout_count += 1
    except Exception as e:
        logger.warning("7-day workout trend query failed: %s", type(e).__name__)

    # ── Format ────────────────────────────────────────────────
    if not daily_cals and workout_count == 0:
        return NO_DATA

    logged_days = len(daily_cals)
    avg_cal_str = f"{round(sum(daily_cals) / logged_days)} kcal" if logged_days > 0 else "chưa có dữ liệu"
    avg_pro_str = f"{round(sum(daily_pros) / logged_days, 1)}g" if logged_days > 0 else "chưa có dữ liệu"

    return (
        f"{LABEL}:\n"
        f"- Số ngày có log dinh dưỡng: {logged_days}/7\n"
        f"- Calo trung bình/ngày: {avg_cal_str}\n"
        f"- Protein trung bình/ngày: {avg_pro_str}\n"
        f"- Số buổi tập: {workout_count} buổi"
    )


def build_health_context(
    user: dict,
    nutrition_col_ref=None,
    workout_col_ref=None,
    users_col_ref=None,
) -> str:
    """Build concise, server-authoritative health context without leaking private fields."""
    email = user.get("email") or ""
    user_id = str(user.get("_id")) if user.get("_id") is not None else None

    ucol = users_col_ref if users_col_ref is not None else users_col
    ncol = nutrition_col_ref if nutrition_col_ref is not None else nutrition_col
    wcol = workout_col_ref if workout_col_ref is not None else workout_history_col

    # If user object is minimal and ucol is available, query DB
    if ucol is not None and email:
        try:
            db_user = ucol.find_one({"email": email})
            if db_user:
                merged_user = dict(db_user)
                merged_user.update({k: v for k, v in user.items() if v is not None})
                user = merged_user
                if user_id is None and user.get("_id") is not None:
                    user_id = str(user.get("_id"))
        except Exception:
            pass

    profile_ctx = _build_user_profile_context(user)
    nutrition_ctx = _build_today_nutrition_context(email, ncol)
    workout_ctx = _build_latest_workout_context(email, user_id, wcol)
    trends_ctx = _build_trends_context(email, user_id, ncol, wcol)

    return f"{profile_ctx}\n\n{nutrition_ctx}\n\n{workout_ctx}\n\n{trends_ctx}"


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

    # Checkpoint 3: Validate conversation_id if provided
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

    # Checkpoint 4a: Check for clear water log intent (250 ml water)
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

    # Checkpoint 2: Build server-authoritative read-only health context.
    # Note: request.context and request.history are ignored for prompt construction.
    health_context = build_health_context(
        current_user,
        nutrition_col_ref=nutrition_col,
        workout_col_ref=workout_history_col,
        users_col_ref=users_col,
    )

    # Checkpoint 4: Multi-turn prompt construction from server-stored turns (max 10 turns)
    history_str = ""
    if conv:
        prior_msgs = conv.get("messages", [])
        if prior_msgs:
            recent_prior = prior_msgs[-10:]
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
    # Checkpoint 5: Proactive coaching system instruction
    prompt_parts.append(
        "HƯỚNG DẪN TRẢ LỜI (Saman Coach):\n"
        "Bạn là Saman Coach — trợ lý sức khỏe cá nhân. Hãy thực hiện đủ 4 bước sau:\n"
        "1. PHÂN TÍCH: Đọc dữ liệu 'DINH DƯỠNG HÔM NAY' và 'XU HƯỚNG 7 NGÀY QUA' ở trên.\n"
        "2. NEXT STEP: Nếu user hỏi về dinh dưỡng hoặc tập luyện, đề xuất đúng 1 bước tiếp theo cụ thể, có thể thực hiện ngay.\n"
        "3. LÝ DO: Giải thích lý do ngắn gọn dựa trên dữ liệu (ví dụ: 'Vì Protein hôm nay của bạn còn thiếu X g so với mục tiêu...').\n"
        "4. PHẢN HỒI: Kết thúc bằng 1 câu hỏi để thu thập phản hồi từ người dùng.\n"
        "Giới hạn: Không chẩn đoán y khoa, không kê đơn. Nếu thiếu dữ liệu, nói rõ 'chưa có dữ liệu' thay vì suy đoán.\n"
        "TRẢ LỜI:"
    )

    full_prompt = "\n\n".join(prompt_parts)

    # Bỏ email khỏi prompt gửi AI (bảo vệ quyền riêng tư người dùng)
    if email:
        full_prompt = full_prompt.replace(email, "")
    full_prompt = re.sub(r'[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+', '', full_prompt)

    reply = await _generate_ai_reply(full_prompt)

    # Checkpoint 3: Persist messages to DB after AI succeeds
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
        # Giữ owner trong điều kiện update và kiểm tra kết quả ghi
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
        # Check if water was already applied for this action in water_col
        if water_col is not None:
            already_applied = water_col.find_one({
                "user_email": email,
                "date": target_date,
                "applied_actions": action_id,
            })
            if already_applied:
                # Water write already took place; cancel is forbidden
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
    # This guarantees that if a concurrent cancel runs, exactly one of them wins the state transition.
    # If cancel wins, confirm matched_count is 0, raising 409 WITHOUT writing to water_col.
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
                # Check if already applied (fast exit if concurrent write or prior attempt succeeded)
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

    # Step C: Verify marker in water_logs. Only return confirmed/success when verified!
    # DO NOT rollback processing to pending if write fails.
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