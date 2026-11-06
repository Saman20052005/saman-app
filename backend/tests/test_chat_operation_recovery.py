import asyncio
import hashlib
import json
import secrets
import unittest
from datetime import datetime, timedelta, timezone
from urllib.parse import urlparse

from bson import ObjectId
from pymongo import MongoClient
from pymongo.errors import DuplicateKeyError

from backend.app.database_chat import ensure_chat_operation_indexes
from backend.app.services.chat_operation_service import ChatOperationService


class _FakeProvider:
    def __init__(self):
        self.calls = 0

    async def generate(self, prompt):
        self.calls += 1
        await asyncio.sleep(0.1)
        return "Canonical advisory response"


class ChatOperationMongoTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        parsed = urlparse("mongodb://localhost:27017")
        if parsed.hostname not in ("localhost", "127.0.0.1", "::1"):
            raise unittest.SkipTest("MongoDB target is not loopback")
        cls.client = MongoClient("mongodb://localhost:27017", serverSelectionTimeoutMS=500)
        try:
            cls.client.admin.command("ping")
        except Exception:
            cls.client.close()
            raise unittest.SkipTest("Loopback MongoDB is unavailable")
        cls.db = cls.client["saman_test_core3_isolated"]
        ensure_chat_operation_indexes(cls.db)

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "client"):
            cls.client.close()

    def setUp(self):
        self.user_id = "test-" + str(ObjectId())
        self.other_user_id = "other-" + str(ObjectId())
        self.op_id = secrets.token_hex(16)
        self.provider = _FakeProvider()
        self.conversations = self.db["conversations"]
        self.operations = self.db["chat_operations"]
        self.conversation_ids = []

    def tearDown(self):
        self.operations.delete_many({"user_id": self.user_id})
        self.operations.delete_many({"user_id": self.other_user_id})
        self.conversations.delete_many({"user_id": self.user_id})

    def _service(self):
        return ChatOperationService(db=self.db, conversations=self.conversations,
            nutrition=None, workouts=None, users=None, provider=self.provider,
            context_builder=lambda **kwargs: {})

    def _saved_operation(self, state, *, target="NEW", conversation_id=None, message="recover me"):
        conversation_id = conversation_id or ObjectId()
        fingerprint = hashlib.sha256(json.dumps(
            {"message": message, "target": target, "history": []},
            sort_keys=True, ensure_ascii=False,
        ).encode()).hexdigest()
        response = "Canonical advisory response"
        self.operations.insert_one({
            "user_id": self.user_id, "operation_id": self.op_id,
            "contract_version": "core3-local-v1", "payload_fingerprint": fingerprint,
            "requested_target": target, "resolved_conversation_id": conversation_id,
            "state": state, "claim_token": "old-token", "lease_until": datetime.now(timezone.utc) - timedelta(seconds=1),
            "canonical_response": response,
            "result_hash": hashlib.sha256(response.encode()).hexdigest(),
        })
        principal = {"_id": self.user_id, "email": "synthetic@example.test"}
        return principal, conversation_id, message

    def test_index_enforces_tenant_scoped_uniqueness(self):
        doc = {"user_id": self.user_id, "operation_id": self.op_id}
        self.operations.insert_one(doc)
        with self.assertRaises(DuplicateKeyError):
            self.operations.insert_one(doc)
        self.operations.insert_one({"user_id": self.other_user_id, "operation_id": self.op_id})

    def test_concurrent_new_operation_dispatches_once_and_appends_once(self):
        principal = {"_id": self.user_id, "email": "synthetic@example.test"}
        async def run_pair():
            service = self._service()
            return await asyncio.gather(*[
                service.handle(principal=principal, operation_id=self.op_id,
                    contract_version="core3-local-v1", message="How should I recover?")
                for _ in range(2)
            ])
        results = asyncio.run(run_pair())
        self.assertEqual(results[0]["conversation_id"], results[1]["conversation_id"])
        self.assertEqual(self.provider.calls, 1)
        conv = self.conversations.find_one({"_id": ObjectId(results[0]["conversation_id"]), "user_id": self.user_id})
        self.assertEqual(len(conv["messages"]), 2)
        self.assertEqual({m["operation_id"] for m in conv["messages"]}, {self.op_id})

    def test_payload_conflict_and_tenant_isolation(self):
        principal = {"_id": self.user_id, "email": "synthetic@example.test"}
        asyncio.run(self._service().handle(principal=principal, operation_id=self.op_id,
            contract_version="core3-local-v1", message="first"))
        with self.assertRaises(Exception):
            asyncio.run(self._service().handle(principal=principal, operation_id=self.op_id,
                contract_version="core3-local-v1", message="different"))
        self.assertIsNone(self.operations.find_one({"user_id": "other", "operation_id": self.op_id}))

    def test_expired_prepared_claim_dispatches_once(self):
        principal, conversation_id, message = self._saved_operation("prepared", target="NEW")
        result = asyncio.run(self._service().handle(principal=principal, operation_id=self.op_id,
            contract_version="core3-local-v1", message=message))
        self.assertEqual(result["conversation_id"], str(conversation_id))
        self.assertEqual(self.provider.calls, 1)

    def test_dispatched_operation_is_unknown_and_never_reclaimed(self):
        principal, _, message = self._saved_operation("dispatched")
        with self.assertRaises(Exception):
            asyncio.run(self._service().handle(principal=principal, operation_id=self.op_id,
                contract_version="core3-local-v1", message=message))
        self.assertEqual(self.provider.calls, 0)

    def test_result_saved_and_append_lost_ack_recover_without_dispatch_or_duplicate(self):
        principal, conversation_id, message = self._saved_operation("result_saved")
        self.conversations.insert_one({"_id": conversation_id, "user_id": self.user_id, "messages": []})
        result = asyncio.run(self._service().handle(principal=principal, operation_id=self.op_id,
            contract_version="core3-local-v1", message=message))
        self.assertEqual(result["reply"], "Canonical advisory response")
        self.assertEqual(self.provider.calls, 0)
        conv = self.conversations.find_one({"_id": conversation_id})
        self.assertEqual(len(conv["messages"]), 2)
        # Replay after append succeeded but the client lost its acknowledgement.
        replay = asyncio.run(self._service().handle(principal=principal, operation_id=self.op_id,
            contract_version="core3-local-v1", message=message))
        self.assertEqual(replay["reply"], result["reply"])
        self.assertEqual(len(self.conversations.find_one({"_id": conversation_id})["messages"]), 2)

    def test_append_lost_ack_marker_is_not_written_twice(self):
        principal, conversation_id, message = self._saved_operation("result_saved")
        timestamp = datetime.now(timezone.utc).isoformat()
        self.conversations.insert_one({"_id": conversation_id, "user_id": self.user_id, "messages": [
            {"role": "user", "content": message, "operation_id": self.op_id, "created_at": timestamp},
            {"role": "assistant", "content": "Canonical advisory response", "operation_id": self.op_id, "created_at": timestamp},
        ]})
        result = asyncio.run(self._service().handle(principal=principal, operation_id=self.op_id,
            contract_version="core3-local-v1", message=message))
        self.assertEqual(result["reply"], "Canonical advisory response")
        self.assertEqual(self.provider.calls, 0)
        self.assertEqual(len(self.conversations.find_one({"_id": conversation_id})["messages"]), 2)

    def test_other_tenant_cannot_replay_or_append_to_owned_conversation(self):
        principal, conversation_id, _ = self._saved_operation("completed")
        self.conversations.insert_one({"_id": conversation_id, "user_id": self.user_id, "messages": []})
        other = {"_id": self.other_user_id, "email": "other@example.test"}
        with self.assertRaises(Exception):
            asyncio.run(self._service().handle(principal=other, operation_id=secrets.token_hex(16),
                contract_version="core3-local-v1", message="private", conversation_id=str(conversation_id)))
        self.assertEqual(self.provider.calls, 0)


if __name__ == "__main__":
    unittest.main()
