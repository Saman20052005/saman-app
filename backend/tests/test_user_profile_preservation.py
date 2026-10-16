"""Isolated unit and contract tests for User Profile preservation and CAS concurrency.

Tests verify:
- Decimal height/weight exact precision preserved (no rounding).
- Partial update (e.g., weight only) merges with existing DB fields to compute stats.
- Extra profile fields (allergies, notes) and extra health_stats fields are preserved.
- Omitted fields keep old values; explicit null on calculation fields raises 422 with zero writes.
- Missing required fields after merge (e.g. brand new user with partial fields) raises 422 with zero writes.
- Owner token strictly decides target record; body email/id/user_id cannot hijack identity.
- Database write failure/no match does not report false success.
- Concurrent requests with stale snapshot trigger CAS predicate failure -> 409 Conflict without writing stale stats.
- POST and PUT compatibility, stable user_id in GET /profile.
"""

from contextlib import ExitStack
import copy
from datetime import datetime
import os
from pathlib import Path
import socket
import sys
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch
import unittest.mock
from bson import ObjectId
import dotenv
import jwt
import pymongo
from fastapi import FastAPI
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
                "JWT_SECRET": "isolated-preservation-contract-jwt-secret",
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


class _UpdateResult:
    def __init__(self, matched_count=0, modified_count=0):
        self.matched_count = matched_count
        self.modified_count = modified_count


class _MemoryUsersCollection:
    def __init__(self):
        self.documents = []
        self.write_count = 0

    def _matches(self, doc, query):
        for k, expected in query.items():
            if "." in k:
                parts = k.split(".")
                curr = doc
                for p in parts:
                    if isinstance(curr, dict):
                        curr = curr.get(p)
                    else:
                        curr = None
                        break
            else:
                curr = doc.get(k)

            if isinstance(expected, dict) and "$in" in expected:
                if curr not in expected["$in"]:
                    return False
            else:
                if curr != expected:
                    return False
        return True

    def find_one(self, query):
        for doc in self.documents:
            if self._matches(doc, query):
                return copy.deepcopy(doc)
        return None

    def insert_one(self, doc):
        stored = copy.deepcopy(doc)
        if "_id" not in stored:
            stored["_id"] = ObjectId()
        self.documents.append(stored)
        return SimpleNamespace(inserted_id=stored["_id"])

    def update_one(self, query, update):
        target = None
        for doc in self.documents:
            if self._matches(doc, query):
                target = doc
                break

        if target is None:
            return _UpdateResult(matched_count=0, modified_count=0)

        self.write_count += 1
        set_fields = update.get("$set", {})
        for k, v in set_fields.items():
            if "." in k:
                parts = k.split(".")
                curr = target
                for p in parts[:-1]:
                    if p in curr:
                        if curr[p] is None:
                            raise ValueError(f"Cannot create field '{parts[-1]}' in element {{{p}: null}}")
                        if not isinstance(curr[p], dict):
                            raise ValueError(f"Cannot create field '{parts[-1]}' in element {{{p}: {curr[p]}}}")
                    else:
                        curr[p] = {}
                    curr = curr[p]
                curr[parts[-1]] = copy.deepcopy(v)
            else:
                target[k] = copy.deepcopy(v)

        return _UpdateResult(matched_count=1, modified_count=1)


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


class UserProfilePreservationTests(unittest.TestCase):
    def setUp(self):
        stack = ExitStack()
        self.addCleanup(stack.close)
        self._blocked_attempts = _enter_isolation_context(stack)

        from backend.routers.user import router as user_router, user_repo
        from backend.auth.config import JWT_SECRET, JWT_ALGORITHM

        stack.enter_context(
            patch.dict(
                globals(),
                {
                    "user_router": user_router,
                    "user_repo": user_repo,
                    "JWT_SECRET": JWT_SECRET,
                    "JWT_ALGORITHM": JWT_ALGORITHM,
                },
            )
        )

        self.app = FastAPI()
        self.app.include_router(user_router)
        self.client = TestClient(self.app)

        self.users_col = _MemoryUsersCollection()
        stack.enter_context(patch.object(user_repo, "collection", self.users_col))

        self.user_id = ObjectId()
        self.email = "preservation_user@example.com"
        self.user_doc = {
            "_id": self.user_id,
            "email": self.email,
            "full_name": "Original Name",
            "profile": {
                "age": 28,
                "gender": "male",
                "height": 178.5,
                "weight": 73.25,
                "activity_level": "moderate",
                "goal": "maintain_weight",
                "allergies": ["peanut", "shellfish"],
                "custom_notes": "Preserve this note",
            },
            "health_stats": {
                "bmi": 23.0,
                "bmr": 1720,
                "tdee": 2666,
                "daily_calories": 2666,
                "custom_metric": 42,
            },
            "meals": [{"meal_id": 1, "name": "Breakfast"}],
            "workouts": [{"workout_id": 101}],
        }
        self.users_col.insert_one(self.user_doc)
        self.token = jwt.encode({"email": self.email}, JWT_SECRET, algorithm=JWT_ALGORITHM)
        self.headers = {"Authorization": f"Bearer {self.token}"}

    def tearDown(self):
        self.assertEqual(
            len(self._blocked_attempts),
            0,
            "External infrastructure access was attempted during test execution",
        )

    def test_decimal_height_weight_exact_precision(self):
        payload = {
            "height": 175.75,
            "weight": 68.35,
        }
        res = self.client.post("/api/user/update-profile", json=payload, headers=self.headers)
        self.assertEqual(res.status_code, 200, res.text)
        data = res.json()
        self.assertEqual(data["profile"]["height"], 175.75)
        self.assertEqual(data["profile"]["weight"], 68.35)

        # GET verification
        get_res = self.client.get("/api/user/profile", headers=self.headers)
        self.assertEqual(get_res.status_code, 200)
        get_data = get_res.json()
        self.assertEqual(get_data["profile"]["height"], 175.75)
        self.assertEqual(get_data["profile"]["weight"], 68.35)

    def test_partial_update_merges_with_existing_db(self):
        # Update weight only
        payload = {"weight": 76.5}
        res = self.client.post("/api/user/update-profile", json=payload, headers=self.headers)
        self.assertEqual(res.status_code, 200, res.text)
        data = res.json()
        # Verify weight updated, other fields retained
        self.assertEqual(data["profile"]["weight"], 76.5)
        self.assertEqual(data["profile"]["height"], 178.5)
        self.assertEqual(data["profile"]["age"], 28)
        self.assertEqual(data["profile"]["gender"], "male")
        self.assertEqual(data["profile"]["activity_level"], "moderate")
        self.assertEqual(data["profile"]["goal"], "maintain_weight")

    def test_extra_profile_and_stats_fields_preserved(self):
        payload = {"weight": 74.0}
        res = self.client.post("/api/user/update-profile", json=payload, headers=self.headers)
        self.assertEqual(res.status_code, 200)

        # Verify DB doc directly
        doc = self.users_col.find_one({"email": self.email})
        self.assertEqual(doc["profile"]["allergies"], ["peanut", "shellfish"])
        self.assertEqual(doc["profile"]["custom_notes"], "Preserve this note")
        self.assertEqual(doc["health_stats"]["custom_metric"], 42)
        self.assertEqual(len(doc["meals"]), 1)
        self.assertEqual(len(doc["workouts"]), 1)

    def test_explicit_null_returns_422_and_zero_writes(self):
        initial_writes = self.users_col.write_count
        for field in ("age", "gender", "height", "weight", "activity_level", "goal"):
            payload = {field: None}
            res = self.client.post("/api/user/update-profile", json=payload, headers=self.headers)
            self.assertEqual(res.status_code, 422, f"Expected 422 for {field}: null, got {res.status_code}")

        self.assertEqual(self.users_col.write_count, initial_writes, "Expected zero DB writes on 422")

    def test_missing_required_merged_fields_returns_422_and_zero_writes(self):
        # Create user with no profile
        new_id = ObjectId()
        new_email = "new_empty@example.com"
        self.users_col.insert_one({"_id": new_id, "email": new_email, "full_name": "Empty User"})
        token = jwt.encode({"email": new_email}, JWT_SECRET, algorithm=JWT_ALGORITHM)
        headers = {"Authorization": f"Bearer {token}"}

        initial_writes = self.users_col.write_count
        # Provide only weight
        payload = {"weight": 70.0}
        res = self.client.post("/api/user/update-profile", json=payload, headers=headers)
        self.assertEqual(res.status_code, 422)
        self.assertEqual(self.users_col.write_count, initial_writes, "Expected zero writes for incomplete new user")

    def test_owner_token_decides_record_body_identity_cannot_override(self):
        evil_email = "other_user@example.com"
        evil_id = ObjectId()
        self.users_col.insert_one({
            "_id": evil_id,
            "email": evil_email,
            "full_name": "Victim",
            "profile": {"age": 40, "gender": "female", "height": 160.0, "weight": 55.0, "activity_level": "light", "goal": "lose_weight"}
        })

        # Request with victim's email in body, but authenticated as preservation_user
        payload = {
            "email": evil_email,
            "weight": 80.0,
        }
        res = self.client.post("/api/user/update-profile", json=payload, headers=self.headers)
        self.assertEqual(res.status_code, 200)

        # Authenticated user's weight was updated
        caller_doc = self.users_col.find_one({"email": self.email})
        self.assertEqual(caller_doc["profile"]["weight"], 80.0)
        self.assertEqual(caller_doc["email"], self.email)

        # Victim's weight remained untouched
        victim_doc = self.users_col.find_one({"email": evil_email})
        self.assertEqual(victim_doc["profile"]["weight"], 55.0)

    def test_concurrent_requests_trigger_cas_conflict_409(self):
        # Request 1 and Request 2 read current user at the same time
        user_snapshot = self.users_col.find_one({"email": self.email})

        # Request 1 updates height from 178.5 to 182.0
        res1 = self.client.post("/api/user/update-profile", json={"height": 182.0}, headers=self.headers)
        self.assertEqual(res1.status_code, 200)

        # Simulate Request 2 which had read user_snapshot before Request 1's write
        # If user_repo.update_profile_stats_cas is called with stale snapshot:
        from backend.app.models.user import UserProfileInput
        from backend.services.health_engine import HealthEngine

        req2_input = UserProfileInput(weight=77.0)
        merged = dict(user_snapshot["profile"])
        merged["weight"] = 77.0
        stats2 = HealthEngine.calculate_stats(merged)

        # Execute CAS with the stale user_snapshot (which had height 178.5, but DB now has 182.0)
        cas_result = user_repo.update_profile_stats_cas(
            email=self.email,
            current_user=user_snapshot,
            profile_input=req2_input,
            merged_profile=merged,
            stats=stats2,
        )
        self.assertEqual(cas_result.matched_count, 0, "CAS predicate should have failed because height changed in DB")

        # Now test that router returns 409 when matched_count == 0
        with unittest.mock.patch.object(user_repo, "update_profile_stats_cas", return_value=_UpdateResult(matched_count=0)):
            res_conflict = self.client.post("/api/user/update-profile", json={"weight": 77.0}, headers=self.headers)
            self.assertEqual(res_conflict.status_code, 409)

    def test_post_and_put_compatibility_and_get_stable_identity(self):
        payload = {"weight": 71.5}
        # Test PUT
        put_res = self.client.put("/api/user/update-profile", json=payload, headers=self.headers)
        self.assertEqual(put_res.status_code, 200)
        self.assertEqual(put_res.json()["profile"]["weight"], 71.5)

        # Test GET returns stable user_id
        get_res = self.client.get("/api/user/profile", headers=self.headers)
        self.assertEqual(get_res.status_code, 200)
        data = get_res.json()
        self.assertEqual(data["user_id"], str(self.user_id))
        self.assertEqual(data["profile"]["weight"], 71.5)

    def test_partial_nested_profile_with_root_fallback(self):
        user_id = ObjectId()
        email = "fallback_user@example.com"
        # User has root height, but profile lacks height
        self.users_col.insert_one({
            "_id": user_id,
            "email": email,
            "full_name": "Fallback User",
            "height": 174.5,
            "profile": {
                "age": 30,
                "gender": "female",
                "weight": 60.0,
                "activity_level": "moderate",
                "goal": "maintain_weight",
                "custom_notes": "Do not lose this note",
            },
            "health_stats": {"bmi": 20.0, "bmr": 1300, "tdee": 1800, "daily_calories": 1800},
        })
        token = jwt.encode({"email": email}, JWT_SECRET, algorithm=JWT_ALGORITHM)
        headers = {"Authorization": f"Bearer {token}"}

        # Update weight only; height must come from root fallback
        payload = {"weight": 62.0}
        res = self.client.post("/api/user/update-profile", json=payload, headers=headers)
        self.assertEqual(res.status_code, 200, res.text)
        data = res.json()
        self.assertEqual(data["profile"]["weight"], 62.0)
        self.assertEqual(data["profile"]["height"], 174.5)

        # Verify DB directly: profile.height must be persisted and notes preserved
        doc = self.users_col.find_one({"email": email})
        self.assertEqual(doc["profile"]["height"], 174.5)
        self.assertEqual(doc["profile"]["weight"], 62.0)
        self.assertEqual(doc["profile"]["custom_notes"], "Do not lose this note")

    def test_root_input_modified_between_read_and_update_triggers_409(self):
        user_id = ObjectId()
        email = "root_conflict@example.com"
        self.users_col.insert_one({
            "_id": user_id,
            "email": email,
            "height": 170.0,
            "profile": {
                "age": 25,
                "gender": "male",
                "weight": 65.0,
                "activity_level": "light",
                "goal": "lose_weight",
            },
            "health_stats": {"bmi": 22.0, "bmr": 1500, "tdee": 2000, "daily_calories": 1500},
        })
        token = jwt.encode({"email": email}, JWT_SECRET, algorithm=JWT_ALGORITHM)
        headers = {"Authorization": f"Bearer {token}"}

        # Read snapshot
        snapshot = self.users_col.find_one({"email": email})
        self.assertEqual(snapshot["height"], 170.0)

        # Another process modifies root height to 175.0 in DB
        self.users_col.update_one({"email": email}, {"$set": {"height": 175.0}})

        # Now attempt CAS update using the stale snapshot (which had root height 170.0)
        from backend.app.models.user import UserProfileInput
        from backend.services.health_engine import HealthEngine

        req_input = UserProfileInput(weight=66.0)
        merged = dict(snapshot["profile"])
        merged["height"] = snapshot["height"]
        merged["weight"] = 66.0
        stats = HealthEngine.calculate_stats(merged)

        cas_res = user_repo.update_profile_stats_cas(
            email=email,
            current_user=snapshot,
            profile_input=req_input,
            merged_profile=merged,
            stats=stats,
        )
        self.assertEqual(cas_res.matched_count, 0, "CAS predicate should have failed because root height changed")

        # Confirm DB still has height 175.0 and weight was not overwritten
        fresh_doc = self.users_col.find_one({"email": email})
        self.assertEqual(fresh_doc["height"], 175.0)
        self.assertEqual(fresh_doc["profile"]["weight"], 65.0)

    def test_extra_health_stats_fields_preserved_on_recalculate(self):
        user_id = ObjectId()
        email = "stats_extra@example.com"
        self.users_col.insert_one({
            "_id": user_id,
            "email": email,
            "profile": {
                "age": 29,
                "gender": "male",
                "height": 180.0,
                "weight": 80.0,
                "activity_level": "active",
                "goal": "gain_muscle",
            },
            "health_stats": {
                "bmi": 24.7,
                "bmr": 1800,
                "tdee": 2700,
                "daily_calories": 3000,
                "body_fat_pct": 14.2,
                "hydration_level": 62.5,
                "custom_tracking": "track_alpha",
            },
        })
        token = jwt.encode({"email": email}, JWT_SECRET, algorithm=JWT_ALGORITHM)
        headers = {"Authorization": f"Bearer {token}"}

        # Update weight -> triggers stats recalculation
        res = self.client.post("/api/user/update-profile", json={"weight": 82.0}, headers=headers)
        self.assertEqual(res.status_code, 200)

        # Extra fields on health_stats must be intact in DB
        doc = self.users_col.find_one({"email": email})
        self.assertEqual(doc["health_stats"]["body_fat_pct"], 14.2)
        self.assertEqual(doc["health_stats"]["hydration_level"], 62.5)
        self.assertEqual(doc["health_stats"]["custom_tracking"], "track_alpha")
        # And standard calculated fields are updated
        self.assertAlmostEqual(doc["health_stats"]["bmi"], 82.0 / (1.80 * 1.80), places=1)

    def test_profile_explicit_null_and_missing_parents_handled_without_dot_update_error(self):
        # 1. Test user with explicit null profile and health_stats
        user_id_1 = ObjectId()
        email_1 = "null_parents@example.com"
        self.users_col.insert_one({
            "_id": user_id_1,
            "email": email_1,
            "profile": None,
            "health_stats": None,
        })
        token_1 = jwt.encode({"email": email_1}, JWT_SECRET, algorithm=JWT_ALGORITHM)
        headers_1 = {"Authorization": f"Bearer {token_1}"}

        # Submitting full onboarding profile should replace null parent objects without throwing dot-update error
        res_1 = self.client.post(
            "/api/user/update-profile",
            json={
                "age": 28,
                "gender": "male",
                "height": 175.0,
                "weight": 70.0,
                "activity_level": "moderate",
                "goal": "maintain_weight",
            },
            headers=headers_1,
        )
        self.assertEqual(res_1.status_code, 200)
        doc_1 = self.users_col.find_one({"email": email_1})
        self.assertIsInstance(doc_1["profile"], dict)
        self.assertEqual(doc_1["profile"]["age"], 28)
        self.assertEqual(doc_1["profile"]["height"], 175.0)
        self.assertIsInstance(doc_1["health_stats"], dict)
        self.assertGreater(doc_1["health_stats"]["daily_calories"], 0)

        # 2. Test user with missing profile and health_stats fields entirely
        user_id_2 = ObjectId()
        email_2 = "missing_parents@example.com"
        self.users_col.insert_one({
            "_id": user_id_2,
            "email": email_2,
        })
        token_2 = jwt.encode({"email": email_2}, JWT_SECRET, algorithm=JWT_ALGORITHM)
        headers_2 = {"Authorization": f"Bearer {token_2}"}

        res_2 = self.client.post(
            "/api/user/update-profile",
            json={
                "age": 30,
                "gender": "female",
                "height": 162.0,
                "weight": 55.0,
                "activity_level": "light",
                "goal": "lose_weight",
            },
            headers=headers_2,
        )
        self.assertEqual(res_2.status_code, 200)
        doc_2 = self.users_col.find_one({"email": email_2})
        self.assertIsInstance(doc_2["profile"], dict)
        self.assertEqual(doc_2["profile"]["age"], 30)
        self.assertIsInstance(doc_2["health_stats"], dict)

    def test_concurrent_creation_of_health_stats_after_read_triggers_409(self):
        user_id = ObjectId()
        email = "concurrent_stats@example.com"
        self.users_col.insert_one({
            "_id": user_id,
            "email": email,
            "profile": None,
            "health_stats": None,
        })

        # Process A reads user snapshot (health_stats is None)
        snapshot = self.users_col.find_one({"email": email})
        self.assertIsNone(snapshot.get("health_stats"))

        # Process B concurrently writes a custom health_stats object
        self.users_col.update_one(
            {"email": email},
            {"$set": {"health_stats": {"custom_device_metric": 99.5, "vo2_max": 48.0}}},
        )

        # Process A attempts CAS update using stale snapshot where health_stats was None
        from backend.app.models.user import UserProfileInput
        from backend.services.health_engine import HealthEngine

        req_input = UserProfileInput(
            age=26,
            gender="female",
            height=165.0,
            weight=58.0,
            activity_level="moderate",
            goal="maintain_weight",
        )
        merged = req_input.model_dump()
        stats = HealthEngine.calculate_stats(merged)

        cas_res = user_repo.update_profile_stats_cas(
            email=email,
            current_user=snapshot,
            profile_input=req_input,
            merged_profile=merged,
            stats=stats,
        )
        self.assertEqual(cas_res.matched_count, 0, "CAS predicate must fail because health_stats is no longer in [None, {}]")

        # Confirm DB custom fields were NOT overwritten (zero data loss)
        doc = self.users_col.find_one({"email": email})
        self.assertEqual(doc["health_stats"]["custom_device_metric"], 99.5)
        self.assertEqual(doc["health_stats"]["vo2_max"], 48.0)

    def test_concurrent_creation_of_profile_after_read_triggers_409(self):
        user_id = ObjectId()
        email = "concurrent_profile@example.com"
        self.users_col.insert_one({
            "_id": user_id,
            "email": email,
            "profile": None,
            "health_stats": None,
        })

        # Process A reads user snapshot (profile is None)
        snapshot = self.users_col.find_one({"email": email})
        self.assertIsNone(snapshot.get("profile"))

        # Process B concurrently writes custom profile fields (e.g. allergies)
        self.users_col.update_one(
            {"email": email},
            {"$set": {"profile": {"allergies": ["peanut", "seafood"], "blood_type": "O+"}}},
        )

        # Process A attempts CAS update using stale snapshot where profile was None
        from backend.app.models.user import UserProfileInput
        from backend.services.health_engine import HealthEngine

        req_input = UserProfileInput(
            age=27,
            gender="male",
            height=178.0,
            weight=74.0,
            activity_level="active",
            goal="gain_muscle",
        )
        merged = req_input.model_dump()
        stats = HealthEngine.calculate_stats(merged)

        cas_res = user_repo.update_profile_stats_cas(
            email=email,
            current_user=snapshot,
            profile_input=req_input,
            merged_profile=merged,
            stats=stats,
        )
        self.assertEqual(cas_res.matched_count, 0, "CAS predicate must fail because profile is no longer in [None, {}]")

        # Confirm DB custom profile fields were NOT overwritten
        doc = self.users_col.find_one({"email": email})
        self.assertEqual(doc["profile"]["allergies"], ["peanut", "seafood"])
        self.assertEqual(doc["profile"]["blood_type"], "O+")


if __name__ == "__main__":
    unittest.main()
