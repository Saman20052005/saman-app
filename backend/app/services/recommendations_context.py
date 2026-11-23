"""Conditionally retrieve a small set of relevant shop and journal entries."""

import re
import unicodedata
from itertools import islice
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


def _normalize_text(text: str) -> str:
    """Lowercase Vietnamese text, remove combining accents, and normalize đ."""
    value = unicodedata.normalize("NFD", str(text or ""))
    value = "".join(char for char in value if unicodedata.category(char) != "Mn")
    return value.replace("đ", "d").replace("Đ", "d").lower()


_SHOP_TERMS = (
    "goi y", "de xuat", "san pham", "mua", "dung cu", "thiet bi", "whey",
    "creatine", "protein", "dam", "casein", "bo sung", "day khang luc",
    "khong co ta", "tap o nha", "binh lac", "shaker", "con lan",
    "foam roller", "phuc hoi", "dien giai", "snack", "yem mach", "yen mach",
    "oats", "granola", "giai phap", "khac phuc", "thieu", "shop",
    "recommend", "suggest",
)
_JOURNAL_TERMS = (
    "tai sao", "vi sao", "nguyen ly", "cach", "kien thuc", "bai viet",
    "huong dan", "doc them", "doms", "dau co", "phuc hoi", "giac ngu",
    "ngu", "progressive overload", "tang ta", "calo", "macro", "protein",
    "giam mo", "tang co", "journal", "cam nang", "khoa hoc",
)
_PROTEIN_CUES = ("dam", "protein", "whey")
_NO_EQUIPMENT_CUES = ("o nha", "khong co dung cu", "day khang luc")
_RECOVERY_CUES = ("dau co", "doms", "nhuc", "phuc hoi", "moi", "ngu")
_HYDRATION_CUES = ("chuot rut", "dien giai", "mat nuoc")

_SHOP_PROJECTION = {
    "_id": 0, "id": 1, "title": 1, "subtitle": 1, "categoryId": 1,
    "subcategoryId": 1, "productType": 1, "priceVnd": 1,
    "searchNormalized": 1, "curatedOrder": 1,
}
_JOURNAL_PROJECTION = {
    "_id": 0, "id": 1, "title": 1, "summary": 1, "topic": 1,
    "read_time_minutes": 1, "tags": 1,
}


def _contains_any(text: str, terms: Sequence[str]) -> bool:
    return any(term in text for term in terms)


def _number(value: Any) -> Optional[float]:
    if isinstance(value, bool) or value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError, OverflowError):
        return None


def _iter_documents(collection: Any, query: Dict[str, Any], projection: Dict[str, int], limit: int) -> List[dict]:
    """Read a bounded cursor while supporting lightweight collection fakes."""
    try:
        cursor = collection.find(query, projection)
    except TypeError:
        cursor = collection.find(query)
    if hasattr(cursor, "limit"):
        try:
            limited = cursor.limit(limit)
            if limited is not None:
                cursor = limited
        except Exception:
            pass
    rows = list(islice(cursor, limit))
    return [row for row in rows if isinstance(row, dict)]


def _context_signals(question: str, base_context: Any) -> List[str]:
    context = base_context if isinstance(base_context, dict) else {}
    nutrition = context.get("nutrition")
    nutrition_rows = nutrition.get("summary", []) if isinstance(nutrition, dict) else []
    if not isinstance(nutrition_rows, list):
        nutrition_rows = []
    latest = next((row for row in reversed(nutrition_rows) if isinstance(row, dict)), {})

    profile = context.get("profile")
    profile_data = profile.get("data", {}) if isinstance(profile, dict) else {}
    if not isinstance(profile_data, dict):
        profile_data = {}
    health_stats = profile_data.get("health_stats", {})
    if not isinstance(health_stats, dict):
        health_stats = {}
    target = _number(health_stats.get("target_protein"))
    weight = _number(
        health_stats.get("weight", profile_data.get("weight", profile_data.get("weight_kg")))
    )
    if target is None and weight is not None:
        target = weight * 1.6
    protein = _number(latest.get("protein_g"))

    preferences = context.get("preferences")
    equipment = preferences.get("equipment") if isinstance(preferences, dict) else None
    if isinstance(equipment, str):
        equipment = [equipment] if equipment.strip() else []
    if not isinstance(equipment, (list, tuple, set)):
        equipment = []
    equipment_values = [_normalize_text(item) for item in equipment if item is not None]
    no_equipment = not equipment_values or all(item == "bodyweight" for item in equipment_values)

    water = context.get("water")
    water = water if isinstance(water, dict) else {}
    water_today = _number(water.get("today_ml"))
    water_target = _number(water.get("target_ml"))

    signals = []
    if (protein is not None and target is not None and target > 0 and protein < target * 0.8) or _contains_any(question, _PROTEIN_CUES):
        signals.append("protein_deficit")
    if no_equipment or _contains_any(question, _NO_EQUIPMENT_CUES):
        signals.append("no_equipment")
    if _contains_any(question, _RECOVERY_CUES):
        signals.append("recovery_need")
    if (
        water_today is not None and water_target is not None and water_target > 0
        and water_today < water_target * 0.6
    ) or _contains_any(question, _HYDRATION_CUES):
        signals.append("hydration_need")
    return signals


def _terms_for_question(norm_q: str) -> List[str]:
    return list(dict.fromkeys(re.findall(r"[a-z0-9]+", norm_q)))


def _field_text(document: dict, fields: Iterable[str]) -> str:
    values = []
    for field in fields:
        value = document.get(field)
        if isinstance(value, (list, tuple, set)):
            values.extend(str(item) for item in value if item is not None)
        elif value is not None:
            values.append(str(value))
    return _normalize_text(" ".join(values))


def _score_product(document: dict, norm_q: str, matched_signals: Sequence[str]) -> int:
    searchable = _field_text(document, ("title", "subtitle", "categoryId", "subcategoryId", "productType", "searchNormalized"))
    score = sum(2 for term in _terms_for_question(norm_q) if len(term) >= 3 and term in searchable)
    category = _normalize_text(document.get("categoryId", ""))
    text = searchable
    if "protein_deficit" in matched_signals and (
        category in ("cat_supplements", "cat_food_beverage")
        or _contains_any(text, ("whey", "protein", "oats", "yen mach", "yem mach", "granola"))
    ):
        score += 4
    if "no_equipment" in matched_signals and (
        category == "cat_gear" or _contains_any(text, ("day khang luc", "xa don", "ab wheel", "bodyweight"))
    ):
        score += 4
    if "recovery_need" in matched_signals and (
        category == "cat_recovery_lifestyle" or _contains_any(text, ("foam roller", "massage", "massage gun", "phuc hoi"))
    ):
        score += 4
    if "hydration_need" in matched_signals and _contains_any(text, ("dien giai", "electrolyte", "binh nuoc", "shaker")):
        score += 3
    return score


def _score_article(document: dict, norm_q: str, matched_signals: Sequence[str]) -> int:
    searchable = _field_text(document, ("title", "summary", "topic", "tags"))
    score = sum(2 for term in _terms_for_question(norm_q) if len(term) >= 3 and term in searchable)
    signal_terms = {
        "protein_deficit": ("protein", "dam", "dinh duong", "macro"),
        "no_equipment": ("tap tai nha", "bodyweight", "dung cu", "khang luc"),
        "recovery_need": ("phuc hoi", "doms", "dau co", "giac ngu", "ngu"),
        "hydration_need": ("nuoc", "dien giai", "mat nuoc", "chuot rut"),
    }
    for signal in matched_signals:
        if _contains_any(searchable, signal_terms.get(signal, ())):
            score += 3
    return score


def build_recommendations_context(
    *,
    question: str | None = None,
    base_context: dict | None = None,
    shop_products_collection=None,
    journal_articles_collection=None,
    tier: str = "core3",
) -> dict:
    """Return up to three relevant products and articles without exposing user data."""
    skipped = {
        "status": "skipped", "triggered": False, "matched_signals": [],
        "shop_products": [], "journal_articles": [],
    }
    try:
        if (tier or "core3").strip().lower() == "swift3" or not isinstance(question, str) or not question.strip():
            return skipped

        norm_q = _normalize_text(question)
        shop_intent = _contains_any(norm_q, _SHOP_TERMS)
        journal_intent = _contains_any(norm_q, _JOURNAL_TERMS)
        if not shop_intent and not journal_intent:
            return skipped

        matched_signals = _context_signals(norm_q, base_context)
        products = []
        articles = []
        shop_error = False
        journal_error = False

        if shop_intent and shop_products_collection is not None:
            try:
                rows = _iter_documents(
                    shop_products_collection,
                    {"publishState": "published", "availability": "available"},
                    _SHOP_PROJECTION,
                    100,
                )
                ranked: List[Tuple[int, float, dict]] = []
                for row in rows:
                    score = _score_product(row, norm_q, matched_signals)
                    if score > 0:
                        order = _number(row.get("curatedOrder"))
                        ranked.append((score, order if order is not None else float("inf"), row))
                ranked.sort(key=lambda item: (-item[0], item[1]))
                for _, _, row in ranked[:3]:
                    products.append({
                        "id": row.get("id"),
                        "title": row.get("title"),
                        "subtitle": str(row.get("subtitle") or "")[:100],
                        "category_id": row.get("categoryId"),
                        "price_vnd": row.get("priceVnd"),
                    })
            except Exception:
                shop_error = True

        if journal_intent and journal_articles_collection is not None:
            try:
                rows = _iter_documents(journal_articles_collection, {}, _JOURNAL_PROJECTION, 30)
                ranked_articles = []
                for row in rows:
                    score = _score_article(row, norm_q, matched_signals)
                    if score > 0:
                        ranked_articles.append((score, row))
                ranked_articles.sort(key=lambda item: -item[0])
                for _, row in ranked_articles[:3]:
                    articles.append({
                        "id": row.get("id"),
                        "title": row.get("title"),
                        "summary": str(row.get("summary") or "")[:120],
                        "topic": row.get("topic"),
                        "read_time_minutes": row.get("read_time_minutes"),
                    })
            except Exception:
                journal_error = True

        needed_collection_missing = (shop_intent and shop_products_collection is None) or (
            journal_intent and journal_articles_collection is None
        )
        if products or articles:
            status = "available"
        elif needed_collection_missing:
            status = "unavailable"
        else:
            status = "empty"
        # DB errors are fail-soft. Keep the response schema stable and never include error text.
        _ = shop_error, journal_error
        return {
            "status": status,
            "triggered": True,
            "matched_signals": matched_signals,
            "shop_products": products,
            "journal_articles": articles,
        }
    except Exception:
        return skipped
