# [File: backend/services/gemini_food_analyzer.py]
import base64
import json
import logging
import math
import os
from typing import Optional, Dict, Any

import httpx

logger = logging.getLogger(__name__)

GEMINI_FOOD_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "is_food": {
            "type": "boolean",
            "description": "True if the image contains recognizable food or beverage, False otherwise."
        },
        "food_name": {
            "type": "string",
            "description": "The specific name of the food dish (e.g., 'Phở Bò', 'Chicken Salad')."
        },
        "dish_name": {"type": "string"},
        "food_label": {
            "type": "string",
            "description": "A lowercase snake_case label for the dish (e.g., 'pho_bo', 'chicken_salad')."
        },
        "confidence": {
            "type": "number",
            "description": "Estimated confidence score between 0.0 and 1.0 for the dish identification."
        },
        "total_weight_grams": {"type": "number"},
        "total_nutrition": {
            "type": "object",
            "properties": {
                "calories": {"type": "number"},
                "protein": {"type": "number"},
                "carbs": {"type": "number"},
                "fat": {"type": "number"},
                "fiber": {"type": "number"},
            },
            "required": ["calories", "protein", "carbs", "fat", "fiber"]
        },
        "ingredients": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "portion_grams": {"type": "number"},
                    "calories": {"type": "number"},
                    "protein": {"type": "number"},
                    "carbs": {"type": "number"},
                    "fat": {"type": "number"},
                    "confidence": {"type": "number"},
                },
                "required": ["name", "portion_grams", "calories", "protein", "carbs", "fat", "confidence"]
            }
        },
        "health_insights": {"type": "array", "items": {"type": "string"}},
        "per_100g": {
            "type": "object",
            "properties": {
                "calories": {"type": "number", "description": "Calories per 100g in kcal."},
                "protein": {"type": "number", "description": "Protein per 100g in grams."},
                "carbs": {"type": "number", "description": "Total carbohydrates per 100g in grams."},
                "fat": {"type": "number", "description": "Total fat per 100g in grams."}
            },
            "required": ["calories", "protein", "carbs", "fat"]
        }
    },
    "required": ["is_food", "food_name", "food_label", "confidence", "per_100g", "total_weight_grams", "total_nutrition", "ingredients", "health_insights"]
}

GEMINI_FOOD_PROMPT: str = (
    "You are a professional nutrition analyzer. Analyze the provided food image carefully.\n"
    "1. Determine whether the image contains recognizable food or beverage.\n"
    "2. If not food, set 'is_food' to false, 'confidence' to 0.0, and provide an empty 'food_name'.\n"
    "3. If it is food, identify the single primary dish, its name, a snake_case label, "
    "your self-assessed confidence score (0.0 to 1.0), total estimated edible weight, total nutrition "
    "(calories in kcal; protein, carbs, fat, fiber in grams), visible ingredients with estimated portion "
    "grams, calories, macros and confidence, plus concise health insights. Also provide realistic nutrition "
    "estimates PER 100 GRAMS in the legacy per_100g object.\n"
    "4. All nutritional values and ingredient portions must be non-negative finite numbers; confidence values "
    "must be between 0 and 1. Use empty ingredient and insight lists when image details are unclear."
)

GEMINI_LABEL_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "is_nutrition_label": {
            "type": "boolean",
            "description": "True if the image clearly shows a packaged food nutrition facts table/label, False otherwise.",
        },
        "product_name": {
            "type": "string",
            "description": "Product name if visible on the packaging, or empty string if not visible.",
        },
        "brand": {
            "type": "string",
            "description": "Brand name if visible on the packaging, or empty string.",
        },
        "serving_size": {
            "type": "string",
            "description": "Serving size text printed on the label (e.g., '30g', '1 gói (45g)', '250ml').",
        },
        "serving_grams": {
            "type": "number",
            "description": "Numeric serving size in grams or milliliters (default 100 if per-100g only or unclear).",
        },
        "per_100g": {
            "type": "object",
            "properties": {
                "calories": {"type": "number", "description": "Energy per 100g/100ml in kcal."},
                "protein": {"type": "number", "description": "Protein per 100g/100ml in grams."},
                "carbs": {"type": "number", "description": "Total carbohydrates per 100g/100ml in grams."},
                "fat": {"type": "number", "description": "Total fat per 100g/100ml in grams."},
                "fiber": {"type": "number", "description": "Dietary fiber per 100g/100ml in grams (0 if not listed)."},
            },
            "required": ["calories", "protein", "carbs", "fat", "fiber"],
        },
        "per_serving": {
            "type": "object",
            "properties": {
                "calories": {"type": "number"},
                "protein": {"type": "number"},
                "carbs": {"type": "number"},
                "fat": {"type": "number"},
                "fiber": {"type": "number"},
            },
        },
    },
    "required": [
        "is_nutrition_label",
        "product_name",
        "brand",
        "serving_size",
        "serving_grams",
        "per_100g",
    ],
}

GEMINI_LABEL_PROMPT: str = (
    "You are an expert OCR nutrition facts label reader. Carefully inspect the provided image.\n"
    "1. Determine whether the image shows a food or beverage nutrition facts label/table.\n"
    "2. If it is NOT a nutrition label (e.g. a selfie, scenery, blurry unreadable text, or plain food without a label), "
    "set 'is_nutrition_label' to false and set numeric fields to 0.\n"
    "3. If it IS a nutrition label, extract product_name (if visible, else ''), brand (if visible, else ''), "
    "serving_size (exact text such as '30g' or '1 hộp 180ml'), serving_grams (numeric grams/ml; use 100 if unknown), "
    "and nutrition values (calories in kcal; protein, carbs, fat, fiber in grams).\n"
    "4. Always provide normalized values PER 100g/100ml in 'per_100g'. If energy is only listed in kJ, convert using kcal = kJ / 4.184. "
    "If the label only lists values per serving, also populate 'per_serving' with the printed per-serving values and compute 'per_100g' accurately.\n"
    "5. All numeric nutrition values must be non-negative finite numbers; use 0 if fiber is not listed on the label."
)


class GeminiFoodAnalyzerError(Exception):
    """Base exception for Gemini food analyzer errors."""
    pass


class GeminiConfigurationError(GeminiFoodAnalyzerError):
    """Raised when Gemini configuration (API key or model name) is missing or invalid."""
    pass


class GeminiAnalysisError(GeminiFoodAnalyzerError):
    """Raised when upstream API fails, returns invalid data, or image is not food."""
    pass


class GeminiFoodAnalyzer:
    """
    Internal Gemini-based food image analyzer using Google Gemini REST API
    with structured JSON schema output.
    """

    # Per-attempt cap when a fallback exists, so primary+fallback stay <= ~12s.
    PRIMARY_TIMEOUT_SECONDS = 6.0
    FALLBACK_MIN_TIMEOUT_SECONDS = 18.0
    FALLBACK_MAX_TIMEOUT_SECONDS = 20.0
    SECONDARY_FALLBACK_MODEL = "gemini-3.1-flash-lite"

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: Optional[str] = None,
        timeout: Optional[float] = None,
    ):
        self._api_key = api_key
        self._model = model
        self._timeout = timeout

    @property
    def api_key(self) -> Optional[str]:
        return self._api_key or os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")

    @property
    def model(self) -> Optional[str]:
        if self._model:
            return self._model
        return os.getenv("GEMINI_FOOD_MODEL", "gemini-3.5-flash-lite").strip() or "gemini-3.5-flash-lite"

    @property
    def fallback_model(self) -> Optional[str]:
        raw = os.getenv("GEMINI_FOOD_FALLBACK_MODEL", "gemini-3.5-flash-lite").strip()
        return raw or None

    @property
    def timeout(self) -> float:
        if self._timeout is not None:
            if isinstance(self._timeout, bool):
                return 15.0
            return float(self._timeout)
        try:
            return float(os.getenv("GEMINI_FOOD_TIMEOUT", "15.0"))
        except (ValueError, TypeError):
            return 15.0

    def validate_configuration(self) -> None:
        """Validate that Gemini food analysis is enabled, and API key and model name are configured."""
        enabled = os.getenv("ENABLE_GEMINI_FOOD_ANALYSIS", "true").strip().lower()
        if enabled in ("false", "0", "no"):
            raise GeminiConfigurationError("Gemini food analysis is disabled")
        if not self.api_key:
            raise GeminiConfigurationError("GEMINI_API_KEY is not configured")
        if not self.model:
            raise GeminiConfigurationError("GEMINI_FOOD_MODEL is not configured")

    @staticmethod
    def _build_payload(
        prompt: str,
        schema: Dict[str, Any],
        b64_image: str,
        mime_type: str,
        *,
        include_thinking: bool = True,
    ) -> Dict[str, Any]:
        generation_config: Dict[str, Any] = {
            "responseMimeType": "application/json",
            "responseSchema": schema,
        }
        if include_thinking:
            generation_config["thinkingConfig"] = {"thinkingLevel": "minimal"}
        return {
            "contents": [
                {
                    "parts": [
                        {"text": prompt},
                        {
                            "inline_data": {
                                "mime_type": mime_type or "image/jpeg",
                                "data": b64_image,
                            }
                        },
                    ]
                }
            ],
            "generationConfig": generation_config,
        }

    async def _post_to_model(
        self,
        client: httpx.AsyncClient,
        model_name: str,
        headers: Dict[str, str],
        prompt: str,
        schema: Dict[str, Any],
        b64_image: str,
        mime_type: str,
        timeout: Optional[float] = None,
    ) -> httpx.Response:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent"
        extra: Dict[str, Any] = {"timeout": timeout} if timeout is not None else {}
        payload = self._build_payload(prompt, schema, b64_image, mime_type, include_thinking=True)
        response = await client.post(url, headers=headers, json=payload, **extra)
        if response.status_code == 400 and "thinking" in (getattr(response, "text", "") or "").lower():
            logger.info("Model '%s' rejected minimal thinkingConfig; retrying without thinkingConfig", model_name)
            payload_no_thinking = self._build_payload(
                prompt, schema, b64_image, mime_type, include_thinking=False
            )
            response = await client.post(url, headers=headers, json=payload_no_thinking, **extra)
        return response

    async def _request_gemini(
        self,
        prompt: str,
        schema: Dict[str, Any],
        image_bytes: bytes,
        mime_type: str,
    ) -> Dict[str, Any]:
        b64_image = base64.b64encode(image_bytes).decode("utf-8")
        headers = {
            "x-goog-api-key": self.api_key,
            "Content-Type": "application/json",
        }
        models_to_try = []
        fb_model = self.fallback_model
        candidate_models = [self.model]
        if fb_model:
            candidate_models.append(fb_model)
            candidate_models.append(self.SECONDARY_FALLBACK_MODEL)
        for candidate in candidate_models:
            cleaned = (candidate or "").strip()
            if cleaned and cleaned not in models_to_try:
                models_to_try.append(cleaned)

        last_error: Optional[GeminiAnalysisError] = None
        client_timeout = max(self.timeout, self.FALLBACK_MAX_TIMEOUT_SECONDS)
        async with httpx.AsyncClient(timeout=client_timeout) as client:
            for idx, model_name in enumerate(models_to_try):
                has_fallback = idx < len(models_to_try) - 1
                if idx == 0 and has_fallback:
                    # Only the primary attempt is capped at 6.0s so fallbacks still have budget.
                    call_timeout = min(self.timeout, self.PRIMARY_TIMEOUT_SECONDS)
                elif idx > 0:
                    # Fallback must keep a full 15.0s-20.0s window so it is not aborted mid-generation.
                    call_timeout = min(max(self.timeout, self.FALLBACK_MIN_TIMEOUT_SECONDS),
                                       self.FALLBACK_MAX_TIMEOUT_SECONDS)
                else:
                    call_timeout = self.timeout
                try:
                    response = await self._post_to_model(
                        client, model_name, headers, prompt, schema, b64_image, mime_type,
                        timeout=call_timeout,
                    )
                except httpx.TimeoutException:
                    last_error = GeminiAnalysisError("Gemini request timed out")
                    if has_fallback:
                        logger.warning(
                            "Gemini model '%s' timed out; falling back to '%s'",
                            model_name,
                            models_to_try[idx + 1],
                        )
                        continue
                    raise last_error
                except httpx.RequestError as exc:
                    last_error = GeminiAnalysisError(f"Gemini connection error: {type(exc).__name__}")
                    if has_fallback:
                        logger.warning(
                            "Gemini model '%s' connection error (%s); falling back to '%s'",
                            model_name,
                            type(exc).__name__,
                            models_to_try[idx + 1],
                        )
                        continue
                    raise last_error
                except Exception as exc:
                    raise GeminiAnalysisError(f"Gemini HTTP request failed: {type(exc).__name__}")

                if response.status_code in (401, 403):
                    raise GeminiAnalysisError("Gemini authentication failed")
                if response.status_code == 404:
                    last_error = GeminiAnalysisError(f"Gemini model not found: '{model_name}'")
                elif response.status_code == 429:
                    last_error = GeminiAnalysisError("Gemini rate limit exceeded")
                elif response.status_code >= 500:
                    last_error = GeminiAnalysisError(f"Gemini upstream server error ({response.status_code})")
                elif response.status_code != 200:
                    last_error = GeminiAnalysisError(f"Gemini API returned status code {response.status_code}")
                else:
                    try:
                        return response.json()
                    except Exception:
                        raise GeminiAnalysisError("Failed to parse Gemini response as JSON")

                if has_fallback and (response.status_code in (404, 429) or response.status_code >= 500):
                    logger.warning(
                        "Gemini model '%s' returned %s; falling back to '%s'",
                        model_name,
                        response.status_code,
                        models_to_try[idx + 1],
                    )
                    continue
                raise last_error

        raise last_error or GeminiAnalysisError("Gemini food analysis failed")

    async def analyze(
        self,
        image_bytes: bytes,
        mime_type: str = "image/jpeg",
        grams: float = 100.0,
    ) -> Dict[str, Any]:
        """
        Analyze food image with Gemini REST API and return normalized result.
        """
        self.validate_configuration()

        if (
            not isinstance(grams, (int, float))
            or isinstance(grams, bool)
            or math.isnan(grams)
            or math.isinf(grams)
            or grams <= 0
        ):
            raise GeminiAnalysisError("Invalid grams parameter")

        data = await self._request_gemini(
            GEMINI_FOOD_PROMPT,
            GEMINI_FOOD_SCHEMA,
            image_bytes,
            mime_type,
        )
        return self._normalize_gemini_response(data, grams)

    def _normalize_gemini_response(self, data: Dict[str, Any], grams: float) -> Dict[str, Any]:
        """Validate and normalize raw Gemini REST response."""
        candidates = data.get("candidates")
        if not candidates or not isinstance(candidates, list) or len(candidates) == 0:
            prompt_feedback = data.get("promptFeedback", {})
            block_reason = prompt_feedback.get("blockReason")
            if block_reason:
                raise GeminiAnalysisError(f"Gemini blocked image due to {block_reason}")
            raise GeminiAnalysisError("Gemini returned no candidates")

        candidate = candidates[0]
        finish_reason = candidate.get("finishReason")
        if finish_reason in ("SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT"):
            raise GeminiAnalysisError(f"Gemini generation blocked: {finish_reason}")

        content = candidate.get("content", {})
        parts = content.get("parts", [])
        if not parts or not isinstance(parts, list) or "text" not in parts[0]:
            raise GeminiAnalysisError("Gemini response missing content text")

        text = parts[0].get("text", "")
        if not text or not text.strip():
            raise GeminiAnalysisError("Gemini returned empty text content")

        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            raise GeminiAnalysisError("Failed to parse structured JSON from Gemini response")

        if not isinstance(parsed, dict):
            raise GeminiAnalysisError("Gemini structured output is not a JSON object")

        if parsed.get("is_food") is not True:
            raise GeminiAnalysisError("Image does not contain recognizable food")

        food_name = str(parsed.get("dish_name") or parsed.get("food_name") or "").strip()
        if not food_name:
            raise GeminiAnalysisError("Gemini returned empty food name")

        food_label = str(parsed.get("food_label", "")).strip().lower().replace(" ", "_")
        if not food_label:
            food_label = food_name.lower().replace(" ", "_")

        raw_conf = parsed.get("confidence")
        if (
            raw_conf is None
            or not isinstance(raw_conf, (int, float))
            or isinstance(raw_conf, bool)
            or math.isnan(raw_conf)
            or math.isinf(raw_conf)
        ):
            raise GeminiAnalysisError("Invalid confidence score in Gemini response")
        confidence = float(raw_conf)
        if confidence < 0.0 or confidence > 1.0:
            raise GeminiAnalysisError("Confidence score out of range [0.0, 1.0]")
        confidence = round(confidence, 3)
        low_confidence = confidence < 0.40

        per_100g_raw = parsed.get("per_100g")
        if not isinstance(per_100g_raw, dict):
            raise GeminiAnalysisError("Missing per_100g nutrition object")

        for macro in ("calories", "protein", "carbs", "fat"):
            val = per_100g_raw.get(macro)
            if (
                val is None
                or not isinstance(val, (int, float))
                or isinstance(val, bool)
                or math.isnan(val)
                or math.isinf(val)
                or val < 0
            ):
                raise GeminiAnalysisError(f"Invalid nutrition value for {macro}")

        c100 = round(float(per_100g_raw["calories"]), 1)
        p100 = round(float(per_100g_raw["protein"]), 1)
        cb100 = round(float(per_100g_raw["carbs"]), 1)
        f100 = round(float(per_100g_raw["fat"]), 1)

        ratio = grams / 100.0

        total_nutrition_raw = parsed.get("total_nutrition")
        if not isinstance(total_nutrition_raw, dict):
            total_nutrition_raw = {}
        total_nutrition = {}
        for nutrient in ("calories", "protein", "carbs", "fat", "fiber"):
            fallback = per_100g_raw.get(nutrient, 0)
            if (not isinstance(fallback, (int, float)) or isinstance(fallback, bool)
                    or not math.isfinite(fallback) or fallback < 0):
                fallback = 0
            value = total_nutrition_raw.get(nutrient, fallback * ratio)
            if (not isinstance(value, (int, float)) or isinstance(value, bool)
                    or not math.isfinite(value) or value < 0):
                value = fallback * ratio
            total_nutrition[nutrient] = round(float(value), 1)

        ingredients = []
        raw_ingredients = parsed.get("ingredients")
        if isinstance(raw_ingredients, list):
            for item in raw_ingredients:
                if not isinstance(item, dict):
                    continue
                name = str(item.get("name") or "").strip()
                if not name:
                    continue
                normalized = {"name": name}
                for field in ("portion_grams", "calories", "protein", "carbs", "fat", "confidence"):
                    value = item.get(field, 0)
                    if (not isinstance(value, (int, float)) or isinstance(value, bool)
                            or not math.isfinite(value) or value < 0):
                        value = 0
                    normalized[field] = round(float(value), 3)
                normalized["confidence"] = min(1.0, normalized["confidence"])
                ingredients.append(normalized)

        raw_insights = parsed.get("health_insights")
        health_insights = (
            [str(value).strip() for value in raw_insights if str(value).strip()]
            if isinstance(raw_insights, list) else []
        )
        total_weight = parsed.get("total_weight_grams", grams)
        if (not isinstance(total_weight, (int, float)) or isinstance(total_weight, bool)
                or not math.isfinite(total_weight) or total_weight <= 0):
            total_weight = grams
        effective_grams = float(total_weight)

        return {
            "food_name": food_name,
            "food_label": food_label,
            "detected_food_name": food_name,
            "confidence": confidence,
            "low_confidence": low_confidence,
            "grams": effective_grams,
            "nutrition": {
                "calories": total_nutrition["calories"],
                "protein": total_nutrition["protein"],
                "carbs": total_nutrition["carbs"],
                "fat": total_nutrition["fat"],
                "fiber": total_nutrition["fiber"],
            },
            "fiber": total_nutrition["fiber"],
            "total_weight_grams": round(float(total_weight), 1),
            "total_nutrition": total_nutrition,
            "ingredients": ingredients,
            "health_insights": health_insights,
            "per_100g": {
                "calories": c100,
                "protein": p100,
                "carbs": cb100,
                "fat": f100,
                "fiber": round(total_nutrition["fiber"] / effective_grams * 100, 1),
            },
            "nutrition_source": "gemini_estimate",
            "top3_predictions": [
                {
                    "label": food_label,
                    "food_name": food_name,
                    "confidence": confidence,
                }
            ],
            "mock": False,
            "temp_id": "",
            "image_url": "",
        }

    async def analyze_nutrition_label(
        self,
        image_bytes: bytes,
        mime_type: str = "image/jpeg",
    ) -> Dict[str, Any]:
        """
        Extract packaged product nutrition facts from a label image using Gemini Vision.
        Normalizes per-serving labels to per_100g when serving_grams > 0.
        """
        self.validate_configuration()
        data = await self._request_gemini(
            GEMINI_LABEL_PROMPT,
            GEMINI_LABEL_SCHEMA,
            image_bytes,
            mime_type,
        )
        return self._normalize_label_response(data)

    def _normalize_label_response(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Validate and normalize raw Gemini Vision nutrition-label response."""
        candidates = data.get("candidates")
        if not candidates or not isinstance(candidates, list) or len(candidates) == 0:
            prompt_feedback = data.get("promptFeedback", {})
            block_reason = prompt_feedback.get("blockReason")
            if block_reason:
                raise GeminiAnalysisError(f"Gemini blocked image due to {block_reason}")
            raise GeminiAnalysisError("Gemini returned no candidates")

        candidate = candidates[0]
        finish_reason = candidate.get("finishReason")
        if finish_reason in ("SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT"):
            raise GeminiAnalysisError(f"Gemini generation blocked: {finish_reason}")

        content = candidate.get("content", {})
        parts = content.get("parts", [])
        if not parts or not isinstance(parts, list) or "text" not in parts[0]:
            raise GeminiAnalysisError("Gemini response missing content text")

        text = parts[0].get("text", "")
        if not text or not text.strip():
            raise GeminiAnalysisError("Gemini returned empty text content")

        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            raise GeminiAnalysisError("Failed to parse structured JSON from Gemini response")

        if not isinstance(parsed, dict):
            raise GeminiAnalysisError("Gemini structured output is not a JSON object")

        if parsed.get("is_nutrition_label") is not True:
            raise GeminiAnalysisError("Image does not contain a recognizable nutrition label")

        product_name = str(parsed.get("product_name") or "").strip()
        brand = str(parsed.get("brand") or "").strip()
        serving_size = str(parsed.get("serving_size") or "").strip()

        raw_serving_grams = parsed.get("serving_grams")
        has_positive_serving_grams = (
            isinstance(raw_serving_grams, (int, float))
            and not isinstance(raw_serving_grams, bool)
            and math.isfinite(raw_serving_grams)
            and float(raw_serving_grams) > 0
        )
        serving_grams = round(float(raw_serving_grams), 1) if has_positive_serving_grams else 100.0

        def _validate_macro_dict(raw_obj: Any, *, allow_missing: bool) -> Optional[Dict[str, Optional[float]]]:
            if not isinstance(raw_obj, dict):
                return None
            out: Dict[str, Optional[float]] = {}
            for macro in ("calories", "protein", "carbs", "fat", "fiber"):
                val = raw_obj.get(macro)
                if val is None:
                    if macro == "fiber" or allow_missing:
                        out[macro] = None
                        continue
                    return None
                if (
                    not isinstance(val, (int, float))
                    or isinstance(val, bool)
                    or math.isnan(val)
                    or math.isinf(val)
                    or val < 0
                ):
                    raise GeminiAnalysisError(f"Invalid nutrition value for {macro}")
                out[macro] = float(val)
            return out

        per_100g_parsed = _validate_macro_dict(parsed.get("per_100g"), allow_missing=True)
        per_serving_parsed = _validate_macro_dict(parsed.get("per_serving"), allow_missing=True)

        core_macros = ("calories", "protein", "carbs", "fat")
        has_complete_100g = (
            per_100g_parsed is not None
            and all(per_100g_parsed.get(k) is not None for k in core_macros)
        )
        per_100g_nonzero = (
            per_100g_parsed is not None
            and any((per_100g_parsed.get(k) or 0.0) > 0 for k in ("calories", "protein", "carbs", "fat", "fiber"))
        )
        per_serving_nonzero = (
            per_serving_parsed is not None
            and any((per_serving_parsed.get(k) or 0.0) > 0 for k in ("calories", "protein", "carbs", "fat", "fiber"))
        )

        # Normalize from per_serving -> per_100g if label only reported per_serving
        use_per_serving = (
            per_serving_parsed is not None
            and has_positive_serving_grams
            and (
                not has_complete_100g
                or (not per_100g_nonzero and per_serving_nonzero)
            )
        )

        normalized_per_100g: Dict[str, float] = {}
        if use_per_serving:
            scale = 100.0 / float(raw_serving_grams)
            for macro in ("calories", "protein", "carbs", "fat", "fiber"):
                s_val = per_serving_parsed.get(macro)
                if s_val is None:
                    fallback = per_100g_parsed.get(macro) if per_100g_parsed else None
                    normalized_per_100g[macro] = round(fallback if fallback is not None else 0.0, 1)
                else:
                    normalized_per_100g[macro] = round(s_val * scale, 1)
        elif has_complete_100g and per_100g_parsed is not None:
            for macro in ("calories", "protein", "carbs", "fat", "fiber"):
                val = per_100g_parsed.get(macro)
                if val is None and macro == "fiber" and per_serving_parsed and has_positive_serving_grams:
                    s_fiber = per_serving_parsed.get("fiber")
                    val = (s_fiber * 100.0 / float(raw_serving_grams)) if s_fiber is not None else 0.0
                normalized_per_100g[macro] = round(val if val is not None else 0.0, 1)
        else:
            raise GeminiAnalysisError("Missing per_100g nutrition data on label")

        if not serving_size:
            serving_size = f"{int(serving_grams)}g" if serving_grams.is_integer() else f"{serving_grams}g"

        return {
            "is_nutrition_label": True,
            "product_name": product_name,
            "brand": brand,
            "serving_size": serving_size,
            "serving_grams": serving_grams,
            "per_100g": normalized_per_100g,
        }


def get_gemini_food_analyzer() -> GeminiFoodAnalyzer:
    """Factory for GeminiFoodAnalyzer."""
    return GeminiFoodAnalyzer()
