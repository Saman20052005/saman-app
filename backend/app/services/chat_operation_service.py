"""Idempotent persistence boundary for advisory Core 3 chat turns."""

import hashlib
import asyncio
import json
import re
import secrets
import time
from datetime import datetime, timedelta, timezone

from bson import ObjectId
from fastapi import HTTPException

try:
    from backend.app.services.core3_context import build_core3_context
    from backend.app.services.core3_provider import Core3PromptTooLarge, GeminiCore3Provider, render_prompt
except ImportError:
    from app.services.core3_context import build_core3_context
    from app.services.core3_provider import Core3PromptTooLarge, GeminiCore3Provider, render_prompt


def _utcnow():
    return datetime.now(timezone.utc)


def _as_utc(value):
    """PyMongo decodes BSON datetimes as naive UTC by default."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


class ChatOperationService:
    def __init__(self, *, db, conversations, nutrition, workouts, users, provider=None, context_builder=build_core3_context):
        self.operations = db["chat_operations"]
        self.conversations = conversations
        self.nutrition = nutrition
        self.workouts = workouts
        self.users = users
        self.provider = provider or GeminiCore3Provider()
        self.context_builder = context_builder

    async def handle(self, *, principal, operation_id, contract_version, message, conversation_id=None, history=None):
        principal_id = str(principal.get("_id") or "")
        if not principal_id or not re.fullmatch(r"[0-9a-f]{32}", str(operation_id or "")) or contract_version != "core3-local-v1":
            raise HTTPException(status_code=422, detail="Invalid Core 3 operation")
        target = str(conversation_id) if conversation_id else "NEW"
        fingerprint = hashlib.sha256(json.dumps(
            {"message": message, "target": target, "history": history or []},
            sort_keys=True, ensure_ascii=False,
        ).encode()).hexdigest()
        now = _utcnow()
        candidate = ObjectId() if target == "NEW" else ObjectId(target)
        lease_token = secrets.token_hex(16)
        key = {"user_id": principal_id, "operation_id": operation_id}
        try:
            self.operations.insert_one({**key, "contract_version": contract_version, "payload_fingerprint": fingerprint,
                "requested_target": target, "resolved_conversation_id": candidate, "state": "prepared",
                "claim_token": lease_token, "lease_until": now + timedelta(seconds=30), "created_at": now})
            claimed = True
        except Exception:
            claimed = False
        op = self.operations.find_one(key)
        if op is None:
            raise HTTPException(status_code=503, detail="Chat operation storage unavailable")
        if op.get("payload_fingerprint") != fingerprint or op.get("requested_target") != target:
            raise HTTPException(status_code=409, detail="Operation id was already used for another request")
        resolved_id = op["resolved_conversation_id"]
        if not claimed and op.get("state") in ("prepared", "dispatched", "result_saved") and not (
            op.get("state") == "prepared" and op.get("lease_until") and _as_utc(op["lease_until"]) <= now
        ):
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline and op.get("state") in ("prepared", "dispatched"):
                await asyncio.sleep(0.05)
                op = self.operations.find_one(key)
            resolved_id = op["resolved_conversation_id"]
        if not claimed and op.get("state") == "prepared" and op.get("lease_until") and _as_utc(op["lease_until"]) <= now:
            lease_token = secrets.token_hex(16)
            result = self.operations.update_one({**key, "state": "prepared", "lease_until": {"$lte": now}},
                {"$set": {"claim_token": lease_token, "lease_until": now + timedelta(seconds=30)}})
            claimed = result.modified_count == 1
            op = self.operations.find_one(key)
            resolved_id = op["resolved_conversation_id"]
        if op.get("state") == "completed":
            return self._response(op)
        if op.get("state") in ("dispatched", "unknown"):
            raise HTTPException(status_code=409, detail={"status": "unknown", "operation_id": operation_id})
        if op.get("state") == "result_saved":
            return self._append_and_complete(op, principal_id, message)
        if not claimed:
            raise HTTPException(status_code=409, detail={"status": "in_progress", "operation_id": operation_id})

        if target != "NEW":
            owned = self.conversations.find_one({"_id": resolved_id, "user_id": principal_id}, {"_id": 1})
            if not owned:
                raise HTTPException(status_code=404, detail="Conversation not found")
        else:
            self.conversations.update_one({"_id": resolved_id, "user_id": principal_id}, {"$setOnInsert": {
                "user_id": principal_id, "user_email": str(principal.get("email") or ""), "title": message[:40],
                "messages": [], "created_at": now, "updated_at": now}}, upsert=True)

        context = self.context_builder(principal=principal, nutrition_collection=self.nutrition,
            workout_collection=self.workouts, users_collection=self.users)
        try:
            prompt = render_prompt(message, history, context)
        except Core3PromptTooLarge as exc:
            raise HTTPException(status_code=413, detail=str(exc))
        dispatch = self.operations.update_one({**key, "state": "prepared", "claim_token": lease_token},
            {"$set": {"state": "dispatched", "dispatched_at": _utcnow()}})
        if dispatch.modified_count != 1:
            raise HTTPException(status_code=409, detail={"status": "in_progress", "operation_id": operation_id})
        try:
            response = await self.provider.generate(prompt)
        except Exception:
            self.operations.update_one({**key, "state": "dispatched"}, {"$set": {"state": "unknown"}})
            raise HTTPException(status_code=504, detail={"status": "unknown", "operation_id": operation_id})
        response = str(response)
        result_hash = hashlib.sha256(response.encode()).hexdigest()
        self.operations.update_one({**key, "state": "dispatched", "claim_token": lease_token}, {"$set": {
            "state": "result_saved", "canonical_response": response, "result_hash": result_hash, "result_saved_at": _utcnow()}})
        op = self.operations.find_one(key)
        return self._append_and_complete(op, principal_id, message)

    def _append_and_complete(self, op, principal_id, message):
        op_id = op["operation_id"]
        conversation_id = op["resolved_conversation_id"]
        timestamp = _utcnow().isoformat()
        user_turn = {"role": "user", "content": message, "operation_id": op_id, "created_at": timestamp}
        assistant_turn = {"role": "assistant", "content": op["canonical_response"], "operation_id": op_id, "created_at": timestamp}
        self.conversations.update_one({"_id": conversation_id, "user_id": principal_id,
            "messages.operation_id": {"$ne": op_id}}, {"$push": {"messages": {"$each": [user_turn, assistant_turn]}},
                "$set": {"updated_at": timestamp}})
        stored = self.conversations.find_one({"_id": conversation_id, "user_id": principal_id}, {"messages": 1})
        turns = [m for m in (stored or {}).get("messages", []) if m.get("operation_id") == op_id]
        if len(turns) != 2 or hashlib.sha256(str(turns[-1].get("content", "")).encode()).hexdigest() != op["result_hash"]:
            raise HTTPException(status_code=503, detail="Chat result persistence is pending recovery")
        self.operations.update_one({"user_id": principal_id, "operation_id": op_id,
            "state": {"$in": ["result_saved", "completed"]}}, {"$set": {"state": "completed", "completed_at": _utcnow()}})
        return self._response(op)

    @staticmethod
    def _response(op):
        return {"reply": op["canonical_response"], "status": "success",
                "conversation_id": str(op["resolved_conversation_id"]), "action": None}
