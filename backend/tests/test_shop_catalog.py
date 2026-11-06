"""
Unit and Integration Tests for Saman Shop Catalog Backend & Admin Workflow.
Subsystem: Saman Shop — Boutique Catalog & Curation (SHOP-EXP-02).

Validates:
- Public endpoints (/api/shop/categories, /api/shop/collections, /api/shop/products, /api/shop/products/{id}, /api/shop/products/batch).
- 5 Canonical Categories (cat_gear: 16, cat_apparel: 20, cat_food_beverage: 24, cat_supplements: 8, cat_recovery_lifestyle: 12) = 80 active items.
- 6 Curated Collections.
- 4 Retained Hidden Products (prod_rc_02, prod_mp_02, prod_mp_04, prod_mp_08) = 84 total catalog records.
- Subcategory filtering and query parameter (subcategoryId).
- Vietnamese diacritic-insensitive search across gear, apparel, food, supplement, and recovery items.
- Cursor pagination across 80 items with stable ordering and mismatch detection.
- Batch lookup preserving requested order and returning null for hidden/missing items.
- Typed attributes round-trip: equipment, apparel (swatches, sizes), food (macros, allergens), supplements (active ingredients, form), lifestyle (capacity, safety).
- Nullable price semantics and numerical 0 preserving.
- Controlled taxonomy migration (dry-run & idempotent apply).
- Admin seed idempotency preserving modified content.
"""

from datetime import datetime, timezone
import unittest
from fastapi.testclient import TestClient

from backend.app.models.shop import (
    ActiveIngredientModel,
    AllergenStatusEnum,
    ApparelAttributesModel,
    ApparelColorSwatchModel,
    ContentProvenance,
    EquipmentAttributesModel,
    FoodAttributesModel,
    LifestyleAttributesModel,
    MacroNutrientsModel,
    ProductAvailability,
    ProductSourceType,
    PublishState,
    ShopProductAdminInput,
    SupplementAttributesModel,
    SupplementFormEnum,
)
from backend.app.services.shop_service import (
    ShopCatalogException,
    ShopInvalidCursorException,
    ShopInvalidQueryException,
    ShopNotFoundException,
    ShopService,
    migrate_catalog_taxonomy,
    normalize_vietnamese,
)
from backend.app.shop_database import (
    COLL_SHOP_CATEGORIES,
    COLL_SHOP_COLLECTIONS,
    COLL_SHOP_PRODUCTS,
    ensure_shop_indexes,
)
from backend.main import app


class InMemoryMockCollection:
    """Mock MongoDB collection storing documents in memory."""
    def __init__(self, name: str):
        self.name = name
        self.docs = []

    def find(self, filter_dict=None, projection=None):
        filter_dict = filter_dict or {}
        results = []
        for doc in self.docs:
            match = True
            for k, v in filter_dict.items():
                if k == "id" and isinstance(v, dict) and "$in" in v:
                    if doc.get("id") not in v["$in"]:
                        match = False
                        break
                elif k == "collectionIds":
                    # array contains check
                    if v not in doc.get("collectionIds", []):
                        match = False
                        break
                elif doc.get(k) != v:
                    match = False
                    break
            if match:
                res = dict(doc)
                if projection and projection.get("_id") == 0 and "_id" in res:
                    del res["_id"]
                results.append(res)

        class Cursor:
            def __init__(self, data):
                self._data = data

            def sort(self, sort_keys):
                for key, direction in reversed(sort_keys):
                    self._data.sort(key=lambda d: d.get(key, 0) or "", reverse=(direction == -1))
                return self

            def __iter__(self):
                return iter(self._data)

            def __list__(self):
                return list(self._data)

        return Cursor(results)

    def find_one(self, filter_dict=None, projection=None):
        cursor = self.find(filter_dict, projection)
        results = list(cursor)
        return results[0] if results else None

    def insert_one(self, doc):
        d = dict(doc)
        if "_id" not in d:
            d["_id"] = str(len(self.docs) + 1)
        self.docs.append(d)

        class Result:
            inserted_id = d["_id"]

        return Result()

    def update_one(self, filter_dict, update_dict, upsert=False):
        found_idx = None
        for i, d in enumerate(self.docs):
            match = True
            for k, v in filter_dict.items():
                if d.get(k) != v:
                    match = False
                    break
            if match:
                found_idx = i
                break

        class Result:
            upserted_id = None
            modified_count = 0

        res = Result()
        if found_idx is not None:
            if "$set" in update_dict:
                self.docs[found_idx].update(update_dict["$set"])
            res.modified_count = 1
        elif upsert:
            new_doc = dict(filter_dict)
            if "$setOnInsert" in update_dict:
                new_doc.update(update_dict["$setOnInsert"])
            if "$set" in update_dict:
                new_doc.update(update_dict["$set"])
            new_doc["_id"] = str(len(self.docs) + 1)
            self.docs.append(new_doc)
            res.upserted_id = new_doc["_id"]
        return res

    def replace_one(self, filter_dict, replacement_doc, upsert=False):
        found_idx = None
        for i, d in enumerate(self.docs):
            match = True
            for k, v in filter_dict.items():
                if d.get(k) != v:
                    match = False
                    break
            if match:
                found_idx = i
                break

        class Result:
            upserted_id = None
            modified_count = 0

        res = Result()
        if found_idx is not None:
            self.docs[found_idx] = dict(replacement_doc)
            res.modified_count = 1
        elif upsert:
            new_doc = dict(replacement_doc)
            new_doc["_id"] = str(len(self.docs) + 1)
            self.docs.append(new_doc)
            res.upserted_id = new_doc["_id"]
        return res

    def create_index(self, keys, **options):
        return options.get("name", "idx_mock")


class InMemoryMockDB:
    def __init__(self):
        self.collections = {
            COLL_SHOP_PRODUCTS: InMemoryMockCollection(COLL_SHOP_PRODUCTS),
            COLL_SHOP_CATEGORIES: InMemoryMockCollection(COLL_SHOP_CATEGORIES),
            COLL_SHOP_COLLECTIONS: InMemoryMockCollection(COLL_SHOP_COLLECTIONS),
        }

    def __getitem__(self, name: str):
        if name not in self.collections:
            self.collections[name] = InMemoryMockCollection(name)
        return self.collections[name]


class TestShopCatalog(unittest.TestCase):
    def setUp(self):
        self.mock_db = InMemoryMockDB()
        self.service = ShopService(db_instance=self.mock_db)
        # Seed default catalog into mock DB (force_overwrite=True for clean test slate)
        self.service.seed_default_catalog(force_overwrite=True)

        # Create test client with dependency override
        from backend.routers.shop import get_shop_service
        app.dependency_overrides[get_shop_service] = lambda: self.service
        self.client = TestClient(app)

    def tearDown(self):
        app.dependency_overrides.clear()

    # ──────────────────────────────────────────────────────────────────────────
    # Vietnamese Normalization Tests
    # ──────────────────────────────────────────────────────────────────────────

    def test_normalize_vietnamese(self):
        self.assertEqual(normalize_vietnamese("Bình Lắc Thép Không Gỉ"), "binh lac thep khong gi")
        self.assertEqual(normalize_vietnamese("Đòn Tạ 50mm"), "don ta 50mm")
        self.assertEqual(normalize_vietnamese("ĐĨA TẠ ĐÔI"), "dia ta doi")
        self.assertEqual(normalize_vietnamese("   Đệm Mút Neoprene   "), "dem mut neoprene")
        self.assertEqual(normalize_vietnamese("Yến Mạch Cán Dẹt Úc"), "yen mach can det uc")
        self.assertEqual(normalize_vietnamese("Bột Đạm Whey Isolate"), "bot dam whey isolate")

    # ──────────────────────────────────────────────────────────────────────────
    # Categories & Collections Endpoints
    # ──────────────────────────────────────────────────────────────────────────

    def test_get_categories(self):
        resp = self.client.get("/api/shop/categories")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data), 5)
        cat_ids = [c["id"] for c in data]
        self.assertEqual(
            cat_ids,
            ["cat_gear", "cat_apparel", "cat_food_beverage", "cat_supplements", "cat_recovery_lifestyle"],
        )

    def test_get_collections(self):
        resp = self.client.get("/api/shop/collections")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(len(data), 6)
        col_ids = [c["id"] for c in data]
        self.assertEqual(
            col_ids,
            [
                "col_home_starter",
                "col_gym_bag",
                "col_quick_breakfast",
                "col_portable_snacks",
                "col_meal_prep",
                "col_active_wear",
            ],
        )

    # ──────────────────────────────────────────────────────────────────────────
    # Product Quota & Active Catalog Tests (80 Active + 4 Hidden = 84 Total)
    # ──────────────────────────────────────────────────────────────────────────

    def test_exact_active_and_hidden_quota(self):
        # 1. Total records in DB (admin list) must be exactly 84
        all_prods = self.service.list_admin_products(include_hidden=True)
        self.assertEqual(len(all_prods), 84)

        # 2. Hidden records must be exactly 4 with designated IDs
        hidden_prods = [p for p in all_prods if p.get("publishState") == "hidden"]
        self.assertEqual(len(hidden_prods), 4)
        hidden_ids = {p["id"] for p in hidden_prods}
        self.assertEqual(hidden_ids, {"prod_rc_02", "prod_mp_02", "prod_mp_04", "prod_mp_08"})

        # 3. Public products must be exactly 80 active
        active_prods = [p for p in all_prods if p.get("publishState") == "published"]
        self.assertEqual(len(active_prods), 80)

        # 4. Quota by Category in active products:
        gear_count = sum(1 for p in active_prods if p["categoryId"] == "cat_gear")
        apparel_count = sum(1 for p in active_prods if p["categoryId"] == "cat_apparel")
        food_count = sum(1 for p in active_prods if p["categoryId"] == "cat_food_beverage")
        supp_count = sum(1 for p in active_prods if p["categoryId"] == "cat_supplements")
        rec_count = sum(1 for p in active_prods if p["categoryId"] == "cat_recovery_lifestyle")

        self.assertEqual(gear_count, 16, "Dụng cụ tập quota must be 16")
        self.assertEqual(apparel_count, 20, "Thời trang thể thao quota must be 20")
        self.assertEqual(food_count, 24, "Thực phẩm & đồ uống quota must be 24")
        self.assertEqual(supp_count, 8, "Thực phẩm bổ sung quota must be 8")
        self.assertEqual(rec_count, 12, "Phục hồi & sinh hoạt quota must be 12")

    # ──────────────────────────────────────────────────────────────────────────
    # Product Listing & Pagination Across 80 Active Items
    # ──────────────────────────────────────────────────────────────────────────

    def test_get_products_pagination_across_80_items(self):
        # Page 1: pageSize 20 (items 1..20)
        resp1 = self.client.get("/api/shop/products?pageSize=20")
        self.assertEqual(resp1.status_code, 200)
        data1 = resp1.json()
        self.assertEqual(len(data1["items"]), 20)
        self.assertTrue(data1["hasMore"])
        self.assertIsNotNone(data1["nextCursor"])

        # Page 2: pageSize 20 (items 21..40)
        resp2 = self.client.get(f"/api/shop/products?pageSize=20&cursor={data1['nextCursor']}")
        self.assertEqual(resp2.status_code, 200)
        data2 = resp2.json()
        self.assertEqual(len(data2["items"]), 20)
        self.assertTrue(data2["hasMore"])

        # Page 3: pageSize 20 (items 41..60)
        resp3 = self.client.get(f"/api/shop/products?pageSize=20&cursor={data2['nextCursor']}")
        self.assertEqual(resp3.status_code, 200)
        data3 = resp3.json()
        self.assertEqual(len(data3["items"]), 20)
        self.assertTrue(data3["hasMore"])

        # Page 4: pageSize 20 (items 61..80) -> final page
        resp4 = self.client.get(f"/api/shop/products?pageSize=20&cursor={data3['nextCursor']}")
        self.assertEqual(resp4.status_code, 200)
        data4 = resp4.json()
        self.assertEqual(len(data4["items"]), 20)
        self.assertFalse(data4["hasMore"])
        self.assertIsNone(data4["nextCursor"])

        # Verify zero overlap and exactly 80 unique items
        all_ids = set()
        for page_data in [data1, data2, data3, data4]:
            page_ids = {p["id"] for p in page_data["items"]}
            self.assertEqual(len(all_ids.intersection(page_ids)), 0, "Pages must not overlap")
            all_ids.update(page_ids)

        self.assertEqual(len(all_ids), 80, "Total paginated items must be 80 active")

    def test_cursor_mismatch_returns_400(self):
        resp = self.client.get("/api/shop/products?categoryId=cat_gear&pageSize=4")
        self.assertEqual(resp.status_code, 200)
        cursor = resp.json()["nextCursor"]
        self.assertIsNotNone(cursor)

        resp_mismatch = self.client.get(f"/api/shop/products?categoryId=cat_apparel&cursor={cursor}")
        self.assertEqual(resp_mismatch.status_code, 400)
        self.assertEqual(resp_mismatch.json()["detail"]["code"], "INVALID_CURSOR")

    def test_cursor_with_subcategory_binding(self):
        # Query with subcategoryId bound into cursor
        resp = self.client.get(
            "/api/shop/products?categoryId=cat_gear&subcategoryId=Ph%E1%BB%A5%20ki%E1%BB%87n%20k%C3%A9o%20l%C6%B0ng&pageSize=1"
        )
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        cursor = data["nextCursor"]
        self.assertIsNotNone(cursor)

        # Re-query with same subcategory -> succeeds
        resp_next = self.client.get(
            f"/api/shop/products?categoryId=cat_gear&subcategoryId=Ph%E1%BB%A5%20ki%E1%BB%87n%20k%C3%A9o%20l%C6%B0ng&pageSize=1&cursor={cursor}"
        )
        self.assertEqual(resp_next.status_code, 200)

        # Re-query with different subcategory -> cursor mismatch 400
        resp_bad = self.client.get(
            f"/api/shop/products?categoryId=cat_gear&subcategoryId=D%C3%A2y%20kh%C3%A1ng%20l%E1%BB%B1c&cursor={cursor}"
        )
        self.assertEqual(resp_bad.status_code, 400)
        self.assertEqual(resp_bad.json()["detail"]["code"], "INVALID_CURSOR")

    # ──────────────────────────────────────────────────────────────────────────
    # Filtering, Legacy Aliases & Search Tests
    # ──────────────────────────────────────────────────────────────────────────

    def test_category_and_legacy_alias_filter(self):
        # Canonical cat_gear: 16 items
        resp1 = self.client.get("/api/shop/products?categoryId=cat_gear&pageSize=50")
        self.assertEqual(resp1.status_code, 200)
        self.assertEqual(len(resp1.json()["items"]), 16)

        # Legacy alias cat_training_gear -> resolves to cat_gear (16 items)
        resp2 = self.client.get("/api/shop/products?categoryId=cat_training_gear&pageSize=50")
        self.assertEqual(resp2.status_code, 200)
        self.assertEqual(len(resp2.json()["items"]), 16)

    def test_subcategoryId_filter(self):
        resp = self.client.get("/api/shop/products?categoryId=cat_food_beverage&subcategoryId=B%E1%BB%AFa%20s%C3%A1ng%20ti%E1%BB%87n%20l%E1%BB%A3i")
        self.assertEqual(resp.status_code, 200)
        items = resp.json()["items"]
        self.assertGreaterEqual(len(items), 2)
        for p in items:
            self.assertEqual(p["subcategoryId"], "Bữa sáng tiện lợi")
            self.assertEqual(p["categoryId"], "cat_food_beverage")

    def test_vietnamese_search_diacritic_and_unaccented(self):
        # Search "quần" with diacritics
        resp1 = self.client.get("/api/shop/products?query=quần")
        self.assertEqual(resp1.status_code, 200)
        items1 = resp1.json()["items"]
        self.assertGreaterEqual(len(items1), 4)

        # Search "quan" without diacritics -> exact match
        resp2 = self.client.get("/api/shop/products?query=quan")
        self.assertEqual(resp2.status_code, 200)
        items2 = resp2.json()["items"]
        self.assertEqual({p["id"] for p in items1}, {p["id"] for p in items2})

    def test_vietnamese_search_supplements_and_food(self):
        # Search "creatine"
        resp = self.client.get("/api/shop/products?query=creatine")
        self.assertEqual(resp.status_code, 200)
        items = resp.json()["items"]
        self.assertGreaterEqual(len(items), 2)
        for p in items:
            self.assertEqual(p["categoryId"], "cat_supplements")

    # ──────────────────────────────────────────────────────────────────────────
    # Typed Attributes & Schema Invariant Tests
    # ──────────────────────────────────────────────────────────────────────────

    def test_typed_attributes_equipment(self):
        resp = self.client.get("/api/shop/products/prod_tg_01")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["productType"], "equipment")
        self.assertIsNotNone(data["equipmentAttributes"])
        eq = data["equipmentAttributes"]
        self.assertEqual(eq["primaryMaterial"], "100% Cotton dệt đôi 4mm")
        self.assertAlmostEqual(eq["lengthCm"], 60.0)
        self.assertAlmostEqual(eq["thicknessMm"], 4.0)

    def test_typed_attributes_apparel_swatches_and_sizes(self):
        resp = self.client.get("/api/shop/products/prod_ap_01")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["productType"], "apparel")
        self.assertIsNotNone(data["apparelAttributes"])
        ap = data["apparelAttributes"]
        self.assertIn("M", ap["sizePreviewList"])
        self.assertGreaterEqual(len(ap["colorSwatches"]), 2)
        self.assertTrue(any(c["hexColor"] == "#16171B" for c in ap["colorSwatches"]))

    def test_typed_attributes_food_macros_and_allergens(self):
        resp = self.client.get("/api/shop/products/prod_fb_01")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["productType"], "food")
        self.assertIsNotNone(data["foodAttributes"])
        fd = data["foodAttributes"]
        self.assertEqual(fd["allergenStatus"], "freeOfDeclaredAllergens")
        self.assertIsNotNone(fd["perServingMacros"])
        # Numerical 0 check: sugars must be preserved as 0.0 or int 0, not stripped
        self.assertIsNotNone(fd["perServingMacros"]["proteinGrams"])

    def test_typed_attributes_supplements_substantive_distinction(self):
        # 8 supplements: 4 proteins, 2 creatines (powder vs capsule), 2 electrolytes (sticks vs effervescent)
        resp = self.client.get("/api/shop/products?categoryId=cat_supplements&pageSize=20")
        self.assertEqual(resp.status_code, 200)
        items = resp.json()["items"]
        self.assertEqual(len(items), 8)

        forms = {p["supplementAttributes"]["form"] for p in items}
        self.assertIn("powder", forms)
        self.assertIn("capsule", forms)
        self.assertIn("effervescentTablet", forms)

        # Verify creatine distinction: prod_sp_05 is powder, prod_sp_06 is capsule
        p_c1 = next(p for p in items if p["id"] == "prod_sp_05")
        p_c2 = next(p for p in items if p["id"] == "prod_sp_06")
        self.assertEqual(p_c1["supplementAttributes"]["form"], "powder")
        self.assertEqual(p_c2["supplementAttributes"]["form"], "capsule")

    def test_typed_attributes_lifestyle_recovery(self):
        resp = self.client.get("/api/shop/products/prod_mp_01")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["productType"], "lifestyle_gear")
        self.assertIsNotNone(data["lifestyleAttributes"])
        self.assertEqual(data["lifestyleAttributes"]["capacityMl"], 750)
        self.assertTrue(data["lifestyleAttributes"]["isBpaFree"])

        # Recovery equipment attributes check: prod_rc_04
        resp_rc = self.client.get("/api/shop/products/prod_rc_04")
        self.assertEqual(resp_rc.status_code, 200)
        data_rc = resp_rc.json()
        self.assertEqual(data_rc["productType"], "recovery")
        self.assertIsNotNone(data_rc["equipmentAttributes"])
        self.assertEqual(data_rc["equipmentAttributes"]["primaryMaterial"], "Silicone y tế đúc đặc")

        # Null price test fixture: prod_tg_06 has priceVnd = None
        resp_null_price = self.client.get("/api/shop/products/prod_tg_06")
        self.assertEqual(resp_null_price.status_code, 200)
        self.assertIsNone(resp_null_price.json()["priceVnd"])

    # ──────────────────────────────────────────────────────────────────────────
    # Batch Lookup & Wishlist Invariants (Null for Hidden, Preserving Order)
    # ──────────────────────────────────────────────────────────────────────────

    def test_batch_lookup_preserves_order_and_null_for_hidden(self):
        # Request: active, retired hidden, missing, active with null price
        requested_ids = ["prod_tg_01", "prod_rc_02", "missing_999", "prod_tg_06"]
        resp = self.client.post("/api/shop/products/batch", json={"ids": requested_ids})
        self.assertEqual(resp.status_code, 200)
        items = resp.json()["items"]
        self.assertEqual(len(items), 4)

        # Index 0: prod_tg_01 (active)
        self.assertIsNotNone(items[0])
        self.assertEqual(items[0]["id"], "prod_tg_01")

        # Index 1: prod_rc_02 (retained hidden) -> MUST BE null in public batch lookup
        self.assertIsNone(items[1], "Hidden product must return null slot in batch lookup")

        # Index 2: missing_999 -> MUST BE null
        self.assertIsNone(items[2])

        # Index 3: prod_tg_06 (active with null price) -> returns product, priceVnd is None
        self.assertIsNotNone(items[3])
        self.assertEqual(items[3]["id"], "prod_tg_06")
        self.assertIsNone(items[3]["priceVnd"])

    # ──────────────────────────────────────────────────────────────────────────
    # Taxonomy Migration (Dry-Run & Idempotent Apply)
    # ──────────────────────────────────────────────────────────────────────────

    def test_taxonomy_migration_dry_run_and_idempotency(self):
        # 1. Setup mock legacy DB with pre-CP-02 product
        mock_legacy_db = InMemoryMockDB()
        prod_col = mock_legacy_db[COLL_SHOP_PRODUCTS]
        prod_col.insert_one({
            "id": "prod_tg_01",
            "title": "Lifting Straps Cotton Heavy-Duty",
            "subtitle": "Sub",
            "categoryId": "cat_training_gear",  # Legacy category ID
            "publishState": "published",
            "curatedOrder": 1,
        })
        prod_col.insert_one({
            "id": "prod_rc_02",
            "title": "Con Lăn Massage Cột Sống",
            "subtitle": "Sub",
            "categoryId": "cat_recovery_tools",  # Legacy category ID
            "publishState": "published",        # Needs to be retired hidden
            "curatedOrder": 2,
        })

        # 2. Dry run migration
        dry_report = migrate_catalog_taxonomy(mock_legacy_db, dry_run=True)
        self.assertTrue(dry_report["dryRun"])
        self.assertFalse(dry_report["applied"])
        self.assertEqual(dry_report["productsToUpdateCount"], 2)
        self.assertIn("prod_tg_01", dry_report["productsToUpdateIds"])
        self.assertIn("prod_rc_02", dry_report["productsToUpdateIds"])

        # Confirm documents were NOT modified in dry run
        p1 = prod_col.find_one({"id": "prod_tg_01"})
        self.assertEqual(p1["categoryId"], "cat_training_gear")

        # 3. Apply migration
        real_report = migrate_catalog_taxonomy(mock_legacy_db, dry_run=False)
        self.assertFalse(real_report["dryRun"])
        self.assertTrue(real_report["applied"])
        self.assertEqual(real_report["productsToUpdateCount"], 2)

        # Confirm documents WERE updated
        p1_updated = prod_col.find_one({"id": "prod_tg_01"})
        self.assertEqual(p1_updated["categoryId"], "cat_gear")
        self.assertEqual(p1_updated["productType"], "equipment")

        p2_updated = prod_col.find_one({"id": "prod_rc_02"})
        self.assertEqual(p2_updated["publishState"], "hidden", "Retired legacy product must be hidden")

        # 4. Idempotency: Running migration second time produces 0 updates
        second_report = migrate_catalog_taxonomy(mock_legacy_db, dry_run=False)
        self.assertEqual(second_report["productsToUpdateCount"], 0)

    # ──────────────────────────────────────────────────────────────────────────
    # Admin Seed Idempotency & Modifications Preservation
    # ──────────────────────────────────────────────────────────────────────────

    def test_seed_idempotency_preserves_admin_modifications(self):
        # 1. Update product title via admin service
        self.service.create_or_update_product(
            ShopProductAdminInput(
                id="prod_tg_01",
                title="Lifting Straps Custom Admin Modified",
                subtitle="Dây kéo lưng sửa đổi",
                categoryId="cat_gear",
                description="Mô tả quản trị viên cập nhật",
                editorialNote="Ghi chú mới",
                priceVnd=220000,
                heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
                sourceType=ProductSourceType.internalBrand,
                isDemo=True,
                publishState=PublishState.published,
                contentProvenance=ContentProvenance(
                    sourceName="Admin", rightsBasis="Internal", isMissingProof=True
                ),
            )
        )

        # 2. Run seed without --force
        res = self.service.seed_default_catalog(force_overwrite=False)
        self.assertEqual(res["products"], 0, "No products should be inserted because 84 exist")

        # 3. Assert admin modification was preserved
        p = self.service.get_product_by_id("prod_tg_01")
        self.assertEqual(p.title, "Lifting Straps Custom Admin Modified")
        self.assertEqual(p.priceVnd, 220000)

    # ──────────────────────────────────────────────────────────────────────────
    # Declarative Index Specifications Test
    # ──────────────────────────────────────────────────────────────────────────

    def test_ensure_shop_indexes(self):
        audit = ensure_shop_indexes(self.mock_db, dry_run=False)
        self.assertGreaterEqual(len(audit), 9)
        for item in audit:
            self.assertTrue(item["applied"])


if __name__ == "__main__":
    unittest.main()
