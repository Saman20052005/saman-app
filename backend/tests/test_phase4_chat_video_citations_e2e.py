"""Phase 4 E2E integration tests: Intent Router -> Core3 Context -> Video Citations -> Provider Smart Routing -> SSE + DB Persistence."""

from copy import deepcopy
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import secrets
import sys
from typing import Any, Dict, List, Optional

_repo_root = str(Path(__file__).parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

import pytest
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

import backend.app.database as db_module
import backend.routers.chat as chat_module
import backend.app.services.chat_operation_service as chat_op_module


# ---------------------------------------------------------------------------
# Lightweight in-memory MongoDB mock (100% offline, no external DB)
# ---------------------------------------------------------------------------

def _field_value(document: Any, field: str) -> Any:
    if not isinstance(document, dict):
        return None
    val: Any = document
    for part in field.split("."):
        if isinstance(val, dict):
            val = val.get(part)
        else:
            return None
    return val


def _set_field(document: dict, field: str, value: Any) -> None:
    parts = field.split(".")
    target = document
    for part in parts[:-1]:
        if part not in target or not isinstance(target[part], dict):
            target[part] = {}
        target = target[part]
    target[parts[-1]] = value


def _matches(doc: dict, query: dict) -> bool:
    if not isinstance(query, dict):
        return doc == query
    for field, expected in query.items():
        if field == "$and":
            if not all(_matches(doc, clause) for clause in expected):
                return False
        elif field == "$or":
            if not any(_matches(doc, clause) for clause in expected):
                return False
        elif field == "messages.operation_id":
            msgs = doc.get("messages") or []
            op_ids = [m.get("operation_id") for m in msgs if isinstance(m, dict)]
            if isinstance(expected, dict) and "$ne" in expected:
                if expected["$ne"] in op_ids:
                    return False
            elif expected not in op_ids:
                return False
        else:
            actual = _field_value(doc, field)
            if isinstance(expected, dict):
                for op, operand in expected.items():
                    if op == "$ne" and actual == operand:
                        return False
                    elif op == "$in" and actual not in operand:
                        return False
                    elif op == "$gte" and (actual is None or actual < operand):
                        return False
                    elif op == "$lte" and (actual is None or actual > operand):
                        return False
                    elif op == "$lt" and (actual is None or actual >= operand):
                        return False
            else:
                if actual != expected:
                    return False
    return True


class _FakeCursor(list):
    def sort(self, key_or_list, direction=None):
        items = list(self)
        if isinstance(key_or_list, list) and key_or_list:
            field, order = key_or_list[0]
            items.sort(key=lambda d: str(d.get(field) or ""), reverse=(order == -1))
        elif isinstance(key_or_list, str):
            items.sort(key=lambda d: str(d.get(key_or_list) or ""), reverse=(direction == -1))
        return _FakeCursor(items)

    def limit(self, n: int):
        return _FakeCursor(self[:n])


class _InsertResult:
    def __init__(self, inserted_id):
        self.inserted_id = inserted_id


class _UpdateResult:
    def __init__(self, matched_count: int, modified_count: int):
        self.matched_count = matched_count
        self.modified_count = modified_count


class _FakeCollection:
    def __init__(self, initial: Optional[List[dict]] = None):
        self.docs: List[dict] = [deepcopy(d) for d in (initial or [])]

    def create_index(self, *args, **kwargs):
        return "idx"

    def find(self, query=None, projection=None):
        query = query or {}
        return _FakeCursor(deepcopy(d) for d in self.docs if _matches(d, query))

    def find_one(self, query=None, projection=None):
        query = query or {}
        for d in self.docs:
            if _matches(d, query):
                return deepcopy(d)
        return None

    def insert_one(self, doc: dict):
        copy_doc = deepcopy(doc)
        if "_id" not in copy_doc:
            copy_doc["_id"] = ObjectId()
        self.docs.append(copy_doc)
        return _InsertResult(copy_doc["_id"])

    def update_one(self, query: dict, update: dict, upsert: bool = False):
        for idx, d in enumerate(self.docs):
            if _matches(d, query):
                if "$set" in update:
                    for k, v in update["$set"].items():
                        _set_field(d, k, deepcopy(v))
                if "$push" in update:
                    for k, v in update["$push"].items():
                        arr = d.setdefault(k, [])
                        if isinstance(v, dict) and "$each" in v:
                            arr.extend(deepcopy(v["$each"]))
                        else:
                            arr.append(deepcopy(v))
                self.docs[idx] = d
                return _UpdateResult(1, 1)
        if upsert:
            new_doc: dict = {}
            for k, v in query.items():
                if not k.startswith("$") and not isinstance(v, dict):
                    _set_field(new_doc, k, deepcopy(v))
            if "$setOnInsert" in update:
                for k, v in update["$setOnInsert"].items():
                    _set_field(new_doc, k, deepcopy(v))
            if "$set" in update:
                for k, v in update["$set"].items():
                    _set_field(new_doc, k, deepcopy(v))
            if "_id" not in new_doc:
                new_doc["_id"] = ObjectId()
            self.docs.append(new_doc)
            return _UpdateResult(0, 1)
        return _UpdateResult(0, 0)


class _FakeDB:
    def __init__(self, collections: Optional[Dict[str, _FakeCollection]] = None):
        self._collections: Dict[str, _FakeCollection] = dict(collections or {})

    def __getitem__(self, name: str) -> _FakeCollection:
        if name not in self._collections:
            self._collections[name] = _FakeCollection()
        return self._collections[name]


class _RecordingProvider:
    """Fake LLM provider recording smart-routing kwargs (intent, prefer_lightweight_model, cached_content_name)."""

    provider_name = "recording_fake"

    def __init__(self, reply_text: str = "Rep 7 bài Lat Pulldown hơi nhanh tại giây 19.5."):
        self.reply_text = reply_text
        self.calls: List[Dict[str, Any]] = []
        self.last_usage = {"prompt_tokens": 120, "output_tokens": 24}

    def resolve_model_name(self, ai_mode: str = "core3") -> str:
        return f"fake-{ai_mode}"

    async def generate(
        self,
        prompt: str,
        *,
        ai_mode: str = "core3",
        cached_content_name: Optional[str] = None,
        intent: Optional[str] = None,
        prefer_lightweight_model: bool = False,
    ) -> str:
        self.calls.append({
            "method": "generate",
            "prompt": prompt,
            "ai_mode": ai_mode,
            "cached_content_name": cached_content_name,
            "intent": intent,
            "prefer_lightweight_model": prefer_lightweight_model,
        })
        return self.reply_text

    async def generate_stream(
        self,
        prompt: str,
        *,
        ai_mode: str = "core3",
        cached_content_name: Optional[str] = None,
        intent: Optional[str] = None,
        prefer_lightweight_model: bool = False,
    ):
        self.calls.append({
            "method": "generate_stream",
            "prompt": prompt,
            "ai_mode": ai_mode,
            "cached_content_name": cached_content_name,
            "intent": intent,
            "prefer_lightweight_model": prefer_lightweight_model,
        })
        yield self.reply_text[:20]
        yield self.reply_text[20:]


def _parse_sse(raw_text: str) -> List[Dict[str, Any]]:
    events: List[Dict[str, Any]] = []
    current_event = "message"
    data_lines: List[str] = []
    for line in raw_text.splitlines():
        if line.startswith("event:"):
            current_event = line[6:].strip()
        elif line.startswith("data:"):
            data_lines.append(line[5:].strip())
        elif line == "":
            if data_lines:
                raw_data = "\n".join(data_lines)
                try:
                    parsed = json.loads(raw_data)
                except Exception:
                    parsed = raw_data
                events.append({"event": current_event, "data": parsed})
                current_event = "message"
                data_lines = []
    if data_lines:
        raw_data = "\n".join(data_lines)
        try:
            parsed = json.loads(raw_data)
        except Exception:
            parsed = raw_data
        events.append({"event": current_event, "data": parsed})
    return events


def _make_lat_pulldown_story(account_id: str, now_utc: datetime) -> dict:
    return {
        "_id": ObjectId(),
        "story_id": "story_lat_001",
        "account_id": account_id,
        "exercise_slug": "lat-pulldown",
        "video_url": f"https://cdn.saman.app/stories/{account_id}/lat_001.mp4",
        "created_at": now_utc - timedelta(days=1),
        "rep_timeline": [
            {
                "rep_index": 7,
                "start_sec": 19.5,
                "end_sec": 22.1,
                "is_valid": False,
                "issue_type": "tooFast",
                "metric_angle_deg": 62.4,
                "visibility_confidence": 0.985,
            },
            {
                "rep_index": 8,
                "start_sec": 22.5,
                "end_sec": 25.0,
                "is_valid": False,
                "issue_type": "shallowDepth",
                "metric_angle_deg": 95.0,
                "visibility_confidence": 0.40,
            },
        ],
    }


def _setup_test_app(
    monkeypatch,
    *,
    current_user: dict,
    video_stories: Optional[List[dict]] = None,
    provider: Optional[_RecordingProvider] = None,
):
    conversations_col = _FakeCollection()
    nutrition_col = _FakeCollection()
    workout_col = _FakeCollection()
    users_col = _FakeCollection([current_user])
    water_col = _FakeCollection()
    video_stories_col = _FakeCollection(video_stories or [])

    fake_db = _FakeDB({
        "conversations": conversations_col,
        "nutrition_plans": nutrition_col,
        "workout_history": workout_col,
        "users": users_col,
        "water_logs": water_col,
        "workout_video_stories": video_stories_col,
        "chat_operations": _FakeCollection(),
        "revenue_subscriptions": _FakeCollection(),
        "revenue_entitlement_grants": _FakeCollection(),
    })

    rec_provider = provider or _RecordingProvider()

    monkeypatch.setattr(chat_module, "conversations_col", conversations_col)
    monkeypatch.setattr(chat_module, "nutrition_col", nutrition_col)
    monkeypatch.setattr(chat_module, "workout_history_col", workout_col)
    monkeypatch.setattr(chat_module, "workout_history_collection", workout_col)
    monkeypatch.setattr(chat_module, "users_col", users_col)
    monkeypatch.setattr(chat_module, "water_col", water_col)
    monkeypatch.setattr(chat_module, "is_ai_paywall_enabled", lambda: False)

    monkeypatch.setattr(db_module, "db", fake_db)
    monkeypatch.setattr(db_module, "workout_video_stories_collection", video_stories_col)
    monkeypatch.setattr(chat_module._db_mod, "db", fake_db)
    monkeypatch.setattr(chat_module._db_mod, "workout_video_stories_collection", video_stories_col)
    monkeypatch.setattr(chat_op_module, "create_llm_provider", lambda *a, **kw: rec_provider)
    monkeypatch.setenv("CHAT_AI_PROVIDER", "fake")

    app = FastAPI()
    app.include_router(chat_module.router)
    app.dependency_overrides[chat_module.get_current_user] = lambda: current_user
    app.dependency_overrides[chat_module.get_current_chat_user] = lambda: current_user

    return TestClient(app), rec_provider, conversations_col


def test_stream_ultra_emits_verified_video_citations_and_persists_to_conversation(monkeypatch):
    now_utc = datetime.now(timezone.utc)
    user_a = {
        "_id": ObjectId(),
        "account_id": "acc_ultra_a",
        "email": "ultra_a@saman.test",
        "membership_tier": "ultra",
    }
    story = _make_lat_pulldown_story("acc_ultra_a", now_utc)
    client, provider, _ = _setup_test_app(monkeypatch, current_user=user_a, video_stories=[story])

    resp = client.post(
        "/api/chat/stream",
        json={
            "message": "Phân tích điểm yếu buổi Lat Pulldown gần nhất và lý do",
            "ai_mode": "pro3",
            "contract_version": "core3-local-v1",
            "operation_id": secrets.token_hex(16),
        },
    )
    assert resp.status_code == 200
    events = _parse_sse(resp.text)
    event_names = [e["event"] for e in events]
    assert "meta" in event_names
    assert "delta" in event_names
    assert "citations" in event_names
    assert "done" in event_names

    citations_event = next(e for e in events if e["event"] == "citations")
    citations = citations_event["data"]["video_citations"]
    assert len(citations) == 1
    c = citations[0]
    assert c["label"] == "Xem Lat Pulldown — Rep 7 (0:19)"
    assert c["seek_sec"] == 19.5
    assert c["video_story_id"] == "story_lat_001"
    assert c["video_url"] == "https://cdn.saman.app/stories/acc_ultra_a/lat_001.mp4"
    assert c["exercise_slug"] == "lat-pulldown"
    assert c["rep_index"] == 7
    assert c["issue_type"] == "tooFast"

    done_event = next(e for e in events if e["event"] == "done")
    assert done_event["data"]["video_citations"] == citations
    conv_id = done_event["data"]["conversation_id"]
    assert conv_id

    # Verify GET /api/chat/conversations/{id} returns persisted video_citations
    conv_resp = client.get(f"/api/chat/conversations/{conv_id}")
    assert conv_resp.status_code == 200
    conv_data = conv_resp.json()
    assistant_msgs = [m for m in conv_data["messages"] if m["role"] == "assistant"]
    assert len(assistant_msgs) == 1
    assert assistant_msgs[0]["video_citations"] == citations

    # Verify provider received full_audit intent (non-lightweight)
    assert len(provider.calls) == 1
    assert provider.calls[0]["intent"] == "full_audit"
    assert provider.calls[0]["prefer_lightweight_model"] is False


def test_post_chat_non_streaming_returns_and_persists_video_citations(monkeypatch):
    now_utc = datetime.now(timezone.utc)
    user_a = {
        "_id": ObjectId(),
        "account_id": "acc_ultra_a",
        "email": "ultra_a@saman.test",
        "membership_tier": "ultra",
    }
    story = _make_lat_pulldown_story("acc_ultra_a", now_utc)
    client, provider, _ = _setup_test_app(monkeypatch, current_user=user_a, video_stories=[story])

    resp = client.post(
        "/api/chat",
        json={
            "message": "Phân tích điểm yếu buổi Lat Pulldown gần nhất và lý do",
            "ai_mode": "core3",
            "contract_version": "core3-local-v1",
            "operation_id": secrets.token_hex(16),
        },
    )
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["video_citations"]) == 1
    assert body["video_citations"][0]["label"] == "Xem Lat Pulldown — Rep 7 (0:19)"
    assert body["video_citations"][0]["seek_sec"] == 19.5

    conv_resp = client.get(f"/api/chat/conversations/{body['conversation_id']}")
    assert conv_resp.status_code == 200
    assistant_msgs = [m for m in conv_resp.json()["messages"] if m["role"] == "assistant"]
    assert assistant_msgs[0]["video_citations"] == body["video_citations"]
    assert provider.calls[0]["intent"] == "full_audit"


def test_free_tier_gets_empty_video_citations(monkeypatch):
    now_utc = datetime.now(timezone.utc)
    free_user = {
        "_id": ObjectId(),
        "account_id": "acc_free_1",
        "email": "free@saman.test",
        "membership_tier": "free",
    }
    story = _make_lat_pulldown_story("acc_free_1", now_utc)
    client, _, _ = _setup_test_app(monkeypatch, current_user=free_user, video_stories=[story])

    resp = client.post(
        "/api/chat/stream",
        json={
            "message": "Phân tích điểm yếu buổi Lat Pulldown gần nhất và lý do",
            "ai_mode": "core3",
            "contract_version": "core3-local-v1",
            "operation_id": secrets.token_hex(16),
        },
    )
    assert resp.status_code == 200
    events = _parse_sse(resp.text)
    assert not any(e["event"] == "citations" for e in events)
    done_event = next(e for e in events if e["event"] == "done")
    assert done_event["data"]["video_citations"] == []


def test_tenant_isolation_blocks_cross_user_video_citations(monkeypatch):
    now_utc = datetime.now(timezone.utc)
    user_b = {
        "_id": ObjectId(),
        "account_id": "acc_ultra_b",
        "email": "ultra_b@saman.test",
        "membership_tier": "ultra",
    }
    # Story belongs strictly to user A, NOT user B
    story_of_a = _make_lat_pulldown_story("acc_ultra_a", now_utc)
    client, _, _ = _setup_test_app(monkeypatch, current_user=user_b, video_stories=[story_of_a])

    resp = client.post(
        "/api/chat",
        json={
            "message": "Phân tích buổi Lat Pulldown gần nhất",
            "ai_mode": "pro3",
            "contract_version": "core3-local-v1",
            "operation_id": secrets.token_hex(16),
        },
    )
    assert resp.status_code == 200
    assert resp.json()["video_citations"] == []


def test_general_chat_routes_lightweight_model_with_no_citations(monkeypatch):
    now_utc = datetime.now(timezone.utc)
    user_a = {
        "_id": ObjectId(),
        "account_id": "acc_ultra_a",
        "email": "ultra_a@saman.test",
        "membership_tier": "ultra",
    }
    story = _make_lat_pulldown_story("acc_ultra_a", now_utc)
    client, provider, _ = _setup_test_app(monkeypatch, current_user=user_a, video_stories=[story])

    resp = client.post(
        "/api/chat/stream",
        json={
            "message": "Xin chào Saman",
            "ai_mode": "pro3",
            "contract_version": "core3-local-v1",
            "operation_id": secrets.token_hex(16),
        },
    )
    assert resp.status_code == 200
    events = _parse_sse(resp.text)
    assert not any(e["event"] == "citations" for e in events)
    done_event = next(e for e in events if e["event"] == "done")
    assert done_event["data"]["video_citations"] == []

    assert len(provider.calls) == 1
    assert provider.calls[0]["intent"] == "general_chat"
    assert provider.calls[0]["prefer_lightweight_model"] is True


@pytest.mark.parametrize(
    ("message", "ai_mode", "expected_retrieving_label"),
    [
        (
            "Kiểm tra form bài Lat Pulldown hôm qua",
            "core3",
            "Retrieving workout & form data...",
        ),
        (
            "Hôm nay tôi ăn bao nhiêu calo và protein rồi?",
            "core3",
            "Retrieving nutrition & meal logs...",
        ),
        (
            "Nhóm cơ lưng của tôi đã phục hồi chưa hay còn mỏi?",
            "core3",
            "Checking muscle recovery & fatigue...",
        ),
        (
            "Phân tích điểm yếu buổi Lat Pulldown gần nhất và lý do",
            "pro3",
            "Synthesizing 30-day training & recovery data...",
        ),
        (
            "Xin chào Saman",
            "core3",
            "Gathering your context...",
        ),
    ],
)
def test_stream_emits_live_sse_status_events_before_first_delta(
    monkeypatch,
    message: str,
    ai_mode: str,
    expected_retrieving_label: str,
):
    user_a = {
        "_id": ObjectId(),
        "account_id": "acc_status_a",
        "email": "status_a@saman.test",
        "membership_tier": "ultra",
    }
    client, _, _ = _setup_test_app(monkeypatch, current_user=user_a)

    resp = client.post(
        "/api/chat/stream",
        json={
            "message": message,
            "ai_mode": ai_mode,
            "contract_version": "core3-local-v1",
            "operation_id": secrets.token_hex(16),
        },
    )
    assert resp.status_code == 200
    events = _parse_sse(resp.text)

    first_delta_idx = next(i for i, e in enumerate(events) if e["event"] == "delta")
    status_events = [(i, e["data"]) for i, e in enumerate(events) if e["event"] == "status"]

    assert len(status_events) == 3
    assert all(idx < first_delta_idx for idx, _ in status_events)

    assert status_events[0][1] == {
        "stage": "routing",
        "label": "Analyzing your request...",
    }
    assert status_events[1][1] == {
        "stage": "retrieving",
        "label": expected_retrieving_label,
    }
    assert status_events[2][1] == {
        "stage": "generating",
        "label": "Generating personalized insights...",
    }


def test_core3_and_swift3_max_output_tokens_expanded():
    from backend.app.services.core3_provider import TIER_CONFIGS, get_tier_config

    assert TIER_CONFIGS["swift3"]["max_output_tokens"] == 512
    assert TIER_CONFIGS["core3"]["max_output_tokens"] == 1024
    assert get_tier_config("swift3")["max_output_tokens"] == 512
    assert get_tier_config("core3")["max_output_tokens"] == 1024
