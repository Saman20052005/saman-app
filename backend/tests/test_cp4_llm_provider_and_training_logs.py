"""
Test suite for CP4.1:
1. Provider Switching (BaseLLMProvider, FakeCore3Provider, SamanCustomLLMProvider, GeminiCore3Provider).
2. PII Anonymization in chat_training_logs (scrub_pii, hash_user_id, record_chat_training_turn).
3. user_action_taken updates on action confirmation and cancellation.
"""

import asyncio
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
from typing import Any, Dict, List, Optional
from unittest.mock import MagicMock, patch

_repo_root = str(Path(__file__).parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

import pytest
from bson import ObjectId

from backend.app.services.core3_provider import (
    BaseLLMProvider,
    FakeCore3Provider,
    GeminiCore3Provider,
    SamanCustomLLMProvider,
    create_llm_provider,
    get_tier_config,
)
from backend.app.services.training_log_service import (
    hash_user_id,
    is_training_log_capture_enabled,
    record_chat_training_turn,
    scrub_pii,
    update_training_action_outcome,
)


# ---------------------------------------------------------------------------
# In-memory mock Mongo collection for training logs
# ---------------------------------------------------------------------------

class MockMongoCollection:
    def __init__(self):
        self.docs: List[Dict[str, Any]] = []

    def insert_one(self, doc: Dict[str, Any]):
        copied = dict(doc)
        if "_id" not in copied:
            copied["_id"] = ObjectId()
        self.docs.append(copied)
        return MagicMock(inserted_id=copied["_id"])

    def update_one(self, filter_query: Dict[str, Any], update_ops: Dict[str, Any], upsert: bool = False):
        matched = None
        for doc in self.docs:
            match = True
            for k, v in filter_query.items():
                if doc.get(k) != v:
                    match = False
                    break
            if match:
                matched = doc
                break

        if matched:
            if "$set" in update_ops:
                for k, v in update_ops["$set"].items():
                    matched[k] = v
            return MagicMock(matched_count=1, modified_count=1)

        if upsert:
            new_doc = {}
            if "$setOnInsert" in update_ops:
                new_doc.update(update_ops["$setOnInsert"])
            if "$set" in update_ops:
                new_doc.update(update_ops["$set"])
            for k, v in filter_query.items():
                new_doc.setdefault(k, v)
            if "_id" not in new_doc:
                new_doc["_id"] = ObjectId()
            self.docs.append(new_doc)
            return MagicMock(matched_count=0, modified_count=0, upserted_id=new_doc["_id"])

        return MagicMock(matched_count=0, modified_count=0)

    def find_one(self, filter_query: Dict[str, Any]):
        for doc in self.docs:
            match = True
            for k, v in filter_query.items():
                if doc.get(k) != v:
                    match = False
                    break
            if match:
                return dict(doc)
        return None


# ===========================================================================
# 1. TEST CRITERION 1: PROVIDER SWITCHING
# ===========================================================================

class TestProviderSwitching:
    def test_fake_provider_switching_and_response(self):
        """When CHAT_AI_PROVIDER=fake, returns FakeCore3Provider and simulated response without calling Gemini."""
        async def _run():
            with patch.dict(os.environ, {"CHAT_AI_PROVIDER": "fake"}):
                provider = create_llm_provider()
                assert isinstance(provider, FakeCore3Provider)
                assert isinstance(provider, BaseLLMProvider)
                assert provider.provider_name == "fake"
                assert provider.resolve_model_name("core3") == "saman-fake-v1"

                reply_core3 = await provider.generate("Xin chào huấn luyện viên", ai_mode="core3")
                assert reply_core3 == "[TEST/core3] Saman Coach sẵn sàng hỗ trợ."
                assert provider.last_usage is not None
                assert provider.last_usage.get("output_tokens") == 16

                reply_swift3 = await provider.generate("Hôm nay ăn gì", ai_mode="swift3")
                assert reply_swift3 == "[TEST/swift3] Saman Coach sẵn sàng hỗ trợ."

                reply_pro3 = await provider.generate("Phân tích cơ chế hypertrophy", ai_mode="pro3")
                assert reply_pro3 == "[TEST/pro3] Saman Coach sẵn sàng hỗ trợ."
        asyncio.run(_run())

    def test_custom_llm_provider_switching_and_routing(self):
        """When CHAT_AI_PROVIDER=saman_custom, routes via CUSTOM_LLM_BASE_URL following BaseLLMProvider."""
        async def _run():
            custom_base_url = "https://custom-llm.saman.internal/v1"
            custom_api_key = "saman-secret-custom-key"

            with patch.dict(os.environ, {
                "CHAT_AI_PROVIDER": "saman_custom",
                "CUSTOM_LLM_BASE_URL": custom_base_url,
                "CUSTOM_LLM_API_KEY": custom_api_key,
                "CUSTOM_LLM_CORE_MODEL": "saman-llama-3-8b-instruct",
            }):
                provider = create_llm_provider()
                assert isinstance(provider, SamanCustomLLMProvider)
                assert isinstance(provider, BaseLLMProvider)
                assert provider.provider_name == "saman_custom"
                assert provider.resolve_model_name("core3") == "saman-llama-3-8b-instruct"
                assert provider.base_url == custom_base_url

                # Mock outgoing HTTP response from custom endpoint
                simulated_response = json.dumps({
                    "id": "chatcmpl-test-123",
                    "choices": [{
                        "index": 0,
                        "message": {"role": "assistant", "content": "Dựa trên thực đơn hôm nay, bạn đã nạp đủ 140g đạm."},
                        "finish_reason": "stop"
                    }],
                    "usage": {"prompt_tokens": 128, "completion_tokens": 32, "total_tokens": 160}
                })

                with patch("backend.app.services.core3_provider._post_json_with_timeout", return_value=simulated_response) as mock_post:
                    reply = await provider.generate("Kiểm tra lượng đạm hôm nay", ai_mode="core3")
                    assert reply == "Dựa trên thực đơn hôm nay, bạn đã nạp đủ 140g đạm."
                    assert provider.last_usage == {"prompt_tokens": 128, "output_tokens": 32}

                    # Verify outgoing Request
                    assert mock_post.called
                    req = mock_post.call_args[0][0]
                    assert req.full_url == f"{custom_base_url}/chat/completions"
                    assert req.headers["Authorization"] == f"Bearer {custom_api_key}"
                    assert req.headers["Content-type"] == "application/json"

                    payload = json.loads(req.data.decode("utf-8"))
                    assert payload["model"] == "saman-llama-3-8b-instruct"
                    assert payload["messages"][0]["content"] == "Kiểm tra lượng đạm hôm nay"
                    assert payload["stream"] is False
        asyncio.run(_run())

    def test_gemini_provider_default(self):
        """Default or 'gemini' returns GeminiCore3Provider."""
        with patch.dict(os.environ, {"CHAT_AI_PROVIDER": "gemini"}):
            provider = create_llm_provider()
            assert isinstance(provider, GeminiCore3Provider)
            assert isinstance(provider, BaseLLMProvider)
            assert provider.provider_name == "gemini"


# ===========================================================================
# 2. TEST CRITERION 2: PII ANONYMIZATION IN CHAT_TRAINING_LOGS
# ===========================================================================

class TestPiiAnonymization:
    def test_scrub_pii_dictionary_keys_and_values(self):
        """Ensures email, user_email, name, phone, token, and user_id are scrubbed from dicts."""
        raw_payload = {
            "user_id": "6724a1b2c3d4e5f6a7b8c9d0",
            "email": "athlete_john@example.com",
            "user_email": "athlete_john@example.com",
            "full_name": "Nguyễn Văn John",
            "phone": "0912345678",
            "phone_number": "+84987654321",
            "password": "secret_password",
            "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.e30.abc",
            "opaque_app_user_id": "anon-uuid-1234",
            "safe_data": {
                "macros": {"protein_g": 120, "calories": 2100},
                "user_id": "inner_user_id_to_strip",
                "nested_email": "nested_user@saman.ai",
            },
            "history": [
                {"role": "user", "content": "Liên hệ tôi qua email athlete_john@example.com hoặc SĐT 0912345678."},
                {"role": "assistant", "content": "Đã ghi nhận thông tin của John với token Bearer abc.def.ghi."},
            ],
        }

        scrubbed = scrub_pii(raw_payload)

        # Sensitive keys must be completely removed from top level and nested dicts
        assert "user_id" not in scrubbed
        assert "email" not in scrubbed
        assert "user_email" not in scrubbed
        assert "full_name" not in scrubbed
        assert "phone" not in scrubbed
        assert "phone_number" not in scrubbed
        assert "password" not in scrubbed
        assert "token" not in scrubbed
        assert "opaque_app_user_id" not in scrubbed
        assert "user_id" not in scrubbed["safe_data"]

        # String redactions
        assert scrubbed["safe_data"]["macros"]["protein_g"] == 120
        assert scrubbed["safe_data"]["nested_email"] == "[REDACTED_EMAIL]"

        # Embedded regex redaction in text content
        user_msg = scrubbed["history"][0]["content"]
        assert "athlete_john@example.com" not in user_msg
        assert "[REDACTED_EMAIL]" in user_msg
        assert "0912345678" not in user_msg
        assert "[REDACTED_PHONE]" in user_msg

        asst_msg = scrubbed["history"][1]["content"]
        assert "Bearer abc.def.ghi" not in asst_msg
        assert "[REDACTED_TOKEN]" in asst_msg

    def test_hash_user_id_determinism_and_length(self):
        """User ID hashing is salted, non-reversible, deterministic, and 24 chars."""
        uid = "6724a1b2c3d4e5f6a7b8c9d0"
        hash_1 = hash_user_id(uid)
        hash_2 = hash_user_id(uid)
        assert hash_1 == hash_2
        assert len(hash_1) == 24
        assert uid not in hash_1
        assert hash_user_id("") == ""
        assert hash_user_id("   ") == ""

    def test_record_chat_training_turn_end_to_end_sanitization(self):
        """record_chat_training_turn strips PII from query, reply, context, and stores user_hash."""
        col = MockMongoCollection()
        principal = {
            "_id": ObjectId("6724a1b2c3d4e5f6a7b8c9d0"),
            "user_id": "6724a1b2c3d4e5f6a7b8c9d0",
            "email": "secret_user@saman.vn",
            "name": "Trần Huấn Luyện",
        }
        raw_context = {
            "user_email": "secret_user@saman.vn",
            "email": "secret_user@saman.vn",
            "user_id": "6724a1b2c3d4e5f6a7b8c9d0",
            "profile": {"goal": "Tăng cơ giảm mỡ", "weight_kg": 72.5},
            "today_water_ml": 1500,
        }
        user_query = "Tôi là Trần Huấn Luyện, email secret_user@saman.vn, vừa uống 500ml nước"
        assistant_reply = "Chào Trần Huấn Luyện (secret_user@saman.vn), tôi đã ghi nhận 500ml nước cho bạn."
        action = {
            "id": "act-water-456",
            "type": "log_water",
            "user_id": "6724a1b2c3d4e5f6a7b8c9d0",
            "amount_ml": 500,
        }

        success = record_chat_training_turn(
            col,
            principal=principal,
            operation_id="op-123456",
            conversation_id="conv-789",
            ai_mode="core3",
            provider_name="fake",
            model_name="saman-fake-v1",
            context=raw_context,
            history=[],
            user_query=user_query,
            assistant_reply=assistant_reply,
            action=action,
            usage={"prompt_tokens": 40, "output_tokens": 16},
        )
        assert success is True
        assert len(col.docs) == 1
        saved = col.docs[0]

        # Verification of stored document
        assert saved["operation_id"] == "op-123456"
        assert saved["user_hash"] == hash_user_id("6724a1b2c3d4e5f6a7b8c9d0")
        assert "6724a1b2c3d4e5f6a7b8c9d0" not in json.dumps(saved["structured_context_json"])
        assert "secret_user@saman.vn" not in json.dumps(saved["structured_context_json"])
        assert "secret_user@saman.vn" not in saved["user_query"]
        assert "secret_user@saman.vn" not in saved["assistant_reply"]
        assert "[REDACTED_EMAIL]" in saved["user_query"]
        assert "[REDACTED_EMAIL]" in saved["assistant_reply"]
        assert saved["user_action_taken"] is None
        assert saved["action_id"] == "act-water-456"


# ===========================================================================
# 3. TEST CRITERION 3: USER_ACTION_TAKEN OUTCOME UPDATES
# ===========================================================================

class TestUserActionTakenUpdate:
    def test_update_training_action_outcome_confirm(self):
        """Updating action with decision='confirm' sets user_action_taken='confirmed'."""
        col = MockMongoCollection()
        user_id = "6724a1b2c3d4e5f6a7b8c9d0"
        u_hash = hash_user_id(user_id)
        action_id = "act-water-999"

        col.insert_one({
            "operation_id": "op-water-999",
            "user_hash": u_hash,
            "action_id": action_id,
            "user_action_taken": None,
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc),
        })

        updated = update_training_action_outcome(
            col,
            user_id=user_id,
            action_id=action_id,
            decision="confirm",
        )
        assert updated is True

        doc = col.find_one({"user_hash": u_hash, "action_id": action_id})
        assert doc is not None
        assert doc["user_action_taken"] == "confirmed"

    def test_update_training_action_outcome_cancel(self):
        """Updating action with decision='cancel' sets user_action_taken='cancelled'."""
        col = MockMongoCollection()
        user_id = "6724a1b2c3d4e5f6a7b8c9d0"
        u_hash = hash_user_id(user_id)
        action_id = "act-workout-888"

        col.insert_one({
            "operation_id": "op-workout-888",
            "user_hash": u_hash,
            "action_id": action_id,
            "user_action_taken": None,
            "created_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc),
        })

        updated = update_training_action_outcome(
            col,
            user_id=user_id,
            action_id=action_id,
            decision="cancelled",
        )
        assert updated is True

        doc = col.find_one({"user_hash": u_hash, "action_id": action_id})
        assert doc is not None
        assert doc["user_action_taken"] == "cancelled"

    def test_invalid_decision_or_missing_user_returns_false(self):
        col = MockMongoCollection()
        assert update_training_action_outcome(col, user_id="", action_id="act", decision="confirm") is False
        assert update_training_action_outcome(col, user_id="user1", action_id="", decision="confirm") is False
        assert update_training_action_outcome(col, user_id="user1", action_id="act", decision="unknown_action") is False
