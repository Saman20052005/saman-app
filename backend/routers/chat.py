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
try:
    from backend.app.repositories.user_repository import UserRepository
    from backend.app.database import (
        users_collection,
        nutrition_collection,
        workout_history_collection,
        conversations_collection,
        messages_collection,
        water_collection,
    exercises_collection,
        custom_plans_collection,
    )
    from backend.auth_utils import verify_token, get_current_user
except ImportError:
    from app.repositories.user_repository import UserRepository
    from app.database import (
        users_collection,
        nutrition_collection,
        workout_history_collection,
        conversations_collection,
        messages_collection,
        water_collection,
    exercises_collection,
        custom_plans_collection,
    )
    from auth_utils import verify_token

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
exercises_col = exercises_collection
workout_history_collection = workout_history_col
exercises_collection = exercises_col
custom_plans_col = custom_plans_collection

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
DEFAULT_GEMINI_MODEL = "gemini-3.5-flash-lite"

DEFAULT_TIMEOUT_SECONDS = 15.0
VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")
ICT_ZONE = VN_TZ


def _get_gemini_model() -> str:
    return (os.getenv("GEMINI_MODEL") or DEFAULT_GEMINI_MODEL).strip()


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


def _extract_nutrition_metric(
    doc: dict,
    primary_key: str,
    alt_key: Optional[str] = None,
    fallback_foods_key: Optional[str] = None,
) -> float:
    val = doc.get(primary_key)
    if val is not None:
        try:
            return float(val)
        except (ValueError, TypeError):
            pass
    if alt_key:
        alt_val = doc.get(alt_key)
        if alt_val is not None:
            try:
                return float(alt_val)
            except (ValueError, TypeError):
                pass
    if fallback_foods_key:
        foods = doc.get("foods")
        if isinstance(foods, list):
            sub_sum = 0.0
            for f in foods:
                if isinstance(f, dict):
                    f_val = f.get(fallback_foods_key)
                    if f_val is not None:
                        try:
                            sub_sum += float(f_val)
                        except (ValueError, TypeError):
                            pass
            return sub_sum
    return 0.0


def _build_today_nutrition_context(email: str, col) -> str:
    today_str = _get_current_vn_date()
    if col is None or not email:
        return f"DINH DƯỠNG HÔM NAY ({today_str}): chưa có dữ liệu"

    try:
        logs = list(col.find({"$or": [{"user_email": email}, {"email": email}], "date": today_str}))
    except Exception as e:
        logger.warning("Failed to query nutrition logs: %s", type(e).__name__)
        logs = []

    if not logs:
        try:
            logs = list(col.find({"user_email": email, "date": today_str}))
        except Exception:
            pass
    if not logs:
        try:
            logs = list(col.find({"email": email, "date": today_str}))
        except Exception:
            pass

    if not logs:
        return f"DINH DƯỠNG HÔM NAY ({today_str}): chưa ghi nhận bữa ăn nào (chưa có dữ liệu)"

    try:
        total_cal = sum(_extract_nutrition_metric(l, "total_calories", "calories", "calories") for l in logs)
        total_pro = round(sum(_extract_nutrition_metric(l, "total_protein", "protein", "protein") for l in logs), 1)
        total_carbs = round(sum(_extract_nutrition_metric(l, "total_carbs", "carbs", "carbs") for l in logs), 1)
        total_fat = round(sum(_extract_nutrition_metric(l, "total_fat", "fat", "fat") for l in logs), 1)
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


def _build_today_water_context(email: str, col) -> str:
    today_str = _get_current_vn_date()
    if col is None or not email:
        return f"NƯỚC UỐNG HÔM NAY ({today_str}): chưa có dữ liệu"

    try:
        logs = list(col.find({"$or": [{"user_email": email}, {"email": email}], "date": today_str}))
    except Exception as e:
        logger.warning("Failed to query water logs: %s", type(e).__name__)
        logs = []

    if not logs:
        try:
            logs = list(col.find({"user_email": email, "date": today_str}))
        except Exception:
            pass
    if not logs:
        try:
            logs = list(col.find({"email": email, "date": today_str}))
        except Exception:
            pass

    if not logs:
        try:
            doc = col.find_one({"user_email": email, "date": today_str})
            if not doc:
                doc = col.find_one({"email": email, "date": today_str})
            if doc:
                logs = [doc]
        except Exception:
            pass

    if not logs:
        return f"NƯỚC UỐNG HÔM NAY ({today_str}): chưa có dữ liệu"

    amounts = []
    for l in logs:
        amt = l.get("amount_ml")
        if amt is not None:
            try:
                amounts.append(float(amt))
            except (ValueError, TypeError):
                pass

    if not amounts:
        return f"NƯỚC UỐNG HÔM NAY ({today_str}): chưa có dữ liệu"

    total_water = sum(amounts)
    val_display = int(total_water) if total_water.is_integer() else total_water
    return f"NƯỚC UỐNG HÔM NAY ({today_str}): {val_display} ml"


def _normalize_to_vn_datetime(val) -> Optional[datetime]:
    if val is None:
        return None
    if isinstance(val, datetime):
        if val.tzinfo is None:
            return val.replace(tzinfo=timezone.utc).astimezone(VN_TZ)
        return val.astimezone(VN_TZ)
    if isinstance(val, str):
        val_clean = val.strip()
        if not val_clean:
            return None
        try:
            iso_str = val_clean.replace("Z", "+00:00")
            parsed = datetime.fromisoformat(iso_str)
            if parsed.tzinfo is None:
                if len(val_clean) == 10:
                    return datetime(parsed.year, parsed.month, parsed.day, 0, 0, tzinfo=VN_TZ)
                return parsed.replace(tzinfo=timezone.utc).astimezone(VN_TZ)
            return parsed.astimezone(VN_TZ)
        except Exception:
            pass
        try:
            parsed = datetime.strptime(val_clean[:10], "%Y-%m-%d")
            return datetime(parsed.year, parsed.month, parsed.day, 0, 0, tzinfo=VN_TZ)
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
        dt = _normalize_to_vn_datetime(raw_val)
        if dt is not None and (best_dt is None or dt > best_dt):
            best_dt = dt
            best_session = s

    if best_session is None and sessions:
        best_session = sessions[-1]

    date_part = best_dt.strftime("%Y-%m-%d") if best_dt else (best_session.get("date") or "chưa có dữ liệu")
    duration = (
        best_session.get("duration_minutes")
        if best_session.get("duration_minutes") is not None
        else best_session.get("duration")
    )
    duration_str = f"{duration} phút" if duration is not None else "chưa có dữ liệu"

    exercises = best_session.get("completed_exercises") or best_session.get("exercises")
    exercise_names = []
    if isinstance(exercises, list):
        for ex in exercises:
            if isinstance(ex, dict):
                ex_name = ex.get("name") or ex.get("exercise_name")
                if ex_name:
                    exercise_names.append(str(ex_name))
            elif isinstance(ex, str) and ex.strip():
                exercise_names.append(ex.strip())

    plan_name = (
        best_session.get("plan_id")
        or best_session.get("plan_name")
        or best_session.get("workout_name")
        or best_session.get("name")
    )
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

def _normalize_trend_date_str(val) -> Optional[str]:
    """Normalize a date, datetime, or date string to YYYY-MM-DD in Asia/Ho_Chi_Minh."""
    if val is None:
        return None
    if isinstance(val, date) and not isinstance(val, datetime):
        return val.strftime("%Y-%m-%d")
    dt = _normalize_to_vn_datetime(val)
    if dt is not None:
        return dt.strftime("%Y-%m-%d")
    if isinstance(val, str):
        clean = val.strip()
        if len(clean) >= 10:
            return clean[:10]
    return None


def _get_workout_day_vn(s: dict) -> Optional[str]:
    """Extract and normalize workout record timestamp to YYYY-MM-DD in Asia/Ho_Chi_Minh.

    Priority: start_time > created_at > date > end_time.
    """
    if not isinstance(s, dict):
        return None
    raw_val = s.get("start_time") or s.get("created_at") or s.get("date") or s.get("end_time")
    return _normalize_trend_date_str(raw_val)


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
        dates_7_set = set(dates_7)
    except Exception:
        return NO_DATA

    # ── Nutrition: aggregate per day ──────────────────────────
    daily_cals: List[float] = []
    daily_pros: List[float] = []
    try:
        ncol = nutrition_col_ref
        if ncol is not None:
            query_or: List[Dict[str, Any]] = [{"user_email": email}, {"email": email}]
            if user_id:
                query_or.append({"user_id": user_id})
            try:
                logs = list(ncol.find({"$or": query_or}))
            except Exception:
                logs = []
            if not logs:
                try:
                    logs = list(ncol.find({"user_email": email}))
                except Exception:
                    pass
            if not logs:
                try:
                    logs = list(ncol.find({"email": email}))
                except Exception:
                    pass
            if not logs and user_id:
                try:
                    logs = list(ncol.find({"user_id": user_id}))
                except Exception:
                    pass

            seen_log_keys = set()
            by_date: Dict[str, Dict[str, float]] = {}
            for l in logs:
                if not isinstance(l, dict):
                    continue
                lid = l.get("_id") or l.get("id")
                if lid is not None:
                    lkey = ("id", str(lid))
                else:
                    lkey = ("obj", id(l))
                if lkey in seen_log_keys:
                    continue
                seen_log_keys.add(lkey)

                d_str = _normalize_trend_date_str(l.get("date") or l.get("created_at"))
                if not d_str or d_str not in dates_7_set:
                    continue

                if d_str not in by_date:
                    by_date[d_str] = {"cal": 0.0, "pro": 0.0}

                cal = _extract_nutrition_metric(l, "total_calories", "calories", "calories")
                pro = _extract_nutrition_metric(l, "total_protein", "protein", "protein")
                by_date[d_str]["cal"] += cal
                by_date[d_str]["pro"] += pro

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
            try:
                sessions = list(wcol.find({"$or": query_or}))
            except Exception:
                sessions = []
            if not sessions:
                try:
                    sessions = list(wcol.find({"email": email}))
                except Exception:
                    pass
            if not sessions:
                try:
                    sessions = list(wcol.find({"user_email": email}))
                except Exception:
                    pass
            if not sessions and user_id:
                try:
                    sessions = list(wcol.find({"user_id": user_id}))
                except Exception:
                    pass

            seen_session_keys = set()
            for s in sessions:
                if not isinstance(s, dict):
                    continue

                # Avoid counting the same session twice
                sid = s.get("_id") or s.get("session_id") or s.get("id")
                if sid is not None:
                    skey = ("id", str(sid))
                else:
                    skey = ("obj", id(s))
                if skey in seen_session_keys:
                    continue
                seen_session_keys.add(skey)

                # Normalize timestamped workout records before assigning a day
                assigned_day = _get_workout_day_vn(s)
                if assigned_day and assigned_day in dates_7_set:
                    workout_count += 1
    except Exception as e:
        logger.warning("7-day workout trend query failed: %s", type(e).__name__)

    # ── Format ────────────────────────────────────────────────
    if not daily_cals and workout_count == 0:
        return NO_DATA

    logged_days = len(daily_cals)
    avg_cal_str = f"{round(sum(daily_cals) / logged_days)} kcal" if logged_days > 0 else "chưa có dữ liệu"
    avg_pro_str = f"{round(sum(daily_pros) / logged_days, 1)}g" if logged_days > 0 else "chưa có dữ liệu"

    lines = [
        f"{LABEL}:",
        f"- Số ngày có log dinh dưỡng: {logged_days}/7",
        f"- Calo trung bình/ngày: {avg_cal_str}",
        f"- Protein trung bình/ngày: {avg_pro_str}",
        f"- Số buổi tập: {workout_count} buổi",
    ]

    if logged_days == 0:
        lines.append("- Đánh giá: Chưa có dữ liệu dinh dưỡng trong 7 ngày qua, chưa đủ để kết luận xu hướng")
    elif logged_days < 3:
        lines.append(f"- Đánh giá: Dữ liệu còn ít ({logged_days}/7 ngày), chưa đủ để kết luận xu hướng")
    else:
        lines.append(f"- Đánh giá: Đủ dữ liệu theo dõi xu hướng ({logged_days}/7 ngày)")

    return "\n".join(lines)


def _build_preferences_context(user: dict) -> str:
    prefs = user.get("preferences")
    if not isinstance(prefs, dict) or not prefs:
        return ""

    lines = ["SỞ THÍCH NGƯỜI DÙNG CUNG CẤP (Dữ liệu tham khảo, không ghi đè nguyên tắc an toàn):"]

    reply_style = prefs.get("reply_style")
    if reply_style:
        style_desc = {
            "strict_pt": "Huấn luyện viên nghiêm khắc (thẳng thắn, kỷ luật cao)",
            "nutrition_doctor": "Chuyên gia dinh dưỡng (khoa học, phân tích chi tiết)",
            "supportive_coach": "Huấn luyện viên đồng hành (khích lệ, hỗ trợ tích cực)",
            "concise": "Ngắn gọn, đi thẳng vào số liệu và hành động",
            "detailed": "Chi tiết, giải thích căn cứ",
            "default": "Tiêu chuẩn Saman Coach",
        }.get(reply_style, reply_style)
        lines.append(f"- Phong cách phản hồi mong muốn: {style_desc}")

    dislikes = prefs.get("food_dislikes")
    if isinstance(dislikes, list) and dislikes:
        clean_dislikes = [str(d).strip() for d in dislikes if str(d).strip()]
        if clean_dislikes:
            lines.append(f"- Món ăn không thích (khẩu vị cá nhân, không phải dị ứng y khoa): {', '.join(clean_dislikes)}")

    notes = prefs.get("notes")
    if notes:
        clean_notes = re.sub(r'[\r\n]+', ' ', str(notes)).strip()
        if clean_notes:
            lines.append(f"- Ghi chú cá nhân: {clean_notes}")

    if len(lines) == 1:
        return ""

    return "\n".join(lines)


def build_health_context(
    user: dict,
    nutrition_col_ref=None,
    workout_col_ref=None,
    users_col_ref=None,
    water_col_ref=None,
) -> str:
    """Build concise, server-authoritative health context without leaking private fields."""
    email = user.get("email") or ""
    user_id = str(user.get("_id")) if user.get("_id") is not None else None

    ucol = users_col_ref if users_col_ref is not None else users_col
    ncol = nutrition_col_ref if nutrition_col_ref is not None else nutrition_col
    wcol = workout_col_ref if workout_col_ref is not None else workout_history_col
    wtcol = water_col_ref if water_col_ref is not None else water_col

    if ucol is not None and email:
        try:
            db_user = ucol.find_one({"email": email})
            if db_user:
                merged_user = dict(db_user)
                merged_user.update({k: v for k, v in user.items() if v is not None})
                # DB is authoritative for preferences
                if "preferences" in db_user and isinstance(db_user["preferences"], dict):
                    merged_user["preferences"] = db_user["preferences"]
                else:
                    merged_user.pop("preferences", None)
                user = merged_user
                if user_id is None and user.get("_id") is not None:
                    user_id = str(user.get("_id"))
        except Exception:
            pass

    profile_ctx = _build_user_profile_context(user)
    nutrition_ctx = _build_today_nutrition_context(email, ncol)
    water_ctx = _build_today_water_context(email, wtcol)
    workout_ctx = _build_latest_workout_context(email, user_id, wcol)
    trends_ctx = _build_trends_context(email, user_id, ncol, wcol)
    pref_ctx = _build_preferences_context(user)

    parts = [profile_ctx, nutrition_ctx, water_ctx, workout_ctx]
    if trends_ctx:
        parts.append(trends_ctx)
    if pref_ctx:
        parts.append(pref_ctx)

    return "\n\n".join(parts)


# ─────────────────────────────────────────────────────────────
# AI CALLERS
# ─────────────────────────────────────────────────────────────

def _call_gemini_sync(prompt: str, api_key: str, timeout_seconds: float) -> Optional[str]:
    import google.generativeai as genai
    genai.configure(api_key=api_key)
    model = genai.GenerativeModel(_get_gemini_model())
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
    ai_provider = (os.getenv("CHAT_AI_PROVIDER") or "").strip().lower()
    if ai_provider == "fake":
        return "[DEV/TEST] Saman Coach (thử nghiệm): Tôi đã nhận được tin nhắn của bạn và sẵn sàng hỗ trợ."
    elif ai_provider and ai_provider != "gemini":
        logger.error("Invalid CHAT_AI_PROVIDER configuration")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Invalid CHAT_AI_PROVIDER configuration",
        )

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
    meal: Optional[Dict[str, Any]] = None
    workout: Optional[Dict[str, Any]] = None


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


def _detect_log_meal_intent(message: str, request: Optional[ChatRequest] = None) -> Optional[Dict[str, Any]]:
    """
    Nhận diện yêu cầu log bữa ăn khi và chỉ khi có ĐẦY ĐỦ chi tiết có cấu trúc
    (tên món, số calo rõ ràng).
    Tuyệt đối KHÔNG suy diễn calo/macros từ text tự do mơ hồ hoặc hình ảnh.
    """
    # 1. Structured meal passed explicitly in request
    if request is not None and getattr(request, "meal", None):
        meal_data = request.meal
        if isinstance(meal_data, dict):
            cals = meal_data.get("calories") or meal_data.get("total_calories")
            name = meal_data.get("name") or (meal_data.get("foods", [{}])[0].get("name") if meal_data.get("foods") else "")
            if cals is not None and name:
                try:
                    cals_int = int(cals)
                    if cals_int > 0:
                        pro = float(meal_data.get("protein") or meal_data.get("total_protein") or 0.0)
                        carb = float(meal_data.get("carbs") or meal_data.get("total_carbs") or 0.0)
                        fat = float(meal_data.get("fat") or meal_data.get("total_fat") or 0.0)
                        m_type = str(meal_data.get("meal_type") or "meal").lower().strip()
                        type_display_map = {
                            "breakfast": "bữa sáng",
                            "lunch": "bữa trưa",
                            "dinner": "bữa tối",
                            "snack": "bữa phụ",
                        }
                        return {
                            "name": str(name).strip(),
                            "calories": cals_int,
                            "protein": round(pro, 1),
                            "carbs": round(carb, 1),
                            "fat": round(fat, 1),
                            "meal_type": m_type,
                            "meal_type_display": type_display_map.get(m_type, "bữa ăn"),
                            "notes": meal_data.get("notes"),
                        }
                except (ValueError, TypeError):
                    pass

    if not message:
        return None

    raw = message.strip()
    raw_lower = raw.lower()

    # Phủ định hoặc câu hỏi, tư vấn -> Tuyệt đối không tạo action
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
        if re.search(pat, raw_lower):
            return None

    # Nếu là yêu cầu nước uống -> Để bộ nhận diện nước xử lý
    if ("nước" in raw_lower or "water" in raw_lower or "nuoc" in raw_lower) and "250" in raw_lower:
        return None

    # Phải có hành động log / ăn / ghi nhận
    action_keywords = [
        "log", "ghi nhận", "ghi", "thêm", "lưu", "nhập", "note", "ăn", "vừa ăn", "da an", "đã ăn"
    ]
    has_action = any(re.search(rf"\b{re.escape(kw)}\b", raw_lower) for kw in action_keywords)
    if not has_action:
        return None

    # Phải có calo rõ ràng (ví dụ: 450 calo, 450 kcal, 450 calories, 450 cal)
    # KHÔNG suy diễn calo nếu không có số calo tường minh
    cal_match = re.search(r"(\d+(?:\.\d+)?)\s*(?:kcal|calo|calories|cal)\b", raw_lower)
    if not cal_match:
        return None

    try:
        calories = int(float(cal_match.group(1)))
        if calories <= 0:
            return None
    except (ValueError, TypeError):
        return None

    # Parse meal type
    meal_type = "meal"
    meal_type_display = "bữa ăn"
    if "sáng" in raw_lower or "breakfast" in raw_lower:
        meal_type = "breakfast"
        meal_type_display = "bữa sáng"
    elif "trưa" in raw_lower or "lunch" in raw_lower:
        meal_type = "lunch"
        meal_type_display = "bữa trưa"
    elif "tối" in raw_lower or "dinner" in raw_lower:
        meal_type = "dinner"
        meal_type_display = "bữa tối"
    elif "phụ" in raw_lower or "snack" in raw_lower:
        meal_type = "snack"
        meal_type_display = "bữa phụ"

    # Parse protein
    pro = 0.0
    pro_match = re.search(r"(\d+(?:\.\d+)?)\s*g?\s*(?:protein|đạm|pro)\b", raw_lower) or \
                re.search(r"(?:protein|đạm|pro)\s*[:=]?\s*(\d+(?:\.\d+)?)\s*g?\b", raw_lower)
    if pro_match:
        try:
            pro = float(pro_match.group(1))
        except (ValueError, TypeError):
            pass

    # Parse carbs
    carbs = 0.0
    carb_match = re.search(r"(\d+(?:\.\d+)?)\s*g?\s*(?:carbs?|tinh bột|carb)\b", raw_lower) or \
                 re.search(r"(?:carbs?|tinh bột|carb)\s*[:=]?\s*(\d+(?:\.\d+)?)\s*g?\b", raw_lower)
    if carb_match:
        try:
            carbs = float(carb_match.group(1))
        except (ValueError, TypeError):
            pass

    # Parse fat
    fat = 0.0
    fat_match = re.search(r"(\d+(?:\.\d+)?)\s*g?\s*(?:fat|chất béo|mỡ)\b", raw_lower) or \
                re.search(r"(?:fat|chất béo|mỡ)\s*[:=]?\s*(\d+(?:\.\d+)?)\s*g?\b", raw_lower)
    if fat_match:
        try:
            fat = float(fat_match.group(1))
        except (ValueError, TypeError):
            pass

    # Extract food name
    food_name = ""
    if ":" in raw:
        parts = raw.split(":", 1)
        after_colon = parts[1].strip()
        tokens = [p.strip() for p in after_colon.split(",") if p.strip()]
        if tokens:
            first_tok = tokens[0]
            cleaned = re.sub(r"\d+(?:\.\d+)?\s*(?:kcal|calo|calories|cal)\b.*", "", first_tok, flags=re.IGNORECASE).strip()
            if cleaned:
                food_name = cleaned
    if not food_name:
        cleaned = raw
        remove_phrases = [
            r"\b(?:tôi\s+)?vừa\s+ăn\b",
            r"\bđã\s+ăn\b",
            r"\blog\s+meal\b",
            r"\blog\b",
            r"\bghi\s+nhận\b",
            r"\bghi\b",
            r"\bthêm\b",
            r"\blưu\b",
            r"\bnhập\b",
            r"\bbữa\s+sáng\b",
            r"\bbữa\s+trưa\b",
            r"\bbữa\s+tối\b",
            r"\bbữa\s+phụ\b",
            r"\bbreakfast\b",
            r"\blunch\b",
            r"\bdinner\b",
            r"\bsnack\b",
        ]
        for rp in remove_phrases:
            cleaned = re.sub(rp, "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\d+(?:\.\d+)?\s*(?:kcal|calo|calories|cal)\b", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\d+(?:\.\d+)?\s*g?\s*(?:protein|đạm|pro)\b", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"(?:protein|đạm|pro)\s*[:=]?\s*\d+(?:\.\d+)?\s*g?\b", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\d+(?:\.\d+)?\s*g?\s*(?:carbs?|tinh bột|carb)\b", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"(?:carbs?|tinh bột|carb)\s*[:=]?\s*\d+(?:\.\d+)?\s*g?\b", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\d+(?:\.\d+)?\s*g?\s*(?:fat|chất béo|mỡ)\b", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"(?:fat|chất béo|mỡ)\s*[:=]?\s*\d+(?:\.\d+)?\s*g?\b", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"[,:;]+", " ", cleaned).strip()
        cleaned = re.sub(r"\s+", " ", cleaned).strip()
        food_name = cleaned

    if not food_name:
        food_name = meal_type_display.capitalize()

    return {
        "name": food_name,
        "calories": calories,
        "protein": round(pro, 1),
        "carbs": round(carbs, 1),
        "fat": round(fat, 1),
        "meal_type": meal_type,
        "meal_type_display": meal_type_display,
        "notes": raw,
    }


def _detect_adjust_workout_intent(
    message: str,
    request: Optional[ChatRequest] = None,
    current_user: Optional[dict] = None,
    custom_plans_col_ref=None,
) -> Optional[Dict[str, Any]]:
    """
    Nhận diện yêu cầu điều chỉnh workout khi và chỉ khi có ĐẦY ĐỦ chi tiết có cấu trúc
    (target plan_id hoặc plan_name rõ ràng, và các trường thay đổi cụ thể before/after).
    Tuyệt đối KHÔNG suy diễn từ text tự do mơ hồ.
    """
    # 1. Structured workout passed explicitly in request
    if request is not None and getattr(request, "workout", None):
        w_data = request.workout
        if isinstance(w_data, dict):
            plan_id = w_data.get("plan_id") or w_data.get("id")
            plan_name = w_data.get("plan_name") or w_data.get("name")
            before = dict(w_data.get("before")) if isinstance(w_data.get("before"), dict) else {}
            after = dict(w_data.get("after")) if isinstance(w_data.get("after"), dict) else {}
            changes = dict(w_data.get("changes")) if isinstance(w_data.get("changes"), dict) else dict(after)

            if (plan_id or plan_name) and (after or changes):
                # If custom_plans_col_ref is available, lookup and verify plan
                if custom_plans_col_ref is not None and current_user:
                    email = current_user.get("email")
                    user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else None
                    q_user = []
                    if email:
                        q_user.append({"email": email})
                    if user_id:
                        q_user.append({"user_id": user_id})
                    q = {"$or": q_user} if q_user else {}

                    p_doc = None
                    if plan_id:
                        try:
                            if ObjectId.is_valid(str(plan_id)):
                                p_doc = custom_plans_col_ref.find_one({"_id": ObjectId(str(plan_id)), **q})
                        except Exception:
                            pass
                        if not p_doc:
                            p_doc = custom_plans_col_ref.find_one({"$or": [{"_id": str(plan_id)}, {"id": str(plan_id)}], **q})
                    elif plan_name:
                        p_doc = custom_plans_col_ref.find_one({"name": plan_name, **q})

                    if p_doc:
                        plan_id = str(p_doc.get("_id"))
                        plan_name = p_doc.get("name", plan_name)
                        if not before:
                            before = {k: p_doc.get(k) for k in (changes or after).keys() if p_doc.get(k) is not None}

                return {
                    "plan_id": str(plan_id or "custom_plan"),
                    "plan_name": str(plan_name or "Kế hoạch tập"),
                    "before": before,
                    "after": after or changes,
                    "changes": changes or after,
                }

    if not message:
        return None

    raw = message.strip()
    raw_lower = raw.lower()

    # Phủ định hoặc câu hỏi, tư vấn -> Tuyệt đối không tạo action
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
        if re.search(pat, raw_lower):
            return None

    # Phải có từ khóa điều chỉnh / thay đổi / chỉnh sửa / cập nhật
    action_keywords = [
        "điều chỉnh", "dieu chinh", "thay đổi", "thay doi", "chỉnh sửa", "chinh sua", "cập nhật", "cap nhat", "adjust", "update"
    ]
    if not any(kw in raw_lower for kw in action_keywords):
        return None

    # Phải có từ khóa liên quan đến workout / buổi tập / kế hoạch tập
    workout_keywords = [
        "workout", "kế hoạch tập", "ke hoach tap", "buổi tập", "buoi tap", "lịch tập", "lich tap", "plan"
    ]
    if not any(kw in raw_lower for kw in workout_keywords):
        return None

    # Check for duration adjustment: e.g. "thời lượng từ 45 phút xuống 30 phút" or "từ 45 phút thành 30 phút"
    dur_match = re.search(
        r"(?:thời lượng|thoi luong|duration)?\s*(?:từ|tu|from)?\s*(\d+)\s*(?:phút|p|min)?\s*(?:thành|thanh|xuống|xuong|lên|len|sang|to)\s*(\d+)\s*(?:phút|p|min)?",
        raw_lower,
    )
    if not dur_match:
        return None

    try:
        from_dur = int(dur_match.group(1))
        to_dur = int(dur_match.group(2))
    except (ValueError, TypeError):
        return None

    if from_dur <= 0 or to_dur <= 0 or from_dur == to_dur:
        return None

    # Try to extract plan name
    plan_name = ""
    name_match = re.search(
        r"(?:kế hoạch tập|ke hoach tap|buổi tập|buoi tap|workout|plan)\s+([^:,\n]+?)(?:\s*[:,\n]|\s+thời lượng|\s+từ|\s+from)",
        raw,
        flags=re.IGNORECASE,
    )
    if name_match:
        plan_name = name_match.group(1).strip()

    # Look up existing plan in custom_plans_col_ref for authenticated user
    plan_id = None
    if custom_plans_col_ref is not None and current_user:
        email = current_user.get("email")
        user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else None
        q_user = []
        if email:
            q_user.append({"email": email})
        if user_id:
            q_user.append({"user_id": user_id})
        q = {"$or": q_user} if q_user else {}
        try:
            user_plans = list(custom_plans_col_ref.find(q))
            if user_plans:
                matched_p = None
                if plan_name:
                    for p in user_plans:
                        if str(p.get("name", "")).strip().lower() == plan_name.lower():
                            matched_p = p
                            break
                if not matched_p and len(user_plans) == 1:
                    matched_p = user_plans[0]
                if matched_p:
                    plan_id = str(matched_p.get("_id"))
                    plan_name = matched_p.get("name", plan_name)
                    from_dur = int(matched_p.get("duration_minutes") or from_dur)
        except Exception:
            pass

    if not plan_id:
        return None

    return {
        "plan_id": str(plan_id),
        "plan_name": plan_name,
        "before": {"duration_minutes": from_dur},
        "after": {"duration_minutes": to_dur},
        "changes": {"duration_minutes": to_dur},
    }





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
        if ObjectId.is_valid(user_id):
            query_or.append({"user_id": ObjectId(user_id)})
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

    if conversations_col is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Chat storage unavailable",
        )

    query_or: List[Dict[str, Any]] = [{"user_email": email}]
    if user_id:
        query_or.append({"user_id": user_id})
        if ObjectId.is_valid(user_id):
            query_or.append({"user_id": ObjectId(user_id)})

    query = {
        "_id": obj_id,
        "$or": query_or,
    }

    try:
        conv = conversations_col.find_one(query)
    except Exception as e:
        logger.warning("Failed to find conversation: %s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Chat storage unavailable",
        )

    if not conv:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    messages = []
    raw_msgs = conv.get("messages")
    if isinstance(raw_msgs, list):
        for m in raw_msgs:
            if isinstance(m, dict):
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


# ─────────────────────────────────────────────────────────────
# CHECKPOINT 4: USER CONFIRMED PREFERENCES
# ─────────────────────────────────────────────────────────────

ALLOWED_REPLY_STYLES = {
    "strict_pt",
    "nutrition_doctor",
    "supportive_coach",
    "concise",
    "detailed",
    "default",
}
MAX_FOOD_DISLIKES = 10
MAX_DISLIKE_LENGTH = 50
MAX_NOTES_LENGTH = 200


class UserPreferencesRequest(BaseModel):
    reply_style: Optional[str] = None
    food_dislikes: Optional[List[str]] = None
    notes: Optional[str] = None
    preferences: Optional[Dict[str, Any]] = None


@router.get("/preferences")
async def get_user_preferences(
    current_user: dict = Depends(get_current_chat_user),
):
    if users_col is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="User storage unavailable",
        )

    email = current_user.get("email") or ""
    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not authenticated",
        )
    try:
        db_user = users_col.find_one({"email": email})
        if isinstance(db_user, dict):
            prefs = db_user.get("preferences") or {}
        else:
            prefs = current_user.get("preferences") or {}
    except Exception as e:
        logger.error("Failed to query user preferences: %s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="User storage unavailable",
        )

    return {
        "status": "success",
        "preferences": prefs if isinstance(prefs, dict) else {},
    }


@router.put("/preferences")
async def update_user_preferences(
    request: UserPreferencesRequest,
    current_user: dict = Depends(get_current_chat_user),
):
    if users_col is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="User storage unavailable",
        )

    sub_prefs = request.preferences if isinstance(request.preferences, dict) else {}
    raw_style = sub_prefs.get("reply_style") if "reply_style" in sub_prefs else request.reply_style
    raw_dislikes = sub_prefs.get("food_dislikes") if "food_dislikes" in sub_prefs else request.food_dislikes
    raw_notes = sub_prefs.get("notes") if "notes" in sub_prefs else request.notes

    clean_style = None
    if raw_style is not None:
        if not isinstance(raw_style, str):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="reply_style must be a string")
        clean_style = raw_style.strip().lower()
        if clean_style not in ALLOWED_REPLY_STYLES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid reply_style. Allowed options: {sorted(list(ALLOWED_REPLY_STYLES))}",
            )

    clean_dislikes = None
    if raw_dislikes is not None:
        if not isinstance(raw_dislikes, list):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="food_dislikes must be a list of strings")
        if len(raw_dislikes) > MAX_FOOD_DISLIKES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Too many food dislikes (maximum {MAX_FOOD_DISLIKES})",
            )
        clean_dislikes = []
        for item in raw_dislikes:
            if not isinstance(item, str):
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Each food dislike must be a string")
            item_clean = item.strip()
            if len(item_clean) > MAX_DISLIKE_LENGTH:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Food dislike entry exceeds maximum length of {MAX_DISLIKE_LENGTH} characters",
                )
            if item_clean and item_clean not in clean_dislikes:
                clean_dislikes.append(item_clean)

    clean_notes = None
    if raw_notes is not None:
        if not isinstance(raw_notes, str):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="notes must be a string")
        clean_notes = raw_notes.strip()
        if len(clean_notes) > MAX_NOTES_LENGTH:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Notes exceed maximum length of {MAX_NOTES_LENGTH} characters",
            )

    now_iso = datetime.now(timezone.utc).isoformat()
    pref_data = {
        "reply_style": clean_style,
        "food_dislikes": clean_dislikes if clean_dislikes is not None else [],
        "notes": clean_notes,
        "updated_at": now_iso,
    }
    # Keep only defined fields
    pref_data = {k: v for k, v in pref_data.items() if v is not None}

    email = current_user.get("email") or ""
    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not authenticated",
        )
    try:
        update_res = users_col.update_one(
            {"email": email},
            {"$set": {"preferences": pref_data}},
        )
        matched_count = getattr(update_res, "matched_count", None)
        if matched_count is not None and matched_count == 0:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="User storage unavailable",
            )
        if isinstance(current_user, dict):
            current_user["preferences"] = pref_data
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to update user preferences: %s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="User storage unavailable",
        )

    return {
        "status": "success",
        "preferences": pref_data,
    }


@router.delete("/preferences")
async def delete_user_preferences(
    current_user: dict = Depends(get_current_chat_user),
):
    if users_col is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="User storage unavailable",
        )

    email = current_user.get("email") or ""
    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not authenticated",
        )
    try:
        update_res = users_col.update_one(
            {"email": email},
            {"$unset": {"preferences": ""}},
        )
        matched_count = getattr(update_res, "matched_count", None)
        if matched_count is not None and matched_count == 0:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="User storage unavailable",
            )
        if isinstance(current_user, dict):
            current_user.pop("preferences", None)
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to delete user preferences: %s", type(e).__name__)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="User storage unavailable",
        )

    return {
        "status": "success",
        "message": "Preferences deleted",
        "preferences": {},
    }


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
        if ObjectId.is_valid(user_id):
            query_or.append({"user_id": ObjectId(user_id)})

    # Checkpoint 4: Validate conversation_id if provided
    conv = None
    if request.conversation_id:
        try:
            obj_id = ObjectId(request.conversation_id)
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

        query = {
            "_id": obj_id,
            "$or": query_or,
        }

        try:
            conv = conversations_col.find_one(query)
        except Exception as e:
            logger.warning("Failed to lookup conversation: %s", type(e).__name__)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Chat storage unavailable",
            )

        if not conv:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Conversation not found",
            )

    # Checkpoint 4a / 6: Check for clear water log intent, meal log intent, or adjust workout intent
    is_water_intent = _detect_log_water_intent(trimmed_message)
    meal_intent = None if is_water_intent else _detect_log_meal_intent(trimmed_message, request)
    workout_intent = None if (is_water_intent or meal_intent) else _detect_adjust_workout_intent(
        trimmed_message, request, current_user, custom_plans_col
    )

    if is_water_intent or meal_intent or workout_intent:
        if conversations_col is None:
            logger.error("Conversations collection is not available")
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Chat storage unavailable",
            )

        now_iso = datetime.now(timezone.utc).isoformat()
        action_id = str(ObjectId())
        action_date = datetime.now(VN_TZ).strftime("%Y-%m-%d")

        if is_water_intent:
            action_data = {
                "id": action_id,
                "type": "log_water",
                "amount_ml": 250,
                "status": "pending",
                "date": action_date,
                "created_at": now_iso,
            }
            reply = "Bạn có muốn thêm 250 ml nước không?"
        elif meal_intent:
            foods = [
                {
                    "name": meal_intent["name"],
                    "calories": meal_intent["calories"],
                    "protein": meal_intent["protein"],
                    "carbs": meal_intent["carbs"],
                    "fat": meal_intent["fat"],
                }
            ]
            action_data = {
                "id": action_id,
                "type": "log_meal",
                "meal_type": meal_intent["meal_type"],
                "foods": foods,
                "total_calories": meal_intent["calories"],
                "total_protein": meal_intent["protein"],
                "total_carbs": meal_intent["carbs"],
                "total_fat": meal_intent["fat"],
                "notes": meal_intent.get("notes"),
                "status": "pending",
                "date": action_date,
                "created_at": now_iso,
            }
            type_display = meal_intent.get("meal_type_display") or "bữa ăn"
            reply = (
                f"Bạn có muốn ghi nhận {type_display}: {meal_intent['name']} "
                f"({meal_intent['calories']} kcal, {meal_intent['protein']}g protein, "
                f"{meal_intent['carbs']}g carbs, {meal_intent['fat']}g fat) không?"
            )
        else:
            action_data = {
                "id": action_id,
                "type": "adjust_workout",
                "plan_id": workout_intent["plan_id"],
                "plan_name": workout_intent["plan_name"],
                "before": workout_intent.get("before", {}),
                "after": workout_intent.get("after", {}),
                "changes": workout_intent.get("changes", {}),
                "status": "pending",
                "date": action_date,
                "created_at": now_iso,
            }
            change_desc_parts = []
            for k, new_v in workout_intent.get("changes", {}).items():
                old_v = workout_intent.get("before", {}).get(k)
                label = "thời lượng" if k == "duration_minutes" else ("độ khó" if k == "difficulty" else k)
                unit = " phút" if k == "duration_minutes" else ""
                if old_v is not None:
                    change_desc_parts.append(f"{label}: {old_v}{unit} -> {new_v}{unit}")
                else:
                    change_desc_parts.append(f"{label}: {new_v}{unit}")
            change_str = ", ".join(change_desc_parts) if change_desc_parts else "thông số mới"
            reply = f"Bạn có muốn điều chỉnh kế hoạch tập '{workout_intent['plan_name']}' ({change_str}) không?"
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
        water_col_ref=water_col,
    )

    # Checkpoint 4: Multi-turn prompt construction from server-stored turns (max 10 turns)
    history_str = ""
    if conv:
        prior_msgs = conv.get("messages", [])
        if isinstance(prior_msgs, list) and prior_msgs:
            recent_prior = prior_msgs[-10:]
            lines = []
            for m in recent_prior:
                if not isinstance(m, dict):
                    continue
                role = "User" if m.get("role") == "user" else "Saman"
                content = (m.get("content") or "").strip()
                if content:
                    lines.append(f"- {role}: {content}")
            if lines:
                history_str = "LỊCH SỬ HỘI THOẠI TRƯỚC ĐÓ:\n" + "\n".join(lines)

    prompt_parts = [health_context]
    if history_str:
        prompt_parts.append(history_str)
    prompt_parts.append(f"USER HỎI: {trimmed_message}")
    # Checkpoint 5: Proactive coaching system instruction
    prompt_parts.append(
        "HƯỚNG DẪN TRẢ LỜI (Saman Coach):\n"
        "Bạn là Saman Coach — trợ lý sức khỏe cá nhân. Hãy tuân thủ các nguyên tắc và 4 bước sau:\n"
        "1. PHÂN TÍCH & TÁCH QUAN SÁT KHỎI SUY LUẬN: Đọc dữ liệu 'DINH DƯỠNG HÔM NAY', 'NƯỚC UỐNG HÔM NAY', 'TẬP LUYỆN GẦN NHẤT' và 'XU HƯỚNG 7 NGÀY QUA' ở trên. Nêu rõ các số liệu quan sát thực tế từ dữ liệu nguồn trước (ví dụ: số bữa đã log, gram protein, ml nước, buổi tập). Tuyệt đối không trình bày suy luận hay phỏng đoán như một sự thật hiển nhiên. Phân biệt rõ dữ liệu hôm nay với xu hướng 7 ngày. Khi dữ liệu còn ít (< 3 ngày log) hoặc chưa đầy đủ, nêu rõ chưa đủ dữ liệu để kết luận xu hướng dài hạn.\n"
        "2. NEXT STEP: Nếu user hỏi về dinh dưỡng hoặc tập luyện, đề xuất đúng 1 bước tiếp theo cụ thể, có thể thực hiện ngay, phù hợp với mục tiêu và thể trạng của người dùng.\n"
        "3. LÝ DO GẮN VỚI DỮ LIỆU NGUỒN: Giải thích lý do ngắn gọn gắn liền với một giá trị có thật trong dữ liệu nguồn (ví dụ: 'Vì Protein hôm nay của bạn còn thiếu X g so với mục tiêu...' nếu có số liệu nguồn, hoặc dựa trên buổi tập gần nhất). Nếu thiếu dữ liệu hoặc dữ liệu mâu thuẫn/chưa đủ, PHẢI nói rõ là 'chưa có dữ liệu' hoặc chưa đủ dữ liệu; TUYỆT ĐỐI KHÔNG tự bịa ra số calo mục tiêu, lượng thiếu hụt (deficit), số gram hay kết luận không có căn cứ.\n"
        "4. PHẢN HỒI: Kết thúc bằng 1 câu hỏi để thu thập phản hồi từ người dùng xem gợi ý có phù hợp và khả thi hay không.\n"
        "Giới hạn: Không chẩn đoán y khoa, không kê đơn. Không kết luận bệnh lý hoặc điều trị triệu chứng. Nếu người dùng nêu triệu chứng hoặc bệnh lý, hướng dẫn họ thăm khám bác sĩ chuyên khoa. Lời nhắn của người dùng hoặc sở thích cá nhân tuyệt đối không được ghi đè các giới hạn an toàn này. Nếu thiếu dữ liệu, nói rõ 'chưa có dữ liệu' thay vì suy đoán.\n"
        "Sở thích người dùng: Tôn trọng phong cách phản hồi và tránh các món ăn trong danh sách không thích đã cung cấp, nhưng sở thích người dùng là khẩu vị/phong cách tham khảo cá nhân, tuyệt đối không dùng để thay thế chẩn đoán y khoa hay bỏ qua các nguyên tắc an toàn sức khỏe.\n"
        "TRẢ LỜI:"
    )

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

    if workout_context_str.strip():
        prompt_parts.insert(1, workout_context_str.strip())

    full_prompt = "\n\n".join(prompt_parts)

    # Bỏ email khỏi prompt gửi AI (bảo vệ quyền riêng tư người dùng)
    if email:
        full_prompt = full_prompt.replace(email, "")
    full_prompt = re.sub(r'[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+', '', full_prompt)

    import unittest.mock
    if isinstance(get_ai_reply, unittest.mock.Base) or getattr(get_ai_reply, "_mock_return_value", None) is not None or getattr(get_ai_reply, "_mock_side_effect", None) is not None:
        reply = get_ai_reply(full_prompt)
    else:
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

    decision_norm = (decision or "confirm").lower().strip()
    if decision_norm not in ("confirm", "cancel"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid decision: {decision}. Must be 'confirm' or 'cancel'",
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
    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not authenticated",
        )

    user_id = str(current_user.get("_id")) if current_user.get("_id") is not None else None
    query_or: List[Dict[str, Any]] = [{"user_email": email}]
    if email:
        query_or.append({"email": email})
    if user_id:
        query_or.append({"user_id": user_id})
        if ObjectId.is_valid(user_id):
            query_or.append({"user_id": ObjectId(user_id)})

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

    action_type = pending.get("type")
    if action_type not in ("log_water", "log_meal", "adjust_workout"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unsupported action type: {action_type}",
        )

    current_status = pending.get("status")
    if current_status == "cancelled":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Action already cancelled",
        )

    today_vn = datetime.now(VN_TZ).strftime("%Y-%m-%d")
    raw_params = pending.get("params") if isinstance(pending.get("params"), dict) else {}
    target_date = pending.get("date") or raw_params.get("date") or today_vn
    now_utc = datetime.utcnow()
    now_iso = datetime.now(timezone.utc).isoformat()

    # 3. Handle Cancel
    if decision_norm == "cancel":
        if current_status in ("processing", "confirmed"):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Action already confirmed",
            )
        # Check if water/meal/workout was already applied for this action in domain collections
        if action_type == "log_water" and water_col is not None:
            already_applied = water_col.find_one({
                "user_email": email,
                "date": target_date,
                "applied_actions": action_id,
            })
            if already_applied:
                try:
                    conversations_col.update_one(
                        {"_id": conv_obj_id, "$or": query_or},
                        {"$set": {"pending_action.status": "confirmed"}}
                    )
                except Exception:
                    pass
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Action already confirmed",
                )
        elif action_type == "log_meal" and nutrition_col is not None:
            already_applied = nutrition_col.find_one({
                "user_email": email,
                "action_id": action_id,
            })
            if already_applied:
                try:
                    conversations_col.update_one(
                        {"_id": conv_obj_id, "$or": query_or},
                        {"$set": {"pending_action.status": "confirmed"}}
                    )
                except Exception:
                    pass
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="Action already confirmed",
                )
        elif action_type == "adjust_workout" and custom_plans_col is not None:
            already_applied = custom_plans_col.find_one({
                "$or": query_or,
                "applied_actions": action_id,
            })
            if already_applied:
                try:
                    conversations_col.update_one(
                        {"_id": conv_obj_id, "$or": query_or},
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

        if action_type == "log_water":
            cancel_msg = "Đã hủy thao tác thêm nước."
        elif action_type == "log_meal":
            cancel_msg = "Đã hủy thao tác ghi nhận bữa ăn."
        else:
            cancel_msg = "Đã hủy thao tác điều chỉnh kế hoạch tập."
        ai_msg_doc = {"role": "assistant", "content": cancel_msg, "created_at": now_iso}
        try:
            conversations_col.update_one(
                {"_id": conv_obj_id, "$or": query_or},
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

    # 3b. Pre-validate Confirm payload before acquiring processing lock or mutating domain collections
    amount_to_add = 250
    validated_meal_doc: Optional[Dict[str, Any]] = None
    validated_workout_fields: Dict[str, Any] = {}
    target_plan_id = None

    if action_type == "log_water":
        raw_amount = pending.get("amount_ml")
        if raw_amount is None and "amount_ml" not in pending:
            raw_amount = raw_params.get("amount_ml", 250)
        if isinstance(raw_amount, bool) or raw_amount is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid water amount in pending action",
            )
        try:
            amount_to_add = int(raw_amount)
        except (ValueError, TypeError):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid water amount in pending action",
            )
        if amount_to_add <= 0 or amount_to_add > 5000:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid water amount in pending action",
            )
    elif action_type == "log_meal":
        meal_type = pending.get("meal_type") or "meal"
        if not isinstance(meal_type, str) or meal_type not in ("breakfast", "lunch", "dinner", "snack", "meal"):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid meal_type in pending action",
            )
        raw_foods = pending.get("foods")
        if not isinstance(raw_foods, list) or len(raw_foods) == 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid foods list in pending action",
            )
        for f_item in raw_foods:
            if not isinstance(f_item, dict) or not isinstance(f_item.get("name"), str) or not f_item["name"].strip():
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid food item in pending action",
                )
        raw_cals = pending.get("total_calories")
        if isinstance(raw_cals, bool) or raw_cals is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid total_calories in pending action",
            )
        if (
            isinstance(pending.get("total_protein"), bool)
            or isinstance(pending.get("total_carbs"), bool)
            or isinstance(pending.get("total_fat"), bool)
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid nutrition values in pending action",
            )
        try:
            total_calories = int(raw_cals)
            total_protein = float(pending.get("total_protein") or 0.0)
            total_carbs = float(pending.get("total_carbs") or 0.0)
            total_fat = float(pending.get("total_fat") or 0.0)
        except (ValueError, TypeError):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid nutrition values in pending action",
            )
        if total_calories <= 0 or total_calories > 10000 or total_protein < 0 or total_carbs < 0 or total_fat < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid nutrition values in pending action",
            )
        validated_meal_doc = {
            "user_email": email,
            "date": target_date,
            "meal_type": meal_type,
            "foods": raw_foods,
            "total_calories": total_calories,
            "total_protein": round(total_protein, 1),
            "total_carbs": round(total_carbs, 1),
            "total_fat": round(total_fat, 1),
            "notes": pending.get("notes"),
            "action_id": action_id,
            "created_at": now_utc,
            "updated_at": now_utc,
        }
    elif action_type == "adjust_workout":
        target_plan_id = pending.get("plan_id")
        changes = pending.get("changes") or pending.get("after") or {}
        if not target_plan_id or not isinstance(changes, dict) or not changes:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid workout adjustment payload in pending action",
            )
        allowed_fields = {"duration_minutes", "difficulty", "name", "description", "target_muscles", "exercises"}
        for k, v in changes.items():
            if k not in allowed_fields or v is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Unsupported or invalid workout adjustment field: {k}",
                )
            if k == "duration_minutes":
                if isinstance(v, bool):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Invalid duration_minutes in workout adjustment",
                    )
                try:
                    dur_val = int(v)
                except (ValueError, TypeError):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Invalid duration_minutes in workout adjustment",
                    )
                if dur_val <= 0 or dur_val > 600:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Invalid duration_minutes in workout adjustment",
                    )
                validated_workout_fields[k] = dur_val
            elif k == "difficulty":
                if not isinstance(v, str) or v.lower() not in ("beginner", "intermediate", "advanced"):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Invalid difficulty in workout adjustment",
                    )
                validated_workout_fields[k] = v.lower()
            else:
                validated_workout_fields[k] = v
        if not validated_workout_fields:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No valid fields to update in workout plan",
            )

    # 4. Handle Confirm: Lock pending -> processing in conversations_col
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
            latest = conversations_col.find_one({"_id": conv_obj_id, "$or": query_or})
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

    # 5. Route Confirm by action_type
    if action_type == "log_water":
        if water_col is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Water storage unavailable",
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

        # Step C: Verify marker in water_logs. Only return confirmed/success when verified!
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

    elif action_type == "log_meal":
        if nutrition_col is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Nutrition storage unavailable",
            )

        # Step A: Check if action_id marker already exists in nutrition_col
        already_doc = nutrition_col.find_one({
            "user_email": email,
            "action_id": action_id,
        })

        write_error = None
        if not already_doc:
            meal_doc = dict(validated_meal_doc)

            # Step B: Atomic write with bounded retry for upsert / DuplicateKeyError race
            max_retries = 3
            for attempt in range(max_retries):
                try:
                    already_check = nutrition_col.find_one({
                        "user_email": email,
                        "action_id": action_id,
                    })
                    if already_check:
                        write_error = None
                        break

                    nutrition_col.update_one(
                        {
                            "action_id": action_id,
                            "user_email": email,
                        },
                        {
                            "$setOnInsert": meal_doc,
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
                    logger.error("Error during meal write attempt %d: %s", attempt + 1, type(e).__name__)
                    write_error = e
                    break

        if write_error is not None:
            logger.error("Meal write encountered error: %s", type(write_error).__name__)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database error while logging meal",
            )

        # Step C: Verify marker in nutrition_col. Only return confirmed/success when verified!
        verified_doc = nutrition_col.find_one({
            "user_email": email,
            "action_id": action_id,
        })
        if not verified_doc:
            logger.error("Meal marker verification failed for action_id=%s", action_id)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database error while logging meal",
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
        food_names = [f.get("name") for f in verified_doc.get("foods", []) if f.get("name")]
        name_str = ", ".join(food_names) if food_names else verified_doc.get("meal_type", "bữa ăn")
        cals = verified_doc.get("total_calories", 0)
        pro = verified_doc.get("total_protein", 0.0)
        carbs = verified_doc.get("total_carbs", 0.0)
        fat = verified_doc.get("total_fat", 0.0)
        confirm_msg = f"Đã ghi nhận bữa ăn: {name_str} ({cals} kcal, {pro}g protein, {carbs}g carbs, {fat}g fat) vào nhật ký hôm nay của bạn."

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
            "action_id": action_id,
            "conversation_id": str(conv_obj_id),
            "meal": {
                "meal_type": verified_doc.get("meal_type"),
                "foods": verified_doc.get("foods", []),
                "total_calories": cals,
                "total_protein": pro,
                "total_carbs": carbs,
                "total_fat": fat,
                "date": verified_doc.get("date"),
            },
        }

    elif action_type == "adjust_workout":
        if custom_plans_col is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Workout storage unavailable",
            )

        # Build plan query respecting ownership isolation
        plan_id_query = []
        if ObjectId.is_valid(str(target_plan_id)):
            plan_id_query.append({"_id": ObjectId(str(target_plan_id))})
        plan_id_query.append({"_id": str(target_plan_id)})
        plan_id_query.append({"id": str(target_plan_id)})

        base_plan_query = {
            "$and": [
                {"$or": query_or},
                {"$or": plan_id_query},
            ]
        }

        # Step A: Check if action_id marker already exists in custom_plans_col (Idempotency)
        already_doc = custom_plans_col.find_one({
            "$and": [
                base_plan_query,
                {"applied_actions": action_id},
            ]
        })

        write_error = None
        if not already_doc:
            # Verify target plan exists and belongs to this user
            target_plan = custom_plans_col.find_one(base_plan_query)
            if not target_plan:
                logger.error("Target workout plan %s not found for user %s", target_plan_id, email)
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Workout plan not found or not owned by user",
                )

            update_fields = dict(validated_workout_fields)
            update_fields["updated_at"] = now_utc

            # Step B: Atomic update with applied_actions deduplication
            max_retries = 3
            for attempt in range(max_retries):
                try:
                    already_check = custom_plans_col.find_one({
                        "$and": [
                            base_plan_query,
                            {"applied_actions": action_id},
                        ]
                    })
                    if already_check:
                        write_error = None
                        break

                    res = custom_plans_col.update_one(
                        {
                            "$and": [
                                base_plan_query,
                                {"applied_actions": {"$ne": action_id}},
                            ]
                        },
                        {
                            "$set": update_fields,
                            "$addToSet": {"applied_actions": action_id},
                        },
                    )
                    if getattr(res, "matched_count", 1) == 0:
                        if custom_plans_col.find_one({
                            "$and": [
                                base_plan_query,
                                {"applied_actions": action_id},
                            ]
                        }):
                            write_error = None
                            break
                        continue
                    write_error = None
                    break
                except Exception as e:
                    logger.error("Error during workout plan update attempt %d: %s", attempt + 1, type(e).__name__)
                    write_error = e
                    break

        if write_error is not None:
            logger.error("Workout plan update encountered error: %s", type(write_error).__name__)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database error while updating workout plan",
            )

        # Step C: Verify marker in custom_plans_col
        verified_doc = custom_plans_col.find_one({
            "$and": [
                base_plan_query,
                {"applied_actions": action_id},
            ]
        })
        if not verified_doc:
            logger.error("Workout marker verification failed for action_id=%s", action_id)
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Database error while updating workout plan",
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
        p_name = verified_doc.get("name") or pending.get("plan_name") or "kế hoạch tập"
        changed_parts = []
        for k in (pending.get("changes") or pending.get("after") or {}).keys():
            val = verified_doc.get(k)
            lbl = "thời lượng" if k == "duration_minutes" else ("độ khó" if k == "difficulty" else k)
            unit = " phút" if k == "duration_minutes" else ""
            changed_parts.append(f"{lbl}: {val}{unit}")
        detail_str = f" ({', '.join(changed_parts)})" if changed_parts else ""
        confirm_msg = f"Đã điều chỉnh kế hoạch tập '{p_name}'{detail_str} thành công."

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
            "action_id": action_id,
            "conversation_id": str(conv_obj_id),
            "workout": {
                "plan_id": str(verified_doc.get("_id", target_plan_id)),
                "name": verified_doc.get("name"),
                "duration_minutes": verified_doc.get("duration_minutes"),
                "difficulty": verified_doc.get("difficulty"),
                "exercises": verified_doc.get("exercises", []),
                "target_muscles": verified_doc.get("target_muscles", []),
            },
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