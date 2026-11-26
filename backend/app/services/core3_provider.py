"""Gemini-only bounded prompt adapter for Core 3."""

import asyncio
import copy
import json
import os
import logging
import threading
from abc import ABC, abstractmethod
from typing import Any, AsyncGenerator, Dict, List, Optional
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

logger = logging.getLogger(__name__)

MAX_INPUT_TOKENS = 4096
MAX_OUTPUT_TOKENS = 512
AI_FALLBACK_REPLY = "Xin lỗi, trợ lý AI hiện đang bảo trì, vui lòng thử lại sau."

DEFAULT_GEMINI_SWIFT_MODEL = "gemini-2.5-flash-lite"
DEFAULT_GEMINI_CORE_MODEL = "gemini-2.5-flash"
DEFAULT_GEMINI_PRO_MODEL = "gemini-2.5-pro"

_THINKING_CONFIG_ERROR_MARKERS = (
    "thinkingconfig",
    "thinkinglevel",
    "thinking_level",
    "thinking_config",
)

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


def _build_gemini_payload(prompt: str, cfg: dict) -> dict:
    generation_config: Dict[str, Any] = {
        "maxOutputTokens": cfg["max_output_tokens"],
        "temperature": cfg["temperature"],
    }
    if _should_include_thinking_config(cfg):
        generation_config["thinkingConfig"] = {"thinkingLevel": cfg["thinking_level"]}
    return {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": generation_config,
    }


TIER_CONFIGS = {
    "swift3": {
        "model": _resolve_tier_model("swift3"),
        "thinking_level": "minimal",
        "temperature": 0.3,
        "max_input_tokens": 3072,
        "max_output_tokens": 256,
    },
    "core3": {
        "model": _resolve_tier_model("core3"),
        "thinking_level": "low",
        "temperature": 0.4,
        "max_input_tokens": 4096,
        "max_output_tokens": 512,
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
            "max_output_tokens": 256,
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
            "max_output_tokens": 512,
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

    def resolve_model_name(self, ai_mode: str = "core3") -> str:
        return get_tier_config(ai_mode)["model"]

    @abstractmethod
    async def generate(self, prompt: str, *, ai_mode: str = "core3") -> str:
        raise NotImplementedError

    async def generate_stream(self, prompt: str, *, ai_mode: str = "core3") -> AsyncGenerator[str, None]:
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
        ai_mode = str((config or {}).get("ai_mode") or "core3")
        max_input = (config or {}).get("max_input_tokens")
        prompt = render_prompt(
            question,
            history,
            context_json,
            system_instruction=system_prompt or DEFAULT_SYSTEM_INSTRUCTION,
            max_input_tokens=max_input,
            ai_mode=ai_mode,
        )
        return await self.generate(prompt, ai_mode=ai_mode)


class GeminiCore3Provider(BaseLLMProvider):
    provider_name = "gemini"

    def __init__(self, engine=None):
        self.engine = engine
        self.last_usage = None

    async def generate(self, prompt, *, ai_mode: str = "core3"):
        cfg = get_tier_config(ai_mode)
        if _estimate_tokens(prompt) > cfg["max_input_tokens"]:
            raise Core3PromptTooLarge("Prompt exceeds input token budget")
        if self.engine is not None:
            result = self.engine.generate_content(prompt, generation_config={"max_output_tokens": cfg["max_output_tokens"]})
            if asyncio.iscoroutine(result):
                result = await result
            return getattr(result, "text", result)
        key = (os.getenv("GEMINI_API_KEY") or os.getenv("STAGING_GEMINI_API_KEY") or "").strip()
        if not key:
            return AI_FALLBACK_REPLY
        model = cfg["model"]
        try:
            import google.generativeai as genai
            genai.configure(api_key=key)
            _ = genai.GenerativeModel(model)
        except Exception:
            pass
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        endpoint_url = f"{url}?{urlencode({'key': key})}"
        payload = _build_gemini_payload(prompt, cfg)
        has_thinking_config = isinstance(payload.get("generationConfig"), dict) and "thinkingConfig" in payload["generationConfig"]
        request = Request(
            endpoint_url,
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            response_body = await asyncio.to_thread(_post_json, request)
        except HTTPError as exc:
            if has_thinking_config and _is_thinking_config_error(exc.code, _read_http_error_body(exc)):
                logger.warning(
                    "Gemini model '%s' rejected thinkingConfig (HTTP 400); retrying once without thinkingConfig",
                    model,
                )
                retry_payload = _strip_thinking_config(payload)
                retry_request = Request(
                    endpoint_url,
                    data=json.dumps(retry_payload, ensure_ascii=False).encode("utf-8"),
                    headers={"Content-Type": "application/json"},
                    method="POST",
                )
                try:
                    response_body = await asyncio.to_thread(_post_json, retry_request)
                except (TimeoutError, HTTPError, URLError, Exception):
                    return AI_FALLBACK_REPLY
            else:
                return AI_FALLBACK_REPLY
        except TimeoutError:
            return AI_FALLBACK_REPLY
        except URLError:
            return AI_FALLBACK_REPLY
        except Exception:
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

    async def generate_stream(self, prompt, *, ai_mode: str = "core3") -> AsyncGenerator[str, None]:
        cfg = get_tier_config(ai_mode)
        if _estimate_tokens(prompt) > cfg["max_input_tokens"]:
            raise Core3PromptTooLarge("Prompt exceeds input token budget")

        key = (os.getenv("GEMINI_API_KEY") or os.getenv("STAGING_GEMINI_API_KEY") or "").strip()
        if self.engine is not None or not key:
            full_text = await self.generate(prompt, ai_mode=ai_mode)
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
        payload = _build_gemini_payload(prompt, cfg)
        has_thinking_config = isinstance(payload.get("generationConfig"), dict) and "thinkingConfig" in payload["generationConfig"]
        request = Request(
            stream_url,
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
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
                    if (
                        not yielded_any
                        and not retried_without_thinking
                        and has_thinking_config
                        and isinstance(val, HTTPError)
                        and _is_thinking_config_error(val.code, _read_http_error_body(val))
                    ):
                        logger.warning(
                            "Gemini model '%s' rejected thinkingConfig on stream (HTTP 400); retrying once without thinkingConfig",
                            model,
                        )
                        retried_without_thinking = True
                        retry_payload = _strip_thinking_config(payload)
                        retry_request = Request(
                            stream_url,
                            data=json.dumps(retry_payload, ensure_ascii=False).encode("utf-8"),
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

    async def generate(self, prompt: str, *, ai_mode: str = "core3") -> str:
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

    async def generate_stream(self, prompt: str, *, ai_mode: str = "core3") -> AsyncGenerator[str, None]:
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

    async def generate(self, prompt: str, *, ai_mode: str = "core3") -> str:
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
