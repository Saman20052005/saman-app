"""Register/login contract tests with no application startup or real persistence."""

import copy
import datetime
from contextlib import ExitStack
import importlib.util
import os
from pathlib import Path
import secrets
import socket
import sys
from types import ModuleType, SimpleNamespace
import unittest
from unittest.mock import patch

import dotenv
import jwt
import pymongo
from fastapi import FastAPI
from fastapi.testclient import TestClient


BACKEND = Path(__file__).resolve().parents[1]


class MemoryUsers:
    def __init__(self):
        self.documents = []

    def find_one(self, query):
        return next(
            (
                copy.deepcopy(document)
                for document in self.documents
                if all(document.get(key) == value for key, value in query.items())
            ),
            None,
        )

    def insert_one(self, document):
        stored = copy.deepcopy(document)
        stored["_id"] = f"fixture-user-{len(self.documents) + 1}"
        self.documents.append(stored)
        return SimpleNamespace(inserted_id=stored["_id"])


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


class AuthRegisterContractTests(unittest.TestCase):
    def setUp(self):
        stack = ExitStack()
        self.addCleanup(stack.close)
        self.blocked_attempts = []

        def forbidden(*args, **kwargs):
            self.blocked_attempts.append(True)
            raise AssertionError("External infrastructure access forbidden")

        original_connect = socket.socket.connect
        original_socketpair = socket.socketpair

        def guarded_connect(sock, address):
            # Windows asyncio needs socketpair's own ephemeral loopback connection.
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
        stack.enter_context(patch.object(pymongo, "MongoClient", forbidden))
        self.dotenv_loader = stack.enter_context(
            patch.object(dotenv, "load_dotenv", return_value=False)
        )
        stack.enter_context(patch.object(dotenv.main, "DotEnv", forbidden))

        self.secret = secrets.token_urlsafe(48)
        stack.enter_context(
            patch.dict(
                os.environ,
                {
                    "JWT_SECRET": self.secret,
                    "JWT_SECRET_KEY": secrets.token_urlsafe(48),
                    "JWT_ALGORITHM": "HS256",
                },
                clear=True,
            )
        )
        stack.enter_context(patch.dict(sys.modules))
        for name in list(sys.modules):
            if name == "backend" or name.startswith("backend."):
                del sys.modules[name]
        for name, path in (
            ("backend", BACKEND),
            ("backend.app", BACKEND / "app"),
            ("backend.app.models", BACKEND / "app" / "models"),
            ("backend.auth", BACKEND / "auth"),
        ):
            package = ModuleType(name)
            package.__path__ = [str(path)]
            package.__package__ = name
            sys.modules[name] = package

        self.users = MemoryUsers()
        self.database = ModuleType("backend.app.database")
        self.database.users_collection = self.users
        self.database.db = {"otps": MemoryUsers()}
        sys.modules[self.database.__name__] = self.database
        load_module(
            "backend.app.models.common", BACKEND / "app" / "models" / "common.py"
        )
        self.models = load_module(
            "backend.app.models.user", BACKEND / "app" / "models" / "user.py"
        )
        self.config = load_module("backend.auth.config", BACKEND / "auth" / "config.py")
        self.auth_utils = load_module("backend.auth_utils", BACKEND / "auth_utils.py")
        self.auth = load_module("_cp7_test_auth_router", BACKEND / "routers" / "auth.py")
        app = FastAPI()
        app.include_router(self.auth.router)
        self.client = stack.enter_context(TestClient(app))
        self.password = secrets.token_urlsafe(24)
        self.email = "cp7-contract@example.com"

    def tearDown(self):
        self.assertEqual(len(self.blocked_attempts), 0)

    def register(self, **extra):
        return self.client.post(
            "/api/auth/register",
            json={"email": self.email, "password": self.password, **extra},
        )

    def seed_user(self, full_name="CP7 Contract"):
        self.users.insert_one(
            {
                "email": self.email,
                "password": self.auth_utils.hash_password(self.password),
                "full_name": full_name,
                "auth_provider": "local",
                "created_at": datetime.datetime.now(datetime.timezone.utc),
            }
        )

    def assert_registered(self, response, full_name):
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"message": "User registered successfully"})
        self.assertEqual(len(self.users.documents), 1)
        document = self.users.find_one({"email": self.email})
        self.assertEqual(
            set(document),
            {"_id", "email", "password", "full_name", "auth_provider", "created_at"},
        )
        self.assertEqual(document["full_name"], full_name)
        self.assertEqual(document["auth_provider"], "local")
        self.assertIsInstance(document["created_at"], datetime.datetime)
        self.assertTrue(document["password"] != self.password)
        self.assertTrue(
            self.auth_utils.verify_password(self.password, document["password"])
        )
        self.assertTrue(self.password not in repr(document))
        response = self.client.post(
            "/api/auth/login",
            json={"email": self.email, "password": self.password},
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["user_info"]["full_name"], full_name)

    def test_isolation_uses_full_source_and_real_auth_config(self):
        self.assertEqual(
            Path(self.auth.__file__).resolve(), BACKEND / "routers" / "auth.py"
        )
        self.assertIs(sys.modules["backend.app.database"], self.database)
        self.assertIs(self.auth.users_collection, self.users)
        self.assertNotIn("backend.main", sys.modules)
        self.assertNotIn("backend.routers", sys.modules)
        self.assertTrue(self.config.JWT_SECRET == self.secret)
        self.assertTrue(self.auth.SECRET_KEY == self.secret)
        self.assertEqual(self.config.JWT_ALGORITHM, "HS256")
        self.dotenv_loader.assert_called_once_with()
        self.assertEqual(set(self.models.UserAuth.model_fields), {"email", "password"})

    def test_register_frontend_payload_stores_name_and_bcrypt_hash(self):
        self.assert_registered(
            self.register(full_name="CP7 Contract", phone="000"),
            "CP7 Contract",
        )

    def test_register_missing_full_name_stores_none(self):
        self.assert_registered(self.register(), None)

    def test_register_null_full_name_stores_none(self):
        self.assert_registered(self.register(full_name=None), None)

    def test_register_empty_full_name_stores_empty_string(self):
        self.assert_registered(self.register(full_name=""), "")

    def test_register_one_character_full_name_has_no_new_length_constraint(self):
        self.assert_registered(self.register(full_name="A"), "A")

    def test_login_email_password_returns_name_and_verified_owner_jwt(self):
        self.seed_user()
        before_documents = copy.deepcopy(self.users.documents)
        before_time = datetime.datetime.now(datetime.timezone.utc).timestamp()
        response = self.client.post(
            "/api/auth/login",
            json={"email": self.email, "password": self.password},
        )
        after_time = datetime.datetime.now(datetime.timezone.utc).timestamp()
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(set(data), {"access_token", "token_type", "user_info"})
        self.assertEqual(data["token_type"], "bearer")
        self.assertEqual(
            data["user_info"], {"email": self.email, "full_name": "CP7 Contract"}
        )
        payload = jwt.decode(data["access_token"], self.secret, algorithms=["HS256"])
        self.assertEqual(set(payload), {"email", "exp"})
        self.assertEqual(payload["email"], self.email)
        week = datetime.timedelta(days=7).total_seconds()
        self.assertGreaterEqual(payload["exp"], before_time + week - 1)
        self.assertLessEqual(payload["exp"], after_time + week)
        self.assertTrue(self.users.documents == before_documents)

    def test_login_ignores_extra_full_name_even_invalid_register_values(self):
        self.seed_user()
        before_documents = copy.deepcopy(self.users.documents)
        for name in ({"invalid": "name"}, ["invalid"], 123):
            with self.subTest(full_name=name):
                response = self.client.post(
                    "/api/auth/login",
                    json={
                        "email": self.email,
                        "password": self.password,
                        "full_name": name,
                    },
                )
                self.assertEqual(response.status_code, 200)
                self.assertEqual(
                    response.json()["user_info"]["full_name"], "CP7 Contract"
                )
        self.assertTrue(self.users.documents == before_documents)

    def test_duplicate_email_returns_400_without_another_insert(self):
        self.seed_user()
        before_documents = copy.deepcopy(self.users.documents)
        response = self.register(full_name="Replacement")
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json(), {"detail": "Email already exists"})
        self.assertTrue(self.users.documents == before_documents)

    def test_wrong_password_returns_401_without_writes(self):
        self.seed_user()
        before_documents = copy.deepcopy(self.users.documents)
        response = self.client.post(
            "/api/auth/login",
            json={"email": self.email, "password": secrets.token_urlsafe(24)},
        )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json(), {"detail": "Invalid email or password"})
        self.assertTrue(self.users.documents == before_documents)

    def test_unknown_login_returns_401_without_writes(self):
        response = self.client.post(
            "/api/auth/login",
            json={"email": self.email, "password": self.password},
        )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json(), {"detail": "Invalid email or password"})
        self.assertEqual(len(self.users.documents), 0)

    def test_short_password_still_returns_422_without_inserts(self):
        for route in ("register", "login"):
            with self.subTest(route=route):
                response = self.client.post(
                    f"/api/auth/{route}",
                    json={
                        "email": self.email,
                        "password": self.password[:7],
                        "full_name": "CP7 Contract",
                    },
                )
                self.assertEqual(response.status_code, 422)
                self.assertEqual(
                    response.json()["detail"][0]["loc"], ["body", "password"]
                )
        self.assertEqual(len(self.users.documents), 0)

    def test_invalid_email_still_returns_422_without_inserts(self):
        for route in ("register", "login"):
            for email in ("invalid-email", "cp7-contract@saman.local"):
                with self.subTest(route=route, email=email):
                    response = self.client.post(
                        f"/api/auth/{route}",
                        json={
                            "email": email,
                            "password": self.password,
                            "full_name": "CP7 Contract",
                        },
                    )
                    self.assertEqual(response.status_code, 422)
                    self.assertEqual(
                        response.json()["detail"][0]["loc"], ["body", "email"]
                    )
        self.assertEqual(len(self.users.documents), 0)

    def test_invalid_register_full_name_returns_422_without_inserts(self):
        response = self.register(full_name={"invalid": "name"})
        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.json()["detail"][0]["loc"], ["body", "full_name"])
        self.assertEqual(len(self.users.documents), 0)


if __name__ == "__main__":
    unittest.main()
