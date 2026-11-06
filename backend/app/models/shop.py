"""
Pydantic Models and Schemas for Saman Shop Catalog.
Subsystem: Saman Shop — Boutique Catalog & Curation (CP-SHOP-07, SHOP-EXP-02).

Invariants:
- priceVnd is strictly positive integer (VND) or null, never float.
- priceUpdatedAt is ISO 8601 with timezone.
- availability ("available", "unavailable", "discontinued", "unknown") is decoupled from publishState.
- publishState ("published", "hidden", "draft") governs visibility in public read APIs.
- Content provenance records sourceName, rightsBasis, evidenceRef, isMissingProof.
- Typed attributes are optional and strictly typed for equipment, apparel, food, supplement, lifestyle_gear.
"""

from datetime import datetime, timezone
from enum import Enum
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field, field_validator


class ProductSourceType(str, Enum):
    internalBrand = "internalBrand"
    affiliatePartner = "affiliatePartner"
    merchantPartner = "merchantPartner"
    manualCurated = "manualCurated"


class ProductAvailability(str, Enum):
    available = "available"
    unavailable = "unavailable"
    discontinued = "discontinued"
    unknown = "unknown"


class PublishState(str, Enum):
    published = "published"
    hidden = "hidden"
    draft = "draft"


class ContentProvenance(BaseModel):
    sourceName: str = Field(..., min_length=2, max_length=200)
    rightsBasis: str = Field(..., min_length=2, max_length=200)
    evidenceRef: Optional[str] = Field(None, max_length=200)
    isMissingProof: bool = False


# ─────────────────────────────────────────────────────────────────────────────
# Typed Attribute Schemas
# ─────────────────────────────────────────────────────────────────────────────

class EquipmentAttributes(BaseModel):
    primaryMaterial: str = Field(..., min_length=1, max_length=200)
    gripType: Optional[str] = Field(None, max_length=100)
    lengthCm: Optional[float] = None
    widthCm: Optional[float] = None
    thicknessMm: Optional[float] = None
    weightKg: Optional[float] = None
    maxLoadCapacityKg: Optional[float] = None
    resistanceRange: Optional[str] = Field(None, max_length=100)
    usageEnvironment: Optional[str] = Field(None, max_length=200)


class ApparelColorSwatch(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    hexColor: str = Field(..., min_length=4, max_length=9)


class ApparelAttributes(BaseModel):
    fabricComposition: str = Field(..., min_length=1, max_length=200)
    fitType: str = Field(..., min_length=1, max_length=100)
    genderTarget: str = Field(..., min_length=1, max_length=50)
    sizePreviewList: List[str] = Field(default_factory=list)
    colorSwatches: List[ApparelColorSwatch] = Field(default_factory=list)
    technologyTags: List[str] = Field(default_factory=list)
    careInstructions: List[str] = Field(default_factory=list)


class AllergenStatus(str, Enum):
    unknown = "unknown"
    freeOfDeclaredAllergens = "freeOfDeclaredAllergens"
    containsAllergens = "containsAllergens"


class MacroNutrients(BaseModel):
    energyKcal: Optional[int] = None
    proteinGrams: Optional[float] = None
    carbohydratesGrams: Optional[float] = None
    totalFatGrams: Optional[float] = None
    saturatedFatGrams: Optional[float] = None
    dietaryFiberGrams: Optional[float] = None
    sugarsGrams: Optional[float] = None  # Distinguish 0.0 from None
    sodiumMg: Optional[int] = None


class FoodAttributes(BaseModel):
    netWeightText: str = Field(..., min_length=1, max_length=100)
    servingSizeText: str = Field(..., min_length=1, max_length=100)
    servingsPerContainer: Optional[int] = None
    perServingMacros: Optional[MacroNutrients] = None
    per100gMacros: Optional[MacroNutrients] = None
    ingredientsText: str = Field(..., min_length=1, max_length=2000)
    allergenStatus: AllergenStatus = AllergenStatus.unknown
    allergenList: List[str] = Field(default_factory=list)
    storageInstructions: Optional[str] = Field(None, max_length=500)
    shelfLifeText: Optional[str] = Field(None, max_length=200)


class SupplementForm(str, Enum):
    powder = "powder"
    capsule = "capsule"
    tablet = "tablet"
    effervescentTablet = "effervescentTablet"
    liquid = "liquid"


class ActiveIngredient(BaseModel):
    name: str = Field(..., min_length=1, max_length=150)
    amountPerServing: str = Field(..., min_length=1, max_length=50)


class SupplementAttributes(BaseModel):
    form: SupplementForm
    netWeightText: str = Field(..., min_length=1, max_length=100)
    servingSizeText: str = Field(..., min_length=1, max_length=100)
    servingsPerContainer: int
    activeIngredients: List[ActiveIngredient] = Field(default_factory=list)
    suggestedUse: str = Field(..., min_length=1, max_length=1000)
    safetyAdvisory: str = Field(..., min_length=1, max_length=1000)
    isProhibitedForMinors: bool = False


class LifestyleAttributes(BaseModel):
    primaryMaterial: str = Field(..., min_length=1, max_length=200)
    capacityMl: Optional[int] = None
    isDishwasherSafe: bool = False
    isMicrowaveSafe: bool = False
    isBpaFree: bool = True
    keepColdHours: Optional[int] = None
    keepHotHours: Optional[int] = None
    compartmentCount: Optional[int] = None
    includedAccessories: List[str] = Field(default_factory=list)


# ─────────────────────────────────────────────────────────────────────────────
# Taxonomy Schemas
# ─────────────────────────────────────────────────────────────────────────────

class ShopCategoryModel(BaseModel):
    id: str = Field(..., min_length=1, max_length=64)
    name: str = Field(..., min_length=1, max_length=128)
    slug: str = Field(..., min_length=1, max_length=128)
    iconAsset: str = Field(..., min_length=1, max_length=256)
    sortOrder: int = 0


class ShopCollectionModel(BaseModel):
    id: str = Field(..., min_length=1, max_length=64)
    title: str = Field(..., min_length=1, max_length=128)
    subtitle: str = Field(..., min_length=1, max_length=256)
    description: str = Field(..., min_length=1, max_length=1000)
    bannerImageUrl: str = Field(..., min_length=1, max_length=512)
    isFeatured: bool = False
    sortOrder: int = 0


# ─────────────────────────────────────────────────────────────────────────────
# Product Models & Responses
# ─────────────────────────────────────────────────────────────────────────────

class ShopProductResponse(BaseModel):
    id: str
    title: str
    subtitle: str
    categoryId: str
    collectionIds: List[str] = Field(default_factory=list)
    productType: Optional[str] = None
    subcategoryId: Optional[str] = None
    badge: Optional[str] = None
    description: str
    editorialNote: str
    priceVnd: Optional[int] = None
    priceUpdatedAt: Optional[datetime] = None
    sellerName: Optional[str] = None
    sourceType: ProductSourceType
    isDemo: bool = True
    contentProvenance: ContentProvenance
    availability: ProductAvailability
    heroImageUrl: str
    galleryImageUrls: List[str] = Field(default_factory=list)
    specifications: Dict[str, str] = Field(default_factory=dict)
    shopeeUrl: Optional[str] = None
    curatedOrder: int = 0

    # Typed attributes (optional)
    equipmentAttributes: Optional[EquipmentAttributes] = None
    apparelAttributes: Optional[ApparelAttributes] = None
    foodAttributes: Optional[FoodAttributes] = None
    supplementAttributes: Optional[SupplementAttributes] = None
    lifestyleAttributes: Optional[LifestyleAttributes] = None

    @field_validator("priceVnd")
    @classmethod
    def validate_price_vnd(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and v <= 0:
            raise ValueError("priceVnd phải là số nguyên dương lớn hơn 0; không có giá để null.")
        return v


class ShopProductPageResponse(BaseModel):
    items: List[ShopProductResponse]
    nextCursor: Optional[str] = None
    hasMore: bool = False


class ShopBatchLookupRequest(BaseModel):
    ids: List[str] = Field(..., max_length=100)


class ShopBatchLookupResponse(BaseModel):
    items: List[Optional[ShopProductResponse]]


class ShopProductAdminInput(BaseModel):
    id: str = Field(..., min_length=3, max_length=64)
    title: str = Field(..., min_length=2, max_length=200)
    subtitle: str = Field(..., min_length=2, max_length=300)
    categoryId: str = Field(..., min_length=1, max_length=64)
    collectionIds: List[str] = Field(default_factory=list)
    productType: Optional[str] = None
    subcategoryId: Optional[str] = None
    badge: Optional[str] = None
    description: str = Field(..., min_length=5, max_length=5000)
    editorialNote: str = Field(..., min_length=5, max_length=2000)
    priceVnd: Optional[int] = None
    priceUpdatedAt: Optional[datetime] = None
    sellerName: Optional[str] = None
    sourceType: ProductSourceType
    isDemo: bool = True
    contentProvenance: ContentProvenance
    availability: ProductAvailability = ProductAvailability.available
    publishState: PublishState = PublishState.published
    heroImageUrl: str = Field(..., min_length=1, max_length=512)
    galleryImageUrls: List[str] = Field(default_factory=list)
    specifications: Dict[str, str] = Field(default_factory=dict)
    shopeeUrl: Optional[str] = None
    curatedOrder: int = 0

    # Typed attributes (optional)
    equipmentAttributes: Optional[EquipmentAttributes] = None
    apparelAttributes: Optional[ApparelAttributes] = None
    foodAttributes: Optional[FoodAttributes] = None
    supplementAttributes: Optional[SupplementAttributes] = None
    lifestyleAttributes: Optional[LifestyleAttributes] = None

    @field_validator("priceVnd")
    @classmethod
    def validate_price_vnd(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and v <= 0:
            raise ValueError("priceVnd phải là số nguyên dương lớn hơn 0; không có giá để null.")
        return v

    @field_validator("shopeeUrl")
    @classmethod
    def validate_shopee_url(cls, v: Optional[str], values=None) -> Optional[str]:
        if v is not None and v.strip() != "":
            raw = v.strip().lower()
            if not raw.startswith("https://"):
                raise ValueError("URL sản phẩm phải dùng giao thức an toàn https://")
        return v
