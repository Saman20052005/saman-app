"""Gemini-only bounded prompt adapter for Core 3."""

import asyncio
from collections import OrderedDict
import copy
import json
import os
import logging
import re
import socket
import threading
import time
from abc import ABC, abstractmethod
from typing import Any, AsyncGenerator, Dict, List, Optional, Tuple
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

logger = logging.getLogger(__name__)

MAX_INPUT_TOKENS = 4096
MAX_OUTPUT_TOKENS = 1024
AI_FALLBACK_REPLY = "Xin lỗi, trợ lý AI hiện đang bảo trì, vui lòng thử lại sau."

DEFAULT_GEMINI_SWIFT_MODEL = "gemini-2.5-flash-lite"
DEFAULT_GEMINI_CORE_MODEL = "gemini-2.5-flash"
DEFAULT_GEMINI_PRO_MODEL = "gemini-2.5-pro"

DEFAULT_CONTEXT_CACHE_TTL_SEC = 1800
DEFAULT_CONTEXT_CACHE_MIN_CHARS = 4000
DEFAULT_CONTEXT_CACHE_MAX_ENTRIES = 256
_CONTEXT_CACHE_SAFETY_MARGIN_SEC = 60.0

_THINKING_CONFIG_ERROR_MARKERS = (
    "thinkingconfig",
    "thinkinglevel",
    "thinking_level",
    "thinking_config",
)

_KEY_QUERY_RE = re.compile(r"([?&]key=)[^&\s'\"\\]+", re.IGNORECASE)
_GOOGLE_API_KEY_RE = re.compile(r"AIza[0-9A-Za-z_\-]{10,}")

DEFAULT_SYSTEM_INSTRUCTION = (
    "Bạn là Saman Coach, trợ lý dinh dưỡng và luyện tập chỉ đưa ra lời khuyên. "
    "Trả lời hoàn chỉnh bằng tiếng Việt tự nhiên, 2-4 câu, an toàn. "
    "Chỉ dùng số liệu và hoạt động có trong ngữ cảnh; không bịa dữ liệu. "
    "Có nhật ký thì nêu đúng số liệu, tên bài tập/số hiệp. "
    'Thiếu dữ liệu thì nói "Hiện chưa có dữ liệu dinh dưỡng/tập luyện gần đây của bạn", gợi ý chung và khuyến khích ghi nhật ký. '
    "Ngữ cảnh rút gọn thì nói là tóm tắt. "
    "Không khẳng định đã lưu dữ liệu; thay đổi cần người dùng xác nhận. "
    "Nếu có `journey.active_journey`, nêu đúng `day_index`/`total_days`, ngày nghỉ, nhiệm vụ đã xong/còn thiếu; `story_logs`, `community` chỉ nhắc mục có thực. "
    "Nếu `recommendations` có `shop_products`/`journal_articles`, chỉ gợi ý 1-2 mục hợp nhất đúng tên và giá trong ngữ cảnh; không bịa."
)

def _resolve_tier_model(mode: str) -> str:
    if mode == "swift3":
        return (os.getenv("GEMINI_SWIFT_MODEL") or "").strip() or DEFAULT_GEMINI_SWIFT_MODEL
    if mode == "pro3":
        return (
            (os.getenv("GEMINI_PRO_MODEL") or os.getenv("GEMINI_MODEL") or "").strip()
            or DEFAULT_GEMINI_PRO_MODEL
        )
    return (
        (os.getenv("GEMINI_CORE_MODEL") or os.getenv("GEMINI_MODEL") or "").strip()
        or DEFAULT_GEMINI_CORE_MODEL
    )


def _should_include_thinking_config(cfg: dict) -> bool:
    setting = (os.getenv("GEMINI_ENABLE_THINKING_CONFIG") or "auto").strip().lower()
    if setting in ("false", "0", "no"):
        return False
    if setting in ("true", "1", "yes"):
        return bool(cfg.get("thinking_level"))
    # Default "auto": include thinkingConfig when tier specifies thinking_level
    # and rely on HTTP 400 retry fallback if unsupported by the target model.
    return bool(cfg.get("thinking_level"))


def _is_thinking_config_error(status_code: int, body_text: str) -> bool:
    if status_code != 400:
        return False
    lowered = (body_text or "").lower()
    return any(marker in lowered for marker in _THINKING_CONFIG_ERROR_MARKERS)


def _strip_thinking_config(payload: dict) -> dict:
    cloned = copy.deepcopy(payload)
    gen_cfg = cloned.get("generationConfig")
    if isinstance(gen_cfg, dict):
        gen_cfg.pop("thinkingConfig", None)
    return cloned


def _strip_cached_content(payload: dict) -> dict:
    cloned = copy.deepcopy(payload)
    cloned.pop("cachedContent", None)
    return cloned


def _is_smart_routing_enabled() -> bool:
    setting = (os.getenv("GEMINI_SMART_ROUTING") or "true").strip().lower()
    return setting not in ("false", "0", "no")


def resolve_effective_tier(
    requested_tier: str,
    *,
    intent: Optional[str] = None,
    prefer_lightweight_model: bool = False,
) -> str:
    """Resolve the effective Gemini tier based on intent and lightweight routing."""
    normalized_tier = (requested_tier or "core3").strip().lower()
    if normalized_tier not in TIER_CONFIGS:
        normalized_tier = "core3"

    if not _is_smart_routing_enabled():
        return normalized_tier

    normalized_intent = (intent or "").strip().lower() if intent is not None else ""

    if prefer_lightweight_model or normalized_intent == "general_chat":
        return "swift3"

    if normalized_tier == "pro3" and normalized_intent in {"nutrition", "recovery"}:
        return "core3"

    return normalized_tier


def _is_context_cache_enabled() -> bool:
    setting = (os.getenv("GEMINI_ENABLE_CONTEXT_CACHE") or "false").strip().lower()
    return setting in ("true", "1", "yes")


def _get_context_cache_ttl_sec() -> int:
    raw = (os.getenv("GEMINI_CONTEXT_CACHE_TTL_SEC") or "").strip()
    if not raw:
        return DEFAULT_CONTEXT_CACHE_TTL_SEC
    try:
        parsed = int(raw)
        return parsed if parsed > 0 else DEFAULT_CONTEXT_CACHE_TTL_SEC
    except ValueError:
        return DEFAULT_CONTEXT_CACHE_TTL_SEC


def _get_context_cache_min_chars() -> int:
    raw = (os.getenv("GEMINI_CONTEXT_CACHE_MIN_CHARS") or "").strip()
    if not raw:
        return DEFAULT_CONTEXT_CACHE_MIN_CHARS
    try:
        parsed = int(raw)
        return parsed if parsed >= 0 else DEFAULT_CONTEXT_CACHE_MIN_CHARS
    except ValueError:
        return DEFAULT_CONTEXT_CACHE_MIN_CHARS


def _sanitize_log_text(text: str, *, max_len: int = 300) -> str:
    """Redact API keys and query credentials from log text and cap length."""
    sanitized = str(text or "")
    sanitized = _KEY_QUERY_RE.sub(r"\1[REDACTED]", sanitized)
    sanitized = _GOOGLE_API_KEY_RE.sub("[REDACTED_API_KEY]", sanitized)
    for env_name in ("GEMINI_API_KEY", "STAGING_GEMINI_API_KEY"):
        secret_val = (os.getenv(env_name) or "").strip()
        if secret_val:
            sanitized = sanitized.replace(secret_val, "[REDACTED_API_KEY]")
    sanitized = " ".join(sanitized.split())
    if len(sanitized) > max_len:
        if max_len > 3:
            sanitized = sanitized[: max_len - 3] + "..."
        else:
            sanitized = sanitized[:max_len]
    return sanitized


def _classify_gemini_error(
    status_code: Optional[int],
    body_text: str,
    exc: Optional[Exception] = None,
) -> str:
    """Classify Gemini HTTP/network failures into production diagnostic categories."""
    lowered = (body_text or "").lower()
    exc_text = str(exc or "").lower()

    if status_code is None and exc is None and "missing_api_key" in lowered:
        return "missing_api_key"

    if isinstance(exc, (TimeoutError, socket.timeout)):
        return "timeout"
    if isinstance(exc, URLError) and isinstance(getattr(exc, "reason", None), (TimeoutError, socket.timeout)):
        return "timeout"
    if "timed out" in exc_text or "timeout" in exc_text:
        return "timeout"

    if (
        status_code in (401, 403)
        or "api key not valid" in lowered
        or "api_key_invalid" in lowered
        or "invalid api key" in lowered
        or "unauthenticated" in lowered
        or "permission_denied" in lowered
    ):
        return "invalid_api_key"

    if (
        status_code == 404
        or "model is not found" in lowered
        or "not found for api version" in lowered
    ):
        return "model_not_found"

    if (
        status_code == 429
        or "resource_exhausted" in lowered
        or "rate limit" in lowered
        or "quota" in lowered
    ):
        return "quota_or_rate_limit"

    if status_code == 400:
        return "bad_request"

    if status_code is not None and 500 <= status_code < 600:
        return "server_error"

    if status_code is not None and 400 <= status_code < 500:
        return "bad_request"

    return "network_error"


def _read_http_error_body(exc: HTTPError) -> str:
    try:
        if hasattr(exc, "read"):
            raw = exc.read()
            if isinstance(raw, bytes):
                decoded = raw.decode("utf-8", errors="replace")
                if decoded:
                    return decoded
            elif raw:
                return str(raw)
    except Exception:
        pass
    return str(exc)


def _build_gemini_payload(
    prompt: str,
    cfg: dict,
    *,
    cached_content_name: Optional[str] = None,
) -> dict:
    generation_config: Dict[str, Any] = {
        "maxOutputTokens": cfg["max_output_tokens"],
        "temperature": cfg["temperature"],
    }
    if _should_include_thinking_config(cfg):
        generation_config["thinkingConfig"] = {"thinkingLevel": cfg["thinking_level"]}
    payload: Dict[str, Any] = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": generation_config,
    }
    cleaned_cache_name = (cached_content_name or "").strip() if cached_content_name else ""
    if cleaned_cache_name:
        payload["cachedContent"] = cleaned_cache_name
    return payload


class GeminiContextCacheManager:
    """Thread-safe bounded in-memory manager for Gemini cachedContents."""

    def __init__(
        self,
        *,
        max_entries: int = DEFAULT_CONTEXT_CACHE_MAX_ENTRIES,
        timeout_seconds: float = 15.0,
    ):
        self._lock = threading.Lock()
        self._entries: "OrderedDict[str, Tuple[str, float]]" = OrderedDict()
        self.max_entries = max(1, int(max_entries))
        self.timeout_seconds = float(timeout_seconds)

    def _prune_expired_locked(self, now: float) -> None:
        expired_keys = [
            key
            for key, (_, expires_at) in self._entries.items()
            if expires_at - now <= _CONTEXT_CACHE_SAFETY_MARGIN_SEC
        ]
        for key in expired_keys:
            self._entries.pop(key, None)

    def invalidate(self, cache_key: str) -> None:
        if not cache_key:
            return
        with self._lock:
            self._entries.pop(cache_key, None)

    def invalidate_by_name(self, cached_content_name: str) -> None:
        target = (cached_content_name or "").strip()
        if not target:
            return
        with self._lock:
            keys_to_remove = [
                key for key, (name, _) in self._entries.items() if name == target
            ]
            for key in keys_to_remove:
                self._entries.pop(key, None)

    def clear(self) -> None:
        with self._lock:
            self._entries.clear()

    def get_or_create_cache(
        self,
        api_key: str,
        model: str,
        static_prefix: str,
        *,
        cache_key: str,
        system_instruction: Optional[str] = None,
        tier: Optional[str] = None,
    ) -> Optional[str]:
        if not _is_context_cache_enabled():
            return None

        cleaned_key = (api_key or "").strip()
        cleaned_model = (model or "").strip()
        cleaned_cache_key = (cache_key or "").strip()
        if not cleaned_key or not cleaned_model or not cleaned_cache_key or not static_prefix:
            return None

        normalized_tier = (tier or "").strip().lower()
        swift_model = _resolve_tier_model("swift3").strip().lower()
        if normalized_tier == "swift3" or (
            not normalized_tier and cleaned_model.lower() == swift_model
        ):
            return None

        min_chars = _get_context_cache_min_chars()
        if len(static_prefix) < min_chars:
            return None

        now = time.monotonic()
        with self._lock:
            entry = self._entries.get(cleaned_cache_key)
            if entry is not None:
                cached_name, expires_at = entry
                if expires_at - now > _CONTEXT_CACHE_SAFETY_MARGIN_SEC:
                    self._entries.move_to_end(cleaned_cache_key)
                    return cached_name
                self._entries.pop(cleaned_cache_key, None)

        ttl_sec = _get_context_cache_ttl_sec()
        normalized_model = (
            cleaned_model if cleaned_model.startswith("models/") else f"models/{cleaned_model}"
        )
        request_body: Dict[str, Any] = {
            "model": normalized_model,
            "contents": [{"role": "user", "parts": [{"text": static_prefix}]}],
            "ttl": f"{ttl_sec}s",
        }
        cleaned_sys = (system_instruction or "").strip() if system_instruction else ""
        if cleaned_sys:
            request_body["systemInstruction"] = {"parts": [{"text": cleaned_sys}]}

        endpoint_url = (
            f"https://generativelanguage.googleapis.com/v1beta/cachedContents"
            f"?{urlencode({'key': cleaned_key})}"
        )
        request = Request(
            endpoint_url,
            data=json.dumps(request_body, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        try:
            with urlopen(request, timeout=self.timeout_seconds) as response:
                raw_response = response.read().decode("utf-8")
            parsed = json.loads(raw_response)
            cached_name = (parsed.get("name") or "").strip()
            if not cached_name:
                logger.warning(
                    "gemini_context_cache_failed model=%s http_status=200 reason=empty_name detail=%s",
                    cleaned_model,
                    _sanitize_log_text(raw_response),
                )
                return None
        except HTTPError as exc:
            err_body = _read_http_error_body(exc)
            reason = _classify_gemini_error(exc.code, err_body, exc)
            logger.warning(
                "gemini_context_cache_failed model=%s http_status=%s reason=%s detail=%s",
                cleaned_model,
                exc.code,
                reason,
                _sanitize_log_text(err_body),
            )
            return None
        except Exception as exc:
            reason = _classify_gemini_error(None, str(exc), exc)
            logger.warning(
                "gemini_context_cache_failed model=%s http_status=none reason=%s detail=%s",
                cleaned_model,
                reason,
                _sanitize_log_text(str(exc)),
            )
            return None

        expires_at = time.monotonic() + float(ttl_sec)
        with self._lock:
            self._prune_expired_locked(time.monotonic())
            self._entries[cleaned_cache_key] = (cached_name, expires_at)
            self._entries.move_to_end(cleaned_cache_key)
            while len(self._entries) > self.max_entries:
                self._entries.popitem(last=False)

        return cached_name


default_context_cache_manager = GeminiContextCacheManager()


TIER_CONFIGS = {
    "swift3": {
        "model": _resolve_tier_model("swift3"),
        "thinking_level": "minimal",
        "temperature": 0.3,
        "max_input_tokens": 3072,
        "max_output_tokens": 512,
    },
    "core3": {
        "model": _resolve_tier_model("core3"),
        "thinking_level": "low",
        "temperature": 0.4,
        "max_input_tokens": 4096,
        "max_output_tokens": 1024,
    },
    "pro3": {
        "model": _resolve_tier_model("pro3"),
        "thinking_level": "high",
        "temperature": 0.5,
        "max_input_tokens": 8192,
        "max_output_tokens": 4096,
    },
}


def get_tier_config(ai_mode: Optional[str] = "core3") -> dict:
    mode = (ai_mode or "core3").strip().lower()
    if mode not in TIER_CONFIGS:
        mode = "core3"

    if mode == "swift3":
        return {
            "model": _resolve_tier_model("swift3"),
            "thinking_level": "minimal",
            "temperature": 0.3,
            "max_input_tokens": 3072,
            "max_output_tokens": 512,
        }
    elif mode == "pro3":
        return {
            "model": _resolve_tier_model("pro3"),
            "thinking_level": "high",
            "temperature": 0.5,
            "max_input_tokens": 8192,
            "max_output_tokens": 4096,
        }
    else:  # core3 fallback
        return {
            "model": _resolve_tier_model("core3"),
            "thinking_level": "low",
            "temperature": 0.4,
            "max_input_tokens": 4096,
            "max_output_tokens": 1024,
        }


class Core3PromptTooLarge(ValueError):
    pass


class ProviderError(RuntimeError):
    """Sanitized provider failure metadata; never includes request credentials."""

    def __init__(self, status, *, retryable):
        self.status = status
        self.retryable = retryable
        super().__init__(status)


def _estimate_tokens(text):
    # Conservative local upper bound (~3 UTF-8 bytes per token) avoiding network calls.
    # avoids making a provider call just to measure a request before dispatch.
    return max(1, (len(text.encode("utf-8")) + 2) // 3)


def render_prompt(
    question,
    history,
    context,
    system_instruction: str = DEFAULT_SYSTEM_INSTRUCTION,
    *,
    max_input_tokens: Optional[int] = None,
    ai_mode: str = "core3",
):
    budget = max_input_tokens or get_tier_config(ai_mode)["max_input_tokens"]

    # Append Persona & Preferences to system_instruction if present in context
    if isinstance(context, dict) and isinstance(context.get("preferences"), dict):
        prefs = context["preferences"]
        persona_lines = []
        persona = prefs.get("coach_persona") or prefs.get("reply_style")
        if persona:
            persona_map = {
                "strict_pt": "Phong cách phản hồi: Huấn luyện viên nghiêm khắc (thẳng thắn, kỷ luật cao, tập trung vào hành động).",
                "nutrition_doctor": "Phong cách phản hồi: Bác sĩ / chuyên gia dinh dưỡng (khoa học, phân tích chi tiết và chính xác).",
                "supportive_coach": "Phong cách phản hồi: Huấn luyện viên đồng hành (khích lệ, hỗ trợ tích cực, đồng cảm và ấm áp).",
            }
            persona_lines.append(persona_map.get(persona, f"Phong cách phản hồi: {persona}."))

        dislikes = prefs.get("food_dislikes")
        if dislikes:
            d_str = ", ".join(str(x) for x in dislikes if str(x).strip()) if isinstance(dislikes, list) else str(dislikes).strip()
            if d_str:
                persona_lines.append(f"Món ăn không thích (tránh gợi ý): {d_str}.")

        equipment = prefs.get("equipment")
        if equipment:
            e_str = ", ".join(str(x) for x in equipment if str(x).strip()) if isinstance(equipment, list) else str(equipment).strip()
            if e_str:
                persona_lines.append(f"Thiết bị tập luyện hiện có: {e_str}.")

        muscles = prefs.get("target_muscles")
        if muscles:
            m_str = ", ".join(str(x) for x in muscles if str(x).strip()) if isinstance(muscles, list) else str(muscles).strip()
            if m_str:
                persona_lines.append(f"Nhóm cơ ưu tiên: {m_str}.")

        if persona_lines:
            system_instruction = f"{system_instruction}\n" + "\n".join(persona_lines)

    history = [item for item in (history or []) if isinstance(item, dict)]
    context_text = json.dumps(context or {}, ensure_ascii=False, separators=(",", ":"))
    mandatory = f"{system_instruction}\nQuestion: {question}"
    if _estimate_tokens(mandatory) > budget:
        raise Core3PromptTooLarge("Mandatory prompt exceeds input token budget")
    while True:
        history_text = "\n".join(
            f"{str(m.get('role', 'user'))}: {str(m.get('content', ''))}"
            for m in history
        )
        prompt = f"{system_instruction}\nContext: {context_text}\nHistory:\n{history_text}\nQuestion: {question}"
        if _estimate_tokens(prompt) <= budget:
            return prompt
        if history:
            del history[:2]
            continue
        if context_text != "{}":
            context_text = "{}"
            continue
        if context_text:
            context_text = ""
            continue
        raise Core3PromptTooLarge("Prompt exceeds input token budget")


def _stream_sse_lines(request, queue, loop):
    try:
        with urlopen(request, timeout=30.0) as response:
            for line in response:
                if loop.is_closed():
                    return
                decoded = line.decode("utf-8", errors="replace")
                loop.call_soon_threadsafe(queue.put_nowait, ("line", decoded))
        if not loop.is_closed():
            loop.call_soon_threadsafe(queue.put_nowait, ("end", None))
    except Exception as exc:
        if not loop.is_closed():
            loop.call_soon_threadsafe(queue.put_nowait, ("error", exc))


class BaseLLMProvider(ABC):
    provider_name: str = "base"
    last_usage: Optional[Dict[str, Any]] = None
    last_error: Optional[Dict[str, Any]] = None

    def resolve_model_name(self, ai_mode: str = "core3") -> str:
        return get_tier_config(ai_mode)["model"]

    @abstractmethod
    async def generate(
        self,
        prompt: str,
        *,
        ai_mode: str = "core3",
        cached_content_name: Optional[str] = None,
        intent: Optional[str] = None,
        prefer_lightweight_model: bool = False,
    ) -> str:
        raise NotImplementedError

    async def generate_stream(
        self,
        prompt: str,
        *,
        ai_mode: str = "core3",
        cached_content_name: Optional[str] = None,
        intent: Optional[str] = None,
        prefer_lightweight_model: bool = False,
    ) -> AsyncGenerator[str, None]:
        if cached_content_name is not None or intent is not None or prefer_lightweight_model:
            full_text = await self.generate(
                prompt,
                ai_mode=ai_mode,
                cached_content_name=cached_content_name,
                intent=intent,
                prefer_lightweight_model=prefer_lightweight_model,
            )
        else:
            full_text = await self.generate(prompt, ai_mode=ai_mode)
        chunk_size = 64
        text = full_text or ""
        for i in range(0, len(text), chunk_size):
            yield text[i:i + chunk_size]

    async def generate_from_context(
        self,
        *,
        system_prompt: str,
        context_json: dict,
        history: list,
        question: str,
        config: dict,
    ) -> str:
        cfg = config or {}
        ai_mode = str(cfg.get("ai_mode") or "core3")
        max_input = cfg.get("max_input_tokens")
        prompt = render_prompt(
            question,
            history,
            context_json,
            system_instruction=system_prompt or DEFAULT_SYSTEM_INSTRUCTION,
            max_input_tokens=max_input,
            ai_mode=ai_mode,
        )
        cached_content_name = cfg.get("cached_content_name")
        intent = cfg.get("intent")
        prefer_lightweight_model = bool(cfg.get("prefer_lightweight_model", False))
        if cached_content_name is not None or intent is not None or prefer_lightweight_model:
            return await self.generate(
                prompt,
                ai_mode=ai_mode,
                cached_content_name=cached_content_name,
                intent=intent,
                prefer_lightweight_model=prefer_lightweight_model,
            )
        return await self.generate(prompt, ai_mode=ai_mode)


def _should_retry_without_cache(status_code: int, body_text: str) -> bool:
    if status_code == 404:
        return True
    if status_code == 400:
        if _is_thinking_config_error(status_code, body_text):
            return False
        if _classify_gemini_error(status_code, body_text) == "invalid_api_key":
            return False
        return True
    return False


class GeminiCore3Provider(BaseLLMProvider):
    provider_name = "gemini"

    def __init__(self, engine=None, *, cache_manager: Optional[GeminiContextCacheManager] = None):
        self.engine = engine
        self.last_usage = None
        self.last_error: Optional[Dict[str, Any]] = None
        self.last_effective_tier: Optional[str] = None
        self.last_model: Optional[str] = None
        self.cache_manager = cache_manager or default_context_cache_manager

    def _record_failure(
        self,
        *,
        tier: str,
        effective_tier: str,
        model: str,
        http_status: Optional[int],
        reason: str,
        detail: str,
    ) -> None:
        safe_detail = _sanitize_log_text(detail)
        self.last_error = {
            "provider": self.provider_name,
            "tier": tier,
            "effective_tier": effective_tier,
            "model": model,
            "http_status": http_status,
            "reason": reason,
            "detail": safe_detail,
        }
        logger.error(
            "gemini_request_failed provider=gemini tier=%s effective_tier=%s model=%s http_status=%s reason=%s detail=%s",
            tier,
            effective_tier,
            model,
            http_status if http_status is not None else "none",
            reason,
            safe_detail,
        )

    async def generate(
        self,
        prompt,
        *,
        ai_mode: str = "core3",
        cached_content_name: Optional[str] = None,
        intent: Optional[str] = None,
        prefer_lightweight_model: bool = False,
    ):
        requested_tier = (ai_mode or "core3").strip().lower()
        if requested_tier not in TIER_CONFIGS:
            requested_tier = "core3"
        effective_tier = resolve_effective_tier(
            requested_tier,
            intent=intent,
            prefer_lightweight_model=prefer_lightweight_model,
        )
        cfg = get_tier_config(effective_tier)
        self.last_error = None
        self.last_effective_tier = effective_tier
        self.last_model = cfg["model"]

        if _estimate_tokens(prompt) > cfg["max_input_tokens"]:
            raise Core3PromptTooLarge("Prompt exceeds input token budget")
        if self.engine is not None:
            result = self.engine.generate_content(
                prompt,
                generation_config={"max_output_tokens": cfg["max_output_tokens"]},
            )
            if asyncio.iscoroutine(result):
                result = await result
            return getattr(result, "text", result)
        key = (os.getenv("GEMINI_API_KEY") or os.getenv("STAGING_GEMINI_API_KEY") or "").strip()
        model = cfg["model"]
        if not key:
            self._record_failure(
                tier=requested_tier,
                effective_tier=effective_tier,
                model=model,
                http_status=None,
                reason="missing_api_key",
                detail="GEMINI_API_KEY is not configured",
            )
            return AI_FALLBACK_REPLY
        try:
            import google.generativeai as genai
            genai.configure(api_key=key)
            _ = genai.GenerativeModel(model)
        except Exception:
            pass
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        endpoint_url = f"{url}?{urlencode({'key': key})}"
        current_payload = _build_gemini_payload(
            prompt,
            cfg,
            cached_content_name=cached_content_name,
        )
        retried_without_cache = False
        retried_without_thinking = False
        response_body = None

        while True:
            request = Request(
                endpoint_url,
                data=json.dumps(current_payload, ensure_ascii=False).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            try:
                response_body = await asyncio.to_thread(_post_json, request)
                break
            except HTTPError as exc:
                err_body = _read_http_error_body(exc)
                has_cached_content = bool(current_payload.get("cachedContent"))
                has_thinking_config = (
                    isinstance(current_payload.get("generationConfig"), dict)
                    and "thinkingConfig" in current_payload["generationConfig"]
                )
                if (
                    not retried_without_cache
                    and has_cached_content
                    and _should_retry_without_cache(exc.code, err_body)
                ):
                    self.cache_manager.invalidate_by_name(str(current_payload.get("cachedContent") or ""))
                    logger.warning(
                        "Gemini model '%s' rejected cachedContent (HTTP %s); retrying once without cachedContent",
                        model,
                        exc.code,
                    )
                    retried_without_cache = True
                    current_payload = _strip_cached_content(current_payload)
                    continue
                if (
                    not retried_without_thinking
                    and has_thinking_config
                    and _is_thinking_config_error(exc.code, err_body)
                ):
                    logger.warning(
                        "Gemini model '%s' rejected thinkingConfig (HTTP 400); retrying once without thinkingConfig",
                        model,
                    )
                    retried_without_thinking = True
                    current_payload = _strip_thinking_config(current_payload)
                    continue
                reason = _classify_gemini_error(exc.code, err_body, exc)
                self._record_failure(
                    tier=requested_tier,
                    effective_tier=effective_tier,
                    model=model,
                    http_status=exc.code,
                    reason=reason,
                    detail=err_body,
                )
                return AI_FALLBACK_REPLY
            except Exception as exc:
                reason = _classify_gemini_error(None, str(exc), exc)
                self._record_failure(
                    tier=requested_tier,
                    effective_tier=effective_tier,
                    model=model,
                    http_status=None,
                    reason=reason,
                    detail=str(exc),
                )
                return AI_FALLBACK_REPLY

        try:
            result = json.loads(response_body)
            candidates = result.get("candidates") or []
            parts = candidates[0].get("content", {}).get("parts", []) if candidates else []
            text = "".join(
                part.get("text", "")
                for part in parts
                if isinstance(part, dict) and not part.get("thought", False)
            )
            if not text:
                return AI_FALLBACK_REPLY
            usage = result.get("usageMetadata") or {}
        except (TypeError, ValueError, KeyError, IndexError):
            return AI_FALLBACK_REPLY
        self.last_usage = {
            "prompt_tokens": usage.get("promptTokenCount"),
            "output_tokens": usage.get("candidatesTokenCount"),
        }
        return text

    async def generate_stream(
        self,
        prompt,
        *,
        ai_mode: str = "core3",
        cached_content_name: Optional[str] = None,
        intent: Optional[str] = None,
        prefer_lightweight_model: bool = False,
    ) -> AsyncGenerator[str, None]:
        requested_tier = (ai_mode or "core3").strip().lower()
        if requested_tier not in TIER_CONFIGS:
            requested_tier = "core3"
        effective_tier = resolve_effective_tier(
            requested_tier,
            intent=intent,
            prefer_lightweight_model=prefer_lightweight_model,
        )
        cfg = get_tier_config(effective_tier)
        self.last_error = None
        self.last_effective_tier = effective_tier
        self.last_model = cfg["model"]

        if _estimate_tokens(prompt) > cfg["max_input_tokens"]:
            raise Core3PromptTooLarge("Prompt exceeds input token budget")

        key = (os.getenv("GEMINI_API_KEY") or os.getenv("STAGING_GEMINI_API_KEY") or "").strip()
        if self.engine is not None or not key:
            full_text = await self.generate(
                prompt,
                ai_mode=ai_mode,
                cached_content_name=cached_content_name,
                intent=intent,
                prefer_lightweight_model=prefer_lightweight_model,
            )
            if not full_text:
                yield AI_FALLBACK_REPLY
                return
            chunk_size = 64
            if len(full_text) <= chunk_size:
                yield full_text
            else:
                for i in range(0, len(full_text), chunk_size):
                    yield full_text[i:i + chunk_size]
            return

        model = cfg["model"]
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent"
        stream_url = f"{url}?{urlencode({'alt': 'sse', 'key': key})}"
        current_payload = _build_gemini_payload(
            prompt,
            cfg,
            cached_content_name=cached_content_name,
        )
        request = Request(
            stream_url,
            data=json.dumps(current_payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        queue: asyncio.Queue = asyncio.Queue()
        loop = asyncio.get_running_loop()
        thread = threading.Thread(
            target=_stream_sse_lines,
            args=(request, queue, loop),
            daemon=True,
        )
        thread.start()

        yielded_any = False
        retried_without_cache = False
        retried_without_thinking = False
        try:
            while True:
                msg_type, val = await queue.get()
                if msg_type == "line":
                    line = val.strip()
                    if not line.startswith("data:"):
                        continue
                    raw_json = line[5:].strip()
                    if not raw_json or raw_json == "[DONE]":
                        continue
                    try:
                        chunk_data = json.loads(raw_json)
                        usage = chunk_data.get("usageMetadata")
                        if isinstance(usage, dict):
                            self.last_usage = {
                                "prompt_tokens": usage.get("promptTokenCount"),
                                "output_tokens": usage.get("candidatesTokenCount"),
                            }
                        candidates = chunk_data.get("candidates") or []
                        parts = candidates[0].get("content", {}).get("parts", []) if candidates else []
                        delta = "".join(
                            part.get("text", "")
                            for part in parts
                            if isinstance(part, dict) and not part.get("thought", False)
                        )
                        if delta:
                            yielded_any = True
                            yield delta
                    except Exception:
                        continue
                elif msg_type == "error":
                    if isinstance(val, HTTPError):
                        err_body = _read_http_error_body(val)
                        has_cached_content = bool(current_payload.get("cachedContent"))
                        has_thinking_config = (
                            isinstance(current_payload.get("generationConfig"), dict)
                            and "thinkingConfig" in current_payload["generationConfig"]
                        )
                        if (
                            not yielded_any
                            and not retried_without_cache
                            and has_cached_content
                            and _should_retry_without_cache(val.code, err_body)
                        ):
                            self.cache_manager.invalidate_by_name(
                                str(current_payload.get("cachedContent") or "")
                            )
                            logger.warning(
                                "Gemini model '%s' rejected cachedContent on stream (HTTP %s); retrying once without cachedContent",
                                model,
                                val.code,
                            )
                            retried_without_cache = True
                            current_payload = _strip_cached_content(current_payload)
                            retry_request = Request(
                                stream_url,
                                data=json.dumps(current_payload, ensure_ascii=False).encode("utf-8"),
                                headers={"Content-Type": "application/json"},
                                method="POST",
                            )
                            queue = asyncio.Queue()
                            retry_thread = threading.Thread(
                                target=_stream_sse_lines,
                                args=(retry_request, queue, loop),
                                daemon=True,
                            )
                            retry_thread.start()
                            continue
                        if (
                            not yielded_any
                            and not retried_without_thinking
                            and has_thinking_config
                            and _is_thinking_config_error(val.code, err_body)
                        ):
                            logger.warning(
                                "Gemini model '%s' rejected thinkingConfig on stream (HTTP 400); retrying once without thinkingConfig",
                                model,
                            )
                            retried_without_thinking = True
                            current_payload = _strip_thinking_config(current_payload)
                            retry_request = Request(
                                stream_url,
                                data=json.dumps(current_payload, ensure_ascii=False).encode("utf-8"),
                                headers={"Content-Type": "application/json"},
                                method="POST",
                            )
                            queue = asyncio.Queue()
                            retry_thread = threading.Thread(
                                target=_stream_sse_lines,
                                args=(retry_request, queue, loop),
                                daemon=True,
                            )
                            retry_thread.start()
                            continue
                        reason = _classify_gemini_error(val.code, err_body, val)
                        self._record_failure(
                            tier=requested_tier,
                            effective_tier=effective_tier,
                            model=model,
                            http_status=val.code,
                            reason=reason,
                            detail=err_body,
                        )
                    else:
                        exc_obj = val if isinstance(val, Exception) else None
                        reason = _classify_gemini_error(None, str(val), exc_obj)
                        self._record_failure(
                            tier=requested_tier,
                            effective_tier=effective_tier,
                            model=model,
                            http_status=None,
                            reason=reason,
                            detail=str(val),
                        )
                    if not yielded_any:
                        yield AI_FALLBACK_REPLY
                    return
                elif msg_type == "end":
                    break
        except GeneratorExit:
            raise
        except Exception as exc:
            reason = _classify_gemini_error(None, str(exc), exc)
            self._record_failure(
                tier=requested_tier,
                effective_tier=effective_tier,
                model=model,
                http_status=None,
                reason=reason,
                detail=str(exc),
            )
            if not yielded_any:
                yield AI_FALLBACK_REPLY
            return

        if not yielded_any:
            yield AI_FALLBACK_REPLY


def _post_json(request):
    with urlopen(request, timeout=15.0) as response:
        return response.read().decode("utf-8")


def _post_json_with_timeout(request, timeout):
    with urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8")


def _stream_sse_lines_with_timeout(request, queue, loop, timeout):
    try:
        with urlopen(request, timeout=timeout) as response:
            for line in response:
                if loop.is_closed():
                    return
                decoded = line.decode("utf-8", errors="replace")
                loop.call_soon_threadsafe(queue.put_nowait, ("line", decoded))
        if not loop.is_closed():
            loop.call_soon_threadsafe(queue.put_nowait, ("end", None))
    except Exception as exc:
        if not loop.is_closed():
            loop.call_soon_threadsafe(queue.put_nowait, ("error", exc))


class SamanCustomLLMProvider(BaseLLMProvider):
    """OpenAI-compatible endpoint provider (vLLM / Ollama / HuggingFace Endpoint)."""

    provider_name = "saman_custom"

    def __init__(
        self,
        *,
        base_url: Optional[str] = None,
        model: Optional[str] = None,
        api_key: Optional[str] = None,
        timeout_seconds: Optional[float] = None,
    ):
        raw_url = base_url if base_url is not None else os.getenv("CUSTOM_LLM_BASE_URL", "")
        self.base_url = (raw_url or "").strip().rstrip("/")
        self.model = model or os.getenv("CUSTOM_LLM_MODEL", "saman-coach-v1")
        self.api_key = api_key if api_key is not None else os.getenv("CUSTOM_LLM_API_KEY", "")
        raw_timeout = timeout_seconds if timeout_seconds is not None else os.getenv("CUSTOM_LLM_TIMEOUT_SECONDS", "30.0")
        try:
            self.timeout_seconds = float(raw_timeout)
        except (TypeError, ValueError):
            self.timeout_seconds = 30.0
        self.last_usage = None

    def resolve_model_name(self, ai_mode: str = "core3") -> str:
        mode = (ai_mode or "core3").strip().lower()
        env_name = {
            "swift3": "CUSTOM_LLM_SWIFT_MODEL",
            "core3": "CUSTOM_LLM_CORE_MODEL",
            "pro3": "CUSTOM_LLM_PRO_MODEL",
        }.get(mode, "CUSTOM_LLM_CORE_MODEL")
        override = (os.getenv(env_name) or "").strip()
        return override or self.model

    def _endpoint(self) -> str:
        if self.base_url.endswith("/chat/completions"):
            return self.base_url
        return f"{self.base_url}/chat/completions"

    def _build_request(self, prompt: str, ai_mode: str, cfg: dict, stream: bool) -> Request:
        payload = {
            "model": self.resolve_model_name(ai_mode),
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": cfg["max_output_tokens"],
            "temperature": cfg["temperature"],
            "stream": stream,
        }
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        return Request(
            self._endpoint(),
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers=headers,
            method="POST",
        )

    def _set_usage(self, usage) -> None:
        if isinstance(usage, dict):
            self.last_usage = {
                "prompt_tokens": usage.get("prompt_tokens"),
                "output_tokens": usage.get("completion_tokens"),
            }

    async def generate(
        self,
        prompt: str,
        *,
        ai_mode: str = "core3",
        cached_content_name: Optional[str] = None,
        intent: Optional[str] = None,
        prefer_lightweight_model: bool = False,
    ) -> str:
        cfg = get_tier_config(ai_mode)
        if _estimate_tokens(prompt) > cfg["max_input_tokens"]:
            raise Core3PromptTooLarge("Prompt exceeds input token budget")
        if not self.base_url:
            return AI_FALLBACK_REPLY
        request = self._build_request(prompt, ai_mode, cfg, False)
        try:
            response_body = await asyncio.to_thread(_post_json_with_timeout, request, self.timeout_seconds)
        except (TimeoutError, HTTPError, URLError):
            return AI_FALLBACK_REPLY
        except Exception:
            return AI_FALLBACK_REPLY
        try:
            result = json.loads(response_body)
            text = (result["choices"][0]["message"]["content"] or "").strip()
            usage = result.get("usage") or {}
        except (TypeError, ValueError, KeyError, IndexError, AttributeError):
            return AI_FALLBACK_REPLY
        if not text:
            return AI_FALLBACK_REPLY
        self._set_usage(usage)
        return text

    async def generate_stream(
        self,
        prompt: str,
        *,
        ai_mode: str = "core3",
        cached_content_name: Optional[str] = None,
        intent: Optional[str] = None,
        prefer_lightweight_model: bool = False,
    ) -> AsyncGenerator[str, None]:
        cfg = get_tier_config(ai_mode)
        if _estimate_tokens(prompt) > cfg["max_input_tokens"]:
            raise Core3PromptTooLarge("Prompt exceeds input token budget")
        if not self.base_url:
            yield AI_FALLBACK_REPLY
            return

        request = self._build_request(prompt, ai_mode, cfg, True)
        queue: asyncio.Queue = asyncio.Queue()
        loop = asyncio.get_running_loop()
        thread = threading.Thread(
            target=_stream_sse_lines_with_timeout,
            args=(request, queue, loop, self.timeout_seconds),
            daemon=True,
        )
        thread.start()

        yielded_any = False
        try:
            while True:
                msg_type, val = await queue.get()
                if msg_type == "line":
                    line = val.strip()
                    if not line.startswith("data:"):
                        continue
                    raw_json = line[5:].strip()
                    if not raw_json or raw_json == "[DONE]":
                        continue
                    try:
                        chunk_data = json.loads(raw_json)
                        self._set_usage(chunk_data.get("usage"))
                        choices = chunk_data.get("choices") or []
                        choice = choices[0] if choices else {}
                        delta = (choice.get("delta") or {}).get("content") or choice.get("text") or ""
                    except Exception:
                        continue
                    if delta:
                        yielded_any = True
                        yield delta
                elif msg_type == "error":
                    if not yielded_any:
                        yield AI_FALLBACK_REPLY
                    return
                elif msg_type == "end":
                    break
        except GeneratorExit:
            raise
        except Exception:
            if not yielded_any:
                yield AI_FALLBACK_REPLY
            return

        if not yielded_any:
            yield AI_FALLBACK_REPLY


class FakeCore3Provider(BaseLLMProvider):
    provider_name = "fake"

    def resolve_model_name(self, ai_mode: str = "core3") -> str:
        return "saman-fake-v1"

    async def generate(
        self,
        prompt: str,
        *,
        ai_mode: str = "core3",
        cached_content_name: Optional[str] = None,
        intent: Optional[str] = None,
        prefer_lightweight_model: bool = False,
    ) -> str:
        cfg = get_tier_config(ai_mode)
        if _estimate_tokens(prompt) > cfg["max_input_tokens"]:
            raise Core3PromptTooLarge("Prompt exceeds input token budget")
        self.last_usage = {"prompt_tokens": _estimate_tokens(prompt), "output_tokens": 16}
        return f"[TEST/{ai_mode}] Saman Coach sẵn sàng hỗ trợ."


def create_llm_provider(provider_name: Optional[str] = None, *, engine=None) -> BaseLLMProvider:
    selected = (provider_name or os.getenv("CHAT_AI_PROVIDER") or "gemini").strip().lower()
    if selected in ("saman_custom", "custom"):
        return SamanCustomLLMProvider()
    if selected == "fake":
        return FakeCore3Provider()
    if selected in ("", "gemini"):
        return GeminiCore3Provider(engine=engine)
    logging.getLogger(__name__).warning("Unknown CHAT_AI_PROVIDER %r; falling back to gemini", selected)
    return GeminiCore3Provider(engine=engine)
