"""Barcode lookup & normalization service (MongoDB cache + Open Food Facts)."""

from datetime import datetime, timezone
import logging
import math
import re
from typing import Any, Dict, Optional

from bson import ObjectId

try:
    import httpx
except ImportError:  # pragma: no cover
    httpx = None  # type: ignore[assignment]

logger = logging.getLogger(__name__)

OPEN_FOOD_FACTS_URL_TEMPLATE = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
OPEN_FOOD_FACTS_USER_AGENT = "SamanFitness/1.0"
OPEN_FOOD_FACTS_TIMEOUT_SECONDS = 8.0

_BARCODE_RE = re.compile(r"^[0-9]{6,14}$")
_SERVING_RE = re.compile(r"(\d+(?:[.,]\d+)?)\s*(kg|g|gr|gram|grams|ml|l)\b", re.IGNORECASE)


def normalize_and_validate_barcode(barcode: str) -> str:
    """Strip whitespace and validate that barcode is 6-14 ASCII digits."""
    if not isinstance(barcode, str):
        raise ValueError("Barcode must be a numeric string of 6-14 digits.")
    cleaned = barcode.strip()
    if not _BARCODE_RE.fullmatch(cleaned):
        raise ValueError("Barcode must contain 6 to 14 digits.")
    return cleaned


def _to_non_negative_float(value: Any) -> Optional[float]:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        num = float(value)
    elif isinstance(value, str):
        text = value.strip().replace(",", ".")
        if not text:
            return None
        try:
            num = float(text)
        except ValueError:
            return None
    else:
        return None
    if not math.isfinite(num) or num < 0:
        return None
    return num


def parse_serving_grams(serving_size: Optional[str], serving_quantity: Any = None) -> float:
    """Parse serving weight/volume in grams (default 100.0 if unavailable or invalid)."""
    qty = _to_non_negative_float(serving_quantity)
    if qty is not None and qty > 0:
        return round(qty, 1)

    if isinstance(serving_size, str) and serving_size.strip():
        match = _SERVING_RE.search(serving_size)
        if match:
            raw_num = match.group(1).replace(",", ".")
            unit = match.group(2).lower()
            try:
                val = float(raw_num)
                if unit in ("kg", "l"):
                    val *= 1000.0
                if math.isfinite(val) and val > 0:
                    return round(val, 1)
            except ValueError:
                pass
        else:
            bare = _to_non_negative_float(serving_size)
            if bare is not None and bare > 0:
                return round(bare, 1)

    return 100.0


def _format_serving_label(serving_size: Optional[str], serving_grams: float) -> str:
    cleaned = str(serving_size or "").strip()
    if cleaned:
        return cleaned
    if float(serving_grams).is_integer():
        return f"{int(serving_grams)}g"
    return f"{serving_grams}g"


def _normalize_per_100g(per_100g: Optional[Dict[str, Any]]) -> Dict[str, float]:
    raw = per_100g if isinstance(per_100g, dict) else {}
    out: Dict[str, float] = {}
    for key in ("calories", "protein", "carbs", "fat", "fiber"):
        val = _to_non_negative_float(raw.get(key))
        out[key] = round(val if val is not None else 0.0, 1)
    return out


def format_barcode_food_doc(doc: Dict[str, Any]) -> Dict[str, Any]:
    """Serialize a food_barcodes Mongo document into a clean JSON-safe food payload."""
    raw_id = doc.get("_id")
    food_id = str(raw_id) if raw_id is not None else str(doc.get("id") or "")

    per_100g_raw = doc.get("per_100g")
    if isinstance(per_100g_raw, dict):
        per_100g = _normalize_per_100g(per_100g_raw)
    else:
        per_100g = _normalize_per_100g({
            "calories": doc.get("calories"),
            "protein": doc.get("protein"),
            "carbs": doc.get("carbs"),
            "fat": doc.get("fat"),
            "fiber": doc.get("fiber"),
        })

    serving_grams = parse_serving_grams(doc.get("serving_size"), doc.get("serving_grams"))
    serving_size = _format_serving_label(doc.get("serving_size"), serving_grams)

    return {
        "id": food_id,
        "barcode": str(doc.get("barcode") or ""),
        "name": str(doc.get("name") or ""),
        "brand": str(doc.get("brand") or ""),
        "serving_size": serving_size,
        "serving_grams": serving_grams,
        "standard_serving": serving_grams,
        "unit": str(doc.get("unit") or "g"),
        "calories": per_100g["calories"],
        "protein": per_100g["protein"],
        "carbs": per_100g["carbs"],
        "fat": per_100g["fat"],
        "fiber": per_100g["fiber"],
        "per_100g": per_100g,
        "image_url": str(doc.get("image_url") or ""),
        "source": str(doc.get("source") or "open_food_facts"),
        "source_type": "barcode",
    }


def upsert_barcode_food(
    barcodes_col: Any,
    barcode: str,
    *,
    name: str,
    per_100g: Dict[str, Any],
    brand: str = "",
    serving_size: str = "",
    serving_grams: Any = None,
    image_url: str = "",
    source: str = "open_food_facts",
) -> Dict[str, Any]:
    """Upsert normalized barcode food into food_barcodes collection with ObjectId _id."""
    cleaned_barcode = normalize_and_validate_barcode(barcode)
    normalized_macros = _normalize_per_100g(per_100g)
    parsed_grams = parse_serving_grams(serving_size, serving_grams)
    formatted_serving = _format_serving_label(serving_size, parsed_grams)
    now = datetime.now(timezone.utc)
    new_oid = ObjectId()

    set_fields = {
        "barcode": cleaned_barcode,
        "name": str(name or "").strip(),
        "brand": str(brand or "").strip(),
        "serving_size": formatted_serving,
        "serving_grams": parsed_grams,
        "standard_serving": parsed_grams,
        "unit": "g",
        "calories": normalized_macros["calories"],
        "protein": normalized_macros["protein"],
        "carbs": normalized_macros["carbs"],
        "fat": normalized_macros["fat"],
        "fiber": normalized_macros["fiber"],
        "per_100g": normalized_macros,
        "image_url": str(image_url or "").strip(),
        "source": source,
        "source_type": "barcode",
        "updated_at": now,
    }

    saved_doc = None
    if barcodes_col is not None:
        res = barcodes_col.update_one(
            {"barcode": cleaned_barcode},
            {
                "$set": set_fields,
                "$setOnInsert": {
                    "_id": new_oid,
                    "created_at": now,
                },
            },
            upsert=True,
        )
        saved_doc = barcodes_col.find_one({"barcode": cleaned_barcode})
        if saved_doc is None:
            upserted_id = getattr(res, "upserted_id", None)
            oid = upserted_id if isinstance(upserted_id, ObjectId) else new_oid
            saved_doc = {"_id": oid, **set_fields}
        elif not isinstance(saved_doc.get("_id"), ObjectId):
            oid = ObjectId(saved_doc["_id"]) if ObjectId.is_valid(str(saved_doc.get("_id", ""))) else new_oid
            saved_doc["_id"] = oid
    else:
        saved_doc = {"_id": new_oid, **set_fields}

    return format_barcode_food_doc(saved_doc)


def _extract_off_per_100g(nutriments: Dict[str, Any]) -> Dict[str, float]:
    calories = _to_non_negative_float(nutriments.get("energy-kcal_100g"))
    if calories is None:
        kj = _to_non_negative_float(nutriments.get("energy-kj_100g"))
        if kj is not None:
            calories = kj / 4.184
        else:
            raw_energy = _to_non_negative_float(nutriments.get("energy_100g"))
            if raw_energy is not None:
                unit = str(nutriments.get("energy_unit") or "").strip().lower()
                calories = raw_energy if unit == "kcal" else raw_energy / 4.184
            else:
                calories = 0.0

    protein = _to_non_negative_float(nutriments.get("proteins_100g"))
    carbs = _to_non_negative_float(nutriments.get("carbohydrates_100g"))
    fat = _to_non_negative_float(nutriments.get("fat_100g"))
    fiber = _to_non_negative_float(nutriments.get("fiber_100g"))

    return {
        "calories": round(calories, 1),
        "protein": round(protein if protein is not None else 0.0, 1),
        "carbs": round(carbs if carbs is not None else 0.0, 1),
        "fat": round(fat if fat is not None else 0.0, 1),
        "fiber": round(fiber if fiber is not None else 0.0, 1),
    }


async def lookup_barcode(barcode: str, barcodes_col: Any) -> Optional[Dict[str, Any]]:
    """
    Lookup food nutrition info by barcode:
    1. Validate barcode (6-14 digits; invalid raises ValueError).
    2. Check MongoDB cache (`food_barcodes`).
    3. Fallback to Open Food Facts API v2; upsert valid result to cache.
    4. Return None if not found or product name is missing (never cache invalid entries).
    """
    cleaned = normalize_and_validate_barcode(barcode)

    # 1. Cache lookup
    if barcodes_col is not None:
        cached = barcodes_col.find_one({"barcode": cleaned})
        if isinstance(cached, dict):
            return {
                "found": True,
                "source": "cache",
                "barcode": cleaned,
                "food": format_barcode_food_doc(cached),
            }

    # 2. Fetch from Open Food Facts
    httpx_mod = httpx
    if httpx_mod is None:
        try:
            import httpx as httpx_mod  # type: ignore[no-redef]
        except ImportError:
            logger.warning("httpx is not installed; cannot fetch Open Food Facts for barcode=%s", cleaned)
            return None

    url = OPEN_FOOD_FACTS_URL_TEMPLATE.format(barcode=cleaned)
    headers = {"User-Agent": OPEN_FOOD_FACTS_USER_AGENT}
    timeout_exc = getattr(httpx_mod, "TimeoutException", TimeoutError)
    request_exc = getattr(httpx_mod, "RequestError", OSError)

    try:
        async with httpx_mod.AsyncClient(timeout=OPEN_FOOD_FACTS_TIMEOUT_SECONDS) as client:
            response = await client.get(url, headers=headers)
    except (timeout_exc, request_exc) as exc:
        logger.warning("Open Food Facts request failed for barcode=%s: %s", cleaned, exc)
        return None
    except Exception as exc:
        logger.warning("Unexpected Open Food Facts error for barcode=%s: %s", cleaned, exc)
        return None

    if response.status_code != 200:
        return None

    try:
        payload = response.json()
    except Exception:
        return None

    if not isinstance(payload, dict) or payload.get("status") != 1:
        return None

    product = payload.get("product")
    if not isinstance(product, dict):
        return None

    product_name = str(
        product.get("product_name_vi")
        or product.get("product_name")
        or product.get("product_name_en")
        or ""
    ).strip()
    if not product_name:
        return None

    brand = str(product.get("brands") or "").strip()
    image_url = str(product.get("image_front_url") or product.get("image_url") or "").strip()
    nutriments = product.get("nutriments") if isinstance(product.get("nutriments"), dict) else {}
    per_100g = _extract_off_per_100g(nutriments)
    serving_size_raw = str(product.get("serving_size") or "").strip()
    serving_grams = parse_serving_grams(serving_size_raw, product.get("serving_quantity"))

    saved_food = upsert_barcode_food(
        barcodes_col,
        cleaned,
        name=product_name,
        brand=brand,
        serving_size=serving_size_raw,
        serving_grams=serving_grams,
        per_100g=per_100g,
        image_url=image_url,
        source="open_food_facts",
    )

    return {
        "found": True,
        "source": "open_food_facts",
        "barcode": cleaned,
        "food": saved_food,
    }

