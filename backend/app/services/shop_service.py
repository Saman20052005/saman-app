"""
Service and Catalog Engine for Saman Shop.
Subsystem: Saman Shop — Boutique Catalog & Curation (SHOP-EXP-02).

Provides:
- Public catalog query with AND filtering (query, category, subcategory, collection).
- Diacritic-insensitive Vietnamese search matching title, subtitle, and description.
- Stable sort by curatedOrder ascending, tie-breaking by product ID.
- Opaque cursor pagination with filter binding and typed error validation.
- Batch lookup preserving requested order and returning null for missing/hidden items.
- Administrative workflow: add, update, hide, publish, idempotent seeding, and controlled taxonomy migration.
- Compatible with live MongoDB (from backend.app.database) and test in-memory mock collections.
"""

import base64
from copy import deepcopy
from datetime import datetime, timezone
import logging
import re
from typing import Any, Dict, List, Optional, Tuple
import urllib.parse

from backend.app.models.shop import (
    ActiveIngredient,
    ActiveIngredientModel,
    AllergenStatus,
    AllergenStatusEnum,
    ApparelAttributes,
    ApparelAttributesModel,
    ApparelColorSwatch,
    ApparelColorSwatchModel,
    ContentProvenance,
    EquipmentAttributes,
    EquipmentAttributesModel,
    FoodAttributes,
    FoodAttributesModel,
    LifestyleAttributes,
    LifestyleAttributesModel,
    MacroNutrients,
    MacroNutrientsModel,
    ProductAvailability,
    ProductSourceType,
    PublishState,
    ShopCategoryModel,
    ShopCollectionModel,
    ShopProductAdminInput,
    ShopProductPageResponse,
    ShopProductResponse,
    SupplementAttributes,
    SupplementAttributesModel,
    SupplementForm,
    SupplementFormEnum,
)
from backend.app.shop_database import (
    COLL_SHOP_CATEGORIES,
    COLL_SHOP_COLLECTIONS,
    COLL_SHOP_PRODUCTS,
)

logger = logging.getLogger(__name__)


class ShopCatalogException(Exception):
    """Base exception for shop catalog business errors."""
    def __init__(self, message: str, code: str = "SHOP_ERROR"):
        self.message = message
        self.code = code
        super().__init__(message)


class ShopNotFoundException(ShopCatalogException):
    def __init__(self, product_id: str):
        super().__init__(
            f"Sản phẩm '{product_id}' không tồn tại hoặc đã bị ẩn khỏi danh mục",
            code="NOT_FOUND",
        )
        self.product_id = product_id


class ShopInvalidCursorException(ShopCatalogException):
    def __init__(self, cursor: str, reason: str = "Cursor phân trang không hợp lệ hoặc không khớp bộ lọc"):
        super().__init__(reason, code="INVALID_CURSOR")
        self.cursor = cursor


class ShopInvalidQueryException(ShopCatalogException):
    def __init__(self, message: str):
        super().__init__(message, code="INVALID_QUERY")


def normalize_vietnamese(text: str) -> str:
    """
    Normalizes a string for diacritic-insensitive Vietnamese matching.
    Lowercases, trims, replaces 'đ/Đ' -> 'd', and removes Vietnamese tone marks.
    Matches Flutter _normalizeVietnamese 100%.
    """
    if not text:
        return ""
    result = text.lower().strip()
    result = result.replace("đ", "d").replace("Đ", "d")

    with_diacritics = "àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵ"
    without_diacritics = "aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyy"

    trans_table = str.maketrans(with_diacritics, without_diacritics)
    return result.translate(trans_table)


def compute_search_normalized(title: str, subtitle: str, description: str) -> str:
    combined = f"{title} {subtitle} {description}"
    return normalize_vietnamese(combined)


def validate_non_demo_commercial_safety(
    is_demo: bool,
    provenance: Any,
    shopee_url: Optional[str],
) -> None:
    """
    CP-SHOP-08 Commercial Safety & Provenance Gate:
    Enforces that non-demo products MUST have:
    1. Verified copyright provenance (isMissingProof=False and evidenceRef present).
    2. Secure, verified HTTPS URL on exact approved host 'shopee.vn'.
    3. Rejection of placeholder mock URLs (e.g. -p1, -p24).
    """
    if is_demo:
        return

    # 1. Provenance & Evidence Verification
    if hasattr(provenance, "isMissingProof"):
        is_missing = provenance.isMissingProof
        evidence_ref = provenance.evidenceRef
    elif isinstance(provenance, dict):
        is_missing = provenance.get("isMissingProof", False)
        evidence_ref = provenance.get("evidenceRef")
    else:
        is_missing = True
        evidence_ref = None

    if is_missing or not evidence_ref:
        raise ShopCatalogException(
            "Không thể publish sản phẩm non-demo khi thiếu bằng chứng quyền tác giả (isMissingProof=True hoặc thiếu evidenceRef)",
            code="UNVERIFIED_PROVENANCE",
        )

    # 2. Destination URL & Host Allowlist Validation
    if not shopee_url or not shopee_url.lower().startswith("https://"):
        raise ShopCatalogException(
            "Không thể publish sản phẩm non-demo khi chưa có URL mua hàng bảo mật (https://) đã kiểm duyệt",
            code="UNVERIFIED_AFFILIATE_URL",
        )

    parsed = urllib.parse.urlparse(shopee_url)
    host = (parsed.netloc or "").lower()
    if ":" in host:
        host = host.split(":")[0]

    # Exact host match: strictly 'shopee.vn'
    if host != "shopee.vn":
        raise ShopCatalogException(
            f"Tên miền '{host}' không nằm trong danh mục đối tác cho phép (chỉ chấp nhận exact host 'shopee.vn')",
            code="UNAPPROVED_HOST",
        )

    # Reject placeholder test links (e.g., ending in -p1, -p22, etc.)
    if re.search(r"-p\d+$", parsed.path.rstrip("/")):
        raise ShopCatalogException(
            "Không thể publish sản phẩm non-demo với liên kết placeholder thử nghiệm (-pX)",
            code="PLACEHOLDER_URL_DISALLOWED",
        )


class ShopService:
    def __init__(self, db_instance=None):
        self._db = db_instance

    def _get_db(self):
        if self._db is not None:
            return self._db
        import os
        shop_uri = os.getenv("SHOP_DB_URI")
        shop_db_name = os.getenv("SHOP_DB_NAME")
        if shop_uri and shop_db_name:
            import pymongo
            client = pymongo.MongoClient(shop_uri, serverSelectionTimeoutMS=5000)
            self._db = client[shop_db_name]
            return self._db
        try:
            from backend.app.database import db
            return db
        except Exception:
            return None

    def _get_products_col(self):
        db = self._get_db()
        if db is not None:
            return db[COLL_SHOP_PRODUCTS]
        return None

    def _get_categories_col(self):
        db = self._get_db()
        if db is not None:
            return db[COLL_SHOP_CATEGORIES]
        return None

    def _get_collections_col(self):
        db = self._get_db()
        if db is not None:
            return db[COLL_SHOP_COLLECTIONS]
        return None

    # ──────────────────────────────────────────────────────────────────────────
    # Cursor Utilities
    # ──────────────────────────────────────────────────────────────────────────

    @staticmethod
    def compute_query_signature(
        query: Optional[str],
        category_id: Optional[str],
        collection_id: Optional[str],
        subcategory_id: Optional[str] = None,
    ) -> str:
        q_norm = normalize_vietnamese(query.strip()) if query and query.strip() else ""
        cat = category_id.strip() if category_id and category_id.strip() else ""
        col = collection_id.strip() if collection_id and collection_id.strip() else ""
        base = f"{q_norm}|{cat}|{col}"
        if subcategory_id and subcategory_id.strip():
            return f"{base}|{subcategory_id.strip()}"
        return base

    @staticmethod
    def encode_cursor(signature: str, offset: int) -> str:
        raw = f"v1:{signature}:{offset}"
        return base64.urlsafe_b64encode(raw.encode("utf-8")).decode("ascii")

    @staticmethod
    def decode_cursor(cursor: str, expected_signature: str) -> int:
        try:
            decoded = base64.urlsafe_b64decode(cursor.encode("ascii")).decode("utf-8")
            parts = decoded.split(":")
            if len(parts) < 3 or parts[0] != "v1":
                raise ShopInvalidCursorException(cursor, "Cursor không đúng định dạng v1")
            offset_str = parts[-1]
            signature = ":".join(parts[1:-1])
            if signature != expected_signature:
                raise ShopInvalidCursorException(cursor, "Cursor không khớp với bộ lọc hoặc từ khóa tìm kiếm hiện tại")
            offset = int(offset_str)
            if offset < 0:
                raise ShopInvalidCursorException(cursor, "Offset cursor không được âm")
            return offset
        except ShopInvalidCursorException:
            raise
        except Exception as e:
            raise ShopInvalidCursorException(cursor, f"Không thể giải mã cursor: {str(e)}")

    # ──────────────────────────────────────────────────────────────────────────
    # Public Read Catalog
    # ──────────────────────────────────────────────────────────────────────────

    def get_categories(self) -> List[ShopCategoryModel]:
        col = self._get_categories_col()
        if col is None:
            return []
        cursor = col.find({}, {"_id": 0}).sort([("sortOrder", 1), ("id", 1)])
        return [ShopCategoryModel(**doc) for doc in cursor]

    def get_collections(self) -> List[ShopCollectionModel]:
        col = self._get_collections_col()
        if col is None:
            return []
        cursor = col.find({}, {"_id": 0}).sort([("sortOrder", 1), ("id", 1)])
        return [ShopCollectionModel(**doc) for doc in cursor]

    def get_products(
        self,
        query: Optional[str] = None,
        category_id: Optional[str] = None,
        collection_id: Optional[str] = None,
        subcategory_id: Optional[str] = None,
        page_size: int = 20,
        cursor: Optional[str] = None,
    ) -> ShopProductPageResponse:
        if page_size <= 0:
            raise ShopInvalidQueryException("pageSize phải là số nguyên dương lớn hơn 0")
        if page_size > 100:
            page_size = 100

        col = self._get_products_col()
        if col is None:
            return ShopProductPageResponse(items=[], nextCursor=None, hasMore=False)

        # Build MongoDB query: strictly published items only
        mongo_filter: Dict[str, Any] = {"publishState": PublishState.published.value}

        # Resolve legacy category aliases
        canonical_category = {
            "cat_training_gear": "cat_gear",
            "cat_recovery_tools": "cat_recovery_lifestyle",
            "cat_meal_prep_hydration": "cat_food_beverage",
        }.get(category_id.strip(), category_id.strip()) if category_id and category_id.strip() else None

        if canonical_category:
            mongo_filter["categoryId"] = canonical_category

        if collection_id and collection_id.strip():
            # Support legacy collection alias col_recovery -> col_gym_bag or direct match
            resolved_col = collection_id.strip()
            if resolved_col == "col_recovery":
                mongo_filter["collectionIds"] = "col_gym_bag"
            else:
                mongo_filter["collectionIds"] = resolved_col

        if subcategory_id and subcategory_id.strip():
            mongo_filter["subcategoryId"] = subcategory_id.strip()

        # Fetch candidate products matching category/collection
        docs = list(col.find(mongo_filter, {"_id": 0}))

        # In-memory subcategory check (for mock collections that may not filter subcategoryId)
        if subcategory_id and subcategory_id.strip():
            target_sub = subcategory_id.strip()
            docs = [d for d in docs if d.get("subcategoryId") == target_sub]

        # Text search matching in Python memory with normalized Vietnamese support
        if query and query.strip():
            norm_q = normalize_vietnamese(query.strip())
            docs = [
                d for d in docs
                if norm_q in d.get("searchNormalized", compute_search_normalized(d.get("title", ""), d.get("subtitle", ""), d.get("description", "")))
            ]

        # Stable sort: curatedOrder ascending, tie-break by ID ascending
        docs.sort(key=lambda d: (d.get("curatedOrder", 0), d.get("id", "")))

        # Cursor validation & pagination
        expected_sig = self.compute_query_signature(query, category_id, collection_id, subcategory_id)
        start_index = 0
        if cursor and cursor.strip():
            start_index = self.decode_cursor(cursor.strip(), expected_sig)
            if start_index > len(docs):
                raise ShopInvalidCursorException(cursor, "Offset cursor vượt quá tổng số sản phẩm tìm thấy")

        end_index = min(start_index + page_size, len(docs))
        page_docs = docs[start_index:end_index]

        next_cursor = None
        has_more = False
        if end_index < len(docs):
            next_cursor = self.encode_cursor(expected_sig, end_index)
            has_more = True

        items = [ShopProductResponse(**d) for d in page_docs]
        return ShopProductPageResponse(
            items=items,
            nextCursor=next_cursor,
            hasMore=has_more,
        )

    def get_product_by_id(self, product_id: str) -> ShopProductResponse:
        col = self._get_products_col()
        if col is None:
            raise ShopNotFoundException(product_id)

        doc = col.find_one({"id": product_id}, {"_id": 0})
        if not doc or doc.get("publishState") != PublishState.published.value:
            raise ShopNotFoundException(product_id)

        return ShopProductResponse(**doc)

    def get_products_by_ids(self, ids: List[str]) -> List[Optional[ShopProductResponse]]:
        """
        Batch lookup preserving the requested ID order.
        If an ID is missing, unpublished, or hidden, returns None at that position.
        """
        if not ids:
            return []

        col = self._get_products_col()
        if col is None:
            return [None for _ in ids]

        cursor = col.find(
            {
                "id": {"$in": ids},
                "publishState": PublishState.published.value,
            },
            {"_id": 0},
        )
        product_map = {doc["id"]: ShopProductResponse(**doc) for doc in cursor}
        return [product_map.get(pid) for pid in ids]

    # ──────────────────────────────────────────────────────────────────────────
    # Administrative Catalog Operations (Local / Controlled CLI)
    # ──────────────────────────────────────────────────────────────────────────

    def create_or_update_product(self, product_input: ShopProductAdminInput) -> Dict[str, Any]:
        """
        Creates or updates a product with validation.
        Computes searchNormalized and preserves audit timestamps.
        """
        col = self._get_products_col()
        if col is None:
            raise ShopCatalogException("Không thể kết nối đến collection shop_products")

        # Provenance & Commercial Safety Gate (CP-SHOP-08)
        if product_input.publishState == PublishState.published:
            validate_non_demo_commercial_safety(
                product_input.isDemo,
                product_input.contentProvenance,
                product_input.shopeeUrl,
            )

        now = datetime.now(timezone.utc)
        doc = product_input.model_dump()
        doc["searchNormalized"] = compute_search_normalized(
            product_input.title, product_input.subtitle, product_input.description
        )
        doc["updatedAt"] = now

        existing = col.find_one({"id": product_input.id})
        if existing:
            doc["createdAt"] = existing.get("createdAt", now)
            col.update_one({"id": product_input.id}, {"$set": doc})
            action = "updated"
        else:
            doc["createdAt"] = now
            col.insert_one(doc)
            action = "created"

        logger.info("[Shop Admin] Product '%s' %s successfully.", product_input.id, action)
        return {"id": product_input.id, "action": action, "publishState": product_input.publishState.value}

    def set_product_publish_state(self, product_id: str, new_state: PublishState) -> Dict[str, Any]:
        """
        Hides or publishes a product.
        SAFETY: Never removes product ID or touches wishlist storage.
        """
        col = self._get_products_col()
        if col is None:
            raise ShopCatalogException("Không thể kết nối đến collection shop_products")

        existing = col.find_one({"id": product_id})
        if not existing:
            raise ShopNotFoundException(product_id)

        # Safety Gate on Re-publishing non-demo products (CP-SHOP-08)
        if new_state == PublishState.published:
            is_demo = existing.get("isDemo", True)
            prov = existing.get("contentProvenance", {})
            url = existing.get("shopeeUrl")
            validate_non_demo_commercial_safety(is_demo, prov, url)

        now = datetime.now(timezone.utc)
        col.update_one(
            {"id": product_id},
            {"$set": {"publishState": new_state.value, "updatedAt": now}},
        )
        logger.info("[Shop Admin] Set product '%s' publishState -> %s", product_id, new_state.value)
        return {"id": product_id, "previousState": existing.get("publishState"), "newState": new_state.value}

    def list_admin_products(self, include_hidden: bool = True) -> List[Dict[str, Any]]:
        col = self._get_products_col()
        if col is None:
            return []

        mongo_filter = {} if include_hidden else {"publishState": PublishState.published.value}
        cursor = col.find(mongo_filter, {"_id": 0}).sort([("curatedOrder", 1), ("id", 1)])
        return list(cursor)

    def seed_default_catalog(self, force_overwrite: bool = False) -> Dict[str, int]:
        """
        Idempotently seeds 5 canonical categories, 6 curated collections, and 84 catalog products
        (80 active + 4 retained hidden).
        If items already exist and force_overwrite is False, preserves existing modified data.
        """
        db = self._get_db()
        if db is None:
            logger.warning("[Shop Seed] No DB connection available.")
            return {"categories": 0, "collections": 0, "products": 0}

        cat_col = db[COLL_SHOP_CATEGORIES]
        col_col = db[COLL_SHOP_COLLECTIONS]
        prod_col = db[COLL_SHOP_PRODUCTS]

        # 1. Seed 5 Canonical Categories
        categories_seed = [
            {"id": "cat_gear", "name": "Dụng cụ tập", "slug": "dung-cu-tap", "iconAsset": "assets/icons/dumbbell.svg", "sortOrder": 1},
            {"id": "cat_apparel", "name": "Thời trang thể thao", "slug": "thoi-trang-the-thao", "iconAsset": "assets/icons/apparel.svg", "sortOrder": 2},
            {"id": "cat_food_beverage", "name": "Thực phẩm & đồ uống", "slug": "thuc-pham-do-uong", "iconAsset": "assets/icons/food.svg", "sortOrder": 3},
            {"id": "cat_supplements", "name": "Thực phẩm bổ sung", "slug": "thuc-pham-bo-sung", "iconAsset": "assets/icons/supplement.svg", "sortOrder": 4},
            {"id": "cat_recovery_lifestyle", "name": "Phục hồi", "slug": "phuc-hoi-sinh-hoat", "iconAsset": "assets/icons/recovery.svg", "sortOrder": 5},
        ]
        cats_added = 0
        for cat in categories_seed:
            res = cat_col.update_one({"id": cat["id"]}, {"$setOnInsert": cat}, upsert=True)
            if res.upserted_id:
                cats_added += 1

        # 2. Seed 6 Curated Collections
        collections_seed = [
            {"id": "col_home_starter", "title": "Bắt đầu tập tại nhà", "subtitle": "Tối ưu không gian nhỏ", "description": "Trang bị tối thiểu nhưng hiệu quả tối đa cho buổi tập thể lực tại nhà.", "bannerImageUrl": "assets/images/workout.jpg", "isFeatured": True, "sortOrder": 1},
            {"id": "col_gym_bag", "title": "Chuẩn bị túi đi tập", "subtitle": "Sẵn sàng cho mọi buổi tập", "description": "Phụ kiện nâng cao hiệu suất và bảo vệ cơ thể sẵn sàng trong túi tập.", "bannerImageUrl": "assets/images/workout.jpg", "isFeatured": True, "sortOrder": 2},
            {"id": "col_quick_breakfast", "title": "Bữa sáng tiện lợi", "subtitle": "Năng lượng sạch khởi đầu ngày", "description": "Bữa sáng cân bằng dinh dưỡng chuẩn bị dưới 5 phút cho người bận rộn.", "bannerImageUrl": "assets/images/nutrition/breakfast_banner.jpg", "isFeatured": True, "sortOrder": 3},
            {"id": "col_portable_snacks", "title": "Đồ ăn nhẹ mang theo", "subtitle": "Cắt cơn đói trước và sau tập", "description": "Đồ ăn nhẹ giàu đạm và chất béo tốt dễ dàng mang theo mọi nơi.", "bannerImageUrl": "assets/images/nutrition/snacks_banner.jpg", "isFeatured": True, "sortOrder": 4},
            {"id": "col_meal_prep", "title": "Chuẩn bị bữa ăn trong tuần", "subtitle": "Kiểm soát Macro chuẩn xác", "description": "Hộp bảo quản, cân tiểu ly và túi giữ nhiệt giúp chuẩn bị thức ăn cả tuần ngăn nắp.", "bannerImageUrl": "assets/images/nutrition/meal_prep_banner.jpg", "isFeatured": True, "sortOrder": 5},
            {"id": "col_active_wear", "title": "Trang phục cho ngày vận động", "subtitle": "Thoải mái và tôn phom dáng", "description": "Chất liệu co giãn 4 chiều và thoáng khí nâng tầm trải nghiệm vận động.", "bannerImageUrl": "assets/images/shop/active_wear_banner.jpg", "isFeatured": True, "sortOrder": 6},
        ]
        cols_added = 0
        for col_data in collections_seed:
            res = col_col.update_one({"id": col_data["id"]}, {"$setOnInsert": col_data}, upsert=True)
            if res.upserted_id:
                cols_added += 1

        # 3. Seed 84 Curated Products (80 active + 4 retained hidden)
        products_seed = _build_default_curated_products()
        now = datetime.now(timezone.utc)
        prods_added = 0
        for p in products_seed:
            p_doc = p.model_dump()
            p_doc["searchNormalized"] = compute_search_normalized(p.title, p.subtitle, p.description)
            p_doc["createdAt"] = now
            p_doc["updatedAt"] = now

            if force_overwrite:
                prod_col.replace_one({"id": p.id}, p_doc, upsert=True)
                prods_added += 1
            else:
                res = prod_col.update_one({"id": p.id}, {"$setOnInsert": p_doc}, upsert=True)
                if res.upserted_id:
                    prods_added += 1

        logger.info(
            "[Shop Seed] Complete: +%d categories, +%d collections, +%d products.",
            cats_added, cols_added, prods_added
        )
        return {"categories": cats_added, "collections": cols_added, "products": prods_added}


def migrate_catalog_taxonomy(db_instance, dry_run: bool = True) -> Dict[str, Any]:
    """
    Controlled schema and taxonomy migration for Saman Shop (SHOP-EXP-02).
    Upgrades legacy pre-CP-02 documents to modern 5-category taxonomy and typed schema:
    1. Upgrades legacy category IDs:
       - cat_training_gear -> cat_gear
       - cat_recovery_tools -> cat_recovery_lifestyle
       - cat_meal_prep_hydration -> cat_recovery_lifestyle (for hydration/boxes) or cat_food_beverage
    2. Retires secondary legacy products to publishState=hidden (prod_rc_02, prod_mp_02, prod_mp_04, prod_mp_08).
       Preserves the document and IDs completely so existing wishlist entries do not break.
    3. Enriches products with productType and subcategoryId.
    
    SAFETY INVARIANTS:
    - dry_run=True computes the exact delta and affected IDs without modifying database documents.
    - Idempotent: Executing multiple times produces identical clean state.
    - Audited: Returns detailed report of modified, retired, and untouched records.
    """
    if db_instance is None:
        raise ShopCatalogException("Không thể thực hiện migration: db_instance là None")

    prod_col = db_instance[COLL_SHOP_PRODUCTS]
    cat_col = db_instance[COLL_SHOP_CATEGORIES]
    col_col = db_instance[COLL_SHOP_COLLECTIONS]

    # Pre-condition check: inspect existing products
    existing_docs = list(prod_col.find({}, {"_id": 0}))
    
    # Target canonical reference map from current curated catalog
    canonical_products = {p.id: p for p in _build_default_curated_products()}
    
    retired_hidden_ids = {"prod_rc_02", "prod_mp_02", "prod_mp_04", "prod_mp_08"}
    
    planned_updates = []
    untouched_ids = []
    
    now = datetime.now(timezone.utc)
    
    for doc in existing_docs:
        pid = doc.get("id")
        if not pid or pid not in canonical_products:
            untouched_ids.append(pid)
            continue
            
        canonical = canonical_products[pid]
        updates: Dict[str, Any] = {}
        
        # Check categoryId upgrade
        if doc.get("categoryId") != canonical.categoryId:
            updates["categoryId"] = canonical.categoryId
            
        # Check productType
        if doc.get("productType") != canonical.productType:
            updates["productType"] = canonical.productType
            
        # Check subcategoryId
        if doc.get("subcategoryId") != canonical.subcategoryId:
            updates["subcategoryId"] = canonical.subcategoryId
            
        # Check publishState for retired products
        if pid in retired_hidden_ids and doc.get("publishState") != PublishState.hidden.value:
            updates["publishState"] = PublishState.hidden.value
            
        # Check typed attributes if missing
        for attr_key in [
            "equipmentAttributes", "apparelAttributes", "foodAttributes",
            "supplementAttributes", "lifestyleAttributes"
        ]:
            canonical_val = getattr(canonical, attr_key)
            if canonical_val is not None and doc.get(attr_key) is None:
                updates[attr_key] = canonical_val.model_dump()
                
        if updates:
            updates["migrationVersion"] = "SHOP-EXP-02"
            updates["updatedAt"] = now
            planned_updates.append({"id": pid, "changes": updates})
        else:
            untouched_ids.append(pid)
            
    # Category collection migration
    categories_seed = [
        {"id": "cat_gear", "name": "Dụng cụ tập", "slug": "dung-cu-tap", "iconAsset": "assets/icons/dumbbell.svg", "sortOrder": 1},
        {"id": "cat_apparel", "name": "Thời trang thể thao", "slug": "thoi-trang-the-thao", "iconAsset": "assets/icons/apparel.svg", "sortOrder": 2},
        {"id": "cat_food_beverage", "name": "Thực phẩm & đồ uống", "slug": "thuc-pham-do-uong", "iconAsset": "assets/icons/food.svg", "sortOrder": 3},
        {"id": "cat_supplements", "name": "Thực phẩm bổ sung", "slug": "thuc-pham-bo-sung", "iconAsset": "assets/icons/supplement.svg", "sortOrder": 4},
        {"id": "cat_recovery_lifestyle", "name": "Phục hồi", "slug": "phuc-hoi-sinh-hoat", "iconAsset": "assets/icons/recovery.svg", "sortOrder": 5},
    ]

    report = {
        "dryRun": dry_run,
        "totalEvaluated": len(existing_docs),
        "productsToUpdateCount": len(planned_updates),
        "productsToUpdateIds": [item["id"] for item in planned_updates],
        "productsUntouchedCount": len(untouched_ids),
        "retiredHiddenIds": list(retired_hidden_ids),
        "applied": False,
    }

    if not dry_run and planned_updates:
        for item in planned_updates:
            prod_col.update_one({"id": item["id"]}, {"$set": item["changes"]})
            
        # Ensure canonical categories exist
        for cat in categories_seed:
            cat_col.update_one({"id": cat["id"]}, {"$set": cat}, upsert=True)
            
        report["applied"] = True
        logger.info("[Shop Migration] Applied taxonomy updates to %d products.", len(planned_updates))
    else:
        logger.info("[Shop Migration Dry-Run] Evaluated %d products, %d require updates.", len(existing_docs), len(planned_updates))

    return report


def _build_default_curated_products() -> List[ShopProductAdminInput]:
    # Provenances
    shaker_prov = ContentProvenance(
        sourceName="Alexander Redl (Unsplash: @alexanderredl)",
        rightsBasis="Unsplash License",
        evidenceRef="https://unsplash.com/photos/black-water-bottle-on-gray-surface-q630so5psh4",
        isMissingProof=False,
    )
    roller_prov = ContentProvenance(
        sourceName="Karsten Winegeart (Unsplash: @karsten116)",
        rightsBasis="Unsplash License",
        evidenceRef="https://unsplash.com/photos/black-foam-roller-on-dark-floor-d3P_xN_048o",
        isMissingProof=False,
    )
    bands_prov = ContentProvenance(
        sourceName="Kelly Sikkema (Unsplash: @kellysikkema)",
        rightsBasis="Unsplash License",
        evidenceRef="https://unsplash.com/photos/resistance-bands-exercise-equipment-4qSb_Fstkio",
        isMissingProof=False,
    )
    glass_prov = ContentProvenance(
        sourceName="Ella Olsson (Unsplash: @ellaolsson)",
        rightsBasis="Unsplash License",
        evidenceRef="https://unsplash.com/photos/glass-food-storage-containers-K4mSJ7kc0As",
        isMissingProof=False,
    )
    generic_prov = ContentProvenance(
        sourceName="Unsplash Contributor (Generic Placeholder Asset)",
        rightsBasis="Unsplash License (Generic Category Placeholder)",
        evidenceRef=None,
        isMissingProof=True,
    )

    products = []
    products.append(
        ShopProductAdminInput(
            id="prod_tg_01",
            title="Lifting Straps Cotton Heavy-Duty",
            subtitle="Dây kéo lưng nâng tạ sợi cotton đệm lót cổ tay",
            categoryId="cat_gear",
            collectionIds=["col_home_starter", "col_gym_bag"],
            productType="equipment",
            subcategoryId="Phụ kiện kéo lưng",
            badge="Curated",
            description="Dây kéo lưng trợ lực cổ tay sợi cotton dệt đôi dày 4mm chịu lực trên 300kg. Đệm mút neoprene êm ái bảo vệ cổ tay khi tập Deadlift và Barbell Rows.",
            editorialNote="Khuyên dùng trong các hiệp tập nặng khi lực nắm cẳng tay bị đuối trước khi nhóm cơ lưng kiệt sức.",
            priceVnd=185000,
            priceUpdatedAt=datetime(2026, 10, 20, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Cotton dệt dày", "Đệm lót": "Neoprene 5mm", "Chiều dài": "60 cm", "Tải trọng thử nghiệm": "350 kg"},
            shopeeUrl="https://shopee.vn/product/saman-lifting-straps-01",
            curatedOrder=1,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="100% Cotton dệt đôi 4mm", gripType="Đệm mút Neoprene 5mm", lengthCm=60.0, widthCm=3.8, thicknessMm=4.0, maxLoadCapacityKg=350.0, usageEnvironment="Tập kéo xà, Deadlift, Barbell Rows"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_02",
            title="Figure 8 Lifting Straps Chuyên Deadlift",
            subtitle="Dây kéo lưng số 8 khóa chặt đòn tạ",
            categoryId="cat_gear",
            collectionIds=["col_gym_bag"],
            productType="equipment",
            subcategoryId="Phụ kiện kéo lưng",
            badge=None,
            description="Thiết kế số 8 kép lồng tay nhanh chóng, phân bổ lực đều khắp cổ tay và thanh đòn. Đường may gia cố chỉ nylon siêu bền chuyên trị các mức tạ kỷ lục.",
            editorialNote="Lựa chọn số 1 cho các vận động viên Powerlifting tập trung hoàn toàn vào lực kéo mà không lo tuột tạ.",
            priceVnd=220000,
            priceUpdatedAt=datetime(2026, 10, 20, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Sợi cotton dệt chéo", "Kiểu dáng": "Số 8 kép", "Kích cỡ": "Tiêu chuẩn cổ tay 16-20cm"},
            shopeeUrl="https://shopee.vn/product/saman-figure8-straps-02",
            curatedOrder=2,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Sợi cotton dệt chéo", gripType="Khóa số 8 tự siết", maxLoadCapacityKg=400.0, usageEnvironment="Deadlift nặng, Shrugs"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_03",
            title="Fabric Resistance Bands Set (3 Kháng Lực)",
            subtitle="Bộ 3 dây kháng lực dệt vải không cuộn mép",
            categoryId="cat_gear",
            collectionIds=["col_home_starter"],
            productType="equipment",
            subcategoryId="Dây kháng lực dệt vải",
            badge="Popular",
            description="Bộ 3 dây kháng lực cotton dệt sợi cao su tự nhiên với 3 mức kháng lực Light, Medium, Heavy. Bề mặt vải mềm mại chống trượt và không bao giờ bị cuộn quăn khi tập mông đùi.",
            editorialNote="Khắc phục triệt để nhược điểm bám dính rít lông chân hoặc bứt đứt đột ngột của dây cao su mỏng truyền thống.",
            priceVnd=245000,
            priceUpdatedAt=datetime(2026, 10, 20, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=bands_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Cotton dệt cao su tự nhiên", "Số lượng": "3 dây / bộ", "Mức kháng": "15-25 lbs, 25-35 lbs, 40-50 lbs"},
            shopeeUrl="https://shopee.vn/product/saman-fabric-bands-03",
            curatedOrder=3,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Cotton pha sợi cao su tự nhiên", resistanceRange="15 - 50 lbs (3 cấp độ)", usageEnvironment="Khởi động mông đùi, Glute Bridge, Squat tại nhà"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_04",
            title="Latex Pull-Up Assist Band (Dây Đỏ 15-35 lbs)",
            subtitle="Dây cao su tự nhiên hỗ trợ hít xà và giãn cơ",
            categoryId="cat_gear",
            collectionIds=["col_home_starter"],
            productType="equipment",
            subcategoryId="Dây kháng lực cao su tự nhiên",
            badge=None,
            description="Dây cao su đúc nguyên khối dài 208cm độ bền kéo giãn 300%. Hỗ trợ đắc lực bài tập hít xà đơn, chống đẩy tạ hoặc giãn cơ toàn thân linh hoạt.",
            editorialNote="Mức kháng lực đỏ 15-35 lbs là mức đa năng nhất, vừa đủ trợ lực hít xà vừa thích hợp khởi động khớp vai.",
            priceVnd=165000,
            priceUpdatedAt=datetime(2026, 10, 20, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=bands_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Cao su Latex tự nhiên", "Chu vi": "208 cm", "Độ rộng": "1.3 cm", "Lực kéo": "15 - 35 lbs"},
            shopeeUrl="https://shopee.vn/product/saman-pullup-band-04",
            curatedOrder=4,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="100% Cao su Latex tự nhiên", lengthCm=208.0, widthCm=1.3, thicknessMm=4.5, resistanceRange="15 - 35 lbs (7 - 16 kg)", usageEnvironment="Trợ lực hít xà, kéo giãn khớp vai"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_05",
            title="Speed Jump Rope Vòng Bi Thép Tốc Độ Cao",
            subtitle="Dây nhảy cáp thép bọc PU tay cầm hợp kim nhôm",
            categoryId="cat_gear",
            collectionIds=["col_home_starter", "col_gym_bag"],
            productType="equipment",
            subcategoryId="Dụng cụ Cardio & Bền bỉ",
            badge=None,
            description="Dây nhảy tốc độ trục xoay vòng bi kép 360 độ quay mượt mà không rối dây. Cáp thép bọc polymer chịu mài mòn cao, tay cầm nhôm phay rãnh kim cương bám tay.",
            editorialNote="Thiết kế tối ưu cho kỹ thuật nhảy Double Unders và bài tập cardio đốt calo cường độ cao HIIT.",
            priceVnd=195000,
            priceUpdatedAt=datetime(2026, 10, 20, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Lõi cáp": "Thép bọc PU 2.5mm", "Chiều dài": "3 mét điều chỉnh được", "Vòng bi": "Bi cầu thép xoay 360 độ"},
            shopeeUrl="https://shopee.vn/product/saman-speed-rope-05",
            curatedOrder=5,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Cáp thép bọc PU, tay cầm hợp kim nhôm", lengthCm=300.0, gripType="Nhôm khía rãnh kim cương chống trượt", usageEnvironment="Cardio tại nhà, phòng gym, sân tập ngoài trời"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_06",
            title="Wrist Wraps Đôi Băng Quấn Cổ Tay Nén Khớp 18\"",
            subtitle="Băng quấn trợ lực cố định khớp cổ tay bản rộng",
            categoryId="cat_gear",
            collectionIds=["col_gym_bag"],
            productType="equipment",
            subcategoryId="Bảo vệ khớp & Cố định",
            badge=None,
            description="Băng quấn sợi co giãn đàn hồi cao bản rộng 7.5cm cố định vững chắc cổ tay trong các bài đẩy ngực Bench Press, đẩy vai Overhead Press.",
            editorialNote="Vòng xỏ ngón cái tiện lợi giúp quấn chặt dễ dàng bằng một tay mà không bị xô lệch vị trí nẹp.",
            priceVnd=None,
            priceUpdatedAt=None,
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chiều dài": "45 cm (18 inch)", "Chiều rộng": "7.5 cm", "Khóa dán": "Velcro bản lớn 10cm"},
            shopeeUrl="https://shopee.vn/product/saman-wrist-wraps-06",
            curatedOrder=6,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Polyester đàn hồi pha sợi cao su", lengthCm=45.0, widthCm=7.5, usageEnvironment="Bench Press, Overhead Press nặng"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_07",
            title="Barbell Collar Clips Khóa Tạ Đòn Chắc Chắn",
            subtitle="Cặp khóa kẹp giữ bánh tạ phi 50mm tháo lắp nhanh",
            categoryId="cat_gear",
            collectionIds=["col_home_starter"],
            productType="equipment",
            subcategoryId="Phụ kiện tạ đòn",
            badge=None,
            description="Khóa kẹp ngàm đôi nhựa ABS chịu lực kết hợp đệm cao su mặt trong kẹp chặt đòn tạ Olympic phi 50mm, chống trượt bánh tạ khi nâng hạ mạnh.",
            editorialNote="Cơ chế khóa bấm một chạm gạt mở nhanh giúp thay đổi mức tạ chỉ trong vài giây giữa các hiệp nghỉ.",
            priceVnd=135000,
            priceUpdatedAt=datetime(2026, 10, 20, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Nhựa kỹ thuật ABS & Cao su", "Đường kính lòng": "50 mm", "Quy cách": "Cặp 2 chiếc"},
            shopeeUrl="https://shopee.vn/product/saman-barbell-collars-07",
            curatedOrder=7,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Nhựa kỹ thuật ABS đệm lót cao su", maxLoadCapacityKg=300.0, usageEnvironment="Thanh đòn Olympic tiêu chuẩn 50mm"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_08",
            title="Liquid Grip Chalk Phấn Lỏng Tập Gym 250ml",
            subtitle="Phấn magie lỏng tăng độ bám tay chống trơn trượt",
            categoryId="cat_gear",
            collectionIds=["col_gym_bag"],
            productType="equipment",
            subcategoryId="Tăng ma sát bám dính",
            badge=None,
            description="Công thức magie carbonat dạng lỏng khô sau 10 giây thoa tay tạo lớp phủ bám dính mỏng nhẹ, không tạo bụi phấn bay lơ lửng trong không khí.",
            editorialNote="Thân thiện với các phòng gym thương mại có quy định nghiêm ngặt cấm sử dụng phấn cục bột truyền thống.",
            priceVnd=175000,
            priceUpdatedAt=datetime(2026, 10, 20, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.unavailable,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "250 ml", "Thành phần": "Magnesium Carbonate, Ethanol tự bay hơi", "Thời gian khô": "10 - 15 giây"},
            shopeeUrl="https://shopee.vn/product/saman-liquid-chalk-08",
            curatedOrder=8,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Magnesium Carbonate & cồn bay hơi nhanh", usageEnvironment="Deadlift, Kéo xà đơn, Leo núi trong nhà"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_09",
            title="Ab Wheel Roller Kèm Thảm Lót Gối",
            subtitle="Con lăn tập cơ bụng bánh xe kép chịu tải 150kg",
            categoryId="cat_gear",
            collectionIds=["col_home_starter"],
            productType="equipment",
            subcategoryId="Dụng cụ tập Core bụng",
            badge=None,
            description="Bánh xe kép bọc cao su chống trượt tạo độ thăng bằng ổn định, trục thép carbon đặc chịu tải 150kg kèm miếng đệm mút lót đầu gối êm ái.",
            editorialNote="Bài tập lăn bụng kích hoạt đồng thời toàn bộ dải cơ thẳng bụng, cơ liên sườn và cơ lưng dưới hiệu quả vượt trội so với gập bụng sàn thông thường.",
            priceVnd=160000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Trục thép mạ kẽm, bánh xe cao su PU", "Tải trọng": "150 kg", "Phụ kiện kèm theo": "Thảm lót gối xốp EVA 34x17cm"},
            shopeeUrl="https://shopee.vn/product/saman-ab-roller-09",
            curatedOrder=9,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Trục thép chịu lực, bánh xe bọc cao su PU", gripType="Tay cầm mút xốp EVA chống chai tay", maxLoadCapacityKg=150.0, usageEnvironment="Tập cơ bụng tại nhà và văn phòng"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_10",
            title="Xà Đơn Gắn Cửa Đa Năng Không Khoan Đục",
            subtitle="Đòn bẩy tự hãm khung cửa chịu lực 130kg",
            categoryId="cat_gear",
            collectionIds=["col_home_starter"],
            productType="equipment",
            subcategoryId="Xà tập thân trên",
            badge=None,
            description="Cơ chế đòn bẩy tự hãm móc trên gờ khung cửa rộng từ 60-90cm không cần khoan đục hay bắt vít. Đệm cao su bảo vệ tường chống trầy xước nước sơn.",
            editorialNote="Hỗ trợ 3 vị trí tay cầm: hẹp tay, rộng tay và trung tính giúp cô lập từng vùng cơ lưng xô và tay trước.",
            priceVnd=350000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Ống thép carbon dày 1.5mm sơn tĩnh điện", "Độ rộng cửa phù hợp": "60 - 90 cm", "Tải trọng tối đa": "130 kg"},
            shopeeUrl="https://shopee.vn/product/saman-pullup-bar-10",
            curatedOrder=10,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Thép carbon sơn tĩnh điện đen mờ", gripType="Mút đệm xốp cao mật độ", maxLoadCapacityKg=130.0, usageEnvironment="Khung cửa gia đình rộng 60-90cm"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_11",
            title="Tạ Ấm Gang Đúc Nguyên Khối 12kg",
            subtitle="Kettlebell gang đúc phủ sơn tĩnh điện tay cầm phẳng",
            categoryId="cat_gear",
            collectionIds=["col_home_starter"],
            productType="equipment",
            subcategoryId="Tạ tự do chức năng",
            badge="Curated",
            description="Gang đúc nguyên khối một mảnh không hàn nối, đáy phẳng chống rung lắc khi đặt sàn. Tay cầm đường kính 33mm mài nhẵn phẳng cho chuyển động Swing mượt mà.",
            editorialNote="Vua của các bài tập rèn luyện sức mạnh bùng nổ chuỗi cơ sau Posterior Chain (mông, đùi sau, lưng dưới).",
            priceVnd=480000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Gang xám đúc nguyên khối", "Trọng lượng": "12 kg (±1%)", "Đường kính tay nắm": "33 mm"},
            shopeeUrl="https://shopee.vn/product/saman-kettlebell-11",
            curatedOrder=11,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="100% Gang đúc nguyên khối sơn tĩnh điện", weightKg=12.0, gripType="Tay cầm gang mài phẳng đường kính 33mm", usageEnvironment="Kettlebell Swing, Goblet Squat, Turkish Get-up"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_12",
            title="Quả Tạ Tay Điều Chỉnh Thông Minh 20kg",
            subtitle="Tạ tay thay đổi 5 mức trọng lượng xoay tay cầm",
            categoryId="cat_gear",
            collectionIds=["col_home_starter"],
            productType="equipment",
            subcategoryId="Tạ tự do đa mức",
            badge=None,
            description="Cơ chế xoay tay cầm chuyển đổi nhanh 5 mức tạ (4kg, 8kg, 12kg, 16kg, 20kg) chỉ trong 1 giây. Khay đựng đế nhựa cố định các bánh tạ không dùng ngăn nắp.",
            editorialNote="Thay thế hoàn toàn cả một giá tạ tay cồng kềnh, giải pháp hoàn hảo cho góc tập luyện căn hộ chung cư.",
            priceVnd=1250000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Mức tạ điều chỉnh": "4kg - 8kg - 12kg - 16kg - 20kg", "Cơ chế khóa": "Bánh răng ngàm khóa an toàn 10 điểm", "Kèm theo": "Khay đế tạ ABS"},
            shopeeUrl="https://shopee.vn/product/saman-adjustable-dumbbell-12",
            curatedOrder=12,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Lõi thép bọc polymer cao cấp", weightKg=20.0, gripType="Cán khía kim loại chống trơn", usageEnvironment="Tập tạ đa nhóm cơ tại nhà"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_13",
            title="Vòng Treo Xà Gỗ Bạch Dương Kèm Dây Số",
            subtitle="Gymnastic rings gỗ tự nhiên 28mm dây đai nylon đánh số",
            categoryId="cat_gear",
            collectionIds=["col_home_starter", "col_gym_bag"],
            productType="equipment",
            subcategoryId="Dụng cụ Calisthenics",
            badge=None,
            description="Vòng gỗ bạch dương tự nhiên đường kính 28mm thấm hút mồ hôi tối ưu, không trơn trượt. Dây đai nylon dày 38mm dài 4.5m dệt vạch số đo cân bằng chính xác.",
            editorialNote="Dụng cụ Calisthenics đỉnh cao phát triển sức mạnh ổn định khớp vai, ngực và bắp tay qua các bài Ring Dips và Muscle-ups.",
            priceVnd=380000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Đường kính vòng": "28 mm (Chuẩn thi đấu FIG)", "Chất liệu vòng": "Gỗ bạch dương tự nhiên", "Dây đai": "Nylon 38mm x 4.5m kèm khóa cam kim loại"},
            shopeeUrl="https://shopee.vn/product/saman-wooden-rings-13",
            curatedOrder=13,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Gỗ bạch dương tự nhiên & Dây đai nylon", maxLoadCapacityKg=400.0, usageEnvironment="Ring Dips, Ring Push-ups, Muscle-ups"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_14",
            title="Đai Lưng Nâng Tạ Da Bò Nguyên Tấm 10mm",
            subtitle="Đai đòn bẩy thép không gỉ bản rộng 10cm cố định cột sống",
            categoryId="cat_gear",
            collectionIds=["col_gym_bag"],
            productType="equipment",
            subcategoryId="Hỗ trợ áp lực ổ bụng",
            badge=None,
            description="Da bò tự nhiên 4 lớp dày 10mm bản thẳng rộng 10cm tạo điểm tựa gồng cứng cơ hoành bụng. Khóa đòn bẩy hợp kim thép không gỉ gạt khóa tức thì trong 1 giây.",
            editorialNote="Thiết kế chuẩn thi đấu Powerlifting giúp tăng áp lực ổ bụng (Intra-Abdominal Pressure) an toàn cho các hiệp Squat và Deadlift tối đa.",
            priceVnd=850000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Da bò nguyên tấm 4 lớp", "Độ dày": "10 mm", "Bản rộng": "10 cm đều", "Khóa": "Khóa đòn bẩy Lever hợp kim kẽm mạ crôm"},
            shopeeUrl="https://shopee.vn/product/saman-lever-belt-14",
            curatedOrder=14,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="100% Da bò tự nhiên dày 10mm", thicknessMm=10.0, widthCm=10.0, usageEnvironment="Heavy Squats, Deadlifts, Overhead Press"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_15",
            title="Cặp Khung Chống Đẩy Gỗ Sồi Song Song",
            subtitle="Parallettes gỗ sồi chân đế lót cao su chống trượt",
            categoryId="cat_gear",
            collectionIds=["col_home_starter"],
            productType="equipment",
            subcategoryId="Dụng cụ Calisthenics",
            badge=None,
            description="Khung chống đẩy song song gỗ sồi tự nhiên cầm chắc tay, chân đế cao su chống trượt trên nền gạch. Giữ cổ tay ở vị trí trung tính không bị bẻ gập đau nhức.",
            editorialNote="Tăng đáng kể biên độ chuyển động hít đất sâu hơn và là bệ phóng cho các kỹ thuật Handstand, L-sit và Planche.",
            priceVnd=290000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Gỗ sồi thịt tự nhiên", "Kích thước": "Dài 30cm x Rộng 14cm x Cao 11cm", "Tải trọng thử nghiệm": "200 kg"},
            shopeeUrl="https://shopee.vn/product/saman-parallettes-15",
            curatedOrder=15,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Gỗ sồi tự nhiên & Đệm cao su chống trượt", lengthCm=30.0, widthCm=14.0, maxLoadCapacityKg=200.0, usageEnvironment="Chống đẩy sâu, L-sit, Handstand sàn nhà"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_tg_16",
            title="Thảm Tập Sàn NBR Dày 15mm Chống Va Đập",
            subtitle="Thảm đệm bảo vệ cột sống và khớp gối khi tập sàn",
            categoryId="cat_gear",
            collectionIds=["col_home_starter"],
            productType="equipment",
            subcategoryId="Thảm đệm bảo vệ khớp",
            badge=None,
            description="Bọt xốp NBR mật độ cao dày 15mm êm ái triệt tiêu chấn động khi gập bụng hoặc chống gối trên sàn cứng. Bề mặt gân ngang chống trượt có dây đai cuộn xách tiện lợi.",
            editorialNote="Độ dày 15mm lý tưởng bảo vệ xương cụt và đốt sống lưng dưới cho người mới bắt đầu tập luyện thể lực tại nhà.",
            priceVnd=190000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Official Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/resistance_bands_fabric.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Bọt xốp NBR mật độ cao", "Kích thước": "183 cm x 61 cm", "Độ dày": "15 mm", "Kèm theo": "Dây đai đeo vai co giãn"},
            shopeeUrl="https://shopee.vn/product/saman-nbr-mat-16",
            curatedOrder=16,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Bọt xốp cao su tổng hợp NBR", lengthCm=183.0, widthCm=61.0, thicknessMm=15.0, usageEnvironment="Tập bụng, Yoga, Giãn cơ sàn nhà"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_01",
            title="Performance Seamless Short Sleeve",
            subtitle="Áo thun tập nam dệt ống liền không đường may",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear", "col_gym_bag"],
            productType="apparel",
            subcategoryId="Áo thun nam tập luyện",
            badge="New Arrival",
            description="Công nghệ dệt ống liền khối không đường may hai bên hông triệt tiêu hiện tượng cọ xát rát da khi vận động cường độ cao. Cấu trúc lưới vi mô tại vùng lưng và ngực tối ưu thoát nhiệt.",
            editorialNote="Chất vải polyamide cao cấp cho cảm giác mát lạnh tức thì ngay khi chạm vào da.",
            priceVnd=320000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "88% Polyamide, 12% Elastane", "Phom dáng": "Athletic Slim Fit", "Công nghệ dệt": "Seamless dệt ống tròn"},
            shopeeUrl="https://shopee.vn/product/saman-seamless-tee-01",
            curatedOrder=17,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="88% Polyamide, 12% Elastane", fitType="Athletic Slim Fit", genderTarget="Men", sizePreviewList=["S", "M", "L", "XL"], colorSwatches=[ApparelColorSwatch(name="Obsidian Black", hexColor="#16171B"), ApparelColorSwatch(name="Deep Slate", hexColor="#334155")], technologyTags=["Seamless Tube Knit", "Moisture-Wicking", "4-Way Stretch"], careInstructions=["Giặt máy nước lạnh dưới 30°C", "Không dùng nước xả vải", "Không sấy nhiệt cao"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_02",
            title="Oversized Heavyweight Cotton Gym Tee",
            subtitle="Áo thun thể hình phom rộng cotton 260gsm đứng dáng",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Áo thun Streetwear Gym",
            badge=None,
            description="100% Cotton chải kỹ định lượng dày dặn 260gsm giữ phom vai vuông vức. Thiết kế vai trễ rộng rãi tạo không gian chuyển động thoải mái tối đa cho cơ ngực và xô khi nâng tạ.",
            editorialNote="Phong cách Gym Streetwear mạnh mẽ, che khuyết điểm cơ thể và mang lại sự tự tin cho buổi tập nặng.",
            priceVnd=280000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Combed Cotton 260gsm", "Phom dáng": "Boxy Oversized Fit", "Cổ áo": "Bo rib dệt đôi chống bai dão"},
            shopeeUrl="https://shopee.vn/product/saman-oversized-tee-02",
            curatedOrder=18,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="100% Combed Cotton Heavyweight 260gsm", fitType="Boxy Oversized", genderTarget="Unisex", sizePreviewList=["M", "L", "XL", "XXL"], colorSwatches=[ApparelColorSwatch(name="Washed Charcoal", hexColor="#27272A"), ApparelColorSwatch(name="Raw Chalk", hexColor="#F4F4F5")], technologyTags=["Heavyweight 260gsm", "Drop-Shoulder", "Double-Stitched Rib"], careInstructions=["Giặt lộn trái áo", "Phơi trong bóng râm", "Ủi nhiệt độ trung bình"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_03",
            title="Core Stringer Tank Top Khoét Sâu",
            subtitle="Áo ba lỗ thể hình dây vai mảnh thoáng cơ lưng",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Áo ba lỗ thể hình",
            badge=None,
            description="Dây quai mảnh khoét nách sâu để lộ toàn bộ khối cơ ngực, vai và xô giúp quan sát sự kích hoạt cơ bắp qua gương phòng tập. Vải cotton pha spandex mềm mại thấm hút.",
            editorialNote="Dáng áo cổ điển của trường phái thể hình Golden Era, triệt tiêu mọi cản trở biên độ chuyển động cánh tay.",
            priceVnd=190000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "95% Cotton, 5% Spandex", "Kiểu dáng": "Deep-cut Stringer Y-Back", "Gấu áo": "Vạt bầu cong tự nhiên"},
            shopeeUrl="https://shopee.vn/product/saman-stringer-03",
            curatedOrder=19,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="95% Cotton, 5% Spandex", fitType="Deep-Cut Stringer", genderTarget="Men", sizePreviewList=["S", "M", "L", "XL"], colorSwatches=[ApparelColorSwatch(name="Jet Black", hexColor="#09090B"), ApparelColorSwatch(name="Military Olive", hexColor="#3F4A3C")], technologyTags=["Y-Back Mobility", "Breathable Cotton", "Curved Hem"], careInstructions=["Giặt máy nước ấm", "Không tẩy clo", "Phơi khô tự nhiên"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_04",
            title="Seamless Racerback Sports Bra",
            subtitle="Áo ngực thể thao nữ nâng đỡ vừa đệm tháo rời",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Áo ngực thể thao nữ",
            badge=None,
            description="Thiết kế lưng chữ Y Racerback giải phóng bả vai, đai chân ngực dệt viền gân đàn hồi cao cố định form vòng một. Đệm ngực mút đúc tổ ong thông khí tháo rời tiện lợi.",
            editorialNote="Mức độ nâng đỡ trung bình (Medium Support) hoàn hảo cho các buổi tập tạ, đạp xe và Yoga chuyển động năng động.",
            priceVnd=290000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "75% Nylon, 25% Spandex", "Nâng đỡ": "Medium Support", "Đệm lót": "Mút đúc có lỗ thở tháo rời"},
            shopeeUrl="https://shopee.vn/product/saman-sports-bra-04",
            curatedOrder=20,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="75% Nylon, 25% Spandex", fitType="Medium Support Compression", genderTarget="Women", sizePreviewList=["XS", "S", "M", "L"], colorSwatches=[ApparelColorSwatch(name="Dusty Rose", hexColor="#9C6B75"), ApparelColorSwatch(name="Midnight Navy", hexColor="#1E293B")], technologyTags=["Racerback Y-Cut", "Removable Honeycomb Cups", "Buttery-Soft Feel"], careInstructions=["Tháo đệm mút trước khi giặt", "Bỏ túi giặt đồ lót", "Không ủi ép nhiệt"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_05",
            title="Long Sleeve Compression Rashguard",
            subtitle="Áo nén cơ dài tay chống trầy xước và giữ nhiệt",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Áo ôm nén cơ dài tay",
            badge=None,
            description="Độ nén ôm sát hỗ trợ tuần hoàn máu vùng cơ bắp tay và vai, ngăn ngừa trầy xước da khi tiếp xúc với thanh đòn tạ gai hoặc thảm sàn. Kháng khuẩn chống hôi mồ hôi.",
            editorialNote="Tăng cường cảm thụ bản thể (Proprioception) giúp người tập cảm nhận rõ nét từng chuyển động khớp cơ.",
            priceVnd=340000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "85% Polyester, 15% Spandex", "Độ nén": "Graduated Compression", "Chỉ số chống nắng": "UPF 50+"},
            shopeeUrl="https://shopee.vn/product/saman-rashguard-05",
            curatedOrder=21,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="85% Polyester, 15% Spandex", fitType="Second-Skin Compression", genderTarget="Unisex", sizePreviewList=["S", "M", "L", "XL"], colorSwatches=[ApparelColorSwatch(name="Stealth Black", hexColor="#18181B"), ApparelColorSwatch(name="Cobalt Blue", hexColor="#1D4ED8")], technologyTags=["Flatlock Stitching", "Muscle Stabilization", "UPF 50+"], careInstructions=["Giặt nước mát", "Không vắt xoắn mạnh", "Phơi phẳng"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_06",
            title="Packable Windbreaker Training Jacket",
            subtitle="Áo khoác dù siêu nhẹ 120g trượt nước gấp gọn",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear", "col_gym_bag"],
            productType="apparel",
            subcategoryId="Áo khoác thể thao ngoài trời",
            badge=None,
            description="Vải dù ripstop siêu mỏng nhẹ chỉ 120g phủ lớp màng trượt nước DWR chắn gió và sương sớm. Tự cuộn gấp gọn gàng thành một túi nhỏ trong túi áo tiện lợi bỏ balo gym.",
            editorialNote="Bảo vệ thân nhiệt không bị lạnh đột ngột khi bước ra khỏi phòng điều hòa gym sau buổi tập đẫm mồ hôi.",
            priceVnd=390000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Micro Ripstop Polyester", "Trọng lượng": "120g siêu nhẹ", "Tính năng": "Chống gió, trượt nước nhẹ DWR"},
            shopeeUrl="https://shopee.vn/product/saman-windbreaker-06",
            curatedOrder=22,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="100% Nylon Ripstop 20D DWR Coated", fitType="Regular Athletic Fit", genderTarget="Unisex", sizePreviewList=["S", "M", "L", "XL", "XXL"], colorSwatches=[ApparelColorSwatch(name="Matte Black", hexColor="#09090B"), ApparelColorSwatch(name="Glacier Grey", hexColor="#CBD5E1")], technologyTags=["Ultralight 120g", "DWR Water-Repellent", "Packable Self-Pocket"], careInstructions=["Không giặt khô", "Không dùng chất tẩy mạnh làm bong màng DWR", "Ủi hơi nước nhẹ"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_07",
            title="Lightweight Pullover Gym Hoodie",
            subtitle="Áo hoodie nỉ da cá French Terry mỏng nhẹ xẻ tà",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Áo hoodie tập thể thao",
            badge=None,
            description="Nỉ da cá French Terry 100% cotton mỏng nhẹ thoáng khí, vạt áo xẻ tà bên hông không bị cộm vướng khi cúi gập người. Mũ trùm đầu rộng có dây rút điều chỉnh.",
            editorialNote="Chiếc áo khởi động Warm-up lý tưởng giúp cơ bắp nóng nhanh trong 15 phút đầu buổi tập.",
            priceVnd=420000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Cotton French Terry 240gsm", "Kiểu dáng": "Athletic Pullover Hoodie", "Chi tiết": "Xẻ tà hông 8cm"},
            shopeeUrl="https://shopee.vn/product/saman-hoodie-07",
            curatedOrder=23,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="100% Cotton French Terry 240gsm", fitType="Relaxed Athletic Pullover", genderTarget="Men", sizePreviewList=["M", "L", "XL"], colorSwatches=[ApparelColorSwatch(name="Heather Grey", hexColor="#9CA3AF"), ApparelColorSwatch(name="Washed Black", hexColor="#18181B")], technologyTags=["French Terry Breathability", "Side Slits", "Pre-Shrunk Cotton"], careInstructions=["Giặt máy nước lạnh", "Không sấy nhiệt cao", "Phơi phẳng râm"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_08",
            title="2-in-1 Running & Training Shorts 5\"",
            subtitle="Quần short 2 lớp tích hợp túi điện thoại chống rung",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear", "col_gym_bag"],
            productType="apparel",
            subcategoryId="Quần short 2 lớp nam",
            badge="Popular",
            description="Lớp lót bó cơ bên trong ôm đùi tích hợp túi ép nhiệt giữ điện thoại không rung lắc khi chạy. Lớp ngoài vải dệt siêu nhẹ xẻ gấu hai bên cho biên độ Squat sâu tự do.",
            editorialNote="Giải quyết dứt điểm tình trạng ma sát rát đùi trong khi chạy bộ và tập chân nặng.",
            priceVnd=350000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Độ dài đũng": "5 inch (Khoảng 13cm)", "Lớp lót": "Spandex nén cơ có túi điện thoại", "Túi sau": "Khóa kéo chống rơi chìa khóa"},
            shopeeUrl="https://shopee.vn/product/saman-2in1-shorts-08",
            curatedOrder=24,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="Vỏ ngoài: 90% Polyester, 10% Spandex; Lót trong: 82% Nylon, 18% Spandex", fitType="5-Inch Inseam 2-in-1 Athletic Fit", genderTarget="Men", sizePreviewList=["S", "M", "L", "XL"], colorSwatches=[ApparelColorSwatch(name="Onyx Black", hexColor="#0A0A0A"), ApparelColorSwatch(name="Forest Green", hexColor="#14532D")], technologyTags=["Built-in Compression Liner", "Anti-Bounce Phone Pocket", "Ventilated Gusset"], careInstructions=["Giặt máy nước mát", "Không dùng chất tẩy", "Phơi khô tự nhiên"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_09",
            title="Lightweight Mesh Linerless Shorts 7\"",
            subtitle="Quần short tập không lót lưới thể thao 2 lớp siêu nhẹ",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Quần short tập không lót",
            badge=None,
            description="Vải lưới thể thao 2 lớp thoáng khí độ dài 7 inch chạm trên gối, hai túi hông khóa kéo kim loại giấu mép giữ chìa khóa xe và thẻ gym an toàn.",
            editorialNote="Dành cho người thích sự thông thoáng tối đa hoặc tự do phối với quần lót nén cơ riêng biệt.",
            priceVnd=280000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Độ dài đũng": "7 inch (Khoảng 18cm)", "Chất liệu": "Lưới thể thao 100% Micro Mesh", "Cạp quần": "Chun dệt kèm dây rút tròn bên trong"},
            shopeeUrl="https://shopee.vn/product/saman-mesh-shorts-09",
            curatedOrder=25,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="100% Micro Polyester Mesh", fitType="7-Inch Inseam Linerless Relaxed Fit", genderTarget="Men", sizePreviewList=["M", "L", "XL", "XXL"], colorSwatches=[ApparelColorSwatch(name="Pitch Black", hexColor="#09090B"), ApparelColorSwatch(name="Steel Grey", hexColor="#4B5563")], technologyTags=["Dual-Layer Mesh", "Zippered Pockets", "Internal Drawcord"], careInstructions=["Giặt máy chế độ nhẹ", "Tránh móc nhọn cọ xát mắt lưới", "Không sấy nóng"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_10",
            title="High-Waist Squat-Proof Leggings 7/8",
            subtitle="Quần dài bó cơ nữ cạp cao cam kết không lộ nội y",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Quần dài bó cơ nữ",
            badge="Curated",
            description="Cấu trúc dệt sợi mật độ liên kết cao đạt tiêu chuẩn Squat-Proof 100% không xuyên thấu khi uốn gập sâu. Cạp cao 12cm nén nhẹ định hình bụng phẳng không trượt cuộn mép.",
            editorialNote="Bề mặt vải xử lý mờ mịn như bơ (Buttery-Soft), đường cắt vát chữ V phía sau tôn dáng vòng 3 tự nhiên.",
            priceVnd=450000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "80% Nylon, 20% Lycra", "Chiều dài": "7/8 Inseam (25 inch)", "Tính năng": "Squat-proof, Cạp cao 12cm chống cuộn"},
            shopeeUrl="https://shopee.vn/product/saman-leggings-10",
            curatedOrder=26,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="80% Nylon, 20% Lycra Spandex", fitType="7/8 Length High-Rise Compression", genderTarget="Women", sizePreviewList=["XS", "S", "M", "L"], colorSwatches=[ApparelColorSwatch(name="Espresso Brown", hexColor="#3E2723"), ApparelColorSwatch(name="Midnight Black", hexColor="#0F172A")], technologyTags=["100% Squat-Proof Guarantee", "Zero-Roll High Waistband", "Buttery-Soft Lycra"], careInstructions=["Giặt lộn trái quần", "Nước lạnh dưới 30°C", "Không dùng nước xả vải"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_11",
            title="Seamless Biker Shorts 6\"",
            subtitle="Quần đùi đạp xe nữ 6 inch dệt liền không đường viền",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Quần đùi đạp xe nữ",
            badge=None,
            description="Chiều dài 6 inch vừa vặn chạm giữa đùi dệt ống liền không đường may viền ống chân triệt tiêu hiện tượng thắt ngấn mỡ đùi. Co giãn 4 chiều chuyển động linh hoạt.",
            editorialNote="Item đa năng từ phòng gym ra phố phối cùng áo thun Oversized mang lại vẻ ngoài trẻ trung năng động.",
            priceVnd=270000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Độ dài đũng": "6 inch (Khoảng 15cm)", "Chất liệu": "Seamless Polyamide dệt ống", "Cạp quần": "Bản rộng 10cm ôm cơ hoành"},
            shopeeUrl="https://shopee.vn/product/saman-biker-shorts-11",
            curatedOrder=27,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="90% Polyamide, 10% Elastane", fitType="6-Inch High-Rise Biker Fit", genderTarget="Women", sizePreviewList=["XS", "S", "M", "L"], colorSwatches=[ApparelColorSwatch(name="Sage Green", hexColor="#84A98C"), ApparelColorSwatch(name="Slate Black", hexColor="#1E1E24")], technologyTags=["No-Dig Hemline", "Seamless Circular Knit", "4-Way Stretch"], careInstructions=["Giặt tay hoặc giặt máy nhẹ", "Không ủi ép nhiệt", "Tránh móc sắc nhọn"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_12",
            title="Tapered Fleece Gym Joggers",
            subtitle="Quần dài nỉ ống côn ôm cổ chân đũng rộng thoải mái",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Quần dài nỉ ống côn",
            badge=None,
            description="Phom dáng ống côn Tapered thu gọn về phía mắt cá chân không vướng vào bàn đạp máy tập. Đũng quần may chèn mảng vải thoi hình tam giác giải phóng biên độ khởi động háng.",
            editorialNote="Chất nỉ bông mịn giữ ấm hoàn hảo cho những ngày tập luyện vào mùa thu đông se lạnh.",
            priceVnd=410000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "70% Cotton, 30% Polyester Fleece 280gsm", "Gấu quần": "Bo chun rib dày 5cm", "Túi": "Hai túi sâu có khóa kéo ẩn"},
            shopeeUrl="https://shopee.vn/product/saman-joggers-12",
            curatedOrder=28,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="70% Cotton, 30% Polyester Fleece 280gsm", fitType="Tapered Leg Athletic Jogger", genderTarget="Men", sizePreviewList=["S", "M", "L", "XL"], colorSwatches=[ApparelColorSwatch(name="Charcoal Heather", hexColor="#374151"), ApparelColorSwatch(name="Deep Black", hexColor="#111827")], technologyTags=["Gusseted Crotch", "Heavyweight 280gsm Fleece", "Zippered Side Pockets"], careInstructions=["Giặt lộn trái", "Nước mát dưới 30°C", "Không sấy sấy nóng"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_13",
            title="Lightweight Woven Track Pants",
            subtitle="Quần gió thể thao co giãn nhẹ có khóa kéo gấu quần",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Quần gió thể thao nam",
            badge=None,
            description="Vải dệt thoi mỏng nhẹ chống thấm nước bề mặt, khóa kéo mở rộng ở gấu quần giúp cởi hoặc mặc nhanh qua giày thể thao mà không cần tháo giày.",
            editorialNote="Sự lựa chọn thực dụng của các huấn luyện viên và vận động viên chuyên nghiệp cho đồ mặc di chuyển trước trận đấu.",
            priceVnd=380000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "92% Polyester, 8% Elastane Woven", "Tính năng gấu": "Khóa kéo kim loại dài 20cm", "Bề mặt": "Chống sương trượt nước nhẹ"},
            shopeeUrl="https://shopee.vn/product/saman-track-pants-13",
            curatedOrder=29,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="92% Polyester, 8% Elastane Woven 4-Way Stretch", fitType="Streamlined Track Fit", genderTarget="Men", sizePreviewList=["M", "L", "XL", "XXL"], colorSwatches=[ApparelColorSwatch(name="Jet Black", hexColor="#09090B"), ApparelColorSwatch(name="Dark Navy", hexColor="#0F172A")], technologyTags=["Ankle Zippers for Quick Change", "4-Way Woven Stretch", "Water-Repellent Coating"], careInstructions=["Giặt máy nước mát", "Kéo kín khóa trước khi giặt", "Không ủi nhiệt cao"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_14",
            title="Set 3 Đôi Tất Cổ Lửng Đệm Gót Chân",
            subtitle="Tất dệt nén vòm bàn chân đệm dày gót và mũi chân",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear", "col_gym_bag"],
            productType="apparel",
            subcategoryId="Tất thể thao cổ trung",
            badge=None,
            description="Lớp đệm xù terry dày ở gót và mũi chân hấp thụ lực chấn động khi tiếp đất. Dải thun co giãn ôm chặt vòm bàn chân chống xê dịch phồng rộp da trong giày.",
            editorialNote="Cổ tất dệt gân rib giữ độ đàn hồi qua hàng trăm lần giặt, không bị tuột trượt xuống cổ chân.",
            priceVnd=120000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Quy cách": "Set 3 đôi", "Chất liệu": "78% Cotton, 18% Polyester, 4% Elastane", "Chiều cao cổ": "Cổ lửng Mid-Crew (15cm)"},
            shopeeUrl="https://shopee.vn/product/saman-crew-socks-14",
            curatedOrder=30,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="78% Cotton chải kỹ, 18% Polyester, 4% Elastane", fitType="Cushioned Mid-Crew", genderTarget="Unisex", sizePreviewList=["Free Size (39-44)"], colorSwatches=[ApparelColorSwatch(name="Triple White", hexColor="#FFFFFF"), ApparelColorSwatch(name="Triple Black", hexColor="#0A0A0A")], technologyTags=["Cushioned Heel & Toe", "Arch Compression Band", "Stay-Up Ribbed Cuff"], careInstructions=["Giặt máy chế độ bình thường", "Không tẩy clo", "Phơi khô tự nhiên"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_15",
            title="Set 3 Đôi Tất Tàng Hình No-Show Nén Vòm",
            subtitle="Tất cổ ngắn giấu mép tích hợp silicone gót chân chống tuột",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Tất thể thao cổ ngắn",
            badge=None,
            description="Cắt thấp giấu hoàn toàn dưới mép cổ giày thể thao. Ba dải silicone sóng ẩn ở gót chân khóa chặt vào da ngăn ngừa triệt để tình trạng tuột tất vào lòng giày.",
            editorialNote="Sợi cotton chải kỹ thấm hút mồ hôi chân và kháng khuẩn ion bạc giữ chân khô thoáng suốt ngày.",
            priceVnd=95000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Quy cách": "Set 3 đôi", "Chất liệu": "80% Cotton, 17% Nylon, 3% Spandex", "Chống tuột": "3 dải đệm Silicone gót chân"},
            shopeeUrl="https://shopee.vn/product/saman-noshow-socks-15",
            curatedOrder=31,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="80% Cotton chải kỹ, 17% Nylon, 3% Spandex", fitType="Low-Cut No-Show", genderTarget="Unisex", sizePreviewList=["Free Size (38-43)"], colorSwatches=[ApparelColorSwatch(name="Multi Pack (White/Grey/Black)", hexColor="#6B7280")], technologyTags=["Triple Silicone Heel Grippers", "Seamless Toe Closure", "Silver-Ion Anti-Odor"], careInstructions=["Giặt máy nước ấm", "Không ủi", "Tránh hóa chất tẩy rửa mạnh"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_16",
            title="Nón Kết Thể Thao Vải Dù Thoáng Khí",
            subtitle="Mũ lưỡi trai chạy bộ lỗ laser tản nhiệt quai dán mềm",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear"],
            productType="apparel",
            subcategoryId="Mũ nón thể thao",
            badge=None,
            description="Vải dù siêu nhẹ cắt lỗ laser hai bên sườn mũ đẩy hơi nóng ra ngoài liên tục. Vành nón cong mềm mại che nắng gắt mắt và quai dán khóa velcro mượt không cắn tóc.",
            editorialNote="Băng trán lót bên trong thấm hút mồ hôi ngăn chảy xuống mắt khi chạy bộ dưới trời nắng trưa.",
            priceVnd=175000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Quick-Dry Micro Polyester", "Thông khí": "Hệ thống lỗ đục Laser Cut sườn mũ", "Trọng lượng": "55g"},
            shopeeUrl="https://shopee.vn/product/saman-cap-16",
            curatedOrder=32,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="100% Quick-Dry Micro Polyester", fitType="Unstructured Low-Profile Cap", genderTarget="Unisex", sizePreviewList=["One Size (Vòng đầu 54-60cm)"], colorSwatches=[ApparelColorSwatch(name="Matte Obsidian", hexColor="#18181B"), ApparelColorSwatch(name="Silver Cloud", hexColor="#E2E8F0")], technologyTags=["Laser-Perforated Ventilation", "Moisture-Wicking Sweatband", "Snag-Free Velcro Strap"], careInstructions=["Giặt nhẹ bằng tay", "Không vắt vặn xoắn vành nón", "Phơi khô tự nhiên"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_17",
            title="Băng Đô Thấm Mồ Hôi Trán Chống Trượt",
            subtitle="Băng đô trán dải silicone ẩn giữ tóc và chặn mồ hôi",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear", "col_gym_bag"],
            productType="apparel",
            subcategoryId="Băng đô trán",
            badge=None,
            description="Sợi vi sợi dệt mỏng đàn hồi cao, dải silicone mờ mặt trong bám nhẹ vào trán không làm xước da hay hằn vết đỏ. Chặn đứng 100% giọt mồ hôi chảy cay mắt.",
            editorialNote="Vật bất ly thân cho người tóc dài và các bài tập cường độ cao như HIIT, nhảy dây, đạp xe trong nhà.",
            priceVnd=85000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "85% Polyester, 15% Spandex", "Bản rộng": "5 cm", "Chống trượt": "Dải Silicone chạy viền trong"},
            shopeeUrl="https://shopee.vn/product/saman-headband-17",
            curatedOrder=33,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="85% Polyester, 15% Spandex", fitType="Elastic Grip Headband", genderTarget="Unisex", sizePreviewList=["One Size Co Giãn"], colorSwatches=[ApparelColorSwatch(name="Black", hexColor="#000000"), ApparelColorSwatch(name="Slate", hexColor="#475569")], technologyTags=["Inner Silicone Non-Slip Strip", "Sweat-Blocking Barrier", "Ultra-Thin 5cm Width"], careInstructions=["Giặt tay nước ấm", "Không tẩy", "Phơi râm"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_18",
            title="Đôi Băng Đeo Tay Thấm Mồ Hôi Cotton",
            subtitle="Terry cloth cotton 100% thấm hút lau mồ hôi mặt nhanh",
            categoryId="cat_apparel",
            collectionIds=["col_active_wear", "col_gym_bag"],
            productType="apparel",
            subcategoryId="Băng tay cotton",
            badge=None,
            description="Bông xù cotton tự nhiên dày dặn thấm hút mồ hôi trán tức thì chỉ bằng một cái gạt tay mà không cần buông tạ tìm khăn lau. Đàn hồi ôm sát cổ tay êm ái.",
            editorialNote="Tiện dụng tuyệt đối khi đang nâng tạ đòn hoặc đang trên máy chạy bộ không rảnh tay.",
            priceVnd=75000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Quy cách": "Cặp 2 chiếc", "Chất liệu": "100% Bông cotton chải xù", "Chiều dài": "8 cm"},
            shopeeUrl="https://shopee.vn/product/saman-wristbands-18",
            curatedOrder=34,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="80% Cotton Terry, 12% Spandex, 8% Nylon", fitType="Snug Wrist Wrap", genderTarget="Unisex", sizePreviewList=["One Size Co Giãn (Dài 8cm)"], colorSwatches=[ApparelColorSwatch(name="Classic Black", hexColor="#111827"), ApparelColorSwatch(name="Sport Grey", hexColor="#9CA3AF")], technologyTags=["High-Density Terry Loops", "Instant Sweat Absorption", "Reinforced Elasticity"], careInstructions=["Giặt máy nước ấm", "Có thể sấy nhẹ", "Không ủi"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_19",
            title="Khăn Tập Gym Microfiber 40x80cm",
            subtitle="Khăn vi sợi kháng khuẩn thấm hút gấp 5 lần có móc treo",
            categoryId="cat_apparel",
            collectionIds=["col_gym_bag"],
            productType="apparel",
            subcategoryId="Khăn tập thể thao",
            badge=None,
            description="Sợi vi mảnh microfiber mềm mịn thấm hút nước gấp 5 lần trọng lượng khăn và khô nhanh gấp 3 lần cotton. Tích hợp móc treo silicon treo thành máy tập sạch sẽ.",
            editorialNote="Kích thước 40x80cm chuẩn mực phủ vừa vặn tựa lưng ghế dốc và ghế Bench Press giữ vệ sinh chung.",
            priceVnd=110000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Kích thước": "40 cm x 80 cm", "Chất liệu": "80% Polyester, 20% Polyamide Microfiber", "Trọng lượng": "90g"},
            shopeeUrl="https://shopee.vn/product/saman-towel-19",
            curatedOrder=35,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="80% Polyester, 20% Polyamide High-Density Microfiber", fitType="Compact Fitness Towel (40x80cm)", genderTarget="Unisex", sizePreviewList=["40 x 80 cm"], colorSwatches=[ApparelColorSwatch(name="Anthracite Dark Grey", hexColor="#1F2937"), ApparelColorSwatch(name="Teal Blue", hexColor="#0F766E")], technologyTags=["Fast-Drying Microfiber", "Silicone Hanging Loop", "Bench-Coverage Sizing"], careInstructions=["Giặt máy nước ấm", "Không dùng nước xả vải làm giảm độ thấm hút", "Phơi khô nhanh"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_ap_20",
            title="Túi Trống Thể Thao Canvas 35L Ngăn Giày Riêng",
            subtitle="Túi duffel vải trượt nước có ngăn thông hơi giày và đồ ướt",
            categoryId="cat_apparel",
            collectionIds=["col_gym_bag"],
            productType="apparel",
            subcategoryId="Túi đựng đồ tập",
            badge=None,
            description="Vải Oxford 900D phủ trượt nước dung tích 35L chứa vừa vặn quần áo, thắt lưng nâng tạ và bình nước. Ngăn để giày riêng biệt có lỗ thoáng khí khử mùi thông minh.",
            editorialNote="Quai đeo vai đệm mút tổ ong phân tán lực êm ái khi mang theo nhiều phụ kiện tập nặng.",
            priceVnd=480000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Athletics Lab",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/apparel_seamless_tee.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích chứa": "35 Lít", "Kích thước": "Dài 50cm x Rộng 26cm x Cao 27cm", "Chất liệu": "Oxford 900D chống thấm"},
            shopeeUrl="https://shopee.vn/product/saman-duffel-bag-20",
            curatedOrder=36,
            equipmentAttributes=None,
            apparelAttributes=ApparelAttributes(fabricComposition="Vải Oxford Polyester 900D phủ màng PU trượt nước", fitType="35L Modular Duffel Bag", genderTarget="Unisex", sizePreviewList=["Dung tích 35L (50x26x27cm)"], colorSwatches=[ApparelColorSwatch(name="Matte Obsidian", hexColor="#18181B")], technologyTags=["Ventilated Shoe Compartment", "Wet-Dry Pocket Separation", "Padded Ergonomic Strap"], careInstructions=["Lau sạch bằng khăn ẩm", "Không giặt máy làm gãy phom túi", "Phơi nơi khô ráo"]),
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_01",
            title="Yến Mạch Ngâm Socola Đen Overnight Oats 350g",
            subtitle="Yến mạch cán vỡ ngâm sẵn bột cacao nguyên chất và hạt chia",
            categoryId="cat_food_beverage",
            collectionIds=["col_quick_breakfast"],
            productType="food",
            subcategoryId="Bữa sáng tiện lợi",
            badge="Breakfast Pick",
            description="Hũ yến mạch dinh dưỡng pha chế sẵn với cacao nguyên chất Đắk Lắk và hạt chia hữu cơ. Chỉ cần đổ sữa chua hoặc sữa tươi vào hũ, để lạnh 20 phút là có bữa sáng cân bằng giàu năng lượng sạch.",
            editorialNote="Giải pháp bữa sáng lý tưởng cho người bận rộn muốn nạp đủ carbs phức hợp và chất xơ trước 8 giờ sáng.",
            priceVnd=115000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "350g", "Số khẩu phần": "7 khẩu phần (50g/lần)", "Hạn sử dụng": "9 tháng kể từ ngày sản xuất"},
            shopeeUrl="https://shopee.vn/product/saman-overnight-oats-01",
            curatedOrder=37,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="350g", servingSizeText="50g (Khoảng 5 muỗng gạt)", servingsPerContainer=7, perServingMacros=MacroNutrients(energyKcal=195, proteinGrams=7.5, carbohydratesGrams=28.0, totalFatGrams=5.2, saturatedFatGrams=1.1, dietaryFiberGrams=6.0, sugarsGrams=0.5, sodiumMg=18), per100gMacros=MacroNutrients(energyKcal=390, proteinGrams=15.0, carbohydratesGrams=56.0, totalFatGrams=10.4, saturatedFatGrams=2.2, dietaryFiberGrams=12.0, sugarsGrams=1.0, sodiumMg=36), ingredientsText="Yến mạch cán dẹt nguyên hạt (70%), hạt chia hữu cơ (15%), bột cacao nguyên chất 100% (10%), muối hồng Himalaya (0.5%).", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Bảo quản nơi khô ráo thoáng mát, đậy kín nắp sau khi mở.", shelfLifeText="9 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_02",
            title="Granola Nướng Mộc Không Đường 400g",
            subtitle="Yến mạch nguyên cám nướng vàng cùng hạnh nhân và việt quất",
            categoryId="cat_food_beverage",
            collectionIds=["col_quick_breakfast"],
            productType="food",
            subcategoryId="Bữa sáng tiện lợi",
            badge=None,
            description="Yến mạch nướng giòn mộc hoàn toàn không tẩm ướp si-rô đường hay mật ong công nghiệp. Kết hợp các loại hạt dinh dưỡng cao cấp hạnh nhân Úc, hạt bí xanh và quả việt quất khô thanh dịu.",
            editorialNote="Không chứa đường tinh luyện (Zero Added Sugar), an toàn tuyệt đối cho chế độ ăn kiêng Low-Carb và người cần kiểm soát đường huyết.",
            priceVnd=165000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "400g", "Thành phần hạt": "Hạnh nhân, Hạt bí, Yến mạch, Việt quất", "Đường bổ sung": "0g (Không đường)"},
            shopeeUrl="https://shopee.vn/product/saman-granola-02",
            curatedOrder=38,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="400g", servingSizeText="40g", servingsPerContainer=10, perServingMacros=MacroNutrients(energyKcal=180, proteinGrams=6.0, carbohydratesGrams=22.0, totalFatGrams=7.5, saturatedFatGrams=0.9, dietaryFiberGrams=4.5, sugarsGrams=0.0, sodiumMg=12), per100gMacros=MacroNutrients(energyKcal=450, proteinGrams=15.0, carbohydratesGrams=55.0, totalFatGrams=18.8, saturatedFatGrams=2.3, dietaryFiberGrams=11.2, sugarsGrams=0.0, sodiumMg=30), ingredientsText="Yến mạch nguyên cám (55%), hạnh nhân thái lát (15%), hạt bí xanh tách vỏ (15%), việt quất khô tự nhiên (14%), chiết xuất vani (1%).", allergenStatus=AllergenStatus.containsAllergens, allergenList=["tree_nuts"], storageInstructions="Bảo quản nơi khô ráo, đậy kín túi zip sau khi dùng.", shelfLifeText="6 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_03",
            title="Cháo Yến Mạch Protein Vị Táo Quế Gói Tiện Lợi",
            subtitle="Bột yến mạch pha đạm thực vật và táo đỏ sấy giòn 50g",
            categoryId="cat_food_beverage",
            collectionIds=["col_quick_breakfast"],
            productType="food",
            subcategoryId="Bữa sáng tiện lợi",
            badge=None,
            description="Gói cháo yến mạch ăn liền bổ sung 15g đạm thực vật hữu cơ cùng bột quế Ceylon thơm nồng và táo giòn thăng hoa. Chỉ cần đổ 150ml nước sôi khuấy đều trong 3 phút là sẵn sàng thưởng thức.",
            editorialNote="Bữa sáng ấm bụng hoàn hảo cho những buổi sáng vội vã cần bữa ăn nóng trước giờ làm việc.",
            priceVnd=32000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng": "50g / gói", "Hàm lượng Protein": "15g mỗi gói", "Cách dùng": "Thêm 150ml nước sôi, chờ 3 phút"},
            shopeeUrl="https://shopee.vn/product/saman-protein-porridge-03",
            curatedOrder=39,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="50g", servingSizeText="1 gói (50g)", servingsPerContainer=1, perServingMacros=MacroNutrients(energyKcal=190, proteinGrams=15.0, carbohydratesGrams=24.0, totalFatGrams=3.2, saturatedFatGrams=0.5, dietaryFiberGrams=5.0, sugarsGrams=2.5, sodiumMg=45), per100gMacros=MacroNutrients(energyKcal=380, proteinGrams=30.0, carbohydratesGrams=48.0, totalFatGrams=6.4, saturatedFatGrams=1.0, dietaryFiberGrams=10.0, sugarsGrams=5.0, sodiumMg=90), ingredientsText="Bột yến mạch mịn (60%), đạm đậu Hà Lan cô lập (25%), táo sấy thăng hoa (10%), bột quế hữu cơ Ceylon (4%), muối biển (1%).", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Nơi khô ráo, tránh ánh nắng trực tiếp.", shelfLifeText="12 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_04",
            title="Ngũ Cốc Mảnh Nguyên Cám Sấy Giòn 300g",
            subtitle="Mảnh lúa mì và yến mạch ép đùn sấy giòn tự nhiên",
            categoryId="cat_food_beverage",
            collectionIds=["col_quick_breakfast"],
            productType="food",
            subcategoryId="Bữa sáng tiện lợi",
            badge=None,
            description="Các mảnh ngũ cốc nguyên cám vàng ươm sấy giòn không dầu, giữ nguyên hàm lượng chất xơ beta-glucan và các vitamin nhóm B tự nhiên. Thích hợp ăn kèm sữa chua Hy Lạp hoặc sữa tươi.",
            editorialNote="Cung cấp nguồn carbohydrate giải phóng chậm duy trì năng lượng bền bỉ suốt buổi sáng mà không làm sụt giảm năng lượng giữa chừng.",
            priceVnd=88000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "300g", "Thành phần chính": "Lúa mì nguyên cám, Yến mạch", "Đường": "Ít ngọt (<3g/100g)"},
            shopeeUrl="https://shopee.vn/product/saman-cereal-flakes-04",
            curatedOrder=40,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="300g", servingSizeText="40g", servingsPerContainer=7, perServingMacros=MacroNutrients(energyKcal=150, proteinGrams=4.5, carbohydratesGrams=30.0, totalFatGrams=1.2, saturatedFatGrams=0.2, dietaryFiberGrams=4.0, sugarsGrams=1.2, sodiumMg=60), per100gMacros=MacroNutrients(energyKcal=375, proteinGrams=11.2, carbohydratesGrams=75.0, totalFatGrams=3.0, saturatedFatGrams=0.5, dietaryFiberGrams=10.0, sugarsGrams=3.0, sodiumMg=150), ingredientsText="Lúa mì nguyên cám (75%), yến mạch nguyên cám (20%), chiết xuất mầm lúa mạch (4%), muối i-ốt (1%).", allergenStatus=AllergenStatus.containsAllergens, allergenList=["gluten"], storageInstructions="Bảo quản trong hộp kín khí sau khi xé miệng túi.", shelfLifeText="12 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_05",
            title="Bánh Mì Hoa Cúc Nguyên Cám Giàu Đạm 250g",
            subtitle="Bánh mì men chậm bột nguyên cám bổ sung lòng trắng trứng",
            categoryId="cat_food_beverage",
            collectionIds=["col_quick_breakfast"],
            productType="food",
            subcategoryId="Bữa sáng tiện lợi",
            badge=None,
            description="Bánh mì nướng men tự nhiên từ 100% bột lúa mì nguyên cám thô kết hợp lòng trắng trứng tươi tăng cường protein. Vị thơm hoa cúc thoang thoảng mềm xốp dễ ăn.",
            editorialNote="Chỉ số đường huyết GI thấp giúp no lâu, mỗi 2 lát bánh cung cấp đến 12g protein nạp nhanh cho cơ bắp.",
            priceVnd=75000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng": "250g (Khoảng 8 lát)", "Protein": "12g / 2 lát (60g)", "Bảo quản": "Ăn ngay hoặc nướng nóng 1-2 phút"},
            shopeeUrl="https://shopee.vn/product/saman-protein-bread-05",
            curatedOrder=41,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="250g", servingSizeText="2 lát (khoảng 60g)", servingsPerContainer=4, perServingMacros=MacroNutrients(energyKcal=160, proteinGrams=12.0, carbohydratesGrams=22.0, totalFatGrams=2.5, saturatedFatGrams=0.4, dietaryFiberGrams=4.2, sugarsGrams=1.8, sodiumMg=120), per100gMacros=MacroNutrients(energyKcal=266, proteinGrams=20.0, carbohydratesGrams=36.6, totalFatGrams=4.1, saturatedFatGrams=0.7, dietaryFiberGrams=7.0, sugarsGrams=3.0, sodiumMg=200), ingredientsText="Bột mì nguyên cám 100% (65%), lòng trắng trứng gà tiệt trùng (20%), nước hoa cúc tự nhiên (10%), men nở tự nhiên (3%), muối biển (2%).", allergenStatus=AllergenStatus.containsAllergens, allergenList=["gluten", "eggs"], storageInstructions="Nơi mát mẻ 3 ngày hoặc ngăn mát tủ lạnh 10 ngày.", shelfLifeText="10 ngày từ ngày nướng"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_06",
            title="Bánh Biscotti Nguyên Cám Hạt Phỉ 250g",
            subtitle="Bánh nướng 2 lần không bơ sữa giòn tan giàu hạt dinh dưỡng",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks"],
            productType="food",
            subcategoryId="Bánh & đồ ăn nhẹ",
            badge="Popular",
            description="Bánh quy phong cách Ý nướng 2 lần giòn rụm không sử dụng bơ động vật hay dầu chiên. Hạt phỉ Thổ Nhĩ Kỳ và hạnh nhân bùi béo kết hợp vỏ cam vàng sấy the mát.",
            editorialNote="Món ăn vặt healthy kiểm soát cơn đói chiều lý tưởng mà không nạp dư chất béo xấu.",
            priceVnd=135000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "250g", "Thành phần hạt": "Hạt phỉ, Hạnh nhân, Nho khô", "Chất béo": "Không dùng bơ sữa động vật"},
            shopeeUrl="https://shopee.vn/product/saman-biscotti-06",
            curatedOrder=42,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="250g", servingSizeText="30g (Khoảng 3-4 thanh)", servingsPerContainer=8, perServingMacros=MacroNutrients(energyKcal=130, proteinGrams=4.5, carbohydratesGrams=18.0, totalFatGrams=4.8, saturatedFatGrams=0.6, dietaryFiberGrams=2.5, sugarsGrams=2.0, sodiumMg=25), per100gMacros=MacroNutrients(energyKcal=433, proteinGrams=15.0, carbohydratesGrams=60.0, totalFatGrams=16.0, saturatedFatGrams=2.0, dietaryFiberGrams=8.3, sugarsGrams=6.6, sodiumMg=83), ingredientsText="Bột mì nguyên cám (45%), hạt phỉ (20%), hạnh nhân (15%), trứng gà (15%), vỏ cam vàng sấy (4%), muối (1%).", allergenStatus=AllergenStatus.containsAllergens, allergenList=["tree_nuts", "eggs", "gluten"], storageInstructions="Đậy kín hộp, tránh để hở gió làm ỉu bánh.", shelfLifeText="4 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_07",
            title="Snack Rong Biển Kẹp Hạt Nướng Protein 60g",
            subtitle="Lá rong biển Hàn Quốc nướng kẹp hạt điều và gạo lứt huyết rồng",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks"],
            productType="food",
            subcategoryId="Bánh & đồ ăn nhẹ",
            badge=None,
            description="Lá rong biển sấy giòn tan kẹp giữa nhân hạt điều Bình Phước nghiền thô, hạt bí xanh và hạt gạo lứt huyết rồng rang phồng. Nướng sấy nhiệt không chiên ngập dầu.",
            editorialNote="Vị mặn bùi tự nhiên của rong biển biển sâu kết hợp hạt giàu đạm, gói 60g tiện lợi bỏ túi xách đi làm.",
            priceVnd=45000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng": "60g / gói", "Phương pháp": "Nướng khí đối lưu không chiên dầu", "Xuất xứ": "Rong biển nhập khẩu Hàn Quốc"},
            shopeeUrl="https://shopee.vn/product/saman-seaweed-snack-07",
            curatedOrder=43,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="60g", servingSizeText="30g (Nửa gói)", servingsPerContainer=2, perServingMacros=MacroNutrients(energyKcal=145, proteinGrams=5.2, carbohydratesGrams=14.0, totalFatGrams=8.0, saturatedFatGrams=1.5, dietaryFiberGrams=2.8, sugarsGrams=0.8, sodiumMg=95), per100gMacros=MacroNutrients(energyKcal=483, proteinGrams=17.3, carbohydratesGrams=46.6, totalFatGrams=26.6, saturatedFatGrams=5.0, dietaryFiberGrams=9.3, sugarsGrams=2.6, sodiumMg=316), ingredientsText="Lá rong biển Hàn Quốc (35%), hạt điều (25%), hạt bí xanh (20%), gạo lứt huyết rồng (15%), nước tương lên men đậu nành (4%), mè rang (1%).", allergenStatus=AllergenStatus.containsAllergens, allergenList=["tree_nuts", "soy"], storageInstructions="Ăn liền sau khi mở gói, tránh ẩm.", shelfLifeText="8 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_08",
            title="Thanh Năng Lượng Chà Là Hạnh Nhân Tự Nhiên",
            subtitle="Raw bar ép lạnh 100% từ quả chà là Medjool và hạnh nhân 45g",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks"],
            productType="food",
            subcategoryId="Bánh & đồ ăn nhẹ",
            badge=None,
            description="Thanh năng lượng thô Raw Energy Bar ép lạnh nguyên liệu hữu cơ, không gia nhiệt, không si-rô ngô hay chất bảo quản. Cung cấp carbohydrate hấp thu tự nhiên cho vận động viên.",
            editorialNote="Cứu cánh năng lượng tuyệt vời ăn trước buổi tập 30 phút để có buổi nâng tạ sung mãn.",
            priceVnd=35000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng": "45g / thanh", "Chế biến": "Ép lạnh không qua nướng nhiệt", "Đường tinh luyện": "0% (Chỉ đường từ quả chà là)"},
            shopeeUrl="https://shopee.vn/product/saman-energy-bar-08",
            curatedOrder=44,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="45g", servingSizeText="1 thanh (45g)", servingsPerContainer=1, perServingMacros=MacroNutrients(energyKcal=185, proteinGrams=4.8, carbohydratesGrams=26.0, totalFatGrams=7.2, saturatedFatGrams=0.8, dietaryFiberGrams=4.0, sugarsGrams=18.0, sodiumMg=5), per100gMacros=MacroNutrients(energyKcal=411, proteinGrams=10.6, carbohydratesGrams=57.7, totalFatGrams=16.0, saturatedFatGrams=1.7, dietaryFiberGrams=8.8, sugarsGrams=40.0, sodiumMg=11), ingredientsText="Quả chà là Medjool ép nhuyễn (60%), hạnh nhân thô nghiền (30%), bột cacao nguyên chất (8%), muối biển (2%).", allergenStatus=AllergenStatus.containsAllergens, allergenList=["tree_nuts"], storageInstructions="Nơi khô mát, ngon hơn khi giữ lạnh nhẹ.", shelfLifeText="6 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_09",
            title="Bánh Quy Yến Mạch Chuối Hạt Chia Mềm Dẻo",
            subtitle="Bánh nướng mềm vị ngọt thanh từ chuối chín tự nhiên",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks"],
            productType="food",
            subcategoryId="Bánh & đồ ăn nhẹ",
            badge=None,
            description="Kết cấu mềm dẻo Soft-Baked từ chuối tươi nghiền nướng cùng yến mạch nguyên hạt và hạt chia Nam Mỹ. Vị ngọt thanh thuần khiết từ hoa quả tự nhiên, không dùng đường mía.",
            editorialNote="Bữa phụ giàu chất xơ hòa tan giúp hỗ trợ nhu động ruột khỏe mạnh và không gây cảm giác đầy bụng ngấy ngọt.",
            priceVnd=85000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "200g (Hộp 6 bánh)", "Vị ngọt": "100% từ chuối tươi chín tự nhiên", "Chất béo": "Không dùng mỡ động vật"},
            shopeeUrl="https://shopee.vn/product/saman-chia-cookies-09",
            curatedOrder=45,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="200g", servingSizeText="1 chiếc (khoảng 33g)", servingsPerContainer=6, perServingMacros=MacroNutrients(energyKcal=110, proteinGrams=3.2, carbohydratesGrams=18.5, totalFatGrams=2.8, saturatedFatGrams=0.4, dietaryFiberGrams=3.0, sugarsGrams=3.5, sodiumMg=20), per100gMacros=MacroNutrients(energyKcal=330, proteinGrams=9.6, carbohydratesGrams=55.5, totalFatGrams=8.4, saturatedFatGrams=1.2, dietaryFiberGrams=9.0, sugarsGrams=10.5, sodiumMg=60), ingredientsText="Yến mạch cán dẹt (50%), chuối tươi chín nghiền (35%), hạt chia hữu cơ (10%), dầu dừa nguyên chất (4%), quế (1%).", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Bảo quản nơi thoáng mát, đậy kín nắp sau khi bóc hộp.", shelfLifeText="3 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_10",
            title="Đậu Gà Sấy Giòn Vị Muối Chanh Biển 150g",
            subtitle="Đậu gà hạt tròn sấy chân không giòn xốp giàu đạm thực vật",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks"],
            productType="food",
            subcategoryId="Bánh & đồ ăn nhẹ",
            badge=None,
            description="Đậu gà hạt tròn ngâm nở sấy chân không giòn rụm bên trong, rắc lớp gia vị muối biển hột và vỏ chanh thơm lừng sảng khoái. Hàm lượng đạm thực vật và chất xơ vượt trội.",
            editorialNote="Thay thế hoàn hảo cho các món snack khoai tây chiên nhiều muối và chất béo chuyển hóa bão hòa.",
            priceVnd=68000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "150g", "Công nghệ sấy": "Sấy chân không giòn xốp không ngập dầu", "Đạm thực vật": "20g protein / 100g"},
            shopeeUrl="https://shopee.vn/product/saman-chickpeas-10",
            curatedOrder=46,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="150g", servingSizeText="30g", servingsPerContainer=5, perServingMacros=MacroNutrients(energyKcal=125, proteinGrams=6.0, carbohydratesGrams=18.0, totalFatGrams=3.0, saturatedFatGrams=0.4, dietaryFiberGrams=5.0, sugarsGrams=1.0, sodiumMg=85), per100gMacros=MacroNutrients(energyKcal=416, proteinGrams=20.0, carbohydratesGrams=60.0, totalFatGrams=10.0, saturatedFatGrams=1.3, dietaryFiberGrams=16.6, sugarsGrams=3.3, sodiumMg=283), ingredientsText="Đậu gà hữu cơ (90%), dầu hướng dương ép lạnh (6%), muối biển tự nhiên (2%), bột vỏ chanh tươi sấy (2%).", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Đóng chặt khóa zip sau khi dùng để giữ độ giòn.", shelfLifeText="9 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_11",
            title="Bơ Đậu Phộng Nguyên Chất 100% Dạng Mịn 350g",
            subtitle="Đậu phộng sẻ rang xay chậm mịn không đường không dầu cọ",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks", "col_quick_breakfast"],
            productType="food",
            subcategoryId="Hạt & bơ hạt",
            badge="Curated",
            description="100% Đậu phộng sẻ hạt tròn rang thơm xay chậm trên cối đá giữ nguyên vẹn chất béo không bão hòa đơn tốt cho tim mạch. Không thêm đường, không muối, không dầu cọ hydro hóa.",
            editorialNote="Hiện tượng tách một lớp dầu mỏng tự nhiên trên bề mặt là bảo chứng cho độ nguyên chất không dùng phụ gia ổn định nhũ hóa.",
            priceVnd=95000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "350g", "Thành phần": "100% Đậu phộng sẻ Việt Nam", "Phụ gia": "0% Phụ gia chất bảo quản"},
            shopeeUrl="https://shopee.vn/product/saman-peanut-butter-11",
            curatedOrder=47,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="350g", servingSizeText="30g (Khoảng 2 muỗng canh)", servingsPerContainer=11, perServingMacros=MacroNutrients(energyKcal=185, proteinGrams=8.5, carbohydratesGrams=4.5, totalFatGrams=15.0, saturatedFatGrams=2.2, dietaryFiberGrams=2.5, sugarsGrams=1.2, sodiumMg=5), per100gMacros=MacroNutrients(energyKcal=616, proteinGrams=28.3, carbohydratesGrams=15.0, totalFatGrams=50.0, saturatedFatGrams=7.3, dietaryFiberGrams=8.3, sugarsGrams=4.0, sodiumMg=16), ingredientsText="100% Đậu phộng sẻ thuần chủng rang mộc xay mịn.", allergenStatus=AllergenStatus.containsAllergens, allergenList=["peanuts"], storageInstructions="Nơi khô ráo hoặc ngăn mát tủ lạnh sau khi mở nắp, khuấy đều lớp dầu tự nhiên trước khi múc.", shelfLifeText="6 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_12",
            title="Bơ Hạnh Nhân Giòn Hạt Chia Thô 300g",
            subtitle="Hạnh nhân rang xay giữ mảnh giòn vụn trộn hạt chia hữu cơ",
            categoryId="cat_food_beverage",
            collectionIds=["col_quick_breakfast"],
            productType="food",
            subcategoryId="Hạt & bơ hạt",
            badge=None,
            description="Hạnh nhân Úc rang thơm xay giữ lại các mảnh giòn hạt vui miệng, trộn hạt chia thô Nam Mỹ giàu Omega-3. Hương vị bùi béo tự nhiên quét kèm bánh mì nguyên cám hoặc chuối tươi.",
            editorialNote="Nguồn vitamin E và chất chống oxy hóa dồi dào hỗ trợ bảo vệ màng tế bào cơ bắp trong các giai đoạn tập luyện nặng.",
            priceVnd=195000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "300g", "Thành phần": "90% Hạnh nhân, 10% Hạt chia", "Độ giòn": "Crunchy mảnh vụn hạt"},
            shopeeUrl="https://shopee.vn/product/saman-almond-butter-12",
            curatedOrder=48,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="300g", servingSizeText="30g", servingsPerContainer=10, perServingMacros=MacroNutrients(energyKcal=190, proteinGrams=7.0, carbohydratesGrams=5.0, totalFatGrams=16.0, saturatedFatGrams=1.5, dietaryFiberGrams=3.8, sugarsGrams=1.0, sodiumMg=4), per100gMacros=MacroNutrients(energyKcal=633, proteinGrams=23.3, carbohydratesGrams=16.6, totalFatGrams=53.3, saturatedFatGrams=5.0, dietaryFiberGrams=12.6, sugarsGrams=3.3, sodiumMg=13), ingredientsText="Hạnh nhân nhập khẩu Úc rang thơm (90%), hạt chia hữu cơ nguyên hạt (10%).", allergenStatus=AllergenStatus.containsAllergens, allergenList=["tree_nuts"], storageInstructions="Bảo quản nơi khô ráo, tránh ánh sáng trực tiếp.", shelfLifeText="6 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_13",
            title="Hạt Điều Bình Phước Rang Mộc Củi 250g",
            subtitle="Hạt điều loại 1 giữ vỏ lụa rang củi than tự nhiên không muối",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks"],
            productType="food",
            subcategoryId="Hạt & bơ hạt",
            badge=None,
            description="Hạt điều loại 1 tuyển chọn vùng đất đỏ bazan Bình Phước rang thủ công bằng than củi tự nhiên. Lớp vỏ lụa giữ trọn vị ngọt thơm béo ngậy nguyên bản của hạt không cần tẩm muối.",
            editorialNote="Giàu khoáng chất Magie và Kẽm tự nhiên cần thiết cho quá trình tổng hợp protein và phục hồi hormone cơ bắp.",
            priceVnd=125000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "250g", "Quy cách": "Hạt nguyên vẹn giữ vỏ lụa", "Muối tẩm": "0% (Rang mộc hoàn toàn)"},
            shopeeUrl="https://shopee.vn/product/saman-cashews-13",
            curatedOrder=49,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="250g", servingSizeText="30g (Khoảng 15-18 hạt)", servingsPerContainer=8, perServingMacros=MacroNutrients(energyKcal=170, proteinGrams=5.5, carbohydratesGrams=9.0, totalFatGrams=13.5, saturatedFatGrams=2.5, dietaryFiberGrams=1.0, sugarsGrams=1.8, sodiumMg=5), per100gMacros=MacroNutrients(energyKcal=566, proteinGrams=18.3, carbohydratesGrams=30.0, totalFatGrams=45.0, saturatedFatGrams=8.3, dietaryFiberGrams=3.3, sugarsGrams=6.0, sodiumMg=16), ingredientsText="100% Hạt điều vỏ lụa Bình Phước rang mộc than củi.", allergenStatus=AllergenStatus.containsAllergens, allergenList=["tree_nuts"], storageInstructions="Đậy kín hộp sau khi bóc vỏ lụa thưởng thức.", shelfLifeText="6 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_14",
            title="Hạt Hạnh Nhân Úc Sấy Mộc Giữ Vỏ 250g",
            subtitle="Hạnh nhân sấy khí đối lưu nguyên vị giòn ngọt thanh khiết",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks"],
            productType="food",
            subcategoryId="Hạt & bơ hạt",
            badge=None,
            description="Hạnh nhân nhập khẩu Úc sấy khí nóng đối lưu kiểm soát nhiệt độ nghiêm ngặt không làm cháy khét tinh dầu hạt. Giữ nguyên độ giòn ngọt thanh khiết và màu vỏ nâu tự nhiên.",
            editorialNote="Chỉ 1 nắm nhỏ 30g mỗi ngày cung cấp đủ 50% nhu cầu Vitamin E chống oxy hóa cho cơ thể vận động.",
            priceVnd=140000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "250g", "Xuất xứ": "Úc (Australia)", "Đóng gói": "Hũ nhựa nắp nhôm kín khí"},
            shopeeUrl="https://shopee.vn/product/saman-almonds-14",
            curatedOrder=50,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="250g", servingSizeText="30g (Khoảng 20-22 hạt)", servingsPerContainer=8, perServingMacros=MacroNutrients(energyKcal=175, proteinGrams=6.3, carbohydratesGrams=6.0, totalFatGrams=15.0, saturatedFatGrams=1.2, dietaryFiberGrams=3.6, sugarsGrams=1.3, sodiumMg=3), per100gMacros=MacroNutrients(energyKcal=583, proteinGrams=21.0, carbohydratesGrams=20.0, totalFatGrams=50.0, saturatedFatGrams=4.0, dietaryFiberGrams=12.0, sugarsGrams=4.3, sodiumMg=10), ingredientsText="100% Hạt hạnh nhân nguyên vỏ sấy mộc.", allergenStatus=AllergenStatus.containsAllergens, allergenList=["tree_nuts"], storageInstructions="Bảo quản nơi khô ráo thoáng mát, đậy nắp chặt.", shelfLifeText="8 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_15",
            title="Hạt Óc Chó Chile Tách Vỏ Nguyên Nửa 200g",
            subtitle="Nhân óc chó sáng màu giàu Omega-3 thực vật chống viêm",
            categoryId="cat_food_beverage",
            collectionIds=["col_quick_breakfast"],
            productType="food",
            subcategoryId="Hạt & bơ hạt",
            badge=None,
            description="Nhân hạt óc chó Chile loại 1 tách vỏ giữ nguyên nửa hạt đẹp mắt, thịt hạt sáng màu không hôi dầu. Hàm lượng axit béo Omega-3 thực vật (ALA) cao nhất trong các loại hạt.",
            editorialNote="Hỗ trợ giảm thiểu tình trạng viêm đau cơ bắp sau các bài tập nặng (DOMS) và tăng cường sức khỏe não bộ.",
            priceVnd=155000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "200g", "Xuất xứ": "Chile", "Quy cách": "Nhân nguyên nửa (Light Halves 80%)"},
            shopeeUrl="https://shopee.vn/product/saman-walnuts-15",
            curatedOrder=51,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="200g", servingSizeText="30g (Khoảng 7-8 nửa hạt)", servingsPerContainer=6, perServingMacros=MacroNutrients(energyKcal=195, proteinGrams=4.5, carbohydratesGrams=4.0, totalFatGrams=19.5, saturatedFatGrams=1.8, dietaryFiberGrams=2.0, sugarsGrams=0.8, sodiumMg=2), per100gMacros=MacroNutrients(energyKcal=650, proteinGrams=15.0, carbohydratesGrams=13.3, totalFatGrams=65.0, saturatedFatGrams=6.0, dietaryFiberGrams=6.6, sugarsGrams=2.6, sodiumMg=6), ingredientsText="100% Nhân hạt óc chó Chile nguyên nửa tự nhiên.", allergenStatus=AllergenStatus.containsAllergens, allergenList=["tree_nuts"], storageInstructions="Nên bảo quản ngăn mát tủ lạnh để giữ độ tươi ngon không bị oxy hóa dầu.", shelfLifeText="6 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_16",
            title="Nước Dừa Xiêm Bến Tre Nguyên Chất 330ml",
            subtitle="Nước dừa tươi đóng hộp tiệt trùng bù khoáng kali tự nhiên",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks", "col_gym_bag"],
            productType="food",
            subcategoryId="Đồ uống",
            badge="Popular",
            description="Nước dừa tươi thu hoạch từ những quả dừa xiêm xanh Bến Tre trứ danh, tiệt trùng UHT và đóng hộp Tetra Pak vô trùng trong vòng 24 giờ. Giàu khoáng chất kali và natri bù điện giải.",
            editorialNote="Nước uống bù dịch tự nhiên tốt nhất từ thiên nhiên, ngọt thanh không hương liệu nhân tạo.",
            priceVnd=25000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "330 ml", "Thành phần": "100% Nước dừa tươi nguyên chất", "Bảo quản": "Nơi mát mẻ, uống ngon hơn khi ướp lạnh"},
            shopeeUrl="https://shopee.vn/product/saman-coconut-water-16",
            curatedOrder=52,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="330ml", servingSizeText="1 hộp (330ml)", servingsPerContainer=1, perServingMacros=MacroNutrients(energyKcal=65, proteinGrams=0.5, carbohydratesGrams=15.0, totalFatGrams=0.0, saturatedFatGrams=0.0, dietaryFiberGrams=0.0, sugarsGrams=12.0, sodiumMg=80), per100gMacros=MacroNutrients(energyKcal=20, proteinGrams=0.2, carbohydratesGrams=4.5, totalFatGrams=0.0, saturatedFatGrams=0.0, dietaryFiberGrams=0.0, sugarsGrams=3.6, sodiumMg=24), ingredientsText="100% Nước dừa tươi nguyên chất, chất chống oxy hóa (Vitamin C).", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Nơi thoáng mát. Sau khi mở nắp giữ lạnh dưới 5°C và dùng trong 24 giờ.", shelfLifeText="12 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_17",
            title="Trà Xanh Matcha Cold Brew Hữu Cơ 300ml",
            subtitle="Trà xanh ủ lạnh 12 giờ chiết xuất polyphenol chống oxy hóa",
            categoryId="cat_food_beverage",
            collectionIds=["col_quick_breakfast"],
            productType="food",
            subcategoryId="Đồ uống",
            badge=None,
            description="Bột trà xanh hữu cơ Shizuoka ủ lạnh chậm 12 tiếng loại bỏ hoàn toàn vị đắng chát gắt, giữ trọn hàm lượng chất chống oxy hóa EGCG và axit amin L-Theanine giúp tỉnh táo tập trung.",
            editorialNote="Cung cấp caffeine tự nhiên giải phóng êm ái, không gây cảm giác hồi hộp tim đập nhanh như cà phê đen.",
            priceVnd=42000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "300 ml", "Ủ lạnh": "Cold Brew 12 tiếng", "Caffeine": "Khoảng 45mg / chai"},
            shopeeUrl="https://shopee.vn/product/saman-matcha-coldbrew-17",
            curatedOrder=53,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="300ml", servingSizeText="1 chai (300ml)", servingsPerContainer=1, perServingMacros=MacroNutrients(energyKcal=15, proteinGrams=0.8, carbohydratesGrams=2.5, totalFatGrams=0.0, saturatedFatGrams=0.0, dietaryFiberGrams=0.5, sugarsGrams=0.0, sodiumMg=10), per100gMacros=MacroNutrients(energyKcal=5, proteinGrams=0.3, carbohydratesGrams=0.8, totalFatGrams=0.0, saturatedFatGrams=0.0, dietaryFiberGrams=0.2, sugarsGrams=0.0, sodiumMg=3), ingredientsText="Nước tinh khiết ủ lạnh, bột trà xanh hữu cơ matcha Nhật Bản (1.5%), chất điều chỉnh độ acid (Vitamin C).", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Luôn giữ lạnh 2-6°C để giữ trọn vẹn hương vị tươi mới.", shelfLifeText="30 ngày kể từ ngày đóng chai"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_18",
            title="Nước Ép Củ Dền Táo Hỗ Trợ Sức Bền 250ml",
            subtitle="Nước ép lạnh giàu hợp chất nitrat tự nhiên tăng lưu lượng oxy",
            categoryId="cat_food_beverage",
            collectionIds=["col_quick_breakfast", "col_gym_bag"],
            productType="food",
            subcategoryId="Đồ uống",
            badge=None,
            description="Củ dền đỏ Đà Lạt ép lạnh công nghệ HPP giữ tươi nguyên vẹn enzym, kết hợp táo xanh cân bằng vị ngọt dịu. Hàm lượng nitrat tự nhiên hỗ trợ giãn mạch và cải thiện sức bền tim mạch.",
            editorialNote="Khuyên dùng trước buổi tập chạy đường dài hoặc buổi tập thể lực nặng 90 phút để tối ưu hô hấp tế bào.",
            priceVnd=48000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "250 ml", "Công nghệ ép": "Ép thủy lực lạnh HPP không sinh nhiệt", "Thành phần": "70% Củ dền đỏ, 30% Táo xanh"},
            shopeeUrl="https://shopee.vn/product/saman-beetroot-juice-18",
            curatedOrder=54,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="250ml", servingSizeText="1 chai (250ml)", servingsPerContainer=1, perServingMacros=MacroNutrients(energyKcal=95, proteinGrams=1.5, carbohydratesGrams=22.0, totalFatGrams=0.2, saturatedFatGrams=0.0, dietaryFiberGrams=1.2, sugarsGrams=18.0, sodiumMg=65), per100gMacros=MacroNutrients(energyKcal=38, proteinGrams=0.6, carbohydratesGrams=8.8, totalFatGrams=0.1, saturatedFatGrams=0.0, dietaryFiberGrams=0.5, sugarsGrams=7.2, sodiumMg=26), ingredientsText="Củ dền đỏ tươi ép lạnh (70%), nước ép táo xanh (28%), nước cốt gừng tươi (2%).", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Giữ lạnh 2-4°C, lắc đều trước khi uống.", shelfLifeText="21 ngày kể từ ngày ép"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_19",
            title="Trà Kombucha Lên Men Gừng Sả Tự Nhiên 330ml",
            subtitle="Trà lên men sống Scoby bổ sung men vi sinh probiotic đường ruột",
            categoryId="cat_food_beverage",
            collectionIds=["col_portable_snacks"],
            productType="food",
            subcategoryId="Đồ uống",
            badge=None,
            description="Kombucha lên men truyền thống 21 ngày từ trà đen Thái Nguyên hữu cơ và con giống Scoby sống. Hương vị chua ngọt thanh sảng khoái với gừng tươi ấm và sả cây thơm mát.",
            editorialNote="Bổ sung hàng tỷ lợi khuẩn probiotic sống và axit hữu cơ hỗ trợ tiêu hóa thức ăn nhiều đạm dễ dàng hơn.",
            priceVnd=45000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "330 ml", "Lên men": "21 ngày men Scoby tự nhiên", "Ga tự nhiên": "Sủi bọt nhẹ tự nhiên không bơm CO2"},
            shopeeUrl="https://shopee.vn/product/saman-kombucha-19",
            curatedOrder=55,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="330ml", servingSizeText="1 chai (330ml)", servingsPerContainer=1, perServingMacros=MacroNutrients(energyKcal=35, proteinGrams=0.2, carbohydratesGrams=8.0, totalFatGrams=0.0, saturatedFatGrams=0.0, dietaryFiberGrams=0.0, sugarsGrams=6.5, sodiumMg=15), per100gMacros=MacroNutrients(energyKcal=11, proteinGrams=0.1, carbohydratesGrams=2.4, totalFatGrams=0.0, saturatedFatGrams=0.0, dietaryFiberGrams=0.0, sugarsGrams=2.0, sodiumMg=5), ingredientsText="Nước tinh khiết, trà đen hữu cơ, men sống Kombucha Scoby, nước ép gừng tươi (2%), sả (1%), đường mía thô lên men.", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Luôn bảo quản lạnh 2-6°C để ức chế men tiếp tục lên men tạo gas mạnh.", shelfLifeText="4 tháng kể từ ngày đóng chai"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_20",
            title="Nước Khoáng Kiềm Thiên Nhiên pH 8.5 500ml",
            subtitle="Nước ngầm giàu khoáng chất canxi magie trung hòa axit cơ",
            categoryId="cat_food_beverage",
            collectionIds=["col_gym_bag"],
            productType="food",
            subcategoryId="Đồ uống",
            badge=None,
            description="Nước khoáng khai thác tại nguồn ngầm tự nhiên sâu 450m với độ kiềm tự nhiên pH 8.5 ổn định. Chứa hàm lượng vi khoáng canxi, magie, kali tự nhiên giúp phục hồi độ ẩm tế bào.",
            editorialNote="Hỗ trợ trung hòa axit lactic tích tụ trong cơ bắp trong các hiệp tập nặng cường độ cao.",
            priceVnd=15000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "500 ml", "Độ kiềm": "pH 8.5 tự nhiên tại nguồn", "Tổng chất rắn hòa tan TDS": "350 mg/l"},
            shopeeUrl="https://shopee.vn/product/saman-alkaline-water-20",
            curatedOrder=56,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="500ml", servingSizeText="1 chai (500ml)", servingsPerContainer=1, perServingMacros=MacroNutrients(energyKcal=0, proteinGrams=0.0, carbohydratesGrams=0.0, totalFatGrams=0.0, saturatedFatGrams=0.0, dietaryFiberGrams=0.0, sugarsGrams=0.0, sodiumMg=18), per100gMacros=MacroNutrients(energyKcal=0, proteinGrams=0.0, carbohydratesGrams=0.0, totalFatGrams=0.0, saturatedFatGrams=0.0, dietaryFiberGrams=0.0, sugarsGrams=0.0, sodiumMg=3), ingredientsText="100% Nước khoáng kiềm thiên nhiên khai thác tại nguồn ngầm.", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Nơi khô ráo sạch sẽ, tránh ánh nắng trực tiếp.", shelfLifeText="24 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_21",
            title="Yến Mạch Cán Dẹt Rolled Oats Hữu Cơ 500g",
            subtitle="Yến mạch nguyên hạt cán dẹt nhập khẩu Úc giàu chất xơ",
            categoryId="cat_food_beverage",
            collectionIds=["col_meal_prep"],
            productType="food",
            subcategoryId="Nguyên liệu chuẩn bị bữa ăn",
            badge="Curated",
            description="Yến mạch nguyên hạt cán dẹt nhập khẩu Úc giữ trọn lớp mầm và cám dinh dưỡng ngoài cùng. Độ dẻo thơm tự nhiên khi nấu cháo dinh dưỡng hoặc làm nguyên liệu nướng bánh granola.",
            editorialNote="Nền tảng tinh bột sạch không thể thiếu trong thực đơn chuẩn bị đồ ăn Meal Prep cho cả tuần.",
            priceVnd=82000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "500g", "Xuất xứ": "Úc (Australia)", "Chứng nhận": "Organic Australian Certified"},
            shopeeUrl="https://shopee.vn/product/saman-rolled-oats-21",
            curatedOrder=57,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="500g", servingSizeText="50g", servingsPerContainer=10, perServingMacros=MacroNutrients(energyKcal=185, proteinGrams=6.8, carbohydratesGrams=32.0, totalFatGrams=3.2, saturatedFatGrams=0.5, dietaryFiberGrams=5.2, sugarsGrams=0.6, sodiumMg=3), per100gMacros=MacroNutrients(energyKcal=370, proteinGrams=13.6, carbohydratesGrams=64.0, totalFatGrams=6.4, saturatedFatGrams=1.0, dietaryFiberGrams=10.4, sugarsGrams=1.2, sodiumMg=6), ingredientsText="100% Yến mạch nguyên hạt cán dẹt hữu cơ.", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Nơi khô thoáng, đậy kín miệng túi zip sau khi lấy bột.", shelfLifeText="12 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_22",
            title="Hạt Diêm Mạch Quinoa Trắng Dinh Dưỡng 500g",
            subtitle="Quinoa trắng hạt mẩy chứa đủ 9 axit amin thiết yếu",
            categoryId="cat_food_beverage",
            collectionIds=["col_meal_prep"],
            productType="food",
            subcategoryId="Nguyên liệu chuẩn bị bữa ăn",
            badge=None,
            description="Hạt diêm mạch trắng Hoàng Gia nhập khẩu Peru đã rửa sạch lớp vỏ đắng saponin tự nhiên. Là một trong số ít thực vật chứa đủ 9 axit amin thiết yếu thay thế cơm trắng tuyệt vời.",
            editorialNote="Không chứa gluten, chỉ số đường huyết cực thấp, giữ nguyên độ tơi xốp khi bảo quản trong hộp meal prep ngăn mát.",
            priceVnd=135000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "500g", "Xuất xứ": "Peru", "Chế biến": "Nấu chín với tỷ lệ 1 quinoa : 2 nước"},
            shopeeUrl="https://shopee.vn/product/saman-quinoa-22",
            curatedOrder=58,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="500g", servingSizeText="45g hạt khô (Nấu ra khoảng 130g cơm)", servingsPerContainer=11, perServingMacros=MacroNutrients(energyKcal=165, proteinGrams=6.3, carbohydratesGrams=28.5, totalFatGrams=2.7, saturatedFatGrams=0.3, dietaryFiberGrams=3.2, sugarsGrams=0.9, sodiumMg=5), per100gMacros=MacroNutrients(energyKcal=368, proteinGrams=14.1, carbohydratesGrams=64.2, totalFatGrams=6.1, saturatedFatGrams=0.7, dietaryFiberGrams=7.0, sugarsGrams=2.0, sodiumMg=12), ingredientsText="100% Hạt diêm mạch (quinoa) trắng tự nhiên đã tách vỏ đắng.", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Nơi khô ráo thoáng mát, tránh ẩm mốc.", shelfLifeText="18 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_23",
            title="Sốt Mè Rang Không Béo Ít Calo 250ml",
            subtitle="Sốt mè rang bùi thơm loại bỏ dầu béo chỉ 15 kcal mỗi khẩu phần",
            categoryId="cat_food_beverage",
            collectionIds=["col_meal_prep"],
            productType="food",
            subcategoryId="Nguyên liệu chuẩn bị bữa ăn",
            badge=None,
            description="Công thức sốt mè rang chuẩn vị Nhật Bản thơm nức nhưng triệt tiêu hoàn toàn mỡ dầu công nghiệp, chỉ 15 kcal cho mỗi khẩu phần 15ml. Giúp món ức gà luộc nhạt nhẽo trở nên hấp dẫn.",
            editorialNote="Bí quyết giúp người siết cân theo đuổi chế độ ăn ức gà luộc rau củ trong nhiều tháng mà không bị ngán.",
            priceVnd=65000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "250 ml", "Calo": "15 kcal / khẩu phần (15ml)", "Chất béo": "<0.5g / khẩu phần"},
            shopeeUrl="https://shopee.vn/product/saman-sesame-sauce-23",
            curatedOrder=59,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="250ml", servingSizeText="1 muỗng canh (15ml)", servingsPerContainer=16, perServingMacros=MacroNutrients(energyKcal=15, proteinGrams=0.5, carbohydratesGrams=2.8, totalFatGrams=0.3, saturatedFatGrams=0.0, dietaryFiberGrams=0.2, sugarsGrams=1.5, sodiumMg=140), per100gMacros=MacroNutrients(energyKcal=100, proteinGrams=3.3, carbohydratesGrams=18.6, totalFatGrams=2.0, saturatedFatGrams=0.2, dietaryFiberGrams=1.3, sugarsGrams=10.0, sodiumMg=933), ingredientsText="Nước tương lên men, hạt mè trắng rang thơm (12%), giấm gạo tự nhiên, đường ăn kiêng cỏ ngọt Stevia, muối, chất làm dày tự nhiên xanthan gum.", allergenStatus=AllergenStatus.containsAllergens, allergenList=["soy", "sesame"], storageInstructions="Nơi khô mát. Bảo quản ngăn mát tủ lạnh sau khi mở nắp.", shelfLifeText="9 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_fb_24",
            title="Dầu Xịt Oliu Nguyên Chất Extra Virgin 200ml",
            subtitle="Bình xịt nén khí kiểm soát lượng dầu ăn 1 giây mỗi lần xịt",
            categoryId="cat_food_beverage",
            collectionIds=["col_meal_prep"],
            productType="food",
            subcategoryId="Nguyên liệu chuẩn bị bữa ăn",
            badge=None,
            description="Bình xịt cơ học không dùng khí đẩy hóa chất, phun sương lớp màng dầu ô-liu siêu mỏng đều khắp mặt chảo chống dính. Giảm 85% lượng calo dư thừa từ dầu ăn khi chiên áp chảo.",
            editorialNote="Mỗi lần nhấn xịt 1 giây chỉ tương đương 10 kcal thay vì 1 muỗng dầu truyền thống tới 120 kcal.",
            priceVnd=145000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Nutrition Pantry",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/overnight_oats_chocolate.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "200 ml", "Loại dầu": "100% Extra Virgin Olive Oil ép lạnh", "Công nghệ xịt": "Túi van Bag-on-Valve không chất đẩy"},
            shopeeUrl="https://shopee.vn/product/saman-olive-spray-24",
            curatedOrder=60,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=FoodAttributes(netWeightText="200ml", servingSizeText="1 lần xịt (khoảng 1.2ml)", servingsPerContainer=160, perServingMacros=MacroNutrients(energyKcal=10, proteinGrams=0.0, carbohydratesGrams=0.0, totalFatGrams=1.1, saturatedFatGrams=0.1, dietaryFiberGrams=0.0, sugarsGrams=0.0, sodiumMg=0), per100gMacros=MacroNutrients(energyKcal=828, proteinGrams=0.0, carbohydratesGrams=0.0, totalFatGrams=92.0, saturatedFatGrams=13.0, dietaryFiberGrams=0.0, sugarsGrams=0.0, sodiumMg=0), ingredientsText="100% Dầu quả ô-liu nguyên chất Extra Virgin ép nguội.", allergenStatus=AllergenStatus.freeOfDeclaredAllergens, allergenList=[], storageInstructions="Nơi khô ráo tránh nguồn nhiệt trực tiếp hoặc ngọn lửa.", shelfLifeText="18 tháng kể từ ngày sản xuất"),
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_sp_01",
            title="Whey Protein Isolate Sữa Bò Ăn Cỏ 1kg",
            subtitle="Đạm Whey Isolate tinh khiết lọc CFM trên 90% protein",
            categoryId="cat_supplements",
            collectionIds=["col_gym_bag"],
            productType="supplement",
            subcategoryId="Đạm Whey cô lập",
            badge="Editor Pick",
            description="Bột đạm Whey Isolate sản xuất từ nguồn sữa bò ăn cỏ chuẩn New Zealand qua màng siêu lọc vi sinh dòng chảy chéo (CFM). Hàm lượng protein đạt 90%, không chứa chất tạo ngọt nhân tạo hay chất độn phụ gia.",
            editorialNote="Độ tinh khiết cao nhất cho mục tiêu tăng khối cơ nạc mà không nạp dư chất béo và đường lactose gây đau bụng.",
            priceVnd=850000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Pure Supplements",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/whey_isolate_1kg.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng": "1 kg (33 khẩu phần)", "Hàm lượng Protein": "27g Protein / muỗng 30g", "BCAA tự nhiên": "6.2g BCAA"},
            shopeeUrl="https://shopee.vn/product/saman-whey-isolate-01",
            curatedOrder=61,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=SupplementAttributes(form=SupplementForm.powder, netWeightText="1kg (2.2 lbs)", servingSizeText="1 muỗng gạt (30g)", servingsPerContainer=33, activeIngredients=[ActiveIngredient(name="Cross-Flow Microfiltered Whey Protein Isolate", amountPerServing="27g"), ActiveIngredient(name="BCAA tự nhiên", amountPerServing="6.2g"), ActiveIngredient(name="Glutamine & Precursors", amountPerServing="4.8g")], suggestedUse="Pha 1 muỗng (30g) với 250ml nước lạnh hoặc sữa hạnh nhân. Dùng ngay sau buổi tập 20 phút hoặc giữa các bữa ăn chính.", safetyAdvisory="Thực phẩm bổ sung không thay thế chế độ ăn uống đa dạng. Không dùng cho phụ nữ có thai khi chưa tham vấn bác sĩ.", isProhibitedForMinors=True),
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_sp_02",
            title="Hydrolyzed Whey Protein Thủy Phân Nhanh 900g",
            subtitle="Đạm Whey thủy phân chuỗi peptide thẩm thấu siêu tốc",
            categoryId="cat_supplements",
            collectionIds=["col_gym_bag"],
            productType="supplement",
            subcategoryId="Đạm Whey thủy phân",
            badge=None,
            description="Đạm Whey thủy phân bằng enzym tự nhiên bẻ gãy các chuỗi protein dài thành các phân tử peptide nhỏ. Khả năng thẩm thấu trực tiếp vào máu chỉ sau 15-20 phút, loại bỏ 100% cảm giác đầy bụng khó tiêu.",
            editorialNote="Sự lựa chọn số một cho vận động viên chuyên nghiệp cần phục hồi cơ bắp thần tốc ngay trong khung giờ vàng sau buổi tập.",
            priceVnd=980000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Pure Supplements",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/whey_isolate_1kg.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng": "900g (30 khẩu phần)", "Hàm lượng Protein": "28g Hydrolyzed Whey / muỗng", "Lactose": "0g (Hoàn toàn không lactose)"},
            shopeeUrl="https://shopee.vn/product/saman-hydro-whey-02",
            curatedOrder=62,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=SupplementAttributes(form=SupplementForm.powder, netWeightText="900g", servingSizeText="1 muỗng (30g)", servingsPerContainer=30, activeIngredients=[ActiveIngredient(name="Hydrolyzed Whey Protein Peptides", amountPerServing="28g"), ActiveIngredient(name="Essential Amino Acids (EAAs)", amountPerServing="13.5g")], suggestedUse="Pha 1 muỗng với 200-250ml nước lọc nguội hoặc lạnh. Lắc đều 10 giây và dùng ngay sau khi kết thúc buổi tập nặng.", safetyAdvisory="Không sử dụng như nguồn dinh dưỡng duy nhất. Bảo quản nơi khô ráo, đậy kín nắp sau khi dùng.", isProhibitedForMinors=True),
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_sp_03",
            title="Đạm Thực Vật Hữu Cơ Đậu Hà Lan & Gạo Lứt 900g",
            subtitle="Plant protein thuần chay hữu cơ đầy đủ axit amin thiết yếu",
            categoryId="cat_supplements",
            collectionIds=["col_meal_prep"],
            productType="supplement",
            subcategoryId="Đạm thực vật thuần chay",
            badge=None,
            description="Sự kết hợp hoàn hảo giữa đạm đậu Hà Lan vàng và đạm mầm gạo lứt lên men tạo nên bảng axit amin hoàn chỉnh tương đương đạm động vật. Không lactose, không gluten, không gây mụn lưng.",
            editorialNote="Giải pháp bổ sung đạm thuần chay cao cấp không gây đầy hơi, dịu nhẹ êm ái cho toàn bộ hệ tiêu hóa.",
            priceVnd=720000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Pure Supplements",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/whey_isolate_1kg.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng": "900g (30 khẩu phần)", "Protein thực vật": "24g / muỗng 30g", "Chứng nhận": "100% Vegan & Non-GMO"},
            shopeeUrl="https://shopee.vn/product/saman-plant-protein-03",
            curatedOrder=63,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=SupplementAttributes(form=SupplementForm.powder, netWeightText="900g", servingSizeText="1 muỗng (30g)", servingsPerContainer=30, activeIngredients=[ActiveIngredient(name="Organic Yellow Pea Protein Isolate", amountPerServing="15g"), ActiveIngredient(name="Organic Sprouted Brown Rice Protein", amountPerServing="9g"), ActiveIngredient(name="Men vi sinh DigeZyme", amountPerServing="100mg")], suggestedUse="Pha 1 muỗng với 300ml nước lọc hoặc sữa yến mạch. Khuấy hoặc lắc đều trong bình shaker.", safetyAdvisory="Thực phẩm bổ sung hỗ trợ sức khỏe. Tránh xa tầm tay trẻ nhỏ.", isProhibitedForMinors=False),
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_sp_04",
            title="Micellar Casein Đạm Tiêu Hóa Chậm Ban Đêm 900g",
            subtitle="Đạm Casein micelle nguyên bản giải phóng axit amin 7-8 giờ",
            categoryId="cat_supplements",
            collectionIds=["col_quick_breakfast"],
            productType="supplement",
            subcategoryId="Đạm Casein ban đêm",
            badge=None,
            description="Cấu trúc hạt micelle tự nhiên kết tủa đông nhẹ trong môi trường dạ dày giúp giải phóng dòng axit amin liên tục suốt 7-8 tiếng khi ngủ. Ngăn chặn triệt để quá trình dị hóa teo cơ ban đêm.",
            editorialNote="Thức uống hoàn hảo trước khi đi ngủ 30 phút để cơ thể luôn được nuôi dưỡng cơ bắp ngay trong giấc ngủ say.",
            priceVnd=820000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Pure Supplements",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/whey_isolate_1kg.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng": "900g (28 khẩu phần)", "Hàm lượng Protein": "25g Micellar Casein / muỗng 32g", "Thời gian hấp thu": "7 - 8 giờ liên tục"},
            shopeeUrl="https://shopee.vn/product/saman-casein-04",
            curatedOrder=64,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=SupplementAttributes(form=SupplementForm.powder, netWeightText="900g", servingSizeText="1 muỗng (32g)", servingsPerContainer=28, activeIngredients=[ActiveIngredient(name="100% Micellar Casein Protein", amountPerServing="25g"), ActiveIngredient(name="Canxi tự nhiên từ sữa", amountPerServing="650mg")], suggestedUse="Pha 1 muỗng với 250-300ml nước hoặc sữa tươi. Dùng trước khi đi ngủ buổi tối 30-45 phút.", safetyAdvisory="Không dùng khi dị ứng với protein từ sữa bò. Không thay thế bữa ăn chính.", isProhibitedForMinors=True),
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_sp_05",
            title="Creatine Monohydrate Vi Hạt Micronized 300g",
            subtitle="Bột Creatine tinh khiết 200 mesh hòa tan nhanh tăng sức mạnh",
            categoryId="cat_supplements",
            collectionIds=["col_gym_bag"],
            productType="supplement",
            subcategoryId="Creatine đơn chất",
            badge="Curated",
            description="Bột Creatine Monohydrate kích thước hạt siêu mịn 200 mesh hòa tan hoàn toàn không để lại cảm giác lạo xạo đáy ly. Gia tăng lượng phosphocreatine tế bào cơ giúp bùng nổ sức mạnh nâng tạ.",
            editorialNote="Thực phẩm bổ sung được nghiên cứu lâm sàng nhiều nhất thế giới chứng minh khả năng tăng thể tích khối cơ và lực đẩy tạ tối đa.",
            priceVnd=350000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Pure Supplements",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/whey_isolate_1kg.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng tịnh": "300g (60 lần dùng)", "Kích cỡ hạt": "Micronized 200 Mesh siêu mịn", "Liều dùng": "5g mỗi ngày"},
            shopeeUrl="https://shopee.vn/product/saman-creatine-powder-05",
            curatedOrder=65,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=SupplementAttributes(form=SupplementForm.powder, netWeightText="300g", servingSizeText="1 muỗng gạt (5g)", servingsPerContainer=60, activeIngredients=[ActiveIngredient(name="Micronized Creatine Monohydrate 200 Mesh", amountPerServing="5000mg")], suggestedUse="Pha 1 muỗng (5g) với 200ml nước lọc, nước trái cây hoặc chung với whey protein. Uống hàng ngày duy trì.", safetyAdvisory="Uống đủ 2.5 - 3 lít nước mỗi ngày khi sử dụng Creatine. Không dùng cho người suy giảm chức năng thận.", isProhibitedForMinors=True),
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_sp_06",
            title="Creatine Monohydrate 750mg Hộp 120 Viên Nang",
            subtitle="Viên nang Creatine tiện lợi mang theo không cần bình lắc",
            categoryId="cat_supplements",
            collectionIds=["col_gym_bag"],
            productType="supplement",
            subcategoryId="Creatine cao cấp dạng viên",
            badge=None,
            description="Creatine Monohydrate chuẩn hóa đóng trong vỏ nang thực vật tiện lợi, giúp chia liều chuẩn xác 3000mg mỗi lần uống mà không phải mang theo thìa đong hay bình pha.",
            editorialNote="Định dạng viên nang lý tưởng cho người hay đi công tác, du lịch hoặc tập luyện tại phòng gym văn phòng.",
            priceVnd=390000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Pure Supplements",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/whey_isolate_1kg.jpg",
            galleryImageUrls=[],
            specifications={"Quy cách": "Hộp 120 viên nang", "Hàm lượng": "750mg Creatine / viên (Khẩu phần 4 viên = 3000mg)", "Vỏ nang": "Plant Cellulose thuần chay"},
            shopeeUrl="https://shopee.vn/product/saman-creatine-caps-06",
            curatedOrder=66,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=SupplementAttributes(form=SupplementForm.capsule, netWeightText="120 viên nang", servingSizeText="4 viên nang (3000mg)", servingsPerContainer=30, activeIngredients=[ActiveIngredient(name="Pure Creatine Monohydrate", amountPerServing="3000mg")], suggestedUse="Uống 4 viên nang với 1 ly nước lớn (300ml) trước hoặc sau buổi tập 30 phút.", safetyAdvisory="Uống nhiều nước trong ngày. Tham khảo ý kiến chuyên gia nếu đang điều trị bệnh lý.", isProhibitedForMinors=True),
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_sp_07",
            title="Hộp 20 Gói Bột Bù Điện Giải Thể Thao Không Đường",
            subtitle="Gói hòa tan tỷ lệ natri kali magie vàng bù khoáng nhanh",
            categoryId="cat_supplements",
            collectionIds=["col_gym_bag", "col_portable_snacks"],
            productType="supplement",
            subcategoryId="Bột điện giải gói hòa tan",
            badge=None,
            description="Công thức điện giải khoa học với tỷ lệ tối ưu 500mg Natri, 200mg Kali, 60mg Magie giúp chống chuột rút cơ và mất nước khi đổ mồ hôi nhiều. Hoàn toàn không đường, vị chanh tươi mát.",
            editorialNote="Gói stick nhỏ gọn dễ xé, đổ trực tiếp vào bình nước thể thao lắc nhẹ tan tức thì.",
            priceVnd=260000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Pure Supplements",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/whey_isolate_1kg.jpg",
            galleryImageUrls=[],
            specifications={"Quy cách": "Hộp 20 gói x 5g", "Đường": "0g Đường (Không calo)", "Khoáng chất": "500mg Natri, 200mg Kali, 60mg Magie"},
            shopeeUrl="https://shopee.vn/product/saman-electrolyte-sticks-07",
            curatedOrder=67,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=SupplementAttributes(form=SupplementForm.powder, netWeightText="Hộp 20 gói (100g)", servingSizeText="1 gói (5g)", servingsPerContainer=20, activeIngredients=[ActiveIngredient(name="Natri (từ Muối hồng Himalaya & Natri Clorid)", amountPerServing="500mg"), ActiveIngredient(name="Kali (từ Kali Clorid)", amountPerServing="200mg"), ActiveIngredient(name="Magie (từ Magie Malate)", amountPerServing="60mg")], suggestedUse="Pha 1 gói (5g) với 500-700ml nước lạnh. Uống từng ngụm nhỏ trong và sau khi tập luyện ra mồ hôi.", safetyAdvisory="Người có tiền sử huyết áp cao cần tham khảo ý kiến bác sĩ về hàm lượng natri.", isProhibitedForMinors=False),
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_sp_08",
            title="Tuýp 20 Viên Sủi Điện Giải Bù Khoáng Nhanh",
            subtitle="Viên sủi tan dưới 60 giây bổ sung kẽm và Vitamin C sau tập",
            categoryId="cat_supplements",
            collectionIds=["col_gym_bag"],
            productType="supplement",
            subcategoryId="Viên sủi điện giải",
            badge=None,
            description="Viên sủi hòa tan nhanh trong nước lạnh tạo thức uống sủi bọt nhẹ vị cam đào thanh mát. Bổ sung các chất điện giải thiết yếu kèm 5mg Kẽm và 60mg Vitamin C tăng cường hệ miễn dịch.",
            editorialNote="Tuýp nhựa nắp lò xo kín khí chống ẩm, tiện lợi mang theo túi gym không lo bị vỡ hay chảy nước.",
            priceVnd=145000,
            priceUpdatedAt=datetime(2026, 10, 31, tzinfo=timezone.utc),
            sellerName="Saman Pure Supplements",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/whey_isolate_1kg.jpg",
            galleryImageUrls=[],
            specifications={"Quy cách": "Tuýp 20 viên sủi", "Thời gian tan": "<60 giây trong nước mát", "Bổ sung": "Điện giải, Kẽm Citrate, Vitamin C"},
            shopeeUrl="https://shopee.vn/product/saman-hydration-tabs-08",
            curatedOrder=68,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=SupplementAttributes(form=SupplementForm.effervescentTablet, netWeightText="Tuýp 20 viên (80g)", servingSizeText="1 viên sủi (4g)", servingsPerContainer=20, activeIngredients=[ActiveIngredient(name="Natri Bicarbonat & Clorid", amountPerServing="300mg"), ActiveIngredient(name="Kali Bicarbonat", amountPerServing="150mg"), ActiveIngredient(name="Magie Carbonat", amountPerServing="40mg"), ActiveIngredient(name="Vitamin C (Axit Ascorbic)", amountPerServing="60mg"), ActiveIngredient(name="Kẽm (từ Kẽm Citrate)", amountPerServing="5mg")], suggestedUse="Thả 1 viên vào 400ml nước lạnh, chờ viên sủi tan hết hoàn toàn rồi uống.", safetyAdvisory="Không nuốt trực tiếp viên sủi. Đậy chặt nắp tuýp sau mỗi lần lấy viên.", isProhibitedForMinors=False),
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_rc_01",
            title="High-Density Foam Roller 45cm Bọt Xốp Mật Độ Cao",
            subtitle="Con lăn EVA nguyên khối 45cm giải tỏa điểm đau cơ",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_home_starter"],
            productType="recovery",
            subcategoryId="Con lăn bọt xốp",
            badge="Signature",
            description="Bọt xốp EVA đúc đặc mật độ cao chiều dài 45cm không xẹp lún sau thời gian dài sử dụng. Giúp tự giải phóng màng cơ myofascial release (SMR) vùng lưng, cơ đùi và bắp chân.",
            editorialNote="Bề mặt trơn mịn cho áp lực đều đặn, phù hợp cho cả người mới bắt đầu làm quen với phương pháp giãn cơ con lăn.",
            priceVnd=260000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=roller_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/foam_roller_eva_45cm.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Bọt xốp EVA mật độ cao", "Chiều dài": "45 cm", "Đường kính": "14 cm", "Tải trọng": "200 kg không lún"},
            shopeeUrl="https://shopee.vn/product/saman-foam-roller-01",
            curatedOrder=69,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Bọt xốp EVA đặc nguyên khối", lengthCm=45.0, widthCm=14.0, maxLoadCapacityKg=200.0, usageEnvironment="Tự giãn cơ SMR, lưng, đùi, hông"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_rc_03",
            title="Bóng Massage Lacrosse Đơn Cao Su Đúc Đặc",
            subtitle="Bóng cao su đặc 6.3cm tác động chính xác điểm đau sâu",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_home_starter", "col_gym_bag"],
            productType="recovery",
            subcategoryId="Bóng massage đơn điểm",
            badge=None,
            description="Cao su tự nhiên đúc đặc 100% độ bám dính cao chống trượt trên sàn. Đường kính 6.3cm tiêu chuẩn tác động trực tiếp vào các điểm cơ co thắt sâu như cơ hình lê, cơ ngực bé và gan bàn chân.",
            editorialNote="Dụng cụ nhỏ gọn nhưng giải quyết dứt điểm các cơn đau nhói bả vai và đau thắt lưng do ngồi nhiều.",
            priceVnd=65000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/foam_roller_eva_45cm.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "100% Cao su đúc đặc tự nhiên", "Đường kính": "6.3 cm", "Trọng lượng": "150g"},
            shopeeUrl="https://shopee.vn/product/saman-lacrosse-ball-03",
            curatedOrder=70,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Cao su đúc đặc tự nhiên 100%", lengthCm=6.3, widthCm=6.3, weightKg=0.15, usageEnvironment="Trigger point cơ ngực, cơ hình lê, lòng bàn chân"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_rc_04",
            title="Bóng Massage Đôi Peanut Silicone Giải Tỏa Cổ Lưng",
            subtitle="Bóng đôi hình hạt lạc silicone ôm sát hai dải cơ cột sống",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_home_starter"],
            productType="recovery",
            subcategoryId="Bóng massage đôi cột sống",
            badge=None,
            description="Thiết kế hõm giữa cong né xương sống, ôm sát hai dải cơ dựng đứng cột sống và cổ gáy. Silicone y tế kháng khuẩn êm ái hơn bóng cao su truyền thống.",
            editorialNote="Tuyệt vời để giải tỏa cứng cổ gáy do làm việc máy tính nhiều giờ mà không sợ làm tổn thương gai đốt sống.",
            priceVnd=120000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/foam_roller_eva_45cm.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Silicone đúc đặc y tế", "Kích thước": "Dài 13cm x Đường kính 6.5cm", "Trọng lượng": "300g"},
            shopeeUrl="https://shopee.vn/product/saman-peanut-ball-04",
            curatedOrder=71,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Silicone y tế đúc đặc", lengthCm=13.0, widthCm=6.5, weightKg=0.3, usageEnvironment="Massage cơ dựng cột sống lưng, cổ vai gáy"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_rc_05",
            title="Súng Massage Cầm Tay Mini 4 Đầu Chuyên Sâu",
            subtitle="Bộ gõ cơ mini lực đấm 3200 vòng/phút pin 2500mAh gọn nhẹ 450g",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_gym_bag"],
            productType="recovery",
            subcategoryId="Thiết bị điện tử phục hồi",
            badge="Popular",
            description="Động cơ không chổi than 4 cấp tốc độ tạo xung lực đấm sâu 8mm giải phóng axit lactic nhanh chóng. Thiết kế nhôm hàng không chỉ nặng 450g bỏ gọn túi tập kèm 4 đầu massage chuyên dụng.",
            editorialNote="Liệu pháp gõ cơ (Percussion Therapy) tiện lợi giúp làm nóng cơ trước tập và giảm đau mỏi cơ bắp tức thì sau hiệp tập nặng.",
            priceVnd=650000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/foam_roller_eva_45cm.jpg",
            galleryImageUrls=[],
            specifications={"Trọng lượng": "450g siêu nhẹ", "Tốc độ": "1800 - 3200 vòng/phút (4 cấp)", "Pin": "Lithium 2500mAh (Dùng 4-6 giờ)", "Phụ kiện": "4 đầu massage tháo lắp"},
            shopeeUrl="https://shopee.vn/product/saman-massage-gun-05",
            curatedOrder=72,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Vỏ hợp kim nhôm hàng không phay CNC", weightKg=0.45, usageEnvironment="Xung lực cơ bắp đùi, vai, bắp chuối sau tập"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_rc_06",
            title="Gậy Lăn Massage Cơ Bắp 9 Con Lăn Bọc Gai",
            subtitle="Trục thép không gỉ 9 bánh răng con lăn xoay độc lập",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_home_starter"],
            productType="recovery",
            subcategoryId="Gậy lăn massage cơ bắp",
            badge=None,
            description="Lõi thép không gỉ cứng cáp với 9 bánh răng độc lập tự lăn theo góc nghiêng cơ thể. Hai tay cầm cao su công thái học giúp người dùng chủ động điều tiết lực ấn sâu theo ý muốn.",
            editorialNote="Cực kỳ hiệu quả khi tự giãn cơ cẳng chân, cơ bắp chuối và cơ tứ đầu đùi khi đang ngồi thư giãn.",
            priceVnd=130000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/foam_roller_eva_45cm.jpg",
            galleryImageUrls=[],
            specifications={"Chiều dài": "44 cm", "Cấu tạo": "Trục thép carbon đặc & 9 con lăn gai ABS", "Tay cầm": "Cao su rãnh ngón tay chống trơn"},
            shopeeUrl="https://shopee.vn/product/saman-roller-stick-06",
            curatedOrder=73,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Trục thép carbon & Nhựa kỹ thuật ABS", lengthCm=44.0, usageEnvironment="Tự lăn cơ bắp chuối, đùi trước, dải chậu chày ITB"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_rc_07",
            title="Đai Chườm Nóng Lạnh Khớp Gối Gel Giữ Nhiệt 2 Chiều",
            subtitle="Túi gel y tế chịu đông và vi sóng dây dán cố định khớp gối",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_home_starter"],
            productType="recovery",
            subcategoryId="Nhiệt trị liệu khớp gối",
            badge=None,
            description="Túi gel y tế cao cấp vẫn giữ được độ mềm dẻo ôm sát khớp gối ngay cả khi làm lạnh ở -18°C hoặc quay nóng trong lò vi sóng. Lớp vải nhung mặt trong ngăn bỏng lạnh da trực tiếp.",
            editorialNote="Liệu pháp nhiệt trị liệu kết hợp lạnh giảm sưng viêm cấp tính và nóng thư giãn dây chằng khớp gối.",
            priceVnd=175000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/foam_roller_eva_45cm.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Gel polymer y tế giữ nhiệt, Vải nhung lót mềm", "Dây dán": "2 đai dán Velcro co giãn ôm sát", "Sử dụng": "Chườm lạnh (ngăn đá) hoặc Chườm nóng (vi sóng)"},
            shopeeUrl="https://shopee.vn/product/saman-knee-ice-wrap-07",
            curatedOrder=74,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Gel polymer y tế chịu nhiệt & Vải nhung lót", usageEnvironment="Giảm sưng đau khớp gối sau chạy và gánh tạ"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_rc_08",
            title="Đôi Tất Nén Y Khoa Hỗ Trợ Tuần Hoàn Bắp Chân",
            subtitle="Liệu pháp nén tĩnh mạch 20-30 mmHg đẩy máu về tim giảm phù nề",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_gym_bag", "col_active_wear"],
            productType="recovery",
            subcategoryId="Liệu pháp nén tĩnh mạch",
            badge=None,
            description="Áp lực nén phân cấp giảm dần từ cổ chân lên bắp chuối 20-30 mmHg hỗ trợ van tĩnh mạch đẩy máu về tim nhanh hơn. Giảm thiểu cảm giác nặng chân, tê mỏi và chuột rút sau buổi tập chân nặng.",
            editorialNote="Được các vận động viên Marathon và thể hình tin dùng mặc phục hồi qua đêm sau ngày tập chân (Leg Day).",
            priceVnd=150000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/foam_roller_eva_45cm.jpg",
            galleryImageUrls=[],
            specifications={"Áp lực nén": "20 - 30 mmHg (Chuẩn y khoa)", "Chất liệu": "75% Nylon, 25% Spandex dệt liền", "Quy cách": "Cặp 2 ống bọc bắp chân"},
            shopeeUrl="https://shopee.vn/product/saman-compression-sleeves-08",
            curatedOrder=75,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="75% Nylon, 25% Spandex dệt liền", usageEnvironment="Phục hồi bắp chân sau tập, chống chuột rút"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_mp_01",
            title="Matte Obsidian Stainless Steel Shaker 750ml",
            subtitle="Bình lắc thép không gỉ 304 hai lớp chân không giữ nhiệt",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_gym_bag"],
            productType="lifestyle_gear",
            subcategoryId="Bình shaker",
            badge="Signature",
            description="Bình lắc shaker vỏ thép không gỉ 304 cách nhiệt chân không giữ lạnh 24 giờ. Bề mặt sơn tĩnh điện đen mờ chống trầy xước, nắp vặn ren kín chống tràn tuyệt đối khi xốc mạnh.",
            editorialNote="Khắc phục triệt để nhược điểm bám mùi whey chua khó chịu của các loại bình nhựa truyền thống.",
            priceVnd=350000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=shaker_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/shaker_steel_750ml.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "750 ml", "Chất liệu thân": "Thép không gỉ 304 (Inox 18/8)", "Giữ lạnh": "24 giờ với đá viên", "Phụ kiện": "Lò xo lắc thép 304"},
            shopeeUrl="https://shopee.vn/product/saman-steel-shaker-01",
            curatedOrder=76,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=LifestyleAttributes(primaryMaterial="Thép không gỉ 304 cao cấp (Inox 18/8)", capacityMl=750, isDishwasherSafe=False, isMicrowaveSafe=False, isBpaFree=True, keepColdHours=24, keepHotHours=12, compartmentCount=1, includedAccessories=["Quả cầu lắc lò xo thép 304"]),
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_mp_03",
            title="Hộp Thủy Tinh Chịu Nhiệt 3 Ngăn Chia Khẩu Phần 1000ml",
            subtitle="Thủy tinh Borosilicate chịu nhiệt 400°C an toàn lò nướng",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_meal_prep"],
            productType="lifestyle_gear",
            subcategoryId="Hộp cơm",
            badge="Curated",
            description="Thủy tinh borosilicate chịu sốc nhiệt từ -20°C đến 400°C an toàn tuyệt đối cho lò nướng và lò vi sóng. Ba ngăn chia vách ngăn kín giúp phân chia đạm, tinh bột và rau củ không bị lẫn nước sốt.",
            editorialNote="Chất liệu thủy tinh sạch bóng không bám mùi thức ăn và dễ dàng rửa sạch lớp dầu mỡ hơn hộp nhựa.",
            priceVnd=165000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=glass_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/meal_prep_glass_container.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "1000 ml", "Chất liệu": "Thủy tinh Borosilicate chịu nhiệt 400°C", "Số ngăn": "3 ngăn chia vách cao", "Nắp": "Nắp nhựa PP khóa 4 cạnh gioăng silicone"},
            shopeeUrl="https://shopee.vn/product/saman-glass-box-03",
            curatedOrder=77,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=LifestyleAttributes(primaryMaterial="Thủy tinh Borosilicate cao cấp chịu sốc nhiệt", capacityMl=1000, isDishwasherSafe=True, isMicrowaveSafe=True, isBpaFree=True, compartmentCount=3, includedAccessories=["Nắp khóa 4 cạnh gioăng silicone tháo rời"]),
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_mp_05",
            title="Cân Tiểu Ly Điện Tử Định Lượng Thực Phẩm Chuẩn 0.1g",
            subtitle="Độ chính xác 0.1g bề mặt kính cường lực chống nước dễ lau",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_meal_prep"],
            productType="lifestyle_gear",
            subcategoryId="Cân thực phẩm",
            badge="Popular",
            description="Cảm biến trọng lực độ nhạy cao đo lường chính xác từng 0.1g từ 1g đến 5000g. Tính năng trừ bì Tare tiện lợi, màn hình LED hiển thị rõ ràng và bề mặt kính cường lực chống nước bám bẩn.",
            editorialNote="Công cụ không thể thiếu của người theo dõi chỉ số Macro và tính calo thâm hụt Deficit chính xác từng gam thực phẩm.",
            priceVnd=220000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/meal_prep_glass_container.jpg",
            galleryImageUrls=[],
            specifications={"Dải đo": "0.1g - 5000g", "Mặt cân": "Kính cường lực chống nước dễ lau", "Đơn vị đo": "g, ml, oz, lb:oz", "Tính năng": "Trừ bì Tare tự động"},
            shopeeUrl="https://shopee.vn/product/saman-food-scale-05",
            curatedOrder=78,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=LifestyleAttributes(primaryMaterial="Kính cường lực & Thân nhựa ABS", isDishwasherSafe=False, isMicrowaveSafe=False, isBpaFree=True, includedAccessories=["2 pin AAA đi kèm"]),
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_mp_06",
            title="Túi Giữ Nhiệt Meal Prep 3 Ngăn Kèm 2 Túi Đá Khô",
            subtitle="Lớp màng nhôm cách nhiệt 8mm giữ ấm lạnh 8 tiếng liên tục",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_meal_prep", "col_gym_bag"],
            productType="lifestyle_gear",
            subcategoryId="Túi giữ nhiệt",
            badge=None,
            description="Màng xốp nhôm EPE cách nhiệt dày 8mm kết hợp 2 túi gel đá khô tái sử dụng giữ thức ăn tươi ngon và lạnh suốt 8 tiếng. Chứa vừa vặn 3 hộp cơm thủy tinh và 2 bình nước thể thao.",
            editorialNote="Giúp bạn tự tin mang theo các bữa ăn chuẩn bị sẵn đi làm và đi tập mà không sợ thức ăn ôi thiu trong thời tiết nắng nóng.",
            priceVnd=320000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/meal_prep_glass_container.jpg",
            galleryImageUrls=[],
            specifications={"Kích thước": "Dài 28cm x Rộng 20cm x Cao 24cm", "Lớp cách nhiệt": "Mút xốp EPE 8mm tráng màng nhôm", "Kèm theo": "2 túi gel đá khô kháng khuẩn"},
            shopeeUrl="https://shopee.vn/product/saman-cooler-bag-06",
            curatedOrder=79,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=LifestyleAttributes(primaryMaterial="Vải Oxford 600D & Màng nhôm cách nhiệt EPE 8mm", isDishwasherSafe=False, isMicrowaveSafe=False, isBpaFree=True, keepColdHours=8, keepHotHours=6, compartmentCount=3, includedAccessories=["2 túi đá khô gel tái sử dụng", "Dây đeo vai đệm mút"]),
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_mp_07",
            title="Bình Nước Thể Thao Đánh Dấu Giờ Uống Nước 2.2L",
            subtitle="Bình nước dung tích lớn 2.2L vạch chia giờ nhắc uống nước",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_gym_bag"],
            productType="lifestyle_gear",
            subcategoryId="Bình nước",
            badge=None,
            description="Dung tích lớn 2.2 lít đáp ứng trọn vẹn nhu cầu bù nước cả ngày chỉ trong một lần châm nước. Vạch chia giờ và câu truyền cảm hứng nhắc nhở uống nước đều đặn, nắp bật silicone chống tràn.",
            editorialNote="Cung cấp đủ lượng nước thiết yếu duy trì thể tích máu và quá trình chuyển hóa năng lượng trong các buổi tập kéo dài.",
            priceVnd=160000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.published,
            heroImageUrl="assets/images/shop/shaker_steel_750ml.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "2.2 Lít (74 oz)", "Chất liệu": "Nhựa PETG cao cấp không chứa BPA", "Thiết kế": "Quai xách đúc liền thân chịu tải"},
            shopeeUrl="https://shopee.vn/product/saman-water-bottle-07",
            curatedOrder=80,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=LifestyleAttributes(primaryMaterial="Nhựa PETG không chứa chất độc hại BPA", capacityMl=2200, isDishwasherSafe=False, isMicrowaveSafe=False, isBpaFree=True, includedAccessories=["Ống hút silicone tháo rời"]),
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_rc_02",
            title="Grid Deep-Tissue Foam Roller Vân Rãnh Ma Trận",
            subtitle="Lõi nhựa ABS chịu tải 250kg bọc vân rãnh mô phỏng ngón tay",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_home_starter"],
            productType="recovery",
            subcategoryId="Con lăn bọt xốp",
            badge=None,
            description="Lõi nhựa ABS chịu lực bọc ngoài lớp vân rãnh ma trận mô phỏng các ngón tay của chuyên viên vật lý trị liệu, nhấn sâu vào các thớ cơ co cứng.",
            editorialNote="Bản ghi lưu trữ dự phòng (retained hidden). Không trùng lặp hiển thị với con lăn EVA prod_rc_01.",
            priceVnd=290000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.hidden,
            heroImageUrl="assets/images/shop/foam_roller_eva_45cm.jpg",
            galleryImageUrls=[],
            specifications={"Chất liệu": "Lõi ABS & Bọc xốp EVA rãnh", "Kích thước": "33cm x 14cm", "Tải trọng": "250 kg"},
            shopeeUrl="https://shopee.vn/product/saman-grid-roller-02",
            curatedOrder=81,
            equipmentAttributes=EquipmentAttributes(primaryMaterial="Lõi nhựa ABS & Bọc xốp EVA rãnh ma trận", lengthCm=33.0, widthCm=14.0, maxLoadCapacityKg=250.0, usageEnvironment="Giãn cơ sâu mô cơ fascia"),
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=None,
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_mp_02",
            title="BPA-Free Tritan Shaker 800ml Quai Xách Thể Thao",
            subtitle="Bình lắc nhựa Tritan trong suốt chống bám mùi",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_gym_bag"],
            productType="lifestyle_gear",
            subcategoryId="Bình shaker",
            badge=None,
            description="Nhựa Tritan trong suốt đạt chuẩn FDA không chứa BPA, có vạch chia ml sắc nét và quả cầu lắc lò xo thép không gỉ.",
            editorialNote="Bản ghi lưu trữ dự phòng (retained hidden). Shaker thép prod_mp_01 là đại diện active chính thức.",
            priceVnd=180000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.hidden,
            heroImageUrl="assets/images/shop/shaker_steel_750ml.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích": "800 ml", "Chất liệu": "Nhựa Tritan Eastman USA", "Kháng khuẩn": "BPA-Free"},
            shopeeUrl="https://shopee.vn/product/saman-tritan-shaker-02",
            curatedOrder=82,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=LifestyleAttributes(primaryMaterial="Nhựa Tritan Eastman USA cao cấp", capacityMl=800, isDishwasherSafe=True, isMicrowaveSafe=False, isBpaFree=True, includedAccessories=["Quả cầu lắc lò xo thép không gỉ"]),
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_mp_04",
            title="Set 5 Hộp Đựng Meal Prep Chống Tràn BPA-Free",
            subtitle="Hộp nhựa nguyên sinh PP số 5 xếp chồng tiết kiệm tủ lạnh",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_meal_prep"],
            productType="lifestyle_gear",
            subcategoryId="Hộp cơm",
            badge=None,
            description="Set 5 hộp nhựa nguyên sinh PP số 5 chuyên dụng cho chuẩn bị đồ ăn cả tuần, nắp khóa kín chống tràn chất lỏng.",
            editorialNote="Bản ghi lưu trữ dự phòng (retained hidden). Hộp thủy tinh borosilicate prod_mp_03 là đại diện active chính thức.",
            priceVnd=210000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.hidden,
            heroImageUrl="assets/images/shop/meal_prep_glass_container.jpg",
            galleryImageUrls=[],
            specifications={"Quy cách": "Set 5 hộp kèm nắp", "Dung tích mỗi hộp": "850 ml", "Chất liệu": "Nhựa PP nguyên sinh số 5"},
            shopeeUrl="https://shopee.vn/product/saman-meal-prep-set-04",
            curatedOrder=83,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=LifestyleAttributes(primaryMaterial="Nhựa nguyên sinh Polypropylene PP số 5", capacityMl=850, isDishwasherSafe=True, isMicrowaveSafe=True, isBpaFree=True, compartmentCount=1, includedAccessories=["5 nắp đậy kín khí"]),
        )
    )
    products.append(
        ShopProductAdminInput(
            id="prod_mp_08",
            title="Phễu Đựng Whey Protein & BCAA Mini Xoáy Nắp Hai Đầu",
            subtitle="Hộp chia sữa bột mini gắn móc khóa tiện lợi châm vào chai",
            categoryId="cat_recovery_lifestyle",
            collectionIds=["col_gym_bag"],
            productType="lifestyle_gear",
            subcategoryId="Phụ kiện bình nước",
            badge=None,
            description="Phễu chứa 1 muỗng đạm whey hoặc BCAA với 2 đầu nắp xoáy, miệng nhỏ rót vừa miệng mọi chai nước suối không bị vương vãi bột.",
            editorialNote="Bản ghi lưu trữ dự phòng (retained hidden). Phụ kiện thứ cấp ngoài 6 công năng cốt lõi.",
            priceVnd=45000,
            priceUpdatedAt=datetime(2026, 10, 18, tzinfo=timezone.utc),
            sellerName="Saman Studio Gear",
            sourceType=ProductSourceType.internalBrand,
            isDemo=True,
            contentProvenance=generic_prov,
            availability=ProductAvailability.available,
            publishState=PublishState.hidden,
            heroImageUrl="assets/images/shop/shaker_steel_750ml.jpg",
            galleryImageUrls=[],
            specifications={"Dung tích chứa": "30g bột (1 serving)", "Cấu tạo": "Nắp xoắn 2 đầu chống rỉ bột", "Móc khóa": "Móc carabiner treo balo"},
            shopeeUrl="https://shopee.vn/product/saman-whey-funnel-08",
            curatedOrder=84,
            equipmentAttributes=None,
            apparelAttributes=None,
            foodAttributes=None,
            supplementAttributes=None,
            lifestyleAttributes=LifestyleAttributes(primaryMaterial="Nhựa PP số 5 an toàn thực phẩm", capacityMl=100, isDishwasherSafe=True, isMicrowaveSafe=False, isBpaFree=True, includedAccessories=["Móc carabiner kim loại"]),
        )
    )
    return products