"""Unit tests for Phase 4: Smart Model Routing, Gemini Context Caching, and Render Error Observability."""

import asyncio
import io
import json
import logging
from pathlib import Path
import sys
from unittest.mock import patch
from urllib.error import HTTPError, URLError

_repo_root = str(Path(__file__).parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

import pytest

from backend.app.services.core3_provider import (
    AI_FALLBACK_REPLY,
    GeminiContextCacheManager,
    GeminiCore3Provider,
    _build_gemini_payload,
    _classify_gemini_error,
    _sanitize_log_text,
    get_tier_config,
    resolve_effective_tier,
)


def _make_http_error(
    code: int,
    body: str,
    url: str = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=AIzaSySUPER_SECRET_TEST_KEY_999",
) -> HTTPError:
    return HTTPError(url, code, "HTTP Error", {}, io.BytesIO(body.encode("utf-8")))


class _FakeJsonResponse:
    def __init__(self, payload: dict):
        self._raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        return False

    def read(self):
        return self._raw


class _FakeSSEResponse:
    def __init__(self, lines):
        self._lines = [line.encode("utf-8") if isinstance(line, str) else line for line in lines]

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        return False

    def __iter__(self):
        return iter(self._lines)


def _clear_phase4_envs(monkeypatch):
    for var in (
        "GEMINI_API_KEY",
        "STAGING_GEMINI_API_KEY",
        "GEMINI_SWIFT_MODEL",
        "GEMINI_CORE_MODEL",
        "GEMINI_PRO_MODEL",
        "GEMINI_MODEL",
        "GEMINI_ENABLE_THINKING_CONFIG",
        "GEMINI_SMART_ROUTING",
        "GEMINI_ENABLE_CONTEXT_CACHE",
        "GEMINI_CONTEXT_CACHE_TTL_SEC",
        "GEMINI_CONTEXT_CACHE_MIN_CHARS",
    ):
        monkeypatch.delenv(var, raising=False)


# ===========================================================================
# 1. SMART MODEL ROUTING
# ===========================================================================


class TestSmartModelRouting:
    def test_resolve_effective_tier_routes_general_chat_and_lightweight_to_swift3(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)

        assert resolve_effective_tier("pro3", intent="general_chat") == "swift3"
        assert resolve_effective_tier("core3", intent="general_chat") == "swift3"
        assert resolve_effective_tier("pro3", prefer_lightweight_model=True) == "swift3"
        assert resolve_effective_tier("core3", prefer_lightweight_model=True) == "swift3"

    def test_resolve_effective_tier_downgrades_pro3_single_domain_to_core3(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)

        assert resolve_effective_tier("pro3", intent="nutrition") == "core3"
        assert resolve_effective_tier("pro3", intent="recovery") == "core3"

    def test_resolve_effective_tier_preserves_pro3_for_full_audit_or_none(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)

        assert resolve_effective_tier("pro3", intent="full_audit") == "pro3"
        assert resolve_effective_tier("pro3", intent=None) == "pro3"
        assert resolve_effective_tier("pro3", intent="workout_form") == "pro3"

    @pytest.mark.parametrize("flag", ["false", "0", "no", "FALSE"])
    def test_smart_routing_disabled_preserves_requested_tier(self, monkeypatch, flag):
        _clear_phase4_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_SMART_ROUTING", flag)

        assert resolve_effective_tier("pro3", intent="general_chat") == "pro3"
        assert resolve_effective_tier("pro3", prefer_lightweight_model=True) == "pro3"
        assert resolve_effective_tier("pro3", intent="nutrition") == "pro3"
        assert resolve_effective_tier("core3", intent="general_chat") == "core3"

    def test_provider_generate_routes_url_to_effective_model(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "test-routing-key")

        captured_urls = []

        def fake_urlopen(request, timeout=15.0):
            captured_urls.append(request.full_url)
            return _FakeJsonResponse(
                {
                    "candidates": [{"content": {"parts": [{"text": "OK"}]}}],
                    "usageMetadata": {"promptTokenCount": 5, "candidatesTokenCount": 2},
                }
            )

        provider = GeminiCore3Provider()
        with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
            asyncio.run(provider.generate("Chào bạn", ai_mode="pro3", intent="general_chat"))
            asyncio.run(provider.generate("Gợi ý thực đơn", ai_mode="pro3", intent="nutrition"))
            asyncio.run(provider.generate("Đánh giá toàn diện", ai_mode="pro3", intent="full_audit"))

        assert "models/gemini-2.5-flash-lite:generateContent" in captured_urls[0]
        assert "models/gemini-2.5-flash:generateContent" in captured_urls[1]
        assert "models/gemini-2.5-pro:generateContent" in captured_urls[2]


# ===========================================================================
# 2. GEMINI CONTEXT CACHING
# ===========================================================================


class TestGeminiContextCacheManager:
    def test_returns_none_without_http_when_env_disabled(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)
        manager = GeminiContextCacheManager()
        long_prefix = "A" * 5000

        with patch("backend.app.services.core3_provider.urlopen") as mock_urlopen:
            result = manager.get_or_create_cache(
                "test-key",
                "gemini-2.5-flash",
                long_prefix,
                cache_key="user-1:core3",
            )

        assert result is None
        mock_urlopen.assert_not_called()

    def test_returns_none_when_prefix_below_min_chars_or_swift3(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_ENABLE_CONTEXT_CACHE", "true")
        monkeypatch.setenv("GEMINI_CONTEXT_CACHE_MIN_CHARS", "4000")
        manager = GeminiContextCacheManager()

        with patch("backend.app.services.core3_provider.urlopen") as mock_urlopen:
            short_res = manager.get_or_create_cache(
                "test-key",
                "gemini-2.5-flash",
                "short text",
                cache_key="user-1:short",
            )
            swift_res = manager.get_or_create_cache(
                "test-key",
                "gemini-2.5-flash-lite",
                "B" * 5000,
                cache_key="user-1:swift",
                tier="swift3",
            )

        assert short_res is None
        assert swift_res is None
        mock_urlopen.assert_not_called()

    def test_creates_cache_once_and_serves_hit_without_extra_http(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_ENABLE_CONTEXT_CACHE", "true")
        monkeypatch.setenv("GEMINI_CONTEXT_CACHE_TTL_SEC", "1800")
        monkeypatch.setenv("GEMINI_CONTEXT_CACHE_MIN_CHARS", "100")

        manager = GeminiContextCacheManager()
        captured_requests = []

        def fake_urlopen(request, timeout=15.0):
            captured_requests.append(
                (request.full_url, json.loads(request.data.decode("utf-8")))
            )
            return _FakeJsonResponse({"name": "cachedContents/cache_abc_123"})

        prefix = "X" * 200
        with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
            first = manager.get_or_create_cache(
                "test-key",
                "gemini-2.5-flash",
                prefix,
                cache_key="user-42:core3",
                system_instruction="Bạn là Saman Coach.",
            )
            second = manager.get_or_create_cache(
                "test-key",
                "gemini-2.5-flash",
                prefix,
                cache_key="user-42:core3",
                system_instruction="Bạn là Saman Coach.",
            )

        assert first == "cachedContents/cache_abc_123"
        assert second == "cachedContents/cache_abc_123"
        assert len(captured_requests) == 1
        req_url, req_body = captured_requests[0]
        assert "/v1beta/cachedContents" in req_url
        assert req_body["model"] == "models/gemini-2.5-flash"
        assert req_body["ttl"] == "1800s"
        assert req_body["contents"][0]["parts"][0]["text"] == prefix
        assert req_body["systemInstruction"]["parts"][0]["text"] == "Bạn là Saman Coach."

    @pytest.mark.parametrize("status_code", [400, 500])
    def test_returns_none_safely_on_http_error_without_leaking_key(self, monkeypatch, caplog, status_code):
        _clear_phase4_envs(monkeypatch)
        secret = "AIzaSySUPER_SECRET_TEST_KEY_999"
        monkeypatch.setenv("GEMINI_API_KEY", secret)
        monkeypatch.setenv("GEMINI_ENABLE_CONTEXT_CACHE", "true")
        monkeypatch.setenv("GEMINI_CONTEXT_CACHE_MIN_CHARS", "50")

        manager = GeminiContextCacheManager()

        def fake_urlopen(request, timeout=15.0):
            raise _make_http_error(
                status_code,
                f'{{"error": {{"code": {status_code}, "message": "Cache creation failed for key={secret}"}}}}',
                url=f"https://generativelanguage.googleapis.com/v1beta/cachedContents?key={secret}",
            )

        with caplog.at_level(logging.WARNING, logger="backend.app.services.core3_provider"):
            with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
                result = manager.get_or_create_cache(
                    secret,
                    "gemini-2.5-flash",
                    "Y" * 100,
                    cache_key="user-err:core3",
                )

        assert result is None
        assert any("gemini_context_cache_failed" in rec.message for rec in caplog.records)
        for rec in caplog.records:
            assert secret not in rec.getMessage()


# ===========================================================================
# 3. CACHED CONTENT PAYLOAD & 404 AUTO-RETRY IN GENERATE / GENERATE_STREAM
# ===========================================================================


class TestCachedContentGenerateAndStream:
    def test_build_payload_includes_cached_content_when_provided(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)
        cfg = get_tier_config("core3")

        payload_with_cache = _build_gemini_payload(
            "Hôm nay ăn gì?",
            cfg,
            cached_content_name="cachedContents/abc",
        )
        payload_without_cache = _build_gemini_payload("Hôm nay ăn gì?", cfg)

        assert payload_with_cache["cachedContent"] == "cachedContents/abc"
        assert "cachedContent" not in payload_without_cache

    def test_generate_sends_cached_content_and_retries_once_on_404_expired(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        monkeypatch.setenv("GEMINI_ENABLE_THINKING_CONFIG", "false")

        captured_payloads = []

        def fake_urlopen(request, timeout=15.0):
            payload = json.loads(request.data.decode("utf-8"))
            captured_payloads.append(payload)
            if len(captured_payloads) == 1:
                raise _make_http_error(
                    404,
                    '{"error": {"code": 404, "message": "CachedContent cachedContents/abc not found or expired"}}',
                )
            return _FakeJsonResponse(
                {
                    "candidates": [{"content": {"parts": [{"text": "Phản hồi không cache thành công"}]}}],
                    "usageMetadata": {"promptTokenCount": 15, "candidatesTokenCount": 7},
                }
            )

        provider = GeminiCore3Provider()
        with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
            reply = asyncio.run(
                provider.generate(
                    "Gợi ý bữa tối",
                    ai_mode="core3",
                    cached_content_name="cachedContents/abc",
                )
            )

        assert reply == "Phản hồi không cache thành công"
        assert len(captured_payloads) == 2
        assert captured_payloads[0].get("cachedContent") == "cachedContents/abc"
        assert "cachedContent" not in captured_payloads[1]

    def test_generate_stream_sends_cached_content_and_retries_once_on_404_expired(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        monkeypatch.setenv("GEMINI_ENABLE_THINKING_CONFIG", "false")

        captured_payloads = []

        def fake_urlopen(request, timeout=30.0):
            payload = json.loads(request.data.decode("utf-8"))
            captured_payloads.append(payload)
            if len(captured_payloads) == 1:
                raise _make_http_error(
                    404,
                    '{"error": {"code": 404, "message": "CachedContent cachedContents/abc expired"}}',
                )
            return _FakeSSEResponse(
                [
                    'data: {"candidates":[{"content":{"parts":[{"text":"Stream "}]}}]}\n',
                    'data: {"candidates":[{"content":{"parts":[{"text":"OK"}]}}]}\n',
                    "data: [DONE]\n",
                ]
            )

        async def _collect():
            provider = GeminiCore3Provider()
            return [
                chunk
                async for chunk in provider.generate_stream(
                    "Gợi ý bữa sáng",
                    ai_mode="core3",
                    cached_content_name="cachedContents/abc",
                )
            ]

        with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
            chunks = asyncio.run(_collect())

        assert chunks == ["Stream ", "OK"]
        assert len(captured_payloads) == 2
        assert captured_payloads[0].get("cachedContent") == "cachedContents/abc"
        assert "cachedContent" not in captured_payloads[1]


# ===========================================================================
# 4. RENDER ERROR OBSERVABILITY (SECRET-SAFE DIAGNOSTIC LOGGING)
# ===========================================================================


class TestRenderErrorObservability:
    def test_sanitize_log_text_strips_keys_and_truncates_to_300_chars(self, monkeypatch):
        _clear_phase4_envs(monkeypatch)
        secret = "AIzaSySUPER_SECRET_TEST_KEY_999"
        monkeypatch.setenv("GEMINI_API_KEY", secret)

        raw = f"POST https://generativelanguage.googleapis.com/v1beta/models/x?alt=sse&key={secret} failed: " + ("z" * 400)
        sanitized = _sanitize_log_text(raw)

        assert secret not in sanitized
        assert "key=[REDACTED]" in sanitized
        assert len(sanitized) <= 300

    def test_missing_api_key_logs_missing_api_key(self, monkeypatch, caplog):
        _clear_phase4_envs(monkeypatch)

        provider = GeminiCore3Provider()
        with caplog.at_level(logging.ERROR, logger="backend.app.services.core3_provider"):
            reply = asyncio.run(provider.generate("Chào bạn", ai_mode="core3"))

        assert reply == AI_FALLBACK_REPLY
        assert provider.last_error is not None
        assert provider.last_error["reason"] == "missing_api_key"
        messages = [rec.getMessage() for rec in caplog.records]
        assert any("gemini_request_failed" in m and "reason=missing_api_key" in m for m in messages)

    def test_http_404_model_not_found_logs_safely_without_leaking_api_key(self, monkeypatch, caplog):
        _clear_phase4_envs(monkeypatch)
        secret = "AIzaSySUPER_SECRET_TEST_KEY_999"
        monkeypatch.setenv("GEMINI_API_KEY", secret)
        monkeypatch.setenv("GEMINI_CORE_MODEL", "gemini-nonexistent-99")

        def fake_urlopen(request, timeout=15.0):
            raise _make_http_error(
                404,
                f'{{"error": {{"code": 404, "message": "models/gemini-nonexistent-99 is not found for API version v1beta (url=https://generativelanguage.googleapis.com/v1beta/models/gemini-nonexistent-99:generateContent?key={secret})"}}}}',
                url=f"https://generativelanguage.googleapis.com/v1beta/models/gemini-nonexistent-99:generateContent?key={secret}",
            )

        provider = GeminiCore3Provider()
        with caplog.at_level(logging.ERROR, logger="backend.app.services.core3_provider"):
            with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
                reply = asyncio.run(provider.generate("Chào bạn", ai_mode="core3"))

        assert reply == AI_FALLBACK_REPLY
        assert provider.last_error is not None
        assert provider.last_error["http_status"] == 404
        assert provider.last_error["reason"] == "model_not_found"
        assert provider.last_error["model"] == "gemini-nonexistent-99"
        assert secret not in json.dumps(provider.last_error)

        messages = [rec.getMessage() for rec in caplog.records]
        assert any(
            "http_status=404" in m
            and "reason=model_not_found" in m
            and "model=gemini-nonexistent-99" in m
            for m in messages
        )
        for msg in messages:
            assert secret not in msg

    @pytest.mark.parametrize(
        "status_code,body,expected_reason",
        [
            (
                403,
                '{"error": {"code": 403, "message": "API key not valid. Please pass a valid API key: AIzaSySUPER_SECRET_TEST_KEY_999"}}',
                "invalid_api_key",
            ),
            (
                429,
                '{"error": {"code": 429, "status": "RESOURCE_EXHAUSTED", "message": "Quota exceeded for key=AIzaSySUPER_SECRET_TEST_KEY_999"}}',
                "quota_or_rate_limit",
            ),
        ],
    )
    def test_http_403_and_429_log_classified_reason_without_leaking_key(
        self, monkeypatch, caplog, status_code, body, expected_reason
    ):
        _clear_phase4_envs(monkeypatch)
        secret = "AIzaSySUPER_SECRET_TEST_KEY_999"
        monkeypatch.setenv("GEMINI_API_KEY", secret)

        def fake_urlopen(request, timeout=15.0):
            raise _make_http_error(status_code, body)

        provider = GeminiCore3Provider()
        with caplog.at_level(logging.ERROR, logger="backend.app.services.core3_provider"):
            with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
                reply = asyncio.run(provider.generate("Gợi ý bữa trưa", ai_mode="core3"))

        assert reply == AI_FALLBACK_REPLY
        assert provider.last_error is not None
        assert provider.last_error["http_status"] == status_code
        assert provider.last_error["reason"] == expected_reason

        messages = [rec.getMessage() for rec in caplog.records]
        assert any(
            f"http_status={status_code}" in m and f"reason={expected_reason}" in m
            for m in messages
        )
        for msg in messages:
            assert secret not in msg

    def test_stream_logs_classified_error_without_leaking_key(self, monkeypatch, caplog):
        _clear_phase4_envs(monkeypatch)
        secret = "AIzaSySUPER_SECRET_TEST_KEY_999"
        monkeypatch.setenv("GEMINI_API_KEY", secret)

        def fake_urlopen(request, timeout=30.0):
            raise _make_http_error(
                429,
                f'{{"error": {{"code": 429, "status": "RESOURCE_EXHAUSTED", "message": "Rate limit exceeded for {secret}"}}}}',
            )

        async def _collect():
            provider = GeminiCore3Provider()
            chunks = [c async for c in provider.generate_stream("Tư vấn tập luyện", ai_mode="pro3")]
            return chunks, provider

        with caplog.at_level(logging.ERROR, logger="backend.app.services.core3_provider"):
            with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
                chunks, provider = asyncio.run(_collect())

        assert chunks == [AI_FALLBACK_REPLY]
        assert provider.last_error is not None
        assert provider.last_error["reason"] == "quota_or_rate_limit"
        messages = [rec.getMessage() for rec in caplog.records]
        assert any("http_status=429" in m and "reason=quota_or_rate_limit" in m for m in messages)
        for msg in messages:
            assert secret not in msg

    def test_timeout_and_network_error_classification(self):
        assert _classify_gemini_error(None, "timed out", TimeoutError("request timed out")) == "timeout"
        assert _classify_gemini_error(None, "DNS failure", URLError("Name or service not known")) == "network_error"
        assert _classify_gemini_error(503, "Service Unavailable") == "server_error"
        assert _classify_gemini_error(400, "Invalid argument") == "bad_request"
