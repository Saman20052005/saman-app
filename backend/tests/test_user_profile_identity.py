"""Isolated unit/contract tests for stable user_id in GET /api/user/profile.

Isolates external infrastructure (database, network, .env) BEFORE importing backend modules.
Tests verify:
- Response contract (stable user_id, preserved fields, no sensitive leak).
- User without profile/health_stats (None semantics preserved).
- A/B owner isolation (no state leakage between distinct users).
- Auth failure contract (401 response, no user_id or success payload).
"""

from contextlib import ExitStack
import copy
import os
from pathlib import Path
import socket
import sys
from types import ModuleType
import unittest
from unittest.mock import patch
from bson import ObjectId
import dotenv
import pymongo
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

_BACKEND_DIR = Path(__file__).resolve().parents[1]


def _enter_isolation_context(stack: ExitStack):
    """Install socket, DB, env, and sys.modules guards on stack with guaranteed restoration."""
    blocked_attempts = []

    def _forbidden(*args, **kwargs):
        blocked_attempts.append(True)
        raise AssertionError("External infrastructure access forbidden during isolated tests")

    base_connect = getattr(socket.socket.connect, "__wrapped__", socket.socket.connect)
    orig_socketpair = socket.socketpair

    def _guarded_connect(sock, address):
        # Windows asyncio loopback connection allowed for TestClient/asyncio
        if (
            sys._getframe(1).f_code is getattr(orig_socketpair, "__code__", None)
            and isinstance(address, tuple)
            and len(address) >= 1
            and address[0] in ("127.0.0.1", "::1")
        ):
            return base_connect(sock, address)
        return _forbidden(sock, address)

    _guarded_connect.__wrapped__ = base_connect

    stack.enter_context(patch.object(socket.socket, "connect", _guarded_connect))
    stack.enter_context(patch.object(socket.socket, "connect_ex", _forbidden))
    stack.enter_context(patch.object(socket, "create_connection", _forbidden))
    stack.enter_context(patch.object(socket, "getaddrinfo", _forbidden))
    stack.enter_context(patch.object(pymongo, "MongoClient", _forbidden))
    stack.enter_context(patch.object(dotenv, "load_dotenv", lambda *args, **kwargs: False))
    if hasattr(dotenv, "main") and hasattr(dotenv.main, "DotEnv"):
        stack.enter_context(patch.object(dotenv.main, "DotEnv", _forbidden))

    stack.enter_context(
        patch.dict(
            os.environ,
            {
                "JWT_SECRET": "isolated-identity-contract-jwt-secret",
                "JWT_ALGORITHM": "HS256",
            },
        )
    )
    stack.enter_context(patch.dict(sys.modules))
    for mod_name in list(sys.modules):
        if mod_name == "backend" or mod_name.startswith("backend."):
            del sys.modules[mod_name]

    for pkg_name, pkg_path in (
        ("backend", _BACKEND_DIR),
        ("backend.app", _BACKEND_DIR / "app"),
        ("backend.app.models", _BACKEND_DIR / "app" / "models"),
        ("backend.app.repositories", _BACKEND_DIR / "app" / "repositories"),
        ("backend.auth", _BACKEND_DIR / "auth"),
        ("backend.routers", _BACKEND_DIR / "routers"),
        ("backend.services", _BACKEND_DIR / "services"),
    ):
        pkg = ModuleType(pkg_name)
        pkg.__path__ = [str(pkg_path)]
        pkg.__package__ = pkg_name
        sys.modules[pkg_name] = pkg

    sys.modules["backend.app.database"] = _MockDatabaseModule("backend.app.database")
    return blocked_attempts


# In-memory mock collection for UserRepository instantiation without DB connection
class _MemoryUsersCollection:
    def __init__(self):
        self.documents = []

    def find_one(self, query):
        return next(
            (
                copy.deepcopy(doc)
                for doc in self.documents
                if all(doc.get(k) == v for k, v in query.items())
            ),
            None,
        )

    def insert_one(self, doc):
        stored = copy.deepcopy(doc)
        if "_id" not in stored:
            stored["_id"] = ObjectId()
        self.documents.append(stored)
        return stored["_id"]


class _MockDB(dict):
    def __getitem__(self, item):
        if item not in self:
            self[item] = _MemoryUsersCollection()
        return super().__getitem__(item)


class _MockDatabaseModule(ModuleType):
    def __init__(self, name):
        super().__init__(name)
        self.users_collection = _MemoryUsersCollection()
        self.db = _MockDB()

    def __getattr__(self, name):
        if name.endswith("_collection"):
            collection = _MemoryUsersCollection()
            setattr(self, name, collection)
            return collection
        raise AttributeError(f"Mock database has no attribute {name}")


class UserProfileIdentityContractTests(unittest.TestCase):
    def setUp(self):
        stack = ExitStack()
        self.addCleanup(stack.close)
        self._blocked_attempts = _enter_isolation_context(stack)

        from backend.routers.user import router, get_current_user

        stack.enter_context(
            patch.dict(
                globals(),
                {
                    "router": router,
                    "get_current_user": get_current_user,
                },
            )
        )

        self.app = FastAPI()
        self.app.include_router(router)
        self.client = TestClient(self.app)

    def tearDown(self):
        self.app.dependency_overrides.clear()
        # Verify no external network calls were attempted
        self.assertEqual(
            len(self._blocked_attempts),
            0,
            "External infrastructure access was attempted during test execution",
        )

    def test_response_contract_includes_stable_user_id(self):
        """Contract test: GET /api/user/profile returns stable user_id string matching _id.

        Preserves existing fields (email, full_name, avatar, profile, health_stats).
        Does NOT expose raw _id or password.
        """
        user_id = ObjectId("650000000000000000000001")
        mock_user = {
            "_id": user_id,
            "email": "user1@example.com",
            "full_name": "Nguyen Van A",
            "avatar": "https://example.com/avatar.png",
            "password": "hashed_secret_credentials",
            "profile": {
                "gender": "male",
                "height": 175,
                "weight": 70,
                "activity_level": "moderate",
                "goal": "maintain",
            },
            "health_stats": {
                "bmi": 22.86,
                "tdee": 2400,
                "daily_calories": 2400,
            },
        }

        self.app.dependency_overrides[get_current_user] = lambda: mock_user

        response = self.client.get("/api/user/profile")

        self.assertEqual(response.status_code, 200)
        data = response.json()

        # Contract assertion: stable user_id matches stringified _id
        self.assertIn("user_id", data)
        self.assertIsInstance(data["user_id"], str)
        self.assertEqual(data["user_id"], str(user_id))

        # Existing fields preserved
        self.assertEqual(data["email"], "user1@example.com")
        self.assertEqual(data["full_name"], "Nguyen Van A")
        self.assertEqual(data["avatar"], "https://example.com/avatar.png")
        self.assertEqual(data["profile"], mock_user["profile"])
        self.assertEqual(data["health_stats"], mock_user["health_stats"])

        # Sensitive and raw DB fields not exposed
        self.assertNotIn("_id", data)
        self.assertNotIn("password", data)

        # Exact expected top-level keys
        expected_keys = {
            "user_id",
            "email",
            "full_name",
            "avatar",
            "profile",
            "health_stats",
        }
        self.assertEqual(set(data.keys()), expected_keys)

    def test_user_without_profile_preserves_none_semantics(self):
        """User document without profile/health_stats still returns 200 and stable user_id.

        profile and health_stats fields maintain existing None semantics.
        """
        user_id = ObjectId("650000000000000000000002")
        mock_user = {
            "_id": user_id,
            "email": "newuser@example.com",
            "full_name": "Tran Thi B",
            "avatar": None,
            # 'profile' and 'health_stats' missing
        }

        self.app.dependency_overrides[get_current_user] = lambda: mock_user

        response = self.client.get("/api/user/profile")

        self.assertEqual(response.status_code, 200)
        data = response.json()

        self.assertEqual(data["user_id"], str(user_id))
        self.assertEqual(data["email"], "newuser@example.com")
        self.assertEqual(data["full_name"], "Tran Thi B")
        self.assertIsNone(data["avatar"])
        self.assertIsNone(data["profile"])
        self.assertIsNone(data["health_stats"])
        self.assertNotIn("_id", data)

    def test_ab_owner_isolation_no_state_leakage(self):
        """A/B isolation test: Requests with different authenticated users receive matching IDs.

        Sequential requests must not retain or leak prior account state.
        """
        user_a_id = ObjectId("65000000000000000000000a")
        user_b_id = ObjectId("65000000000000000000000b")

        user_a = {
            "_id": user_a_id,
            "email": "alice@example.com",
            "full_name": "Alice User",
            "avatar": None,
        }
        user_b = {
            "_id": user_b_id,
            "email": "bob@example.com",
            "full_name": "Bob User",
            "avatar": None,
        }

        # 1. Request as User A
        self.app.dependency_overrides[get_current_user] = lambda: user_a
        resp_a1 = self.client.get("/api/user/profile")
        self.assertEqual(resp_a1.status_code, 200)
        self.assertEqual(resp_a1.json()["user_id"], str(user_a_id))
        self.assertEqual(resp_a1.json()["email"], "alice@example.com")

        # 2. Request as User B
        self.app.dependency_overrides[get_current_user] = lambda: user_b
        resp_b = self.client.get("/api/user/profile")
        self.assertEqual(resp_b.status_code, 200)
        self.assertEqual(resp_b.json()["user_id"], str(user_b_id))
        self.assertEqual(resp_b.json()["email"], "bob@example.com")
        self.assertNotEqual(resp_b.json()["user_id"], resp_a1.json()["user_id"])

        # 3. Request again as User A to ensure no residual state from User B
        self.app.dependency_overrides[get_current_user] = lambda: user_a
        resp_a2 = self.client.get("/api/user/profile")
        self.assertEqual(resp_a2.status_code, 200)
        self.assertEqual(resp_a2.json()["user_id"], str(user_a_id))
        self.assertEqual(resp_a2.json()["email"], "alice@example.com")

    def test_auth_failure_router_contract_returns_401(self):
        """Contract test: Router returns 401 when auth dependency raises 401.

        Verifies that no user_id or successful profile payload is ever returned.
        Note: This verifies the router endpoint error contract; it does not test
        production JWT signature verification, as get_current_user is mocked here.
        """

        def auth_failure():
            raise HTTPException(status_code=401, detail="Could not validate credentials")

        self.app.dependency_overrides[get_current_user] = auth_failure

        response = self.client.get("/api/user/profile")

        self.assertEqual(response.status_code, 401)
        data = response.json()
        self.assertEqual(data, {"detail": "Could not validate credentials"})
        self.assertNotIn("user_id", data)

    def test_string_id_document_handled_consistently(self):
        """User document where _id is already a string format returns identical string."""
        str_id = "fixture-string-id-998877"
        mock_user = {
            "_id": str_id,
            "email": "stringid@example.com",
            "full_name": "String ID User",
        }

        self.app.dependency_overrides[get_current_user] = lambda: mock_user

        response = self.client.get("/api/user/profile")

        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data["user_id"], str_id)
        self.assertIsInstance(data["user_id"], str)


if __name__ == "__main__":
    unittest.main()
