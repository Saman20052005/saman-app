"""Gemini-only bounded prompt adapter for Core 3."""

import asyncio
import json
import os
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

MAX_INPUT_TOKENS = 4096
MAX_OUTPUT_TOKENS = 512


class Core3PromptTooLarge(ValueError):
    pass


class ProviderError(RuntimeError):
    """Sanitized provider failure metadata; never includes request credentials."""

    def __init__(self, status, *, retryable):
        self.status = status
        self.retryable = retryable
        super().__init__(status)


def _estimate_tokens(text):
    # UTF-8 byte count is a conservative local upper bound for token count and
    # avoids making a provider call just to measure a request before dispatch.
    return max(1, len(text.encode("utf-8")))


def render_prompt(question, history, context, system_instruction=(
    "Bạn là Saman Coach, trợ lý dinh dưỡng và luyện tập chỉ đưa ra lời khuyên. "
    "Luôn trả lời hoàn chỉnh bằng tiếng Việt tự nhiên, ngắn gọn trong 2-4 câu và an toàn; không chỉ viết tiêu đề. "
    "Chỉ sử dụng số liệu và hoạt động có trong ngữ cảnh được cung cấp; không tự bịa dữ liệu lịch sử. "
    "Khi ngữ cảnh có nhật ký, hãy nêu chính xác các số liệu liên quan và tên bài tập/số hiệp đã ghi. "
    "Nếu ngữ cảnh cho biết thiếu dữ liệu dinh dưỡng hoặc tập luyện, hãy nói rõ: "
    '"Hiện chưa có dữ liệu dinh dưỡng/tập luyện gần đây của bạn", đưa ra gợi ý chung an toàn '
    "và khuyến khích người dùng ghi nhật ký. Nếu ngữ cảnh bị rút gọn, hãy nói đây là tóm tắt. "
    "Không khẳng định đã lưu bữa ăn hoặc bài tập; mọi thay đổi dữ liệu cần người dùng xác nhận."
)):
    history = [item for item in (history or []) if isinstance(item, dict)]
    context_text = json.dumps(context or {}, ensure_ascii=False, separators=(",", ":"))
    mandatory = f"{system_instruction}\nQuestion: {question}"
    if _estimate_tokens(mandatory) > MAX_INPUT_TOKENS:
        raise Core3PromptTooLarge("Mandatory prompt exceeds input token budget")
    while True:
        history_text = "\n".join(
            f"{str(m.get('role', 'user'))}: {str(m.get('content', ''))}"
            for m in history
        )
        prompt = f"{system_instruction}\nContext: {context_text}\nHistory:\n{history_text}\nQuestion: {question}"
        if _estimate_tokens(prompt) <= MAX_INPUT_TOKENS:
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


class GeminiCore3Provider:
    def __init__(self, engine=None):
        self.engine = engine
        self.last_usage = None

    async def generate(self, prompt):
        if _estimate_tokens(prompt) > MAX_INPUT_TOKENS:
            raise Core3PromptTooLarge("Prompt exceeds input token budget")
        if self.engine is not None:
            result = self.engine.generate_content(prompt, generation_config={"max_output_tokens": MAX_OUTPUT_TOKENS})
            if asyncio.iscoroutine(result):
                result = await result
            return getattr(result, "text", result)
        key = os.getenv("GEMINI_API_KEY") or os.getenv("STAGING_GEMINI_API_KEY")
        if not key:
            raise RuntimeError("Gemini is not configured")
        model = os.getenv("GEMINI_MODEL", "gemini-3.6-flash")
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
        payload = {
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {
                "maxOutputTokens": MAX_OUTPUT_TOKENS,
                "temperature": 0.4,
                "thinkingConfig": {"thinkingLevel": "minimal"},
            },
        }
        request = Request(
            f"{url}?{urlencode({'key': key})}",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            response_body = await asyncio.to_thread(_post_json, request)
        except TimeoutError:
            raise ProviderError("timeout", retryable=True) from None
        except HTTPError as exc:
            if exc.code == 429:
                raise ProviderError("quota_exceeded", retryable=False) from None
            if exc.code >= 500:
                raise ProviderError("server_error", retryable=True) from None
            raise ProviderError("request_rejected", retryable=False) from None
        except URLError:
            raise ProviderError("network_error", retryable=True) from None
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
                raise ValueError("Gemini response has no text")
            usage = result.get("usageMetadata") or {}
        except (TypeError, ValueError, KeyError, IndexError):
            raise ProviderError("invalid_response", retryable=False) from None
        self.last_usage = {
            "prompt_tokens": usage.get("promptTokenCount"),
            "output_tokens": usage.get("candidatesTokenCount"),
        }
        return text


def _post_json(request):
    with urlopen(request, timeout=15.0) as response:
        return response.read().decode("utf-8")
