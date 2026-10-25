"""Regression tests for Weekly Report consumed integrity (SAMAN Nutrition N1).

Runs real handler logic from backend.routers.nutrition with controlled in-memory
collections at the database/auth boundary (no external MongoDB, network, or .env).
"""

import asyncio
import copy
from contextlib import ExitStack
from datetime import datetime, timezone
import importlib.util
import os
from pathlib import Path
import socket
import sys
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch


PROJECT_ROOT = Path(__file__).resolve().parents[2]
BACKEND_DIR = PROJECT_ROOT / "backend"
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


def _install_dependency_stubs(stack: ExitStack):
    """Provide minimal module stubs and attribute patches scoped to the provided ExitStack.

    Guarantees:
    - Newly created stub modules are tracked and removed on cleanup.
    - Pre-existing modules retain their exact object identity.
    - Added attributes on pre-existing modules are removed via delattr on cleanup.
    - Modified attributes on pre-existing modules are restored to their original values on cleanup.
    """
    if "bson" not in sys.modules:
        try:
            import bson  # noqa: F401
        except ImportError:
            bson_stub = ModuleType("bson")

            class ObjectId(str):
                def __new__(cls, value=None):
                    return super().__new__(cls, value or "650000000000000000000001")

            bson_stub.ObjectId = ObjectId
            sys.modules["bson"] = bson_stub
            stack.callback(lambda: sys.modules.pop("bson", None))
    else:
        bson_mod = sys.modules["bson"]
        if not hasattr(bson_mod, "ObjectId"):
            stack.enter_context(patch.object(bson_mod, "ObjectId", ObjectId, create=True))

    if "cloudinary" not in sys.modules:
        try:
            import cloudinary  # noqa: F401
            import cloudinary.uploader  # noqa: F401
        except ImportError:
            cloud_stub = ModuleType("cloudinary")
            cloud_stub.config = lambda **kwargs: None
            uploader_stub = ModuleType("cloudinary.uploader")
            uploader_stub.upload = lambda *args, **kwargs: {}
            cloud_stub.uploader = uploader_stub
            sys.modules["cloudinary"] = cloud_stub
            sys.modules["cloudinary.uploader"] = uploader_stub
            stack.callback(lambda: sys.modules.pop("cloudinary", None))
            stack.callback(lambda: sys.modules.pop("cloudinary.uploader", None))
    else:
        cloud_mod = sys.modules["cloudinary"]
        if not hasattr(cloud_mod, "config"):
            stack.enter_context(patch.object(cloud_mod, "config", lambda **kwargs: None, create=True))

    if "pydantic" not in sys.modules:
        try:
            import pydantic  # noqa: F401
        except ImportError:
            pydantic_stub = ModuleType("pydantic")

            class BaseModel:
                def __init__(self, **kwargs):
                    for key, val in type(self).__dict__.items():
                        if not key.startswith("_") and not callable(val):
                            setattr(self, key, copy.deepcopy(val))
                    for key, val in kwargs.items():
                        setattr(self, key, val)

                def dict(self):
                    return dict(self.__dict__)

            pydantic_stub.BaseModel = BaseModel
            sys.modules["pydantic"] = pydantic_stub
            stack.callback(lambda: sys.modules.pop("pydantic", None))
    else:
        pydantic_mod = sys.modules["pydantic"]
        if not hasattr(pydantic_mod, "BaseModel"):
            stack.enter_context(patch.object(pydantic_mod, "BaseModel", BaseModel, create=True))

    if "fastapi" not in sys.modules:
        try:
            import fastapi  # noqa: F401
        except ImportError:
            fastapi_stub = ModuleType("fastapi")

            class status:
                HTTP_200_OK = 200
                HTTP_400_BAD_REQUEST = 400
                HTTP_401_UNAUTHORIZED = 401
                HTTP_404_NOT_FOUND = 404
                HTTP_409_CONFLICT = 409
                HTTP_500_INTERNAL_SERVER_ERROR = 500
                HTTP_503_SERVICE_UNAVAILABLE = 503

            def Depends(dep=None):
                return dep

            def Query(default=None, **kwargs):
                return default

            def File(default=None, **kwargs):
                return default

            def Form(default=None, **kwargs):
                return default

            class UploadFile:
                pass

            class APIRouter:
                def __init__(self, prefix="", tags=None, dependencies=None):
                    self.prefix = prefix
                    self.tags = tags or []
                    self.dependencies = dependencies or []

                def get(self, path="", **kwargs):
                    return lambda func: func

                def post(self, path="", **kwargs):
                    return lambda func: func

                def put(self, path="", **kwargs):
                    return lambda func: func

                def delete(self, path="", **kwargs):
                    return lambda func: func

            fastapi_stub.APIRouter = APIRouter
            fastapi_stub.Depends = Depends
            fastapi_stub.HTTPException = HTTPException
            fastapi_stub.Query = Query
            fastapi_stub.File = File
            fastapi_stub.Form = Form
            fastapi_stub.UploadFile = UploadFile
            fastapi_stub.status = status
            sys.modules["fastapi"] = fastapi_stub
            stack.callback(lambda: sys.modules.pop("fastapi", None))
    else:
        fastapi_mod = sys.modules["fastapi"]
        if not hasattr(fastapi_mod, "Query"):
            stack.enter_context(patch.object(fastapi_mod, "Query", lambda default=None, **kwargs: default, create=True))
        if hasattr(fastapi_mod, "APIRouter"):
            if not hasattr(fastapi_mod.APIRouter, "put"):
                stack.enter_context(patch.object(fastapi_mod.APIRouter, "put", lambda self, *args, **kwargs: lambda func: func, create=True))
            if not hasattr(fastapi_mod.APIRouter, "delete"):
                stack.enter_context(patch.object(fastapi_mod.APIRouter, "delete", lambda self, *args, **kwargs: lambda func: func, create=True))
        if hasattr(fastapi_mod, "status"):
            for code_name, code_val in (
                ("HTTP_200_OK", 200),
                ("HTTP_400_BAD_REQUEST", 400),
                ("HTTP_401_UNAUTHORIZED", 401),
                ("HTTP_404_NOT_FOUND", 404),
                ("HTTP_409_CONFLICT", 409),
                ("HTTP_500_INTERNAL_SERVER_ERROR", 500),
                ("HTTP_503_SERVICE_UNAVAILABLE", 503),
            ):
                if not hasattr(fastapi_mod.status, code_name):
                    stack.enter_context(patch.object(fastapi_mod.status, code_name, code_val, create=True))


try:
    from bson import ObjectId  # noqa: E402
except ImportError:
    class ObjectId(str):  # noqa: E402
        def __new__(cls, value=None):
            return super().__new__(cls, value or "650000000000000000000001")

try:
    from fastapi import HTTPException  # noqa: E402
except ImportError:
    class HTTPException(Exception):  # noqa: E402
        def __init__(self, status_code: int = 500, detail=None, headers=None):
            super().__init__(detail)
            self.status_code = status_code
            self.detail = detail
            self.headers = headers

HAS_TESTCLIENT = False


class MemoryCursor:
    def __init__(self, items):
        self._items = list(items)

    def sort(self, key_or_list, direction=1):
        if isinstance(key_or_list, str):
            reverse = direction == -1
            def _sort_key(doc):
                val = doc.get(key_or_list)
                if val is None:
                    return (0, 0)
                if isinstance(val, datetime):
                    v_utc = val.replace(tzinfo=timezone.utc) if val.tzinfo is None else val
                    return (1, v_utc.timestamp())
                return (2, str(val))
            self._items.sort(key=_sort_key, reverse=reverse)
        return self

    def limit(self, count):
        if count is not None:
            self._items = self._items[:count]
        return self

    def __iter__(self):
        return iter(self._items)


class MemoryCollection:
    """Controlled in-memory collection supporting find/find_one/insert_one/update_one."""

    def __init__(self, initial_docs=None):
        self.documents = [copy.deepcopy(d) for d in (initial_docs or [])]

    def insert_one(self, document):
        stored = copy.deepcopy(document)
        if "_id" not in stored:
            stored["_id"] = ObjectId()
        self.documents.append(stored)
        return SimpleNamespace(inserted_id=stored["_id"])

    def find(self, query=None, projection=None):
        query = query or {}
        matched = [
            copy.deepcopy(doc)
            for doc in self.documents
            if self._matches(doc, query)
        ]
        return MemoryCursor(matched)

    def find_one(self, query=None, projection=None):
        for doc in self.find(query, projection):
            return doc
        return None

    def update_one(self, filter_query, update_doc, upsert=False):
        for idx, doc in enumerate(self.documents):
            if self._matches(doc, filter_query):
                updated = copy.deepcopy(doc)
                if "$set" in update_doc:
                    updated.update(copy.deepcopy(update_doc["$set"]))
                if "$inc" in update_doc:
                    for k, v in update_doc["$inc"].items():
                        updated[k] = updated.get(k, 0) + v
                self.documents[idx] = updated
                return SimpleNamespace(matched_count=1, modified_count=1)

        if upsert:
            new_doc = {
                k: copy.deepcopy(v)
                for k, v in filter_query.items()
                if not k.startswith("$") and not isinstance(v, dict)
            }
            if "_id" not in new_doc:
                new_doc["_id"] = ObjectId()
            if "$setOnInsert" in update_doc:
                new_doc.update(copy.deepcopy(update_doc["$setOnInsert"]))
            if "$set" in update_doc:
                new_doc.update(copy.deepcopy(update_doc["$set"]))
            if "$inc" in update_doc:
                for k, v in update_doc["$inc"].items():
                    new_doc[k] = new_doc.get(k, 0) + v
            self.documents.append(new_doc)
            return SimpleNamespace(matched_count=0, modified_count=0, upserted_id=new_doc["_id"])

        return SimpleNamespace(matched_count=0, modified_count=0)

    def _matches(self, doc, query):
        for key, expected in query.items():
            if key == "$and":
                if not all(self._matches(doc, sub) for sub in expected):
                    return False
            elif key == "$or":
                if not any(self._matches(doc, sub) for sub in expected):
                    return False
            else:
                actual = doc.get(key)
                if isinstance(expected, dict):
                    for op, bound in expected.items():
                        if op == "$gte":
                            if actual is None or not (actual >= bound):
                                return False
                        elif op == "$gt":
                            if actual is None or not (actual > bound):
                                return False
                        elif op == "$lte":
                            if actual is None or not (actual <= bound):
                                return False
                        elif op == "$lt":
                            if actual is None or not (actual < bound):
                                return False
                        elif op == "$ne":
                            if actual == bound:
                                return False
                        elif op == "$in":
                            if actual not in bound:
                                return False
                        else:
                            raise ValueError(f"Unsupported query operator in test fixture: {op}")
                else:
                    if actual != expected:
                        return False
        return True


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class WeeklyReportConsumedIntegrityTests(unittest.TestCase):
    def setUp(self):
        stack = ExitStack()
        self.addCleanup(stack.close)

        def forbidden(*args, **kwargs):
            raise AssertionError("External network/DB access is forbidden in N1 tests")

        original_connect = socket.socket.connect
        original_socketpair = socket.socketpair

        def guarded_connect(sock, address):
            if (
                sys._getframe(1).f_code
                is getattr(original_socketpair, "__code__", None)
                and address[0] in ("127.0.0.1", "::1")
            ):
                return original_connect(sock, address)
            return forbidden()

        stack.enter_context(patch.object(socket.socket, "connect", guarded_connect))
        stack.enter_context(patch.object(socket.socket, "connect_ex", forbidden))
        stack.enter_context(patch.object(socket, "create_connection", forbidden))
        stack.enter_context(patch.object(socket, "getaddrinfo", forbidden))

        stack.enter_context(patch.dict(sys.modules))
        _install_dependency_stubs(stack)
        for mod_name in list(sys.modules):
            if mod_name == "backend" or mod_name.startswith("backend."):
                del sys.modules[mod_name]

        for pkg_name, pkg_path in (
            ("backend", BACKEND_DIR),
            ("backend.app", BACKEND_DIR / "app"),
            ("backend.app.models", BACKEND_DIR / "app" / "models"),
            ("backend.app.repositories", BACKEND_DIR / "app" / "repositories"),
            ("backend.routers", BACKEND_DIR / "routers"),
            ("backend.services", BACKEND_DIR / "services"),
        ):
            pkg = ModuleType(pkg_name)
            pkg.__path__ = [str(pkg_path)]
            pkg.__package__ = pkg_name
            sys.modules[pkg_name] = pkg

        self.users_col = MemoryCollection()
        self.nutrition_col = MemoryCollection()
        self.story_logs_col = MemoryCollection()
        self.foods_col = MemoryCollection()
        self.water_col = MemoryCollection()
        self.user_foods_col = MemoryCollection()
        self.day_resets_col = MemoryCollection()

        self.db_dict = {
            "day_resets": self.day_resets_col,
            "users": self.users_col,
            "nutrition_plans": self.nutrition_col,
            "story_logs": self.story_logs_col,
            "foods": self.foods_col,
            "water_logs": self.water_col,
            "user_foods": self.user_foods_col,
        }

        db_module = ModuleType("backend.app.database")
        db_module.users_collection = self.users_col
        db_module.nutrition_collection = self.nutrition_col
        db_module.story_logs_collection = self.story_logs_col
        db_module.foods_collection = self.foods_col
        db_module.water_collection = self.water_col
        db_module.user_foods_collection = self.user_foods_col
        db_module.db = self.db_dict
        sys.modules["backend.app.database"] = db_module

        auth_utils_module = ModuleType("backend.auth_utils")

        def get_current_user():
            return self.active_user

        auth_utils_module.get_current_user = get_current_user
        sys.modules["backend.auth_utils"] = auth_utils_module

        user_repo_module = ModuleType("backend.app.repositories.user_repository")

        class StubUserRepository:
            def __init__(repo_self):
                repo_self.collection = self.users_col

            def get_by_email(repo_self, email: str):
                return self.users_col.find_one({"email": email})

        user_repo_module.UserRepository = StubUserRepository
        sys.modules["backend.app.repositories.user_repository"] = user_repo_module

        _load_module("backend.services.meal_generator", BACKEND_DIR / "services" / "meal_generator.py")
        self.nutrition_module = _load_module(
            "backend.routers.nutrition",
            BACKEND_DIR / "routers" / "nutrition.py",
        )

        self.user_a = {
            "_id": ObjectId("650000000000000000000001"),
            "email": "user_a@saman.test",
            "full_name": "User A",
            "health_stats": {
                "daily_calories": 2100,
                "target_protein": 120,
                "target_carbs": 230,
                "target_fat": 70,
                "water_target_ml": 2200,
            },
        }
        self.user_b = {
            "_id": ObjectId("650000000000000000000002"),
            "email": "user_b@saman.test",
            "full_name": "User B",
            "health_stats": {
                "daily_calories": 1800,
                "target_protein": 90,
                "target_carbs": 200,
                "target_fat": 60,
                "water_target_ml": 2000,
            },
        }
        self.users_col.insert_one(self.user_a)
        self.users_col.insert_one(self.user_b)
        self.active_user = self.user_a

        if HAS_TESTCLIENT:
            self.app = FastAPI()
            self.app.include_router(self.nutrition_module.router)
            self.app.dependency_overrides[get_current_user] = lambda: self.active_user
            self.client = TestClient(self.app)
        else:
            self.client = None

    def _call_weekly_report(self, start_date: str):
        if self.client is not None:
            resp = self.client.get("/api/nutrition/report/weekly", params={"start_date": start_date})
            return resp.status_code, resp.json()
        try:
            data = asyncio.run(
                self.nutrition_module.get_weekly_report(
                    start_date=start_date,
                    current_user=self.active_user,
                )
            )
            return 200, data
        except HTTPException as exc:
            return exc.status_code, {"detail": exc.detail}

    def _call_daily_summary(self, date_str: str):
        if self.client is not None:
            resp = self.client.get(f"/api/nutrition/{date_str}")
            return resp.status_code, resp.json()
        try:
            data = asyncio.run(
                self.nutrition_module.get_nutrition_by_date(
                    date=date_str,
                    current_user=self.active_user,
                )
            )
            return 200, data
        except HTTPException as exc:
            return exc.status_code, {"detail": exc.detail}

    def test_linked_nutrition_log_and_story_counted_once(self):
        """AC1: A 500 kcal nutrition log linked to a 500 kcal Story is counted once."""
        story_res = self.story_logs_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "meal_type": "lunch",
                "food_name": "Com ga nuong",
                "food_label": "com_ga_nuong",
                "grams": 300.0,
                "calories": 500.0,
                "protein": 35.0,
                "carbs": 50.0,
                "fat": 15.0,
                "note": "AI scan",
                "logged_at": "2026-10-12T12:15:00",
                "source": "story",
                "created_at": "2026-10-12T12:15:00",
            }
        )
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-12",
                "meal_type": "lunch",
                "foods": [
                    {
                        "name": "Com ga nuong",
                        "weight_grams": 300,
                        "calories": 500,
                        "protein": 35.0,
                        "carbs": 50.0,
                        "fat": 15.0,
                    }
                ],
                "total_calories": 500,
                "total_protein": 35.0,
                "total_carbs": 50.0,
                "total_fat": 15.0,
                "story_id": str(story_res.inserted_id),
                "created_at": datetime(2026, 10, 12, 12, 15, 1),
            }
        )

        status_w, weekly = self._call_weekly_report("2026-10-12")
        status_d, daily = self._call_daily_summary("2026-10-12")

        self.assertEqual(status_w, 200)
        self.assertEqual(status_d, 200)

        day_item = next(d for d in weekly["daily"] if d["date"] == "2026-10-12")
        self.assertEqual(day_item["calories"], 500.0)
        self.assertEqual(day_item["protein"], 35.0)
        self.assertEqual(day_item["carbs"], 50.0)
        self.assertEqual(day_item["fat"], 15.0)
        self.assertEqual(day_item["log_count"], 1)

        self.assertEqual(weekly["days_logged"], 1)
        self.assertEqual(
            weekly["weekly_totals"],
            {"calories": 500.0, "protein": 35.0, "carbs": 50.0, "fat": 15.0},
        )

        # Matches Daily Summary
        self.assertEqual(day_item["calories"], daily["total_calories"])
        self.assertEqual(day_item["protein"], daily["total_protein"])
        self.assertEqual(day_item["carbs"], daily["total_carbs"])
        self.assertEqual(day_item["fat"], daily["total_fat"])
        self.assertEqual(day_item["log_count"], len(daily["entries"]))

    def test_standalone_story_with_nutrition_fields_does_not_increase_consumed(self):
        """AC2: Standalone Story records (even with nutrition fields) do not increase consumed."""
        self.story_logs_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "meal_type": "dinner",
                "food_name": "Pho bo",
                "calories": 650.0,
                "protein": 40.0,
                "carbs": 75.0,
                "fat": 20.0,
                "logged_at": "2026-10-13T19:00:00",
                "source": "story",
            }
        )

        status_w, weekly = self._call_weekly_report("2026-10-12")
        status_d, daily = self._call_daily_summary("2026-10-13")

        self.assertEqual(status_w, 200)
        self.assertEqual(status_d, 200)

        day_item = next(d for d in weekly["daily"] if d["date"] == "2026-10-13")
        self.assertEqual(day_item["calories"], 0.0)
        self.assertEqual(day_item["protein"], 0.0)
        self.assertEqual(day_item["carbs"], 0.0)
        self.assertEqual(day_item["fat"], 0.0)
        self.assertEqual(day_item["log_count"], 0)
        self.assertEqual(weekly["days_logged"], 0)
        self.assertEqual(
            weekly["weekly_totals"],
            {"calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0},
        )
        self.assertEqual(daily["total_calories"], 0)
        self.assertEqual(len(daily["entries"]), 0)

    def test_two_identical_active_nutrition_logs_counted_twice(self):
        """AC3: Two identical intentional nutrition logs are counted twice."""
        for idx in range(2):
            self.nutrition_col.insert_one(
                {
                    "user_email": self.user_a["email"],
                    "date": "2026-10-14",
                    "meal_type": "snack",
                    "foods": [
                        {
                            "name": "Protein Shake",
                            "weight_grams": 250,
                            "calories": 220,
                            "protein": 30.0,
                            "carbs": 12.0,
                            "fat": 4.5,
                        }
                    ],
                    "total_calories": 220,
                    "total_protein": 30.0,
                    "total_carbs": 12.0,
                    "total_fat": 4.5,
                    "created_at": datetime(2026, 10, 14, 10 + idx, 0, 0),
                }
            )

        status_w, weekly = self._call_weekly_report("2026-10-12")
        status_d, daily = self._call_daily_summary("2026-10-14")

        self.assertEqual(status_w, 200)
        self.assertEqual(status_d, 200)

        day_item = next(d for d in weekly["daily"] if d["date"] == "2026-10-14")
        self.assertEqual(day_item["calories"], 440.0)
        self.assertEqual(day_item["protein"], 60.0)
        self.assertEqual(day_item["carbs"], 24.0)
        self.assertEqual(day_item["fat"], 9.0)
        self.assertEqual(day_item["log_count"], 2)

        self.assertEqual(day_item["calories"], daily["total_calories"])
        self.assertEqual(day_item["log_count"], len(daily["entries"]))

    def test_cross_user_isolation(self):
        """AC4: User B's logs never appear in User A's weekly report."""
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-12",
                "meal_type": "breakfast",
                "foods": [{"name": "Oats", "calories": 350, "protein": 15.0, "carbs": 55.0, "fat": 7.0}],
                "total_calories": 350,
                "total_protein": 15.0,
                "total_carbs": 55.0,
                "total_fat": 7.0,
                "created_at": datetime(2026, 10, 12, 7, 30, 0),
            }
        )
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_b["email"],
                "date": "2026-10-12",
                "meal_type": "lunch",
                "foods": [{"name": "Steak", "calories": 950, "protein": 70.0, "carbs": 40.0, "fat": 55.0}],
                "total_calories": 950,
                "total_protein": 70.0,
                "total_carbs": 40.0,
                "total_fat": 55.0,
                "created_at": datetime(2026, 10, 12, 12, 30, 0),
            }
        )
        self.story_logs_col.insert_one(
            {
                "user_email": self.user_b["email"],
                "meal_type": "lunch",
                "calories": 950.0,
                "protein": 70.0,
                "carbs": 40.0,
                "fat": 55.0,
                "logged_at": "2026-10-12T12:30:00",
            }
        )

        self.active_user = self.user_a
        status_w, weekly = self._call_weekly_report("2026-10-12")
        self.assertEqual(status_w, 200)
        self.assertEqual(
            weekly["weekly_totals"],
            {"calories": 350.0, "protein": 15.0, "carbs": 55.0, "fat": 7.0},
        )
        self.assertEqual(weekly["days_logged"], 1)

    def test_seven_days_range_empty_days_and_contract(self):
        """AC5 & AC8: Exactly 7 days returned, empty days have 0 totals, out-of-range excluded, contract preserved."""
        # Out-of-range before start_date (2026-10-11)
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-11",
                "meal_type": "dinner",
                "total_calories": 800,
                "total_protein": 40.0,
                "total_carbs": 80.0,
                "total_fat": 30.0,
                "foods": [],
                "created_at": datetime(2026, 10, 11, 19, 0, 0),
            }
        )
        # First day in range (2026-10-12)
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-12",
                "meal_type": "lunch",
                "total_calories": 700,
                "total_protein": 45.0,
                "total_carbs": 70.0,
                "total_fat": 22.0,
                "foods": [],
                "created_at": datetime(2026, 10, 12, 12, 0, 0),
            }
        )
        # Last day in range (2026-10-18)
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-18",
                "meal_type": "dinner",
                "total_calories": 700,
                "total_protein": 55.0,
                "total_carbs": 60.0,
                "total_fat": 25.0,
                "foods": [],
                "created_at": datetime(2026, 10, 18, 18, 0, 0),
            }
        )
        # Out-of-range after end_date (2026-10-19)
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-19",
                "meal_type": "breakfast",
                "total_calories": 900,
                "total_protein": 50.0,
                "total_carbs": 90.0,
                "total_fat": 35.0,
                "foods": [],
                "created_at": datetime(2026, 10, 19, 8, 0, 0),
            }
        )

        status_w, weekly = self._call_weekly_report("2026-10-12")
        self.assertEqual(status_w, 200)
        self.assertEqual(weekly["start_date"], "2026-10-12")
        self.assertEqual(weekly["end_date"], "2026-10-18")
        self.assertEqual(weekly["days_logged"], 2)
        self.assertEqual(len(weekly["daily"]), 7)

        expected_dates = [f"2026-10-{d}" for d in range(12, 19)]
        self.assertEqual([d["date"] for d in weekly["daily"]], expected_dates)

        for day_entry in weekly["daily"]:
            self.assertEqual(
                set(day_entry.keys()),
                {"date", "calories", "protein", "carbs", "fat", "log_count"},
            )
            if day_entry["date"] not in ("2026-10-12", "2026-10-18"):
                self.assertEqual(day_entry["calories"], 0.0)
                self.assertEqual(day_entry["protein"], 0.0)
                self.assertEqual(day_entry["carbs"], 0.0)
                self.assertEqual(day_entry["fat"], 0.0)
                self.assertEqual(day_entry["log_count"], 0)

        self.assertEqual(
            weekly["weekly_totals"],
            {"calories": 1400.0, "protein": 100.0, "carbs": 130.0, "fat": 47.0},
        )
        self.assertEqual(weekly["daily_average"], {"calories": 200.0})
        self.assertEqual(
            weekly["macro_targets"],
            {"calories": 2100, "protein": 120, "carbs": 230, "fat": 70},
        )

    def test_day_reset_matches_daily_summary_without_deleting_data(self):
        """AC6: With day_resets fixture, Weekly Report matches Daily Summary for every day."""
        # Day 2026-10-15: pre-reset log, exact-reset-timestamp log, and post-reset log
        reset_time_15 = datetime(2026, 10, 15, 12, 0, 0)
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-15",
                "meal_type": "breakfast",
                "foods": [{"name": "Pre-reset meal", "calories": 600, "protein": 30.0, "carbs": 60.0, "fat": 20.0}],
                "total_calories": 600,
                "total_protein": 30.0,
                "total_carbs": 60.0,
                "total_fat": 20.0,
                "created_at": datetime(2026, 10, 15, 8, 30, 0),
            }
        )
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-15",
                "meal_type": "lunch",
                "foods": [{"name": "Boundary meal", "calories": 300, "protein": 15.0, "carbs": 30.0, "fat": 10.0}],
                "total_calories": 300,
                "total_protein": 15.0,
                "total_carbs": 30.0,
                "total_fat": 10.0,
                "created_at": reset_time_15,
            }
        )
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-15",
                "meal_type": "dinner",
                "foods": [{"name": "Post-reset meal", "calories": 450, "protein": 35.0, "carbs": 42.0, "fat": 14.0}],
                "total_calories": 450,
                "total_protein": 35.0,
                "total_carbs": 42.0,
                "total_fat": 14.0,
                "created_at": datetime(2026, 10, 15, 18, 0, 0),
            }
        )
        self.day_resets_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-15",
                "reset_at": reset_time_15,
                "updated_at": reset_time_15,
            }
        )

        # Day 2026-10-16: pre-reset log only, then reset -> day becomes empty (0 kcal, 0 logs)
        reset_time_16 = datetime(2026, 10, 16, 15, 0, 0)
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-16",
                "meal_type": "lunch",
                "foods": [{"name": "Reset away meal", "calories": 520, "protein": 28.0, "carbs": 50.0, "fat": 18.0}],
                "total_calories": 520,
                "total_protein": 28.0,
                "total_carbs": 50.0,
                "total_fat": 18.0,
                "created_at": datetime(2026, 10, 16, 11, 0, 0),
            }
        )
        self.day_resets_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-16",
                "reset_at": reset_time_16,
                "updated_at": reset_time_16,
            }
        )

        status_w, weekly = self._call_weekly_report("2026-10-12")
        self.assertEqual(status_w, 200)

        # Underlying records are preserved (reset does not delete data)
        self.assertEqual(len(self.nutrition_col.documents), 4)

        for day_item in weekly["daily"]:
            status_d, daily = self._call_daily_summary(day_item["date"])
            self.assertEqual(status_d, 200)
            self.assertEqual(round(day_item["calories"]), daily["total_calories"])
            self.assertEqual(day_item["protein"], daily["total_protein"])
            self.assertEqual(day_item["carbs"], daily["total_carbs"])
            self.assertEqual(day_item["fat"], daily["total_fat"])
            self.assertEqual(day_item["log_count"], len(daily["entries"]))

        day_15 = next(d for d in weekly["daily"] if d["date"] == "2026-10-15")
        self.assertEqual(day_15["calories"], 450.0)
        self.assertEqual(day_15["log_count"], 1)

        day_16 = next(d for d in weekly["daily"] if d["date"] == "2026-10-16")
        self.assertEqual(day_16["calories"], 0.0)
        self.assertEqual(day_16["log_count"], 0)

        self.assertEqual(weekly["days_logged"], 1)
        self.assertEqual(
            weekly["weekly_totals"],
            {"calories": 450.0, "protein": 35.0, "carbs": 42.0, "fat": 14.0},
        )

    def test_missing_source_collection_fails_like_daily_summary(self):
        """AC7: Missing source collection must not return a 200 zero-total report when Daily Summary fails."""
        self.nutrition_module.nutrition_collection = None

        status_d, body_d = self._call_daily_summary("2026-10-12")
        status_w, body_w = self._call_weekly_report("2026-10-12")

        self.assertEqual(status_d, 503)
        self.assertEqual(status_w, 503)
        self.assertEqual(body_w.get("detail"), body_d.get("detail"))

    def test_created_at_null_and_missing_with_and_without_reset(self):
        """F-03: created_at null/missing with and without reset in Daily Summary and Weekly Report."""
        reset_time_15 = datetime(2026, 10, 15, 12, 0, 0)

        # Day 2026-10-15 (WITH RESET):
        # 1. created_at is explicitly None
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-15",
                "meal_type": "breakfast",
                "foods": [{"name": "Null timestamp meal", "calories": 400, "protein": 20.0, "carbs": 40.0, "fat": 10.0}],
                "total_calories": 400,
                "total_protein": 20.0,
                "total_carbs": 40.0,
                "total_fat": 10.0,
                "created_at": None,
            }
        )
        # 2. created_at key is missing entirely
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-15",
                "meal_type": "snack",
                "foods": [{"name": "Missing timestamp meal", "calories": 350, "protein": 15.0, "carbs": 35.0, "fat": 8.0}],
                "total_calories": 350,
                "total_protein": 15.0,
                "total_carbs": 35.0,
                "total_fat": 8.0,
            }
        )
        # 3. created_at valid before reset
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-15",
                "meal_type": "lunch",
                "foods": [{"name": "Pre-reset meal", "calories": 500, "protein": 25.0, "carbs": 50.0, "fat": 15.0}],
                "total_calories": 500,
                "total_protein": 25.0,
                "total_carbs": 50.0,
                "total_fat": 15.0,
                "created_at": datetime(2026, 10, 15, 9, 0, 0),
            }
        )
        # 4. created_at valid after reset
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-15",
                "meal_type": "dinner",
                "foods": [{"name": "Post-reset meal", "calories": 600, "protein": 30.0, "carbs": 60.0, "fat": 20.0}],
                "total_calories": 600,
                "total_protein": 30.0,
                "total_carbs": 60.0,
                "total_fat": 20.0,
                "created_at": datetime(2026, 10, 15, 15, 0, 0),
            }
        )
        # Reset doc for 2026-10-15
        self.day_resets_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-15",
                "reset_at": reset_time_15,
                "updated_at": reset_time_15,
            }
        )

        # Day 2026-10-16 (NO RESET):
        # 5. created_at is explicitly None
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-16",
                "meal_type": "breakfast",
                "foods": [{"name": "No-reset null timestamp meal", "calories": 250, "protein": 12.0, "carbs": 25.0, "fat": 6.0}],
                "total_calories": 250,
                "total_protein": 12.0,
                "total_carbs": 25.0,
                "total_fat": 6.0,
                "created_at": None,
            }
        )
        # 6. created_at key is missing entirely
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-16",
                "meal_type": "lunch",
                "foods": [{"name": "No-reset missing timestamp meal", "calories": 300, "protein": 15.0, "carbs": 30.0, "fat": 8.0}],
                "total_calories": 300,
                "total_protein": 15.0,
                "total_carbs": 30.0,
                "total_fat": 8.0,
            }
        )
        # 7. created_at valid
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-16",
                "meal_type": "dinner",
                "foods": [{"name": "No-reset valid meal", "calories": 450, "protein": 25.0, "carbs": 45.0, "fat": 12.0}],
                "total_calories": 450,
                "total_protein": 25.0,
                "total_carbs": 45.0,
                "total_fat": 12.0,
                "created_at": datetime(2026, 10, 16, 19, 0, 0),
            }
        )

        # Call Daily Summary on reset day (2026-10-15)
        status_d_15, daily_15 = self._call_daily_summary("2026-10-15")
        self.assertEqual(status_d_15, 200, f"Daily summary failed on reset day with error: {daily_15}")
        self.assertEqual(daily_15["total_calories"], 600.0)
        self.assertEqual(len(daily_15["entries"]), 1)
        self.assertEqual(daily_15["entries"][0]["food_name"], "Post-reset meal")

        # Call Daily Summary on no-reset day (2026-10-16)
        status_d_16, daily_16 = self._call_daily_summary("2026-10-16")
        self.assertEqual(status_d_16, 200, f"Daily summary failed on no-reset day with error: {daily_16}")
        self.assertEqual(daily_16["total_calories"], 1000.0)  # 250 + 300 + 450
        self.assertEqual(len(daily_16["entries"]), 3)

        # Call Weekly Report covering the week
        status_w, weekly = self._call_weekly_report("2026-10-12")
        self.assertEqual(status_w, 200, f"Weekly report failed with error: {weekly}")

        day_15 = next(d for d in weekly["daily"] if d["date"] == "2026-10-15")
        self.assertEqual(day_15["calories"], 600.0)
        self.assertEqual(day_15["log_count"], 1)

        day_16 = next(d for d in weekly["daily"] if d["date"] == "2026-10-16")
        self.assertEqual(day_16["calories"], 1000.0)
        self.assertEqual(day_16["log_count"], 3)

    def test_created_at_timezone_awareness_and_iso_format(self):
        """F-03: Naive vs Aware datetimes and ISO string timestamps compare safely without TypeError."""
        # Day 2026-10-17: reset_at is aware (UTC)
        reset_aware_17 = datetime(2026, 10, 17, 12, 0, 0, tzinfo=timezone.utc)
        self.day_resets_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-17",
                "reset_at": reset_aware_17,
                "updated_at": reset_aware_17,
            }
        )
        # Pre-reset meal with naive datetime (09:00:00) -> excluded
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-17",
                "meal_type": "breakfast",
                "foods": [{"name": "Pre-reset naive meal", "calories": 400, "protein": 20.0, "carbs": 40.0, "fat": 10.0}],
                "total_calories": 400,
                "total_protein": 20.0,
                "total_carbs": 40.0,
                "total_fat": 10.0,
                "created_at": datetime(2026, 10, 17, 9, 0, 0),
            }
        )
        # Post-reset meal with naive datetime (15:00:00) -> included
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-17",
                "meal_type": "lunch",
                "foods": [{"name": "Post-reset naive meal", "calories": 500, "protein": 25.0, "carbs": 50.0, "fat": 15.0}],
                "total_calories": 500,
                "total_protein": 25.0,
                "total_carbs": 50.0,
                "total_fat": 15.0,
                "created_at": datetime(2026, 10, 17, 15, 0, 0),
            }
        )
        # Post-reset meal with ISO string timestamp (18:00:00 UTC) -> included
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-17",
                "meal_type": "dinner",
                "foods": [{"name": "Post-reset ISO string meal", "calories": 350, "protein": 20.0, "carbs": 30.0, "fat": 10.0}],
                "total_calories": 350,
                "total_protein": 20.0,
                "total_carbs": 30.0,
                "total_fat": 10.0,
                "created_at": "2026-10-17T18:00:00Z",
            }
        )
        # Boundary meal (exact reset time naive) -> excluded
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-17",
                "meal_type": "snack",
                "foods": [{"name": "Boundary meal", "calories": 250, "protein": 10.0, "carbs": 25.0, "fat": 8.0}],
                "total_calories": 250,
                "total_protein": 10.0,
                "total_carbs": 25.0,
                "total_fat": 8.0,
                "created_at": datetime(2026, 10, 17, 12, 0, 0),
            }
        )

        # Day 2026-10-18: reset_at is naive, meals are aware
        reset_naive_18 = datetime(2026, 10, 18, 12, 0, 0)
        self.day_resets_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-18",
                "reset_at": reset_naive_18,
                "updated_at": reset_naive_18,
            }
        )
        # Post-reset meal with aware datetime (14:00:00 UTC) -> included
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-18",
                "meal_type": "lunch",
                "foods": [{"name": "Post-reset aware meal", "calories": 700, "protein": 40.0, "carbs": 70.0, "fat": 20.0}],
                "total_calories": 700,
                "total_protein": 40.0,
                "total_carbs": 70.0,
                "total_fat": 20.0,
                "created_at": datetime(2026, 10, 18, 14, 0, 0, tzinfo=timezone.utc),
            }
        )
        # Pre-reset meal with aware datetime (10:00:00 UTC) -> excluded
        self.nutrition_col.insert_one(
            {
                "user_email": self.user_a["email"],
                "date": "2026-10-18",
                "meal_type": "breakfast",
                "foods": [{"name": "Pre-reset aware meal", "calories": 300, "protein": 15.0, "carbs": 30.0, "fat": 8.0}],
                "total_calories": 300,
                "total_protein": 15.0,
                "total_carbs": 30.0,
                "total_fat": 8.0,
                "created_at": datetime(2026, 10, 18, 10, 0, 0, tzinfo=timezone.utc),
            }
        )

        # Verify Day 17 Daily Summary: 500 + 350 = 850 kcal, 2 entries
        status_d_17, daily_17 = self._call_daily_summary("2026-10-17")
        self.assertEqual(status_d_17, 200, f"Daily summary failed on Day 17: {daily_17}")
        self.assertEqual(daily_17["total_calories"], 850.0)
        self.assertEqual(len(daily_17["entries"]), 2)

        # Verify Day 18 Daily Summary: 700 kcal, 1 entry
        status_d_18, daily_18 = self._call_daily_summary("2026-10-18")
        self.assertEqual(status_d_18, 200, f"Daily summary failed on Day 18: {daily_18}")
        self.assertEqual(daily_18["total_calories"], 700.0)
        self.assertEqual(len(daily_18["entries"]), 1)

        # Verify Weekly Report consistency
        status_w, weekly = self._call_weekly_report("2026-10-12")
        self.assertEqual(status_w, 200, f"Weekly report failed: {weekly}")

        day_17 = next(d for d in weekly["daily"] if d["date"] == "2026-10-17")
        self.assertEqual(day_17["calories"], 850.0)
        self.assertEqual(day_17["log_count"], 2)

        day_18 = next(d for d in weekly["daily"] if d["date"] == "2026-10-18")
        self.assertEqual(day_18["calories"], 700.0)
        self.assertEqual(day_18["log_count"], 1)



if __name__ == "__main__":
    unittest.main()
