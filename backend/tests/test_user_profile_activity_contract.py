"""Isolated contract tests for 5-tier activity levels, canonical factors, and legacy compatibility.

Verifies:
- 5 canonical values: sedentary, light, moderate, active, very_active round-trip without loss.
- Legacy values: low, medium, high mapping to correct canonical factors:
    low -> sedentary (1.2)
    medium -> moderate (1.55)
    high -> active (1.725, NOT 1.9!)
- Canonical multipliers:
    sedentary: 1.2
    light: 1.375
    moderate: 1.55
    active: 1.725
    very_active: 1.9
- Invalid activity levels rejected with 422.
"""

import copy
from datetime import datetime
import socket
import sys
from types import ModuleType, SimpleNamespace
import unittest
from bson import ObjectId
import dotenv
import jwt
import pymongo
from fastapi import FastAPI
from fastapi.testclient import TestClient

# ---------------------------------------------------------------------------
# 1. PRE-IMPORT ISOLATION GUARDS: Block real DB, sockets, and .env loading
# ---------------------------------------------------------------------------

_blocked_attempts = []


def _forbidden(*args, **kwargs):
    _blocked_attempts.append(True)
    raise AssertionError("External infrastructure access forbidden during isolated tests")


_orig_socket_connect = socket.socket.connect
_orig_socketpair = socket.socketpair


def _guarded_connect(sock, address):
    if (
        sys._getframe(1).f_code is getattr(_orig_socketpair, "__code__", None)
        and address[0] in ("127.0.0.1", "::1")
    ):
        return _orig_socket_connect(sock, address)
    return _forbidden(sock, address)


socket.socket.connect = _guarded_connect
socket.socket.connect_ex = _forbidden
socket.create_connection = _forbidden
socket.getaddrinfo = _forbidden
pymongo.MongoClient = _forbidden
dotenv.load_dotenv = lambda *args, **kwargs: False


class _UpdateResult:
    def __init__(self, matched_count=0, modified_count=0):
        self.matched_count = matched_count
        self.modified_count = modified_count


class _MemoryUsersCollection:
    def __init__(self):
        self.documents = []

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

        set_fields = update.get("$set", {})
        for k, v in set_fields.items():
            if "." in k:
                parts = k.split(".")
                curr = target
                for p in parts[:-1]:
                    if p not in curr or not isinstance(curr[p], dict):
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


if "backend.app.database" not in sys.modules:
    sys.modules["backend.app.database"] = _MockDatabaseModule("backend.app.database")

from backend.routers.user import router as user_router, user_repo
from backend.services.health_engine import HealthEngine, calculate_tdee
from backend.auth.config import JWT_SECRET, JWT_ALGORITHM


class UserProfileActivityContractTests(unittest.TestCase):
    def setUp(self):
        self.app = FastAPI()
        self.app.include_router(user_router)
        self.client = TestClient(self.app)

        self.users_col = _MemoryUsersCollection()
        user_repo.collection = self.users_col

        self.user_id = ObjectId()
        self.email = "contract_test@example.com"
        self.user_doc = {
            "_id": self.user_id,
            "email": self.email,
            "full_name": "Activity Tester",
            "profile": {
                "age": 30,
                "gender": "male",
                "height": 180.0,
                "weight": 75.0,
                "activity_level": "moderate",
                "goal": "maintain_weight",
            },
            "health_stats": {
                "bmi": 23.1,
                "bmr": 1755,
                "tdee": 2720,
                "daily_calories": 2720,
            },
        }
        self.users_col.insert_one(self.user_doc)
        self.token = jwt.encode({"email": self.email}, JWT_SECRET, algorithm=JWT_ALGORITHM)
        self.headers = {"Authorization": f"Bearer {self.token}"}

    def test_five_canonical_activity_values_accepted_and_roundtrip(self):
        canonical_values = ["sedentary", "light", "moderate", "active", "very_active"]
        for act in canonical_values:
            payload = {
                "age": 30,
                "gender": "male",
                "height": 180.0,
                "weight": 75.0,
                "activity_level": act,
                "goal": "maintain_weight",
            }
            res = self.client.post("/api/user/update-profile", json=payload, headers=self.headers)
            self.assertEqual(res.status_code, 200, f"Failed for activity_level={act}: {res.text}")
            data = res.json()
            self.assertEqual(data["profile"]["activity_level"], act)

            # Fresh GET readback
            get_res = self.client.get("/api/user/profile", headers=self.headers)
            self.assertEqual(get_res.status_code, 200)
            get_data = get_res.json()
            self.assertEqual(get_data["profile"]["activity_level"], act)

    def test_canonical_multipliers_calculation(self):
        # BMR for 75kg, 180cm, 30yo male = 10*75 + 6.25*180 - 5*30 + 5 = 750 + 1125 - 150 + 5 = 1730
        bmr = 1730
        factors = {
            "sedentary": 1.2,
            "light": 1.375,
            "moderate": 1.55,
            "active": 1.725,
            "very_active": 1.9,
        }
        for act, factor in factors.items():
            profile_dict = {
                "weight": 75.0,
                "height": 180.0,
                "age": 30,
                "gender": "male",
                "activity_level": act,
                "goal": "maintain",
            }
            tdee_res = calculate_tdee(profile_dict)
            expected_tdee = round(bmr * factor)
            self.assertEqual(tdee_res["tdee"], expected_tdee, f"Mismatch for {act}")

    def test_legacy_activity_mapping_and_factors(self):
        # Legacy: low -> 1.2 (sedentary), medium -> 1.55 (moderate), high -> 1.725 (active, NOT 1.9)
        legacy_factors = {
            "low": 1.2,
            "medium": 1.55,
            "high": 1.725,
        }
        for leg, factor in legacy_factors.items():
            payload = {
                "age": 30,
                "gender": "male",
                "height": 180.0,
                "weight": 75.0,
                "activity_level": leg,
                "goal": "maintain_weight",
            }
            res = self.client.post("/api/user/update-profile", json=payload, headers=self.headers)
            self.assertEqual(res.status_code, 200, f"Failed for legacy {leg}: {res.text}")
            data = res.json()
            # BMR=1730 -> TDEE = round(1730 * factor)
            expected_tdee = round(1730 * factor)
            self.assertEqual(data["health_stats"]["tdee"], expected_tdee)
            # High must NOT be 1.9 (which would be 3287)
            if leg == "high":
                self.assertNotEqual(data["health_stats"]["tdee"], round(1730 * 1.9))

    def test_invalid_activity_level_returns_422(self):
        payload = {
            "age": 30,
            "gender": "male",
            "height": 180.0,
            "weight": 75.0,
            "activity_level": "extreme_olympian",
            "goal": "maintain_weight",
        }
        res = self.client.post("/api/user/update-profile", json=payload, headers=self.headers)
        self.assertEqual(res.status_code, 422)


if __name__ == "__main__":
    unittest.main()
