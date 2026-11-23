"""Idempotent persistence boundary for advisory Core 3 chat turns."""

import asyncio
import hashlib
import inspect
import json
import re
import secrets
import time
from datetime import datetime, timedelta, timezone

from bson import ObjectId
from fastapi import HTTPException

try:
    from backend.app.services.core3_context import build_core3_context
    from backend.app.services.core3_provider import (
        Core3PromptTooLarge,
        GeminiCore3Provider,
        create_llm_provider,
        get_tier_config,
        render_prompt,
    )
except ImportError:
    from app.services.core3_context import build_core3_context
    from app.services.core3_provider import (
        Core3PromptTooLarge,
        GeminiCore3Provider,
        create_llm_provider,
        get_tier_config,
        render_prompt,
    )

try:
    from backend.app.services.training_log_service import record_chat_training_turn
except ImportError:
    try:
        from app.services.training_log_service import record_chat_training_turn
    except ImportError:
        record_chat_training_turn = None

VALID_AI_MODES = ("swift3", "core3", "pro3")


def _utcnow():
    return datetime.now(timezone.utc)


def _as_utc(value):
    """PyMongo decodes BSON datetimes as naive UTC by default."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _normalize_ai_mode(ai_mode) -> str:
    mode = str(ai_mode or "core3").strip().lower()
    if mode not in VALID_AI_MODES:
        raise HTTPException(status_code=422, detail="Invalid AI mode")
    return mode


class ChatOperationService:
    def __init__(
        self,
        *,
        db,
        conversations,
        nutrition,
        workouts,
        users,
        provider=None,
        context_builder=build_core3_context,
        water=None,
        weight_history=None,
        action_detector=None,
        shop_products=None,
        journal_articles=None,
        training_logs=None,
        journeys=None,
        story_logs=None,
        community_posts=None,
        community_interactions=None,
        community_follows=None,
        supplements=None,
        recipes=None,
    ):
        self.operations = db["chat_operations"]
        self.conversations = conversations
        self.nutrition = nutrition
        self.workouts = workouts
        self.users = users
        self.water = water
        self.weight_history = weight_history
        self.action_detector = action_detector
        self.shop_products = shop_products
        self.journal_articles = journal_articles
        self.training_logs = training_logs
        self.journeys = journeys
        self.story_logs = story_logs
        self.community_posts = community_posts
        self.community_interactions = community_interactions
        self.community_follows = community_follows
        self.supplements = supplements
        self.recipes = recipes
        self.provider = provider or create_llm_provider()
        self.context_builder = context_builder

    def _record_training_turn(
        self,
        *,
        principal,
        operation_id,
        conversation_id,
        mode,
        context,
        history,
        message,
        response,
        action,
    ):
        if self.training_logs is None or not callable(record_chat_training_turn):
            return
        try:
            provider_name = str(getattr(self.provider, "provider_name", type(self.provider).__name__))
            resolve_fn = getattr(self.provider, "resolve_model_name", None)
            if callable(resolve_fn):
                model_name = str(resolve_fn(mode))
            else:
                model_name = str(get_tier_config(mode).get("model", "unknown"))
            usage = getattr(self.provider, "last_usage", None)
            record_chat_training_turn(
                self.training_logs,
                principal=principal,
                operation_id=operation_id,
                conversation_id=conversation_id,
                ai_mode=mode,
                provider_name=provider_name,
                model_name=model_name,
                context=context,
                history=history,
                user_query=message,
                assistant_reply=response,
                action=action,
                usage=usage,
            )
        except Exception:
            pass

    def _build_context(self, principal, mode: str, question: str | None = None):
        base_kwargs = {
            "principal": principal,
            "nutrition_collection": self.nutrition,
            "workout_collection": self.workouts,
            "users_collection": self.users,
        }
        extra_kwargs = {
            "water_collection": self.water,
            "weight_history_collection": self.weight_history,
            "shop_products_collection": self.shop_products,
            "journal_articles_collection": self.journal_articles,
            "question": question,
            "tier": mode,
        }
        for k, v in (
            ("journeys_collection", self.journeys),
            ("story_logs_collection", self.story_logs),
            ("community_posts_collection", self.community_posts),
            ("community_interactions_collection", self.community_interactions),
            ("community_follows_collection", self.community_follows),
            ("supplements_collection", self.supplements),
            ("recipes_collection", self.recipes),
        ):
            if v is not None:
                extra_kwargs[k] = v
        try:
            sig = inspect.signature(self.context_builder)
            has_var_kw = any(
                p.kind == inspect.Parameter.VAR_KEYWORD
                for p in sig.parameters.values()
            )
            if has_var_kw:
                return self.context_builder(**base_kwargs, **extra_kwargs)
            call_kwargs = dict(base_kwargs)
            for k, v in extra_kwargs.items():
                if k in sig.parameters:
                    call_kwargs[k] = v
            return self.context_builder(**call_kwargs)
        except (TypeError, ValueError):
            return self.context_builder(**base_kwargs)

    @staticmethod
    def _render_prompt(message, history, context, mode: str):
        try:
            sig = inspect.signature(render_prompt)
            if "ai_mode" in sig.parameters or any(
                p.kind == inspect.Parameter.VAR_KEYWORD
                for p in sig.parameters.values()
            ):
                return render_prompt(message, history, context, ai_mode=mode)
        except (TypeError, ValueError):
            pass
        return render_prompt(message, history, context)

    async def _detect_action(self, *, principal, message, conversation_id, request_obj):
        if not callable(self.action_detector):
            return None
        try:
            detected = self.action_detector(
                principal=principal,
                message=message,
                conversation_id=conversation_id,
                request_obj=request_obj,
            )
            if inspect.isawaitable(detected):
                detected = await detected
            return detected
        except Exception:
            return None

    async def _generate(self, prompt: str, mode: str):
        try:
            sig = inspect.signature(self.provider.generate)
            accepts_ai_mode = "ai_mode" in sig.parameters or any(
                p.kind == inspect.Parameter.VAR_KEYWORD
                for p in sig.parameters.values()
            )
        except (TypeError, ValueError):
            accepts_ai_mode = True
        if accepts_ai_mode:
            try:
                return await self.provider.generate(prompt, ai_mode=mode)
            except TypeError:
                return await self.provider.generate(prompt)
        return await self.provider.generate(prompt)

    async def _iter_provider_stream(self, prompt: str, mode: str):
        if not hasattr(self.provider, "generate_stream"):
            text = await self._generate(prompt, mode)
            if text:
                yield str(text)
            return
        stream_fn = self.provider.generate_stream
        try:
            sig = inspect.signature(stream_fn)
            accepts_ai_mode = "ai_mode" in sig.parameters or any(
                p.kind == inspect.Parameter.VAR_KEYWORD
                for p in sig.parameters.values()
            )
        except (TypeError, ValueError):
            accepts_ai_mode = True
        if accepts_ai_mode:
            try:
                stream = stream_fn(prompt, ai_mode=mode)
            except TypeError:
                stream = stream_fn(prompt)
        else:
            stream = stream_fn(prompt)
        if inspect.isawaitable(stream):
            stream = await stream
        if hasattr(stream, "__aiter__"):
            async for chunk in stream:
                if chunk:
                    yield str(chunk)
        else:
            for chunk in stream:
                if chunk:
                    yield str(chunk)

    @staticmethod
    def _fingerprints(message, target: str, history, mode: str):
        fingerprint = hashlib.sha256(json.dumps(
            {"message": message, "target": target, "history": history or [], "ai_mode": mode},
            sort_keys=True, ensure_ascii=False,
        ).encode()).hexdigest()
        valid = {fingerprint}
        if mode == "core3":
            legacy = hashlib.sha256(json.dumps(
                {"message": message, "target": target, "history": history or []},
                sort_keys=True, ensure_ascii=False,
            ).encode()).hexdigest()
            valid.add(legacy)
        return fingerprint, valid

    async def handle(
        self,
        *,
        principal,
        operation_id,
        contract_version,
        message,
        conversation_id=None,
        history=None,
        ai_mode: str = "core3",
        request_obj=None,
    ):
        principal_id = str(principal.get("_id") or "")
        if not principal_id or not re.fullmatch(r"[0-9a-f]{32}", str(operation_id or "")) or contract_version != "core3-local-v1":
            raise HTTPException(status_code=422, detail="Invalid Core 3 operation")
        mode = _normalize_ai_mode(ai_mode)
        target = str(conversation_id) if conversation_id else "NEW"
        fingerprint, valid_fingerprints = self._fingerprints(message, target, history, mode)
        now = _utcnow()
        candidate = ObjectId() if target == "NEW" else ObjectId(target)
        lease_token = secrets.token_hex(16)
        key = {"user_id": principal_id, "operation_id": operation_id}
        try:
            self.operations.insert_one({
                **key,
                "contract_version": contract_version,
                "payload_fingerprint": fingerprint,
                "requested_target": target,
                "resolved_conversation_id": candidate,
                "ai_mode": mode,
                "state": "prepared",
                "claim_token": lease_token,
                "lease_until": now + timedelta(seconds=30),
                "created_at": now,
            })
            claimed = True
        except Exception:
            claimed = False
        op = self.operations.find_one(key)
        if op is None:
            raise HTTPException(status_code=503, detail="Chat operation storage unavailable")
        if op.get("payload_fingerprint") not in valid_fingerprints or op.get("requested_target") != target:
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
                {"$set": {"claim_token": lease_token, "lease_until": now + timedelta(seconds=30), "ai_mode": mode}})
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

        context = self._build_context(principal, mode, question=message)
        try:
            prompt = self._render_prompt(message, history, context, mode)
        except Core3PromptTooLarge as exc:
            raise HTTPException(status_code=413, detail=str(exc))
        pending_action = await self._detect_action(
            principal=principal,
            message=message,
            conversation_id=resolved_id,
            request_obj=request_obj,
        )
        dispatch = self.operations.update_one({**key, "state": "prepared", "claim_token": lease_token},
            {"$set": {"state": "dispatched", "dispatched_at": _utcnow(), "ai_mode": mode}})
        if dispatch.modified_count != 1:
            raise HTTPException(status_code=409, detail={"status": "in_progress", "operation_id": operation_id})
        try:
            response = await self._generate(prompt, mode)
        except Exception:
            self.operations.update_one({**key, "state": "dispatched"}, {"$set": {"state": "unknown"}})
            raise HTTPException(status_code=504, detail={"status": "unknown", "operation_id": operation_id})
        response = str(response)
        result_hash = hashlib.sha256(response.encode()).hexdigest()
        self.operations.update_one({**key, "state": "dispatched", "claim_token": lease_token}, {"$set": {
            "state": "result_saved",
            "canonical_response": response,
            "canonical_action": pending_action,
            "ai_mode": mode,
            "result_hash": result_hash,
            "result_saved_at": _utcnow(),
        }})
        op = self.operations.find_one(key)
        result = self._append_and_complete(op, principal_id, message)
        self._record_training_turn(
            principal=principal,
            operation_id=operation_id,
            conversation_id=resolved_id,
            mode=mode,
            context=context,
            history=history,
            message=message,
            response=response,
            action=pending_action,
        )
        return result

    async def handle_stream(
        self,
        *,
        principal,
        operation_id,
        contract_version,
        message,
        conversation_id=None,
        history=None,
        ai_mode="core3",
        request_obj=None,
    ):
        principal_id = str(principal.get("_id") or "")
        if not principal_id or not re.fullmatch(r"[0-9a-f]{32}", str(operation_id or "")) or contract_version != "core3-local-v1":
            raise HTTPException(status_code=422, detail="Invalid Core 3 operation")
        mode = _normalize_ai_mode(ai_mode)
        target = str(conversation_id) if conversation_id else "NEW"
        fingerprint, valid_fingerprints = self._fingerprints(message, target, history, mode)
        now = _utcnow()
        candidate = ObjectId() if target == "NEW" else ObjectId(target)
        lease_token = secrets.token_hex(16)
        key = {"user_id": principal_id, "operation_id": operation_id}
        try:
            self.operations.insert_one({
                **key,
                "contract_version": contract_version,
                "payload_fingerprint": fingerprint,
                "requested_target": target,
                "resolved_conversation_id": candidate,
                "ai_mode": mode,
                "state": "prepared",
                "claim_token": lease_token,
                "lease_until": now + timedelta(seconds=30),
                "created_at": now,
            })
            claimed = True
        except Exception:
            claimed = False
        op = self.operations.find_one(key)
        if op is None:
            raise HTTPException(status_code=503, detail="Chat operation storage unavailable")
        if op.get("payload_fingerprint") not in valid_fingerprints or op.get("requested_target") != target:
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
                {"$set": {"claim_token": lease_token, "lease_until": now + timedelta(seconds=30), "ai_mode": mode}})
            claimed = result.modified_count == 1
            op = self.operations.find_one(key)
            resolved_id = op["resolved_conversation_id"]
        if op.get("state") == "result_saved":
            self._append_and_complete(op, principal_id, message)
            op = self.operations.find_one(key)
        if op.get("state") == "completed":
            op_mode = op.get("ai_mode", mode)
            saved_action = op.get("canonical_action")
            yield {"event": "meta", "data": {"conversation_id": str(resolved_id), "ai_mode": op_mode, "operation_id": operation_id}}
            yield {"event": "delta", "data": {"text": str(op.get("canonical_response") or "")}}
            if saved_action is not None:
                yield {"event": "action", "data": saved_action}
            yield {"event": "done", "data": {"conversation_id": str(resolved_id), "ai_mode": op_mode, "action": saved_action}}
            return
        if op.get("state") in ("dispatched", "unknown"):
            raise HTTPException(status_code=409, detail={"status": "unknown", "operation_id": operation_id})
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

        context = self._build_context(principal, mode, question=message)
        try:
            prompt = self._render_prompt(message, history, context, mode)
        except Core3PromptTooLarge as exc:
            raise HTTPException(status_code=413, detail=str(exc))
        pending_action = await self._detect_action(
            principal=principal,
            message=message,
            conversation_id=resolved_id,
            request_obj=request_obj,
        )
        dispatch = self.operations.update_one({**key, "state": "prepared", "claim_token": lease_token},
            {"$set": {"state": "dispatched", "dispatched_at": _utcnow(), "ai_mode": mode}})
        if dispatch.modified_count != 1:
            raise HTTPException(status_code=409, detail={"status": "in_progress", "operation_id": operation_id})

        yield {"event": "meta", "data": {"conversation_id": str(resolved_id), "ai_mode": mode, "operation_id": operation_id}}
        chunks = []
        try:
            async for chunk in self._iter_provider_stream(prompt, mode):
                chunks.append(chunk)
                yield {"event": "delta", "data": {"text": chunk}}
        except Exception:
            self.operations.update_one({**key, "state": "dispatched"}, {"$set": {"state": "unknown"}})
            raise HTTPException(status_code=504, detail={"status": "unknown", "operation_id": operation_id})

        response = "".join(chunks)
        result_hash = hashlib.sha256(response.encode()).hexdigest()
        self.operations.update_one({**key, "state": "dispatched", "claim_token": lease_token}, {"$set": {
            "state": "result_saved",
            "canonical_response": response,
            "canonical_action": pending_action,
            "ai_mode": mode,
            "result_hash": result_hash,
            "result_saved_at": _utcnow(),
        }})
        op = self.operations.find_one(key)
        self._append_and_complete(op, principal_id, message)
        self._record_training_turn(
            principal=principal,
            operation_id=operation_id,
            conversation_id=resolved_id,
            mode=mode,
            context=context,
            history=history,
            message=message,
            response=response,
            action=pending_action,
        )
        if pending_action is not None:
            yield {"event": "action", "data": pending_action}
        yield {"event": "done", "data": {"conversation_id": str(resolved_id), "ai_mode": mode, "action": pending_action}}

    def _append_and_complete(self, op, principal_id, message):
        op_id = op["operation_id"]
        conversation_id = op["resolved_conversation_id"]
        timestamp = _utcnow().isoformat()
        user_turn = {"role": "user", "content": message, "operation_id": op_id, "created_at": timestamp}
        assistant_turn = {"role": "assistant", "content": op["canonical_response"], "operation_id": op_id, "created_at": timestamp}
        set_fields = {"updated_at": timestamp}
        pending_action = op.get("canonical_action")
        if pending_action is not None:
            set_fields["pending_action"] = pending_action
        self.conversations.update_one({"_id": conversation_id, "user_id": principal_id,
            "messages.operation_id": {"$ne": op_id}}, {"$push": {"messages": {"$each": [user_turn, assistant_turn]}},
                "$set": set_fields})
        stored = self.conversations.find_one({"_id": conversation_id, "user_id": principal_id}, {"messages": 1})
        turns = [m for m in (stored or {}).get("messages", []) if m.get("operation_id") == op_id]
        if len(turns) != 2 or hashlib.sha256(str(turns[-1].get("content", "")).encode()).hexdigest() != op["result_hash"]:
            raise HTTPException(status_code=503, detail="Chat result persistence is pending recovery")
        self.operations.update_one({"user_id": principal_id, "operation_id": op_id,
            "state": {"$in": ["result_saved", "completed"]}}, {"$set": {"state": "completed", "completed_at": _utcnow()}})
        return self._response(op)

    @staticmethod
    def _response(op):
        return {
            "reply": op["canonical_response"],
            "status": "success",
            "conversation_id": str(op["resolved_conversation_id"]),
            "action": op.get("canonical_action"),
            "ai_mode": op.get("ai_mode", "core3"),
        }
