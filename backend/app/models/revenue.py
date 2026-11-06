"""
Domain Schemas and Data Models for Saman Revenue.
Subsystem: Saman Revenue — Membership, Billing & Entitlements (CP-03 / CP-03A / CP-04).

Invariants:
- All monetary amounts MUST be represented as integers in minor currency units (cents). Floats are strictly prohibited.
- Timestamps must be timezone-aware UTC datetimes.
- Feature eligibility is decoupled from tier hierarchy.
- All preview catalog definitions are marked purchasable=False by default.
- Catalog definitions and matrix specifications are frozen (immutable) value objects.
"""

from datetime import datetime, timezone
from enum import Enum
from typing import Dict, List, Optional, Any
from pydantic import BaseModel, Field, field_validator, model_validator, ConfigDict


# ==============================================================================
# ENUMS
# ==============================================================================

class MembershipTier(str, Enum):
    FREE = "free"
    PLUS = "plus"
    PRO = "pro"
    ULTRA = "ultra"


class BillingPeriod(str, Enum):
    MONTHLY = "monthly"
    YEARLY = "yearly"


class CatalogStatus(str, Enum):
    DRAFT = "draft"
    PUBLISHED = "published"
    RETIRED = "retired"


class InclusionStatus(str, Enum):
    INCLUDED = "included"        # Free / baseline inclusion
    PLANNED = "planned"          # Planned roadmap inclusion
    NOT_INCLUDED = "not_included" # Not part of tier


class SubscriptionStatus(str, Enum):
    TRIALING = "trialing"
    ACTIVE = "active"
    PAST_DUE = "past_due"
    CANCELED = "canceled"
    EXPIRED = "expired"


class PaymentStatus(str, Enum):
    PENDING = "pending"
    VERIFIED = "verified"
    FAILED = "failed"
    REFUNDED = "refunded"


class EntitlementStatus(str, Enum):
    GRANTED = "granted"
    DENIED = "denied"
    REVOKED = "revoked"
    EXPIRED = "expired"


class UsageOpStatus(str, Enum):
    RESERVED = "reserved"
    EXECUTING = "executing"
    COMMITTED = "committed"
    RELEASED = "released"
    FAILED_UNKNOWN = "failed_unknown"


class EventProcessingStatus(str, Enum):
    RECEIVED = "received"
    PROCESSED = "processed"
    IGNORED_DUPLICATE = "ignored_duplicate"
    IGNORED_OUT_OF_ORDER = "ignored_out_of_order"
    IGNORED_UNSUPPORTED = "ignored_unsupported"
    FAILED = "failed"


class EntitlementDecisionStatus(str, Enum):
    ALLOWED = "allowed"
    ENTITLEMENT_REQUIRED = "entitlement_required"
    EXPIRED = "expired"
    REVOKED = "revoked"
    STORAGE_UNAVAILABLE = "storage_unavailable"


class ReservationStatus(str, Enum):
    RESERVED = "reserved"
    ALREADY_COMPLETED = "already_completed"
    IN_PROGRESS = "in_progress"
    QUOTA_EXHAUSTED = "quota_exhausted"
    OPERATION_CONFLICT = "operation_conflict"
    STORAGE_UNAVAILABLE = "storage_unavailable"
    ENTITLEMENT_DENIED = "entitlement_denied"


class PaymentProviderName(str, Enum):
    UNCONFIGURED = "unconfigured"
    APPLE_APP_STORE = "apple_app_store"
    GOOGLE_PLAY = "google_play"
    REVENUECAT = "revenuecat"
    STRIPE = "stripe"


class PaymentEnvironment(str, Enum):
    SANDBOX = "sandbox"
    PRODUCTION = "production"


class ProviderVerificationStatus(str, Enum):
    VERIFIED_ACTIVE = "verified_active"
    VERIFIED = "verified"
    PENDING = "pending"
    CANCELED = "canceled"
    EXPIRED = "expired"
    REVOKED = "revoked"
    INVALID = "invalid"
    PROVIDER_UNAVAILABLE = "provider_unavailable"


class PurchaseVerificationOutcomeStatus(str, Enum):
    CONFIRMED = "confirmed"
    PENDING = "pending"
    CANCELED = "canceled"
    FAILED = "failed"
    UNAVAILABLE = "unavailable"


class SubscriptionLifecycleEventType(str, Enum):
    INITIAL_PURCHASE = "initial_purchase"
    RENEWAL = "renewal"
    CANCELLATION = "cancellation"  # Cancel auto-renew (entitlement preserved until period end)
    BILLING_ISSUE = "billing_issue"  # Payment failure (past_due / grace evaluation)
    GRACE_EXPIRED = "grace_expired"
    EXPIRATION = "expiration"
    REVOCATION = "revocation"  # Refund / chargeback (targeted grant revoke)
    RESTORE = "restore"
    RECONCILIATION = "reconciliation"


class ReceiptOwnershipStatus(str, Enum):
    VERIFIED_OWNER = "verified_owner"
    UNRESOLVED_CONFLICT = "unresolved_conflict"
    FIRST_OWNER_PROPOSED = "first_owner_proposed"


class GracePeriodPolicy(BaseModel):
    """
    Policy governing subscription grace period during billing retry.
    Explicitly injected — never hardcoded to arbitrary values (CP-08 Invariant).
    """
    model_config = ConfigDict(frozen=True)

    enabled: bool = False
    grace_duration_seconds: int = Field(0, ge=0)



# ==============================================================================
# PLAN, PRICE & CATALOG SCHEMAS (FROZEN VALUE OBJECTS)
# ==============================================================================

class Price(BaseModel):
    """
    Commercial pricing definition for a plan in a given billing period.
    Monetary amounts are strictly integers in minor units (e.g., 1000 = $10.00 USD).
    Immutable value object.
    """
    model_config = ConfigDict(frozen=True)

    price_id: str = Field(..., description="Stable price identifier, e.g. price_plus_monthly_usd_1000")
    plan_id: str = Field(..., description="Target plan ID, e.g. plan_plus")
    period: BillingPeriod
    amount_cents: int = Field(..., ge=0, description="Price in minor currency units (cents). Float is prohibited.")
    currency: str = Field("USD", min_length=3, max_length=3, description="ISO 4217 3-letter currency code.")
    yearly_equivalent_monthly_cents: Optional[int] = Field(None, ge=0, description="Displayed monthly equivalent in cents.")
    purchasable: bool = Field(False, description="Flag indicating whether this price is open for purchase. False in preview.")
    provider_references: Dict[str, str] = Field(default_factory=dict, description="Mapping of provider product IDs (e.g. apple, google).")

    @field_validator("currency")
    @classmethod
    def validate_currency_uppercase(cls, v: str) -> str:
        return v.upper()


class Plan(BaseModel):
    """
    Product plan specification representing a tier offering.
    Immutable value object.
    """
    model_config = ConfigDict(frozen=True)

    plan_id: str = Field(..., description="Stable plan identifier, e.g. plan_free, plan_plus")
    tier: MembershipTier
    name: str = Field(..., min_length=1)
    subtitle: str
    hero_description: str
    is_recommended: bool = False
    is_current: bool = False
    icon_name: str
    feature_ids: List[str] = Field(default_factory=list, description="List of benefit IDs included in this plan.")
    prices: List[Price] = Field(default_factory=list)
    availability_notice: str
    schema_version: int = Field(1, description="Schema evolution version.")


class MatrixFeatureDefinition(BaseModel):
    """
    Comparison matrix feature mapping across tiers.
    Eligibility is explicit per tier; higher tiers do NOT automatically inherit unlisted features.
    Immutable value object.
    """
    model_config = ConfigDict(frozen=True)

    id: str = Field(..., description="Stable feature ID, e.g. core.nutrition_logging")
    title: str
    group: str = Field(..., description="Feature group title, e.g. CORE ESSENTIALS, NUTRITION AI")
    status_map: Dict[MembershipTier, InclusionStatus]

    def status_for(self, tier: MembershipTier) -> InclusionStatus:
        return self.status_map.get(tier, InclusionStatus.NOT_INCLUDED)


class CatalogVersion(BaseModel):
    """
    Immutable versioned catalog snapshot.
    Once published, the contents of a catalog version cannot be mutated.
    """
    model_config = ConfigDict(frozen=True)

    version_id: str = Field(..., description="Semantic version string, e.g. v1.0-preview")
    status: CatalogStatus = Field(CatalogStatus.DRAFT)
    currency: str = Field("USD", min_length=3, max_length=3)
    preview_mode: bool = Field(True, description="True if prices and plans are demo/preview and not commercially active.")
    disclaimer: str = Field(
        "Demo pricing · Subject to change. Not purchasable.",
        description="User-facing legal and commercial notice."
    )
    plans: List[Plan] = Field(default_factory=list)
    prices: List[Price] = Field(default_factory=list)
    matrix_features: List[MatrixFeatureDefinition] = Field(default_factory=list)
    published_at: Optional[datetime] = None
    notes: Optional[str] = None
    schema_version: int = Field(1)

    @field_validator("currency")
    @classmethod
    def validate_catalog_currency(cls, v: str) -> str:
        return v.upper()

    @model_validator(mode="after")
    def validate_published_immutability_constraints(self) -> "CatalogVersion":
        if self.status == CatalogStatus.PUBLISHED and not self.published_at:
            # Auto-assign UTC timestamp if not provided upon publishing
            object.__setattr__(self, "published_at", datetime.now(timezone.utc))
        return self


# ==============================================================================
# SUBSCRIPTION & PAYMENT SCHEMAS
# ==============================================================================

class Subscription(BaseModel):
    """
    Financial subscription record binding a user to a plan and price.
    Identity is scoped by provider, environment, and original_transaction_id.
    """
    subscription_id: str
    user_id: str
    user_email: str
    plan_id: str
    tier: MembershipTier
    price_id: str
    status: SubscriptionStatus
    provider: str = Field(..., description="Payment rail: apple_storekit, google_play, stripe, or manual_mock")
    environment: str = Field("production", description="Environment scope: production, sandbox, staging, or test.")
    app_id: Optional[str] = Field(None, description="Client/bundle identifier, e.g. com.saman.app.")
    original_transaction_id: Optional[str] = Field(
        None,
        description="Root subscription lineage token/identifier (e.g. Apple originalTransactionId, Google purchaseToken, Stripe subscription_id)."
    )
    latest_transaction_id: Optional[str] = Field(
        None,
        description="Most recent billing event/renewal transaction identifier (e.g. Apple transactionId, Google orderId GPA.xxx, Stripe invoice_id)."
    )
    current_period_start: datetime
    current_period_end: datetime
    cancel_at_period_end: bool = False
    canceled_at: Optional[datetime] = None
    auto_renew_status: bool = True
    in_grace_period: bool = False
    grace_period_expires_at: Optional[datetime] = None
    last_event_id: Optional[str] = None
    last_event_type: Optional[str] = None
    last_event_timestamp: Optional[datetime] = None
    version: int = 1
    reconciliation_required: bool = False
    ownership_status: str = "first_owner_proposed"
    catalog_version: str = Field("v1.0-preview", description="Catalog version referenced at purchase time.")
    schema_version: int = 1
    created_at: datetime
    updated_at: datetime


class PaymentTransaction(BaseModel):
    """
    Verified financial transaction ledger entry.
    """
    transaction_id: str
    subscription_id: str
    user_id: str
    status: PaymentStatus
    amount_cents: int = Field(..., ge=0)
    currency: str = "USD"
    provider: str
    provider_transaction_id: str
    transaction_time: datetime
    raw_payload_hash: Optional[str] = None
    schema_version: int = 1
    created_at: datetime


class ProviderEvent(BaseModel):
    """
    Raw payment webhook event for audit, reconciliation, and idempotency.
    """
    event_id: str
    provider: str
    provider_event_id: str
    event_type: str
    event_timestamp: datetime
    processing_status: EventProcessingStatus = EventProcessingStatus.RECEIVED
    raw_payload: Optional[Dict[str, Any]] = None
    schema_version: int = 1
    created_at: datetime


# ==============================================================================
# ENTITLEMENT & USAGE SCHEMAS
# ==============================================================================

class EntitlementGrant(BaseModel):
    """
    Effective permission granted to a user for a specific capability.
    Decoupled from subscription financial status.
    """
    grant_id: str
    user_id: str
    benefit_id: str = Field(..., description="Stable dot-notated benefit ID, e.g. ai.nutrition_gemini")
    status: EntitlementStatus = EntitlementStatus.GRANTED
    source_type: str = Field("subscription", description="subscription | staff_override | default_free | trial")
    source_subscription_id: Optional[str] = None
    valid_from: datetime
    valid_until: Optional[datetime] = None
    schema_version: int = 1
    created_at: datetime
    updated_at: datetime


class UsageBucket(BaseModel):
    """
    Metered usage allowance tracking for a specific capability in a billing cycle.
    """
    bucket_id: str
    user_id: str
    benefit_id: str
    period_key: str = Field(..., description="Format YYYYMMDD or YYYYMM matching billing cycle anchor")
    limit_units: int = Field(..., ge=0)
    consumed_units: int = Field(0, ge=0)
    reserved_units: int = Field(0, ge=0)
    reset_at: datetime
    schema_version: int = 1
    created_at: datetime
    updated_at: datetime

    @property
    def remaining_units(self) -> int:
        return max(0, self.limit_units - (self.consumed_units + self.reserved_units))


class UsageOperation(BaseModel):
    """
    Single in-flight or completed reservation record for an AI operation.
    Permanent billing/quota audit log.
    Canonical idempotency identity: (user_id, benefit_id, idempotency_key).
    """
    operation_id: str
    user_id: str
    bucket_id: str
    benefit_id: str
    idempotency_key: str = Field(..., description="Client-provided or canonical idempotency key.")
    client_request_id: Optional[str] = Field(None, description="Raw client request ID / UUID.")
    request_hash: Optional[str] = Field(
        None,
        description="SHA-256 fingerprint of normalized request parameters to detect payload mismatch."
    )
    lease_token: Optional[str] = Field(None, description="Active worker lease token for CAS updates.")
    dispatched: bool = Field(False, description="True if provider dispatch was attempted.")
    dispatched_at: Optional[datetime] = None
    error_reason: Optional[str] = None
    response_summary: Optional[Dict[str, Any]] = Field(None, description="Brief non-sensitive execution summary.")
    units: int = Field(1, ge=1)
    status: UsageOpStatus = UsageOpStatus.RESERVED
    schema_version: int = 1
    created_at: datetime
    expires_at: datetime


class IdempotencyCacheRecord(BaseModel):
    """
    Short-term result cache record for idempotent retries.
    Decoupled from UsageOperation (which is the permanent billing/quota audit log).
    Enforces user isolation: (user_id, client_request_id).
    """
    user_id: str
    client_request_id: str
    benefit_id: str
    request_hash: str = Field(..., description="SHA-256 hex digest of request payload.")
    operation_id: Optional[str] = None
    status: str = Field("completed", description="processing | completed | failed")
    response_payload: Optional[Dict[str, Any]] = None
    created_at: datetime
    expires_at: datetime


# ==============================================================================
# EVALUATION & RESERVATION DECISION SCHEMAS (CP-04)
# ==============================================================================

class EntitlementDecision(BaseModel):
    """
    Typed result of evaluating an entitlement for an authenticated user and benefit.
    """
    status: EntitlementDecisionStatus
    user_id: str
    benefit_id: str
    tier: Optional[MembershipTier] = None
    source: Optional[str] = None  # "staff_override" | "subscription" | "default_free"
    valid_until: Optional[datetime] = None
    reason: Optional[str] = None


class ReservationResult(BaseModel):
    """
    Typed result of atomic quota reservation attempt.
    """
    status: ReservationStatus
    operation_id: Optional[str] = None
    lease_token: Optional[str] = None
    bucket_id: Optional[str] = None
    units: int = 1
    consumed_units: Optional[int] = None
    remaining_units: Optional[int] = None
    limit_units: Optional[int] = None
    cached_payload: Optional[Dict[str, Any]] = None
    error_message: Optional[str] = None


class BenefitUsageSummary(BaseModel):
    benefit_id: str
    consumed_units: int
    reserved_units: int
    remaining_units: Optional[int] = None
    limit_units: Optional[int] = None
    period_key: str
    reset_at: Optional[datetime] = None


class AccountMembershipSummary(BaseModel):
    user_id: str
    account_id: Optional[str] = None
    tier: MembershipTier = MembershipTier.FREE
    status: str = "none"  # "none" | "active" | "trialing" | "expired"
    is_active_subscription: bool = False
    current_period_end: Optional[datetime] = None
    auto_renew_status: bool = True
    in_grace_period: bool = False
    grace_period_expires_at: Optional[datetime] = None
    cancel_at_period_end: bool = False
    ownership_status: Optional[str] = None
    opaque_app_user_id: Optional[str] = None
    entitlements: List[Dict[str, Any]] = Field(default_factory=list)
    usage: Dict[str, BenefitUsageSummary] = Field(default_factory=dict)
    as_of: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ProviderCustomerMapping(BaseModel):
    """
    Server-owned random provider customer mapping (REVENUE-R02A).
    Invariants:
    - Bound to immutable internal account_id and scoped by (provider, project_id).
    - Never derived from email or hash of email.
    - Immutable once created for (provider, project_id, account_id).
    """
    model_config = ConfigDict(frozen=True)

    mapping_id: str
    provider: PaymentProviderName = PaymentProviderName.REVENUECAT
    project_id: str
    account_id: str
    app_user_id: str
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


# ==============================================================================
# PAYMENT BOUNDARY, PROVIDER ADAPTER & EVENT SCHEMAS (CP-07)
# ==============================================================================

class StoreProductMapping(BaseModel):
    """
    Canonical internal mapping from a store SKU to internal Saman catalog & benefit policy.
    Scoped strictly by (provider, environment, app_id, product_id).
    Immutable value object.
    """
    model_config = ConfigDict(frozen=True)

    provider: PaymentProviderName
    environment: PaymentEnvironment
    app_id: str = Field(..., min_length=1, description="Verified bundleId or packageName")
    product_id: str = Field(..., min_length=1, description="Store product SKU identifier")
    catalog_version: str = Field("v1.0-preview")
    plan_id: str
    price_id: str
    tier: MembershipTier
    period: BillingPeriod = BillingPeriod.MONTHLY
    amount_cents: int = Field(..., ge=0)
    currency: str = Field("USD", min_length=3, max_length=3)
    benefit_ids: List[str] = Field(default_factory=list)
    quota_limits: Dict[str, int] = Field(default_factory=dict)
    enabled: bool = Field(
        False,
        description="Must be False until commercial provider & store SKUs are approved.",
    )


class PurchaseVerificationRequest(BaseModel):
    """
    Untrusted client purchase verification request payload.
    Invariants:
    - Authenticated user_id is ALWAYS resolved from JWT (verify_token), never from client payload.
    - Any client-supplied tier, price, expiry, or user_id is untrusted and cannot grant rights.
    """
    provider: PaymentProviderName
    environment: PaymentEnvironment = PaymentEnvironment.SANDBOX
    app_id: str = Field(..., min_length=1)
    product_id: str = Field(..., min_length=1)
    verification_token: str = Field(..., description="Opaque store receipt or purchase token")
    transaction_id: Optional[str] = None
    original_transaction_id: Optional[str] = None
    client_request_id: Optional[str] = None
    idempotency_key: Optional[str] = None
    # Untrusted fields optionally sent by buggy/malicious clients — captured only to reject or strip
    user_id: Optional[str] = None
    tier: Optional[MembershipTier] = None
    amount_cents: Optional[int] = None
    expires_date: Optional[datetime] = None


class VerifiedProviderTransaction(BaseModel):
    """
    Normalized, cryptographically/server-verified transaction result produced ONLY
    by a trusted IPaymentProviderAdapter boundary.
    Immutable value object.
    """
    model_config = ConfigDict(frozen=True)

    provider: PaymentProviderName
    environment: PaymentEnvironment
    app_id: str
    product_id: str
    transaction_id: str
    original_transaction_id: str
    verification_status: ProviderVerificationStatus
    purchase_date: datetime
    expires_date: datetime
    provider_event_id: Optional[str] = None
    raw_payload_hash: str = Field(..., min_length=10, description="SHA-256 hash of raw receipt/token; never raw secret.")
    grace_period_expires_date: Optional[datetime] = None
    unsubscribe_detected_at: Optional[datetime] = None
    billing_issues_detected_at: Optional[datetime] = None
    refunded_at: Optional[datetime] = None
    store: Optional[str] = None
    period_type: Optional[str] = None
    error_code: Optional[str] = None
    error_message: Optional[str] = None


class VerifiedWebhookEvent(BaseModel):
    """
    Normalized, authenticated server-to-server webhook event produced ONLY
    by a trusted IPaymentProviderAdapter webhook verifier.
    Immutable value object.
    """
    model_config = ConfigDict(frozen=True)

    event_id: str
    provider: PaymentProviderName
    environment: PaymentEnvironment
    event_type: str
    event_timestamp: datetime
    user_id: Optional[str] = None
    transaction: VerifiedProviderTransaction
    raw_payload_hash: str = Field(..., min_length=10)
    cancel_reason: Optional[str] = None
    expiration_reason: Optional[str] = None
    grace_period_expires_date: Optional[datetime] = None
    project_id: Optional[str] = None
    store: Optional[str] = None
    period_type: Optional[str] = None
    transferred_from: Optional[List[str]] = None
    transferred_to: Optional[List[str]] = None
    aliases: Optional[List[str]] = None


class PurchaseVerificationResponse(BaseModel):
    """
    Authoritative backend response for purchase verification.
    """
    outcome: PurchaseVerificationOutcomeStatus
    user_id: str
    provider: PaymentProviderName
    environment: PaymentEnvironment
    transaction_id: Optional[str] = None
    original_transaction_id: Optional[str] = None
    subscription_id: Optional[str] = None
    tier: MembershipTier = MembershipTier.FREE
    is_active_subscription: bool = False
    current_period_end: Optional[datetime] = None
    duplicate_ignored: bool = False
    error_code: Optional[str] = None
    message: str = ""


# ==============================================================================
# RESTORE & SUBSCRIPTION LIFECYCLE SCHEMAS (CP-08)
# ==============================================================================

class RestorePurchasesRequest(BaseModel):
    """
    Untrusted client request to restore purchases across store tokens.
    Authenticated user_id is ALWAYS taken from JWT auth, never from client body.
    """
    provider: PaymentProviderName
    environment: PaymentEnvironment = PaymentEnvironment.SANDBOX
    app_id: str = Field(..., min_length=1)
    verification_token: str = Field(..., description="Opaque store receipt or purchase token")
    transaction_id: Optional[str] = None
    original_transaction_id: Optional[str] = None
    client_request_id: Optional[str] = None
    idempotency_key: Optional[str] = None
    # Untrusted fields sent by clients (captured to reject explicit spoofing):
    user_id: Optional[str] = None


class RestorePurchasesResponse(BaseModel):
    """
    Authoritative backend response for purchase restore.
    """
    outcome: PurchaseVerificationOutcomeStatus
    user_id: str
    provider: PaymentProviderName
    environment: PaymentEnvironment
    ownership_status: ReceiptOwnershipStatus
    transaction_id: Optional[str] = None
    original_transaction_id: Optional[str] = None
    subscription_id: Optional[str] = None
    tier: MembershipTier = MembershipTier.FREE
    is_active_subscription: bool = False
    current_period_end: Optional[datetime] = None
    auto_renew_status: bool = True
    in_grace_period: bool = False
    grace_period_expires_at: Optional[datetime] = None
    restored_grants_count: int = 0
    duplicate_ignored: bool = False
    first_owner_policy: str = "PROPOSED"
    error_code: Optional[str] = None
    message: str = ""


# ==============================================================================
# RECONCILIATION & AUDITED OPERATIONS SCHEMAS (CP-10)
# ==============================================================================

class ReconciliationFindingType(str, Enum):
    UNPROJECTED_EVENT = "unprojected_event"
    EXPIRED_GRANT_ACTIVE = "expired_grant_active"
    SUBSCRIPTION_GRANT_MISMATCH = "subscription_grant_mismatch"
    OWNERSHIP_CONFLICT = "ownership_conflict"
    UNKNOWN_PRODUCT_MAPPING = "unknown_product_mapping"
    NEGATIVE_QUOTA_COUNTER = "negative_quota_counter"
    STRANDED_RESERVATION = "stranded_reservation"
    OPERATION_BUCKET_MISMATCH = "operation_bucket_mismatch"
    UNKNOWN_OPERATION_REQUIRING_EVIDENCE = "unknown_operation_requiring_evidence"


class ReconciliationSeverity(str, Enum):
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"


class ReconciliationActionType(str, Enum):
    REPROJECT_EVENT = "reproject_event"
    EXPIRE_GRANT = "expire_grant"
    RECLAIM_RESERVATION = "reclaim_reservation"
    ADJUST_QUOTA_BUCKET = "adjust_quota_bucket"
    SYNCHRONIZE_GRANT_STATE = "synchronize_grant_state"
    REQUIRES_MANUAL_REVIEW = "requires_manual_review"
    NOOP = "noop"


class ReconciliationFinding(BaseModel):
    """
    Structured discrepancy finding generated by the ReconciliationScanner.
    Invariants:
    - Never stores raw sensitive receipt tokens, prompts, or personal health payloads.
    - Captures deterministic precondition expressions for safe Compare-And-Swap (CAS) execution.
    """
    finding_id: str = Field(..., description="Unique deterministic finding identifier.")
    finding_type: ReconciliationFindingType
    severity: ReconciliationSeverity
    entity_type: str = Field(..., description="Target collection entity: event | grant | subscription | bucket | operation")
    entity_id: str = Field(..., description="Unique identifier of affected record.")
    user_id: Optional[str] = None
    description: str = Field(..., description="Human-readable explanation of discrepancy.")
    evidence_references: Dict[str, Any] = Field(default_factory=dict, description="Redacted audit evidence references (hashes only).")
    proposed_action: ReconciliationActionType = ReconciliationActionType.NOOP
    requires_manual_review: bool = False
    precondition: Optional[Dict[str, Any]] = Field(None, description="CAS predicate: current state required for safe apply.")
    detected_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ReconciliationPlanStatus(str, Enum):
    DRAFT = "draft"
    APPLYING = "applying"
    APPLIED = "applied"
    FAILED = "failed"
    ABORTED = "aborted"


class ReconciliationPlan(BaseModel):
    """
    Dry-run reconciliation plan with versioning, timestamps, scope, and expected outcome.
    Invariants:
    - Default mode is read-only / dry-run.
    - Applying a plan requires explicit operator invocation with CAS precondition checks.
    """
    plan_id: str
    version: int = 1
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    status: ReconciliationPlanStatus = ReconciliationPlanStatus.DRAFT
    scope: Dict[str, Any] = Field(default_factory=dict, description="Query scope filters applied during scan.")
    total_findings: int = 0
    actionable_count: int = 0
    manual_review_count: int = 0
    findings: List[ReconciliationFinding] = Field(default_factory=list)
    expected_state: Dict[str, Any] = Field(default_factory=dict, description="Summary of prospective mutations.")
    applied_at: Optional[datetime] = None
    applied_by: Optional[str] = None


class ReconciliationApplyResult(BaseModel):
    """
    Execution summary returned after applying a reconciliation plan.
    """
    plan_id: str
    status: ReconciliationPlanStatus
    total_actions: int = 0
    applied_actions: int = 0
    aborted_actions: int = 0
    failed_actions: int = 0
    manual_review_items: int = 0
    action_details: List[Dict[str, Any]] = Field(default_factory=list)
    duration_seconds: float = 0.0


# ==============================================================================
# AUDITED MANUAL GRANT & REVOCATION SCHEMAS (CP-10)
# ==============================================================================

class ManualGrantAuditStatus(str, Enum):
    REQUESTED = "requested"
    APPLIED = "applied"
    FAILED = "failed"


class ManualGrantRequest(BaseModel):
    """
    Audited manual entitlement grant request.
    Invariants:
    - Requires explicit idempotency key and actor identity.
    - Permanent grants are strictly prohibited: valid_until must be explicitly provided.
    - Does NOT create fake payment transactions or subscriptions.
    - Does NOT reset or alter quota counters.
    """
    idempotency_key: str = Field(..., min_length=8, description="Mandatory unique client/operator idempotency key.")
    actor: str = Field(..., min_length=2, description="Identity of operator/staff executing grant.")
    target_user_id: str = Field(..., min_length=1, description="Target recipient user ID.")
    benefit_id: str = Field(..., min_length=1, description="Catalog dot-notated benefit ID.")
    valid_from: Optional[datetime] = Field(None, description="Start of validity. Defaults to UTC now.")
    valid_until: datetime = Field(..., description="Mandatory finite expiration timestamp. Permanent grants are forbidden.")
    reason: str = Field(..., min_length=5, description="Business justification (e.g. VIP goodwill, incident compensation).")
    ticket_reference: str = Field(..., min_length=3, description="Support ticket or incident identifier (e.g. TICKET-1042).")
    metadata: Dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_time_window(self) -> "ManualGrantRequest":
        start = self.valid_from or datetime.now(timezone.utc)
        if self.valid_until <= start:
            raise ValueError("valid_until must be strictly in the future of valid_from.")
        return self


class ManualGrantRevokeRequest(BaseModel):
    """
    Audited manual entitlement revocation request.
    Invariants:
    - Targets a specific grant_id; never affects independent grants or payment transactions.
    - Requires operator identity, reason, ticket reference, and idempotency key.
    """
    idempotency_key: str = Field(..., min_length=8)
    actor: str = Field(..., min_length=2)
    target_grant_id: str = Field(..., min_length=1)
    reason: str = Field(..., min_length=5)
    ticket_reference: str = Field(..., min_length=3)


class ManualGrantAuditRecord(BaseModel):
    """
    Append-only audit trail entry for manual entitlement mutations.
    Invariants:
    - Tracks two-phase state: REQUESTED -> APPLIED / FAILED.
    - Captures before_state and after_state snapshots.
    - Hard deletion is strictly prohibited.
    """
    audit_id: str
    idempotency_key: str
    action: str = Field(..., description="GRANT or REVOKE")
    actor: str
    target_user_id: str
    target_grant_id: Optional[str] = None
    benefit_id: Optional[str] = None
    reason: str
    ticket_reference: str
    status: ManualGrantAuditStatus = ManualGrantAuditStatus.REQUESTED
    before_state: Optional[Dict[str, Any]] = None
    after_state: Optional[Dict[str, Any]] = None
    error_reason: Optional[str] = None
    request_hash: str = Field(..., min_length=10, description="SHA-256 hash of canonical request parameters.")
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


