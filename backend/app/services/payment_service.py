"""
Saman Revenue — Payment Integration Boundary, Settlement & Internal Webhook Contract (CP-07).

Invariants Enforced:
1. No payment provider is assumed or selected on behalf of the user (default adapter is
   UnconfiguredPaymentProviderAdapter which fails closed with PaymentConfigurationNotReadyError).
2. Untrusted client inputs (user_id, tier, amount_cents, expiry, entitlement claims) are strictly
   separated from verified provider transaction data. Client claims NEVER grant entitlements.
3. Strict 4-tuple mapping:
     (provider, environment, app_id, product_id) -> StoreProductMapping
   Unknown product, wrong app_id, wrong environment (sandbox vs production), or disabled mappings
   are rejected before any durable entitlement projection.
4. Preview/demo catalog items do not become commercially active unless explicitly enabled.
5. Receipt ownership is bound to (provider, environment, original_transaction_id). Silent receipt
   transfer across accounts is forbidden (raises ReceiptOwnershipConflictError -> HTTP 409).
6. Durable Write-Ahead Event + Crash-Recoverable Projection:
   - Every verified purchase/webhook writes a durable ProviderEvent with processing_status='received'
     and normalized projection snapshot BEFORE projecting Subscription, EntitlementGrant, and UsageBucket.
   - ProviderEvent transitions to processing_status='processed' ONLY after all projections succeed.
   - If a crash or storage failure occurs after event persistence and before projection completes,
     reconcile_incomplete_payment_events() or a retry of the same event/transaction safely resumes
     and completes the projection without double-granting.
7. Raw secrets, API keys, and raw receipt payloads are NEVER logged or stored in plaintext
   (only SHA-256 hashes of raw verification payloads are stored).
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from datetime import datetime, timezone, timedelta
import hashlib
import logging
import os
from typing import Optional, Dict, Any, List, Tuple

from backend.app.models.revenue import (
    BillingPeriod,
    PaymentProviderName,
    PaymentEnvironment,
    ProviderVerificationStatus,
    PurchaseVerificationOutcomeStatus,
    StoreProductMapping,
    PurchaseVerificationRequest,
    VerifiedProviderTransaction,
    VerifiedWebhookEvent,
    PurchaseVerificationResponse,
    MembershipTier,
    SubscriptionStatus,
    EntitlementStatus,
    SubscriptionLifecycleEventType,
    ReceiptOwnershipStatus,
    GracePeriodPolicy,
    RestorePurchasesRequest,
    RestorePurchasesResponse,
)
from backend.app.database_revenue import (
    COLL_PROVIDER_EVENTS,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_SUBSCRIPTIONS,
    COLL_ENTITLEMENT_GRANTS,
    COLL_USAGE_BUCKETS,
)
from backend.app.services.quota_service import QuotaService, StorageUnavailableException

logger = logging.getLogger(__name__)


# ==============================================================================
# 1. Domain Exceptions
# ==============================================================================

class PaymentBoundaryError(Exception):
    """Base exception for payment boundary errors."""

    def __init__(self, code: str, message: str, http_status: int = 400):
        super().__init__(message)
        self.code = code
        self.message = message
        self.http_status = http_status


class PaymentConfigurationNotReadyError(PaymentBoundaryError):
    """Raised when payment provider or product mapping is not configured/enabled."""

    def __init__(self, message: str = "Payment provider or product mapping is not configured."):
        super().__init__(
            code="PAYMENT_CONFIG_NOT_READY",
            message=message,
            http_status=503,
        )


class UnverifiedPurchasePayloadError(PaymentBoundaryError):
    """Raised when client purchase payload lacks verification token or fails provider verification."""

    def __init__(self, code: str = "UNVERIFIED_PURCHASE_PAYLOAD", message: str = "Purchase verification failed."):
        super().__init__(code=code, message=message, http_status=400)


class ProductMappingRejectedError(PaymentBoundaryError):
    """Raised when (provider, environment, app_id, product_id) is unknown, mismatched, or disabled."""

    def __init__(self, code: str, message: str, http_status: int = 422):
        super().__init__(code=code, message=message, http_status=http_status)


class ReceiptOwnershipConflictError(PaymentBoundaryError):
    """
    Raised when an original_transaction_id is already bound to a different user account.
    CP-08 Invariants:
    - Separates ownership conflict detection from transfer decision.
    - Classifies first-owner policy as PROPOSED (not unilaterally decided).
    - Unresolved conflict does NOT transfer ownership or grant entitlement to another account.
    """

    def __init__(
        self,
        message: str = "This purchase receipt is already bound to another account.",
        ownership_status: str = "unresolved_conflict",
        first_owner_policy: str = "PROPOSED",
    ):
        super().__init__(
            code="RECEIPT_OWNERSHIP_CONFLICT",
            message=message,
            http_status=409,
        )
        self.ownership_status = ownership_status
        self.first_owner_policy = first_owner_policy


class ClientIdentityMismatchError(PaymentBoundaryError):
    """Raised when client supplies user_id differing from authenticated JWT user (HTTP 403)."""

    def __init__(self, message: str = "Client-supplied user_id does not match authenticated user session."):
        super().__init__(
            code="USER_IDENTITY_MISMATCH",
            message=message,
            http_status=403,
        )


class WebhookVerificationError(PaymentBoundaryError):
    """Raised when an incoming webhook fails signature/auth, schema, or environment validation."""

    def __init__(self, code: str = "WEBHOOK_VERIFICATION_FAILED", message: str = "Webhook verification failed.", http_status: int = 401):
        super().__init__(code=code, message=message, http_status=http_status)


class PaymentStorageError(PaymentBoundaryError):
    """Raised when durable persistence or projection fails due to storage error."""

    def __init__(self, message: str = "Durable payment persistence failed."):
        super().__init__(
            code="PAYMENT_STORAGE_UNAVAILABLE",
            message=message,
            http_status=503,
        )


def hash_sensitive_payload(raw_value: str) -> str:
    """Computes a one-way SHA-256 hash of a raw receipt/token/webhook payload (never logs raw value)."""
    normalized = (raw_value or "").encode("utf-8")
    return f"sha256:{hashlib.sha256(normalized).hexdigest()}"


# ==============================================================================
# 2. Typed Provider Adapter Interface & Unconfigured Default
# ==============================================================================

class IPaymentProviderAdapter(ABC):
    """
    Trusted boundary interface for verifying store purchases and webhook events
    against an external payment provider (e.g., Apple App Store Server API,
    Google Play Developer API, RevenueCat, or Stripe).
    """

    @property
    @abstractmethod
    def provider_name(self) -> PaymentProviderName:
        """Canonical provider name handled by this adapter."""

    @abstractmethod
    def is_configured(self) -> bool:
        """Returns True only if provider credentials and runtime settings are ready."""

    @abstractmethod
    def verify_purchase(
        self,
        request: PurchaseVerificationRequest,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedProviderTransaction:
        """
        Contacts the authoritative provider (or validates cryptographic JWS) to verify
        a client purchase proof. Must never trust client-supplied tier/price/expiry.
        """

    @abstractmethod
    def verify_and_parse_webhook(
        self,
        headers: Dict[str, str],
        raw_body: bytes,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedWebhookEvent:
        """
        Authenticates and parses an incoming provider webhook using the provider's
        official verification mechanism (e.g., JWS certificate chain, OIDC token,
        or provider-specific Authorization/signature header).
        """


class UnconfiguredPaymentProviderAdapter(IPaymentProviderAdapter):
    """
    Default fail-closed adapter used while the payment provider decision (CP-01 Decision 2)
    is still pending human approval or credentials are not provisioned.
    """

    def __init__(self, provider: PaymentProviderName = PaymentProviderName.UNCONFIGURED):
        self._provider = provider

    @property
    def provider_name(self) -> PaymentProviderName:
        return self._provider

    def is_configured(self) -> bool:
        return False

    def verify_purchase(
        self,
        request: PurchaseVerificationRequest,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedProviderTransaction:
        raise PaymentConfigurationNotReadyError(
            "No payment provider has been approved or configured for runtime purchase verification."
        )

    def verify_and_parse_webhook(
        self,
        headers: Dict[str, str],
        raw_body: bytes,
        expected_environment: PaymentEnvironment,
        expected_app_id: str,
    ) -> VerifiedWebhookEvent:
        raise PaymentConfigurationNotReadyError(
            "No payment provider has been approved or configured for webhook ingestion."
        )


# ==============================================================================
# 3. Store Product Mapping Registry
# ==============================================================================

def build_default_revenuecat_mappings(
    environment: PaymentEnvironment = PaymentEnvironment.SANDBOX,
    app_id: str = "com.saman.health",
    enabled: bool = False,
    unapproved_test_quota_limits: Optional[Dict[MembershipTier, Dict[str, int]]] = None,
) -> List[StoreProductMapping]:
    """
    Returns canonical RevenueCat store product mappings for Saman tiers.
    REVENUE-R02A / REVENUE-R03 Invariants:
    - Commercial pricing and quota limits (100/300) are NOT business-approved.
    - By default (`enabled=False`, `unapproved_test_quota_limits=None`), `quota_limits` is empty `{}`.
    - Tests verifying quota projection mechanics must explicitly pass `unapproved_test_quota_limits`.
    - Canonical tier SKUs (`saman_plus_monthly`, `saman_pro_monthly`, etc.) work across both
      RevenueCat Test Store (`store == 'TEST_STORE'`, `purchases_flutter >= 9.8.0` / `9.16.2`)
      and Google Play / App Store sandboxes when configured in `SANDBOX` environment.
    """
    from backend.app.services.revenuecat_adapter import (
        build_default_revenuecat_mappings as _build_rc_mappings,
    )

    return _build_rc_mappings(
        environment=environment,
        app_id=app_id,
        enabled=enabled,
        unapproved_test_quota_limits=unapproved_test_quota_limits,
    )


class ProductMappingRegistry:
    """
    Maps (provider, environment, app_id, product_id) -> StoreProductMapping.
    Enforces that:
    - Arbitrary tiers or quotas from client/webhook are never accepted.
    - Sandbox and production product mappings are strictly isolated.
    - Preview catalog definitions remain non-purchasable (enabled=False) by default
      until human approval and store product setup are completed.
    """

    def __init__(
        self,
        mappings: Optional[List[StoreProductMapping]] = None,
        expected_environment: Optional[PaymentEnvironment] = None,
        allowed_app_ids: Optional[List[str]] = None,
    ):
        env_raw = os.environ.get("REVENUE_PAYMENT_ENVIRONMENT", "sandbox").strip().lower()
        if expected_environment is not None:
            self.expected_environment = expected_environment
        elif env_raw == "production":
            self.expected_environment = PaymentEnvironment.PRODUCTION
        else:
            self.expected_environment = PaymentEnvironment.SANDBOX

        if allowed_app_ids is not None:
            self.allowed_app_ids = set(allowed_app_ids)
        else:
            configured_apps = os.environ.get("REVENUE_ALLOWED_APP_IDS", "").strip()
            self.allowed_app_ids = (
                {a.strip() for a in configured_apps.split(",") if a.strip()}
                if configured_apps
                else set()
            )

        self._mappings: Dict[Tuple[str, str, str, str], StoreProductMapping] = {}
        if mappings:
            for m in mappings:
                self.register(m)

    def register_revenuecat_defaults(
        self,
        environment: Optional[PaymentEnvironment] = None,
        app_id: str = "com.saman.health",
        enabled: bool = False,
        unapproved_test_quota_limits: Optional[Dict[MembershipTier, Dict[str, int]]] = None,
    ) -> None:
        target_env = environment or self.expected_environment
        defaults = build_default_revenuecat_mappings(
            environment=target_env,
            app_id=app_id,
            enabled=enabled,
            unapproved_test_quota_limits=unapproved_test_quota_limits,
        )
        for m in defaults:
            self.register(m)

    @staticmethod
    def _key(
        provider: PaymentProviderName,
        environment: PaymentEnvironment,
        app_id: str,
        product_id: str,
    ) -> Tuple[str, str, str, str]:
        p_val = provider.value if isinstance(provider, PaymentProviderName) else str(provider)
        e_val = environment.value if isinstance(environment, PaymentEnvironment) else str(environment)
        return (p_val, e_val, app_id.strip(), product_id.strip())

    def register(self, mapping: StoreProductMapping) -> None:
        key = self._key(mapping.provider, mapping.environment, mapping.app_id, mapping.product_id)
        self._mappings[key] = mapping

    def has_enabled_mappings(self) -> bool:
        return any(m.enabled for m in self._mappings.values())

    def resolve(
        self,
        provider: PaymentProviderName,
        environment: PaymentEnvironment,
        app_id: str,
        product_id: str,
    ) -> StoreProductMapping:
        """
        Resolves and validates the internal catalog/benefit policy for a verified store product.
        Raises ProductMappingRejectedError or PaymentConfigurationNotReadyError on any mismatch.
        """
        if environment != self.expected_environment:
            raise ProductMappingRejectedError(
                code="PAYMENT_ENVIRONMENT_MISMATCH",
                message=(
                    f"Environment mismatch: transaction is '{environment.value}' "
                    f"but server expects '{self.expected_environment.value}'."
                ),
                http_status=422,
            )

        if self.allowed_app_ids and app_id not in self.allowed_app_ids:
            raise ProductMappingRejectedError(
                code="PAYMENT_APP_ID_MISMATCH",
                message=f"App/store scope '{app_id}' is not authorized for this backend.",
                http_status=422,
            )

        if not self._mappings:
            raise PaymentConfigurationNotReadyError(
                "Store product mappings are not yet configured (catalog remains in preview mode)."
            )

        key = self._key(provider, environment, app_id, product_id)
        mapping = self._mappings.get(key)
        if mapping is None:
            # Check if product_id exists under a different app_id or environment to return a specific code
            for (p_k, e_k, app_k, prod_k), m_val in self._mappings.items():
                if p_k == provider.value and prod_k == product_id and app_k != app_id:
                    raise ProductMappingRejectedError(
                        code="PAYMENT_APP_ID_MISMATCH",
                        message=f"Product '{product_id}' is not registered under app scope '{app_id}'.",
                        http_status=422,
                    )
            raise ProductMappingRejectedError(
                code="UNKNOWN_STORE_PRODUCT",
                message=f"Unknown store product '{product_id}' for provider '{provider.value}' in '{environment.value}'.",
                http_status=422,
            )

        if not mapping.enabled:
            raise PaymentConfigurationNotReadyError(
                f"Store product '{product_id}' mapping is disabled (commercial sales are not active)."
            )

        return mapping


# ==============================================================================
# 4. Payment Settlement & Crash-Recoverable Projection Service
# ==============================================================================

class PaymentSettlementService:
    """
    Coordinates purchase verification, durable event/transaction logging, and
    crash-recoverable subscription + entitlement + quota projection.
    """

    def __init__(
        self,
        db=None,
        adapter: Optional[IPaymentProviderAdapter] = None,
        mapping_registry: Optional[ProductMappingRegistry] = None,
    ):
        self._db = db
        self._adapter = adapter or UnconfiguredPaymentProviderAdapter()
        self._mapping_registry = mapping_registry or ProductMappingRegistry()

    def _get_db(self):
        if self._db is not None:
            return self._db
        try:
            from backend.database import db as global_db
            return global_db
        except ImportError:
            return None

    def verify_and_settle_purchase(
        self,
        authenticated_user_id: str,
        request: PurchaseVerificationRequest,
        as_of: Optional[datetime] = None,
    ) -> PurchaseVerificationResponse:
        """
        Executes the authoritative purchase verification and projection workflow:
          1. Rejects client identity spoofing (if client supplied user_id != authenticated_user_id)
             and ignores all untrusted client fields (tier, amount_cents, expiry, entitlements).
          2. Rejects empty/missing verification tokens before calling provider.
          3. Ensures provider adapter and product mapping registry are configured.
          4. Verifies purchase proof via trusted IPaymentProviderAdapter.
          5. Validates verified (provider, environment, app_id, product_id) against ProductMappingRegistry.
          6. Checks receipt ownership binding on (provider, environment, original_transaction_id).
          7. Writes durable ProviderEvent (write-ahead log) with projection snapshot.
          8. Runs idempotent, crash-recoverable projection for Transaction, Subscription,
             EntitlementGrant, and UsageBucket.
        """
        now = as_of or datetime.now(timezone.utc)
        if not authenticated_user_id or not authenticated_user_id.strip():
            raise UnverifiedPurchasePayloadError(
                code="UNAUTHENTICATED_USER",
                message="Authenticated user identity is required for purchase verification.",
            )

        # Invariant: Never trust client-supplied user_id; reject explicit spoofing attempts
        if request.user_id and request.user_id.strip() != authenticated_user_id.strip():
            raise ClientIdentityMismatchError()

        if not request.verification_token or not request.verification_token.strip():
            raise UnverifiedPurchasePayloadError(
                code="MISSING_VERIFICATION_TOKEN",
                message="Verification token / store receipt proof is required.",
            )

        if (
            request.provider == PaymentProviderName.UNCONFIGURED
            or not self._adapter.is_configured()
        ):
            raise PaymentConfigurationNotReadyError(
                "Payment provider integration is not yet configured or approved."
            )

        if request.provider != self._adapter.provider_name:
            raise PaymentConfigurationNotReadyError(
                f"Requested provider '{request.provider.value}' does not match configured adapter '{self._adapter.provider_name.value}'."
            )

        db = self._get_db()
        if db is None:
            raise PaymentStorageError("Revenue database connection is unavailable.")

        # Pre-validate request environment before invoking provider adapter
        if request.environment != self._mapping_registry.expected_environment:
            raise ProductMappingRejectedError(
                code="PAYMENT_ENVIRONMENT_MISMATCH",
                message=(
                    f"Request environment '{request.environment.value}' does not match "
                    f"server environment '{self._mapping_registry.expected_environment.value}'."
                ),
                http_status=422,
            )

        clean_user = authenticated_user_id.strip()
        target_account_id = clean_user

        if request.provider == PaymentProviderName.REVENUECAT:
            from backend.app.services.revenuecat_adapter import (
                is_legacy_r02_opaque_user_id,
                is_valid_revenuecat_app_user_id,
                resolve_account_id_from_provider_customer_id,
                resolve_or_create_account_id,
                resolve_or_create_provider_customer_id,
            )

            if is_legacy_r02_opaque_user_id(request.verification_token):
                raise UnverifiedPurchasePayloadError(
                    code="LEGACY_R02_IDENTITY_MIGRATION_REQUIRED",
                    message="Legacy R02 email-hash App User ID is disabled in REVENUE-R02A.",
                )

            target_account_id = resolve_or_create_account_id(db, clean_user)

            # Check receipt ownership on client-supplied original_transaction_id before remote call if present
            if request.original_transaction_id:
                self._assert_receipt_ownership(
                    db=db,
                    user_id=target_account_id,
                    provider=request.provider,
                    environment=request.environment,
                    original_transaction_id=request.original_transaction_id,
                )

            proj_id = getattr(self._adapter, "expected_project_id", None)
            expected_rc_id = resolve_or_create_provider_customer_id(
                db, target_account_id, project_id=proj_id
            )
            token_clean = request.verification_token.strip()
            if is_valid_revenuecat_app_user_id(token_clean):
                mapped_owner = resolve_account_id_from_provider_customer_id(
                    db, token_clean, project_id=proj_id
                )
                if mapped_owner is not None and mapped_owner != target_account_id:
                    raise ClientIdentityMismatchError(
                        "RevenueCat customer ID belongs to a different Saman account."
                    )
                if token_clean != expected_rc_id:
                    raise ClientIdentityMismatchError(
                        "RevenueCat customer ID does not match the server-assigned mapping for this account."
                    )

        # Verify with trusted provider adapter
        verified_tx = self._adapter.verify_purchase(
            request=request,
            expected_environment=self._mapping_registry.expected_environment,
            expected_app_id=request.app_id,
        )
        verified_tx = self._resolve_existing_subscription_lineage(db, verified_tx)

        resp = self._process_verified_transaction(
            db=db,
            authenticated_user_id=target_account_id,
            verified_tx=verified_tx,
            event_id=verified_tx.provider_event_id or f"evt_verify_{verified_tx.provider.value}_{verified_tx.environment.value}_{verified_tx.transaction_id}",
            event_type="purchase.verify",
            event_timestamp=verified_tx.purchase_date or now,
            as_of=now,
        )
        if resp.user_id != clean_user:
            resp = resp.model_copy(update={"user_id": clean_user})
        return resp

    def _process_verified_transaction(
        self,
        db,
        authenticated_user_id: str,
        verified_tx: VerifiedProviderTransaction,
        event_id: str,
        event_type: str,
        event_timestamp: datetime,
        as_of: datetime,
    ) -> PurchaseVerificationResponse:
        # 1. Handle non-granting verification statuses first
        if verified_tx.verification_status == ProviderVerificationStatus.INVALID:
            raise UnverifiedPurchasePayloadError(
                code=verified_tx.error_code or "PROVIDER_VERIFICATION_INVALID",
                message=verified_tx.error_message or "Provider rejected purchase verification proof.",
            )

        # 2. Validate (provider, environment, app_id, product_id) against internal mapping registry
        #    Even for pending/canceled/revoked events, environment/app/product must be recognized.
        mapping = self._mapping_registry.resolve(
            provider=verified_tx.provider,
            environment=verified_tx.environment,
            app_id=verified_tx.app_id,
            product_id=verified_tx.product_id,
        )

        if verified_tx.verification_status == ProviderVerificationStatus.PENDING:
            return PurchaseVerificationResponse(
                outcome=PurchaseVerificationOutcomeStatus.PENDING,
                user_id=authenticated_user_id,
                provider=verified_tx.provider,
                environment=verified_tx.environment,
                transaction_id=verified_tx.transaction_id,
                original_transaction_id=verified_tx.original_transaction_id,
                subscription_id=None,
                tier=MembershipTier.FREE,
                is_active_subscription=False,
                current_period_end=None,
                duplicate_ignored=False,
                message="Purchase is pending store settlement; no entitlement granted yet.",
            )

        if verified_tx.verification_status == ProviderVerificationStatus.CANCELED:
            return PurchaseVerificationResponse(
                outcome=PurchaseVerificationOutcomeStatus.CANCELED,
                user_id=authenticated_user_id,
                provider=verified_tx.provider,
                environment=verified_tx.environment,
                transaction_id=verified_tx.transaction_id,
                original_transaction_id=verified_tx.original_transaction_id,
                subscription_id=None,
                tier=MembershipTier.FREE,
                is_active_subscription=False,
                current_period_end=None,
                duplicate_ignored=False,
                message="Purchase was canceled; no entitlement granted.",
            )

        # 3. Check receipt ownership binding on (provider, environment, original_transaction_id)
        self._assert_receipt_ownership(
            db=db,
            user_id=authenticated_user_id,
            provider=verified_tx.provider,
            environment=verified_tx.environment,
            original_transaction_id=verified_tx.original_transaction_id,
        )

        # 4. Write-Ahead Durable ProviderEvent + Crash-Recoverable Projection
        projection_snapshot = {
            "user_id": authenticated_user_id,
            "provider": verified_tx.provider.value,
            "environment": verified_tx.environment.value,
            "app_id": verified_tx.app_id,
            "product_id": verified_tx.product_id,
            "transaction_id": verified_tx.transaction_id,
            "original_transaction_id": verified_tx.original_transaction_id,
            "verification_status": verified_tx.verification_status.value,
            "purchase_date": verified_tx.purchase_date,
            "expires_date": verified_tx.expires_date,
            "raw_payload_hash": verified_tx.raw_payload_hash,
            "event_timestamp": event_timestamp,
            "event_type": event_type,
            "mapping": mapping.model_dump(),
        }

        event_doc, already_processed = self._record_durable_provider_event(
            db=db,
            provider=verified_tx.provider,
            environment=verified_tx.environment,
            event_id=event_id,
            event_type=event_type,
            raw_payload_hash=verified_tx.raw_payload_hash,
            projection_snapshot=projection_snapshot,
            as_of=as_of,
        )

        if already_processed:
            sub_id = self._deterministic_subscription_id(
                verified_tx.provider,
                verified_tx.environment,
                verified_tx.original_transaction_id,
            )
            is_active = verified_tx.verification_status == ProviderVerificationStatus.VERIFIED_ACTIVE
            return PurchaseVerificationResponse(
                outcome=(
                    PurchaseVerificationOutcomeStatus.CONFIRMED
                    if is_active
                    else PurchaseVerificationOutcomeStatus.FAILED
                ),
                user_id=authenticated_user_id,
                provider=verified_tx.provider,
                environment=verified_tx.environment,
                transaction_id=verified_tx.transaction_id,
                original_transaction_id=verified_tx.original_transaction_id,
                subscription_id=sub_id,
                tier=mapping.tier if is_active else MembershipTier.FREE,
                is_active_subscription=is_active,
                current_period_end=verified_tx.expires_date if is_active else None,
                duplicate_ignored=True,
                message="Duplicate verified event/transaction ignored idempotently.",
            )

        # Execute crash-recoverable projection from snapshot and finalize event
        outcome_resp = self._execute_projection_from_snapshot(
            db=db,
            event_id=event_doc["event_id"],
            provider=verified_tx.provider,
            snapshot=projection_snapshot,
            as_of=as_of,
        )
        return outcome_resp

    def _assert_receipt_ownership(
        self,
        db,
        user_id: str,
        provider: PaymentProviderName,
        environment: PaymentEnvironment,
        original_transaction_id: str,
    ) -> ReceiptOwnershipStatus:
        """
        Ensures (provider, environment, original_transaction_id) is never silently transferred
        across accounts (CP-07 Invariant 7 & 9, CP-08 Section 5.A).
        Returns ReceiptOwnershipStatus.VERIFIED_OWNER or ReceiptOwnershipStatus.FIRST_OWNER_PROPOSED.
        Raises ReceiptOwnershipConflictError if bound to another user.
        """
        try:
            tx_col = db[COLL_PAYMENT_TRANSACTIONS]
            existing_tx = tx_col.find_one({
                "provider": provider.value,
                "environment": environment.value,
                "original_transaction_id": original_transaction_id,
            })
            if existing_tx and existing_tx.get("user_id") != user_id:
                raise ReceiptOwnershipConflictError(
                    message=f"Receipt original_transaction_id '{original_transaction_id}' is already bound to another user.",
                    ownership_status=ReceiptOwnershipStatus.UNRESOLVED_CONFLICT.value,
                    first_owner_policy="PROPOSED",
                )

            subs_col = db[COLL_SUBSCRIPTIONS]
            sub_id = self._deterministic_subscription_id(provider, environment, original_transaction_id)
            existing_sub = subs_col.find_one({"subscription_id": sub_id})
            if existing_sub and existing_sub.get("user_id") != user_id:
                raise ReceiptOwnershipConflictError(
                    message=f"Subscription '{sub_id}' is already bound to another user.",
                    ownership_status=ReceiptOwnershipStatus.UNRESOLVED_CONFLICT.value,
                    first_owner_policy="PROPOSED",
                )

            if existing_tx or existing_sub:
                return ReceiptOwnershipStatus.VERIFIED_OWNER
            return ReceiptOwnershipStatus.FIRST_OWNER_PROPOSED
        except ReceiptOwnershipConflictError:
            raise
        except Exception as exc:
            raise PaymentStorageError(f"Storage error verifying receipt ownership: {exc}") from exc

    @staticmethod
    def _deterministic_subscription_id(
        provider: PaymentProviderName,
        environment: PaymentEnvironment,
        original_transaction_id: str,
    ) -> str:
        p_val = provider.value if isinstance(provider, PaymentProviderName) else str(provider)
        e_val = environment.value if isinstance(environment, PaymentEnvironment) else str(environment)
        return f"sub_{p_val}_{e_val}_{original_transaction_id}"

    def _resolve_existing_subscription_lineage(
        self,
        db,
        verified_tx: VerifiedProviderTransaction,
    ) -> VerifiedProviderTransaction:
        """
        Official RevenueCat REST API v1 `GET /v1/subscribers/{app_user_id}` returns
        `store_transaction_id` (the latest store transaction ID), whereas webhooks return
        both `transaction_id` and `original_transaction_id`. If a subscription or transaction
        record already exists in the database for `(provider, environment)` where
        `transaction_id == verified_tx.transaction_id` or `latest_transaction_id == verified_tx.transaction_id`,
        preserve its established `original_transaction_id` lineage.
        """
        if verified_tx.original_transaction_id != verified_tx.transaction_id:
            return verified_tx
        try:
            tx_doc = db[COLL_PAYMENT_TRANSACTIONS].find_one({
                "provider": verified_tx.provider.value,
                "environment": verified_tx.environment.value,
                "transaction_id": verified_tx.transaction_id,
            })
            if tx_doc and tx_doc.get("original_transaction_id"):
                return verified_tx.model_copy(
                    update={"original_transaction_id": str(tx_doc["original_transaction_id"])}
                )
            sub_doc = db[COLL_SUBSCRIPTIONS].find_one({
                "provider": verified_tx.provider.value,
                "environment": verified_tx.environment.value,
                "latest_transaction_id": verified_tx.transaction_id,
            })
            if sub_doc and sub_doc.get("original_transaction_id"):
                return verified_tx.model_copy(
                    update={"original_transaction_id": str(sub_doc["original_transaction_id"])}
                )
        except Exception:
            pass
        return verified_tx

    def _record_durable_provider_event(
        self,
        db,
        provider: PaymentProviderName,
        environment: PaymentEnvironment,
        event_id: str,
        event_type: str,
        raw_payload_hash: str,
        projection_snapshot: Dict[str, Any],
        as_of: datetime,
    ) -> Tuple[Dict[str, Any], bool]:
        """
        Persists the verified ProviderEvent as a durable write-ahead record in COLL_PROVIDER_EVENTS.
        Also checks if the transaction_id was already fully projected under another event_id.
        Returns (event_doc, already_processed).
        """
        try:
            events_col = db[COLL_PROVIDER_EVENTS]
            tx_col = db[COLL_PAYMENT_TRANSACTIONS]

            # Check if transaction_id was already fully projected
            existing_tx = tx_col.find_one({
                "provider": provider.value,
                "environment": environment.value,
                "transaction_id": projection_snapshot["transaction_id"],
            })
            if existing_tx and existing_tx.get("projection_status") == "projected":
                # Check ownership first
                if existing_tx.get("user_id") != projection_snapshot["user_id"]:
                    raise ReceiptOwnershipConflictError(
                        "Transaction is already bound to another user account."
                    )
                # Ensure event record is also marked processed if same event_id
                existing_evt = events_col.find_one({
                    "provider": provider.value,
                    "event_id": event_id,
                })
                if existing_evt and existing_evt.get("processing_status") == "processed":
                    return existing_evt, True
                # If this is a purchase.verify call for an already-projected transaction, treat as idempotent duplicate
                if event_type == "purchase.verify":
                    return existing_evt or {"event_id": event_id, "provider": provider.value}, True

            existing_evt = events_col.find_one({
                "provider": provider.value,
                "event_id": event_id,
            })
            if existing_evt:
                if existing_evt.get("processing_status") == "processed":
                    snap = existing_evt.get("projection_snapshot") or {}
                    if snap.get("user_id") and snap.get("user_id") != projection_snapshot["user_id"]:
                        raise ReceiptOwnershipConflictError(
                            "Event was already processed for another user account."
                        )
                    return existing_evt, True
                # Incomplete ('received' or 'failed') -> update snapshot if needed and resume projection
                events_col.update_one(
                    {"provider": provider.value, "event_id": event_id},
                    {
                        "$set": {
                            "projection_snapshot": projection_snapshot,
                            "error_message": None,
                        }
                    },
                )
                existing_evt["projection_snapshot"] = projection_snapshot
                return existing_evt, False

            doc = {
                "event_id": event_id,
                "provider": provider.value,
                "environment": environment.value,
                "event_type": event_type,
                "raw_payload_hash": raw_payload_hash,
                "processing_status": "received",
                "projection_snapshot": projection_snapshot,
                "received_at": as_of,
                "processed_at": None,
                "error_message": None,
            }
            try:
                events_col.insert_one(doc)
                return doc, False
            except Exception as ins_exc:
                if "E11000" in str(ins_exc) or "duplicate key" in str(ins_exc).lower():
                    raced = events_col.find_one({
                        "provider": provider.value,
                        "event_id": event_id,
                    })
                    if raced:
                        return raced, raced.get("processing_status") == "processed"
                raise
        except ReceiptOwnershipConflictError:
            raise
        except Exception as exc:
            raise PaymentStorageError(f"Failed to persist durable provider event: {exc}") from exc

    def _execute_projection_from_snapshot(
        self,
        db,
        event_id: str,
        provider: PaymentProviderName,
        snapshot: Dict[str, Any],
        as_of: datetime,
    ) -> PurchaseVerificationResponse:
        """
        Idempotently projects:
          1. PaymentTransaction record in COLL_PAYMENT_TRANSACTIONS
          2. Subscription record in COLL_SUBSCRIPTIONS (enforcing out-of-order event protection)
          3. EntitlementGrant records in COLL_ENTITLEMENT_GRANTS
          4. UsageBucket limit_units in COLL_USAGE_BUCKETS (preserving consumed & reserved units)
          5. Marks ProviderEvent as 'processed' in COLL_PROVIDER_EVENTS.
        If any step fails, records error_message on ProviderEvent and raises PaymentStorageError
        so the event remains in 'received'/'failed' state for crash recovery / retry.
        """
        user_id: str = snapshot["user_id"]
        env = PaymentEnvironment(snapshot["environment"])
        app_id: str = snapshot["app_id"]
        product_id: str = snapshot["product_id"]
        transaction_id: str = snapshot["transaction_id"]
        original_transaction_id: str = snapshot["original_transaction_id"]
        ver_status = ProviderVerificationStatus(snapshot["verification_status"])
        purchase_date: datetime = snapshot["purchase_date"]
        expires_date: datetime = snapshot["expires_date"]
        raw_payload_hash: str = snapshot["raw_payload_hash"]
        event_timestamp: datetime = snapshot.get("event_timestamp") or as_of
        mapping = StoreProductMapping(**snapshot["mapping"])

        sub_id = self._deterministic_subscription_id(provider, env, original_transaction_id)

        try:
            tx_col = db[COLL_PAYMENT_TRANSACTIONS]
            subs_col = db[COLL_SUBSCRIPTIONS]
            grants_col = db[COLL_ENTITLEMENT_GRANTS]
            buckets_col = db[COLL_USAGE_BUCKETS]
            events_col = db[COLL_PROVIDER_EVENTS]

            # Step 1: Upsert durable transaction record (status='pending_projection' first)
            tx_doc_existing = tx_col.find_one({
                "provider": provider.value,
                "environment": env.value,
                "transaction_id": transaction_id,
            })
            if tx_doc_existing and tx_doc_existing.get("user_id") != user_id:
                raise ReceiptOwnershipConflictError(
                    "Transaction is already bound to another user account."
                )

            tx_payload = {
                "transaction_id": transaction_id,
                "original_transaction_id": original_transaction_id,
                "provider": provider.value,
                "environment": env.value,
                "app_id": app_id,
                "product_id": product_id,
                "user_id": user_id,
                "subscription_id": sub_id,
                "plan_id": mapping.plan_id,
                "price_id": mapping.price_id,
                "tier": mapping.tier.value,
                "catalog_version": mapping.catalog_version,
                "amount_cents": mapping.amount_cents,
                "currency": mapping.currency,
                "verification_status": ver_status.value,
                "purchase_date": purchase_date,
                "expires_date": expires_date,
                "raw_payload_hash": raw_payload_hash,
                "last_event_id": event_id,
                "updated_at": as_of,
            }
            if tx_doc_existing is None:
                try:
                    tx_col.insert_one({
                        **tx_payload,
                        "projection_status": "in_progress",
                        "created_at": as_of,
                    })
                except Exception as ins_tx_exc:
                    if "E11000" in str(ins_tx_exc) or "duplicate key" in str(ins_tx_exc).lower():
                        tx_col.update_one(
                            {
                                "provider": provider.value,
                                "environment": env.value,
                                "transaction_id": transaction_id,
                            },
                            {"$set": tx_payload},
                        )
                    else:
                        raise
            else:
                tx_col.update_one(
                    {
                        "provider": provider.value,
                        "environment": env.value,
                        "transaction_id": transaction_id,
                    },
                    {"$set": tx_payload},
                )

            # Step 2: Check existing Subscription for out-of-order event protection
            existing_sub = subs_col.find_one({"subscription_id": sub_id})
            if existing_sub and existing_sub.get("user_id") != user_id:
                raise ReceiptOwnershipConflictError(
                    "Subscription is already bound to another user account."
                )

            last_evt_ts = existing_sub.get("last_event_timestamp") if existing_sub else None
            if isinstance(last_evt_ts, datetime) and last_evt_ts.tzinfo is None:
                last_evt_ts = last_evt_ts.replace(tzinfo=timezone.utc)
            norm_evt_ts = (
                event_timestamp.replace(tzinfo=timezone.utc)
                if isinstance(event_timestamp, datetime) and event_timestamp.tzinfo is None
                else event_timestamp
            )
            is_stale_event = bool(
                last_evt_ts
                and isinstance(norm_evt_ts, datetime)
                and norm_evt_ts < last_evt_ts
            )
            # If timestamp is missing on existing subscription, flag reconciliation required
            if existing_sub and norm_evt_ts is None:
                subs_col.update_one(
                    {"subscription_id": sub_id},
                    {"$set": {"reconciliation_required": True, "updated_at": as_of}},
                )

            is_active_grant = ver_status == ProviderVerificationStatus.VERIFIED_ACTIVE
            target_sub_status = (
                SubscriptionStatus.ACTIVE.value
                if is_active_grant
                else (
                    SubscriptionStatus.CANCELED.value
                    if ver_status == ProviderVerificationStatus.REVOKED
                    else SubscriptionStatus.EXPIRED.value
                )
            )

            if not is_stale_event:
                sub_fields = {
                    "subscription_id": sub_id,
                    "user_id": user_id,
                    "plan_id": mapping.plan_id,
                    "price_id": mapping.price_id,
                    "tier": mapping.tier.value,
                    "status": target_sub_status,
                    "provider": provider.value,
                    "environment": env.value,
                    "app_id": app_id,
                    "product_id": product_id,
                    "original_transaction_id": original_transaction_id,
                    "provider_subscription_ref": original_transaction_id,
                    "latest_transaction_id": transaction_id,
                    "current_period_start": purchase_date,
                    "current_period_end": expires_date,
                    "cancel_at_period_end": (snapshot.get("event_type") == "cancellation") or (not is_active_grant),
                    "auto_renew_status": (snapshot.get("event_type") != "cancellation") and is_active_grant,
                    "in_grace_period": False,
                    "grace_period_expires_at": None,
                    "ownership_status": snapshot.get("ownership_status", "first_owner_proposed"),
                    "last_event_id": event_id,
                    "last_event_timestamp": norm_evt_ts,
                    "version": existing_sub.get("version", 1) + 1 if existing_sub else 1,
                    "updated_at": as_of,
                }
                if existing_sub is None:
                    try:
                        subs_col.insert_one({
                            **sub_fields,
                            "created_at": as_of,
                        })
                    except Exception as ins_sub_exc:
                        if "E11000" in str(ins_sub_exc) or "duplicate key" in str(ins_sub_exc).lower():
                            subs_col.update_one(
                                {"subscription_id": sub_id},
                                {"$set": sub_fields},
                            )
                        else:
                            raise
                else:
                    subs_col.update_one(
                        {"subscription_id": sub_id},
                        {"$set": sub_fields},
                    )

                # Step 3: Project EntitlementGrants for each benefit in the mapped plan
                target_grant_status = (
                    EntitlementStatus.GRANTED.value
                    if is_active_grant
                    else (
                        EntitlementStatus.REVOKED.value
                        if ver_status == ProviderVerificationStatus.REVOKED
                        else EntitlementStatus.EXPIRED.value
                    )
                )

                for benefit_id in mapping.benefit_ids:
                    grant_id = f"grant_{sub_id}_{benefit_id}"
                    grant_fields = {
                        "grant_id": grant_id,
                        "user_id": user_id,
                        "benefit_id": benefit_id,
                        "status": target_grant_status,
                        "source_type": "subscription",
                        "source_subscription_id": sub_id,
                        "source_ref": sub_id,
                        "tier": mapping.tier.value,
                        "valid_from": purchase_date,
                        "valid_until": expires_date,
                        "updated_at": as_of,
                    }
                    existing_grant = grants_col.find_one({"grant_id": grant_id})
                    if existing_grant is None:
                        try:
                            grants_col.insert_one({
                                **grant_fields,
                                "created_at": as_of,
                            })
                        except Exception as ins_grant_exc:
                            if "E11000" in str(ins_grant_exc) or "duplicate key" in str(ins_grant_exc).lower():
                                grants_col.update_one(
                                    {"grant_id": grant_id},
                                    {"$set": grant_fields},
                                )
                            else:
                                raise
                    else:
                        grants_col.update_one(
                            {"grant_id": grant_id},
                            {"$set": grant_fields},
                        )
                    # Deduplicate any raced concurrent inserts on collections without unique grant_id index
                    all_matching = list(grants_col.find({"grant_id": grant_id}))
                    if len(all_matching) > 1 and hasattr(grants_col, "delete_one"):
                        for extra in all_matching[1:]:
                            if "_id" in extra:
                                grants_col.delete_one({"_id": extra["_id"]})

                # Step 4: Project UsageBucket quota limit without resetting consumed/reserved units.
                # REVENUE-R02A Invariant: Never fallback to limit_units = 30 on expiration/revocation;
                # only project tier_limit when the grant is active and mapping specifies quota_limits.
                if is_active_grant and mapping.quota_limits:
                    q_svc = QuotaService(db=db)
                    w_start, w_end, b_key = q_svc._get_window_bounds(as_of)
                    for benefit_id, tier_limit in mapping.quota_limits.items():
                        existing_bucket = buckets_col.find_one({
                            "user_id": user_id,
                            "bucket_key": b_key,
                            "window_start": w_start,
                        })
                        if existing_bucket is None:
                            try:
                                buckets_col.insert_one({
                                    "bucket_id": f"bkt_{user_id}_{b_key}_{int(w_start.timestamp())}",
                                    "user_id": user_id,
                                    "benefit_id": benefit_id,
                                    "bucket_key": b_key,
                                    "window_start": w_start,
                                    "window_end": w_end,
                                    "limit_units": tier_limit,
                                    "consumed_units": 0,
                                    "reserved_units": 0,
                                    "reset_at": w_end,
                                    "updated_at": as_of,
                                })
                            except Exception as ins_bkt_exc:
                                if "E11000" in str(ins_bkt_exc) or "duplicate key" in str(ins_bkt_exc).lower():
                                    buckets_col.update_one(
                                        {
                                            "user_id": user_id,
                                            "bucket_key": b_key,
                                            "window_start": w_start,
                                        },
                                        {
                                            "$set": {
                                                "limit_units": tier_limit,
                                                "updated_at": as_of,
                                            }
                                        },
                                    )
                                else:
                                    raise
                        else:
                            buckets_col.update_one(
                                {
                                    "user_id": user_id,
                                    "bucket_key": b_key,
                                    "window_start": w_start,
                                },
                                {
                                    "$set": {
                                        "limit_units": tier_limit,
                                        "updated_at": as_of,
                                    }
                                },
                            )

            # Step 5: Mark transaction projected and ProviderEvent processed
            tx_col.update_one(
                {
                    "provider": provider.value,
                    "environment": env.value,
                    "transaction_id": transaction_id,
                },
                {
                    "$set": {
                        "projection_status": "projected",
                        "updated_at": as_of,
                    }
                },
            )
            events_col.update_one(
                {"provider": provider.value, "event_id": event_id},
                {
                    "$set": {
                        "processing_status": "processed",
                        "processed_at": as_of,
                        "error_message": None,
                    }
                },
            )
        except ReceiptOwnershipConflictError:
            raise
        except Exception as exc:
            # Best-effort mark event as failed so reconciliation can inspect and retry
            try:
                db[COLL_PROVIDER_EVENTS].update_one(
                    {"provider": provider.value, "event_id": event_id},
                    {
                        "$set": {
                            "processing_status": "failed",
                            "error_message": str(exc),
                        }
                    },
                )
            except Exception:
                pass
            raise PaymentStorageError(f"Failed during payment projection: {exc}") from exc

        is_active = ver_status == ProviderVerificationStatus.VERIFIED_ACTIVE
        return PurchaseVerificationResponse(
            outcome=(
                PurchaseVerificationOutcomeStatus.CONFIRMED
                if is_active
                else PurchaseVerificationOutcomeStatus.FAILED
            ),
            user_id=user_id,
            provider=provider,
            environment=env,
            transaction_id=transaction_id,
            original_transaction_id=original_transaction_id,
            subscription_id=sub_id,
            tier=mapping.tier if is_active else MembershipTier.FREE,
            is_active_subscription=is_active,
            current_period_end=expires_date if is_active else None,
            duplicate_ignored=False,
            message=(
                "Purchase verified and entitlements projected."
                if is_active
                else f"Transaction processed with status '{ver_status.value}'."
            ),
        )

    def reconcile_incomplete_payment_events(
        self,
        as_of: Optional[datetime] = None,
        limit: int = 100,
    ) -> Dict[str, Any]:
        """
        Crash-recovery reconciliation pass:
        Scans COLL_PROVIDER_EVENTS for events with processing_status in ('received', 'failed')
        that have a persisted projection_snapshot, and resumes projection idempotently.
        """
        now = as_of or datetime.now(timezone.utc)
        db = self._get_db()
        if db is None:
            raise PaymentStorageError("Database unavailable for payment event reconciliation.")

        events_col = db[COLL_PROVIDER_EVENTS]
        pending_events = list(
            events_col.find({"processing_status": {"$in": ["received", "failed"]}})
        )[:limit]

        recovered = 0
        failed = 0
        for evt in pending_events:
            snapshot = evt.get("projection_snapshot")
            if not snapshot:
                continue
            try:
                provider = PaymentProviderName(evt["provider"])
                self._execute_projection_from_snapshot(
                    db=db,
                    event_id=evt["event_id"],
                    provider=provider,
                    snapshot=snapshot,
                    as_of=now,
                )
                recovered += 1
            except Exception as exc:
                logger.error("Failed to reconcile provider event %s: %s", evt.get("event_id"), exc)
                failed += 1

        return {
            "scanned": len(pending_events),
            "recovered": recovered,
            "failed": failed,
        }

    def verify_and_settle_restore(
        self,
        authenticated_user_id: str,
        request: RestorePurchasesRequest,
        as_of: Optional[datetime] = None,
    ) -> RestorePurchasesResponse:
        """
        Executes authoritative purchase restoration (CP-08 Section 5.E).
        Invariants:
        1. Fails closed with PaymentConfigurationNotReadyError (503) if payment provider unconfigured.
        2. Rejects client identity mismatch if client supplied user_id != authenticated_user_id (403).
        3. Untrusted client claims never grant entitlements. Verified by trusted provider adapter.
        4. Same Account Restore:
           - Refreshes verified state and projects idempotently.
           - Does NOT create a new purchase/transaction record.
           - Does NOT artificially extend expiry dates.
           - Returns RestorePurchasesResponse with outcome=CONFIRMED, ownership_status=VERIFIED_OWNER.
        5. Different Account Restore (Ownership Conflict):
           - Detects conflict on (provider, environment, original_transaction_id).
           - First-owner policy is classified as PROPOSED (not unilaterally decided).
           - Does NOT transfer receipt. Does NOT grant entitlement to the caller.
           - Raises ReceiptOwnershipConflictError (409) with ownership_status='unresolved_conflict'.
        6. First Owner Proposed:
           - If no prior owner exists in database, binds to authenticated_user_id and activates.
        """
        now = as_of or datetime.now(timezone.utc)
        if not authenticated_user_id or not authenticated_user_id.strip():
            raise UnverifiedPurchasePayloadError(
                code="UNAUTHENTICATED_USER",
                message="Authenticated user identity is required for purchase restore.",
            )

        clean_user = authenticated_user_id.strip()
        if request.user_id and request.user_id.strip() != clean_user:
            raise ClientIdentityMismatchError()

        if not request.verification_token or not request.verification_token.strip():
            raise UnverifiedPurchasePayloadError(
                code="MISSING_VERIFICATION_TOKEN",
                message="Verification token / store receipt proof is required.",
            )

        if (
            request.provider == PaymentProviderName.UNCONFIGURED
            or not self._adapter.is_configured()
        ):
            raise PaymentConfigurationNotReadyError(
                "Payment provider integration is not yet configured or approved for live restore."
            )

        if request.provider != self._adapter.provider_name:
            raise PaymentConfigurationNotReadyError(
                f"Requested provider '{request.provider.value}' does not match configured adapter '{self._adapter.provider_name.value}'."
            )

        if request.provider == PaymentProviderName.REVENUECAT and not getattr(
            self._adapter, "is_restore_policy_verified", False
        ):
            reason_code = "RESTORE_POLICY_NOT_VERIFIED"
            reason_msg = (
                "RevenueCat restore policy ('Keep with original App User ID') is not yet verified "
                "in dashboard configuration."
            )
            if hasattr(self._adapter, "restore_unavailable_reason"):
                reason_code, reason_msg = self._adapter.restore_unavailable_reason()
            raise PaymentConfigurationNotReadyError(f"{reason_msg} ({reason_code})")

        db = self._get_db()
        if db is None:
            raise PaymentStorageError("Revenue database connection is unavailable.")

        if request.environment != self._mapping_registry.expected_environment:
            raise ProductMappingRejectedError(
                code="PAYMENT_ENVIRONMENT_MISMATCH",
                message=(
                    f"Request environment '{request.environment.value}' does not match "
                    f"server environment '{self._mapping_registry.expected_environment.value}'."
                ),
                http_status=422,
            )

        target_account_id = clean_user
        if request.provider == PaymentProviderName.REVENUECAT:
            from backend.app.services.revenuecat_adapter import (
                is_legacy_r02_opaque_user_id,
                resolve_or_create_account_id,
            )

            if is_legacy_r02_opaque_user_id(request.verification_token):
                raise UnverifiedPurchasePayloadError(
                    code="LEGACY_R02_IDENTITY_MIGRATION_REQUIRED",
                    message="Legacy R02 email-hash App User ID is disabled in REVENUE-R02A.",
                )
            target_account_id = resolve_or_create_account_id(db, clean_user)

        # Convert to PurchaseVerificationRequest for adapter verification
        pv_req = PurchaseVerificationRequest(
            provider=request.provider,
            environment=request.environment,
            app_id=request.app_id,
            product_id="restore_query",
            verification_token=request.verification_token,
            transaction_id=request.transaction_id,
            original_transaction_id=request.original_transaction_id,
            client_request_id=request.client_request_id,
            idempotency_key=request.idempotency_key,
        )

        verified_tx = self._adapter.verify_purchase(
            request=pv_req,
            expected_environment=self._mapping_registry.expected_environment,
            expected_app_id=request.app_id,
        )
        verified_tx = self._resolve_existing_subscription_lineage(db, verified_tx)

        mapping = self._mapping_registry.resolve(
            provider=verified_tx.provider,
            environment=verified_tx.environment,
            app_id=verified_tx.app_id,
            product_id=verified_tx.product_id,
        )

        sub_id = self._deterministic_subscription_id(
            verified_tx.provider,
            verified_tx.environment,
            verified_tx.original_transaction_id,
        )

        # Detect ownership status
        tx_col = db[COLL_PAYMENT_TRANSACTIONS]
        subs_col = db[COLL_SUBSCRIPTIONS]

        existing_tx = tx_col.find_one({
            "provider": verified_tx.provider.value,
            "environment": verified_tx.environment.value,
            "original_transaction_id": verified_tx.original_transaction_id,
        })
        existing_sub = subs_col.find_one({"subscription_id": sub_id})

        prior_owner = (
            existing_sub.get("user_id")
            if existing_sub
            else (existing_tx.get("user_id") if existing_tx else None)
        )

        if prior_owner and prior_owner != target_account_id:
            # Conflict detected: receipt is bound to a different account
            raise ReceiptOwnershipConflictError(
                message=(
                    f"Receipt original_transaction_id '{verified_tx.original_transaction_id}' "
                    f"is bound to another account. Automatic transfer is not supported."
                ),
                ownership_status=ReceiptOwnershipStatus.UNRESOLVED_CONFLICT.value,
                first_owner_policy="PROPOSED",
            )

        ownership_status = (
            ReceiptOwnershipStatus.VERIFIED_OWNER
            if prior_owner == target_account_id
            else ReceiptOwnershipStatus.FIRST_OWNER_PROPOSED
        )

        norm_expires = (
            verified_tx.expires_date.replace(tzinfo=timezone.utc)
            if verified_tx.expires_date and verified_tx.expires_date.tzinfo is None
            else verified_tx.expires_date
        )
        is_active = (
            verified_tx.verification_status == ProviderVerificationStatus.VERIFIED_ACTIVE
            and (norm_expires is None or now < norm_expires)
        )

        # Idempotently project subscription & grants without creating a new financial transaction
        projection_snapshot = {
            "user_id": target_account_id,
            "provider": verified_tx.provider.value,
            "environment": verified_tx.environment.value,
            "app_id": verified_tx.app_id,
            "product_id": verified_tx.product_id,
            "transaction_id": verified_tx.transaction_id,
            "original_transaction_id": verified_tx.original_transaction_id,
            "verification_status": (
                ProviderVerificationStatus.VERIFIED_ACTIVE.value
                if is_active
                else ProviderVerificationStatus.EXPIRED.value
            ),
            "purchase_date": verified_tx.purchase_date,
            "expires_date": verified_tx.expires_date,
            "raw_payload_hash": verified_tx.raw_payload_hash,
            "event_timestamp": now,
            "mapping": mapping.model_dump(),
            "is_restore": True,
            "ownership_status": ownership_status.value,
        }

        self._execute_projection_from_snapshot(
            db=db,
            event_id=f"evt_restore_{verified_tx.provider.value}_{verified_tx.environment.value}_{verified_tx.transaction_id}",
            provider=verified_tx.provider,
            snapshot=projection_snapshot,
            as_of=now,
        )

        return RestorePurchasesResponse(
            outcome=(
                PurchaseVerificationOutcomeStatus.CONFIRMED
                if is_active
                else PurchaseVerificationOutcomeStatus.FAILED
            ),
            user_id=clean_user,
            provider=verified_tx.provider,
            environment=verified_tx.environment,
            ownership_status=ownership_status,
            transaction_id=verified_tx.transaction_id,
            original_transaction_id=verified_tx.original_transaction_id,
            subscription_id=sub_id,
            tier=mapping.tier if is_active else MembershipTier.FREE,
            is_active_subscription=is_active,
            current_period_end=verified_tx.expires_date if is_active else None,
            restored_grants_count=len(mapping.benefit_ids) if is_active else 0,
            duplicate_ignored=True,
            first_owner_policy="PROPOSED",
            message=(
                "Purchases successfully restored."
                if is_active
                else "Restored purchase has expired; no active entitlements granted."
            ),
        )

    def process_lifecycle_event(
        self,
        event: VerifiedWebhookEvent,
        grace_policy: Optional[GracePeriodPolicy] = None,
        as_of: Optional[datetime] = None,
    ) -> Dict[str, Any]:
        """
        Coordinates full subscription lifecycle transitions (CP-08 Section 5.B & 5.C):
        - INITIAL_PURCHASE / ACTIVATION: Grants active access, creates initial quota bucket.
        - RENEWAL: Extends subscription period, maintains entitlement, advances quota period
          WITHOUT resetting usage on duplicate event replay.
        - CANCELLATION: Cancels auto-renew (cancel_at_period_end=True); keeps entitlement ACTIVE until current_period_end.
        - BILLING_ISSUE: Payment failure; evaluates injected GracePeriodPolicy (missing policy does NOT fake grace).
        - GRACE_EXPIRED / EXPIRATION: Marks subscription expired; revokes entitlement access.
        - REVOCATION / REFUND: Targets specific transaction and grant; does NOT blanket revoke unrelated user grants.
        - Ordering & Concurrency: Rejects out-of-order events; older events CANNOT revive revoked subscriptions;
          identical timestamp collisions are flagged as reconciliation_required without guessing access.
        """
        now = as_of or datetime.now(timezone.utc)
        if not self._adapter.is_configured():
            raise PaymentConfigurationNotReadyError(
                "Lifecycle processing is disabled until a payment provider is approved and configured."
            )

        db = self._get_db()
        if db is None:
            raise PaymentStorageError("Database unavailable for lifecycle processing.")

        tx = event.transaction
        mapping = self._mapping_registry.resolve(
            provider=tx.provider,
            environment=tx.environment,
            app_id=tx.app_id,
            product_id=tx.product_id,
        )

        sub_id = self._deterministic_subscription_id(tx.provider, tx.environment, tx.original_transaction_id)
        subs_col = db[COLL_SUBSCRIPTIONS]
        events_col = db[COLL_PROVIDER_EVENTS]
        grants_col = db[COLL_ENTITLEMENT_GRANTS]
        tx_col = db[COLL_PAYMENT_TRANSACTIONS]
        buckets_col = db[COLL_USAGE_BUCKETS]

        existing_sub = subs_col.find_one({"subscription_id": sub_id})
        resolved_user_id = event.user_id or (existing_sub.get("user_id") if existing_sub else None)

        if not resolved_user_id:
            raise WebhookVerificationError(
                code="WEBHOOK_UNBOUND_USER",
                message="Lifecycle event cannot be resolved to an existing user binding.",
                http_status=422,
            )

        clean_user = resolved_user_id.strip()
        if existing_sub and existing_sub.get("user_id") != clean_user:
            raise ReceiptOwnershipConflictError(
                message=f"Ownership conflict on lifecycle event: subscription '{sub_id}' belongs to another user.",
                ownership_status=ReceiptOwnershipStatus.UNRESOLVED_CONFLICT.value,
                first_owner_policy="PROPOSED",
            )

        # Step 1: Idempotency check on event_id
        existing_evt = events_col.find_one({
            "provider": event.provider.value,
            "event_id": event.event_id,
        })
        if existing_evt and existing_evt.get("processing_status") == "processed":
            return {
                "acknowledged": True,
                "event_id": event.event_id,
                "duplicate_ignored": True,
                "status": "processed",
                "message": "Duplicate lifecycle event already processed.",
            }

        # Step 2: Write-Ahead Log in COLL_PROVIDER_EVENTS
        evt_snapshot = {
            "event_id": event.event_id,
            "event_type": event.event_type,
            "provider": event.provider.value,
            "environment": event.environment.value,
            "user_id": clean_user,
            "transaction_id": tx.transaction_id,
            "original_transaction_id": tx.original_transaction_id,
            "event_timestamp": event.event_timestamp,
        }
        if existing_evt is None:
            try:
                events_col.insert_one({
                    "event_id": event.event_id,
                    "provider": event.provider.value,
                    "environment": event.environment.value,
                    "event_type": event.event_type,
                    "raw_payload_hash": event.raw_payload_hash,
                    "processing_status": "received",
                    "projection_snapshot": evt_snapshot,
                    "received_at": now,
                    "processed_at": None,
                })
            except Exception as ins_evt_exc:
                if "E11000" not in str(ins_evt_exc) and "duplicate key" not in str(ins_evt_exc).lower():
                    raise PaymentStorageError(f"Failed to record lifecycle event: {ins_evt_exc}") from ins_evt_exc

        # Step 3: Event Ordering & Concurrency Protection
        norm_evt_ts = None
        if event.event_timestamp is not None:
            norm_evt_ts = (
                event.event_timestamp.replace(tzinfo=timezone.utc)
                if event.event_timestamp.tzinfo is None
                else event.event_timestamp
            )

        if existing_sub:
            last_ts = existing_sub.get("last_event_timestamp")
            norm_last_ts = None
            if isinstance(last_ts, datetime):
                norm_last_ts = last_ts.replace(tzinfo=timezone.utc) if last_ts.tzinfo is None else last_ts

            # Indeterminate ordering if timestamp is missing from event or subscription
            if norm_evt_ts is None or norm_last_ts is None:
                subs_col.update_one(
                    {"subscription_id": sub_id},
                    {"$set": {"reconciliation_required": True, "updated_at": now}},
                )
                events_col.update_one(
                    {"provider": event.provider.value, "event_id": event.event_id},
                    {"$set": {"processing_status": "reconciliation_required", "processed_at": now}},
                )
                return {
                    "acknowledged": True,
                    "event_id": event.event_id,
                    "reconciliation_required": True,
                    "status": "reconciliation_required",
                    "message": "Missing event timestamp; ordering indeterminate. Flagged reconciliation_required.",
                }

            # Rule 1: Out-of-order stale event
            if norm_evt_ts < norm_last_ts:
                events_col.update_one(
                    {"provider": event.provider.value, "event_id": event.event_id},
                    {"$set": {"processing_status": "ignored_out_of_order", "processed_at": now}},
                )
                return {
                    "acknowledged": True,
                    "event_id": event.event_id,
                    "duplicate_ignored": True,
                    "status": "ignored_out_of_order",
                    "message": "Stale out-of-order event ignored; existing newer state preserved.",
                }
            # Rule 2: Ambiguous timestamp collision from different event
            if norm_evt_ts == norm_last_ts and event.event_id != existing_sub.get("last_event_id"):
                subs_col.update_one(
                    {"subscription_id": sub_id},
                    {"$set": {"reconciliation_required": True, "updated_at": now}},
                )
                events_col.update_one(
                    {"provider": event.provider.value, "event_id": event.event_id},
                    {"$set": {"processing_status": "reconciliation_required", "processed_at": now}},
                )
                return {
                    "acknowledged": True,
                    "event_id": event.event_id,
                    "reconciliation_required": True,
                    "status": "reconciliation_required",
                    "message": "Event timestamp collision; marked for reconciliation without granting access.",
                }

        # Step 4: Lifecycle State Transitions
        evt_type = (event.event_type or "").lower()
        new_version = (existing_sub.get("version", 1) + 1) if existing_sub else 1

        if evt_type in [
            SubscriptionLifecycleEventType.INITIAL_PURCHASE.value,
            SubscriptionLifecycleEventType.RENEWAL.value,
            "initial_purchase",
            "renewal",
        ]:
            # Record financial transaction
            tx_col.update_one(
                {
                    "provider": event.provider.value,
                    "environment": event.environment.value,
                    "transaction_id": tx.transaction_id,
                },
                {
                    "$set": {
                        "transaction_id": tx.transaction_id,
                        "original_transaction_id": tx.original_transaction_id,
                        "provider": event.provider.value,
                        "environment": event.environment.value,
                        "app_id": tx.app_id,
                        "product_id": tx.product_id,
                        "user_id": clean_user,
                        "subscription_id": sub_id,
                        "plan_id": mapping.plan_id,
                        "price_id": mapping.price_id,
                        "tier": mapping.tier.value,
                        "amount_cents": mapping.amount_cents,
                        "currency": mapping.currency,
                        "status": "verified",
                        "verification_status": "verified_active",
                        "purchase_date": tx.purchase_date,
                        "expires_date": tx.expires_date,
                        "raw_payload_hash": tx.raw_payload_hash,
                        "updated_at": now,
                    },
                    "$setOnInsert": {
                        "projection_status": "projected",
                        "created_at": now,
                    },
                },
                upsert=True,
            )

            # Update subscription to ACTIVE
            subs_col.update_one(
                {"subscription_id": sub_id},
                {
                    "$set": {
                        "subscription_id": sub_id,
                        "user_id": clean_user,
                        "plan_id": mapping.plan_id,
                        "price_id": mapping.price_id,
                        "tier": mapping.tier.value,
                        "status": SubscriptionStatus.ACTIVE.value,
                        "provider": event.provider.value,
                        "environment": event.environment.value,
                        "app_id": tx.app_id,
                        "product_id": tx.product_id,
                        "original_transaction_id": tx.original_transaction_id,
                        "latest_transaction_id": tx.transaction_id,
                        "current_period_start": tx.purchase_date,
                        "current_period_end": tx.expires_date,
                        "auto_renew_status": True,
                        "cancel_at_period_end": False,
                        "in_grace_period": False,
                        "grace_period_expires_at": None,
                        "last_event_id": event.event_id,
                        "last_event_type": evt_type,
                        "last_event_timestamp": norm_evt_ts,
                        "version": new_version,
                        "updated_at": now,
                    },
                    "$setOnInsert": {"created_at": now},
                },
                upsert=True,
            )

            # Update entitlement grants
            for benefit_id in mapping.benefit_ids:
                grant_id = f"grant_{sub_id}_{benefit_id}"
                grants_col.update_one(
                    {"grant_id": grant_id},
                    {
                        "$set": {
                            "grant_id": grant_id,
                            "user_id": clean_user,
                            "benefit_id": benefit_id,
                            "status": EntitlementStatus.GRANTED.value,
                            "source_type": "subscription",
                            "source_subscription_id": sub_id,
                            "tier": mapping.tier.value,
                            "valid_from": tx.purchase_date,
                            "valid_until": tx.expires_date,
                            "updated_at": now,
                        },
                        "$setOnInsert": {"created_at": now},
                    },
                    upsert=True,
                )

            # Quota period management (ensures renewal replay does not reset usage)
            q_svc = QuotaService(db=db)
            w_start, w_end, b_key = q_svc._get_window_bounds(tx.purchase_date or now)
            for benefit_id, tier_limit in mapping.quota_limits.items():
                existing_bkt = buckets_col.find_one({
                    "user_id": clean_user,
                    "bucket_key": b_key,
                    "window_start": w_start,
                })
                if existing_bkt is None:
                    # New billing cycle: initialize fresh bucket
                    buckets_col.insert_one({
                        "bucket_id": f"bkt_{clean_user}_{b_key}_{int(w_start.timestamp())}",
                        "user_id": clean_user,
                        "benefit_id": benefit_id,
                        "bucket_key": b_key,
                        "window_start": w_start,
                        "window_end": w_end,
                        "limit_units": tier_limit,
                        "consumed_units": 0,
                        "reserved_units": 0,
                        "reset_at": w_end,
                        "created_at": now,
                        "updated_at": now,
                    })
                else:
                    # Replay or existing period: update limit ONLY, preserve consumed and reserved units!
                    buckets_col.update_one(
                        {
                            "user_id": clean_user,
                            "bucket_key": b_key,
                            "window_start": w_start,
                        },
                        {
                            "$set": {
                                "limit_units": tier_limit,
                                "updated_at": now,
                            }
                        },
                    )

        elif evt_type in [
            SubscriptionLifecycleEventType.CANCELLATION.value,
            "cancellation",
            "did_change_renewal_status",
        ]:
            # User canceled auto-renew: retains entitlement until current_period_end (CP-08 & REVENUE-R02A Invariant)
            norm_exp = (
                tx.expires_date.replace(tzinfo=timezone.utc)
                if tx.expires_date and tx.expires_date.tzinfo is None
                else tx.expires_date
            )
            period_already_ended = bool(norm_exp and now >= norm_exp)
            cancel_fields: Dict[str, Any] = {
                "auto_renew_status": False,
                "cancel_at_period_end": True,
                "canceled_at": norm_evt_ts,
                "cancel_reason": getattr(event, "cancel_reason", None),
                "last_event_id": event.event_id,
                "last_event_type": "cancellation",
                "last_event_timestamp": norm_evt_ts,
                "version": new_version,
                "updated_at": now,
            }
            if period_already_ended:
                cancel_fields["status"] = SubscriptionStatus.EXPIRED.value
            subs_col.update_one(
                {"subscription_id": sub_id},
                {"$set": cancel_fields},
            )
            if period_already_ended:
                for g in list(grants_col.find({"source_subscription_id": sub_id})):
                    if "grant_id" in g:
                        grants_col.update_one(
                            {"grant_id": g["grant_id"]},
                            {"$set": {"status": EntitlementStatus.EXPIRED.value, "updated_at": now}},
                        )
            # Otherwise grants remain GRANTED until current_period_end; independent grants are untouched.

        elif evt_type in [
            SubscriptionLifecycleEventType.BILLING_ISSUE.value,
            "billing_issue",
            "payment_failed",
            "past_due",
        ]:
            # Payment failure: evaluates provider grace_period_expires_date or injected GracePeriodPolicy.
            # REVENUE-R02A Invariant: NEVER invent a grace period when neither is present.
            in_grace = False
            grace_expires = None
            provider_grace_end = getattr(event, "grace_period_expires_date", None) or getattr(
                tx, "grace_period_expires_date", None
            )
            if provider_grace_end is not None:
                norm_pg = (
                    provider_grace_end.replace(tzinfo=timezone.utc)
                    if provider_grace_end.tzinfo is None
                    else provider_grace_end
                )
                if norm_pg > now:
                    in_grace = True
                    grace_expires = norm_pg
            elif grace_policy and grace_policy.enabled and grace_policy.grace_duration_seconds > 0:
                in_grace = True
                grace_expires = norm_evt_ts + timedelta(seconds=grace_policy.grace_duration_seconds)

            subs_col.update_one(
                {"subscription_id": sub_id},
                {
                    "$set": {
                        "status": SubscriptionStatus.PAST_DUE.value,
                        "in_grace_period": in_grace,
                        "grace_period_expires_at": grace_expires,
                        "last_event_id": event.event_id,
                        "last_event_type": "billing_issue",
                        "last_event_timestamp": norm_evt_ts,
                        "version": new_version,
                        "updated_at": now,
                    }
                },
            )
            if in_grace and grace_expires:
                # Extend grant valid_until to grace_expires so explicit subscription grant stays valid during grace
                for g in list(grants_col.find({"source_subscription_id": sub_id})):
                    if "grant_id" in g:
                        grants_col.update_one(
                            {"grant_id": g["grant_id"]},
                            {"$set": {"valid_until": grace_expires, "updated_at": now}},
                        )
            else:
                # Without active grace, mark subscription-scoped grants EXPIRED (independent grants untouched)
                for g in list(grants_col.find({"source_subscription_id": sub_id})):
                    if "grant_id" in g:
                        grants_col.update_one(
                            {"grant_id": g["grant_id"]},
                            {"$set": {"status": EntitlementStatus.EXPIRED.value, "updated_at": now}},
                        )

        elif evt_type in [
            SubscriptionLifecycleEventType.GRACE_EXPIRED.value,
            SubscriptionLifecycleEventType.EXPIRATION.value,
            "grace_expired",
            "expiration",
        ]:
            subs_col.update_one(
                {"subscription_id": sub_id},
                {
                    "$set": {
                        "status": SubscriptionStatus.EXPIRED.value,
                        "in_grace_period": False,
                        "auto_renew_status": False,
                        "expiration_reason": getattr(event, "expiration_reason", None),
                        "last_event_id": event.event_id,
                        "last_event_type": "expiration",
                        "last_event_timestamp": norm_evt_ts,
                        "version": new_version,
                        "updated_at": now,
                    }
                },
            )
            # Only expire grants belonging to this subscription; never touch independent grants or usage counters
            for g in list(grants_col.find({"source_subscription_id": sub_id})):
                if "grant_id" in g:
                    grants_col.update_one(
                        {"grant_id": g["grant_id"]},
                        {"$set": {"status": EntitlementStatus.EXPIRED.value, "updated_at": now}},
                    )

        elif evt_type in [
            SubscriptionLifecycleEventType.REVOCATION.value,
            "revocation",
            "refund",
        ]:
            # Target specific transaction (refund)
            tx_col.update_one(
                {
                    "provider": event.provider.value,
                    "environment": event.environment.value,
                    "transaction_id": tx.transaction_id,
                },
                {"$set": {"status": "refunded", "updated_at": now}},
            )
            # Target specific grant for this subscription lineage (revoked); independent grants untouched
            for g in list(grants_col.find({"source_subscription_id": sub_id})):
                if "grant_id" in g:
                    grants_col.update_one(
                        {"grant_id": g["grant_id"]},
                        {
                            "$set": {
                                "status": EntitlementStatus.REVOKED.value,
                                "valid_until": norm_evt_ts,
                                "updated_at": now,
                            }
                        },
                    )
            # Set subscription to CANCELED
            subs_col.update_one(
                {"subscription_id": sub_id},
                {
                    "$set": {
                        "status": SubscriptionStatus.CANCELED.value,
                        "in_grace_period": False,
                        "auto_renew_status": False,
                        "cancel_reason": getattr(event, "cancel_reason", None),
                        "last_event_id": event.event_id,
                        "last_event_type": "revocation",
                        "last_event_timestamp": norm_evt_ts,
                        "version": new_version,
                        "updated_at": now,
                    }
                },
            )

        # Step 5: Finalize ProviderEvent as processed
        events_col.update_one(
            {"provider": event.provider.value, "event_id": event.event_id},
            {
                "$set": {
                    "processing_status": "processed",
                    "processed_at": now,
                    "error_message": None,
                }
            },
        )

        return {
            "acknowledged": True,
            "event_id": event.event_id,
            "event_type": evt_type,
            "subscription_id": sub_id,
            "status": "processed",
        }

    def sweep_expired_subscriptions(
        self,
        as_of: Optional[datetime] = None,
        limit: int = 500,
    ) -> Dict[str, Any]:
        """
        Explicit background sweep to mark expired subscriptions and grants in database.
        Note: EntitlementService evaluates expiry dynamically at query time using as_of;
        this sweep keeps persistent database records synchronized.
        """
        now = as_of or datetime.now(timezone.utc)
        db = self._get_db()
        if db is None:
            raise PaymentStorageError("Database unavailable for subscription sweep.")

        subs_col = db[COLL_SUBSCRIPTIONS]
        grants_col = db[COLL_ENTITLEMENT_GRANTS]

        query = {
            "status": {
                "$in": [
                    SubscriptionStatus.ACTIVE.value,
                    SubscriptionStatus.TRIALING.value,
                    SubscriptionStatus.PAST_DUE.value,
                ]
            },
            "current_period_end": {"$lte": now},
        }

        candidates = list(subs_col.find(query))[:limit]
        swept = 0

        for sub in candidates:
            # Check if grace period is active
            if sub.get("status") == SubscriptionStatus.PAST_DUE.value:
                grace_end = sub.get("grace_period_expires_at")
                if grace_end:
                    norm_grace_end = (
                        grace_end.replace(tzinfo=timezone.utc)
                        if grace_end.tzinfo is None
                        else grace_end
                    )
                    if now < norm_grace_end:
                        continue  # Still within valid grace period

            sub_id = sub.get("subscription_id")
            subs_col.update_one(
                {"subscription_id": sub_id},
                {
                    "$set": {
                        "status": SubscriptionStatus.EXPIRED.value,
                        "in_grace_period": False,
                        "updated_at": now,
                    }
                },
            )
            for g in list(grants_col.find({"source_subscription_id": sub_id, "status": EntitlementStatus.GRANTED.value})):
                if "grant_id" in g:
                    grants_col.update_one(
                        {"grant_id": g["grant_id"]},
                        {
                            "$set": {
                                "status": EntitlementStatus.EXPIRED.value,
                                "updated_at": now,
                            }
                        },
                    )
            swept += 1

        return {
            "scanned": len(candidates),
            "swept": swept,
            "as_of": now,
        }


# ==============================================================================
# 5. Internal Webhook Ingestion Contract
# ==============================================================================

class PaymentWebhookIngestionService:
    """
    Internal webhook ingestion boundary (Section 5.D).
    - While no payment provider is approved, NO public unauthenticated webhook endpoint
      is mounted that could accept generic JSON to grant entitlements.
    - Authenticates incoming webhooks strictly through IPaymentProviderAdapter.verify_and_parse_webhook
      (which does NOT assume every provider uses HMAC; supports JWS/OIDC/provider-specific auth).
    - Validates event schema, environment isolation, app_id, product mapping, and duplicate delivery.
    - Storage failures raise PaymentStorageError (HTTP 503) and NEVER acknowledge 200 OK if
      the event is not durably recorded and projected.
    """

    def __init__(
        self,
        settlement_service: PaymentSettlementService,
        adapter: Optional[IPaymentProviderAdapter] = None,
        mapping_registry: Optional[ProductMappingRegistry] = None,
        grace_policy: Optional[GracePeriodPolicy] = None,
    ):
        self._settlement = settlement_service
        self._adapter = adapter or settlement_service._adapter
        self._mapping_registry = mapping_registry or settlement_service._mapping_registry
        self._grace_policy = grace_policy

    def ingest_webhook(
        self,
        headers: Dict[str, str],
        raw_body: bytes,
        expected_app_id: str,
        as_of: Optional[datetime] = None,
    ) -> Dict[str, Any]:
        now = as_of or datetime.now(timezone.utc)
        is_wh_ready = (
            self._adapter.is_webhook_configured()
            if hasattr(self._adapter, "is_webhook_configured")
            else self._adapter.is_configured()
        )
        if not is_wh_ready:
            raise PaymentConfigurationNotReadyError(
                "Webhook ingestion is disabled until a payment provider webhook auth is configured."
            )

        db = self._settlement._get_db()
        if db is None:
            raise PaymentStorageError("Database unavailable; cannot durably persist webhook event.")

        verified_event = self._adapter.verify_and_parse_webhook(
            headers=headers,
            raw_body=raw_body,
            expected_environment=self._mapping_registry.expected_environment,
            expected_app_id=expected_app_id,
        )

        # Handle unsupported / operational / non-subscription events safely in WAL without granting or revoking
        if verified_event.event_type.startswith("unsupported:"):
            events_col = db[COLL_PROVIDER_EVENTS]
            existing_evt = events_col.find_one({
                "provider": verified_event.provider.value,
                "event_id": verified_event.event_id,
            })
            if existing_evt:
                return {
                    "acknowledged": True,
                    "event_id": verified_event.event_id,
                    "duplicate_ignored": True,
                    "status": existing_evt.get("processing_status", "ignored_unsupported"),
                    "outcome": "ignored",
                    "reconciliation_required": bool(existing_evt.get("reconciliation_required", False)),
                }

            raw_unsupported_type = verified_event.event_type.split(":", 1)[1].upper()
            needs_reconciliation = raw_unsupported_type in {"TRANSFER", "PRODUCT_CHANGE", "SUBSCRIPTION_PAUSED"}

            # If a subscription exists for this original_transaction_id and event requires reconciliation,
            # flag reconciliation_required=True WITHOUT changing ownership or entitlements.
            tx = verified_event.transaction
            if needs_reconciliation and tx and tx.original_transaction_id:
                sub_id = self._settlement._deterministic_subscription_id(
                    tx.provider, tx.environment, tx.original_transaction_id
                )
                existing_sub = db[COLL_SUBSCRIPTIONS].find_one({"subscription_id": sub_id})
                if existing_sub:
                    db[COLL_SUBSCRIPTIONS].update_one(
                        {"subscription_id": sub_id},
                        {"$set": {"reconciliation_required": True, "updated_at": now}},
                    )

            events_col.insert_one({
                "event_id": verified_event.event_id,
                "provider": verified_event.provider.value,
                "environment": verified_event.environment.value,
                "event_type": verified_event.event_type,
                "raw_payload_hash": verified_event.raw_payload_hash,
                "processing_status": "ignored_unsupported",
                "reconciliation_required": needs_reconciliation,
                "received_at": now,
                "processed_at": now,
            })
            return {
                "acknowledged": True,
                "event_id": verified_event.event_id,
                "duplicate_ignored": False,
                "status": "ignored_unsupported",
                "outcome": "ignored",
                "reconciliation_required": needs_reconciliation,
            }

        # Resolve user_id: prioritize existing subscription binding by original_transaction_id
        tx = verified_event.transaction
        existing_sub = None
        if tx and tx.original_transaction_id:
            sub_id = self._settlement._deterministic_subscription_id(
                tx.provider, tx.environment, tx.original_transaction_id
            )
            try:
                existing_sub = db[COLL_SUBSCRIPTIONS].find_one({"subscription_id": sub_id})
            except Exception as exc:
                raise PaymentStorageError(f"Database error looking up subscription for webhook: {exc}") from exc

        resolved_user_id = None
        if verified_event.provider == PaymentProviderName.REVENUECAT:
            from backend.app.services.revenuecat_adapter import (
                is_legacy_r02_opaque_user_id,
                resolve_account_id_from_provider_customer_id,
            )

            if verified_event.user_id and is_legacy_r02_opaque_user_id(verified_event.user_id):
                raise WebhookVerificationError(
                    code="LEGACY_R02_IDENTITY_MIGRATION_REQUIRED",
                    message=(
                        f"Webhook references legacy R02 email-hash identity '{verified_event.user_id}'. "
                        "Automatic migration is forbidden by REVENUE-R02A."
                    ),
                    http_status=422,
                )

            proj_id = verified_event.project_id or getattr(self._adapter, "expected_project_id", None)
            mapped_account_id = (
                resolve_account_id_from_provider_customer_id(
                    db, verified_event.user_id, project_id=proj_id
                )
                if verified_event.user_id
                else None
            )

            if existing_sub and existing_sub.get("user_id"):
                sub_owner = str(existing_sub["user_id"])
                if mapped_account_id and mapped_account_id != sub_owner:
                    raise ReceiptOwnershipConflictError(
                        message="RevenueCat webhook customer ID maps to a different account than existing subscription owner."
                    )
                resolved_user_id = sub_owner
            else:
                resolved_user_id = mapped_account_id
                if not resolved_user_id:
                    raise WebhookVerificationError(
                        code="WEBHOOK_UNBOUND_USER",
                        message=(
                            "RevenueCat webhook app_user_id is not bound to any Saman account in "
                            "revenue_provider_customers."
                        ),
                        http_status=422,
                    )

            lifecycle_event = verified_event.model_copy(update={"user_id": resolved_user_id})
            lc_res = self._settlement.process_lifecycle_event(
                event=lifecycle_event,
                grace_policy=self._grace_policy,
                as_of=now,
            )
            is_dup = bool(lc_res.get("duplicate_ignored", False))
            is_rec = bool(lc_res.get("reconciliation_required", False))
            outcome_str = (
                "confirmed"
                if tx.verification_status == ProviderVerificationStatus.VERIFIED_ACTIVE and not is_rec
                else lc_res.get("status", "processed")
            )
            return {
                "acknowledged": lc_res.get("acknowledged", True),
                "event_id": verified_event.event_id,
                "duplicate_ignored": is_dup,
                "status": lc_res.get("status", "processed"),
                "outcome": outcome_str,
                "subscription_id": lc_res.get("subscription_id"),
                "reconciliation_required": is_rec,
            }

        if existing_sub and existing_sub.get("user_id"):
            resolved_user_id = existing_sub.get("user_id")
        if not resolved_user_id:
            resolved_user_id = verified_event.user_id

        if not resolved_user_id:
            raise WebhookVerificationError(
                code="WEBHOOK_UNBOUND_USER",
                message="Webhook event cannot be resolved to an existing account or verified user binding.",
                http_status=422,
            )

        resp = self._settlement._process_verified_transaction(
            db=db,
            authenticated_user_id=resolved_user_id,
            verified_tx=tx,
            event_id=verified_event.event_id,
            event_type=verified_event.event_type,
            event_timestamp=verified_event.event_timestamp,
            as_of=now,
        )
        return {
            "acknowledged": True,
            "event_id": verified_event.event_id,
            "duplicate_ignored": resp.duplicate_ignored,
            "outcome": resp.outcome.value,
            "subscription_id": resp.subscription_id,
        }


# Singleton default service accessors
_default_settlement_service: Optional[PaymentSettlementService] = None
_default_webhook_service: Optional[PaymentWebhookIngestionService] = None


def configure_payment_settlement_service(service: Optional[PaymentSettlementService]) -> None:
    """Explicitly inject or reset settlement service (primarily for testing and mock environments)."""
    global _default_settlement_service, _default_webhook_service
    _default_settlement_service = service
    _default_webhook_service = None


def get_payment_settlement_service() -> PaymentSettlementService:
    global _default_settlement_service
    if _default_settlement_service is None:
        rc_key = (
            os.environ.get("REVENUECAT_SECRET_API_KEY", "").strip()
            or os.environ.get("REVENUECAT_SECRET_KEY", "").strip()
        )
        rc_webhook = (
            os.environ.get("REVENUECAT_WEBHOOK_AUTH_HEADER", "").strip()
            or os.environ.get("REVENUECAT_WEBHOOK_AUTH_TOKEN", "").strip()
            or os.environ.get("REVENUECAT_WEBHOOK_HMAC_SECRET", "").strip()
            or os.environ.get("REVENUECAT_WEBHOOK_SIGNATURE_SECRET", "").strip()
        )
        prov_env = os.environ.get("REVENUE_PAYMENT_PROVIDER", "").strip().lower()
        mappings_enabled = os.environ.get("REVENUECAT_MAPPINGS_ENABLED", "").strip().lower() in ("1", "true", "yes")

        if prov_env == "revenuecat" or rc_key or rc_webhook:
            from backend.app.services.revenuecat_adapter import RevenueCatProviderAdapter
            adapter = RevenueCatProviderAdapter()
            mapping_registry = ProductMappingRegistry()
            mapping_registry.register_revenuecat_defaults(
                environment=mapping_registry.expected_environment,
                enabled=mappings_enabled,
            )
            _default_settlement_service = PaymentSettlementService(
                adapter=adapter,
                mapping_registry=mapping_registry,
            )
        else:
            _default_settlement_service = PaymentSettlementService()
    return _default_settlement_service


def get_payment_webhook_service() -> PaymentWebhookIngestionService:
    global _default_webhook_service
    if _default_webhook_service is None:
        settlement = get_payment_settlement_service()
        _default_webhook_service = PaymentWebhookIngestionService(settlement_service=settlement)
    return _default_webhook_service
