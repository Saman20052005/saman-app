"""Deterministic lightweight intent router for AI Chat (Phase 4).

Classifies user questions into 5 domains without LLM cost:
- full_audit: deep audit, multi-domain comparison, weekly/monthly reviews, or cross-checking.
- workout_form: form analysis, CV metrics, rep count, tempo, exercises.
- recovery: muscle fatigue, soreness, DOMS, sleep/rest, 72h recovery.
- nutrition: calories, macros, meals, water, recipes, supplements.
- general_chat: greetings, short casual pleasantries.
"""

from dataclasses import dataclass
import re
import unicodedata
from typing import FrozenSet


@dataclass(frozen=True)
class IntentRouteResult:
    intent: str
    collections: FrozenSet[str]
    include_video_citations: bool
    prefer_lightweight_model: bool
    reason: str


ALL_COLLECTIONS: FrozenSet[str] = frozenset({
    "profile",
    "nutrition",
    "water",
    "workout",
    "recovery",
    "weight",
    "journey",
    "story_logs",
    "community",
    "supplements",
    "recipes",
    "recommendations",
    "video_stories",
})

WORKOUT_FORM_COLLECTIONS: FrozenSet[str] = frozenset({
    "profile",
    "workout",
    "recovery",
    "video_stories",
})

RECOVERY_COLLECTIONS: FrozenSet[str] = frozenset({
    "profile",
    "workout",
    "recovery",
    "water",
})

NUTRITION_COLLECTIONS: FrozenSet[str] = frozenset({
    "profile",
    "nutrition",
    "water",
    "weight",
    "supplements",
    "recipes",
})

GENERAL_CHAT_COLLECTIONS: FrozenSet[str] = frozenset({
    "profile",
})


def _strip_accents(text: str) -> str:
    """Normalize and remove Vietnamese accents for robust keyword matching."""
    text = unicodedata.normalize("NFD", text)
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Mn")
    return unicodedata.normalize("NFC", text)


def _contains_any(text: str, norm_text: str, keywords: tuple[str, ...]) -> bool:
    for kw in keywords:
        pattern = r"\b" + re.escape(kw) + r"\b"
        if re.search(pattern, text) or re.search(pattern, norm_text):
            return True
    return False


_AUDIT_KEYWORDS = (
    "phan tich sau", "phân tích sâu", "audit", "tong ket", "tổng kết",
    "doi chieu", "đối chiếu", "diem yeu", "điểm yếu", "tai sao", "tại sao",
    "ly do", "lý do", "tuan nay", "tuần này", "thang nay", "tháng này",
    "30 ngay", "30 ngày", "cross-check", "cross check", "tong quan", "tổng quan",
    "danh gia toan dien", "đánh giá toàn diện", "bao cao tong hop", "báo cáo tổng hợp",
)

_WORKOUT_KEYWORDS = (
    "form", "rep", "tempo", "goc", "góc", "video", "lat pulldown", "pull up", "pull-up",
    "squat", "push up", "push-up", "bicep", "buoi tap", "buổi tập", "tap luyen", "tập luyện",
    "ta", "tạ", "pr", "hiep", "hiệp", "ky thuat", "kỹ thuật", "loi", "lỗi", "exercise",
    "workout", "bench press", "deadlift", "cv", "tu the", "tư thế", "sai form",
)

_RECOVERY_KEYWORDS = (
    "phuc hoi", "phục hồi", "recovery", "moi", "mỏi", "dau co", "đau cơ", "doms",
    "nghi", "nghỉ", "fatigue", "overtraining", "ngu", "ngủ", "nhom co", "nhóm cơ",
    "tap nhom nao", "tập nhóm nào", "co bap", "cơ bắp", "cang co", "căng cơ", "rest", "soreness",
)

_NUTRITION_KEYWORDS = (
    "calo", "calorie", "protein", "carb", "fat", "macro", "bua an", "bữa ăn", "mon an", "món ăn",
    "nuoc", "nước", "ml", "uong", "uống", "can nang", "cân nặng", "weight",
    "tdee", "bmr", "thuc don", "thực đơn", "supplement", "thuc pham bo sung", "thực phẩm bổ sung",
    "whey", "creatine", "dinh duong", "dinh dưỡng", "diet", "meal", "recipe", "cong thuc", "công thức",
)

_GREETING_PATTERNS = (
    r"^(xin\s+)?chao(\s+ban|\s+ai|\s+bot)?$",
    r"^(xin\s+)?chào(\s+bạn|\s+ai|\s+bot)?$",
    r"^hi(\s+there|\s+bot|\s+ai)?$",
    r"^hello(\s+there|\s+bot|\s+ai)?$",
    r"^(cam\s+on|cảm\s+ơn|cám\s+ơn|thanks|thank\s+you)(\s+nhe|\s+nhé|\s+nhieu|\s+nhiều)?$",
    r"^(ok|oke|okay|alo|hey|ê|e)$",
)


def classify_chat_intent(
    message: str,
    *,
    ai_mode: str = "core3",
    has_workout_payload: bool = False,
    has_meal_payload: bool = False,
) -> IntentRouteResult:
    """Classify user chat intent deterministically without external LLM calls.

    Returns an IntentRouteResult containing target collections, video citation flags,
    model preference, and classification reason.
    """
    raw_text = (message or "").strip().lower()
    norm_text = _strip_accents(raw_text)

    # 1. Check for general greeting / short casual pleasantries
    if not has_workout_payload and not has_meal_payload and len(raw_text) <= 40:
        for pat in _GREETING_PATTERNS:
            if re.match(pat, raw_text) or re.match(pat, norm_text):
                return IntentRouteResult(
                    intent="general_chat",
                    collections=GENERAL_CHAT_COLLECTIONS,
                    include_video_citations=False,
                    prefer_lightweight_model=True,
                    reason="Greeting / casual pleasantry detected",
                )

    # Detect domain matches
    has_audit_kw = _contains_any(raw_text, norm_text, _AUDIT_KEYWORDS)
    has_workout_kw = has_workout_payload or _contains_any(raw_text, norm_text, _WORKOUT_KEYWORDS)
    has_recovery_kw = _contains_any(raw_text, norm_text, _RECOVERY_KEYWORDS)
    has_nutrition_kw = has_meal_payload or _contains_any(raw_text, norm_text, _NUTRITION_KEYWORDS)

    # Count how many distinct domains matched (workout, recovery, nutrition)
    domains_hit = sum([bool(has_workout_kw), bool(has_recovery_kw), bool(has_nutrition_kw)])

    # 2. full_audit condition
    # - pro3 mode with audit keyword, OR
    # - audit keyword + at least one domain, OR
    # - cross-domain query touching >= 2 distinct domains simultaneously
    if (ai_mode == "pro3" and (has_audit_kw or domains_hit >= 2)) or (has_audit_kw and domains_hit >= 1) or (domains_hit >= 2):
        return IntentRouteResult(
            intent="full_audit",
            collections=ALL_COLLECTIONS,
            include_video_citations=True,
            prefer_lightweight_model=False,
            reason=f"Multi-domain audit (hits={domains_hit}, audit_kw={has_audit_kw}, mode={ai_mode})",
        )

    # 3. workout_form condition
    if has_workout_kw:
        return IntentRouteResult(
            intent="workout_form",
            collections=WORKOUT_FORM_COLLECTIONS,
            include_video_citations=True,
            prefer_lightweight_model=False,
            reason="Workout form / CV exercise inquiry",
        )

    # 4. recovery condition
    if has_recovery_kw:
        return IntentRouteResult(
            intent="recovery",
            collections=RECOVERY_COLLECTIONS,
            include_video_citations=False,
            prefer_lightweight_model=False,
            reason="Muscle recovery & fatigue inquiry",
        )

    # 5. nutrition condition
    if has_nutrition_kw:
        return IntentRouteResult(
            intent="nutrition",
            collections=NUTRITION_COLLECTIONS,
            include_video_citations=False,
            prefer_lightweight_model=False,
            reason="Nutrition, meal, or calorie inquiry",
        )

    # Default fallback: general_chat if very short, or fallback to workout+nutrition baseline
    if len(raw_text) <= 20:
        return IntentRouteResult(
            intent="general_chat",
            collections=GENERAL_CHAT_COLLECTIONS,
            include_video_citations=False,
            prefer_lightweight_model=True,
            reason="Default short message fallback to general chat",
        )

    return IntentRouteResult(
        intent="general_chat",
        collections=frozenset({"profile", "workout", "nutrition"}),
        include_video_citations=False,
        prefer_lightweight_model=False,
        reason="Default broad conversational query",
    )
