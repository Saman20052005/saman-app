"""
Comprehensive unit & integration test suite for CP3 Batch 2 (CP3.3 Recommendations):
1. Intent Gate & Phân tầng:
   - tier="swift3" luôn trả về status == "skipped", triggered == False, và không đụng DB (spy find_calls == 0).
   - Câu hỏi log/hỏi số liệu đơn thuần ở core3/pro3 ("Hôm nay tôi uống bao nhiêu nước?", "Hôm nay tôi còn nhiệm vụ gì?")
     -> status == "skipped", triggered == False, số lần gọi find == 0.
2. Smart Deficit Filtering cho shop_products:
   - Thiếu đạm (nutrition.summary protein 40g vs target_protein 150g) + user hỏi "Tôi đang thiếu đạm thì nên bổ sung sản phẩm nào?"
     -> trả về tối đa 3 món, ưu tiên nhóm Whey / Đạm / Bữa sáng giàu đạm.
   - Không có dụng cụ (preferences.equipment == []) + user hỏi "Tôi tập ở nhà không có dụng cụ thì nên mua gì?"
     -> ưu tiên cat_gear (dây kháng lực, xà đơn, ab wheel).
   - Bảo mật & Trạng thái Catalog: publishState="hidden"/"draft" hoặc availability="unavailable"/"discontinued"
     TUYỆT ĐỐI KHÔNG bao giờ được trả về.
3. Smart Retrieval cho journal_articles:
   - User hỏi "Tại sao tập chân xong bị đau cơ DOMS và cách phục hồi?"
     -> trả về tối đa 3 bài viết liên quan (topic="recovery" lên đầu), KHÔNG nhồi content_body vào context.
4. Token Budget & Tích hợp ChatOperationService.handle:
   - Xác minh core3 & pro3 đưa recommendations vào prompt khi có intent phù hợp.
   - Xác minh swift3 giữ kích thước JSON context <= 1500 UTF-8 bytes và render_prompt không báo Core3PromptTooLarge
     với DEFAULT_SYSTEM_INSTRUCTION mới.
"""

import asyncio
from copy import deepcopy
from datetime import datetime, timezone
import json
from pathlib import Path
import sys

_repo_root = str(Path(__file__).parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

import pytest
from bson import ObjectId

from backend.app.services.core3_context import build_core3_context
from backend.app.services.recommendations_context import (
    build_recommendations_context,
    _normalize_text,
    _SHOP_PROJECTION,
    _JOURNAL_PROJECTION,
)
from backend.app.services.core3_provider import (
    DEFAULT_SYSTEM_INSTRUCTION,
    Core3PromptTooLarge,
    get_tier_config,
    render_prompt,
)
from backend.app.services.chat_operation_service import ChatOperationService
from backend.tests.test_cp3_batch1_context import FakeCollection, FakeCursor, FakeProvider


# ---------------------------------------------------------------------------
# Spy Collection tracking database interactions
# ---------------------------------------------------------------------------

class SpyCollection(FakeCollection):
    """Fake Mongo Collection that tracks invocation counts to verify DB-touch gates."""

    def __init__(self, name="spy_collection", documents=None, raise_on_find=False):
        super().__init__(name, documents)
        self.find_calls = 0
        self.find_one_calls = 0
        self.last_query = None
        self.last_projection = None
        self.raise_on_find = raise_on_find

    def find(self, query=None, projection=None):
        self.find_calls += 1
        self.last_query = deepcopy(query)
        self.last_projection = deepcopy(projection)
        if self.raise_on_find:
            raise RuntimeError(f"Simulated DB failure on {self.name}.find")
        return super().find(query, projection)

    def find_one(self, query=None, projection=None):
        self.find_one_calls += 1
        self.last_query = deepcopy(query)
        self.last_projection = deepcopy(projection)
        if self.raise_on_find:
            raise RuntimeError(f"Simulated DB failure on {self.name}.find_one")
        return super().find_one(query, projection)


# ---------------------------------------------------------------------------
# TEST SUITE 1: Intent Gate & Stratification
# ---------------------------------------------------------------------------

class TestIntentGateAndStratification:
    """Verify tier gating and query intent gating with zero database access."""

    @pytest.mark.parametrize("tier", ["swift3", "SWIFT3", " swift3 "])
    @pytest.mark.parametrize("query", [
        "Tôi muốn mua whey protein bổ sung đạm",
        "Tôi tập ở nhà không có dụng cụ thì nên mua gì?",
        "Tại sao tập chân xong bị đau cơ DOMS và cách phục hồi?",
        "Gợi ý sản phẩm phục hồi cơ bắp và giảm đau nhức",
    ])
    def test_swift3_tier_always_returns_skipped_and_zero_db_calls(self, tier, query):
        spy_shop = SpyCollection("shop_products", [
            {"id": "p1", "title": "Whey Isolate", "publishState": "published", "availability": "available"}
        ])
        spy_journal = SpyCollection("journal_articles", [
            {"id": "j1", "title": "DOMS Recovery", "topic": "recovery"}
        ])

        res = build_recommendations_context(
            question=query,
            base_context={"profile": {}, "nutrition": {"summary": []}},
            shop_products_collection=spy_shop,
            journal_articles_collection=spy_journal,
            tier=tier,
        )

        assert res["status"] == "skipped"
        assert res["triggered"] is False
        assert res["matched_signals"] == []
        assert res["shop_products"] == []
        assert res["journal_articles"] == []

        # Gate guarantee: zero calls to Mongo
        assert spy_shop.find_calls == 0
        assert spy_shop.find_one_calls == 0
        assert spy_journal.find_calls == 0
        assert spy_journal.find_one_calls == 0

    @pytest.mark.parametrize("tier", ["core3", "pro3"])
    @pytest.mark.parametrize("metric_query", [
        "Hôm nay tôi uống bao nhiêu nước?",
        "Hôm nay tôi còn nhiệm vụ gì?",
        "Hôm nay tôi còn nhiệm vụ nào trong hành trình?",
        "Hôm nay tôi đã hoàn thành bao nhiêu nhiệm vụ?",
        "Số bước chân hôm nay của tôi là bao nhiêu?",
    ])
    def test_pure_metric_or_log_queries_skipped_at_core3_and_pro3_with_zero_db_calls(self, tier, metric_query):
        spy_shop = SpyCollection("shop_products", [
            {"id": "p1", "title": "Whey Isolate", "publishState": "published", "availability": "available"}
        ])
        spy_journal = SpyCollection("journal_articles", [
            {"id": "j1", "title": "DOMS Recovery", "topic": "recovery"}
        ])

        res = build_recommendations_context(
            question=metric_query,
            base_context={"profile": {}, "nutrition": {"summary": []}},
            shop_products_collection=spy_shop,
            journal_articles_collection=spy_journal,
            tier=tier,
        )

        assert res["status"] == "skipped"
        assert res["triggered"] is False
        assert res["matched_signals"] == []
        assert res["shop_products"] == []
        assert res["journal_articles"] == []

        # Gate guarantee: neither shop nor journal DB touched
        assert spy_shop.find_calls == 0
        assert spy_journal.find_calls == 0

    @pytest.mark.parametrize("empty_query", ["", "   ", "\n\t", None])
    def test_empty_or_whitespace_or_none_question_skipped(self, empty_query):
        spy_shop = SpyCollection("shop_products")
        spy_journal = SpyCollection("journal_articles")

        res = build_recommendations_context(
            question=empty_query,
            base_context={},
            shop_products_collection=spy_shop,
            journal_articles_collection=spy_journal,
            tier="core3",
        )

        assert res["status"] == "skipped"
        assert res["triggered"] is False
        assert spy_shop.find_calls == 0
        assert spy_journal.find_calls == 0


# ---------------------------------------------------------------------------
# TEST SUITE 2: Smart Deficit Filtering for shop_products
# ---------------------------------------------------------------------------

class TestSmartDeficitShopProducts:
    """Verify deficit matching, catalog security, projection safety, and limit capping."""

    def test_protein_deficit_prioritizes_whey_and_protein_items_max_3(self):
        # 40g actual vs 150g target protein
        base_context = {
            "nutrition": {
                "summary": [
                    {"date": "2026-11-17", "calories": 1600, "protein_g": 40.0, "carbs_g": 180.0, "fat_g": 45.0}
                ]
            },
            "profile": {
                "data": {
                    "health_stats": {
                        "target_protein": 150.0,
                        "weight": 70.0,
                    }
                }
            },
        }

        catalog = [
            {
                "id": "prod_whey_iso",
                "title": "Whey Isolate Protein 2kg",
                "subtitle": "Bổ sung đạm tinh khiết hấp thu siêu nhanh cho người tập luyện",
                "categoryId": "cat_supplements",
                "subcategoryId": "sub_whey",
                "productType": "physical",
                "priceVnd": 1650000,
                "curatedOrder": 1,
                "publishState": "published",
                "availability": "available",
            },
            {
                "id": "prod_granola_protein",
                "title": "Granola Siêu Hạt Giàu Đạm 500g",
                "subtitle": "Bữa sáng giàu đạm tự nhiên cùng yến mạch và hạnh nhân",
                "categoryId": "cat_food_beverage",
                "subcategoryId": "sub_granola",
                "productType": "physical",
                "priceVnd": 180000,
                "curatedOrder": 2,
                "publishState": "published",
                "availability": "available",
            },
            {
                "id": "prod_oats_protein",
                "title": "Yến Mạch Bổ Sung Đạm Oat Flakes 1kg",
                "subtitle": "Yến mạch nguyên cám giàu dinh dưỡng cho bữa phụ",
                "categoryId": "cat_food_beverage",
                "subcategoryId": "sub_oats",
                "productType": "physical",
                "priceVnd": 95000,
                "curatedOrder": 3,
                "publishState": "published",
                "availability": "available",
            },
            {
                "id": "prod_powerband",
                "title": "Dây Kháng Lực PowerBand Tập Mông Đùi",
                "subtitle": "Dây thun cao su tự nhiên cao cấp",
                "categoryId": "cat_gear",
                "subcategoryId": "sub_bands",
                "productType": "physical",
                "priceVnd": 250000,
                "curatedOrder": 4,
                "publishState": "published",
                "availability": "available",
            },
            {
                "id": "prod_shaker",
                "title": "Bình Lắc Shaker 700ml Có Lưới Đánh",
                "subtitle": "Bình nước nhựa Tritan an toàn",
                "categoryId": "cat_gear",
                "subcategoryId": "sub_bottles",
                "productType": "physical",
                "priceVnd": 120000,
                "curatedOrder": 5,
                "publishState": "published",
                "availability": "available",
            },
        ]

        spy_shop = SpyCollection("shop_products", catalog)
        question = "Tôi đang thiếu đạm thì nên bổ sung sản phẩm nào?"

        res = build_recommendations_context(
            question=question,
            base_context=base_context,
            shop_products_collection=spy_shop,
            tier="core3",
        )

        assert res["status"] == "available"
        assert res["triggered"] is True
        assert "protein_deficit" in res["matched_signals"]

        # Bound check: maximum 3 items
        products = res["shop_products"]
        assert 1 <= len(products) <= 3

        # Ordering check: prioritized protein & whey & oat products
        returned_ids = [p["id"] for p in products]
        assert "prod_whey_iso" in returned_ids
        # None of the pure gear items should outrank protein/whey/granola items
        assert "prod_powerband" not in returned_ids

        # Ensure schema structure
        for prod in products:
            assert set(prod.keys()) == {"id", "title", "subtitle", "category_id", "price_vnd"}
            assert prod["price_vnd"] is not None

    def test_no_equipment_prioritizes_cat_gear(self):
        base_context = {
            "preferences": {
                "equipment": [],  # No gym gear available
            },
            "profile": {
                "data": {"health_stats": {"weight": 65.0}}
            },
        }

        catalog = [
            {
                "id": "gear_band",
                "title": "Bộ Dây Kháng Lực Ngũ Sắc Tập Toàn Thân",
                "subtitle": "5 mức kháng lực tập tại nhà không cần tạ",
                "categoryId": "cat_gear",
                "subcategoryId": "sub_resistance_bands",
                "productType": "physical",
                "priceVnd": 220000,
                "curatedOrder": 1,
                "publishState": "published",
                "availability": "available",
            },
            {
                "id": "gear_pullup_bar",
                "title": "Xà Đơn Gắn Cửa Không Cần Khoan",
                "subtitle": "Xà đơn hít xà tập lưng xô tại nhà chịu tải 200kg",
                "categoryId": "cat_gear",
                "subcategoryId": "sub_pullup_bars",
                "productType": "physical",
                "priceVnd": 310000,
                "curatedOrder": 2,
                "publishState": "published",
                "availability": "available",
            },
            {
                "id": "gear_ab_wheel",
                "title": "Con Lăn Tập Bụng Ab Wheel Tự Hồi",
                "subtitle": "Dụng cụ tập cơ bụng 6 múi hiệu quả",
                "categoryId": "cat_gear",
                "subcategoryId": "sub_core_trainers",
                "productType": "physical",
                "priceVnd": 180000,
                "curatedOrder": 3,
                "publishState": "published",
                "availability": "available",
            },
            {
                "id": "supp_whey",
                "title": "Whey Gold Standard 5lbs",
                "subtitle": "Đạm whey hỗ trợ cơ bắp",
                "categoryId": "cat_supplements",
                "subcategoryId": "sub_whey",
                "productType": "physical",
                "priceVnd": 1750000,
                "curatedOrder": 4,
                "publishState": "published",
                "availability": "available",
            },
        ]

        spy_shop = SpyCollection("shop_products", catalog)
        question = "Tôi tập ở nhà không có dụng cụ thì nên mua gì?"

        res = build_recommendations_context(
            question=question,
            base_context=base_context,
            shop_products_collection=spy_shop,
            tier="core3",
        )

        assert res["status"] == "available"
        assert res["triggered"] is True
        assert "no_equipment" in res["matched_signals"]

        products = res["shop_products"]
        assert 1 <= len(products) <= 3

        returned_ids = [p["id"] for p in products]
        # Must prioritize cat_gear (dây kháng lực, xà đơn, ab wheel)
        assert "gear_band" in returned_ids or "gear_pullup_bar" in returned_ids or "gear_ab_wheel" in returned_ids
        for p in products:
            assert p["category_id"] == "cat_gear"

    def test_catalog_security_strictly_excludes_hidden_draft_and_unavailable_items(self):
        catalog = [
            # 1. Hidden item (must be blocked)
            {
                "id": "p_hidden",
                "title": "Whey Protein 100% Siêu Rẻ Bị Ẩn",
                "subtitle": "Sản phẩm ẩn không bán công khai",
                "categoryId": "cat_supplements",
                "priceVnd": 500000,
                "publishState": "hidden",
                "availability": "available",
            },
            # 2. Draft item (must be blocked)
            {
                "id": "p_draft",
                "title": "Whey Isolate Bản Nháp Chưa Duyệt",
                "subtitle": "Sản phẩm bản nháp",
                "categoryId": "cat_supplements",
                "priceVnd": 990000,
                "publishState": "draft",
                "availability": "available",
            },
            # 3. Unavailable item (must be blocked)
            {
                "id": "p_unavail",
                "title": "Dây Kháng Lực Tạm Hết Hàng",
                "subtitle": "Tạm thời hết hàng trong kho",
                "categoryId": "cat_gear",
                "priceVnd": 150000,
                "publishState": "published",
                "availability": "unavailable",
            },
            # 4. Discontinued item (must be blocked)
            {
                "id": "p_discontinued",
                "title": "Xà Đơn Ngừng Kinh Doanh",
                "subtitle": "Đã ngừng sản xuất và phân phối",
                "categoryId": "cat_gear",
                "priceVnd": 250000,
                "publishState": "published",
                "availability": "discontinued",
            },
            # 5. Legitimate published and available item
            {
                "id": "p_valid_whey",
                "title": "Whey Isolate Hợp Lệ Chính Hãng",
                "subtitle": "Đầy đủ kiểm định y tế",
                "categoryId": "cat_supplements",
                "priceVnd": 1400000,
                "publishState": "published",
                "availability": "available",
                "curatedOrder": 1,
            },
            # 6. Legitimate published and available item 2
            {
                "id": "p_valid_plant_protein",
                "title": "Đạm Thực Vật Hữu Cơ Cao Cấp",
                "subtitle": "Nguồn protein thuần thực vật",
                "categoryId": "cat_supplements",
                "priceVnd": 1200000,
                "publishState": "published",
                "availability": "available",
                "curatedOrder": 2,
            },
        ]

        spy_shop = SpyCollection("shop_products", catalog)
        question = "Tôi muốn mua whey protein và đạm thực vật"

        res = build_recommendations_context(
            question=question,
            base_context={},
            shop_products_collection=spy_shop,
            tier="core3",
        )

        assert res["status"] == "available"
        assert res["triggered"] is True

        returned_ids = [p["id"] for p in res["shop_products"]]

        # Critical security assertions: non-published or non-available items must NEVER leak
        assert "p_hidden" not in returned_ids
        assert "p_draft" not in returned_ids
        assert "p_unavail" not in returned_ids
        assert "p_discontinued" not in returned_ids

        # Only legitimate items allowed
        assert "p_valid_whey" in returned_ids
        assert "p_valid_plant_protein" in returned_ids

        # Verify DB query filter passed to find()
        assert spy_shop.last_query == {"publishState": "published", "availability": "available"}

    def test_shop_projection_does_not_leak_internal_pricing_or_pii(self):
        catalog = [
            {
                "_id": ObjectId("607f1f77bcf86cd799439011"),
                "id": "prod_secure",
                "title": "Whey Protein Safe",
                "subtitle": "A" * 200,  # Longer than 100 characters to test truncation
                "categoryId": "cat_supplements",
                "subcategoryId": "sub_whey",
                "productType": "physical",
                "priceVnd": 1500000,
                "costPrice": 600000,  # Sensitive internal cost
                "supplierEmail": "supplier@internal.corp",  # Sensitive supplier PII
                "margin": 0.6,
                "curatedOrder": 1,
                "publishState": "published",
                "availability": "available",
            }
        ]

        spy_shop = SpyCollection("shop_products", catalog)
        res = build_recommendations_context(
            question="Gợi ý sản phẩm whey",
            base_context={},
            shop_products_collection=spy_shop,
            tier="core3",
        )

        assert res["status"] == "available"
        prod = res["shop_products"][0]

        # Verify allowlisted fields only
        assert set(prod.keys()) == {"id", "title", "subtitle", "category_id", "price_vnd"}
        assert "_id" not in prod
        assert "costPrice" not in prod
        assert "supplierEmail" not in prod
        assert "margin" not in prod
        assert len(prod["subtitle"]) <= 100


# ---------------------------------------------------------------------------
# TEST SUITE 3: Smart Retrieval for journal_articles
# ---------------------------------------------------------------------------

class TestSmartJournalArticlesRetrieval:
    """Verify topic relevance, DOMS/recovery prioritization, and zero content_body leakage."""

    def test_doms_and_recovery_question_prioritizes_recovery_topic_max_3(self):
        articles = [
            {
                "_id": ObjectId("607f1f77bcf86cd799439021"),
                "id": "art_doms_legs",
                "title": "DOMS là gì? Cách phục hồi cơ bắp sau ngày tập chân",
                "summary": "Đau nhức cơ bắp khởi phát muộn (DOMS) thường xuất hiện sau 24-48 giờ tập chân nặng. "
                           "Các biện pháp phục hồi hiệu quả bao gồm ngủ đủ giấc, bổ sung protein và giãn cơ.",
                "topic": "recovery",
                "read_time_minutes": 5,
                "tags": ["doms", "dau co", "phuc hoi", "tap chan"],
                "content_body": "Nội dung bài viết rất dài chứa hàng nghìn từ...",
            },
            {
                "_id": ObjectId("607f1f77bcf86cd799439022"),
                "id": "art_sleep_recovery",
                "title": "Tối ưu giấc ngủ và dinh dưỡng để phục hồi cơ bắp nhanh",
                "summary": "Giấc ngủ sâu từ 7-9 tiếng là thời điểm cơ thể tiết hormone tăng trưởng GH giúp phục hồi mô cơ bị tổn thương.",
                "topic": "recovery",
                "read_time_minutes": 6,
                "tags": ["giac ngu", "phuc hoi", "co bap"],
                "content_body": "Chi tiết các giai đoạn của giấc ngủ REM...",
            },
            {
                "_id": ObjectId("607f1f77bcf86cd799439023"),
                "id": "art_foam_roller",
                "title": "Kỹ thuật giãn cơ và Foam Roller giảm đau nhức tức thì",
                "summary": "Hướng dẫn tự giải phóng mạc cơ (SMR) bằng con lăn foam roller giúp giải tỏa căng thẳng bắp chân và đùi.",
                "topic": "recovery",
                "read_time_minutes": 4,
                "tags": ["foam roller", "gian co", "dau nhuc", "phuc hoi"],
                "content_body": "Các vị trí lăn con lăn foam roller...",
            },
            {
                "_id": ObjectId("607f1f77bcf86cd799439024"),
                "id": "art_macro_calc",
                "title": "Bí quyết tính macro và calo cho người mới bắt đầu",
                "summary": "Cách phân bổ tỷ lệ protein, carbs và fat theo cân nặng và mục tiêu tăng cơ giảm mỡ.",
                "topic": "nutrition",
                "read_time_minutes": 7,
                "tags": ["macro", "calo", "dinh duong"],
                "content_body": "Công thức Mifflin-St Jeor...",
            },
            {
                "_id": ObjectId("607f1f77bcf86cd799439025"),
                "id": "art_ppl_split",
                "title": "Lịch tập Push Pull Legs chuẩn khoa học cho gymer",
                "summary": "Phân chia các nhóm cơ đẩy, kéo và chân hợp lý để tối ưu tần suất tập luyện hàng tuần.",
                "topic": "training",
                "read_time_minutes": 8,
                "tags": ["lich tap", "ppl", "progressive overload"],
                "content_body": "Các bài tập Bench Press, Barbell Row...",
            },
        ]

        spy_journal = SpyCollection("journal_articles", articles)
        question = "Tại sao tập chân xong bị đau cơ DOMS và cách phục hồi?"

        res = build_recommendations_context(
            question=question,
            base_context={},
            journal_articles_collection=spy_journal,
            tier="core3",
        )

        assert res["status"] == "available"
        assert res["triggered"] is True
        assert "recovery_need" in res["matched_signals"]

        returned_articles = res["journal_articles"]
        assert 1 <= len(returned_articles) <= 3

        returned_ids = [a["id"] for a in returned_articles]
        # Most relevant DOMS & recovery article must be at the top
        assert returned_ids[0] == "art_doms_legs"
        # All returned articles should have topic recovery
        for art in returned_articles:
            assert art["topic"] == "recovery"
            assert art["summary"] is not None

    def test_no_content_body_stuffed_into_context_under_any_circumstance(self):
        articles = [
            {
                "_id": ObjectId("607f1f77bcf86cd799439026"),
                "id": "art_large_body",
                "title": "Nguyên lý phục hồi cơ bắp và giảm đau cơ sau tập",
                "summary": "Tóm tắt ngắn gọn dưới 120 ký tự về cách phục hồi cơ bắp và chống viêm sau vận động mạnh.",
                "topic": "recovery",
                "read_time_minutes": 5,
                "tags": ["phuc hoi", "dau co", "doms"],
                "content_body": "X" * 50000,  # 50KB heavy article body
                "full_text": "Y" * 30000,
                "author_id": "author_private_123",
                "editor_notes": "Internal review passed",
            }
        ]

        spy_journal = SpyCollection("journal_articles", articles)
        res = build_recommendations_context(
            question="Tại sao bị đau cơ DOMS sau tập và nguyên lý phục hồi?",
            base_context={},
            journal_articles_collection=spy_journal,
            tier="pro3",
        )

        assert res["status"] == "available"
        art = res["journal_articles"][0]

        # Explicit requirement verification: KHÔNG nhồi content_body vào context
        assert "content_body" not in art
        assert "full_text" not in art
        assert "author_id" not in art
        assert "editor_notes" not in art
        assert "_id" not in art

        # Allowlisted fields only
        assert set(art.keys()) == {"id", "title", "summary", "topic", "read_time_minutes"}
        assert len(art["summary"]) <= 120


# ---------------------------------------------------------------------------
# TEST SUITE 4: Token Budget & ChatOperationService Integration
# ---------------------------------------------------------------------------

class TestIntegrationTokenBudgetAndChatService:
    """Verify prompt integration, token budget limits, and fail-soft behavior."""

    def test_chat_operation_service_core3_includes_recommendations_in_llm_prompt(self):
        uid = "u_rec_core3"
        email = "rec_core3@example.com"
        db = {"chat_operations": FakeCollection("chat_operations")}
        conv_col = FakeCollection("conversations")
        fake_provider = FakeProvider(reply_text="Bạn đang thiếu đạm, tôi gợi ý bổ sung Whey Isolate 2kg.")

        shop_catalog = [
            {
                "id": "prod_whey_iso_premium",
                "title": "Whey Isolate Protein 2kg",
                "subtitle": "Bổ sung đạm tinh khiết",
                "categoryId": "cat_supplements",
                "priceVnd": 1650000,
                "curatedOrder": 1,
                "publishState": "published",
                "availability": "available",
            }
        ]
        shop_col = FakeCollection("shop_products", shop_catalog)

        nutrition_col = FakeCollection("nutrition", [
            {
                "user_id": uid,
                "date": "2026-11-17",
                "total_calories": 1500,
                "total_protein": 35.0,
                "total_carbs": 160.0,
                "total_fat": 40.0,
            }
        ])
        users_col = FakeCollection("users", [
            {
                "_id": uid,
                "email": email,
                "health_stats": {"target_protein": 140.0, "weight": 68.0},
            }
        ])

        question = "Tôi đang thiếu đạm thì nên bổ sung sản phẩm nào?"

        # Context builder integrating Core 3 context + Recommendations context
        def context_builder_core3_with_recs(**kwargs):
            ctx = build_core3_context(**kwargs)
            tier = kwargs.get("tier", "core3")
            recs = build_recommendations_context(
                question=question,
                base_context=ctx,
                shop_products_collection=shop_col,
                tier=tier,
            )
            ctx["recommendations"] = recs
            return ctx

        service = ChatOperationService(
            db=db,
            conversations=conv_col,
            nutrition=nutrition_col,
            workouts=FakeCollection("workouts"),
            users=users_col,
            provider=fake_provider,
            context_builder=context_builder_core3_with_recs,
        )

        op_id = "11112222333344445555666677778888"
        res = asyncio.run(
            service.handle(
                principal={"_id": uid, "email": email},
                operation_id=op_id,
                contract_version="core3-local-v1",
                message=question,
                ai_mode="core3",
            )
        )

        assert res["status"] == "success"
        assert len(fake_provider.captured_prompts) == 1
        prompt_text, mode = fake_provider.captured_prompts[0]
        assert mode == "core3"

        # Prompt must include shop product recommendation grounded in context
        assert "recommendations" in prompt_text
        assert "Whey Isolate Protein 2kg" in prompt_text
        assert "1650000" in prompt_text
        assert "cat_supplements" in prompt_text

    def test_chat_operation_service_pro3_includes_journal_recommendations_in_llm_prompt(self):
        uid = "u_rec_pro3"
        email = "rec_pro3@example.com"
        db = {"chat_operations": FakeCollection("chat_operations")}
        conv_col = FakeCollection("conversations")
        fake_provider = FakeProvider(reply_text="Để phục hồi sau ngày tập chân, bạn có thể tham khảo bài viết DOMS.")

        articles = [
            {
                "id": "art_doms_guide",
                "title": "Cẩm nang phục hồi đau cơ DOMS sau tập chân",
                "summary": "Phân tích nguyên nhân vi tổn thương sợi cơ và chiến lược giảm đau nhanh.",
                "topic": "recovery",
                "read_time_minutes": 5,
                "tags": ["doms", "dau co", "phuc hoi"],
                "content_body": "Chi tiết kỹ thuật hồi phục...",
            }
        ]
        journal_col = FakeCollection("journal_articles", articles)

        question = "Tại sao tập chân xong bị đau cơ DOMS và cách phục hồi?"

        def context_builder_pro3_with_recs(**kwargs):
            ctx = build_core3_context(**kwargs)
            tier = kwargs.get("tier", "pro3")
            recs = build_recommendations_context(
                question=question,
                base_context=ctx,
                journal_articles_collection=journal_col,
                tier=tier,
            )
            ctx["recommendations"] = recs
            return ctx

        service = ChatOperationService(
            db=db,
            conversations=conv_col,
            nutrition=FakeCollection("nutrition"),
            workouts=FakeCollection("workouts"),
            users=FakeCollection("users"),
            provider=fake_provider,
            context_builder=context_builder_pro3_with_recs,
        )

        op_id = "99998888777766665555444433332222"
        res = asyncio.run(
            service.handle(
                principal={"_id": uid, "email": email},
                operation_id=op_id,
                contract_version="core3-local-v1",
                message=question,
                ai_mode="pro3",
            )
        )

        assert res["status"] == "success"
        assert len(fake_provider.captured_prompts) == 1
        prompt_text, mode = fake_provider.captured_prompts[0]
        assert mode == "pro3"

        # Prompt must include journal article recommendation grounded in context
        assert "recommendations" in prompt_text
        assert "Cẩm nang phục hồi đau cơ DOMS sau tập chân" in prompt_text
        assert "recovery" in prompt_text
        # Must not contain content_body
        assert "Chi tiết kỹ thuật hồi phục..." not in prompt_text

    def test_swift3_context_json_under_1500_bytes_and_render_prompt_never_raises_prompt_too_large(self):
        uid = "u_swift3_budget"
        email = "swift3_budget@example.com"

        nutrition_col = FakeCollection("nutrition", [
            {
                "user_id": uid,
                "date": "2026-11-17",
                "total_calories": 1800,
                "total_protein": 90.0,
                "total_carbs": 200.0,
                "total_fat": 50.0,
            }
        ])
        workout_col = FakeCollection("workouts", [
            {
                "user_id": uid,
                "date": "2026-11-17",
                "plan_name": "Quick Workout",
                "total_duration_minutes": 30,
                "total_volume_kg": 1500,
                "exercise_logs": [
                    {
                        "exercise_slug": "push-ups",
                        "sets": 3,
                        "reps": 15,
                    }
                ],
            }
        ])
        users_col = FakeCollection("users", [
            {
                "_id": uid,
                "email": email,
                "health_stats": {
                    "water_target_ml": 2000,
                    "target_protein": 120.0,
                },
                "profile": {"weight": 65.0, "height": 172.0, "age": 28, "gender": "male"},
            }
        ])
        water_col = FakeCollection("water", [
            {"user_id": uid, "date": "2026-11-17", "amount_ml": 1500}
        ])

        question = "Hôm nay tôi uống bao nhiêu nước?"

        # 1. Build Swift3 context
        swift_ctx = build_core3_context(
            principal={"_id": uid, "email": email},
            nutrition_collection=nutrition_col,
            workout_collection=workout_col,
            users_collection=users_col,
            water_collection=water_col,
            tier="swift3",
        )

        # 2. Attach skipped recommendations (or build_recommendations_context output for swift3)
        swift_recs = build_recommendations_context(
            question=question,
            base_context=swift_ctx,
            shop_products_collection=FakeCollection("shop_products"),
            journal_articles_collection=FakeCollection("journal_articles"),
            tier="swift3",
        )
        assert swift_recs["status"] == "skipped"
        swift_ctx["recommendations"] = swift_recs

        # 3. Verify JSON context UTF-8 encoded bytes <= 1500
        json_bytes = json.dumps(swift_ctx, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        assert len(json_bytes) <= 1500, f"Swift3 JSON context is {len(json_bytes)} bytes > 1500 bytes"

        # 4. Verify render_prompt succeeds without Core3PromptTooLarge with the new DEFAULT_SYSTEM_INSTRUCTION
        history = [
            {"role": "user", "content": "Chào Coach!"},
            {"role": "model", "content": "Chào bạn, hôm nay bạn đã tập luyện thế nào?"},
        ]
        prompt = render_prompt(
            question=question,
            history=history,
            context=swift_ctx,
            system_instruction=DEFAULT_SYSTEM_INSTRUCTION,
            ai_mode="swift3",
        )

        assert isinstance(prompt, str)
        swift_max_tokens = get_tier_config("swift3")["max_input_tokens"]
        assert len(prompt.encode("utf-8")) <= swift_max_tokens

    def test_fail_soft_behavior_when_collections_are_missing_or_raise_exception(self):
        question = "Gợi ý sản phẩm whey và bài viết phục hồi"

        # Case 1: Collections are None
        res_none = build_recommendations_context(
            question=question,
            base_context={},
            shop_products_collection=None,
            journal_articles_collection=None,
            tier="core3",
        )
        assert res_none["status"] == "unavailable"
        assert res_none["triggered"] is True
        assert res_none["shop_products"] == []
        assert res_none["journal_articles"] == []

        # Case 2: Collections raise exceptions (DB crash)
        spy_failing_shop = SpyCollection("shop_products", raise_on_find=True)
        spy_failing_journal = SpyCollection("journal_articles", raise_on_find=True)

        res_err = build_recommendations_context(
            question=question,
            base_context={},
            shop_products_collection=spy_failing_shop,
            journal_articles_collection=spy_failing_journal,
            tier="core3",
        )
        # Fail-soft: no exception escapes, empty result returned safely
        assert res_err["status"] == "empty"
        assert res_err["triggered"] is True
        assert res_err["shop_products"] == []
        assert res_err["journal_articles"] == []
