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
        "food_label": {
            "type": "string",
            "description": "A lowercase snake_case label for the dish (e.g., 'pho_bo', 'chicken_salad')."
        },
        "confidence": {
            "type": "number",
            "description": "Estimated confidence score between 0.0 and 1.0 for the dish identification."
        },
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
    "required": ["is_food", "food_name", "food_label", "confidence", "per_100g"]
}

GEMINI_FOOD_PROMPT: str = (
    "You are a professional nutrition analyzer. Analyze the provided food image carefully.\n"
    "1. Determine whether the image contains recognizable food or beverage.\n"
    "2. If not food, set 'is_food' to false, 'confidence' to 0.0, and provide an empty 'food_name'.\n"
    "3. If it is food, identify the single primary dish, its name, a snake_case label, "
    "your self-assessed confidence score (0.0 to 1.0), and realistic nutritional estimates PER 100 GRAMS "
    "(calories in kcal, protein, carbs, and fat in grams).\n"
    "4. All nutritional values per 100g must be non-negative finite numbers."
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
        return self._model or os.getenv("GEMINI_FOOD_MODEL")

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
        """Validate that API key and model name are configured."""
        if not self.api_key:
            raise GeminiConfigurationError("GEMINI_API_KEY is not configured")
        if not self.model:
            raise GeminiConfigurationError("GEMINI_FOOD_MODEL is not configured")

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

        b64_image = base64.b64encode(image_bytes).decode("utf-8")
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"
        headers = {
            "x-goog-api-key": self.api_key,
            "Content-Type": "application/json",
        }
        payload = {
            "contents": [
                {
                    "parts": [
                        {"text": GEMINI_FOOD_PROMPT},
                        {
                            "inline_data": {
                                "mime_type": mime_type or "image/jpeg",
                                "data": b64_image,
                            }
                        },
                    ]
                }
            ],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": GEMINI_FOOD_SCHEMA,
            },
        }

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(url, headers=headers, json=payload)
        except httpx.TimeoutException:
            raise GeminiAnalysisError("Gemini request timed out")
        except httpx.RequestError as exc:
            raise GeminiAnalysisError(f"Gemini connection error: {type(exc).__name__}")
        except Exception as exc:
            raise GeminiAnalysisError(f"Gemini HTTP request failed: {type(exc).__name__}")

        if response.status_code == 401 or response.status_code == 403:
            raise GeminiAnalysisError("Gemini authentication failed")
        if response.status_code == 404:
            raise GeminiAnalysisError(f"Gemini model not found: '{self.model}'")
        if response.status_code == 429:
            raise GeminiAnalysisError("Gemini rate limit exceeded")
        if response.status_code >= 500:
            raise GeminiAnalysisError(f"Gemini upstream server error ({response.status_code})")
        if response.status_code != 200:
            raise GeminiAnalysisError(f"Gemini API returned status code {response.status_code}")

        try:
            data = response.json()
        except Exception:
            raise GeminiAnalysisError("Failed to parse Gemini response as JSON")

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

        food_name = str(parsed.get("food_name", "")).strip()
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

        return {
            "food_name": food_name,
            "food_label": food_label,
            "detected_food_name": food_name,
            "confidence": confidence,
            "low_confidence": low_confidence,
            "grams": grams,
            "nutrition": {
                "calories": round(c100 * ratio, 1),
                "protein": round(p100 * ratio, 1),
                "carbs": round(cb100 * ratio, 1),
                "fat": round(f100 * ratio, 1),
            },
            "per_100g": {
                "calories": c100,
                "protein": p100,
                "carbs": cb100,
                "fat": f100,
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


def get_gemini_food_analyzer() -> GeminiFoodAnalyzer:
    """Factory for GeminiFoodAnalyzer."""
    return GeminiFoodAnalyzer()
