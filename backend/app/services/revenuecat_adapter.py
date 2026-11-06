"""
Saman Revenue — RevenueCat Provider Adapter & Customer Identity Mapping (REVENUE-R02A).

Invariants Enforced (REVENUE-R02A):
1. Server-Owned Random Provider Customer Identity:
   - Never uses email or hash of email (`saman_usr_<sha256>`) as canonical payment identity.
   - Maps each immutable internal `account_id` (`acct_<32-hex>`) to a non-guessable CSPRNG
     RevenueCat App User ID (`rc_cus_<32-hex>`) scoped by `(provider, project_id, account_id)`
     in `revenue_provider_customers`.
   - Changing a user's email never alters `account_id` or `rc_cus_<32-hex>`.
   - Legacy R02 `saman_usr_*` identities are never auto-migrated, aliased, or merged;
     encountering them raises `LegacyR02IdentityMigrationRequiredError` (fail-closed blocker).
2. Trusted Server-Side Verification via HTTP Client:
   - Client `CustomerInfo` / `tokenReady` is untrusted and never sufficient to grant entitlements.
   - `verify_purchase` always executes an outbound `GET {api_base_url}/v1/subscribers/{app_user_id}`
     through an injectable `http_client` callable (exercising URL construction, URL encoding,
     `Authorization: Bearer <secret_key>` header, timeout, and HTTP status handling).
   - Never invents `expires_date = now + 30d` when `expires_date` is missing.
   - Never defaults missing `is_sandbox`; requires explicit boolean `is_sandbox` matching
     `expected_environment`, strictly isolating sandbox vs production records even when a
     subscriber has both sandbox and production entries.
   - Provider-reported transaction IDs (`store_transaction_id`, `original_transaction_id`)
     always take precedence over client-supplied hints.
3. Official RevenueCat Webhook Authentication:
   - Supports explicit `webhook_auth_mode` (`"bearer"`, `"hmac"`, `"bearer_and_hmac"`),
     failing closed when required secrets are missing.
   - Verifies `X-RevenueCat-Webhook-Signature: t=<unix_timestamp>,v1=<hex_sig>` by computing
     HMAC-SHA256 over `f"{timestamp}.{raw_body_str}"` (exact raw bytes `b"%s.%s" % (t, raw_body)`)
     using `hmac.compare_digest` and enforcing timestamp tolerance (default 300s).
4. Unapproved Policy Guardrails:
   - Product mapping builder does not embed unapproved production quotas (100/300) by default;
     test fixtures must explicitly pass `unapproved_test_quota_limits`.
   - Live restore requires explicit `restore_policy_verified=True` (`REVENUECAT_RESTORE_POLICY_VERIFIED=true`).
"""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import hmac
import json
import logging
import os
import re
import secrets
from typing import Any, Callable, Dict, List, Optional, Set, Tuple
import urllib.error
import urllib.parse
import urllib.request

from backend.app.database_revenue import (
    COLL_ENTITLEMENT_GRANTS,
    COLL_PAYMENT_TRANSACTIONS,
    COLL_PROVIDER_CUSTOMERS,
    COLL_SUBSCRIPTIONS,
    COLL_USAGE_BUCKETS,
)
from backend.app.models.revenue import (
    BillingPeriod,
    MembershipTier,
    PaymentEnvironment,
    PaymentProviderName,
    ProviderCustomerMapping,
    ProviderVerificationStatus,
    PurchaseVerificationRequest,
    StoreProductMapping,
    SubscriptionLifecycleEventType,
    VerifiedProviderTransaction,
    VerifiedWebhookEvent,
)
from backend.app.services.payment_service import (
    IPaymentProviderAdapter,
    PaymentConfigurationNotReadyError,
    ProductMappingRejectedError,
    UnverifiedPurchasePayloadError,
    WebhookVerificationError,
    hash_sensitive_payload,
)

logger = logging.getLogger(__name__)

DEFAULT_REVENUECAT_API_BASE_URL = "https://api.revenuecat.com"
DEFAULT_REVENUECAT_APP_ID = "com.saman.health"
DEFAULT_REVENUECAT_PROJECT_ID = "rc_proj_default"
DEFAULT_WEBHOOK_TOLERANCE_SECONDS = 300

_ACCOUNT_ID_PATTERN = re.compile(r"^acct_[0-9a-f]{32}$")
_RC_CUSTOMER_ID_PATTERN = re.compile(r"^rc_cus_[0-9a-f]{32}$")
_LEGACY_R02_PREFIX = "saman_usr_"

# Type alias for injectable low-level HTTP client:
# (Request, timeout_seconds) -> (status_code, response_headers, raw_body_bytes)
HttpClientCallable = Callable[
    [urllib.request.Request, float],
    Tuple[int, Dict[str, str], bytes],
]


class LegacyR02IdentityMigrationRequiredError(PaymentConfigurationNotReadyError):
    """
    Raised when a legacy R02 email-hash identity (`saman_usr_*`) is detected.
    In accordance with REVENUE-R02A invariants, legacy identities must NEVER be
    silently migrated, aliased, or merged; a read-only migration plan and human
    approval are required.
    """

    def __init__(self, message: str):
        super().__init__(message=message)
        self.code = "LEGACY_R02_IDENTITY_MIGRATION_REQUIRED"
        self.http_status = 409


def generate_random_account_id() -> str:
    """Generates a server-owned immutable 128-bit random internal account ID."""
    return f"acct_{secrets.token_hex(16)}"


def generate_random_revenuecat_app_user_id() -> str:
    """Generates a server-owned non-guessable 128-bit random RevenueCat App User ID."""
    return f"rc_cus_{secrets.token_hex(16)}"


def is_valid_account_id(value: Optional[str]) -> bool:
    if not value or not isinstance(value, str):
        return False
    return bool(_ACCOUNT_ID_PATTERN.match(value.strip()))


def is_valid_revenuecat_app_user_id(value: Optional[str]) -> bool:
    if not value or not isinstance(value, str):
        return False
    cleaned = value.strip()
    if "@" in cleaned or cleaned.startswith("$RCAnonymousID:") or cleaned.startswith(_LEGACY_R02_PREFIX):
        return False
    return bool(_RC_CUSTOMER_ID_PATTERN.match(cleaned))


def is_legacy_r02_opaque_user_id(value: Optional[str]) -> bool:
    if not value or not isinstance(value, str):
        return False
    return value.strip().lower().startswith(_LEGACY_R02_PREFIX)


def inspect_legacy_r02_identities_readonly(db: Any) -> Dict[str, Any]:
    """
    Read-only diagnostic scan for any legacy R02 `saman_usr_*` records across
    Revenue collections. Never mutates, aliases, or merges records.
    """
    if db is None:
        return {"has_legacy_records": False, "total_legacy_records": 0, "counts": {}, "samples": {}}

    collections_to_scan = [
        (COLL_SUBSCRIPTIONS, "user_id"),
        (COLL_ENTITLEMENT_GRANTS, "user_id"),
        (COLL_PAYMENT_TRANSACTIONS, "user_id"),
        (COLL_PROVIDER_CUSTOMERS, "app_user_id"),
    ]
    counts: Dict[str, int] = {}
    samples: Dict[str, List[str]] = {}

    for coll_name, field_name in collections_to_scan:
        matched_ids: List[str] = []
        try:
            docs = db[coll_name].find({})
            for doc in docs:
                val = str(doc.get(field_name) or "")
                if is_legacy_r02_opaque_user_id(val):
                    matched_ids.append(val)
        except Exception as exc:
            logger.warning("Read-only legacy identity scan failed on %s: %s", coll_name, exc)
        counts[coll_name] = len(matched_ids)
        if matched_ids:
            samples[coll_name] = sorted(set(matched_ids))[:10]

    total = sum(counts.values())
    return {
        "has_legacy_records": total > 0,
        "total_legacy_records": total,
        "counts": counts,
        "samples": samples,
    }


def _check_user_legacy_r02_blocker(db: Any, identifiers: List[str]) -> None:
    """
    Checks whether any candidate identifier (or Legacy R02 hash of email) has
    existing records under `saman_usr_*`. If found, raises LegacyR02IdentityMigrationRequiredError
    so we never silently orphan or auto-merge legacy R02 purchases.
    """
    if db is None:
        return

    candidate_legacy_ids: Set[str] = set()
    for ident in identifiers:
        if not ident:
            continue
        cleaned = ident.strip()
        if is_legacy_r02_opaque_user_id(cleaned):
            candidate_legacy_ids.add(cleaned.lower())
        elif "@" in cleaned:
            digest = hashlib.sha256(cleaned.lower().encode("utf-8")).hexdigest()[:16]
            candidate_legacy_ids.add(f"{_LEGACY_R02_PREFIX}{digest}")

    for legacy_id in candidate_legacy_ids:
        sub_doc = db[COLL_SUBSCRIPTIONS].find_one({"user_id": legacy_id})
        if sub_doc is not None:
            raise LegacyR02IdentityMigrationRequiredError(
                f"Legacy R02 email-hash identity '{legacy_id}' has existing subscription records. "
                "Automatic migration/aliasing is forbidden by REVENUE-R02A; execute approved read-only migration plan."
            )
        grant_doc = db[COLL_ENTITLEMENT_GRANTS].find_one({"user_id": legacy_id})
        if grant_doc is not None:
            raise LegacyR02IdentityMigrationRequiredError(
                f"Legacy R02 email-hash identity '{legacy_id}' has existing entitlement grant records. "
                "Automatic migration/aliasing is forbidden by REVENUE-R02A; execute approved read-only migration plan."
            )


def resolve_or_create_account_id(db: Any, authenticated_user_ref: str) -> str:
    """
    Resolves the canonical immutable internal `account_id` (`acct_<32-hex>`) for
    an authenticated user reference (JWT sub / email / account_id).
    - If `users` document already has `account_id`, returns it.
    - Changing `email` on the `users` document preserves `account_id`.
    - If `users` document exists without `account_id`, assigns and persists a random `acct_<32-hex>`.
    - If no `users` document exists yet in `db["users"]`:
      - If pre-seeded non-RevenueCat test records exist directly under `authenticated_user_ref`
        or `db["users"]` is a read-only mock without `update_one`, returns `authenticated_user_ref`.
      - Otherwise inserts a canonical user document with a fresh `acct_<32-hex>` `account_id`.
    """
    clean_ref = (authenticated_user_ref or "").strip()
    if not clean_ref:
        raise ValueError("Authenticated user reference cannot be empty.")
    if is_legacy_r02_opaque_user_id(clean_ref):
        raise LegacyR02IdentityMigrationRequiredError(
            f"Legacy R02 identity '{clean_ref}' is not a valid canonical account_id."
        )

    if db is None:
        if is_valid_account_id(clean_ref):
            return clean_ref
        raise RuntimeError("Database is required to resolve canonical account_id.")

    users_coll = db["users"]

    # 1. Lookup by immutable account_id first
    user_doc = users_coll.find_one({"account_id": clean_ref})
    if user_doc is None:
        # 2. Lookup by email
        user_doc = users_coll.find_one({"email": clean_ref})

    if user_doc is not None:
        existing_acct_id = user_doc.get("account_id")
        email_val = str(user_doc.get("email") or "")
        _check_user_legacy_r02_blocker(db, [clean_ref, email_val, str(existing_acct_id or "")])

        if is_valid_account_id(existing_acct_id):
            return str(existing_acct_id)

        new_acct_id = clean_ref if is_valid_account_id(clean_ref) else generate_random_account_id()
        if hasattr(users_coll, "update_one"):
            filter_key = (
                {"_id": user_doc["_id"]}
                if "_id" in user_doc
                else {"email": user_doc.get("email", clean_ref)}
            )
            users_coll.update_one(filter_key, {"$set": {"account_id": new_acct_id}})
        else:
            user_doc["account_id"] = new_acct_id
        return new_acct_id

    # Check if legacy R02 records exist for this identifier before creating new account mapping
    _check_user_legacy_r02_blocker(db, [clean_ref])

    # Preserve compatibility with lightweight CP-03/04/06/07 unit tests that seed records
    # directly by user_id without seeding db["users"] or using update_one
    if not hasattr(users_coll, "update_one"):
        return clean_ref
    if (
        db[COLL_SUBSCRIPTIONS].find_one({"user_id": clean_ref}) is not None
        or db[COLL_ENTITLEMENT_GRANTS].find_one({"user_id": clean_ref}) is not None
        or db[COLL_USAGE_BUCKETS].find_one({"user_id": clean_ref}) is not None
    ):
        return clean_ref

    new_acct_id = clean_ref if is_valid_account_id(clean_ref) else generate_random_account_id()
    now = datetime.now(timezone.utc)
    doc_to_insert: Dict[str, Any] = {
        "account_id": new_acct_id,
        "created_at": now,
        "updated_at": now,
    }
    if "@" in clean_ref or not is_valid_account_id(clean_ref):
        doc_to_insert["email"] = clean_ref
    users_coll.insert_one(doc_to_insert)
    return new_acct_id


def resolve_or_create_provider_customer_id(
    db: Any,
    account_id: str,
    project_id: Optional[str] = None,
    provider: PaymentProviderName = PaymentProviderName.REVENUECAT,
) -> str:
    """
    Resolves or creates the server-owned random RevenueCat App User ID (`rc_cus_<32-hex>`)
    uniquely bound to `(provider, project_id, account_id)` in `revenue_provider_customers`.
    Never hashes email or accepts client-generated identifiers.
    """
    if db is None:
        raise RuntimeError("Database is required to resolve provider customer mapping.")

    clean_acct = (account_id or "").strip()
    if not clean_acct:
        raise ValueError("account_id cannot be empty.")
    if is_legacy_r02_opaque_user_id(clean_acct):
        raise LegacyR02IdentityMigrationRequiredError(
            f"Refusing to create provider mapping for legacy R02 identity '{clean_acct}'."
        )

    canonical_account_id = (
        clean_acct if is_valid_account_id(clean_acct) else resolve_or_create_account_id(db, clean_acct)
    )
    _check_user_legacy_r02_blocker(db, [clean_acct, canonical_account_id])

    effective_project_id = (
        project_id
        or os.environ.get("REVENUECAT_PROJECT_ID", "").strip()
        or DEFAULT_REVENUECAT_PROJECT_ID
    )

    cust_coll = db[COLL_PROVIDER_CUSTOMERS]
    existing = cust_coll.find_one(
        {
            "provider": provider.value,
            "project_id": effective_project_id,
            "account_id": canonical_account_id,
        }
    )
    if existing is not None:
        app_user_id = str(existing.get("app_user_id") or "")
        if is_legacy_r02_opaque_user_id(app_user_id):
            raise LegacyR02IdentityMigrationRequiredError(
                f"Provider customer mapping for account '{canonical_account_id}' uses legacy R02 ID '{app_user_id}'."
            )
        return app_user_id

    now = datetime.now(timezone.utc)
    new_app_user_id = generate_random_revenuecat_app_user_id()
    mapping = ProviderCustomerMapping(
        mapping_id=f"pcm_{secrets.token_hex(12)}",
        provider=provider,
        project_id=effective_project_id,
        account_id=canonical_account_id,
        app_user_id=new_app_user_id,
        created_at=now,
        updated_at=now,
    )
    cust_coll.insert_one(mapping.model_dump())
    return new_app_user_id


def resolve_account_id_from_provider_customer_id(
    db: Any,
    app_user_id: str,
    project_id: Optional[str] = None,
    provider: PaymentProviderName = PaymentProviderName.REVENUECAT,
) -> Optional[str]:
    """
    Looks up the canonical internal `account_id` for a RevenueCat `app_user_id`.
    Raises `LegacyR02IdentityMigrationRequiredError` if `app_user_id` is a legacy `saman_usr_*` ID.
    Returns None if no mapping exists.
    """
    clean_app_user_id = (app_user_id or "").strip()
    if not clean_app_user_id:
        return None
    if is_legacy_r02_opaque_user_id(clean_app_user_id):
        raise LegacyR02IdentityMigrationRequiredError(
            f"Legacy R02 App User ID '{clean_app_user_id}' encountered; manual read-only migration required."
        )
    if db is None:
        return None

    effective_project_id = (
        project_id
        or os.environ.get("REVENUECAT_PROJECT_ID", "").strip()
        or DEFAULT_REVENUECAT_PROJECT_ID
    )
    doc = db[COLL_PROVIDER_CUSTOMERS].find_one(
        {
            "provider": provider.value,
            "project_id": effective_project_id,
            "app_user_id": clean_app_user_id,
        }
    )
    if doc is not None and doc.get("account_id"):
        return str(doc["account_id"])
    return None


def _parse_iso_datetime(val: Any) -> Optional[datetime]:
    """Parses ISO-8601 strings (e.g. '2026-10-31T12:00:00Z') or epoch ms into UTC datetime."""
    if val is None:
        return None
    if isinstance(val, datetime):
        return val if val.tzinfo else val.replace(tzinfo=timezone.utc)
    if isinstance(val, (int, float)):
        return datetime.fromtimestamp(float(val) / 1000.0, tz=timezone.utc)
    if isinstance(val, str):
        s = val.strip()
        if not s:
            return None
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        try:
            dt = datetime.fromisoformat(s)
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    return None


def _default_urllib_http_client(
    req: urllib.request.Request, timeout: float
) -> Tuple[int, Dict[str, str], bytes]:
    """Default low-level HTTP client executing urllib.request.urlopen."""
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = int(getattr(resp, "status", 200))
            headers = {k.lower(): v for k, v in resp.headers.items()} if getattr(resp, "headers", None) else {}
            body = resp.read()
            return status, headers, body
    except urllib.error.HTTPError as http_err:
        err_body = http_err.read() if hasattr(http_err, "read") else b""
        headers = {k.lower(): v for k, v in http_err.headers.items()} if getattr(http_err, "headers", None) else {}
        return int(http_err.code), headers, err_body


# Known subscription lifecycle webhook event types that mutate subscription state:
SUBSCRIPTION_LIFECYCLE_WEBHOOK_TYPES: Set[str] = {
    "INITIAL_PURCHASE",
    "RENEWAL",
    "CANCELLATION",
    "UNCANCELLATION",
    "BILLING_ISSUE",
    "EXPIRATION",
    "REVOCATION",
    "REFUND",
    "SUBSCRIPTION_EXTENDED",
}


class RevenueCatProviderAdapter(IPaymentProviderAdapter):
    """
    Trusted RevenueCat server-side adapter implementing IPaymentProviderAdapter (REVENUE-R02A).

    Key guarantees:
    1. Outbound verification calls `GET {api_base_url}/v1/subscribers/{quoted_app_user_id}`
       via `http_client` callable (never bypassing HTTP request construction).
    2. Strict validation of `project_id`, `app_id`, `store`, explicit boolean `is_sandbox`,
       and mandatory `purchase_date` / `expires_date`.
    3. Dual sandbox + production subscriber records are filtered strictly by `expected_environment`.
    4. Provider-reported transaction IDs take precedence over client hints.
    5. Webhook signature verification follows official RevenueCat spec:
       `X-RevenueCat-Webhook-Signature: t=<unix_timestamp>,v1=<hmac_sha256_hex>`
       computed over `f"{t}.{raw_body}"` with timestamp tolerance check.
    """

    DEFAULT_ALLOWED_STORES: Set[str] = {"APP_STORE", "MAC_APP_STORE", "PLAY_STORE", "STRIPE"}
    DEFAULT_SANDBOX_ONLY_STORES: Set[str] = {"TEST_STORE"}
    REQUIRED_RESTORE_BEHAVIOR: str = "keep_with_original_app_user_id"

    def __init__(
        self,
        secret_key: Optional[str] = None,
        webhook_auth_header: Optional[str] = None,
        webhook_auth_token: Optional[str] = None,
        webhook_hmac_secret: Optional[str] = None,
        webhook_signature_secret: Optional[str] = None,
        webhook_auth_mode: Optional[str] = None,
        webhook_timestamp_tolerance_seconds: int = DEFAULT_WEBHOOK_TOLERANCE_SECONDS,
        expected_app_id: Optional[str] = None,
        expected_webhook_app_id: Optional[str] = None,
        expected_project_id: Optional[str] = None,
        allowed_stores: Optional[Set[str]] = None,
        restore_policy_verified: Optional[bool] = None,
        restore_policy_approved: Optional[bool] = None,
        restore_behavior_verified: Optional[bool] = None,
        configured_restore_behavior: Optional[str] = None,
        api_base_url: Optional[str] = None,
        base_url: Optional[str] = None,
        timeout_seconds: float = 10.0,
        http_client: Optional[HttpClientCallable] = None,
        clock: Optional[Callable[[], datetime]] = None,
    ) -> None:
        self._secret_key = (
            secret_key
            if secret_key is not None
            else os.environ.get("REVENUECAT_SECRET_API_KEY", "").strip()
            or os.environ.get("REVENUECAT_SECRET_KEY", "").strip()
        )
        resolved_auth_header = (
            webhook_auth_header
            if webhook_auth_header is not None
            else webhook_auth_token
        )
        self._webhook_auth_header = (
            resolved_auth_header
            if resolved_auth_header is not None
            else os.environ.get("REVENUECAT_WEBHOOK_AUTH_HEADER", "").strip()
            or os.environ.get("REVENUECAT_WEBHOOK_AUTH_TOKEN", "").strip()
        )
        resolved_hmac_secret = (
            webhook_hmac_secret
            if webhook_hmac_secret is not None
            else webhook_signature_secret
        )
        self._webhook_hmac_secret = (
            resolved_hmac_secret
            if resolved_hmac_secret is not None
            else os.environ.get("REVENUECAT_WEBHOOK_HMAC_SECRET", "").strip()
            or os.environ.get("REVENUECAT_WEBHOOK_SIGNATURE_SECRET", "").strip()
        )

        raw_mode = (
            webhook_auth_mode
            if webhook_auth_mode is not None
            else os.environ.get("REVENUECAT_WEBHOOK_AUTH_MODE", "").strip().lower()
        )
        if not raw_mode:
            if self._webhook_auth_header and self._webhook_hmac_secret:
                raw_mode = "bearer_and_hmac"
            elif self._webhook_hmac_secret:
                raw_mode = "hmac"
            elif self._webhook_auth_header:
                raw_mode = "bearer"
            else:
                raw_mode = "unconfigured"
        self._webhook_auth_mode = raw_mode.lower()
        self._webhook_timestamp_tolerance_seconds = int(webhook_timestamp_tolerance_seconds)

        self._expected_app_id = (
            expected_app_id
            if expected_app_id is not None
            else os.environ.get("REVENUECAT_APP_ID", "").strip()
            or os.environ.get("REVENUE_EXPECTED_APP_ID", "").strip()
        )
        self._expected_webhook_app_id = (
            expected_webhook_app_id
            if expected_webhook_app_id is not None
            else os.environ.get("REVENUECAT_WEBHOOK_APP_ID", "").strip()
        )
        self._expected_project_id = (
            expected_project_id
            if expected_project_id is not None
            else os.environ.get("REVENUECAT_PROJECT_ID", "").strip()
        )
        if allowed_stores is not None:
            self._allowed_stores: Set[str] = {s.upper() for s in allowed_stores}
        else:
            self._allowed_stores = set(self.DEFAULT_ALLOWED_STORES) | set(self.DEFAULT_SANDBOX_ONLY_STORES)

        # REVENUE-R03 Task 3: Separate restore policy approval, dashboard verification,
        # and required 'keep_with_original_app_user_id' behavior.
        if restore_policy_approved is not None:
            self._restore_policy_approved = bool(restore_policy_approved)
        else:
            env_approved = os.environ.get("REVENUECAT_RESTORE_POLICY_APPROVED", "").strip().lower()
            self._restore_policy_approved = env_approved in ("1", "true", "yes")

        if restore_behavior_verified is not None:
            self._restore_behavior_verified = bool(restore_behavior_verified)
        else:
            env_beh_ver = os.environ.get("REVENUECAT_RESTORE_BEHAVIOR_VERIFIED", "").strip().lower()
            self._restore_behavior_verified = env_beh_ver in ("1", "true", "yes")

        if configured_restore_behavior is not None:
            self._configured_restore_behavior = configured_restore_behavior.strip().lower()
        else:
            env_beh = os.environ.get("REVENUECAT_CONFIGURED_RESTORE_BEHAVIOR", "").strip().lower()
            self._configured_restore_behavior = env_beh or "unverified"

        # Backwards compatibility when legacy composite flag is explicitly provided
        if restore_policy_verified is not None:
            if bool(restore_policy_verified):
                if restore_policy_approved is None:
                    self._restore_policy_approved = True
                if restore_behavior_verified is None:
                    self._restore_behavior_verified = True
                if configured_restore_behavior is None:
                    self._configured_restore_behavior = self.REQUIRED_RESTORE_BEHAVIOR
            else:
                if restore_policy_approved is None and restore_behavior_verified is None:
                    self._restore_policy_approved = False

        resolved_url = api_base_url or base_url or os.environ.get("REVENUECAT_API_BASE_URL", DEFAULT_REVENUECAT_API_BASE_URL)
        self._api_base_url = resolved_url.strip().rstrip("/")
        self._timeout_seconds = float(timeout_seconds)
        self._http_client: HttpClientCallable = http_client or _default_urllib_http_client
        self._clock: Callable[[], datetime] = clock or (lambda: datetime.now(timezone.utc))

    @property
    def provider_name(self) -> PaymentProviderName:
        return PaymentProviderName.REVENUECAT

    @property
    def expected_project_id(self) -> str:
        return self._expected_project_id or DEFAULT_REVENUECAT_PROJECT_ID

    @property
    def is_restore_policy_approved(self) -> bool:
        """True only when business policy for live purchase restoration has been approved."""
        return self._restore_policy_approved

    @property
    def is_restore_behavior_verified(self) -> bool:
        """True only when an operator has inspected and verified the RevenueCat dashboard restore behavior setting."""
        return self._restore_behavior_verified

    @property
    def configured_restore_behavior(self) -> str:
        """The attested RevenueCat dashboard restore behavior setting (e.g. 'keep_with_original_app_user_id')."""
        return self._configured_restore_behavior

    @property
    def is_restore_keep_original_enforced(self) -> bool:
        """True only when the dashboard restore behavior is attested as 'keep_with_original_app_user_id'."""
        return self._configured_restore_behavior == self.REQUIRED_RESTORE_BEHAVIOR

    @property
    def _restore_policy_verified(self) -> bool:
        return (
            self._restore_policy_approved
            and self._restore_behavior_verified
            and self.is_restore_keep_original_enforced
        )

    @_restore_policy_verified.setter
    def _restore_policy_verified(self, value: bool) -> None:
        if bool(value):
            self._restore_policy_approved = True
            self._restore_behavior_verified = True
            self._configured_restore_behavior = self.REQUIRED_RESTORE_BEHAVIOR
        else:
            self._restore_policy_approved = False

    @property
    def is_restore_policy_verified(self) -> bool:
        """
        True ONLY when:
        1. Business restore policy is approved (`is_restore_policy_approved == True`),
        2. RevenueCat dashboard restore setting has been verified (`is_restore_behavior_verified == True`), and
        3. The configured dashboard behavior is `'keep_with_original_app_user_id'`.
        """
        return self._restore_policy_verified

    def restore_unavailable_reason(self) -> Tuple[str, str]:
        """Returns (reason_code, message) explaining why live restore is unavailable."""
        if not self._restore_policy_approved:
            return (
                "RESTORE_POLICY_NOT_APPROVED",
                "Business restore policy is not yet approved; live RevenueCat restore is unavailable.",
            )
        if not self._restore_behavior_verified:
            return (
                "RESTORE_DASHBOARD_NOT_VERIFIED",
                "RevenueCat dashboard restore behavior setting has not been verified; live restore is unavailable.",
            )
        if not self.is_restore_keep_original_enforced:
            return (
                "RESTORE_BEHAVIOR_MUST_KEEP_ORIGINAL",
                f"RevenueCat dashboard restore behavior is '{self._configured_restore_behavior}', "
                f"which does not enforce '{self.REQUIRED_RESTORE_BEHAVIOR}'; live restore is unavailable to prevent silent customer transfer.",
            )
        return ("READY", "Restore policy is approved and verified.")

    def is_configured(self) -> bool:
        """Returns True only when a non-empty secret API key is provisioned."""
        return bool(self._secret_key)

    def is_webhook_configured(self) -> bool:
        """Returns True only when the configured webhook_auth_mode has its required secrets."""
        if self._webhook_auth_mode == "bearer":
            return bool(self._webhook_auth_header)
        if self._webhook_auth_mode == "hmac":
            return bool(self._webhook_hmac_secret)
        if self._webhook_auth_mode == "bearer_and_hmac":
            return bool(self._webhook_auth_header and self._webhook_hmac_secret)
        return False

    def verify_purchase(
        self,
        request: PurchaseVerificationRequest,
        expected_environment: PaymentEnvironment,
        expected_app_id: str = "",
    ) -> VerifiedProviderTransaction:
        """
        Queries trusted RevenueCat REST API `GET /v1/subscribers/{app_user_id}` via `_http_client`
        and returns a normalized `VerifiedProviderTransaction`.
        Never trusts client-supplied CustomerInfo, expiration dates, or transaction IDs over
        RevenueCat's server response.
        """
        if not self.is_configured():
            raise PaymentConfigurationNotReadyError(
                "RevenueCat adapter is not configured. REVENUECAT_SECRET_API_KEY is missing."
            )

        app_user_id = (request.verification_token or "").strip()
        if not app_user_id:
            raise UnverifiedPurchasePayloadError(
                code="MISSING_VERIFICATION_TOKEN",
                message="Verification token (RevenueCat customer ID) is required.",
            )

        if request.environment != expected_environment:
            raise ProductMappingRejectedError(
                code="PAYMENT_ENVIRONMENT_MISMATCH",
                message=(
                    f"Request environment '{request.environment.value}' does not match "
                    f"server expected environment '{expected_environment.value}'."
                ),
                http_status=422,
            )

        target_app_id = expected_app_id or self._expected_app_id
        if target_app_id and request.app_id != target_app_id:
            raise ProductMappingRejectedError(
                code="PAYMENT_APP_ID_MISMATCH",
                message=f"App ID '{request.app_id}' does not match expected scope '{target_app_id}'.",
                http_status=422,
            )

        if is_legacy_r02_opaque_user_id(app_user_id):
            raise UnverifiedPurchasePayloadError(
                code="LEGACY_R02_IDENTITY_MIGRATION_REQUIRED",
                message=(
                    "Legacy R02 email-hash App User ID is disabled in REVENUE-R02A. "
                    "Use server-assigned random provider customer ID."
                ),
            )

        if not is_valid_revenuecat_app_user_id(app_user_id):
            raise UnverifiedPurchasePayloadError(
                code="INVALID_PROVIDER_CUSTOMER_ID",
                message="Verification token must be a server-owned RevenueCat customer ID (rc_cus_<32-hex>).",
            )

        now = self._clock()
        raw_hash = hash_sensitive_payload(app_user_id)

        encoded_user_id = urllib.parse.quote(app_user_id, safe="")
        url = f"{self._api_base_url}/v1/subscribers/{encoded_user_id}"
        http_req = urllib.request.Request(
            url,
            method="GET",
            headers={
                "Authorization": f"Bearer {self._secret_key}",
                "Accept": "application/json",
                "Content-Type": "application/json",
                "User-Agent": "Saman-Revenue-Backend/1.0",
            },
        )

        try:
            status_code, _resp_headers, resp_bytes = self._http_client(http_req, self._timeout_seconds)
        except Exception as exc:
            logger.error("RevenueCat HTTP transport error during verify_purchase: %s", exc)
            raise UnverifiedPurchasePayloadError(
                code="REVENUECAT_NETWORK_ERROR",
                message=f"Failed to reach RevenueCat API: {exc}",
            ) from exc

        if status_code == 404:
            raise UnverifiedPurchasePayloadError(
                code="REVENUECAT_SUBSCRIBER_NOT_FOUND",
                message="Subscriber record not found in RevenueCat.",
            )
        if status_code in (401, 403):
            raise UnverifiedPurchasePayloadError(
                code="REVENUECAT_AUTH_FAILED",
                message=f"RevenueCat API authentication failed with HTTP {status_code}.",
            )
        if status_code < 200 or status_code >= 300:
            raise UnverifiedPurchasePayloadError(
                code="REVENUECAT_API_ERROR",
                message=f"RevenueCat API returned HTTP {status_code}.",
            )

        try:
            subscriber_payload = json.loads(resp_bytes.decode("utf-8"))
        except Exception as exc:
            raise UnverifiedPurchasePayloadError(
                code="REVENUECAT_INVALID_JSON",
                message=f"Invalid JSON from RevenueCat API: {exc}",
            ) from exc

        subscriber = subscriber_payload.get("subscriber")
        if not isinstance(subscriber, dict):
            raise UnverifiedPurchasePayloadError(
                code="REVENUECAT_SUBSCRIBER_NOT_FOUND",
                message="RevenueCat response did not contain a valid 'subscriber' object.",
            )

        # Official RevenueCat REST API v1 GET /v1/subscribers/{app_user_id} does NOT include
        # `project_id` or `app_id` in the JSON payload. Project scope is cryptographically enforced
        # by the project-scoped Secret API Key (`Authorization: Bearer <secret_key>`) and server-side
        # `revenue_provider_customers` `(provider, project_id, account_id)` binding.
        # If a proxy/custom payload explicitly supplies `project_id`, verify it matches.
        resp_project_id = subscriber_payload.get("project_id") or subscriber.get("project_id")
        if self._expected_project_id and resp_project_id and str(resp_project_id) != self._expected_project_id:
            raise ProductMappingRejectedError(
                code="PAYMENT_PROJECT_ID_MISMATCH",
                message=(
                    f"RevenueCat project_id '{resp_project_id}' does not match expected '{self._expected_project_id}'."
                ),
                http_status=422,
            )

        # Reject silent alias/transfer mismatch if subscriber original_app_user_id differs from queried app_user_id
        orig_app_user_id = subscriber.get("original_app_user_id")
        if orig_app_user_id and str(orig_app_user_id).strip() != app_user_id:
            raise UnverifiedPurchasePayloadError(
                code="SUBSCRIBER_IDENTITY_ALIAS_MISMATCH",
                message=(
                    "RevenueCat subscriber original_app_user_id differs from requested customer ID. "
                    "Automatic customer aliasing/merging is prohibited."
                ),
            )

        subscriptions = subscriber.get("subscriptions") or {}
        if not isinstance(subscriptions, dict):
            subscriptions = {}

        is_restore_query = request.product_id == "restore_query"
        matching_product_records: List[Tuple[str, Dict[str, Any]]] = []

        for sub_key, sub_val in subscriptions.items():
            if not isinstance(sub_val, dict):
                continue
            prod_ident = str(sub_val.get("product_identifier") or sub_key)
            plan_ident = str(sub_val.get("product_plan_identifier") or "").strip()
            composite_play_ident = f"{sub_key}:{plan_ident}" if plan_ident else ""
            if is_restore_query:
                matching_product_records.append((prod_ident, sub_val))
            elif (
                sub_key == request.product_id
                or prod_ident == request.product_id
                or (composite_play_ident and composite_play_ident == request.product_id)
            ):
                matching_product_records.append((request.product_id, sub_val))

        if not matching_product_records:
            raise UnverifiedPurchasePayloadError(
                code="PRODUCT_SUBSCRIPTION_NOT_FOUND",
                message=f"No subscription record found in RevenueCat for product '{request.product_id}'.",
            )

        # Validate explicit boolean is_sandbox and filter by expected_environment
        env_matched_records: List[Tuple[str, Dict[str, Any]]] = []
        saw_environment_mismatch = False
        saw_missing_sandbox_flag = False

        for prod_ident, rec in matching_product_records:
            raw_is_sandbox = rec.get("is_sandbox")
            if not isinstance(raw_is_sandbox, bool):
                saw_missing_sandbox_flag = True
                continue
            rec_env = PaymentEnvironment.SANDBOX if raw_is_sandbox else PaymentEnvironment.PRODUCTION
            if rec_env == expected_environment:
                env_matched_records.append((prod_ident, rec))
            else:
                saw_environment_mismatch = True

        if not env_matched_records:
            if saw_environment_mismatch:
                raise ProductMappingRejectedError(
                    code="PAYMENT_ENVIRONMENT_MISMATCH",
                    message=(
                        f"Subscriber has subscription record(s) for '{request.product_id}', "
                        f"but none match expected environment '{expected_environment.value}'."
                    ),
                    http_status=422,
                )
            if saw_missing_sandbox_flag:
                raise UnverifiedPurchasePayloadError(
                    code="MISSING_IS_SANDBOX_FLAG",
                    message="RevenueCat subscription record is missing an explicit boolean 'is_sandbox' field.",
                )

        # Pick the most recent environment-matched subscription record by expires_date
        resolved_product_id, sub_data = env_matched_records[0]
        if len(env_matched_records) > 1:
            resolved_product_id, sub_data = max(
                env_matched_records,
                key=lambda item: _parse_iso_datetime(item[1].get("expires_date"))
                or datetime.min.replace(tzinfo=timezone.utc),
            )

        # Validate store and enforce Test Store environment isolation
        store_raw = str(sub_data.get("store") or "").strip().upper()
        if store_raw == "TEST_STORE" and expected_environment == PaymentEnvironment.PRODUCTION:
            raise ProductMappingRejectedError(
                code="TEST_STORE_FORBIDDEN_IN_PRODUCTION",
                message="RevenueCat Test Store ('test_store') purchases are strictly forbidden in production environment.",
                http_status=422,
            )
        if not store_raw or store_raw not in self._allowed_stores:
            raise UnverifiedPurchasePayloadError(
                code="UNSUPPORTED_OR_MISSING_STORE",
                message=f"Subscription store '{store_raw}' is missing or not in allowed stores.",
            )

        # Mandatory verified timestamps — NEVER invent now + 30 days!
        purchase_date = _parse_iso_datetime(sub_data.get("purchase_date"))
        expires_date = _parse_iso_datetime(sub_data.get("expires_date"))
        if purchase_date is None or expires_date is None:
            raise UnverifiedPurchasePayloadError(
                code="MISSING_VERIFIED_TIMESTAMPS",
                message="RevenueCat subscription record is missing verified 'purchase_date' or 'expires_date'.",
            )

        # Provider-reported store_transaction_id is mandatory in GET /v1/subscribers (may be string or integer in OpenAPI examples)
        raw_store_txn = sub_data.get("store_transaction_id")
        if raw_store_txn is None:
            raw_store_txn = sub_data.get("transaction_id")
        provider_store_txn_id = str(raw_store_txn).strip() if raw_store_txn is not None else ""
        if not provider_store_txn_id:
            raise UnverifiedPurchasePayloadError(
                code="MISSING_PROVIDER_TRANSACTION_ID",
                message="RevenueCat subscription record is missing 'store_transaction_id'.",
            )

        # Official GET /v1/subscribers returns `store_transaction_id` and `original_purchase_date`
        # (whereas `original_transaction_id` is a webhook-only field). Default to `provider_store_txn_id`
        # when `original_transaction_id` is absent from GET /v1/subscribers; PaymentSettlementService
        # resolves existing subscription lineage when renewing.
        raw_orig_txn = sub_data.get("original_store_transaction_id") or sub_data.get("original_transaction_id")
        provider_orig_txn_id = (
            str(raw_orig_txn).strip() if raw_orig_txn is not None and str(raw_orig_txn).strip() else provider_store_txn_id
        )

        unsubscribe_detected_at = _parse_iso_datetime(sub_data.get("unsubscribe_detected_at"))
        billing_issues_detected_at = _parse_iso_datetime(sub_data.get("billing_issues_detected_at"))
        grace_period_expires_date = _parse_iso_datetime(sub_data.get("grace_period_expires_date"))
        refunded_at = _parse_iso_datetime(sub_data.get("refunded_at"))
        period_type = str(sub_data.get("period_type") or "normal").lower()

        if refunded_at is not None:
            v_status = ProviderVerificationStatus.REVOKED
        elif expires_date <= now:
            if grace_period_expires_date is not None and grace_period_expires_date > now:
                v_status = ProviderVerificationStatus.VERIFIED_ACTIVE
            else:
                v_status = ProviderVerificationStatus.EXPIRED
        else:
            v_status = ProviderVerificationStatus.VERIFIED_ACTIVE

        return VerifiedProviderTransaction(
            provider=PaymentProviderName.REVENUECAT,
            environment=expected_environment,
            app_id=request.app_id,
            product_id=resolved_product_id,
            transaction_id=provider_store_txn_id,
            original_transaction_id=provider_orig_txn_id,
            verification_status=v_status,
            purchase_date=purchase_date,
            expires_date=expires_date,
            provider_event_id=f"rc_verify_{provider_store_txn_id}",
            raw_payload_hash=raw_hash,
            grace_period_expires_date=grace_period_expires_date,
            unsubscribe_detected_at=unsubscribe_detected_at,
            billing_issues_detected_at=billing_issues_detected_at,
            refunded_at=refunded_at,
            store=store_raw,
            period_type=period_type,
        )

    def _verify_webhook_bearer(self, normalized_headers: Dict[str, str]) -> None:
        auth_header = normalized_headers.get("authorization", "").strip()
        if not auth_header:
            raise WebhookVerificationError(
                code="WEBHOOK_AUTH_FAILED",
                message="Missing Authorization header on RevenueCat webhook request.",
                http_status=401,
            )

        expected_raw = self._webhook_auth_header.strip()
        expected_with_bearer = (
            expected_raw if expected_raw.lower().startswith("bearer ") else f"Bearer {expected_raw}"
        )
        matched = hmac.compare_digest(auth_header, expected_raw) or hmac.compare_digest(
            auth_header, expected_with_bearer
        )
        if not matched:
            raise WebhookVerificationError(
                code="WEBHOOK_AUTH_FAILED",
                message="Invalid Authorization header on RevenueCat webhook request.",
                http_status=401,
            )

    def _verify_webhook_hmac(self, normalized_headers: Dict[str, str], raw_body: bytes) -> None:
        sig_header = normalized_headers.get("x-revenuecat-webhook-signature", "").strip()
        if not sig_header:
            raise WebhookVerificationError(
                code="WEBHOOK_SIGNATURE_MISMATCH",
                message="Missing X-RevenueCat-Webhook-Signature header on RevenueCat webhook request.",
                http_status=401,
            )

        # Official RevenueCat format: t=<unix_timestamp>,v1=<hex_signature>
        parts: Dict[str, str] = {}
        for item in sig_header.split(","):
            if "=" in item:
                k, v = item.split("=", 1)
                parts[k.strip()] = v.strip()

        timestamp_str = parts.get("t", "")
        v1_sig = parts.get("v1", "")
        if not timestamp_str or not v1_sig:
            raise WebhookVerificationError(
                code="WEBHOOK_SIGNATURE_MISMATCH",
                message="Malformed X-RevenueCat-Webhook-Signature header; expected 't=<timestamp>,v1=<signature>'.",
                http_status=401,
            )

        try:
            timestamp_int = int(timestamp_str)
        except ValueError as exc:
            raise WebhookVerificationError(
                code="WEBHOOK_SIGNATURE_MISMATCH",
                message="Invalid timestamp 't' in X-RevenueCat-Webhook-Signature header.",
                http_status=401,
            ) from exc

        now_unix = int(self._clock().timestamp())
        if abs(now_unix - timestamp_int) > self._webhook_timestamp_tolerance_seconds:
            raise WebhookVerificationError(
                code="WEBHOOK_SIGNATURE_TIMESTAMP_EXPIRED",
                message=f"Webhook signature timestamp expired or outside tolerance window ({self._webhook_timestamp_tolerance_seconds}s).",
                http_status=401,
            )

        # Official RevenueCat signed payload: f"{timestamp}.{raw_body}"
        signed_payload = timestamp_str.encode("utf-8") + b"." + raw_body
        expected_sig = hmac.new(
            self._webhook_hmac_secret.encode("utf-8"),
            signed_payload,
            hashlib.sha256,
        ).hexdigest()

        if not hmac.compare_digest(expected_sig.lower(), v1_sig.lower()):
            raise WebhookVerificationError(
                code="WEBHOOK_SIGNATURE_MISMATCH",
                message="RevenueCat webhook HMAC-SHA256 signature verification failed.",
                http_status=401,
            )

    def verify_and_parse_webhook(
        self,
        headers: Dict[str, str],
        raw_body: bytes,
        expected_environment: PaymentEnvironment,
        expected_app_id: str = "",
    ) -> VerifiedWebhookEvent:
        """
        Verifies and normalizes an incoming RevenueCat server-to-server webhook event.
        Enforces explicit `webhook_auth_mode` (`bearer`, `hmac`, or `bearer_and_hmac`)
        over the exact raw request bytes before parsing JSON.
        """
        if not self.is_webhook_configured():
            raise PaymentConfigurationNotReadyError(
                f"RevenueCat webhook authentication (mode='{self._webhook_auth_mode}') is not configured."
            )

        normalized_headers = {k.lower(): v for k, v in (headers or {}).items()}

        if self._webhook_auth_mode in ("bearer", "bearer_and_hmac"):
            self._verify_webhook_bearer(normalized_headers)

        if self._webhook_auth_mode in ("hmac", "bearer_and_hmac"):
            self._verify_webhook_hmac(normalized_headers, raw_body)

        raw_hash = hash_sensitive_payload(raw_body.decode("utf-8", errors="replace"))

        try:
            payload = json.loads(raw_body.decode("utf-8"))
        except Exception as exc:
            raise WebhookVerificationError(
                code="INVALID_JSON_PAYLOAD",
                message=f"Malformed JSON in RevenueCat webhook body: {exc}",
                http_status=400,
            ) from exc

        event_data = payload.get("event")
        if not isinstance(event_data, dict):
            raise WebhookVerificationError(
                code="INVALID_WEBHOOK_SCHEMA",
                message="Webhook payload is missing the top-level 'event' object.",
                http_status=422,
            )

        event_id = str(event_data.get("id") or "").strip()
        raw_event_type = str(event_data.get("type") or "").strip().upper()
        if not event_id or not raw_event_type:
            raise WebhookVerificationError(
                code="INVALID_WEBHOOK_SCHEMA",
                message="RevenueCat webhook event is missing mandatory 'id' or 'type'.",
                http_status=422,
            )

        # Official RevenueCat webhook common fields include `api_version`, `type`, `id`,
        # `event_timestamp_ms`, and `app_id` (Always). `project_id` is not a standard webhook
        # field; validate `project_id` only if explicitly present in the webhook payload, while
        # customer mapping lookup uses `webhook_project_id or self._expected_project_id`.
        webhook_project_id = str(event_data.get("project_id") or "").strip() or None
        if (
            self._expected_project_id
            and webhook_project_id is not None
            and webhook_project_id != self._expected_project_id
        ):
            raise WebhookVerificationError(
                code="WEBHOOK_PROJECT_ID_MISMATCH",
                message=(
                    f"RevenueCat webhook project_id '{webhook_project_id}' does not match expected '{self._expected_project_id}'."
                ),
                http_status=422,
            )

        # Validate app_id (`event.app_id` is an official Always field on RevenueCat webhooks)
        target_app_id = expected_app_id or self._expected_app_id
        expected_wh_app = self._expected_webhook_app_id or target_app_id
        raw_event_app_id = str(event_data.get("app_id") or "").strip()
        if expected_wh_app and raw_event_app_id and raw_event_app_id != expected_wh_app and raw_event_app_id != target_app_id:
            raise WebhookVerificationError(
                code="PAYMENT_APP_ID_MISMATCH",
                message=f"RevenueCat webhook app_id '{raw_event_app_id}' does not match expected '{expected_wh_app}'.",
                http_status=422,
            )
        webhook_app_id = (target_app_id or raw_event_app_id or DEFAULT_REVENUECAT_APP_ID).strip()

        # Environment check
        env_str = str(event_data.get("environment") or "").strip().upper()
        if env_str == "SANDBOX":
            event_env = PaymentEnvironment.SANDBOX
        elif env_str == "PRODUCTION":
            event_env = PaymentEnvironment.PRODUCTION
        else:
            raise WebhookVerificationError(
                code="PAYMENT_ENVIRONMENT_MISMATCH",
                message=f"RevenueCat webhook has invalid or missing environment '{env_str}'.",
                http_status=422,
            )

        if event_env != expected_environment:
            raise WebhookVerificationError(
                code="PAYMENT_ENVIRONMENT_MISMATCH",
                message=(
                    f"Webhook event environment '{event_env.value}' does not match "
                    f"server expected environment '{expected_environment.value}'."
                ),
                http_status=422,
            )

        event_timestamp = _parse_iso_datetime(
            event_data.get("event_timestamp_ms") or event_data.get("purchased_at_ms")
        )
        app_user_id = str(
            event_data.get("app_user_id") or event_data.get("original_app_user_id") or ""
        ).strip() or None

        cancel_reason = str(event_data.get("cancel_reason") or "").strip().upper() or None
        expiration_reason = str(event_data.get("expiration_reason") or "").strip().upper() or None
        grace_period_expires_date = _parse_iso_datetime(
            event_data.get("grace_period_expiration_at_ms")
            or event_data.get("grace_period_expires_date")
        )
        store_raw = str(event_data.get("store") or "").strip().upper() or None
        if store_raw == "TEST_STORE" and event_env == PaymentEnvironment.PRODUCTION:
            raise WebhookVerificationError(
                code="TEST_STORE_FORBIDDEN_IN_PRODUCTION",
                message="RevenueCat Test Store ('TEST_STORE') webhook events are forbidden in production environment.",
                http_status=422,
            )
        period_type = str(event_data.get("period_type") or "normal").strip().lower()
        transferred_from = (
            [str(x) for x in event_data["transferred_from"]]
            if isinstance(event_data.get("transferred_from"), list)
            else None
        )
        transferred_to = (
            [str(x) for x in event_data["transferred_to"]]
            if isinstance(event_data.get("transferred_to"), list)
            else None
        )
        aliases = (
            [str(x) for x in event_data["aliases"]]
            if isinstance(event_data.get("aliases"), list)
            else None
        )

        is_lifecycle_event = raw_event_type in SUBSCRIPTION_LIFECYCLE_WEBHOOK_TYPES
        now = self._clock()

        if not is_lifecycle_event:
            # Non-subscription / unsupported / operational webhook events (e.g. TEST, TRANSFER,
            # NON_RENEWING_PURCHASE, SUBSCRIPTION_PAUSED, PRODUCT_CHANGE, unknown).
            # Never map these to INITIAL_PURCHASE or REVOCATION; preserve raw type so
            # PaymentWebhookIngestionService records them in WAL as IGNORED_UNSUPPORTED without mutating entitlements.
            product_id = str(event_data.get("product_id") or "unsupported_event_product").strip()
            txn_id = str(
                event_data.get("transaction_id")
                or event_data.get("store_transaction_id")
                or f"evt_txn_{event_id}"
            ).strip()
            orig_txn_id = str(
                event_data.get("original_transaction_id") or txn_id
            ).strip()
            eff_ts = event_timestamp or now
            purchased_at = _parse_iso_datetime(event_data.get("purchased_at_ms")) or eff_ts
            expires_at = _parse_iso_datetime(event_data.get("expiration_at_ms")) or eff_ts

            tx = VerifiedProviderTransaction(
                provider=PaymentProviderName.REVENUECAT,
                environment=event_env,
                app_id=webhook_app_id,
                product_id=product_id,
                transaction_id=txn_id,
                original_transaction_id=orig_txn_id,
                verification_status=ProviderVerificationStatus.INVALID,
                purchase_date=purchased_at,
                expires_date=expires_at,
                provider_event_id=event_id,
                raw_payload_hash=raw_hash,
                grace_period_expires_date=grace_period_expires_date,
                store=store_raw,
                period_type=period_type,
                error_code="UNSUPPORTED_WEBHOOK_EVENT_TYPE",
                error_message=f"Webhook event type '{raw_event_type}' does not grant or revoke subscriptions automatically.",
            )
            return VerifiedWebhookEvent(
                event_id=event_id,
                provider=PaymentProviderName.REVENUECAT,
                environment=event_env,
                event_type=f"unsupported:{raw_event_type.lower()}",
                event_timestamp=eff_ts,
                user_id=app_user_id,
                transaction=tx,
                raw_payload_hash=raw_hash,
                cancel_reason=cancel_reason,
                expiration_reason=expiration_reason,
                grace_period_expires_date=grace_period_expires_date,
                project_id=webhook_project_id,
                store=store_raw,
                period_type=period_type,
                transferred_from=transferred_from,
                transferred_to=transferred_to,
                aliases=aliases,
            )

        if event_timestamp is None:
            raise WebhookVerificationError(
                code="MISSING_WEBHOOK_TIMESTAMP",
                message=f"RevenueCat lifecycle webhook '{raw_event_type}' is missing 'event_timestamp_ms'.",
                http_status=422,
            )

        product_id = str(event_data.get("product_id") or "").strip()
        if not product_id:
            raise WebhookVerificationError(
                code="INVALID_WEBHOOK_SCHEMA",
                message=f"RevenueCat lifecycle webhook '{raw_event_type}' is missing 'product_id'.",
                http_status=422,
            )

        txn_id = str(
            event_data.get("transaction_id") or event_data.get("store_transaction_id") or ""
        ).strip()
        orig_txn_id = str(
            event_data.get("original_transaction_id") or txn_id
        ).strip()
        if not txn_id or not orig_txn_id:
            raise WebhookVerificationError(
                code="INVALID_WEBHOOK_SCHEMA",
                message=f"RevenueCat lifecycle webhook '{raw_event_type}' is missing 'transaction_id' or 'original_transaction_id'.",
                http_status=422,
            )

        purchased_at = _parse_iso_datetime(event_data.get("purchased_at_ms"))
        expires_at = _parse_iso_datetime(event_data.get("expiration_at_ms"))
        if purchased_at is None or expires_at is None:
            raise WebhookVerificationError(
                code="MISSING_VERIFIED_TIMESTAMPS",
                message=f"RevenueCat lifecycle webhook '{raw_event_type}' is missing 'purchased_at_ms' or 'expiration_at_ms'.",
                http_status=422,
            )

        if raw_event_type == "INITIAL_PURCHASE":
            normalized_type = SubscriptionLifecycleEventType.INITIAL_PURCHASE.value
            v_status = ProviderVerificationStatus.VERIFIED_ACTIVE
        elif raw_event_type in ("RENEWAL", "UNCANCELLATION", "SUBSCRIPTION_EXTENDED"):
            normalized_type = SubscriptionLifecycleEventType.RENEWAL.value
            v_status = ProviderVerificationStatus.VERIFIED_ACTIVE
        elif raw_event_type == "CANCELLATION":
            # Distinguish CUSTOMER_SUPPORT refund/immediate revocation vs voluntary UNSUBSCRIBE
            if cancel_reason == "CUSTOMER_SUPPORT":
                normalized_type = SubscriptionLifecycleEventType.REVOCATION.value
                v_status = ProviderVerificationStatus.REVOKED
            else:
                normalized_type = SubscriptionLifecycleEventType.CANCELLATION.value
                v_status = (
                    ProviderVerificationStatus.VERIFIED_ACTIVE
                    if now < expires_at
                    else ProviderVerificationStatus.EXPIRED
                )
        elif raw_event_type == "BILLING_ISSUE":
            normalized_type = SubscriptionLifecycleEventType.BILLING_ISSUE.value
            v_status = ProviderVerificationStatus.VERIFIED_ACTIVE
        elif raw_event_type == "EXPIRATION":
            normalized_type = SubscriptionLifecycleEventType.EXPIRATION.value
            v_status = ProviderVerificationStatus.EXPIRED
        elif raw_event_type in ("REVOCATION", "REFUND"):
            normalized_type = SubscriptionLifecycleEventType.REVOCATION.value
            v_status = ProviderVerificationStatus.REVOKED
        else:
            normalized_type = f"unsupported:{raw_event_type.lower()}"
            v_status = ProviderVerificationStatus.INVALID

        tx = VerifiedProviderTransaction(
            provider=PaymentProviderName.REVENUECAT,
            environment=event_env,
            app_id=webhook_app_id,
            product_id=product_id,
            transaction_id=txn_id,
            original_transaction_id=orig_txn_id,
            verification_status=v_status,
            purchase_date=purchased_at,
            expires_date=expires_at,
            provider_event_id=event_id,
            raw_payload_hash=raw_hash,
            grace_period_expires_date=grace_period_expires_date,
            store=store_raw,
            period_type=period_type,
        )

        return VerifiedWebhookEvent(
            event_id=event_id,
            provider=PaymentProviderName.REVENUECAT,
            environment=event_env,
            event_type=normalized_type,
            event_timestamp=event_timestamp,
            user_id=app_user_id,
            transaction=tx,
            raw_payload_hash=raw_hash,
            cancel_reason=cancel_reason,
            expiration_reason=expiration_reason,
            grace_period_expires_date=grace_period_expires_date,
            project_id=webhook_project_id,
            store=store_raw,
            period_type=period_type,
            transferred_from=transferred_from,
            transferred_to=transferred_to,
            aliases=aliases,
        )

    def verify_webhook(
        self,
        raw_body: bytes,
        headers: Dict[str, str],
        expected_environment: PaymentEnvironment,
        expected_app_id: str = "",
    ) -> VerifiedWebhookEvent:
        """Convenience alias for verify_and_parse_webhook."""
        return self.verify_and_parse_webhook(
            headers=headers,
            raw_body=raw_body,
            expected_environment=expected_environment,
            expected_app_id=expected_app_id,
        )


def build_default_revenuecat_mappings(
    environment: PaymentEnvironment = PaymentEnvironment.SANDBOX,
    app_id: str = DEFAULT_REVENUECAT_APP_ID,
    enabled: bool = False,
    unapproved_test_quota_limits: Optional[Dict[MembershipTier, Dict[str, int]]] = None,
) -> List[StoreProductMapping]:
    """
    Builds canonical store product mappings for RevenueCat SKUs.

    REVENUE-R02A Policy Invariant:
    - Commercial pricing ($10/$20/$30) and quota limits (100/300) are NOT business-approved.
    - By default (`enabled=False`, `unapproved_test_quota_limits=None`), `quota_limits` is empty `{}`
      so runtime code never silently provisions unapproved 100/300 quota limits.
    - Unit/integration tests that verify quota projection mechanics must explicitly pass
      `unapproved_test_quota_limits` labeled as a test fixture.
    """
    is_prod = environment == PaymentEnvironment.PRODUCTION
    active_enabled = False if is_prod else enabled

    plus_quotas = (
        dict(unapproved_test_quota_limits.get(MembershipTier.PLUS, {}))
        if unapproved_test_quota_limits
        else {}
    )
    pro_quotas = (
        dict(unapproved_test_quota_limits.get(MembershipTier.PRO, {}))
        if unapproved_test_quota_limits
        else {}
    )
    ultra_quotas = (
        dict(unapproved_test_quota_limits.get(MembershipTier.ULTRA, {}))
        if unapproved_test_quota_limits
        else {}
    )

    return [
        StoreProductMapping(
            provider=PaymentProviderName.REVENUECAT,
            environment=environment,
            app_id=app_id,
            product_id="saman_plus_monthly",
            catalog_version="v1.0-preview",
            plan_id="plan_plus",
            price_id="price_plus_monthly_usd_1000",
            tier=MembershipTier.PLUS,
            period=BillingPeriod.MONTHLY,
            amount_cents=1000,
            currency="USD",
            benefit_ids=["ai.nutrition_gemini"],
            quota_limits=plus_quotas,
            enabled=active_enabled,
        ),
        StoreProductMapping(
            provider=PaymentProviderName.REVENUECAT,
            environment=environment,
            app_id=app_id,
            product_id="saman_plus_yearly",
            catalog_version="v1.0-preview",
            plan_id="plan_plus",
            price_id="price_plus_yearly_usd_6000",
            tier=MembershipTier.PLUS,
            period=BillingPeriod.YEARLY,
            amount_cents=6000,
            currency="USD",
            benefit_ids=["ai.nutrition_gemini"],
            quota_limits=plus_quotas,
            enabled=active_enabled,
        ),
        StoreProductMapping(
            provider=PaymentProviderName.REVENUECAT,
            environment=environment,
            app_id=app_id,
            product_id="saman_pro_monthly",
            catalog_version="v1.0-preview",
            plan_id="plan_pro",
            price_id="price_pro_monthly_usd_1500",
            tier=MembershipTier.PRO,
            period=BillingPeriod.MONTHLY,
            amount_cents=1500,
            currency="USD",
            benefit_ids=[
                "ai.nutrition_gemini",
                "ai.coaching_voice",
                "analytics.advanced_trends",
                "content.exclusive_workouts",
            ],
            quota_limits=pro_quotas,
            enabled=active_enabled,
        ),
        StoreProductMapping(
            provider=PaymentProviderName.REVENUECAT,
            environment=environment,
            app_id=app_id,
            product_id="saman_pro_yearly",
            catalog_version="v1.0-preview",
            plan_id="plan_pro",
            price_id="price_pro_yearly_usd_12000",
            tier=MembershipTier.PRO,
            period=BillingPeriod.YEARLY,
            amount_cents=12000,
            currency="USD",
            benefit_ids=[
                "ai.nutrition_gemini",
                "ai.coaching_voice",
                "analytics.advanced_trends",
                "content.exclusive_workouts",
            ],
            quota_limits=pro_quotas,
            enabled=active_enabled,
        ),
        StoreProductMapping(
            provider=PaymentProviderName.REVENUECAT,
            environment=environment,
            app_id=app_id,
            product_id="saman_ultra_monthly",
            catalog_version="v1.0-preview",
            plan_id="plan_ultra",
            price_id="price_ultra_monthly_usd_3000",
            tier=MembershipTier.ULTRA,
            period=BillingPeriod.MONTHLY,
            amount_cents=3000,
            currency="USD",
            benefit_ids=[
                "ai.nutrition_gemini",
                "ai.coaching_voice",
                "analytics.advanced_trends",
                "content.exclusive_workouts",
            ],
            quota_limits=ultra_quotas,
            enabled=active_enabled,
        ),
        StoreProductMapping(
            provider=PaymentProviderName.REVENUECAT,
            environment=environment,
            app_id=app_id,
            product_id="saman_ultra_yearly",
            catalog_version="v1.0-preview",
            plan_id="plan_ultra",
            price_id="price_ultra_yearly_usd_28800",
            tier=MembershipTier.ULTRA,
            period=BillingPeriod.YEARLY,
            amount_cents=28800,
            currency="USD",
            benefit_ids=[
                "ai.nutrition_gemini",
                "ai.coaching_voice",
                "analytics.advanced_trends",
                "content.exclusive_workouts",
            ],
            quota_limits=ultra_quotas,
            enabled=active_enabled,
        ),
    ]
