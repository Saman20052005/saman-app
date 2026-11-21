"""Fail-safe, PII-scrubbed capture of Core 3 chat training turns."""

import hashlib
import logging
import os
import re
from datetime import datetime, timezone
from typing import Any, Optional


logger = logging.getLogger(__name__)

_SENSITIVE_KEYS = {
    "email",
    "user_email",
    "full_name",
    "phone",
    "phone_number",
    "password",
    "password_hash",
    "token",
    "jwt",
    "authorization",
    "opaque_app_user_id",
    "user_id",
}
_EMAIL_RE = re.compile(r"[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+")
_BEARER_TOKEN_RE = re.compile(
    r"Bearer\s+[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+",
    re.IGNORECASE,
)
_PHONE_RE = re.compile(r"(?<!\d)(?:\+?84|0)(?:[\s.-]?\d){8,10}(?!\d)")


def is_training_log_capture_enabled() -> bool:
    value = os.getenv("ENABLE_TRAINING_LOG_CAPTURE", "true")
    return value.strip().lower() in {"1", "true", "yes", "on"}


def hash_user_id(user_id: str) -> str:
    normalized_user_id = str(user_id).strip()
    if not normalized_user_id:
        return ""
    salt = os.getenv("TRAINING_LOG_SALT", "saman-training-v1")
    digest = hashlib.sha256(
        f"{salt}:{normalized_user_id}".encode("utf-8")
    ).hexdigest()
    return digest[:24]


def scrub_pii(value: Any) -> Any:
    """Recursively remove identifier fields and redact PII embedded in text."""
    if isinstance(value, dict):
        scrubbed = {}
        for key, item in value.items():
            key_text = str(key)
            if key_text.lower() in _SENSITIVE_KEYS:
                continue
            scrubbed[key_text] = scrub_pii(item)
        return scrubbed
    if isinstance(value, list):
        return [scrub_pii(item) for item in value]
    if isinstance(value, str):
        value = _EMAIL_RE.sub("[REDACTED_EMAIL]", value)
        value = _BEARER_TOKEN_RE.sub("[REDACTED_TOKEN]", value)
        return _PHONE_RE.sub("[REDACTED_PHONE]", value)
    if value is None or isinstance(value, (bool, int, float)):
        return value
    if isinstance(value, datetime):
        return value.isoformat()
    # Covers BSON ObjectId and other non-JSON-serializable values.
    return str(value)


def record_chat_training_turn(
    collection,
    *,
    principal: dict,
    operation_id: str,
    conversation_id: Any,
    ai_mode: str,
    provider_name: str,
    model_name: str,
    context: Any,
    history: Any,
    user_query: str,
    assistant_reply: str,
    action: Optional[dict] = None,
    usage: Optional[dict] = None,
) -> bool:
    try:
        if (
            collection is None
            or not is_training_log_capture_enabled()
            or not operation_id
        ):
            return False

        raw_uid = str(
            (principal or {}).get("_id")
            or (principal or {}).get("user_id")
            or ""
        )
        user_hash = hash_user_id(raw_uid)
        if not user_hash:
            return False

        bounded_history = []
        if isinstance(history, list):
            for turn in history[-10:]:
                if isinstance(turn, dict):
                    bounded_history.append(
                        {
                            "role": scrub_pii(turn.get("role")),
                            "content": scrub_pii(turn.get("content")),
                        }
                    )

        now_utc = datetime.now(timezone.utc)
        document = {
            "operation_id": operation_id,
            "user_hash": user_hash,
            "conversation_hash": hash_user_id(str(conversation_id)),
            "schema_version": 1,
            "model_tier": ai_mode,
            "provider_name": provider_name,
            "model_name": model_name,
            "structured_context_json": scrub_pii(context or {}),
            "history_turns": bounded_history,
            "user_query": scrub_pii(user_query),
            "assistant_reply": scrub_pii(assistant_reply),
            "pending_action_type": (
                scrub_pii(action.get("type")) if isinstance(action, dict) else None
            ),
            "action_id": (
                str(action.get("id"))
                if isinstance(action, dict) and action.get("id")
                else None
            ),
            "user_action_taken": None,
            "usage": scrub_pii(usage) if isinstance(usage, dict) else None,
            "created_at": now_utc,
            "updated_at": now_utc,
        }
        collection.update_one(
            {"user_hash": user_hash, "operation_id": operation_id},
            {"$setOnInsert": document},
            upsert=True,
        )
        return True
    except Exception as exc:
        logger.warning("Training log capture failed (%s)", type(exc).__name__)
        return False


def update_training_action_outcome(
    collection,
    *,
    user_id: str,
    action_id: str,
    decision: str,
) -> bool:
    try:
        if collection is None or not user_id or not action_id:
            return False
        if decision not in ("confirmed", "cancelled", "confirm", "cancel"):
            return False

        normalized_decision = {
            "confirm": "confirmed",
            "cancel": "cancelled",
        }.get(decision, decision)
        user_hash = hash_user_id(user_id)
        if not user_hash:
            return False

        result = collection.update_one(
            {"user_hash": user_hash, "action_id": str(action_id)},
            {
                "$set": {
                    "user_action_taken": normalized_decision,
                    "updated_at": datetime.now(timezone.utc),
                }
            },
        )
        return bool(getattr(result, "matched_count", 0))
    except Exception as exc:
        logger.warning("Training action outcome update failed (%s)", type(exc).__name__)
        return False
