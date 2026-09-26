# [File: backend/routers/chat.py]
import os
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
    full_name = user.get("full_name") or "chưa có dữ liệu"
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
    model = genai.GenerativeModel("gemini-1.5-flash")
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

    return {
        "id": str(conv["_id"]),
        "title": conv.get("title") or "Cuộc trò chuyện",
        "messages": messages,
        "created_at": conv.get("created_at", ""),
        "updated_at": conv.get("updated_at", ""),
        "status": "success",
    }


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

    # Checkpoint 2: Build server-authoritative read-only health context.
    # Note: request.context and request.history are ignored for prompt construction.
    health_context = build_health_context(
        current_user,
        nutrition_col_ref=nutrition_col,
        workout_col_ref=workout_history_col,
    )

    # Checkpoint 3: Multi-turn prompt construction from server-stored turns
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
    }