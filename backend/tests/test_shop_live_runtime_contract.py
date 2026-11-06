"""
End-to-End Runtime Contract Verification for Saman Shop (CP-SHOP-07).

Proves:
1. Product starts published -> read API returns it.
2. Admin workflow hides product -> read API immediately excludes it, detail returns 404, batch returns null (preserving Saved bookmark placeholder).
3. Admin workflow adds a new product -> read API immediately serves it.
4. All verified dynamically over HTTP without rebuilding Flutter client or APK.
"""

from datetime import datetime, timezone
import unittest
from fastapi.testclient import TestClient

from backend.app.models.shop import (
    ContentProvenance,
    ProductAvailability,
    ProductSourceType,
    PublishState,
    ShopProductAdminInput,
)
from backend.app.services.shop_service import (
    ShopService,
)
from backend.tests.test_shop_catalog import InMemoryMockDB
from backend.main import app
from backend.routers.shop import get_shop_service


class TestShopLiveRuntimeContract(unittest.TestCase):
    def setUp(self):
        self.mock_db = InMemoryMockDB()
        self.service = ShopService(db_instance=self.mock_db)
        self.service.seed_default_catalog(force_overwrite=True)

        app.dependency_overrides[get_shop_service] = lambda: self.service
        self.client = TestClient(app)

    def tearDown(self):
        app.dependency_overrides.clear()

    def test_catalog_change_reflected_without_rebuild(self):
        # STEP 1: Baseline verification — prod_tg_01 is published and visible
        resp_before = self.client.get("/api/shop/products/prod_tg_01")
        self.assertEqual(resp_before.status_code, 200)
        self.assertEqual(resp_before.json()["id"], "prod_tg_01")
        self.assertEqual(resp_before.json()["title"], "Lifting Straps Cotton Heavy-Duty")

        resp_list_before = self.client.get("/api/shop/products?pageSize=100")
        self.assertEqual(resp_list_before.status_code, 200)
        initial_count = len(resp_list_before.json()["items"])
        self.assertEqual(initial_count, 24)

        # STEP 2: Administrative action — Hide prod_tg_01 via admin workflow
        hide_result = self.service.set_product_publish_state("prod_tg_01", PublishState.hidden)
        self.assertEqual(hide_result["newState"], "hidden")

        # STEP 3: Verification — Read API immediately reflects hidden state WITHOUT REBUILD
        # List excludes prod_tg_01 (count drops to 23)
        resp_list_after_hide = self.client.get("/api/shop/products?pageSize=100")
        self.assertEqual(resp_list_after_hide.status_code, 200)
        items_after_hide = resp_list_after_hide.json()["items"]
        self.assertEqual(len(items_after_hide), 23)
        self.assertNotIn("prod_tg_01", [p["id"] for p in items_after_hide])

        # Detail endpoint returns 404
        resp_detail_after_hide = self.client.get("/api/shop/products/prod_tg_01")
        self.assertEqual(resp_detail_after_hide.status_code, 404)

        # Batch lookup returns null for prod_tg_01, preserving Saved placeholder position
        resp_batch = self.client.post(
            "/api/shop/products/batch",
            json={"ids": ["prod_tg_01", "prod_tg_02"]},
        )
        self.assertEqual(resp_batch.status_code, 200)
        batch_items = resp_batch.json()["items"]
        self.assertIsNone(batch_items[0])
        self.assertIsNotNone(batch_items[1])
        self.assertEqual(batch_items[1]["id"], "prod_tg_02")

        # STEP 4: Administrative action — Add new curated product via admin workflow
        new_product = ShopProductAdminInput(
            id="prod_dyn_99",
            title="Bình Nước Giữ Nhiệt Saman Titanium 1000ml",
            subtitle="Phiên bản giới hạn titan siêu nhẹ",
            categoryId="cat_meal_prep_hydration",
            collectionIds=["col_meal_prep"],
            description="Bình titan nguyên khối siêu bền giữ nhiệt 24 giờ cho gymer chuyên nghiệp.",
            editorialNote="Phiên bản đặc biệt chỉ cung cấp qua Saman Shop.",
            priceVnd=450000,
            priceUpdatedAt=datetime.now(timezone.utc),
            sellerName="Saman Titanium Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=ContentProvenance(
                sourceName="Saman Titanium Lab",
                rightsBasis="Internal Photography / Registered Design",
                evidenceRef="https://assets.saman.app/provenance/titanium-bottle-evidence.pdf",
                isMissingProof=False,
            ),
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/titanium_bottle.jpg",
            curatedOrder=99,
        )
        add_result = self.service.create_or_update_product(new_product)
        self.assertEqual(add_result["action"], "created")

        # STEP 5: Verification — Client reads newly added product immediately WITHOUT REBUILD
        resp_new_detail = self.client.get("/api/shop/products/prod_dyn_99")
        self.assertEqual(resp_new_detail.status_code, 200)
        data_new = resp_new_detail.json()
        self.assertEqual(data_new["id"], "prod_dyn_99")
        self.assertEqual(data_new["title"], "Bình Nước Giữ Nhiệt Saman Titanium 1000ml")
        self.assertEqual(data_new["priceVnd"], 450000)

        # Search without accents immediately finds the newly added product
        resp_search = self.client.get("/api/shop/products?query=titanium")
        self.assertEqual(resp_search.status_code, 200)
        found_items = resp_search.json()["items"]
        self.assertEqual(len(found_items), 1)
        self.assertEqual(found_items[0]["id"], "prod_dyn_99")


if __name__ == "__main__":
    unittest.main()

