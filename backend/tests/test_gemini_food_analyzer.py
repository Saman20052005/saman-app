"""Targeted tests for Gemini Food Analyzer (SAMAN Nutrition G1 & G3A).

Verifies internal Gemini integration, provider selection, contract preservation,
macro scaling by grams, robust error rejection, zero database mutations,
request-based mode routing, and strict identity-based internal permission checking.
"""

import asyncio
from contextlib import ExitStack
import copy
import io
import json
import os
from pathlib import Path
import socket
import sys
from types import ModuleType
import unittest
from unittest.mock import patch, AsyncMock, MagicMock

try:
    import bcrypt  # Pre-load C-extension before patch.dict(sys.modules)
except ImportError:
    pass


PROJECT_ROOT = Path(__file__).resolve().parents[2]
BACKEND_DIR = PROJECT_ROOT / "backend"
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))


class _StubTimeoutException(Exception):
    pass


class _StubRequestError(Exception):
    pass


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

        def Query(default=None, **kwargs):
            return default

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
        httpx_stub.AsyncClient = AsyncClient
        httpx_stub.TimeoutException = _StubTimeoutException
        httpx_stub.RequestError = _StubRequestError
        sys.modules["httpx"] = httpx_stub
        stack.callback(lambda: sys.modules.pop("httpx", None))
    else:
        httpx_mod = sys.modules["httpx"]
        if not hasattr(httpx_mod, "TimeoutException"):
            stack.enter_context(patch.object(httpx_mod, "TimeoutException", _StubTimeoutException, create=True))
        if not hasattr(httpx_mod, "RequestError"):
            stack.enter_context(patch.object(httpx_mod, "RequestError", _StubRequestError, create=True))

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

try:
    import httpx  # noqa: E402
except ImportError:
    class StubHttpx(ModuleType):
        TimeoutException = _StubTimeoutException
        RequestError = _StubRequestError
        class AsyncClient:
            def __init__(self, *args, **kwargs):
                pass
            async def __aenter__(self):
                return self
            async def __aexit__(self, *args):
                pass
            async def post(self, *args, **kwargs):
                raise RuntimeError("External network forbidden in test fixture")
    httpx = StubHttpx("httpx")

try:
    from backend.services.gemini_food_analyzer import (  # noqa: E402
        GeminiFoodAnalyzer,
        GeminiConfigurationError,
        GeminiAnalysisError,
    )
except (ImportError, AttributeError):
    GeminiFoodAnalyzer = None
    GeminiConfigurationError = None
    GeminiAnalysisError = None

router_mod = None


class StubUploadFile:
    def __init__(self, content: bytes = b"x" * 2048, content_type: str = "image/jpeg", filename: str = "test.jpg"):
        self.content = content
        self.content_type = content_type
        self.filename = filename

    async def read(self) -> bytes:
        return self.content


def _build_gemini_raw_response(structured_dict: dict, finish_reason: str = "STOP", status_code: int = 200):
    """Build a mock httpx.Response object returning Gemini REST response format."""
    mock_resp = MagicMock()
    mock_resp.status_code = status_code
    if status_code == 200:
        data = {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"text": json.dumps(structured_dict)}
                        ],
                        "role": "model",
                    },
                    "finishReason": finish_reason,
                }
            ]
        }
    else:
        data = {"error": {"message": f"Error {status_code}"}}
    mock_resp.json = MagicMock(return_value=data)
    return mock_resp


class GeminiFoodAnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(sys.modules))
        _install_dependency_stubs(self.stack)

        import backend.services.gemini_food_analyzer as gemini_service
        import backend.routers.food_analysis as router_mod_loaded
        self.router_mod = router_mod_loaded
        global router_mod, GeminiFoodAnalyzer, GeminiConfigurationError, GeminiAnalysisError
        router_mod = router_mod_loaded
        GeminiFoodAnalyzer = gemini_service.GeminiFoodAnalyzer
        GeminiConfigurationError = gemini_service.GeminiConfigurationError
        GeminiAnalysisError = gemini_service.GeminiAnalysisError

        # Block any accidental real external network requests
        def forbidden(*args, **kwargs):
            raise AssertionError("External network access is forbidden in G1 unit tests")

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

        # Default isolated environment for Gemini with authorized test emails
        self.env_patch = {
            "FOOD_ANALYSIS_PROVIDER": "gemini",
            "GEMINI_API_KEY": "test_mock_api_key_12345",
            "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
            "GEMINI_FOOD_TIMEOUT": "10.0",
            "GEMINI_ALLOWED_EMAILS": "user@saman.test,authorized@saman.test,isolated_gemini@saman.test,chef@saman.test",
        }
        self.stack.enter_context(patch.dict(os.environ, self.env_patch))

        self.router_mod = router_mod

    # -------------------------------------------------------------------------
    # 1. PROVIDER SELECTION & ISOLATION
    # -------------------------------------------------------------------------
    def test_default_provider_is_food101(self):
        """AC1: When FOOD_ANALYSIS_PROVIDER is unset or empty, default is food101."""
        with patch.dict(os.environ, {"FOOD_ANALYSIS_PROVIDER": ""}, clear=False):
            provider = self.router_mod.get_analysis_provider()
            self.assertEqual(provider, "food101")

        with patch.dict(os.environ, {}, clear=True):
            provider = self.router_mod.get_analysis_provider()
            self.assertEqual(provider, "food101")

    def test_invalid_provider_raises_500(self):
        """AC1: Invalid FOOD_ANALYSIS_PROVIDER must raise HTTP 500 and not silently fallback."""
        dummy_file = StubUploadFile()
        with patch.dict(os.environ, {"FOOD_ANALYSIS_PROVIDER": "unsupported_provider"}):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("Invalid FOOD_ANALYSIS_PROVIDER", str(ctx.exception.detail))

    def test_provider_gemini_does_not_call_get_classifier(self):
        """AC3: When provider is gemini, FoodClassifier is never called or loaded."""
        dummy_file = StubUploadFile()

        structured = {
            "is_food": True,
            "food_name": "Phở Bò",
            "food_label": "pho_bo",
            "confidence": 0.91,
            "per_100g": {"calories": 68.0, "protein": 5.1, "carbs": 9.8, "fat": 1.2},
        }
        mock_resp = _build_gemini_raw_response(structured)

        with patch.object(self.router_mod, "get_classifier") as mock_get_classifier, \
             patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    email="user@saman.test",
                )
            )
            self.assertEqual(resp["food_name"], "Phở Bò")
            mock_get_classifier.assert_not_called()

    def test_provider_food101_does_not_require_gemini_keys(self):
        """AC2: When provider is food101, no Gemini API key or model is needed."""
        dummy_file = StubUploadFile()

        class ReadyClassifier:
            ready = True
            classes = ["pho"]
            def predict(self, b):
                return {
                    "label": "pho",
                    "food_name": "Pho",
                    "confidence": 0.95,
                    "low_confidence": False,
                    "top3": [{"label": "pho", "food_name": "Pho", "confidence": 0.95}],
                    "mock": False,
                }

        async def fake_lookup(food_label, grams):
            return {
                "calories": 68.0, "protein": 5.1, "carbs": 9.8, "fat": 1.2,
                "per_100g": {"calories": 68, "protein": 5.1, "carbs": 9.8, "fat": 1.2},
                "source": "fallback",
            }

        # Clear any Gemini environment variables
        with patch.dict(os.environ, {"FOOD_ANALYSIS_PROVIDER": "food101", "GEMINI_API_KEY": "", "GEMINI_FOOD_MODEL": ""}), \
             patch.object(self.router_mod, "get_classifier", return_value=ReadyClassifier()), \
             patch.object(self.router_mod._nutrition_lookup, "lookup", side_effect=fake_lookup):
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    email="user@saman.test",
                )
            )
            self.assertEqual(resp["food_name"], "Pho")
            self.assertEqual(resp["nutrition_source"], "fallback")

    # -------------------------------------------------------------------------
    # 2. CONFIGURATION VALIDATION
    # -------------------------------------------------------------------------
    def test_missing_gemini_api_key_raises_500(self):
        """AC6: When provider is gemini but GEMINI_API_KEY is missing, raise HTTP 500."""
        dummy_file = StubUploadFile()
        with patch.dict(os.environ, {"GEMINI_API_KEY": ""}):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("GEMINI_API_KEY", str(ctx.exception.detail))

    def test_missing_gemini_food_model_raises_500(self):
        """AC6: When provider is gemini but GEMINI_FOOD_MODEL is missing, raise HTTP 500."""
        dummy_file = StubUploadFile()
        with patch.dict(os.environ, {"GEMINI_FOOD_MODEL": ""}):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("GEMINI_FOOD_MODEL", str(ctx.exception.detail))

    # -------------------------------------------------------------------------
    # 3. SCHEMA PRESERVATION & SUCCESS RESPONSE
    # -------------------------------------------------------------------------
    def test_gemini_valid_analysis_preserves_full_contract(self):
        """AC4: Valid Gemini analysis preserves exact AIAnalysisResult contract and gemini_estimate source."""
        dummy_file = StubUploadFile()

        structured = {
            "is_food": True,
            "food_name": "Phở Bò Tái",
            "food_label": "pho_bo_tai",
            "confidence": 0.94,
            "per_100g": {"calories": 130.0, "protein": 9.2, "carbs": 18.5, "fat": 2.4},
        }
        mock_resp = _build_gemini_raw_response(structured)

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    email="chef@saman.test",
                )
            )

        self.assertEqual(resp["food_name"], "Phở Bò Tái")
        self.assertEqual(resp["food_label"], "pho_bo_tai")
        self.assertEqual(resp["detected_food_name"], "Phở Bò Tái")
        self.assertEqual(resp["confidence"], 0.94)
        self.assertFalse(resp["low_confidence"])
        self.assertEqual(resp["grams"], 100.0)
        self.assertEqual(resp["nutrition"]["calories"], 130.0)
        self.assertEqual(resp["nutrition"]["protein"], 9.2)
        self.assertEqual(resp["nutrition"]["carbs"], 18.5)
        self.assertEqual(resp["nutrition"]["fat"], 2.4)
        self.assertEqual(resp["per_100g"]["calories"], 130.0)
        self.assertEqual(resp["per_100g"]["protein"], 9.2)
        self.assertEqual(resp["per_100g"]["carbs"], 18.5)
        self.assertEqual(resp["per_100g"]["fat"], 2.4)
        self.assertEqual(resp["nutrition_source"], "gemini_estimate")
        self.assertEqual(len(resp["top3_predictions"]), 1)
        self.assertEqual(resp["top3_predictions"][0]["label"], "pho_bo_tai")
        self.assertFalse(resp["mock"])
        self.assertEqual(resp["user_email"], "chef@saman.test")
        self.assertEqual(resp["temp_id"], "")
        self.assertEqual(resp["image_url"], "")

    # -------------------------------------------------------------------------
    # 4. MACRO SCALING BY GRAMS
    # -------------------------------------------------------------------------
    def test_gemini_nutrition_scales_linearly_with_grams(self):
        """AC5: Nutritional values scale strictly by (grams / 100.0)."""
        analyzer = GeminiFoodAnalyzer(api_key="mock_key", model="gemini-3.8-flash")

        structured = {
            "is_food": True,
            "food_name": "Ức Gà Áp Chảo",
            "food_label": "uc_ga_ap_chao",
            "confidence": 0.88,
            "per_100g": {"calories": 165.0, "protein": 31.0, "carbs": 0.0, "fat": 3.6},
        }
        mock_resp = _build_gemini_raw_response(structured)

        # 250 grams -> 2.5x
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            res_250 = asyncio.run(analyzer.analyze(b"fake_image_bytes" * 50, grams=250.0))

        self.assertEqual(res_250["grams"], 250.0)
        self.assertAlmostEqual(res_250["nutrition"]["calories"], 412.5, places=1)
        self.assertAlmostEqual(res_250["nutrition"]["protein"], 77.5, places=1)
        self.assertAlmostEqual(res_250["nutrition"]["carbs"], 0.0, places=1)
        self.assertAlmostEqual(res_250["nutrition"]["fat"], 9.0, places=1)

        # per_100g remains unscaled baseline
        self.assertEqual(res_250["per_100g"]["calories"], 165.0)
        self.assertEqual(res_250["per_100g"]["protein"], 31.0)
        self.assertEqual(res_250["per_100g"]["fat"], 3.6)

    # -------------------------------------------------------------------------
    # 5. CONFIDENCE PASS-THROUGH & LOW CONFIDENCE FLAG
    # -------------------------------------------------------------------------
    def test_gemini_confidence_score_and_low_confidence_flag(self):
        """AC4: Confidence score passed through cleanly; low_confidence flag set when < 0.40."""
        analyzer = GeminiFoodAnalyzer(api_key="mock_key", model="gemini-3.8-flash")

        structured = {
            "is_food": True,
            "food_name": "Bánh Mì",
            "food_label": "banh_mi",
            "confidence": 0.32,  # Low confidence
            "per_100g": {"calories": 250.0, "protein": 9.0, "carbs": 40.0, "fat": 6.0},
        }
        mock_resp = _build_gemini_raw_response(structured)

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            res = asyncio.run(analyzer.analyze(b"fake_image_bytes" * 50, grams=100.0))

        self.assertEqual(res["confidence"], 0.32)
        self.assertTrue(res["low_confidence"])

    # -------------------------------------------------------------------------
    # 6. ERROR REJECTION (NO FALSE SUCCESS, NO LEAKING SECRETS)
    # -------------------------------------------------------------------------
    def test_gemini_image_not_food_raises_500(self):
        """AC6: If image is not food (is_food=False), raise HTTP 500."""
        dummy_file = StubUploadFile()
        structured = {
            "is_food": False,
            "food_name": "",
            "food_label": "",
            "confidence": 0.0,
            "per_100g": {"calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0},
        }
        mock_resp = _build_gemini_raw_response(structured)

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("recognizable food", str(ctx.exception.detail))

    def test_gemini_empty_food_name_raises_500(self):
        """AC6: Empty food name is rejected with HTTP 500."""
        dummy_file = StubUploadFile()
        structured = {
            "is_food": True,
            "food_name": "   ",
            "food_label": "empty",
            "confidence": 0.90,
            "per_100g": {"calories": 100.0, "protein": 5.0, "carbs": 10.0, "fat": 2.0},
        }
        mock_resp = _build_gemini_raw_response(structured)

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)

    def test_gemini_negative_macro_raises_500(self):
        """AC6: Negative nutritional values are rejected with HTTP 500."""
        dummy_file = StubUploadFile()
        structured = {
            "is_food": True,
            "food_name": "Corrupted Food",
            "food_label": "corrupted",
            "confidence": 0.85,
            "per_100g": {"calories": -100.0, "protein": 5.0, "carbs": 10.0, "fat": 2.0},
        }
        mock_resp = _build_gemini_raw_response(structured)

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("Invalid nutrition value", str(ctx.exception.detail))

    def test_gemini_boolean_confidence_rejected(self):
        """F-04: Boolean confidence values (True/False) must be rejected with HTTP 500."""
        dummy_file = StubUploadFile()
        for bool_val in (True, False):
            structured = {
                "is_food": True,
                "food_name": "Test Dish",
                "food_label": "test_dish",
                "confidence": bool_val,
                "per_100g": {"calories": 100.0, "protein": 5.0, "carbs": 10.0, "fat": 2.0},
            }
            mock_resp = _build_gemini_raw_response(structured)
            with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
                with self.assertRaises(HTTPException) as ctx:
                    asyncio.run(
                        self.router_mod.analyze_food_image(
                            image=dummy_file,
                            grams=100.0,
                            email="user@saman.test",
                        )
                    )
                self.assertEqual(ctx.exception.status_code, 500)
                self.assertIn("Invalid confidence score", str(ctx.exception.detail))

    def test_gemini_boolean_macros_rejected(self):
        """F-04: Boolean values in any macro must be rejected, not treated as 0.0 or 1.0."""
        dummy_file = StubUploadFile()
        for macro in ("calories", "protein", "carbs", "fat"):
            for bool_val in (True, False):
                per_100g = {"calories": 100.0, "protein": 5.0, "carbs": 10.0, "fat": 2.0}
                per_100g[macro] = bool_val
                structured = {
                    "is_food": True,
                    "food_name": "Test Dish",
                    "food_label": "test_dish",
                    "confidence": 0.85,
                    "per_100g": per_100g,
                }
                mock_resp = _build_gemini_raw_response(structured)
                with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
                    with self.assertRaises(HTTPException) as ctx:
                        asyncio.run(
                            self.router_mod.analyze_food_image(
                                image=dummy_file,
                                grams=100.0,
                                email="user@saman.test",
                            )
                        )
                    self.assertEqual(ctx.exception.status_code, 500)
                    self.assertIn(f"Invalid nutrition value for {macro}", str(ctx.exception.detail))

    def test_gemini_valid_zero_nutrition_and_confidence_accepted(self):
        """F-04: Valid 0 and 0.0 numeric values are accepted according to field rules."""
        dummy_file = StubUploadFile()
        structured = {
            "is_food": True,
            "food_name": "Black Coffee",
            "food_label": "black_coffee",
            "confidence": 0.0,
            "per_100g": {"calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0},
        }
        mock_resp = _build_gemini_raw_response(structured)
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            res = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    email="user@saman.test",
                )
            )
            self.assertEqual(res["confidence"], 0.0)
            self.assertTrue(res["low_confidence"])
            self.assertEqual(res["nutrition"]["calories"], 0.0)
            self.assertEqual(res["nutrition"]["protein"], 0.0)
            self.assertEqual(res["nutrition"]["carbs"], 0.0)
            self.assertEqual(res["nutrition"]["fat"], 0.0)

    def test_gemini_valid_integer_macros_accepted_and_normalized(self):
        """F-04: Valid int values in macros and confidence are accepted and scaled."""
        dummy_file = StubUploadFile()
        structured = {
            "is_food": True,
            "food_name": "Boiled Eggs",
            "food_label": "boiled_eggs",
            "confidence": 1,
            "per_100g": {"calories": 155, "protein": 13, "carbs": 1, "fat": 11},
        }
        mock_resp = _build_gemini_raw_response(structured)
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            res = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=200.0,
                    email="user@saman.test",
                )
            )
            self.assertEqual(res["confidence"], 1.0)
            self.assertFalse(res["low_confidence"])
            self.assertEqual(res["nutrition"]["calories"], 310.0)
            self.assertEqual(res["nutrition"]["protein"], 26.0)
            self.assertEqual(res["nutrition"]["carbs"], 2.0)
            self.assertEqual(res["nutrition"]["fat"], 22.0)

    def test_gemini_analyzer_direct_boolean_grams_rejected(self):
        """F-04: analyzer.analyze() directly rejects boolean grams."""
        analyzer = GeminiFoodAnalyzer(api_key="key", model="model")
        for bool_grams in (True, False):
            with self.assertRaises(GeminiAnalysisError) as ctx:
                asyncio.run(analyzer.analyze(image_bytes=b"fake_bytes", grams=bool_grams))
            self.assertIn("Invalid grams parameter", str(ctx.exception))

    def test_gemini_blocked_safety_finish_reason_raises_500(self):
        """AC6: Upstream safety block raises HTTP 500."""
        dummy_file = StubUploadFile()
        structured = {"is_food": True, "food_name": "Pho", "food_label": "pho", "confidence": 0.9, "per_100g": {"calories": 100, "protein": 5, "carbs": 10, "fat": 2}}
        mock_resp = _build_gemini_raw_response(structured, finish_reason="SAFETY")

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("SAFETY", str(ctx.exception.detail))

    def test_gemini_timeout_raises_500(self):
        """AC6: Request timeout raises HTTP 500 cleanly."""
        dummy_file = StubUploadFile()

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, side_effect=httpx.TimeoutException("Read timed out")):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("timed out", str(ctx.exception.detail))

    def test_gemini_rate_limit_429_raises_500(self):
        """AC6: Rate limit (429) raises HTTP 500 cleanly without leaking raw internals."""
        dummy_file = StubUploadFile()
        mock_resp = _build_gemini_raw_response({}, status_code=429)

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("rate limit", str(ctx.exception.detail).lower())

    def test_gemini_upstream_auth_failure_raises_500(self):
        """AC6: Upstream 401/403 raises HTTP 500 without printing API key."""
        dummy_file = StubUploadFile()
        mock_resp = _build_gemini_raw_response({}, status_code=401)

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertNotIn("test_mock_api_key_12345", str(ctx.exception.detail))

    # -------------------------------------------------------------------------
    # 7. DATABASE ISOLATION
    # -------------------------------------------------------------------------
    def test_gemini_analysis_does_not_mutate_db_or_create_logs(self):
        """AC8: Gemini photo analysis never queries or mutates DB, logs, or consumed totals."""
        dummy_file = StubUploadFile()

        structured = {
            "is_food": True,
            "food_name": "Salad Trộn",
            "food_label": "salad_tron",
            "confidence": 0.89,
            "per_100g": {"calories": 45.0, "protein": 1.5, "carbs": 6.0, "fat": 1.8},
        }
        mock_resp = _build_gemini_raw_response(structured)

        mock_db_calls = []
        def forbidden_db(*args, **kwargs):
            mock_db_calls.append((args, kwargs))
            raise AssertionError("Database must not be accessed during food analysis")

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    email="isolated_gemini@saman.test",
                )
            )

        self.assertEqual(resp["food_name"], "Salad Trộn")
        self.assertEqual(len(mock_db_calls), 0)

    # -------------------------------------------------------------------------
    # 8. NO RETRY & NO AUTOMATIC FALLBACK
    # -------------------------------------------------------------------------
    def test_gemini_failure_does_not_fallback_to_food101(self):
        """AC7: When Gemini fails, it returns error immediately without falling back to Food-101."""
        dummy_file = StubUploadFile()

        with patch.object(self.router_mod, "get_classifier") as mock_classifier, \
             patch("httpx.AsyncClient.post", new_callable=AsyncMock, side_effect=RuntimeError("Google 503 error")):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            mock_classifier.assert_not_called()


class GeminiRequestRoutingAndPermissionTests(unittest.TestCase):
    def setUp(self):
        self.stack = ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(sys.modules))
        _install_dependency_stubs(self.stack)

        def forbidden(*args, **kwargs):
            raise AssertionError("External network access is forbidden in unit tests")

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

        import backend.routers.food_analysis as router_mod_loaded
        self.router_mod = router_mod_loaded
        global router_mod
        router_mod = router_mod_loaded

    def _sample_gemini_resp(self, food_name="Phở Bò", food_label="pho_bo"):
        structured = {
            "is_food": True,
            "food_name": food_name,
            "food_label": food_label,
            "confidence": 0.92,
            "per_100g": {"calories": 135.0, "protein": 9.5, "carbs": 17.0, "fat": 3.2},
        }
        return _build_gemini_raw_response(structured)

    def _mock_ready_food101_classifier(self, food_name="Pho", label="pho"):
        class ReadyClassifier:
            ready = True
            classes = [label]
            def predict(self, b):
                return {
                    "label": label,
                    "food_name": food_name,
                    "confidence": 0.90,
                    "low_confidence": False,
                    "top3": [{"label": label, "food_name": food_name, "confidence": 0.90}],
                    "mock": False,
                }
        return ReadyClassifier()

    # 1. standard chỉ gọi Food-101
    def test_standard_mode_only_calls_food101(self):
        dummy_file = StubUploadFile()
        async def fake_lookup(label, grams):
            return {
                "calories": 140.0, "protein": 8.0, "carbs": 20.0, "fat": 2.5,
                "per_100g": {"calories": 140, "protein": 8.0, "carbs": 20.0, "fat": 2.5},
                "source": "usda",
            }

        with patch.dict(os.environ, {
            "FOOD_ANALYSIS_PROVIDER": "gemini",
            "GEMINI_ALLOWED_EMAILS": "",
            "GEMINI_API_KEY": "",
        }), \
        patch.object(self.router_mod, "get_classifier", return_value=self._mock_ready_food101_classifier()), \
        patch.object(self.router_mod._nutrition_lookup, "lookup", side_effect=fake_lookup), \
        patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_gemini_post:
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    mode="standard",
                    email="unauthorized@saman.test",
                )
            )
            self.assertEqual(resp["food_name"], "Pho")
            self.assertEqual(resp["nutrition_source"], "usda")
            mock_gemini_post.assert_not_called()

    # 2. advanced + email được phép chỉ gọi Gemini
    def test_advanced_mode_with_authorized_email_only_calls_gemini(self):
        dummy_file = StubUploadFile()
        mock_resp = self._sample_gemini_resp("Bún Chả", "bun_cha")

        with patch.dict(os.environ, {
            "FOOD_ANALYSIS_PROVIDER": "food101",
            "GEMINI_ALLOWED_EMAILS": "tester@saman.test",
            "GEMINI_API_KEY": "valid_key",
            "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
        }), \
        patch.object(self.router_mod, "get_classifier") as mock_classifier, \
        patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp) as mock_gemini_post:
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    mode="advanced",
                    email="tester@saman.test",
                )
            )
            self.assertEqual(resp["food_name"], "Bún Chả")
            self.assertEqual(resp["nutrition_source"], "gemini_estimate")
            mock_classifier.assert_not_called()
            mock_gemini_post.assert_called_once()

    # 3. advanced + email không được phép trả 403, không gọi analyzer
    def test_advanced_mode_with_unauthorized_email_raises_403_and_calls_no_analyzer(self):
        dummy_file = StubUploadFile()

        with patch.dict(os.environ, {
            "GEMINI_ALLOWED_EMAILS": "tester@saman.test",
            "GEMINI_API_KEY": "valid_key",
            "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
        }), \
        patch.object(self.router_mod, "get_classifier") as mock_classifier, \
        patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_gemini_post:
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        mode="advanced",
                        email="unauthorized_hacker@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 403)
            self.assertIn("restricted", str(ctx.exception.detail).lower())
            mock_classifier.assert_not_called()
            mock_gemini_post.assert_not_called()

    # 4. Không mode + mặc định food101 giữ pipeline cũ
    def test_no_mode_default_food101_preserves_old_pipeline(self):
        dummy_file = StubUploadFile()
        async def fake_lookup(label, grams):
            return {
                "calories": 100.0, "protein": 5.0, "carbs": 15.0, "fat": 2.0,
                "per_100g": {"calories": 100, "protein": 5.0, "carbs": 15.0, "fat": 2.0},
                "source": "openfoodfacts",
            }

        with patch.dict(os.environ, {
            "FOOD_ANALYSIS_PROVIDER": "food101",
            "GEMINI_ALLOWED_EMAILS": "",
        }), \
        patch.object(self.router_mod, "get_classifier", return_value=self._mock_ready_food101_classifier("Banh Mi", "banh_mi")), \
        patch.object(self.router_mod._nutrition_lookup, "lookup", side_effect=fake_lookup), \
        patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_gemini_post:
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    mode=None,
                    email="any_user@saman.test",
                )
            )
            self.assertEqual(resp["food_name"], "Banh Mi")
            self.assertEqual(resp["nutrition_source"], "openfoodfacts")
            mock_gemini_post.assert_not_called()

    # 5. Không mode + mặc định gemini + không được phép trả 403 (không thể bỏ mode để vượt allowlist)
    def test_no_mode_default_gemini_unauthorized_raises_403(self):
        dummy_file = StubUploadFile()

        with patch.dict(os.environ, {
            "FOOD_ANALYSIS_PROVIDER": "gemini",
            "GEMINI_ALLOWED_EMAILS": "vip@saman.test",
            "GEMINI_API_KEY": "valid_key",
            "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
        }), \
        patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_gemini_post:
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        mode=None,  # No mode passed!
                        email="regular_user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 403)
            mock_gemini_post.assert_not_called()

    # 6. Không mode + mặc định gemini + được phép gọi Gemini
    def test_no_mode_default_gemini_authorized_calls_gemini(self):
        dummy_file = StubUploadFile()
        mock_resp = self._sample_gemini_resp("Phở Bò", "pho_bo")

        with patch.dict(os.environ, {
            "FOOD_ANALYSIS_PROVIDER": "gemini",
            "GEMINI_ALLOWED_EMAILS": "vip@saman.test",
            "GEMINI_API_KEY": "valid_key",
            "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
        }), \
        patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp) as mock_gemini_post:
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    mode=None,
                    email="vip@saman.test",
                )
            )
            self.assertEqual(resp["food_name"], "Phở Bò")
            self.assertEqual(resp["nutrition_source"], "gemini_estimate")
            mock_gemini_post.assert_called_once()

    # 7. Allowlist thiếu/rỗng từ chối Gemini
    def test_empty_or_missing_allowlist_rejects_all_gemini(self):
        dummy_file = StubUploadFile()

        for empty_val in ["", "   "]:
            with patch.dict(os.environ, {
                "FOOD_ANALYSIS_PROVIDER": "gemini",
                "GEMINI_ALLOWED_EMAILS": empty_val,
                "GEMINI_API_KEY": "valid_key",
                "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
            }):
                with self.assertRaises(HTTPException) as ctx:
                    asyncio.run(
                        self.router_mod.analyze_food_image(
                            image=dummy_file,
                            grams=100.0,
                            mode="advanced",
                            email="admin@saman.test",
                        )
                    )
                self.assertEqual(ctx.exception.status_code, 403)

    # 8. Email gần giống hoặc chỉ chứa email được phép không được vượt quyền
    def test_email_matching_exact_trimmed_lowercase_no_substring_no_wildcard(self):
        dummy_file = StubUploadFile()
        mock_resp = self._sample_gemini_resp()

        with patch.dict(os.environ, {
            "GEMINI_ALLOWED_EMAILS": "  allowed@saman.test ,  vip@saman.vn  ",
            "GEMINI_API_KEY": "valid_key",
            "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
        }), \
        patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):

            # Trim and case-insensitive check -> PASS
            resp1 = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    mode="advanced",
                    email=" ALLOWED@SAMAN.TEST ",
                )
            )
            self.assertEqual(resp1["food_name"], "Phở Bò")

            resp2 = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=100.0,
                    mode="advanced",
                    email="vip@SAMAN.VN",
                )
            )
            self.assertEqual(resp2["food_name"], "Phở Bò")

            # Substring / Prefix / Suffix / Wildcard attempts -> MUST BE REJECTED 403
            for spoofed in [
                "allowed@saman.testing",
                "sub_allowed@saman.test",
                "allowed@saman",
                "allowed@saman.test.attacker.com",
                "vip@saman.vn.co",
                "not_vip@saman.vn",
            ]:
                with self.assertRaises(HTTPException) as ctx:
                    asyncio.run(
                        self.router_mod.analyze_food_image(
                            image=dummy_file,
                            grams=100.0,
                            mode="advanced",
                            email=spoofed,
                        )
                    )
                self.assertEqual(ctx.exception.status_code, 403)

    # 9. Form email/user_id giả không thay được danh tính đã xác thực
    def test_form_spoofing_email_cannot_override_authenticated_identity(self):
        dummy_file = StubUploadFile()
        # Even if someone injects a fake email parameter into form or client body,
        # the route relies strictly on the `email` resolved from verify_token dependency.
        with patch.dict(os.environ, {
            "GEMINI_ALLOWED_EMAILS": "admin@saman.test",
            "GEMINI_API_KEY": "valid_key",
            "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
        }):
            # The authenticated user is 'attacker@saman.test'
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        mode="advanced",
                        email="attacker@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 403)

    # 10. Mode không hợp lệ trả 422
    def test_invalid_mode_returns_422(self):
        dummy_file = StubUploadFile()
        for bad_mode in ["gemini", "pro", "gemini_pro", "custom_123", "ultra"]:
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        mode=bad_mode,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 422)
            self.assertIn("Invalid analysis mode", str(ctx.exception.detail))

    # 11. Cấu hình mặc định không hợp lệ giữ lỗi G1
    def test_invalid_default_provider_configuration_raises_500(self):
        dummy_file = StubUploadFile()
        with patch.dict(os.environ, {"FOOD_ANALYSIS_PROVIDER": "unsupported_provider"}):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        mode=None,
                        email="user@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            self.assertIn("Invalid FOOD_ANALYSIS_PROVIDER configuration", str(ctx.exception.detail))

    # 12. Gemini lỗi không chuyển sang Food-101
    def test_gemini_error_does_not_fallback_to_food101(self):
        dummy_file = StubUploadFile()

        with patch.dict(os.environ, {
            "GEMINI_ALLOWED_EMAILS": "authorized@saman.test",
            "GEMINI_API_KEY": "valid_key",
            "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
        }), \
        patch.object(self.router_mod, "get_classifier") as mock_classifier, \
        patch("httpx.AsyncClient.post", new_callable=AsyncMock, side_effect=RuntimeError("Google 503 error")):
            with self.assertRaises(HTTPException) as ctx:
                asyncio.run(
                    self.router_mod.analyze_food_image(
                        image=dummy_file,
                        grams=100.0,
                        mode="advanced",
                        email="authorized@saman.test",
                    )
                )
            self.assertEqual(ctx.exception.status_code, 500)
            mock_classifier.assert_not_called()

    # 13. Response thành công giữ nguyên contract; không phát sinh ghi Story/log/DB
    def test_successful_analysis_contract_and_zero_db_mutations(self):
        dummy_file = StubUploadFile()
        mock_resp = self._sample_gemini_resp("Cơm Tấm", "com_tam")

        mock_db_calls = []
        def forbidden_db(*args, **kwargs):
            mock_db_calls.append((args, kwargs))
            raise AssertionError("Database access forbidden during analysis")

        with patch.dict(os.environ, {
            "GEMINI_ALLOWED_EMAILS": "authorized@saman.test",
            "GEMINI_API_KEY": "valid_key",
            "GEMINI_FOOD_MODEL": "gemini-3.8-flash",
        }), \
        patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_resp):
            resp = asyncio.run(
                self.router_mod.analyze_food_image(
                    image=dummy_file,
                    grams=150.0,
                    mode="advanced",
                    email="authorized@saman.test",
                )
            )

        # Schema contract verification
        self.assertEqual(resp["food_name"], "Cơm Tấm")
        self.assertEqual(resp["food_label"], "com_tam")
        self.assertEqual(resp["detected_food_name"], "Cơm Tấm")
        self.assertEqual(resp["confidence"], 0.92)
        self.assertFalse(resp["low_confidence"])
        self.assertEqual(resp["grams"], 150.0)
        self.assertIn("calories", resp["nutrition"])
        self.assertIn("protein", resp["nutrition"])
        self.assertIn("carbs", resp["nutrition"])
        self.assertIn("fat", resp["nutrition"])
        self.assertIn("per_100g", resp)
        self.assertEqual(resp["nutrition_source"], "gemini_estimate")
        self.assertIsInstance(resp["top3_predictions"], list)
        self.assertFalse(resp["mock"])
        self.assertEqual(resp["user_email"], "authorized@saman.test")
        self.assertEqual(len(mock_db_calls), 0)


if __name__ == "__main__":
    unittest.main()
