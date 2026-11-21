"""
Unit & Router tests for P1.2 Backend: Barcode Lookup & Nutrition Label AI.

Verifies:
1. Route precedence: GET /api/nutrition/barcode/{barcode} is NOT swallowed by GET /api/nutrition/{date}.
2. Barcode lookup:
   - Cache hit returns found=True, source="cache" with zero Open Food Facts calls.
   - Open Food Facts hit normalizes per_100g (kcal + kJ/4.184 fallback), parses serving_grams
     (default 100), upserts with ObjectId _id, returns found=True, source="open_food_facts", id=str(_id).
   - Open Food Facts status != 1 or missing product name does NOT insert into DB and returns HTTP 404
     with detail.code == "barcode_not_found".
   - Invalid barcode format returns HTTP 400.
3. GET /api/nutrition/foods/{food_id} fallback lookup into food_barcodes_collection by ObjectId.
4. GeminiFoodAnalyzer.analyze_nutrition_label:
   - Extracts direct per_100g label.
   - Normalizes per_serving-only label using serving_grams > 0.
   - Raises GeminiAnalysisError when is_nutrition_label is False.
5. POST /api/nutrition/barcode/analyze-label:
   - Validates image size (<1000B -> 400, >10MB -> 413) and barcode (400).
   - Success with paywall ON: caches to food_barcodes (source="gemini_label_community"),
     commits ai.nutrition_gemini quota, returns standard {found, source, barcode, food} payload,
     and subsequent GET /barcode/{barcode} hits cache.
   - Failure / non-label: releases reserved quota (0 consumed, 0 reserved) and does NOT cache.
   - Paywall ON quota exhaustion returns HTTP 429 (code="quota_exceeded") with zero extra Gemini calls.
   - Paywall ON limit_units==0 returns HTTP 403 (code="entitlement_required") with zero Gemini calls.
"""

import asyncio
from copy import deepcopy
import json
from pathlib import Path
import sys
import threading
from types import ModuleType, SimpleNamespace
from typing import Any, Dict, List, Optional, Tuple
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import pytest
from bson import ObjectId
from fastapi import FastAPI

import backend.app.database as app_db
from backend.app.database_revenue import COLL_USAGE_BUCKETS, COLL_USAGE_OPERATIONS
from backend.app.models.revenue import MembershipTier
from backend.app.services.barcode_service import (
    OPEN_FOOD_FACTS_USER_AGENT,
    lookup_barcode,
    normalize_and_validate_barcode,
    parse_serving_grams,
)
from backend.auth_utils import get_current_user
from backend.routers import nutrition as nutrition_router


# ---------------------------------------------------------------------------
# Minimal httpx stub fallback when running in offline environments without httpx
# ---------------------------------------------------------------------------

class _StubTimeoutException(Exception):
    pass


class _StubRequestError(Exception):
    pass


def _ensure_httpx_module(monkeypatch: pytest.MonkeyPatch):
    if "httpx" in sys.modules:
        return sys.modules["httpx"]
    stub = ModuleType("httpx")

    class AsyncClient:
        def __init__(self, *args, **kwargs):
            self.timeout = kwargs.get("timeout")

        async def __aenter__(self):
            return self

        async def __aexit__(self, *args):
            return None

        async def get(self, *args, **kwargs):
            raise RuntimeError("Real network call forbidden in unit tests")

        async def post(self, *args, **kwargs):
            raise RuntimeError("Real network call forbidden in unit tests")

    stub.AsyncClient = AsyncClient
    stub.TimeoutException = _StubTimeoutException
    stub.RequestError = _StubRequestError
    monkeypatch.setitem(sys.modules, "httpx", stub)
    if "backend.services.gemini_food_analyzer" in sys.modules:
        monkeypatch.setattr(sys.modules["backend.services.gemini_food_analyzer"], "httpx", stub)
    if "backend.app.services.barcode_service" in sys.modules:
        monkeypatch.setattr(sys.modules["backend.app.services.barcode_service"], "httpx", stub)
    return stub


# ---------------------------------------------------------------------------
# Lightweight ASGI client for real FastAPI routing/Form/File/Header testing
# without requiring external httpx package
# ---------------------------------------------------------------------------

def _encode_multipart(
    data: Optional[Dict[str, str]] = None,
    files: Optional[Dict[str, Tuple[str, bytes, str]]] = None,
) -> Tuple[bytes, str]:
    boundary = f"----SamanTestBoundary{uuid4().hex}"
    chunks: List[bytes] = []
    for name, val in (data or {}).items():
        chunks.append(f"--{boundary}\r\n".encode("utf-8"))
        chunks.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode("utf-8"))
        chunks.append(str(val).encode("utf-8") + b"\r\n")
    for field_name, (filename, content, content_type) in (files or {}).items():
        chunks.append(f"--{boundary}\r\n".encode("utf-8"))
        chunks.append(
            f'Content-Disposition: form-data; name="{field_name}"; filename="{filename}"\r\n'.encode("utf-8")
        )
        chunks.append(f"Content-Type: {content_type}\r\n\r\n".encode("utf-8"))
        chunks.append(content + b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode("utf-8"))
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


class _ASGIResponse:
    def __init__(self, status_code: int, body: bytes, headers: Dict[str, str]):
        self.status_code = status_code
        self.content = body
        self.headers = headers

    def json(self) -> Any:
        return json.loads(self.content.decode("utf-8"))

    @property
    def text(self) -> str:
        return self.content.decode("utf-8", errors="replace")


class _ASGIAppClient:
    def __init__(self, app: FastAPI):
        self.app = app

    def request(
        self,
        method: str,
        path: str,
        *,
        data: Optional[Dict[str, str]] = None,
        files: Optional[Dict[str, Tuple[str, bytes, str]]] = None,
        headers: Optional[Dict[str, str]] = None,
    ) -> _ASGIResponse:
        req_headers = {k.lower(): v for k, v in (headers or {}).items()}
        body = b""
        if data is not None or files is not None:
            body, content_type = _encode_multipart(data=data, files=files)
            req_headers["content-type"] = content_type
            req_headers["content-length"] = str(len(body))

        raw_path, _, query_str = path.partition("?")
        scope = {
            "type": "http",
            "asgi": {"version": "3.0"},
            "http_version": "1.1",
            "method": method.upper(),
            "scheme": "http",
            "path": raw_path,
            "raw_path": raw_path.encode("utf-8"),
            "query_string": query_str.encode("utf-8"),
            "headers": [(k.encode("latin-1"), v.encode("latin-1")) for k, v in req_headers.items()],
            "client": ("127.0.0.1", 12345),
            "server": ("testserver", 80),
        }

        sent_body = False
        status_code = 500
        resp_headers: Dict[str, str] = {}
        resp_chunks: List[bytes] = []

        async def receive():
            nonlocal sent_body
            if not sent_body:
                sent_body = True
                return {"type": "http.request", "body": body, "more_body": False}
            return {"type": "http.disconnect"}

        async def send(message):
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                for k, v in message.get("headers", []):
                    resp_headers[k.decode("latin-1").lower()] = v.decode("latin-1")
            elif message["type"] == "http.response.body":
                chunk = message.get("body", b"")
                if chunk:
                    resp_chunks.append(chunk)

        asyncio.run(self.app(scope, receive, send))
        return _ASGIResponse(status_code=status_code, body=b"".join(resp_chunks), headers=resp_headers)

    def get(self, path: str, **kwargs) -> _ASGIResponse:
        return self.request("GET", path, **kwargs)

    def post(self, path: str, **kwargs) -> _ASGIResponse:
        return self.request("POST", path, **kwargs)


# ---------------------------------------------------------------------------
# Thread-safe in-memory MongoDB Mock supporting $expr, $add, $ifNull, $lte, $inc, $setOnInsert
# ---------------------------------------------------------------------------

def _eval_expr_operand(doc: Dict[str, Any], expr: Any) -> Any:
    if isinstance(expr, (int, float)):
        return expr
    if isinstance(expr, str) and expr.startswith("$"):
        return doc.get(expr[1:], 0)
    if isinstance(expr, dict):
        if "$add" in expr:
            return sum(_eval_expr_operand(doc, item) for item in expr["$add"])
        if "$ifNull" in expr:
            field_ref, default_val = expr["$ifNull"]
            if isinstance(field_ref, str) and field_ref.startswith("$"):
                val = doc.get(field_ref[1:])
            else:
                val = field_ref
            return default_val if val is None else val
    return expr


class MockMongoCollection:
    def __init__(self, name: str = "col", docs: Optional[List[Dict[str, Any]]] = None):
        self.name = name
        self.docs: List[Dict[str, Any]] = [deepcopy(d) for d in (docs or [])]
        self._lock = threading.Lock()

    def _matches(self, doc: Dict[str, Any], query: Optional[Dict[str, Any]]) -> bool:
        if not query:
            return True
        for k, v in query.items():
            if k == "$expr":
                if "$lte" in v:
                    left, right = v["$lte"]
                    if _eval_expr_operand(doc, left) > _eval_expr_operand(doc, right):
                        return False
                continue
            if k == "$and":
                if not all(self._matches(doc, clause) for clause in v):
                    return False
                continue
            if k == "$or":
                if not any(self._matches(doc, clause) for clause in v):
                    return False
                continue
            doc_val = doc.get(k)
            if isinstance(v, dict):
                if "$in" in v and doc_val not in v["$in"]:
                    return False
                if "$lte" in v and not (doc_val is not None and doc_val <= v["$lte"]):
                    return False
                if "$lt" in v and not (doc_val is not None and doc_val < v["$lt"]):
                    return False
                if "$gte" in v and not (doc_val is not None and doc_val >= v["$gte"]):
                    return False
                if "$ne" in v and doc_val == v["$ne"]:
                    return False
            else:
                if doc_val != v:
                    return False
        return True

    def find(self, query: Optional[Dict[str, Any]] = None, projection: Any = None) -> List[Dict[str, Any]]:
        with self._lock:
            return [deepcopy(d) for d in self.docs if self._matches(d, query)]

    def find_one(self, query: Optional[Dict[str, Any]] = None, projection: Any = None) -> Optional[Dict[str, Any]]:
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    return deepcopy(d)
            return None

    def insert_one(self, doc: Dict[str, Any]):
        with self._lock:
            d = deepcopy(doc)
            if "_id" not in d:
                d["_id"] = ObjectId()
            if self.name == COLL_USAGE_OPERATIONS:
                for existing in self.docs:
                    if (
                        existing.get("user_id") == d.get("user_id")
                        and existing.get("benefit_id") == d.get("benefit_id")
                        and existing.get("idempotency_key") == d.get("idempotency_key")
                    ):
                        raise RuntimeError("DuplicateKeyError")
            self.docs.append(d)
            return SimpleNamespace(inserted_id=d["_id"])

    def update_one(self, query: Dict[str, Any], update: Dict[str, Any], upsert: bool = False):
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    self._apply_update(d, update)
                    return SimpleNamespace(matched_count=1, modified_count=1, upserted_id=None)
            if upsert:
                new_doc: Dict[str, Any] = {}
                for k, v in query.items():
                    if not k.startswith("$") and not isinstance(v, dict):
                        new_doc[k] = deepcopy(v)
                if "$setOnInsert" in update:
                    new_doc.update(deepcopy(update["$setOnInsert"]))
                if "$set" in update:
                    new_doc.update(deepcopy(update["$set"]))
                if "$inc" in update:
                    for k, v in update["$inc"].items():
                        new_doc[k] = new_doc.get(k, 0) + v
                if "_id" not in new_doc:
                    new_doc["_id"] = ObjectId()
                self.docs.append(new_doc)
                return SimpleNamespace(matched_count=0, modified_count=1, upserted_id=new_doc["_id"])
            return SimpleNamespace(matched_count=0, modified_count=0, upserted_id=None)

    def find_one_and_update(self, query: Dict[str, Any], update: Dict[str, Any], **kwargs) -> Optional[Dict[str, Any]]:
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    self._apply_update(d, update)
                    return deepcopy(d)
            return None

    def _apply_update(self, doc: Dict[str, Any], update: Dict[str, Any]) -> None:
        if "$inc" in update:
            for k, v in update["$inc"].items():
                doc[k] = doc.get(k, 0) + v
        if "$set" in update:
            for k, v in update["$set"].items():
                doc[k] = deepcopy(v)


class MockMongoDB:
    def __init__(self):
        self._cols: Dict[str, MockMongoCollection] = {}

    def __getitem__(self, name: str) -> MockMongoCollection:
        if name not in self._cols:
            self._cols[name] = MockMongoCollection(name)
        return self._cols[name]


def _make_httpx_response(status_code: int, payload: Dict[str, Any]) -> MagicMock:
    resp = MagicMock()
    resp.status_code = status_code
    resp.json = MagicMock(return_value=payload)
    return resp


def _make_gemini_raw_response(structured: Dict[str, Any], status_code: int = 200) -> MagicMock:
    resp = MagicMock()
    resp.status_code = status_code
    if status_code == 200:
        data = {
            "candidates": [
                {
                    "content": {
                        "parts": [{"text": json.dumps(structured)}],
                        "role": "model",
                    },
                    "finishReason": "STOP",
                }
            ]
        }
    else:
        data = {"error": {"message": f"Error {status_code}"}}
    resp.json = MagicMock(return_value=data)
    return resp


def _build_client(user: Optional[Dict[str, Any]] = None) -> _ASGIAppClient:
    app = FastAPI()
    app.include_router(nutrition_router.router)
    active_user = user or {
        "_id": "650000000000000000000010",
        "email": "barcode_user@saman.test",
    }
    app.dependency_overrides[get_current_user] = lambda: active_user
    return _ASGIAppClient(app)


# ---------------------------------------------------------------------------
# 1. Unit tests for barcode_service
# ---------------------------------------------------------------------------

class TestBarcodeService:
    def test_validate_barcode_rules(self):
        assert normalize_and_validate_barcode("  8934588012112 \n") == "8934588012112"
        assert normalize_and_validate_barcode("123456") == "123456"
        assert normalize_and_validate_barcode("12345678901234") == "12345678901234"

        for bad in ("", "12345", "123456789012345", "89345abc12112", "893-458801", "2026-11-20"):
            with pytest.raises(ValueError):
                normalize_and_validate_barcode(bad)

    def test_parse_serving_grams(self):
        assert parse_serving_grams("1 pack (35 g)") == 35.0
        assert parse_serving_grams("250ml") == 250.0
        assert parse_serving_grams("0.5 L") == 500.0
        assert parse_serving_grams("1 serving", serving_quantity=42.5) == 42.5
        assert parse_serving_grams("unknown") == 100.0
        assert parse_serving_grams("") == 100.0

    def test_lookup_barcode_off_kj_fallback_and_cache_upsert(self, monkeypatch):
        httpx_mod = _ensure_httpx_module(monkeypatch)
        barcodes_col = MockMongoCollection("food_barcodes")
        off_payload = {
            "status": 1,
            "product": {
                "product_name": "Sữa Tươi Vinamilk Ít Đường",
                "brands": "Vinamilk",
                "serving_size": "1 hộp (180 ml)",
                "image_front_url": "https://images.openfoodfacts.org/milk.jpg",
                "nutriments": {
                    "energy-kj_100g": 260.0,
                    "proteins_100g": 3.0,
                    "carbohydrates_100g": 7.4,
                    "fat_100g": 3.2,
                    "fiber_100g": 0.0,
                },
            },
        }
        mock_get = AsyncMock(return_value=_make_httpx_response(200, off_payload))

        with patch.object(httpx_mod.AsyncClient, "get", mock_get):
            result = asyncio.run(lookup_barcode("8934673100123", barcodes_col))

        assert result is not None
        assert result["found"] is True
        assert result["source"] == "open_food_facts"
        assert result["barcode"] == "8934673100123"
        food = result["food"]
        assert ObjectId.is_valid(food["id"])
        assert food["name"] == "Sữa Tươi Vinamilk Ít Đường"
        assert food["brand"] == "Vinamilk"
        assert food["serving_grams"] == 180.0
        assert food["per_100g"]["calories"] == round(260.0 / 4.184, 1)
        assert food["per_100g"]["protein"] == 3.0
        assert food["per_100g"]["carbs"] == 7.4
        assert food["per_100g"]["fat"] == 3.2
        assert food["per_100g"]["fiber"] == 0.0

        # Verify User-Agent header sent to Open Food Facts
        call_kwargs = mock_get.call_args.kwargs
        assert call_kwargs["headers"]["User-Agent"] == OPEN_FOOD_FACTS_USER_AGENT

        # Verify persisted with ObjectId _id
        stored = barcodes_col.find_one({"barcode": "8934673100123"})
        assert stored is not None
        assert isinstance(stored["_id"], ObjectId)
        assert str(stored["_id"]) == food["id"]

        # Second call hits cache without calling httpx again
        mock_get.reset_mock()
        with patch.object(httpx_mod.AsyncClient, "get", mock_get):
            cached = asyncio.run(lookup_barcode("8934673100123", barcodes_col))

        mock_get.assert_not_called()
        assert cached["found"] is True
        assert cached["source"] == "cache"
        assert cached["food"]["id"] == food["id"]


# ---------------------------------------------------------------------------
# 2. Unit tests for GeminiFoodAnalyzer.analyze_nutrition_label
# ---------------------------------------------------------------------------

class TestGeminiLabelAnalyzer:
    def test_analyze_label_per_100g_direct(self, monkeypatch):
        httpx_mod = _ensure_httpx_module(monkeypatch)
        from backend.services.gemini_food_analyzer import GeminiFoodAnalyzer

        analyzer = GeminiFoodAnalyzer(api_key="test-key", model="gemini-3.6-flash")
        structured = {
            "is_nutrition_label": True,
            "product_name": "Yến Mạch Quaker",
            "brand": "Quaker",
            "serving_size": "40g",
            "serving_grams": 40,
            "per_100g": {
                "calories": 375.0,
                "protein": 13.5,
                "carbs": 67.0,
                "fat": 6.5,
                "fiber": 10.0,
            },
        }
        mock_post = AsyncMock(return_value=_make_gemini_raw_response(structured))
        with patch.object(httpx_mod.AsyncClient, "post", mock_post):
            res = asyncio.run(analyzer.analyze_nutrition_label(b"x" * 2048, mime_type="image/jpeg"))

        assert res["is_nutrition_label"] is True
        assert res["product_name"] == "Yến Mạch Quaker"
        assert res["brand"] == "Quaker"
        assert res["serving_grams"] == 40.0
        assert res["per_100g"] == {
            "calories": 375.0,
            "protein": 13.5,
            "carbs": 67.0,
            "fat": 6.5,
            "fiber": 10.0,
        }

    def test_analyze_label_normalizes_per_serving_to_per_100g(self, monkeypatch):
        httpx_mod = _ensure_httpx_module(monkeypatch)
        from backend.services.gemini_food_analyzer import GeminiFoodAnalyzer

        analyzer = GeminiFoodAnalyzer(api_key="test-key", model="gemini-3.6-flash")
        # Label only printed per serving (serving_grams = 50g -> multiply by 2 for per_100g)
        structured = {
            "is_nutrition_label": True,
            "product_name": "Whey Protein Bar",
            "brand": "SamanLab",
            "serving_size": "1 thanh (50g)",
            "serving_grams": 50,
            "per_100g": {
                "calories": 0,
                "protein": 0,
                "carbs": 0,
                "fat": 0,
                "fiber": 0,
            },
            "per_serving": {
                "calories": 190.0,
                "protein": 20.0,
                "carbs": 18.0,
                "fat": 5.5,
                "fiber": 4.0,
            },
        }
        mock_post = AsyncMock(return_value=_make_gemini_raw_response(structured))
        with patch.object(httpx_mod.AsyncClient, "post", mock_post):
            res = asyncio.run(analyzer.analyze_nutrition_label(b"x" * 2048))

        assert res["serving_grams"] == 50.0
        assert res["per_100g"] == {
            "calories": 380.0,
            "protein": 40.0,
            "carbs": 36.0,
            "fat": 11.0,
            "fiber": 8.0,
        }

    def test_analyze_label_non_label_raises_error(self, monkeypatch):
        httpx_mod = _ensure_httpx_module(monkeypatch)
        from backend.services.gemini_food_analyzer import GeminiAnalysisError, GeminiFoodAnalyzer

        analyzer = GeminiFoodAnalyzer(api_key="test-key", model="gemini-3.6-flash")
        structured = {
            "is_nutrition_label": False,
            "product_name": "",
            "brand": "",
            "serving_size": "",
            "serving_grams": 0,
            "per_100g": {"calories": 0, "protein": 0, "carbs": 0, "fat": 0, "fiber": 0},
        }
        mock_post = AsyncMock(return_value=_make_gemini_raw_response(structured))
        with patch.object(httpx_mod.AsyncClient, "post", mock_post):
            with pytest.raises(GeminiAnalysisError, match="nutrition label"):
                asyncio.run(analyzer.analyze_nutrition_label(b"x" * 2048))


# ---------------------------------------------------------------------------
# 3. Router integration tests: route precedence, lookup, foods/{id}, analyze-label + quota
# ---------------------------------------------------------------------------

class TestBarcodeRouterAndQuota:
    @pytest.fixture
    def env(self, monkeypatch):
        httpx_mod = _ensure_httpx_module(monkeypatch)
        mock_db = MockMongoDB()
        barcodes_col = mock_db["food_barcodes"]
        foods_col = mock_db["foods"]
        user_foods_col = mock_db["user_foods"]

        monkeypatch.setattr(app_db, "db", mock_db)
        monkeypatch.setattr(app_db, "food_barcodes_collection", barcodes_col)
        monkeypatch.setattr(nutrition_router, "db", mock_db)
        monkeypatch.setattr(nutrition_router, "food_barcodes_collection", barcodes_col)
        monkeypatch.setattr(nutrition_router, "foods_collection", foods_col)
        monkeypatch.setattr(nutrition_router, "user_foods_collection", user_foods_col)
        monkeypatch.setenv("ENABLE_AI_PAYWALL", "false")
        monkeypatch.setenv("REVENUE_ENFORCEMENT_ENABLED", "false")
        return {
            "httpx": httpx_mod,
            "db": mock_db,
            "barcodes": barcodes_col,
            "foods": foods_col,
            "user_foods": user_foods_col,
        }

    def test_route_not_swallowed_by_date_and_cache_hit(self, env):
        oid = ObjectId("650000000000000000000101")
        env["barcodes"].insert_one({
            "_id": oid,
            "barcode": "8934588012112",
            "name": "Nước Yến Ngân Nhĩ",
            "brand": "Sanest",
            "serving_size": "70ml",
            "serving_grams": 70.0,
            "calories": 55.0,
            "protein": 0.5,
            "carbs": 13.0,
            "fat": 0.0,
            "fiber": 0.2,
            "per_100g": {"calories": 55.0, "protein": 0.5, "carbs": 13.0, "fat": 0.0, "fiber": 0.2},
            "source": "open_food_facts",
        })

        client = _build_client()
        with patch.object(env["httpx"].AsyncClient, "get", new_callable=AsyncMock) as mock_get:
            resp = client.get("/api/nutrition/barcode/8934588012112")

        assert resp.status_code == 200
        mock_get.assert_not_called()
        body = resp.json()
        # Confirms route hit barcode handler rather than /{date}
        assert body["found"] is True
        assert body["source"] == "cache"
        assert body["barcode"] == "8934588012112"
        assert body["food"]["id"] == str(oid)
        assert body["food"]["name"] == "Nước Yến Ngân Nhĩ"

    def test_get_barcode_open_food_facts_hit_and_food_id_fallback(self, env):
        off_payload = {
            "status": 1,
            "product": {
                "product_name": "Bánh Gạo Lứt",
                "brands": "Oishi",
                "serving_size": "25g",
                "nutriments": {
                    "energy-kcal_100g": 420,
                    "proteins_100g": 7.5,
                    "carbohydrates_100g": 78.0,
                    "fat_100g": 8.5,
                    "fiber_100g": 3.2,
                },
            },
        }
        client = _build_client()
        with patch.object(
            env["httpx"].AsyncClient,
            "get",
            new_callable=AsyncMock,
            return_value=_make_httpx_response(200, off_payload),
        ):
            resp = client.get("/api/nutrition/barcode/8934803012345")

        assert resp.status_code == 200
        data = resp.json()
        assert data["found"] is True
        assert data["source"] == "open_food_facts"
        food_id = data["food"]["id"]
        assert ObjectId.is_valid(food_id)
        assert data["food"]["per_100g"] == {
            "calories": 420.0,
            "protein": 7.5,
            "carbs": 78.0,
            "fat": 8.5,
            "fiber": 3.2,
        }

        # Fallback lookup via GET /api/nutrition/foods/{food_id}
        food_resp = client.get(f"/api/nutrition/foods/{food_id}")
        assert food_resp.status_code == 200
        food_detail = food_resp.json()
        assert food_detail["id"] == food_id
        assert food_detail["name"] == "Bánh Gạo Lứt"
        assert food_detail["source_type"] == "barcode"
        assert food_detail["calories"] == 420.0

    def test_get_barcode_not_found_and_missing_name_not_saved(self, env):
        client = _build_client()

        # Case 1: status != 1
        with patch.object(
            env["httpx"].AsyncClient,
            "get",
            new_callable=AsyncMock,
            return_value=_make_httpx_response(200, {"status": 0}),
        ):
            r1 = client.get("/api/nutrition/barcode/8930000000001")
        assert r1.status_code == 404
        assert r1.json()["detail"] == {
            "code": "barcode_not_found",
            "barcode": "8930000000001",
            "message": "Chưa có dữ liệu mã vạch này.",
        }
        assert env["barcodes"].find_one({"barcode": "8930000000001"}) is None

        # Case 2: status == 1 but missing product_name
        missing_name_payload = {"status": 1, "product": {"product_name": "   ", "nutriments": {"energy-kcal_100g": 100}}}
        with patch.object(
            env["httpx"].AsyncClient,
            "get",
            new_callable=AsyncMock,
            return_value=_make_httpx_response(200, missing_name_payload),
        ):
            r2 = client.get("/api/nutrition/barcode/8930000000002")
        assert r2.status_code == 404
        assert r2.json()["detail"]["code"] == "barcode_not_found"
        assert env["barcodes"].find_one({"barcode": "8930000000002"}) is None

    def test_get_barcode_invalid_format_returns_400(self, env):
        client = _build_client()
        for bad in ("12345", "abc12345", "123456789012345"):
            r = client.get(f"/api/nutrition/barcode/{bad}")
            assert r.status_code == 400
            assert r.json()["detail"]["code"] == "invalid_barcode"

    def test_analyze_label_image_size_and_barcode_validation(self, env):
        client = _build_client()

        # Invalid barcode -> 400
        r_bad_bc = client.post(
            "/api/nutrition/barcode/analyze-label",
            data={"barcode": "123"},
            files={"image": ("label.jpg", b"a" * 2048, "image/jpeg")},
        )
        assert r_bad_bc.status_code == 400

        # Image too small (< 1000B) -> 400
        r_small = client.post(
            "/api/nutrition/barcode/analyze-label",
            data={"barcode": "8934588012112"},
            files={"image": ("tiny.jpg", b"a" * 500, "image/jpeg")},
        )
        assert r_small.status_code == 400

        # Image too large (> 10MB) -> 413
        r_large = client.post(
            "/api/nutrition/barcode/analyze-label",
            data={"barcode": "8934588012112"},
            files={"image": ("huge.jpg", b"a" * (10 * 1024 * 1024 + 1), "image/jpeg")},
        )
        assert r_large.status_code == 413

    def test_analyze_label_success_commits_quota_and_caches_community(self, env, monkeypatch):
        from backend.services.gemini_food_analyzer import GeminiFoodAnalyzer

        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user = {"_id": "u_free_label_1", "email": "free_label@saman.test"}
        client = _build_client(user=user)

        mock_analyze = AsyncMock(return_value={
            "is_nutrition_label": True,
            "product_name": "Sữa Hạt Óc Chó",
            "brand": "TH True Nut",
            "serving_size": "180ml",
            "serving_grams": 180.0,
            "per_100g": {
                "calories": 58.0,
                "protein": 1.6,
                "carbs": 4.8,
                "fat": 3.5,
                "fiber": 0.8,
            },
        })

        with patch.object(GeminiFoodAnalyzer, "analyze_nutrition_label", mock_analyze):
            resp = client.post(
                "/api/nutrition/barcode/analyze-label",
                data={"barcode": "8935217400999", "product_name": "Sữa Hạt Óc Chó TH"},
                files={"image": ("label.jpg", b"img_bytes_" * 300, "image/jpeg")},
                headers={"X-Idempotency-Key": "idemp-label-1"},
            )

        assert resp.status_code == 200
        body = resp.json()
        assert body["found"] is True
        assert body["source"] == "gemini_label_community"
        assert body["barcode"] == "8935217400999"
        assert body["food"]["name"] == "Sữa Hạt Óc Chó TH"
        assert body["food"]["brand"] == "TH True Nut"
        assert body["food"]["source"] == "gemini_label_community"
        assert ObjectId.is_valid(body["food"]["id"])

        # Quota committed (Free tier daily limit = 1)
        buckets = env["db"][COLL_USAGE_BUCKETS].find({"user_id": "u_free_label_1"})
        assert len(buckets) == 1
        assert buckets[0]["consumed_units"] == 1
        assert buckets[0]["reserved_units"] == 0

        # Subsequent GET hits MongoDB cache
        with patch.object(env["httpx"].AsyncClient, "get", new_callable=AsyncMock) as mock_off:
            cached_resp = client.get("/api/nutrition/barcode/8935217400999")
        mock_off.assert_not_called()
        assert cached_resp.status_code == 200
        assert cached_resp.json()["source"] == "cache"
        assert cached_resp.json()["food"]["id"] == body["food"]["id"]

        # 2nd analyze-label call by same Free user -> 429 quota_exceeded with 0 extra Gemini calls
        mock_analyze.reset_mock()
        with patch.object(GeminiFoodAnalyzer, "analyze_nutrition_label", mock_analyze):
            r_429 = client.post(
                "/api/nutrition/barcode/analyze-label",
                data={"barcode": "8935217400888"},
                files={"image": ("label2.jpg", b"other_img_" * 300, "image/jpeg")},
                headers={"X-Idempotency-Key": "idemp-label-2"},
            )
        mock_analyze.assert_not_called()
        assert r_429.status_code == 429
        detail = r_429.json()["detail"]
        assert detail["code"] == "quota_exceeded"
        assert detail["benefit_id"] == "ai.nutrition_gemini"
        assert detail["limit_units"] == 1
        assert detail["remaining_units"] == 0

    def test_analyze_label_non_label_and_error_release_quota(self, env, monkeypatch):
        from backend.services.gemini_food_analyzer import GeminiAnalysisError, GeminiFoodAnalyzer

        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user = {"_id": "u_free_release", "email": "free_release@saman.test"}
        client = _build_client(user=user)

        # 1. Non-label rejection -> 400 and release quota
        mock_non_label = AsyncMock(
            side_effect=GeminiAnalysisError("Image does not contain a recognizable nutrition label")
        )
        with patch.object(GeminiFoodAnalyzer, "analyze_nutrition_label", mock_non_label):
            r_non = client.post(
                "/api/nutrition/barcode/analyze-label",
                data={"barcode": "8935217400777"},
                files={"image": ("not_label.jpg", b"not_a_lbl_" * 300, "image/jpeg")},
                headers={"X-Idempotency-Key": "idemp-non-label"},
            )
        assert r_non.status_code == 400
        assert r_non.json()["detail"]["code"] == "not_nutrition_label"
        assert env["barcodes"].find_one({"barcode": "8935217400777"}) is None

        buckets = env["db"][COLL_USAGE_BUCKETS].find({"user_id": "u_free_release"})
        assert len(buckets) == 1
        assert buckets[0]["consumed_units"] == 0
        assert buckets[0]["reserved_units"] == 0

        # 2. Recoverable upstream error -> 502 and release quota
        mock_err = AsyncMock(side_effect=GeminiAnalysisError("Gemini upstream server error (503)"))
        with patch.object(GeminiFoodAnalyzer, "analyze_nutrition_label", mock_err):
            r_err = client.post(
                "/api/nutrition/barcode/analyze-label",
                data={"barcode": "8935217400778"},
                files={"image": ("err.jpg", b"err_image_" * 300, "image/jpeg")},
                headers={"X-Idempotency-Key": "idemp-provider-err"},
            )
        assert r_err.status_code == 502
        buckets = env["db"][COLL_USAGE_BUCKETS].find({"user_id": "u_free_release"})
        assert buckets[0]["consumed_units"] == 0
        assert buckets[0]["reserved_units"] == 0

    def test_analyze_label_paywall_zero_limit_returns_403_entitlement_required(self, env, monkeypatch):
        from backend.services.gemini_food_analyzer import GeminiFoodAnalyzer

        monkeypatch.setenv("ENABLE_AI_PAYWALL", "true")
        user = {"_id": "u_blocked_tier", "email": "blocked@saman.test"}
        client = _build_client(user=user)

        mock_analyze = AsyncMock()
        with patch(
            "backend.app.services.quota_service.resolve_user_tier_and_quota",
            return_value=(MembershipTier.FREE, "daily", 0),
        ), patch.object(GeminiFoodAnalyzer, "analyze_nutrition_label", mock_analyze):
            resp = client.post(
                "/api/nutrition/barcode/analyze-label",
                data={"barcode": "8935217400666"},
                files={"image": ("label.jpg", b"img_bytes_" * 300, "image/jpeg")},
            )

        mock_analyze.assert_not_called()
        assert resp.status_code == 403
        detail = resp.json()["detail"]
        assert detail["code"] == "entitlement_required"
        assert detail["benefit_id"] == "ai.nutrition_gemini"
