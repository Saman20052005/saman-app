# [File: routers/chat.py]
from typing import Optional, Dict, List, Any, Tuple
from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
import os
import re
import logging
from datetime import datetime, date, timezone, timedelta
from bson import ObjectId

# 🔥 REPOSITORIES & DATABASE
from backend.app.repositories.user_repository import UserRepository
from backend.app.database import workout_history_collection, exercises_collection
try:
    from backend.app.data.exercises.back import BACK_EXERCISES
except Exception:
    BACK_EXERCISES = []

# Auth
from backend.auth_utils import verify_token, get_current_user

try:
    from zoneinfo import ZoneInfo
    ICT_ZONE = ZoneInfo("Asia/Ho_Chi_Minh")
except Exception:
    ICT_ZONE = timezone(timedelta(hours=7))

router = APIRouter(prefix="/api/chat", tags=["AI Chat"])

# Khởi tạo Repo
user_repo = UserRepository()

# 🔑 KEY CỦA BẠN
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")

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
    if exercises_collection is not None:
        try:
            doc = None
            if exercise_slug:
                doc = exercises_collection.find_one({"slug": exercise_slug})
            if not doc and exercise_id:
                doc = exercises_collection.find_one({"id": exercise_id})
                if not doc:
                    try:
                        doc = exercises_collection.find_one({"_id": ObjectId(exercise_id)})
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
    if workout_history_collection is None:
        raise RuntimeError("Cơ sở dữ liệu workout_history không khả dụng (collection is None)")
    query = {"user_id": user_id}
    cursor = workout_history_collection.find(query)
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


# ─── ROUTE DEFINITION ─────────────────────────────────────────────────────────

class ChatRequest(BaseModel):
    message: str
    context: Optional[Dict] = None
    history: Optional[List] = None


@router.post("")
async def chat_with_ai(
    request: ChatRequest,
    current_user: dict = Depends(get_current_user)
):
    try:
        # 🔥 Lấy ID từ authenticated user_id principal, không tin client owner/context
        user_id = str(current_user["_id"])
        user = current_user

        user_context_str = ""
        if user and "profile" in user and user["profile"]:
            p = user["profile"]
            stats = user.get("health_stats", {})
            user_context_str = f"""
            HỒ SƠ NGƯỜI DÙNG:
            - Tên: {user.get('full_name', 'Bạn')}
            - Cân nặng: {p.get('weight')}kg
            - Mục tiêu: {p.get('goal', 'sống khỏe')}
            - TDEE: {stats.get('tdee', 'chưa tính')} kcal
            """

        # 🏋️ Workout Grounding Retrieval
        workout_context_str = ""
        retrieval_meta = None
        query_type, target_date_iso, error_reason = parse_date_query(request.message)
        if query_type != "NONE":
            workout_context_str, retrieval_meta = build_workout_grounding_context(
                user_id=user_id,
                query_type=query_type,
                target_date_iso=target_date_iso,
                error_reason=error_reason
            )

        # Xây dựng prompt
        prompt_parts = []
        if user_context_str.strip():
            prompt_parts.append(user_context_str.strip())
        if workout_context_str.strip():
            prompt_parts.append(workout_context_str.strip())
        prompt_parts.append(f"USER HỎI: {request.message}")
        prompt_parts.append("TRẢ LỜI NGẮN GỌN & THÂN THIỆN:")

        full_prompt = "\n\n".join(prompt_parts)

        # Gọi existing real AI provider call
        reply = get_ai_reply(full_prompt)

        status = "success" if not reply.startswith("Lỗi:") else "error"
        response_data: Dict[str, Any] = {
            "reply": reply,
            "status": status,
        }

        # Additive retrieval metadata: nhỏ, an toàn và phản ánh retrieval thực tế
        if retrieval_meta:
            response_data["retrieval"] = {
                "grounded": status == "success" and retrieval_meta.get("applied", False),
                "query_type": retrieval_meta.get("query_type"),
                "sessions_found": retrieval_meta.get("sessions_count", 0),
            }

        return response_data

    except Exception as e:
        logging.error(f"Chat Route Error: {e}")
        return {
            "reply": f"Lỗi hệ thống: {str(e)}",
            "status": "error"
        }
