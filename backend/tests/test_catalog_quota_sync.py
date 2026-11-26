"""
Sync verification tests between Backend catalog_engine (v1.0-vn),
quota_service limits, and Frontend membership_plan.dart (Master Plan Section 3.2).
"""

from pathlib import Path
import re

from backend.app.models.revenue import BillingPeriod, InclusionStatus, MembershipTier
from backend.app.services.catalog_engine import CatalogEngine
from backend.app.services import quota_service


REPO_ROOT = Path(__file__).resolve().parents[2]
DART_CATALOG_PATH = (
    REPO_ROOT
    / "frontend"
    / "lib"
    / "features"
    / "membership"
    / "domain"
    / "models"
    / "membership_plan.dart"
)


def _get_matrix_feature(catalog, feature_id: str):
    return next(f for f in catalog.matrix_features if f.id == feature_id)


def _get_plan(catalog, tier: MembershipTier):
    return next(p for p in catalog.plans if p.tier == tier)


def test_v1_vn_catalog_plans_and_vnd_prices_preserved():
    engine = CatalogEngine()
    catalog = engine.get_catalog_by_version("v1.0-vn")
    assert catalog is not None
    assert catalog.currency == "VND"
    assert catalog.preview_mode is False

    tiers = [p.tier for p in catalog.plans]
    assert tiers == [
        MembershipTier.FREE,
        MembershipTier.PLUS,
        MembershipTier.PRO,
        MembershipTier.ULTRA,
    ]

    expected_prices = {
        "plan_free": {BillingPeriod.MONTHLY: 0, BillingPeriod.YEARLY: 0},
        "plan_plus": {BillingPeriod.MONTHLY: 59000, BillingPeriod.YEARLY: 588000},
        "plan_pro": {BillingPeriod.MONTHLY: 119000, BillingPeriod.YEARLY: 1188000},
        "plan_ultra": {BillingPeriod.MONTHLY: 199000, BillingPeriod.YEARLY: 2028000},
    }
    for plan in catalog.plans:
        by_period = {pr.period: pr.amount_cents for pr in plan.prices}
        assert by_period == expected_prices[plan.plan_id]


def test_v1_vn_matrix_features_master_plan_sync():
    engine = CatalogEngine()
    catalog = engine.get_catalog_by_version("v1.0-vn")
    assert catalog is not None

    feature_ids = [f.id for f in catalog.matrix_features]
    for required_id in (
        "gemini_food_analysis",
        "monthly_ai_allowance",
        "workout_cv_ai",
        "movement_rep_counting",
        "separate_cv_allowance",
        "video_story_cloud_storage",
        "ai_video_citation",
    ):
        assert required_id in feature_ids

    # Free MUST include gemini_food_analysis (1/ngày) and workout_cv_ai (2/tuần)
    gemini = _get_matrix_feature(catalog, "gemini_food_analysis")
    assert gemini.status_for(MembershipTier.FREE) == InclusionStatus.INCLUDED
    assert gemini.status_for(MembershipTier.PLUS) == InclusionStatus.INCLUDED
    assert gemini.status_for(MembershipTier.PRO) == InclusionStatus.INCLUDED
    assert gemini.status_for(MembershipTier.ULTRA) == InclusionStatus.INCLUDED

    daily_ai = _get_matrix_feature(catalog, "monthly_ai_allowance")
    assert daily_ai.status_for(MembershipTier.FREE) == InclusionStatus.INCLUDED
    assert daily_ai.status_for(MembershipTier.PLUS) == InclusionStatus.INCLUDED
    assert daily_ai.status_for(MembershipTier.PRO) == InclusionStatus.INCLUDED
    assert daily_ai.status_for(MembershipTier.ULTRA) == InclusionStatus.INCLUDED

    cv_ai = _get_matrix_feature(catalog, "workout_cv_ai")
    assert cv_ai.status_for(MembershipTier.FREE) == InclusionStatus.INCLUDED
    assert cv_ai.status_for(MembershipTier.PLUS) == InclusionStatus.INCLUDED
    assert cv_ai.status_for(MembershipTier.PRO) == InclusionStatus.INCLUDED
    assert cv_ai.status_for(MembershipTier.ULTRA) == InclusionStatus.INCLUDED

    rep_count = _get_matrix_feature(catalog, "movement_rep_counting")
    assert rep_count.status_for(MembershipTier.FREE) == InclusionStatus.INCLUDED
    assert rep_count.status_for(MembershipTier.PLUS) == InclusionStatus.INCLUDED
    assert rep_count.status_for(MembershipTier.PRO) == InclusionStatus.INCLUDED
    assert rep_count.status_for(MembershipTier.ULTRA) == InclusionStatus.INCLUDED

    unlimited_cv = _get_matrix_feature(catalog, "separate_cv_allowance")
    assert unlimited_cv.status_for(MembershipTier.FREE) == InclusionStatus.NOT_INCLUDED
    assert unlimited_cv.status_for(MembershipTier.PLUS) == InclusionStatus.NOT_INCLUDED
    assert unlimited_cv.status_for(MembershipTier.PRO) == InclusionStatus.INCLUDED
    assert unlimited_cv.status_for(MembershipTier.ULTRA) == InclusionStatus.INCLUDED

    video_story = _get_matrix_feature(catalog, "video_story_cloud_storage")
    assert video_story.status_for(MembershipTier.FREE) == InclusionStatus.NOT_INCLUDED
    assert video_story.status_for(MembershipTier.PLUS) == InclusionStatus.INCLUDED
    assert video_story.status_for(MembershipTier.PRO) == InclusionStatus.INCLUDED
    assert video_story.status_for(MembershipTier.ULTRA) == InclusionStatus.INCLUDED

    citation = _get_matrix_feature(catalog, "ai_video_citation")
    assert citation.status_for(MembershipTier.FREE) == InclusionStatus.NOT_INCLUDED
    assert citation.status_for(MembershipTier.PLUS) == InclusionStatus.INCLUDED
    assert citation.status_for(MembershipTier.PRO) == InclusionStatus.INCLUDED
    assert citation.status_for(MembershipTier.ULTRA) == InclusionStatus.INCLUDED


def test_v1_vn_plan_copy_matches_master_plan():
    engine = CatalogEngine()
    catalog = engine.get_catalog_by_version("v1.0-vn")
    assert catalog is not None

    free = _get_plan(catalog, MembershipTier.FREE)
    assert "1 ảnh" in free.hero_description
    assert "5 lượt Swift 3/ngày" in free.hero_description
    assert "2 lượt Workout CV/tuần" in free.hero_description
    assert "0 MB Cloud Video Story" in free.hero_description
    assert "workout.cv.ai" in free.feature_ids
    assert "ai.nutrition_gemini" in free.feature_ids

    plus = _get_plan(catalog, MembershipTier.PLUS)
    assert "5 ảnh" in plus.hero_description
    assert "30 Swift 3 + 10 Core 3/ngày" in plus.hero_description
    assert "5 lượt Workout CV/tuần" in plus.hero_description
    assert "500 MB Cloud Video Story" in plus.hero_description
    assert "7 ngày" in plus.hero_description
    assert "workout.cv.ai" in plus.feature_ids
    assert "workout.video_story_cloud" in plus.feature_ids
    assert "ai.video_citation" in plus.feature_ids

    pro = _get_plan(catalog, MembershipTier.PRO)
    assert "Workout CV AI không giới hạn" in pro.hero_description
    assert "10 ảnh" in pro.hero_description
    assert "50 Swift 3 + 30 Core 3/ngày" in pro.hero_description
    assert "5 GB Cloud Video Story" in pro.hero_description
    assert "14 ngày" in pro.hero_description

    ultra = _get_plan(catalog, MembershipTier.ULTRA)
    assert "20 ảnh" in ultra.hero_description
    assert "50 Swift 3 + 30 Core 3 + 15 Pro 3 (Deep Audit)/ngày" in ultra.hero_description
    assert "Workout CV không giới hạn" in ultra.hero_description
    assert "20 GB Cloud Video Story" in ultra.hero_description
    assert "30 ngày + Deep Audit" in ultra.hero_description


def test_cross_check_quota_service_limits():
    limits = quota_service.TIER_QUOTA_LIMITS
    assert limits["free"]["ai.nutrition_gemini"] == ("daily", 1)
    assert limits["free"]["ai.chat.swift3"] == ("daily", 5)
    assert limits["free"]["workout.cv.ai"] == ("weekly", 2)

    assert limits["plus"]["ai.nutrition_gemini"] == ("daily", 5)
    assert limits["plus"]["ai.chat.swift3"] == ("daily", 30)
    assert limits["plus"]["ai.chat.core3"] == ("daily", 10)

    assert limits["pro"]["ai.nutrition_gemini"] == ("daily", 10)
    assert limits["pro"]["ai.chat.swift3"] == ("daily", 50)
    assert limits["pro"]["ai.chat.core3"] == ("daily", 30)
    assert limits["pro"]["workout.cv.ai"] == ("weekly", -1)

    assert limits["ultra"]["ai.nutrition_gemini"] == ("daily", 20)
    assert limits["ultra"]["ai.chat.swift3"] == ("daily", 50)
    assert limits["ultra"]["ai.chat.core3"] == ("daily", 30)
    assert limits["ultra"]["ai.chat.pro3"] == ("daily", 15)
    assert limits["ultra"]["workout.cv.ai"] == ("weekly", -1)

    # P2-A live sync verification
    assert limits["plus"]["workout.cv.ai"] == ("weekly", 5)

    storage_limits = quota_service.TIER_STORAGE_LIMITS_MB
    assert storage_limits["free"] == 0
    assert storage_limits["plus"] == 500
    assert storage_limits["pro"] == 5000
    assert storage_limits["ultra"] == 20000

    citation_days = quota_service.TIER_VIDEO_CITATION_DAYS
    assert citation_days["free"] == 0
    assert citation_days["plus"] == 7
    assert citation_days["pro"] == 14
    assert citation_days["ultra"] == 30


def test_frontend_membership_plan_dart_sync():
    assert DART_CATALOG_PATH.exists(), f"Missing {DART_CATALOG_PATH}"
    dart_text = DART_CATALOG_PATH.read_text(encoding="utf-8")

    # All 4 required matrix keys exist
    for key in (
        "'gemini_food_analysis'",
        "'workout_cv_ai'",
        "'video_story_cloud_storage'",
        "'ai_video_citation'",
    ):
        assert key in dart_text, f"Missing matrix key {key} in membership_plan.dart"

    # Extract matrix blocks and verify free inclusion for gemini_food_analysis & workout_cv_ai
    def _extract_matrix_block(feature_id: str) -> str:
        pattern = rf"MatrixFeature\(\s*id:\s*'{feature_id}'.*?statusMap:\s*\{{(.*?)\}}"
        match = re.search(pattern, dart_text, re.DOTALL)
        assert match is not None, f"Could not find MatrixFeature block for {feature_id}"
        return match.group(1)

    gemini_block = _extract_matrix_block("gemini_food_analysis")
    assert "MembershipTier.free: InclusionStatus.included" in gemini_block
    assert "MembershipTier.free: InclusionStatus.notIncluded" not in gemini_block

    cv_block = _extract_matrix_block("workout_cv_ai")
    assert "MembershipTier.free: InclusionStatus.included" in cv_block
    assert "MembershipTier.plus: InclusionStatus.included" in cv_block
    assert "MembershipTier.free: InclusionStatus.notIncluded" not in cv_block
    assert "MembershipTier.plus: InclusionStatus.notIncluded" not in cv_block

    video_story_block = _extract_matrix_block("video_story_cloud_storage")
    assert "MembershipTier.free: InclusionStatus.notIncluded" in video_story_block
    assert "MembershipTier.plus: InclusionStatus.included" in video_story_block
    assert "MembershipTier.pro: InclusionStatus.included" in video_story_block
    assert "MembershipTier.ultra: InclusionStatus.included" in video_story_block

    citation_block = _extract_matrix_block("ai_video_citation")
    assert "MembershipTier.free: InclusionStatus.notIncluded" in citation_block
    assert "MembershipTier.plus: InclusionStatus.included" in citation_block
    assert "MembershipTier.pro: InclusionStatus.included" in citation_block
    assert "MembershipTier.ultra: InclusionStatus.included" in citation_block

    # Verify plan copy tokens in Dart
    for expected_snippet in (
        "2 lượt Workout CV/tuần",
        "0 MB Cloud Video Story",
        "5 lượt Workout CV/tuần",
        "500 MB Cloud Video Story",
        "7 ngày",
        "5 GB Cloud Video Story",
        "14 ngày",
        "20 GB Cloud Video Story",
        "30 ngày + Deep Audit",
    ):
        assert expected_snippet in dart_text, f"Missing '{expected_snippet}' in membership_plan.dart"
