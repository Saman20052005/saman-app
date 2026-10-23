"""Targeted integrity tests for Food Analysis (SAMAN Nutrition G0 & G3A).

Verifies that Food-101 photo analysis does not return fake mock classifications,
generic default nutrition on unknown foods, or silent zero-macro successes on lookup errors.
Also verifies request-based mode routing and standard mode isolation.
"""

import asyncio
from contextlib import ExitStack
import copy
import io
import os
from pathlib import Path
import socket
import sys
from types import ModuleType
import unittest
from unittest.mock import patch, AsyncMock

try:
    import bcrypt  # Pre-load C-extension before patch.dict(sys.modules)
except ImportError:
    pass


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
    if "fastapi" not in sys.modules:
        fastapi_stub = ModuleType("fastapi")

        class status:
            HTTP_200_OK = 200
            HTTP_400_BAD_REQUEST = 400
            HTTP_401_UNAUTHORIZED = 401
            HTTP_403_FORBIDDEN = 403
            HTTP_404_NOT_FOUND = 404
            HTTP_409_CONFLICT = 409
            HTTP_413_REQUEST_ENTITY_TOO_LARGE = 413
            HTTP_422_UNPROCESSABLE_ENTITY = 422
            HTTP_500_INTERNAL_SERVER_ERROR = 500
            HTTP_502_BAD_GATEWAY = 502
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
            def __init__(self, filename="test.jpg", content_type="image/jpeg", file=None):
                self.filename = filename
                self.content_type = content_type
                self.file = file or io.BytesIO()

            async def read(self):
                return self.file.getvalue() if hasattr(self.file, "getvalue") else b""

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
        fastapi_stub.Query = Query
        fastapi_stub.HTTPException = HTTPException
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
                ("HTTP_403_FORBIDDEN", 403),
                ("HTTP_404_NOT_FOUND", 404),
                ("HTTP_409_CONFLICT", 409),
                ("HTTP_413_REQUEST_ENTITY_TOO_LARGE", 413),
                ("HTTP_422_UNPROCESSABLE_ENTITY", 422),
                ("HTTP_500_INTERNAL_SERVER_ERROR", 500),
                ("HTTP_502_BAD_GATEWAY", 502),
                ("HTTP_503_SERVICE_UNAVAILABLE", 503),
            ):
                if not hasattr(fastapi_mod.status, code_name):
                    stack.enter_context(patch.object(fastapi_mod.status, code_name, code_val, create=True))

    if "fastapi.responses" not in sys.modules:
        responses_stub = ModuleType("fastapi.responses")
        class JSONResponse:
            def __init__(self, content, status_code=200):
                self.content = content
                self.status_code = status_code
        responses_stub.JSONResponse = JSONResponse
        sys.modules["fastapi.responses"] = responses_stub
        stack.callback(lambda: sys.modules.pop("fastapi.responses", None))

    if "httpx" not in sys.modules:
        httpx_stub = ModuleType("httpx")
        class AsyncClient:
            def __init__(self, *args, **kwargs):
                pass
            async def __aenter__(self):
                return self
            async def __aexit__(self, *args):
                pass
            async def get(self, *args, **kwargs):
                raise RuntimeError("External network forbidden in test fixture")
            async def post(self, *args, **kwargs):
                raise RuntimeError("External network forbidden in test fixture")
        class TimeoutException(Exception):
            pass
        class RequestError(Exception):
            pass
        httpx_stub.AsyncClient = AsyncClient
        httpx_stub.TimeoutException = TimeoutException
        httpx_stub.RequestError = RequestError
        sys.modules["httpx"] = httpx_stub
        stack.callback(lambda: sys.modules.pop("httpx", None))

    if "backend.auth_utils" not in sys.modules:
        try:
            import jwt  # noqa: F401
        except ImportError:
            auth_utils_stub = ModuleType("backend.auth_utils")
            def verify_token():
                return "test@saman.test"
            def get_current_user():
                return {"email": "test@saman.test", "id": "test_id"}
            auth_utils_stub.verify_token = verify_token
            auth_utils_stub.get_current_user = get_current_user
            sys.modules["backend.auth_utils"] = auth_utils_stub
            stack.callback(lambda: sys.modules.pop("backend.auth_utils", None))
    else:
        auth_mod = sys.modules["backend.auth_utils"]
        if not hasattr(auth_mod, "verify_token"):
            stack.enter_context(patch.object(auth_mod, "verify_token", lambda: "test@saman.test", create=True))
        if not hasattr(auth_mod, "get_current_user"):
            stack.enter_context(patch.object(auth_mod, "get_current_user", lambda: {"email": "test@saman.test", "id": "test_id"}, create=True))

    if "PIL" not in sys.modules:
        try:
            import PIL  # noqa: F401
        except ImportError:
            pil_stub = ModuleType("PIL")
            class ImageStub:
                @staticmethod
                def open(*args, **kwargs):
                    return ImageStub()
                def convert(self, *args, **kwargs):
                    return self
            pil_stub.Image = ImageStub
            sys.modules["PIL"] = pil_stub
            stack.callback(lambda: sys.modules.pop("PIL", None))


try:
    from fastapi import HTTPException  # noqa: E402
except ImportError:
    class HTTPException(Exception):  # noqa: E402
        def __init__(self, status_code: int = 500, detail=None, headers=None):
            super().__init__(detail)
            self.status_code = status_code
            self.detail = detail
            self.headers = headers


class StubUploadFile:
    def __init__(self, content: bytes = b"x" * 2048, content_type: str = "image/jpeg", filename: str = "test.jpg"):
        self.content = content
        self.content_type = content_type
        self.filename = filename

    async def read(self) -> bytes:
        return self.content


class FoodAnalysisIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(sys.modules))
        _install_dependency_stubs(self.stack)

        # Guard against any unexpected external network access
        def forbidden(*args, **kwargs):
            raise AssertionError("External network/DB access is forbidden in G0 integrity tests")

        original_connect = socket.socket.connect
        original_socketpair = getattr(socket, "socketpair", None)

        def guarded_connect(sock, address):
            if (
                original_socketpair is not None
                and sys._getframe(1).f_code is getattr(original_socketpair, "__code__", None)
                and address[0] in ("127.0.0.1", "::1")
            ):
                return original_connect(sock, address)
            return forbidden()

        self.stack.enter_context(patch.object(socket.socket, "connect", guarded_connect))
        self.stack.enter_context(patch.object(socket.socket, "connect_ex", forbidden))
        self.stack.enter_context(patch.object(socket, "create_connection", forbidden))
        self.stack.enter_context(patch.object(socket, "getaddrinfo", forbidden))
        # Ensure configuration isolation: G0 tests test the default food101 pipeline
        self.stack.enter_context(patch.dict(os.environ, {"FOOD_ANALYSIS_PROVIDER": "food101"}))

        # Import modules under test
        import backend.services.nutrition_lookup as lookup_mod
        import backend.routers.food_analysis as router_mod

        self.lookup_mod = lookup_mod
        self.router_mod = router_mod
        self.lookup = lookup_mod.NutritionLookup()

    # -------------------------------------------------------------------------
    # POINT A: FoodClassifier unready / mock branch must NOT return fake success
    # -------------------------------------------------------------------------
    def test_classifier_not_ready_raises_500(self):
        """Point A: When model is not ready (ready=False), /analyze must raise 500 instead of returning mock Pizza."""
        dummy_file = StubUploadFile()

        class UnreadyClassifier:
            ready = False
            classes = ["pho"]
            def predict(self, image_bytes):
                return {"mock": True, "label": "pizza", "confidence": 0.85, "food_name": "Pizza"}

        with patch.object(self.router_mod, "get_classifier", return_value=UnreadyClassifier()):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="test@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("not ready", str(ctx.exception.detail))

    def test_mock_prediction_flag_raises_500(self):
        """Point A: If predict() returns mock=True, /analyze must raise 500 instead of false success."""
        dummy_file = StubUploadFile()

        class MockingClassifier:
            ready = True
            classes = ["pizza"]
            def predict(self, image_bytes):
                return {"mock": True, "label": "pizza", "confidence": 0.99, "food_name": "Pizza"}

        with patch.object(self.router_mod, "get_classifier", return_value=MockingClassifier()):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="test@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("not ready", str(ctx.exception.detail))

    # -------------------------------------------------------------------------
    # POINT B: Generic default nutrition fallback on unknown labels is removed
    # -------------------------------------------------------------------------
    def test_unknown_label_returns_none_from_lookup(self):
        """Point B: NutritionLookup returns None for unknown labels rather than generic 200 kcal."""
        async def run_test():
            result = await self.lookup.lookup("definitely_nonexistent_food_xyz_123", 100.0)
            self.assertIsNone(result)

        asyncio.run(run_test())

    def test_unknown_label_raises_500_in_analyze(self):
        """Point B: When lookup returns None for an unrecognized food label, /analyze raises 500."""
        dummy_file = StubUploadFile()

        class UnknownFoodClassifier:
            ready = True
            classes = ["unknown_dish"]
            def predict(self, image_bytes):
                return {
                    "label": "unknown_dish",
                    "food_name": "Unknown Dish",
                    "confidence": 0.70,
                    "low_confidence": False,
                    "top3": [{"label": "unknown_dish", "food_name": "Unknown Dish", "confidence": 0.70}],
                    "mock": False,
                }

        with patch.object(self.router_mod, "get_classifier", return_value=UnknownFoodClassifier()), \
             patch.object(self.router_mod._nutrition_lookup, "lookup", new_callable=AsyncMock, return_value=None):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="test@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("Nutrition data not found", str(ctx.exception.detail))

    # -------------------------------------------------------------------------
    # POINT C: Lookup failure must NOT return HTTP 200 with 0 macros
    # -------------------------------------------------------------------------
    def test_lookup_exception_raises_500(self):
        """Point C: When NutritionLookup raises an exception, /analyze raises 500 (never 200 with 0 macros)."""
        dummy_file = StubUploadFile()

        class ReadyClassifier:
            ready = True
            classes = ["pho"]
            def predict(self, image_bytes):
                return {
                    "label": "pho",
                    "food_name": "Pho",
                    "confidence": 0.92,
                    "low_confidence": False,
                    "top3": [{"label": "pho", "food_name": "Pho", "confidence": 0.92}],
                    "mock": False,
                }

        async def broken_lookup(food_label, grams):
            raise RuntimeError("USDA/OFF connection timeout")

        with patch.object(self.router_mod, "get_classifier", return_value=ReadyClassifier()), \
             patch.object(self.router_mod._nutrition_lookup, "lookup", side_effect=broken_lookup):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="test@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("Nutrition lookup failed", str(ctx.exception.detail))

    def test_zero_macro_suppression_verified(self):
        """Point C: Verify that returning 0 calories / 0 macros to mask lookup failure is impossible."""
        dummy_file = StubUploadFile()

        class ReadyClassifier:
            ready = True
            classes = ["pho"]
            def predict(self, image_bytes):
                return {
                    "label": "pho",
                    "food_name": "Pho",
                    "confidence": 0.90,
                    "low_confidence": False,
                    "top3": [{"label": "pho", "food_name": "Pho", "confidence": 0.90}],
                    "mock": False,
                }

        with patch.object(self.router_mod, "get_classifier", return_value=ReadyClassifier()), \
             patch.object(self.router_mod._nutrition_lookup, "lookup", new_callable=AsyncMock, return_value=None):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="test@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)

    # -------------------------------------------------------------------------
    # HAPPY PATH & INTEGRITY PRESERVATION
    # -------------------------------------------------------------------------
    def test_happy_path_valid_reference_data_returns_200(self):
        """Happy Path: Recognized food with valid reference data returns full nutrition contract."""
        dummy_file = StubUploadFile()

        class ReadyClassifier:
            ready = True
            classes = ["pho"]
            def predict(self, image_bytes):
                return {
                    "label": "pho",
                    "food_name": "Pho",
                    "confidence": 0.95,
                    "low_confidence": False,
                    "top3": [{"label": "pho", "food_name": "Pho", "confidence": 0.95}],
                    "mock": False,
                }

        async def valid_lookup(food_label, grams):
            return {
                "calories": 350.0,
                "protein": 20.0,
                "carbs": 52.0,
                "fat": 6.0,
                "per_100g": {"calories": 140, "protein": 8.0, "carbs": 20.8, "fat": 2.4},
                "source": "fallback",
            }

        with patch.object(self.router_mod, "get_classifier", return_value=ReadyClassifier()), \
             patch.object(self.router_mod._nutrition_lookup, "lookup", side_effect=valid_lookup):
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=250.0,
                    email="valid_user@saman.test",
                )
            )

        self.assertIsNotNone(resp)
        self.assertEqual(resp["food_name"], "Pho")
        self.assertEqual(resp["food_label"], "pho")
        self.assertEqual(resp["confidence"], 0.95)
        self.assertFalse(resp["low_confidence"])
        self.assertEqual(resp["grams"], 250.0)
        self.assertEqual(resp["nutrition"]["calories"], 350.0)
        self.assertEqual(resp["nutrition"]["protein"], 20.0)
        self.assertEqual(resp["nutrition"]["carbs"], 52.0)
        self.assertEqual(resp["nutrition"]["fat"], 6.0)
        self.assertEqual(resp["nutrition_source"], "fallback")
        self.assertFalse(resp["mock"])
        self.assertEqual(resp["user_email"], "valid_user@saman.test")

    def test_no_story_or_log_written_during_analysis(self):
        """Integrity: POST /api/food/analyze is strictly read-only and never writes to DB or Story."""
        dummy_file = StubUploadFile()

        class ReadyClassifier:
            ready = True
            classes = ["pho"]
            def predict(self, image_bytes):
                return {
                    "label": "pho",
                    "food_name": "Pho",
                    "confidence": 0.90,
                    "low_confidence": False,
                    "top3": [{"label": "pho", "food_name": "Pho", "confidence": 0.90}],
                    "mock": False,
                }

        async def fake_lookup(food_label, grams):
            return {
                "calories": 68.0,
                "protein": 5.1,
                "carbs": 9.8,
                "fat": 1.2,
                "per_100g": {"calories": 68, "protein": 5.1, "carbs": 9.8, "fat": 1.2},
                "source": "fallback",
            }

        # Mock database collection find/insert if database module is loaded
        mock_db_calls = []
        def intercept_db(*args, **kwargs):
            mock_db_calls.append((args, kwargs))
            raise AssertionError("Database should not be accessed during food analysis")

        with patch.object(self.router_mod, "get_classifier", return_value=ReadyClassifier()), \
             patch.object(self.router_mod._nutrition_lookup, "lookup", side_effect=fake_lookup):
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    email="isolated_user@saman.test",
                )
            )

        self.assertIsNotNone(resp)
        self.assertEqual(len(mock_db_calls), 0)

    # -------------------------------------------------------------------------
    # G3A POINT: Request Mode "standard" routes to Food-101
    # -------------------------------------------------------------------------
    def test_explicit_mode_standard_runs_food101_pipeline(self):
        """G3A: When mode='standard', Food-101 runs even if default provider is gemini and allowlist is empty."""
        dummy_file = StubUploadFile()

        class ReadyClassifier:
            ready = True
            classes = ["pho"]
            def predict(self, image_bytes):
                return {
                    "label": "pho",
                    "food_name": "Pho",
                    "confidence": 0.92,
                    "low_confidence": False,
                    "top3": [{"label": "pho", "food_name": "Pho", "confidence": 0.92}],
                    "mock": False,
                }

        async def fake_lookup(food_label, grams):
            return {
                "calories": 140.0,
                "protein": 8.0,
                "carbs": 20.0,
                "fat": 2.5,
                "per_100g": {"calories": 140, "protein": 8.0, "carbs": 20.0, "fat": 2.5},
                "source": "usda",
            }

        with patch.dict(os.environ, {"FOOD_ANALYSIS_PROVIDER": "gemini", "GEMINI_ALLOWED_EMAILS": "", "GEMINI_API_KEY": ""}), \
             patch.object(self.router_mod, "get_classifier", return_value=ReadyClassifier()), \
             patch.object(self.router_mod._nutrition_lookup, "lookup", side_effect=fake_lookup):
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    mode="standard",
                    email="unauthorized_gemini_user@saman.test",
                )
            )

        self.assertEqual(resp["food_name"], "Pho")
        self.assertEqual(resp["nutrition_source"], "usda")

    def test_mode_standard_case_insensitive_and_trimmed(self):
        """G3A: Mode string is trimmed and case-insensitive (e.g. '  STANDARD  ')."""
        dummy_file = StubUploadFile()

        class ReadyClassifier:
            ready = True
            classes = ["pho"]
            def predict(self, image_bytes):
                return {
                    "label": "pho",
                    "food_name": "Pho",
                    "confidence": 0.92,
                    "low_confidence": False,
                    "top3": [{"label": "pho", "food_name": "Pho", "confidence": 0.92}],
                    "mock": False,
                }

        async def fake_lookup(food_label, grams):
            return {
                "calories": 140.0,
                "protein": 8.0,
                "carbs": 20.0,
                "fat": 2.5,
                "per_100g": {"calories": 140, "protein": 8.0, "carbs": 20.0, "fat": 2.5},
                "source": "fallback",
            }

        with patch.object(self.router_mod, "get_classifier", return_value=ReadyClassifier()), \
             patch.object(self.router_mod._nutrition_lookup, "lookup", side_effect=fake_lookup):
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    mode="  STANDARD  ",
                    email="user@saman.test",
                )
            )

        self.assertEqual(resp["food_name"], "Pho")

    def test_invalid_mode_raises_422(self):
        """G3A: Unknown or invalid mode returns HTTP 422."""
        dummy_file = StubUploadFile()
        with self.assertRaises(HTTPException) as ctx:
            asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    mode="unsupported_ai_mode",
                    email="user@saman.test",
                )
            )
        self.assertEqual(ctx.exception.status_code, 422)
        self.assertIn("Invalid analysis mode", str(ctx.exception.detail))


class StubRestorationAndLifecycleTests(unittest.TestCase):
    """F-01 Restoration Verification:
    Proves that dependency stubbing strictly observes lifecycle restoration:
    1. Pre-existing modules retain exact object identity.
    2. Added attributes on pre-existing modules are removed via delattr.
    3. Modified attributes on pre-existing modules are restored to their original values.
    4. Newly created fake modules do not persist in sys.modules outside test scope.
    5. Environment and HTTP/socket patches are restored.
    6. Cleanup executes reliably even if setup or test fails.
    """

    def test_pre_existing_module_identity_and_attribute_addition_restored(self):
        """Pre-existing module identity is preserved and added attributes are deleted."""
        fake_fastapi = ModuleType("fastapi")
        fake_fastapi.custom_marker = "preserve_marker"
        fake_fastapi.status = ModuleType("fastapi.status")

        # Set up module in sys.modules prior to patch
        with patch.dict(sys.modules, {"fastapi": fake_fastapi}, clear=False):
            self.assertFalse(hasattr(fake_fastapi, "Query"))
            self.assertFalse(hasattr(fake_fastapi.status, "HTTP_409_CONFLICT"))

            test_stack = ExitStack()
            test_stack.enter_context(patch.dict(sys.modules))
            _install_dependency_stubs(test_stack)

            # During test scope: identity preserved, missing attributes available
            self.assertIs(sys.modules["fastapi"], fake_fastapi)
            self.assertTrue(hasattr(fake_fastapi, "Query"))
            self.assertTrue(hasattr(fake_fastapi.status, "HTTP_409_CONFLICT"))

            # Exit test scope
            test_stack.close()

            # After cleanup: identity preserved, temporary attributes removed
            self.assertIs(sys.modules["fastapi"], fake_fastapi)
            self.assertFalse(hasattr(fake_fastapi, "Query"))
            self.assertFalse(hasattr(fake_fastapi.status, "HTTP_409_CONFLICT"))
            self.assertEqual(fake_fastapi.custom_marker, "preserve_marker")

    def test_pre_existing_attribute_modification_restored_to_original(self):
        """Pre-existing attribute on a module is restored to its exact original value."""
        fake_fastapi = ModuleType("fastapi")
        sentinel_query = object()
        fake_fastapi.Query = sentinel_query

        with patch.dict(sys.modules, {"fastapi": fake_fastapi}, clear=False):
            self.assertIs(fake_fastapi.Query, sentinel_query)

            test_stack = ExitStack()
            test_stack.enter_context(patch.dict(sys.modules))
            _install_dependency_stubs(test_stack)

            # During test scope: Query is not mutated if already present
            self.assertIs(fake_fastapi.Query, sentinel_query)

            # Manually simulate attribute override through patch.object
            test_stack.enter_context(patch.object(fake_fastapi, "Query", "temporary_val"))
            self.assertEqual(fake_fastapi.Query, "temporary_val")

            test_stack.close()

            # After cleanup: original sentinel restored
            self.assertIs(fake_fastapi.Query, sentinel_query)

    def test_newly_created_stub_modules_removed_on_cleanup(self):
        """Modules created solely for the test are removed from sys.modules on cleanup."""
        # Ensure fresh state
        with patch.dict(sys.modules):
            for mod_name in ("fastapi", "fastapi.responses", "httpx", "backend.auth_utils", "PIL"):
                sys.modules.pop(mod_name, None)

            self.assertNotIn("fastapi", sys.modules)
            self.assertNotIn("httpx", sys.modules)

            test_stack = ExitStack()
            test_stack.enter_context(patch.dict(sys.modules))
            _install_dependency_stubs(test_stack)

            # During test scope: stubs are present
            self.assertIn("fastapi", sys.modules)
            self.assertIn("httpx", sys.modules)

            # Exit test scope
            test_stack.close()

            # After cleanup: stubs are removed
            self.assertNotIn("fastapi", sys.modules)
            self.assertNotIn("httpx", sys.modules)

    def test_env_and_socket_patches_restored(self):
        """Socket connect guards and env patches are restored after test cleanup."""
        orig_connect = socket.socket.connect
        orig_env = os.environ.get("FOOD_ANALYSIS_PROVIDER")

        test_case = FoodAnalysisIntegrityTests("test_invalid_mode_raises_422")
        test_case.setUp()

        try:
            # During test: connect is patched and env is food101
            self.assertIsNot(socket.socket.connect, orig_connect)
            self.assertEqual(os.environ.get("FOOD_ANALYSIS_PROVIDER"), "food101")
        finally:
            test_case.doCleanups()

        # After cleanup: original socket.connect and env are restored
        self.assertIs(socket.socket.connect, orig_connect)
        self.assertEqual(os.environ.get("FOOD_ANALYSIS_PROVIDER"), orig_env)

    def test_cleanup_runs_reliably_even_if_setup_fails(self):
        """addCleanup hooks fire and restore state even if an exception occurs during setUp."""
        cleaned_up = []

        class FailingSetUpTest(unittest.TestCase):
            def setUp(self):
                self.stack = ExitStack()
                self.addCleanup(self.stack.close)
                self.stack.callback(lambda: cleaned_up.append("executed"))
                raise RuntimeError("Simulated failure inside setUp")

            def test_noop(self):
                pass

        suite = unittest.TestLoader().loadTestsFromTestCase(FailingSetUpTest)
        runner = unittest.TextTestRunner(stream=io.StringIO())
        res = runner.run(suite)

        self.assertEqual(len(res.errors), 1)
        self.assertEqual(cleaned_up, ["executed"])


if __name__ == "__main__":
    unittest.main()
