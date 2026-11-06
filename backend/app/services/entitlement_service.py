"""
Entitlement Evaluation Service for Saman Revenue.
Subsystem: Saman Revenue — Membership, Billing & Entitlements (CP-04).

Evaluates effective capability authorization for an authenticated user, feature, and time.
Decouples explicit grants from subscription status and catalog previews.
"""

from datetime import datetime, timezone
from typing import Any, Dict, List, Optional
import logging

from backend.app.models.revenue import (
    EntitlementDecision,
    EntitlementDecisionStatus,
    EntitlementStatus,
    InclusionStatus,
    MembershipTier,
    SubscriptionStatus,
)
from backend.app.services.catalog_engine import get_catalog_engine
from backend.app.database_revenue import (
    COLL_ENTITLEMENT_GRANTS,
    COLL_SUBSCRIPTIONS,
)

logger = logging.getLogger(__name__)

# Canonical mapping between dot-notated benefit IDs and catalog matrix feature keys
BENEFIT_TO_MATRIX_MAP: Dict[str, str] = {
    # Core essentials
    "core.nutrition_logging": "nutrition_logging",
    "core.manual_workouts": "manual_workouts",
    "core.basic_health_metrics": "basic_health_metrics",
    "ai.food_classifier.free": "free_food_photo_model",
    # Nutrition AI
    "ai.nutrition_gemini": "gemini_food_analysis",
    "ai.chat_coach": "gemini_food_analysis",  # or advanced chat coach
    "ai.monthly_allowance": "monthly_ai_allowance",
    # Workout CV
    "workout.cv.ai": "workout_cv_ai",
    "workout.cv.lat_pulldown": "workout_cv_ai",
    "workout.movement_rep_counting": "movement_rep_counting",
    # Advanced intelligence
    "ai.advanced_thinking": "advanced_thinking",
    "ai.extended_memory": "extended_history_memory",
}


class StorageUnavailableException(Exception):
    """Raised when the database layer is unavailable."""
    pass


class EntitlementService:
    """
    Evaluates whether an authenticated user has entitlement to a specific benefit.
    
    Precedence Hierarchy:
    1. Active Staff/Promotional Override Grant (revenue_entitlement_grants)
    2. Active Paid Subscription Tier (revenue_subscriptions -> Catalog Matrix)
    3. Default Baseline Free Tier (Catalog Matrix Free tier)
    
    Safety:
    - Fails closed on storage failure for AI/paid benefits.
    - Requires authenticated user_id.
    - Supports clock injection for precise boundary testing.
    """

    def __init__(self, db: Any = None):
        self._db = db

    def _get_db(self) -> Any:
        if self._db is not None:
            return self._db
        try:
            from backend.app.database import db as active_db
            return active_db
        except ImportError:
            return None

    def evaluate_entitlement(
        self,
        user_id: str,
        benefit_id: str,
        as_of: Optional[datetime] = None,
    ) -> EntitlementDecision:
        """
        Evaluates entitlement for user_id and benefit_id as of a specific point in time.
        
        Args:
            user_id: Authenticated user ID.
            benefit_id: Dot-notated benefit ID (e.g. 'ai.nutrition_gemini').
            as_of: Point-in-time timestamp. Defaults to UTC now.
            
        Returns:
            EntitlementDecision with typed decision status.
        """
        if not user_id:
            return EntitlementDecision(
                status=EntitlementDecisionStatus.ENTITLEMENT_REQUIRED,
                user_id="",
                benefit_id=benefit_id,
                reason="Unauthenticated request: user_id is missing."
            )

        eval_time = as_of or datetime.now(timezone.utc)
        db = self._get_db()

        # Step 1: Check Explicit Grants in revenue_entitlement_grants
        if db is not None:
            try:
                grants_col = db[COLL_ENTITLEMENT_GRANTS]
                # Find grants for user and benefit
                query = {
                    "user_id": user_id,
                    "benefit_id": benefit_id,
                }
                raw_grants = list(grants_col.find(query))
                
                # Check for active grants or explicit revocations
                active_decision = None
                revoked_decision = None

                for g in raw_grants:
                    status = g.get("status")
                    if status == EntitlementStatus.GRANTED.value:
                        valid_from = g.get("valid_from")
                        valid_until = g.get("valid_until")

                        # Handle boundary conditions
                        if valid_from and eval_time < valid_from:
                            continue  # Not yet valid
                        if valid_until and eval_time >= valid_until:
                            continue  # Expired

                        active_decision = EntitlementDecision(
                            status=EntitlementDecisionStatus.ALLOWED,
                            user_id=user_id,
                            benefit_id=benefit_id,
                            source=g.get("source_type", "staff_override"),
                            valid_until=valid_until,
                            reason=f"Active explicit grant: {g.get('grant_id')}"
                        )
                        break

                    elif status == EntitlementStatus.REVOKED.value:
                        if revoked_decision is None:
                            revoked_decision = EntitlementDecision(
                                status=EntitlementDecisionStatus.REVOKED,
                                user_id=user_id,
                                benefit_id=benefit_id,
                                reason=f"Entitlement grant was revoked: {g.get('grant_id')}"
                            )

                if active_decision is not None:
                    return active_decision
                if revoked_decision is not None:
                    return revoked_decision
            except Exception as exc:
                logger.error("Database query failed while evaluating explicit grants: %s", exc)
                return EntitlementDecision(
                    status=EntitlementDecisionStatus.STORAGE_UNAVAILABLE,
                    user_id=user_id,
                    benefit_id=benefit_id,
                    reason=f"Storage error reading grants: {exc}"
                )
        else:
            # DB is None: fail-closed for paid/AI benefits
            if benefit_id.startswith("ai.") or benefit_id.startswith("workout.cv"):
                return EntitlementDecision(
                    status=EntitlementDecisionStatus.STORAGE_UNAVAILABLE,
                    user_id=user_id,
                    benefit_id=benefit_id,
                    reason="Database connection unavailable; fail-closed on AI entitlement."
                )

        # Step 2: Check Active Paid Subscriptions in revenue_subscriptions
        active_sub_tier: Optional[MembershipTier] = None
        sub_valid_until: Optional[datetime] = None

        if db is not None:
            try:
                subs_col = db[COLL_SUBSCRIPTIONS]
                sub_query = {
                    "user_id": user_id,
                    "status": {
                        "$in": [
                            SubscriptionStatus.ACTIVE.value,
                            SubscriptionStatus.TRIALING.value,
                            SubscriptionStatus.PAST_DUE.value,
                        ]
                    },
                }
                raw_subs = list(subs_col.find(sub_query))

                for s in raw_subs:
                    p_start = s.get("current_period_start")
                    p_end = s.get("current_period_end")
                    sub_st = s.get("status")

                    # If PAST_DUE, must have an explicit, active grace period
                    if sub_st == SubscriptionStatus.PAST_DUE.value:
                        in_grace = s.get("in_grace_period", False)
                        grace_end = s.get("grace_period_expires_at")
                        if not in_grace or not grace_end:
                            continue
                        norm_grace_end = (
                            grace_end.replace(tzinfo=timezone.utc)
                            if isinstance(grace_end, datetime) and grace_end.tzinfo is None
                            else grace_end
                        )
                        if eval_time >= norm_grace_end:
                            continue
                    else:
                        if p_start:
                            norm_start = (
                                p_start.replace(tzinfo=timezone.utc)
                                if isinstance(p_start, datetime) and p_start.tzinfo is None
                                else p_start
                            )
                            if eval_time < norm_start:
                                continue
                        if p_end:
                            norm_end = (
                                p_end.replace(tzinfo=timezone.utc)
                                if isinstance(p_end, datetime) and p_end.tzinfo is None
                                else p_end
                            )
                            if eval_time >= norm_end:
                                continue

                    # Active subscription period or valid grace period matched
                    tier_str = s.get("tier")
                    try:
                        active_sub_tier = MembershipTier(tier_str)
                        sub_valid_until = p_end
                        break
                    except ValueError:
                        continue
            except Exception as exc:
                logger.error("Database query failed while evaluating subscription: %s", exc)
                return EntitlementDecision(
                    status=EntitlementDecisionStatus.STORAGE_UNAVAILABLE,
                    user_id=user_id,
                    benefit_id=benefit_id,
                    reason=f"Storage error reading subscriptions: {exc}"
                )

        # Step 3: Evaluate Catalog Matrix Inclusion
        effective_tier = active_sub_tier or MembershipTier.FREE
        catalog = get_catalog_engine().get_active_catalog()

        if catalog is None:
            return EntitlementDecision(
                status=EntitlementDecisionStatus.STORAGE_UNAVAILABLE,
                user_id=user_id,
                benefit_id=benefit_id,
                reason="Active catalog is unavailable."
            )

        matrix_feature_key = BENEFIT_TO_MATRIX_MAP.get(benefit_id, benefit_id)
        target_feature = next(
            (f for f in catalog.matrix_features if f.id == matrix_feature_key),
            None
        )

        if target_feature is not None:
            inclusion = target_feature.status_for(effective_tier)
            if inclusion == InclusionStatus.INCLUDED:
                source_label = "subscription" if active_sub_tier else "default_free"
                return EntitlementDecision(
                    status=EntitlementDecisionStatus.ALLOWED,
                    user_id=user_id,
                    benefit_id=benefit_id,
                    tier=effective_tier,
                    source=source_label,
                    valid_until=sub_valid_until,
                    reason=f"Feature '{matrix_feature_key}' is included in tier '{effective_tier.value}'."
                )
            elif inclusion == InclusionStatus.PLANNED:
                return EntitlementDecision(
                    status=EntitlementDecisionStatus.ENTITLEMENT_REQUIRED,
                    user_id=user_id,
                    benefit_id=benefit_id,
                    tier=effective_tier,
                    reason=f"Feature '{matrix_feature_key}' is planned on roadmap but not yet active for tier '{effective_tier.value}'."
                )
            else:
                return EntitlementDecision(
                    status=EntitlementDecisionStatus.ENTITLEMENT_REQUIRED,
                    user_id=user_id,
                    benefit_id=benefit_id,
                    tier=effective_tier,
                    reason=f"Feature '{matrix_feature_key}' is not included in tier '{effective_tier.value}'."
                )

        # Feature not found in catalog matrix
        return EntitlementDecision(
            status=EntitlementDecisionStatus.ENTITLEMENT_REQUIRED,
            user_id=user_id,
            benefit_id=benefit_id,
            tier=effective_tier,
            reason=f"Benefit '{benefit_id}' is not configured in the active catalog matrix."
        )

