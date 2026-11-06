"""Credential-gated Gemini staging acceptance against isolated loopback MongoDB."""

import asyncio
import importlib.util
import json
import os
from pathlib import Path
import sys
import types
import time
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from bson import ObjectId
from fastapi import FastAPI
from pymongo import MongoClient

os.environ["MONGO_URI"] = "mongodb://127.0.0.1:27017"
os.environ["DB_NAME"] = "saman_test_core3_isolated"

# The selected test venv omits these packages. They are unused here: the
# database is loopback-only, and the route's auth dependency is overridden.
if "certifi" not in sys.modules:
    sys.modules["certifi"] = types.SimpleNamespace(where=lambda: "")
if "jwt" not in sys.modules:
    sys.modules["jwt"] = types.SimpleNamespace()

from backend.app import database as core3_database
from backend.app.database_chat import ensure_chat_operation_indexes
from backend.app.services import chat_operation_service, core3_provider

# Load the production chat router without importing every unrelated router in
# backend.routers.__init__.py. The route's authentication dependency is
# replaced below with a synthetic principal; these stubs are not called.
_repo_package = types.ModuleType("backend.app.repositories")
_repo_package.__path__ = []
_repo_module = types.ModuleType("backend.app.repositories.user_repository")
_repo_module.UserRepository = type("UserRepository", (), {})
sys.modules.setdefault("backend.app.repositories", _repo_package)
sys.modules.setdefault("backend.app.repositories.user_repository", _repo_module)
_auth_module = types.ModuleType("backend.auth_utils")
_auth_module.get_current_user = lambda: None
_auth_module.verify_token = lambda *args, **kwargs: None
sys.modules.setdefault("backend.auth_utils", _auth_module)

_chat_path = Path(__file__).resolve().parents[1] / "routers" / "chat.py"
_chat_spec = importlib.util.spec_from_file_location("_cp03_live_chat_router", _chat_path)
chat_module = importlib.util.module_from_spec(_chat_spec)
_chat_spec.loader.exec_module(chat_module)


class _CountingGeminiProvider(core3_provider.GeminiCore3Provider):
    dispatches = 0
    instances = []

    def __init__(self, engine=None):
        super().__init__(engine)
        type(self).instances.append(self)

    async def generate(self, prompt):
        type(self).dispatches += 1
        self.last_prompt = prompt
        return await super().generate(prompt)


chat_operation_service.GeminiCore3Provider = _CountingGeminiProvider


class Core3LiveStagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (os.getenv("GEMINI_API_KEY") or os.getenv("STAGING_GEMINI_API_KEY")):
            raise unittest.SkipTest("Gemini staging credential is unavailable")

        cls.client = MongoClient(os.environ["MONGO_URI"], serverSelectionTimeoutMS=1000)
        try:
            cls.client.admin.command("ping")
        except Exception as exc:
            cls.client.close()
            raise unittest.SkipTest("Loopback MongoDB is unavailable") from exc

        cls.db = cls.client["saman_test_core3_isolated"]
        core3_database.MONGO_URI = os.environ["MONGO_URI"]
        core3_database.DB_NAME = "saman_test_core3_isolated"
        core3_database.db = cls.db
        chat_module.users_col = cls.db["users"]
        chat_module.nutrition_col = cls.db["nutrition_plans"]
        chat_module.workout_history_col = cls.db["workout_history"]
        chat_module.conversations_col = cls.db["conversations"]
        ensure_chat_operation_indexes(cls.db)

        cls.current_user = None
        cls.app = FastAPI()
        cls.app.include_router(chat_module.router)
        cls.app.dependency_overrides[chat_module.get_current_user] = lambda: cls.current_user
        _CountingGeminiProvider.dispatches = 0
        _CountingGeminiProvider.instances = []

    @classmethod
    def tearDownClass(cls):
        cls.client.close()

    def setUp(self):
        self.user_id = str(ObjectId())
        self.email = f"core3-live-{uuid.uuid4().hex}@example.test"
        self.operation_id = uuid.uuid4().hex
        self.db["users"].insert_one({"_id": self.user_id, "goal": "muscle_gain"})
        self.current_user = {"_id": self.user_id, "email": self.email, "goal": "muscle_gain"}
        type(self).current_user = self.current_user

    def tearDown(self):
        self.db["chat_operations"].delete_many({"user_id": self.user_id})
        self.db["conversations"].delete_many({"user_id": self.user_id})
        self.db["nutrition_plans"].delete_many({"user_email": self.email})
        self.db["workout_history"].delete_many({"user_id": self.user_id})
        self.db["users"].delete_one({"_id": self.user_id})

    @staticmethod
    async def _post_json(app, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        received = False
        sent = []

        async def receive():
            nonlocal received
            if not received:
                received = True
                return {"type": "http.request", "body": body, "more_body": False}
            return {"type": "http.disconnect"}

        async def send(message):
            sent.append(message)

        scope = {
            "type": "http",
            "asgi": {"version": "3.0", "spec_version": "2.3"},
            "http_version": "1.1",
            "method": "POST",
            "scheme": "http",
            "path": "/api/chat",
            "raw_path": b"/api/chat",
            "query_string": b"",
            "root_path": "",
            "headers": [
                (b"host", b"staging.test"),
                (b"content-type", b"application/json"),
                (b"content-length", str(len(body)).encode("ascii")),
            ],
            "client": ("127.0.0.1", 40000),
            "server": ("127.0.0.1", 80),
        }
        await app(scope, receive, send)
        status = next(message["status"] for message in sent if message["type"] == "http.response.start")
        response_body = b"".join(
            message.get("body", b"") for message in sent if message["type"] == "http.response.body"
        )
        return status, json.loads(response_body.decode("utf-8"))

    def test_live_context_empty_context_and_zero_dispatch_replay(self):
        vn_today = datetime.now(ZoneInfo("Asia/Ho_Chi_Minh")).date()
        self.db["nutrition_plans"].insert_one({
            "user_email": self.email,
            "date": vn_today.isoformat(),
            "total_calories": 650,
            "total_protein": 45,
            "total_carbs": 60,
            "total_fat": 15,
        })
        workout_time = datetime.now(timezone.utc) - timedelta(days=1)
        self.db["workout_history"].insert_one({
            "user_id": self.user_id,
            "started_at": workout_time,
            "date": workout_time.date().isoformat(),
            "plan_name": "Synthetic strength session",
            "exercise_logs": [
                {"exercise_slug": "squat", "weight_kg": 80, "set_number": index}
                for index in range(1, 4)
            ],
        })

        full_payload = {
            "message": "Đánh giá nhanh lượng dinh dưỡng hôm nay và buổi tập gần nhất của tôi.",
            "contract_version": "core3-local-v1",
            "operation_id": self.operation_id,
        }
        status, full_result = asyncio.run(self._post_json(self.app, full_payload))
        self.assertEqual(status, 200)
        full_reply = full_result["reply"]
        self.assertTrue(any(char in full_reply for char in "ăâđêôơư"), full_reply)
        self.assertIn("650", full_reply, full_reply)
        self.assertIn("45", full_reply, full_reply)
        self.assertIn("squat", full_reply.casefold(), full_reply)

        operation = self.db["chat_operations"].find_one({
            "user_id": self.user_id,
            "operation_id": self.operation_id,
        })
        self.assertEqual(operation["state"], "completed")
        full_usage = _CountingGeminiProvider.instances[-1].last_usage
        self.assertGreater(full_usage["prompt_tokens"], 0)
        self.assertGreater(full_usage["output_tokens"], 0)
        self.assertLessEqual(full_usage["output_tokens"], core3_provider.MAX_OUTPUT_TOKENS)

        empty_user_id = str(ObjectId())
        empty_email = f"core3-empty-{uuid.uuid4().hex}@example.test"
        self.db["users"].insert_one({"_id": empty_user_id, "goal": "muscle_gain"})
        empty_principal = {"_id": empty_user_id, "email": empty_email, "goal": "muscle_gain"}
        type(self).current_user = empty_principal
        empty_payload = {
            "message": "Gợi ý cho tôi bữa phụ trước khi tập gym.",
            "contract_version": "core3-local-v1",
            "operation_id": uuid.uuid4().hex,
        }
        try:
            empty_status, empty_result = asyncio.run(self._post_json(self.app, empty_payload))
            self.assertEqual(empty_status, 200)
            empty_reply = empty_result["reply"]
            empty_normalized = empty_reply.casefold()
            self.assertTrue(any(char in empty_reply for char in "ăâđêôơư"), empty_reply)
            self.assertIn("chưa có dữ liệu", empty_normalized, empty_reply)
            self.assertTrue("nhật ký" in empty_normalized or "ghi lại" in empty_normalized, empty_reply)
            self.assertNotIn("650", empty_reply)
            self.assertNotIn("45", empty_reply)
            empty_usage = _CountingGeminiProvider.instances[-1].last_usage
            self.assertGreater(empty_usage["prompt_tokens"], 0)
            self.assertGreater(empty_usage["output_tokens"], 0)
            self.assertLessEqual(empty_usage["output_tokens"], core3_provider.MAX_OUTPUT_TOKENS)
        finally:
            self.db["chat_operations"].delete_many({"user_id": empty_user_id})
            self.db["conversations"].delete_many({"user_id": empty_user_id})
            self.db["nutrition_plans"].delete_many({"user_email": empty_email})
            self.db["workout_history"].delete_many({"user_id": empty_user_id})
            self.db["users"].delete_one({"_id": empty_user_id})
            type(self).current_user = self.current_user

        self.assertEqual(_CountingGeminiProvider.dispatches, 2)
        replay_started = time.perf_counter()
        replay_status, replay_result = asyncio.run(self._post_json(self.app, full_payload))
        replay_latency_ms = (time.perf_counter() - replay_started) * 1000
        self.assertEqual(replay_status, 200)
        self.assertEqual(replay_result, full_result)
        self.assertLess(replay_latency_ms, 100, f"replay took {replay_latency_ms:.1f} ms")
        self.assertEqual(_CountingGeminiProvider.dispatches, 2)

        model = os.getenv("GEMINI_MODEL", "gemini-3.6-flash")
        average_prompt = (full_usage["prompt_tokens"] + empty_usage["prompt_tokens"]) / 2
        average_output = (full_usage["output_tokens"] + empty_usage["output_tokens"]) / 2
        print(f"LIVE_MODEL={model}; LIVE_DISPATCHES=2; REPLAY_DISPATCHES=0")
        print(f"TOKEN_AVERAGE prompt={average_prompt:.1f}, output={average_output:.1f}")
        print(f"REPLAY_LATENCY_MS={replay_latency_ms:.1f}")
        print(f"FULL_CONTEXT_SAMPLE={full_reply}")
        print(f"EMPTY_CONTEXT_SAMPLE={empty_reply}")


if __name__ == "__main__":
    unittest.main()
