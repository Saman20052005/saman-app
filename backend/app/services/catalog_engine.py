"""
Versioned Catalog Engine for Saman Revenue.
Subsystem: Saman Revenue — Membership, Billing & Entitlements (CP-03 / CP-03A).

Responsible for:
- Maintaining immutable, versioned product catalog snapshots.
- Enforcing catalog lifecycle transitions (DRAFT -> PUBLISHED -> RETIRED).
- Serving the active preview catalog matching Flutter UI specs with purchasable=False.

ARCHITECTURAL BOUNDARIES & GUARANTEES:
1. Process Scope: This engine is implemented as an in-memory, thread-safe process singleton.
   Thread safety is guaranteed within a single Python process via threading.Lock.
2. Immutability: Published catalog snapshots cannot be modified in-place; all retrievals
   return isolated deep copies of frozen Pydantic models.
3. Restart Persistence: NOT persisted across process restarts. In-memory snapshots re-seed
   from code baseline upon process startup.
4. Multi-Worker Limitation: State updates (such as draft promotion) in one worker process
   do NOT automatically propagate across multiple independent worker processes (e.g. Uvicorn
   multi-worker or multi-container deployments). Distributed catalog sync and durable database
   persistence are deferred to future checkpoints.
"""

from copy import deepcopy
from datetime import datetime, timezone
from typing import Dict, List, Optional
from threading import Lock

from backend.app.models.revenue import (
    BillingPeriod,
    CatalogStatus,
    CatalogVersion,
    InclusionStatus,
    MatrixFeatureDefinition,
    MembershipTier,
    Plan,
    Price,
)


class CatalogImmutabilityError(Exception):
    """Raised when attempting to modify an already published catalog version."""
    pass


class CatalogNotFoundError(Exception):
    """Raised when a requested catalog version does not exist."""
    pass


# ==============================================================================
# SEED CATALOG: v1.0-preview (Canonical Handover Matching Flutter UI)
# ==============================================================================

def _build_v1_preview_catalog() -> CatalogVersion:
    """
    Constructs the canonical v1.0-preview catalog snapshot.
    All plans and prices match Saman_Membership_Design_Handover_v1.0.md.
    Strictly marked preview_mode=True and purchasable=False.
    """
    # 1. PRICES (Minor units in cents: $10 = 1000 cents, $60 = 6000 cents)
    prices: List[Price] = [
        # Free
        Price(
            price_id="price_free_monthly",
            plan_id="plan_free",
            period=BillingPeriod.MONTHLY,
            amount_cents=0,
            currency="USD",
            yearly_equivalent_monthly_cents=0,
            purchasable=False,
        ),
        Price(
            price_id="price_free_yearly",
            plan_id="plan_free",
            period=BillingPeriod.YEARLY,
            amount_cents=0,
            currency="USD",
            yearly_equivalent_monthly_cents=0,
            purchasable=False,
        ),
        # Plus ($10 / mo, $60 / yr)
        Price(
            price_id="price_plus_monthly_usd_1000",
            plan_id="plan_plus",
            period=BillingPeriod.MONTHLY,
            amount_cents=1000,
            currency="USD",
            yearly_equivalent_monthly_cents=None,
            purchasable=False,
            provider_references={"apple": "saman_plus_monthly", "google": "saman.plus.monthly"},
        ),
        Price(
            price_id="price_plus_yearly_usd_6000",
            plan_id="plan_plus",
            period=BillingPeriod.YEARLY,
            amount_cents=6000,
            currency="USD",
            yearly_equivalent_monthly_cents=500,
            purchasable=False,
            provider_references={"apple": "saman_plus_yearly", "google": "saman.plus.yearly"},
        ),
        # Pro ($15 / mo, $120 / yr)
        Price(
            price_id="price_pro_monthly_usd_1500",
            plan_id="plan_pro",
            period=BillingPeriod.MONTHLY,
            amount_cents=1500,
            currency="USD",
            yearly_equivalent_monthly_cents=None,
            purchasable=False,
            provider_references={"apple": "saman_pro_monthly", "google": "saman.pro.monthly"},
        ),
        Price(
            price_id="price_pro_yearly_usd_12000",
            plan_id="plan_pro",
            period=BillingPeriod.YEARLY,
            amount_cents=12000,
            currency="USD",
            yearly_equivalent_monthly_cents=1000,
            purchasable=False,
            provider_references={"apple": "saman_pro_yearly", "google": "saman.pro.yearly"},
        ),
        # Ultra ($30 / mo, $240 / yr)
        Price(
            price_id="price_ultra_monthly_usd_3000",
            plan_id="plan_ultra",
            period=BillingPeriod.MONTHLY,
            amount_cents=3000,
            currency="USD",
            yearly_equivalent_monthly_cents=None,
            purchasable=False,
            provider_references={"apple": "saman_ultra_monthly", "google": "saman.ultra.monthly"},
        ),
        Price(
            price_id="price_ultra_yearly_usd_24000",
            plan_id="plan_ultra",
            period=BillingPeriod.YEARLY,
            amount_cents=24000,
            currency="USD",
            yearly_equivalent_monthly_cents=2000,
            purchasable=False,
            provider_references={"apple": "saman_ultra_yearly", "google": "saman.ultra.yearly"},
        ),
    ]

    # Map prices per plan
    prices_by_plan: Dict[str, List[Price]] = {}
    for p in prices:
        prices_by_plan.setdefault(p.plan_id, []).append(p)

    # 2. PLANS
    plans: List[Plan] = [
        Plan(
            plan_id="plan_free",
            tier=MembershipTier.FREE,
            name="Free",
            subtitle="Core essentials",
            hero_description="Everyday food tracking, workout logging, and basic health metrics.",
            is_recommended=False,
            is_current=True,
            icon_name="check_circle_outline",
            feature_ids=[
                "core.nutrition_logging",
                "core.manual_workouts",
                "core.basic_health_metrics",
                "ai.food_classifier.free",
            ],
            prices=prices_by_plan.get("plan_free", []),
            availability_notice="Included with your free Saman account.",
        ),
        Plan(
            plan_id="plan_plus",
            tier=MembershipTier.PLUS,
            name="Plus",
            subtitle="Nutrition AI",
            hero_description="A planned step beyond everyday food tracking, with Gemini food photo analysis.",
            is_recommended=False,
            is_current=False,
            icon_name="restaurant",
            feature_ids=[
                "core.nutrition_logging",
                "core.manual_workouts",
                "core.basic_health_metrics",
                "ai.food_classifier.free",
                "ai.nutrition_gemini",
                "ai.chat_coach",
            ],
            prices=prices_by_plan.get("plan_plus", []),
            availability_notice="Plus is not available yet. Planned features, limits, and pricing may change before launch.",
        ),
        Plan(
            plan_id="plan_pro",
            tier=MembershipTier.PRO,
            name="Pro",
            subtitle="Workout Intelligence",
            hero_description="Planned movement analysis and rep counting, alongside Nutrition AI.",
            is_recommended=True,
            is_current=False,
            icon_name="fitness_center",
            feature_ids=[
                "core.nutrition_logging",
                "core.manual_workouts",
                "core.basic_health_metrics",
                "ai.food_classifier.free",
                "ai.nutrition_gemini",
                "ai.chat_coach",
                "workout.cv.lat_pulldown",
            ],
            prices=prices_by_plan.get("plan_pro", []),
            availability_notice="Pro is not available yet. Planned features, limits, and pricing may change before launch.",
        ),
        Plan(
            plan_id="plan_ultra",
            tier=MembershipTier.ULTRA,
            name="Ultra",
            subtitle="Personalized Intelligence",
            hero_description="Planned advanced intelligence, a larger AI allowance, and more personalized context.",
            is_recommended=False,
            is_current=False,
            icon_name="psychology_outlined",
            feature_ids=[
                "core.nutrition_logging",
                "core.manual_workouts",
                "core.basic_health_metrics",
                "ai.food_classifier.free",
                "ai.nutrition_gemini",
                "ai.chat_coach",
                "workout.cv.lat_pulldown",
                "ai.advanced_thinking",
                "ai.extended_memory",
            ],
            prices=prices_by_plan.get("plan_ultra", []),
            availability_notice="Ultra is not available yet. Planned features, limits, and pricing may change before launch.",
        ),
    ]

    # 3. MATRIX FEATURE DEFINITIONS
    matrix_features: List[MatrixFeatureDefinition] = [
        # Group 1: Core Essentials
        MatrixFeatureDefinition(
            id="nutrition_logging",
            title="Nutrition logging",
            group="CORE ESSENTIALS",
            status_map={
                MembershipTier.FREE: InclusionStatus.INCLUDED,
                MembershipTier.PLUS: InclusionStatus.INCLUDED,
                MembershipTier.PRO: InclusionStatus.INCLUDED,
                MembershipTier.ULTRA: InclusionStatus.INCLUDED,
            },
        ),
        MatrixFeatureDefinition(
            id="manual_workouts",
            title="Manual workouts",
            group="CORE ESSENTIALS",
            status_map={
                MembershipTier.FREE: InclusionStatus.INCLUDED,
                MembershipTier.PLUS: InclusionStatus.INCLUDED,
                MembershipTier.PRO: InclusionStatus.INCLUDED,
                MembershipTier.ULTRA: InclusionStatus.INCLUDED,
            },
        ),
        MatrixFeatureDefinition(
            id="free_food_photo_model",
            title="Free food photo model",
            group="CORE ESSENTIALS",
            status_map={
                MembershipTier.FREE: InclusionStatus.INCLUDED,
                MembershipTier.PLUS: InclusionStatus.INCLUDED,
                MembershipTier.PRO: InclusionStatus.INCLUDED,
                MembershipTier.ULTRA: InclusionStatus.INCLUDED,
            },
        ),
        MatrixFeatureDefinition(
            id="basic_health_metrics",
            title="Basic health metrics",
            group="CORE ESSENTIALS",
            status_map={
                MembershipTier.FREE: InclusionStatus.INCLUDED,
                MembershipTier.PLUS: InclusionStatus.INCLUDED,
                MembershipTier.PRO: InclusionStatus.INCLUDED,
                MembershipTier.ULTRA: InclusionStatus.INCLUDED,
            },
        ),
        # Group 2: Nutrition AI
        MatrixFeatureDefinition(
            id="gemini_food_analysis",
            title="Gemini food analysis",
            group="NUTRITION AI",
            status_map={
                MembershipTier.FREE: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PLUS: InclusionStatus.PLANNED,
                MembershipTier.PRO: InclusionStatus.PLANNED,
                MembershipTier.ULTRA: InclusionStatus.PLANNED,
            },
        ),
        MatrixFeatureDefinition(
            id="monthly_ai_allowance",
            title="Monthly AI allowance",
            group="NUTRITION AI",
            status_map={
                MembershipTier.FREE: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PLUS: InclusionStatus.PLANNED,
                MembershipTier.PRO: InclusionStatus.PLANNED,
                MembershipTier.ULTRA: InclusionStatus.PLANNED,
            },
        ),
        # Group 3: Workout CV Intelligence
        MatrixFeatureDefinition(
            id="workout_cv_ai",
            title="Workout CV AI",
            group="WORKOUT CV INTELLIGENCE",
            status_map={
                MembershipTier.FREE: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PLUS: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PRO: InclusionStatus.PLANNED,
                MembershipTier.ULTRA: InclusionStatus.PLANNED,
            },
        ),
        MatrixFeatureDefinition(
            id="movement_rep_counting",
            title="Movement analysis & rep counting",
            group="WORKOUT CV INTELLIGENCE",
            status_map={
                MembershipTier.FREE: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PLUS: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PRO: InclusionStatus.PLANNED,
                MembershipTier.ULTRA: InclusionStatus.PLANNED,
            },
        ),
        MatrixFeatureDefinition(
            id="separate_cv_allowance",
            title="Separate CV allowance",
            group="WORKOUT CV INTELLIGENCE",
            status_map={
                MembershipTier.FREE: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PLUS: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PRO: InclusionStatus.PLANNED,
                MembershipTier.ULTRA: InclusionStatus.PLANNED,
            },
        ),
        # Group 4: Advanced Intelligence
        MatrixFeatureDefinition(
            id="advanced_thinking",
            title="Advanced Thinking",
            group="ADVANCED INTELLIGENCE",
            status_map={
                MembershipTier.FREE: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PLUS: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PRO: InclusionStatus.NOT_INCLUDED,
                MembershipTier.ULTRA: InclusionStatus.PLANNED,
            },
        ),
        MatrixFeatureDefinition(
            id="extended_history_memory",
            title="Extended history & memory",
            group="ADVANCED INTELLIGENCE",
            status_map={
                MembershipTier.FREE: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PLUS: InclusionStatus.NOT_INCLUDED,
                MembershipTier.PRO: InclusionStatus.NOT_INCLUDED,
                MembershipTier.ULTRA: InclusionStatus.PLANNED,
            },
        ),
    ]

    return CatalogVersion(
        version_id="v1.0-preview",
        status=CatalogStatus.PUBLISHED,
        currency="USD",
        preview_mode=True,
        disclaimer="Demo pricing · Subject to change. Not purchasable.",
        plans=plans,
        prices=prices,
        matrix_features=matrix_features,
        published_at=datetime(2026, 10, 28, 0, 0, 0, tzinfo=timezone.utc),
        notes="Official baseline catalog synchronized with Flutter UI demo handover.",
        schema_version=1,
    )


# ==============================================================================
# CATALOG ENGINE SERVICE
# ==============================================================================

class CatalogEngine:
    """
    In-memory, thread-safe versioned catalog registry.
    Ensures immutability of published catalog versions.
    """
    _instance: Optional["CatalogEngine"] = None
    _lock = Lock()

    def __init__(self):
        self._versions: Dict[str, CatalogVersion] = {}
        self._active_version_id: Optional[str] = None
        # Bootstrap canonical preview version
        initial_catalog = _build_v1_preview_catalog()
        self._register_internal(initial_catalog, set_active=True)

    @classmethod
    def get_instance(cls) -> "CatalogEngine":
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = cls()
        return cls._instance

    def _register_internal(self, catalog: CatalogVersion, set_active: bool = False) -> None:
        vid = catalog.version_id
        if vid in self._versions and self._versions[vid].status == CatalogStatus.PUBLISHED:
            # Cannot modify published version
            raise CatalogImmutabilityError(f"Catalog version '{vid}' is published and immutable.")
        self._versions[vid] = deepcopy(catalog)
        if set_active:
            self._active_version_id = vid

    def register_version(self, catalog: CatalogVersion, set_active: bool = False) -> None:
        """Register a new catalog version or update a draft version."""
        with self._lock:
            self._register_internal(catalog, set_active)

    def publish_version(self, version_id: str, set_active: bool = True) -> CatalogVersion:
        """Promote a draft catalog to published status and record UTC timestamp."""
        with self._lock:
            if version_id not in self._versions:
                raise CatalogNotFoundError(f"Catalog version '{version_id}' not found.")
            cat = self._versions[version_id]
            if cat.status == CatalogStatus.PUBLISHED:
                return deepcopy(cat)
            updated = cat.model_copy(update={
                "status": CatalogStatus.PUBLISHED,
                "published_at": datetime.now(timezone.utc)
            })
            self._versions[version_id] = updated
            if set_active:
                self._active_version_id = version_id
            return deepcopy(updated)

    def get_active_catalog(self, include_drafts: bool = False) -> Optional[CatalogVersion]:
        """Retrieve the currently active published catalog."""
        with self._lock:
            if not self._active_version_id or self._active_version_id not in self._versions:
                return None
            active = self._versions[self._active_version_id]
            if not include_drafts and active.status != CatalogStatus.PUBLISHED:
                return None
            return deepcopy(active)

    def get_catalog_by_version(self, version_id: str, include_drafts: bool = False) -> Optional[CatalogVersion]:
        """Retrieve a specific catalog by version string."""
        with self._lock:
            cat = self._versions.get(version_id)
            if not cat:
                return None
            if not include_drafts and cat.status != CatalogStatus.PUBLISHED:
                return None
            return deepcopy(cat)

    def list_published_versions(self) -> List[str]:
        """List all published version identifiers."""
        with self._lock:
            return [
                vid for vid, cat in self._versions.items()
                if cat.status == CatalogStatus.PUBLISHED
            ]


# Singleton accessor
def get_catalog_engine() -> CatalogEngine:
    return CatalogEngine.get_instance()

