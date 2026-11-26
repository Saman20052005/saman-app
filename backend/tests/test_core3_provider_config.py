"""Unit tests for core3_provider model config, thinkingConfig toggle, and HTTP 400 retry."""

import asyncio
import io
import json
import logging
from pathlib import Path
import sys
from unittest.mock import patch
from urllib.error import HTTPError

_repo_root = str(Path(__file__).parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

import pytest

from backend.app.services.core3_provider import (
    AI_FALLBACK_REPLY,
    GeminiCore3Provider,
    _is_thinking_config_error,
    _strip_thinking_config,
    get_tier_config,
)


def _make_http_error(code: int, body: str, url: str = "https://generativelanguage.googleapis.com/v1beta/test") -> HTTPError:
    return HTTPError(url, code, "Bad Request", {}, io.BytesIO(body.encode("utf-8")))


class _FakeSSEResponse:
    def __init__(self, lines):
        self._lines = [line.encode("utf-8") if isinstance(line, str) else line for line in lines]

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        return False

    def __iter__(self):
        return iter(self._lines)


class _FakeJsonResponse:
    def __init__(self, payload: dict):
        self._raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        return False

    def read(self):
        return self._raw


def _clear_gemini_model_envs(monkeypatch):
    for var in (
        "GEMINI_SWIFT_MODEL",
        "GEMINI_CORE_MODEL",
        "GEMINI_PRO_MODEL",
        "GEMINI_MODEL",
        "GEMINI_ENABLE_THINKING_CONFIG",
    ):
        monkeypatch.delenv(var, raising=False)


class TestModelResolution:
    def test_default_model_resolution_without_env(self, monkeypatch):
        _clear_gemini_model_envs(monkeypatch)

        assert get_tier_config("swift3")["model"] == "gemini-2.5-flash-lite"
        assert get_tier_config("core3")["model"] == "gemini-2.5-flash"
        assert get_tier_config("pro3")["model"] == "gemini-2.5-pro"

        provider = GeminiCore3Provider()
        assert provider.resolve_model_name("swift3") == "gemini-2.5-flash-lite"
        assert provider.resolve_model_name("core3") == "gemini-2.5-flash"
        assert provider.resolve_model_name("pro3") == "gemini-2.5-pro"

    def test_model_override_via_tier_env_vars(self, monkeypatch):
        _clear_gemini_model_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_SWIFT_MODEL", "gemini-2.5-flash-lite-custom")
        monkeypatch.setenv("GEMINI_CORE_MODEL", "gemini-2.5-flash-custom")
        monkeypatch.setenv("GEMINI_PRO_MODEL", "gemini-2.5-pro-custom")

        assert get_tier_config("swift3")["model"] == "gemini-2.5-flash-lite-custom"
        assert get_tier_config("core3")["model"] == "gemini-2.5-flash-custom"
        assert get_tier_config("pro3")["model"] == "gemini-2.5-pro-custom"

    def test_legacy_gemini_model_fallback_and_tier_precedence(self, monkeypatch):
        _clear_gemini_model_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_MODEL", "gemini-2.5-flash-legacy")

        assert get_tier_config("swift3")["model"] == "gemini-2.5-flash-lite"
        assert get_tier_config("core3")["model"] == "gemini-2.5-flash-legacy"
        assert get_tier_config("pro3")["model"] == "gemini-2.5-flash-legacy"

        monkeypatch.setenv("GEMINI_PRO_MODEL", "gemini-2.5-pro-override")
        assert get_tier_config("pro3")["model"] == "gemini-2.5-pro-override"


class TestThinkingConfigHelpers:
    @pytest.mark.parametrize(
        "body",
        [
            '{"error": {"message": "Unknown name \\"thinkingConfig\\" in generationConfig"}}',
            '{"error": {"message": "Invalid value for thinkingLevel"}}',
            '{"error": {"message": "Unsupported field thinking_level"}}',
            '{"error": {"message": "thinking_config is not supported by this model"}}',
        ],
    )
    def test_is_thinking_config_error_matches_400_markers(self, body):
        assert _is_thinking_config_error(400, body) is True

    def test_is_thinking_config_error_rejects_non_400_or_unrelated(self):
        assert _is_thinking_config_error(500, "thinkingConfig error") is False
        assert _is_thinking_config_error(403, "thinkingLevel rejected") is False
        assert _is_thinking_config_error(400, '{"error": {"message": "API key not valid"}}') is False
        assert _is_thinking_config_error(400, "") is False

    def test_strip_thinking_config_does_not_mutate_original(self):
        original = {
            "contents": [{"role": "user", "parts": [{"text": "hello"}]}],
            "generationConfig": {
                "maxOutputTokens": 512,
                "temperature": 0.4,
                "thinkingConfig": {"thinkingLevel": "low"},
            },
        }
        stripped = _strip_thinking_config(original)

        assert "thinkingConfig" in original["generationConfig"]
        assert "thinkingConfig" not in stripped["generationConfig"]
        assert stripped["generationConfig"]["maxOutputTokens"] == 512
        assert stripped["generationConfig"]["temperature"] == 0.4


class TestThinkingConfigToggle:
    @pytest.mark.parametrize("flag_value", ["false", "0", "no", "FALSE"])
    def test_generate_omits_thinking_config_when_disabled(self, monkeypatch, flag_value):
        _clear_gemini_model_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        monkeypatch.setenv("GEMINI_ENABLE_THINKING_CONFIG", flag_value)

        captured_payloads = []

        def fake_urlopen(request, timeout=15.0):
            captured_payloads.append(json.loads(request.data.decode("utf-8")))
            return _FakeJsonResponse(
                {
                    "candidates": [{"content": {"parts": [{"text": "Xin chào!"}]}}],
                    "usageMetadata": {"promptTokenCount": 10, "candidatesTokenCount": 5},
                }
            )

        provider = GeminiCore3Provider()
        with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
            reply = asyncio.run(provider.generate("Chào bạn", ai_mode="core3"))

        assert reply == "Xin chào!"
        assert len(captured_payloads) == 1
        assert "thinkingConfig" not in captured_payloads[0]["generationConfig"]

    def test_generate_stream_omits_thinking_config_when_disabled(self, monkeypatch):
        _clear_gemini_model_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        monkeypatch.setenv("GEMINI_ENABLE_THINKING_CONFIG", "false")

        captured_payloads = []

        def fake_urlopen(request, timeout=30.0):
            captured_payloads.append(json.loads(request.data.decode("utf-8")))
            return _FakeSSEResponse(
                [
                    'data: {"candidates":[{"content":{"parts":[{"text":"Chào "}]}}]}\n',
                    'data: {"candidates":[{"content":{"parts":[{"text":"bạn!"}]}}]}\n',
                    "data: [DONE]\n",
                ]
            )

        async def _collect():
            provider = GeminiCore3Provider()
            chunks = []
            async for chunk in provider.generate_stream("Chào bạn", ai_mode="core3"):
                chunks.append(chunk)
            return chunks

        with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
            chunks = asyncio.run(_collect())

        assert chunks == ["Chào ", "bạn!"]
        assert len(captured_payloads) == 1
        assert "thinkingConfig" not in captured_payloads[0]["generationConfig"]


class TestThinkingConfigRetry:
    def test_generate_retries_once_on_400_thinking_error_and_succeeds(self, monkeypatch, caplog):
        _clear_gemini_model_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        monkeypatch.setenv("GEMINI_ENABLE_THINKING_CONFIG", "auto")

        captured_payloads = []

        def fake_urlopen(request, timeout=15.0):
            payload = json.loads(request.data.decode("utf-8"))
            captured_payloads.append(payload)
            if len(captured_payloads) == 1:
                raise _make_http_error(
                    400,
                    '{"error": {"code": 400, "message": "Invalid JSON payload received. Unknown name \\"thinkingLevel\\" at generationConfig.thinkingConfig"}}',
                )
            return _FakeJsonResponse(
                {
                    "candidates": [{"content": {"parts": [{"text": "Phản hồi sau retry"}]}}],
                    "usageMetadata": {"promptTokenCount": 20, "candidatesTokenCount": 8},
                }
            )

        provider = GeminiCore3Provider()
        with caplog.at_level(logging.WARNING, logger="backend.app.services.core3_provider"):
            with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
                reply = asyncio.run(provider.generate("Gợi ý bữa tối", ai_mode="core3"))

        assert reply == "Phản hồi sau retry"
        assert provider.last_usage == {"prompt_tokens": 20, "output_tokens": 8}
        assert len(captured_payloads) == 2
        assert "thinkingConfig" in captured_payloads[0]["generationConfig"]
        assert "thinkingConfig" not in captured_payloads[1]["generationConfig"]
        assert any("gemini-2.5-flash" in rec.message for rec in caplog.records)

    def test_generate_stream_retries_once_on_400_thinking_error_and_streams(self, monkeypatch, caplog):
        _clear_gemini_model_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        monkeypatch.setenv("GEMINI_ENABLE_THINKING_CONFIG", "auto")

        captured_payloads = []

        def fake_urlopen(request, timeout=30.0):
            payload = json.loads(request.data.decode("utf-8"))
            captured_payloads.append(payload)
            if len(captured_payloads) == 1:
                raise _make_http_error(
                    400,
                    '{"error": {"code": 400, "message": "thinkingConfig is not supported for this model"}}',
                )
            return _FakeSSEResponse(
                [
                    'data: {"candidates":[{"content":{"parts":[{"text":"Stream "}]}}]}\n',
                    'data: {"candidates":[{"content":{"parts":[{"text":"thành công"}]}}],"usageMetadata":{"promptTokenCount":12,"candidatesTokenCount":6}}\n',
                    "data: [DONE]\n",
                ]
            )

        async def _collect():
            provider = GeminiCore3Provider()
            chunks = []
            async for chunk in provider.generate_stream("Tư vấn tập ngực", ai_mode="pro3"):
                chunks.append(chunk)
            return chunks, provider.last_usage

        with caplog.at_level(logging.WARNING, logger="backend.app.services.core3_provider"):
            with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
                chunks, usage = asyncio.run(_collect())

        assert chunks == ["Stream ", "thành công"]
        assert AI_FALLBACK_REPLY not in chunks
        assert usage == {"prompt_tokens": 12, "output_tokens": 6}
        assert len(captured_payloads) == 2
        assert "thinkingConfig" in captured_payloads[0]["generationConfig"]
        assert "thinkingConfig" not in captured_payloads[1]["generationConfig"]
        assert any("gemini-2.5-pro" in rec.message for rec in caplog.records)

    def test_generate_does_not_retry_on_unrelated_400(self, monkeypatch):
        _clear_gemini_model_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "invalid-key")

        call_count = 0

        def fake_urlopen(request, timeout=15.0):
            nonlocal call_count
            call_count += 1
            raise _make_http_error(
                400,
                '{"error": {"code": 400, "message": "API key not valid. Please pass a valid API key."}}',
            )

        provider = GeminiCore3Provider()
        with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
            reply = asyncio.run(provider.generate("Chào bạn", ai_mode="core3"))

        assert call_count == 1
        assert reply == AI_FALLBACK_REPLY

    def test_generate_stream_does_not_retry_on_unrelated_400(self, monkeypatch):
        _clear_gemini_model_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "invalid-key")

        call_count = 0

        def fake_urlopen(request, timeout=30.0):
            nonlocal call_count
            call_count += 1
            raise _make_http_error(
                400,
                '{"error": {"code": 400, "message": "Invalid argument: prompt blocked"}}',
            )

        async def _collect():
            provider = GeminiCore3Provider()
            return [c async for c in provider.generate_stream("Chào bạn", ai_mode="swift3")]

        with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
            chunks = asyncio.run(_collect())

        assert call_count == 1
        assert chunks == [AI_FALLBACK_REPLY]

    def test_generate_stream_caps_retry_at_one_attempt(self, monkeypatch):
        _clear_gemini_model_envs(monkeypatch)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")

        call_count = 0

        def fake_urlopen(request, timeout=30.0):
            nonlocal call_count
            call_count += 1
            raise _make_http_error(
                400,
                '{"error": {"code": 400, "message": "thinkingConfig still rejected"}}',
            )

        async def _collect():
            provider = GeminiCore3Provider()
            return [c async for c in provider.generate_stream("Chào bạn", ai_mode="core3")]

        with patch("backend.app.services.core3_provider.urlopen", side_effect=fake_urlopen):
            chunks = asyncio.run(_collect())

        assert call_count == 2
        assert chunks == [AI_FALLBACK_REPLY]
