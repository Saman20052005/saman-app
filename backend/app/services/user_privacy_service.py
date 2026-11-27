"""User Privacy & Legal Compliance Service (VN 2026 — Decree 13/2023/ND-CP & Law on Personal Data Protection).

Provides:
1. Consent status check against CURRENT_CONSENT_VERSION.
2. Explicit 3-flag consent recording (users.consent + immutable user_consents audit log).
3. Full personal data export (JSON) with strict secret-field scrubbing.
4. Tenant-isolated account deletion across Cloudflare R2 media objects and all 36 Wave-0
   MongoDB collections + user_consents (37 collections total).
"""

from __future__ import annotations

import hashlib
import logging
import os
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional, Sequence, Set, Tuple

from bson import ObjectId

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CURRENT_CONSENT_VERSION: str = "v1.0-vn-2026"
EXPORT_SCHEMA_VERSION: str = "saman_export_v1"
EXPORT_COLLECTION_LIMIT: int = 5000

SECRET_USER_FIELDS: frozenset[str] = frozenset(
    {
        "password",
        "password_hash",
        "hashed_password",
        "otp",
        "otp_code",
        "otp_expiry",
        "otp_created_at",
        "reset_token",
        "reset_code",
        "refresh_token",
        "google_sub_secret",
        "apple_sub_secret",
    }
)

# Exhaustive inventory of 36 Wave-0 user-scoped collections + user_consents (37 total).
# Note: `users` is ALWAYS deleted last after all dependent collections are cleaned.
USER_CORE_DATA_COLLECTIONS: Tuple[str, ...] = (
    "nutrition_plans",
    "story_logs",
    "workout_history",
    "custom_plans",
    "water_logs",
    "supplement_logs",
    "user_foods",
    "weight_history",
    "journeys",
    "user_consents",
)

USER_JOURNAL_COLLECTIONS: Tuple[str, ...] = (
    "journal_reading_progress",
    "journal_bookmarks",
)

USER_REVENUE_COLLECTIONS: Tuple[str, ...] = (
    "payment_orders",
    "revenue_subscriptions",
    "revenue_entitlement_grants",
    "revenue_usage_buckets",
    "revenue_usage_operations",
    "food_analysis_idempotency_cache",
    "revenue_payment_transactions",
    "revenue_provider_customers",
)

ALL_DELETION_COLLECTIONS: Tuple[str, ...] = (
    *USER_CORE_DATA_COLLECTIONS,
    "otps",
    "conversations",
    "messages",
    "chat_operations",
    "chat_training_logs",
    "workout_video_stories",
    "workout_cv_telemetry",
    "community_posts",
    "community_comments",
    "community_answers",
    "community_answer_votes",
    "community_interactions",
    "community_follows",
    "community_notifications",
    "community_messages",
    "community_conversations",
    *USER_JOURNAL_COLLECTIONS,
    *USER_REVENUE_COLLECTIONS,
    "users",
)


# ---------------------------------------------------------------------------
# Serialization, Scrubbing & Hash Helpers
# ---------------------------------------------------------------------------


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _format_datetime_iso(value: Any) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, datetime):
        dt = (
            value.replace(tzinfo=timezone.utc)
            if value.tzinfo is None or value.tzinfo.utcoffset(value) is None
            else value.astimezone(timezone.utc)
        )
        return dt.isoformat().replace("+00:00", "Z")
    if isinstance(value, str):
        cleaned = value.strip()
        return cleaned or None
    return str(value)


def _is_secret_key(key: str, *, is_user_root: bool = False) -> bool:
    lower = key.strip().lower()
    if lower in SECRET_USER_FIELDS:
        return True
    if lower.startswith("otp") or lower.startswith("reset_"):
        return True
    if "password" in lower or "secret" in lower:
        return True
    if is_user_root and "token" in lower:
        return True
    return False


def _scrub_document(doc: Any, *, _is_user_root: bool = False) -> Any:
    """Recursively convert BSON/datetime types to JSON-safe values and remove secret keys."""
    if doc is None or isinstance(doc, (bool, int, float, str)):
        return doc
    if isinstance(doc, ObjectId):
        return str(doc)
    if isinstance(doc, datetime):
        return _format_datetime_iso(doc)
    if isinstance(doc, bytes):
        return "[BINARY_OMITTED]"
    if isinstance(doc, dict):
        cleaned: Dict[str, Any] = {}
        for k, v in doc.items():
            key_str = str(k)
            if _is_secret_key(key_str, is_user_root=_is_user_root):
                continue
            cleaned[key_str] = _scrub_document(v, _is_user_root=False)
        return cleaned
    if isinstance(doc, (list, tuple, set)):
        return [_scrub_document(item, _is_user_root=False) for item in doc]
    return str(doc)


def compute_cv_telemetry_subject_hash(account_id_or_uid: str) -> str:
    """One-way anonymous hash matching backend/routers/workout.py (_compute_anonymous_subject_hash)."""
    clean = str(account_id_or_uid or "").strip()
    if not clean:
        return ""
    salt = os.getenv("CV_TELEMETRY_HASH_SALT", "saman-ultra-p5-anon-v1")
    raw = f"{salt}:{clean}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:16]


def compute_training_log_user_hash(user_id: str) -> str:
    """One-way hash matching backend/app/services/training_log_service.py (hash_user_id)."""
    clean = str(user_id or "").strip()
    if not clean:
        return ""
    salt = os.getenv("TRAINING_LOG_SALT", "saman-training-v1")
    return hashlib.sha256(f"{salt}:{clean}".encode("utf-8")).hexdigest()[:24]


def _dedupe_non_empty(values: Iterable[Any]) -> List[Any]:
    result: List[Any] = []
    seen_reprs: Set[Tuple[type, str]] = set()
    for val in values:
        if val is None:
            continue
        if isinstance(val, str):
            val = val.strip()
            if not val:
                continue
        key = (type(val), str(val))
        if key not in seen_reprs:
            seen_reprs.add(key)
            result.append(val)
    return result


def _safe_or_filter(clauses: Sequence[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Build a fail-closed MongoDB filter. Returns None if no valid non-empty clause exists."""
    valid_clauses: List[Dict[str, Any]] = []
    for clause in clauses:
        if not isinstance(clause, dict) or not clause:
            continue
        if clause not in valid_clauses:
            valid_clauses.append(clause)
    if not valid_clauses:
        return None
    if len(valid_clauses) == 1:
        return valid_clauses[0]
    return {"$or": valid_clauses}


def _build_field_match_clauses(field_name: str, values: Sequence[Any]) -> List[Dict[str, Any]]:
    clean_vals = _dedupe_non_empty(values)
    if not clean_vals:
        return []
    if len(clean_vals) == 1:
        return [{field_name: clean_vals[0]}]
    return [{field_name: {"$in": clean_vals}}]


# ---------------------------------------------------------------------------
# Service Implementation
# ---------------------------------------------------------------------------


class UserPrivacyService:
    """Service managing user legal consent, personal data export, and full account deletion."""

    def __init__(self, db: Any, media_storage: Any = None) -> None:
        self.db = db
        self._media_storage = media_storage

    def _get_collection(self, name: str) -> Any:
        if self.db is None:
            return None
        try:
            return self.db[name]
        except Exception as exc:
            logger.warning("Unable to access collection %s: %s", name, exc)
            return None

    def _get_media_storage(self) -> Any:
        if self._media_storage is not None:
            return self._media_storage
        try:
            from backend.app.services.media_storage_service import get_media_storage_service

            return get_media_storage_service()
        except Exception as exc:
            logger.warning("MediaStorageService unavailable during privacy operation: %s", exc)
            return None

    def _extract_identifiers(
        self,
        user_doc: Dict[str, Any],
        *,
        account_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Extract all non-empty tenant-scoped identifiers for the given user without creating records."""
        if not isinstance(user_doc, dict):
            user_doc = {}

        raw_id = user_doc.get("_id")
        if raw_id is None:
            raw_id = user_doc.get("user_id") or user_doc.get("id")

        user_id_str = str(raw_id).strip() if raw_id is not None else ""
        id_variants: List[Any] = []
        if raw_id is not None and str(raw_id).strip():
            id_variants.append(raw_id)
        if user_id_str:
            id_variants.append(user_id_str)
            if ObjectId.is_valid(user_id_str):
                id_variants.append(ObjectId(user_id_str))
        id_variants = _dedupe_non_empty(id_variants)

        raw_email = user_doc.get("email")
        email_raw_str = raw_email.strip() if isinstance(raw_email, str) else ""
        email = email_raw_str.lower()
        email_variants = _dedupe_non_empty([email, email_raw_str])

        resolved_account_id = ""
        for candidate in (account_id, user_doc.get("account_id")):
            if isinstance(candidate, str) and candidate.strip():
                resolved_account_id = candidate.strip()
                break

        # Read-only lookup on users collection for existing account_id (never creates one)
        if not resolved_account_id and self.db is not None:
            users_col = self._get_collection("users")
            if users_col is not None:
                lookup_clauses: List[Dict[str, Any]] = []
                lookup_clauses.extend(_build_field_match_clauses("_id", id_variants))
                lookup_clauses.extend(_build_field_match_clauses("email", email_variants))
                lookup_filter = _safe_or_filter(lookup_clauses)
                if lookup_filter is not None:
                    try:
                        fresh = users_col.find_one(lookup_filter)
                        if isinstance(fresh, dict):
                            acct_val = fresh.get("account_id")
                            if isinstance(acct_val, str) and acct_val.strip():
                                resolved_account_id = acct_val.strip()
                    except Exception:
                        pass

        subject_hash_inputs = _dedupe_non_empty([resolved_account_id, user_id_str, email])
        subject_hashes = _dedupe_non_empty(
            compute_cv_telemetry_subject_hash(val) for val in subject_hash_inputs
        )

        user_hash_inputs = _dedupe_non_empty([user_id_str, resolved_account_id])
        user_hashes = _dedupe_non_empty(
            compute_training_log_user_hash(val) for val in user_hash_inputs
        )

        return {
            "raw_id": raw_id,
            "user_id_str": user_id_str,
            "id_variants": id_variants,
            "email": email,
            "email_variants": email_variants,
            "account_id": resolved_account_id,
            "subject_hashes": subject_hashes,
            "user_hashes": user_hashes,
        }

    def _safe_find_docs(
        self,
        collection_name: str,
        query_filter: Optional[Dict[str, Any]],
        *,
        limit: int = EXPORT_COLLECTION_LIMIT,
    ) -> List[Dict[str, Any]]:
        """Safely read documents matching a non-empty filter; never queries with an empty filter."""
        if not query_filter:
            return []
        col = self._get_collection(collection_name)
        if col is None:
            return []
        try:
            cursor = col.find(query_filter)
            if hasattr(cursor, "limit") and limit > 0:
                cursor = cursor.limit(limit)
            return [doc for doc in list(cursor) if isinstance(doc, dict)]
        except Exception as exc:
            logger.warning("Safe read failed on collection %s: %s", collection_name, exc)
            return []

    def _safe_delete_many(
        self,
        collection_name: str,
        query_filter: Optional[Dict[str, Any]],
    ) -> Tuple[bool, int]:
        """Execute delete_many ONLY when query_filter is strictly non-empty.

        Returns (collection_processed, deleted_count).
        """
        if not query_filter:
            return (False, 0)
        col = self._get_collection(collection_name)
        if col is None:
            return (False, 0)
        try:
            res = col.delete_many(query_filter)
            deleted = int(getattr(res, "deleted_count", 0) or 0)
            return (True, deleted)
        except Exception as exc:
            logger.warning("Safe delete_many failed on collection %s: %s", collection_name, exc)
            return (False, 0)

    # -----------------------------------------------------------------------
    # 1. GET Consent Status
    # -----------------------------------------------------------------------

    def get_consent_status(self, user_doc: Dict[str, Any]) -> Dict[str, Any]:
        """Return user's current consent state compared against CURRENT_CONSENT_VERSION."""
        consent_doc: Optional[Dict[str, Any]] = None
        if isinstance(user_doc, dict) and isinstance(user_doc.get("consent"), dict):
            consent_doc = user_doc["consent"]

        # Fallback: check latest immutable record in user_consents
        if consent_doc is None and self.db is not None:
            ident = self._extract_identifiers(user_doc)
            clauses: List[Dict[str, Any]] = []
            clauses.extend(_build_field_match_clauses("user_id", ident["id_variants"]))
            clauses.extend(_build_field_match_clauses("user_email", ident["email_variants"]))
            clauses.extend(_build_field_match_clauses("email", ident["email_variants"]))
            query_filter = _safe_or_filter(clauses)
            docs = self._safe_find_docs("user_consents", query_filter, limit=200)
            if docs:
                docs.sort(
                    key=lambda d: str(_format_datetime_iso(d.get("accepted_at")) or ""),
                    reverse=True,
                )
                consent_doc = docs[0]

        if not isinstance(consent_doc, dict):
            return {
                "has_consented": False,
                "required_version": CURRENT_CONSENT_VERSION,
                "consent_version": None,
                "accepted_at": None,
                "accepted_health_data": False,
                "accepted_ai_processing": False,
                "acknowledged_medical_disclaimer": False,
            }

        consent_version = consent_doc.get("consent_version")
        consent_version_str = (
            consent_version.strip()
            if isinstance(consent_version, str) and consent_version.strip()
            else None
        )
        accepted_at = _format_datetime_iso(consent_doc.get("accepted_at"))
        accepted_health_data = consent_doc.get("accepted_health_data") is True
        accepted_ai_processing = consent_doc.get("accepted_ai_processing") is True
        acknowledged_medical_disclaimer = consent_doc.get("acknowledged_medical_disclaimer") is True

        has_consented = (
            consent_version_str == CURRENT_CONSENT_VERSION
            and accepted_health_data
            and accepted_ai_processing
            and acknowledged_medical_disclaimer
        )

        return {
            "has_consented": has_consented,
            "required_version": CURRENT_CONSENT_VERSION,
            "consent_version": consent_version_str,
            "accepted_at": accepted_at,
            "accepted_health_data": accepted_health_data,
            "accepted_ai_processing": accepted_ai_processing,
            "acknowledged_medical_disclaimer": acknowledged_medical_disclaimer,
        }

    # -----------------------------------------------------------------------
    # 2. POST Record Consent
    # -----------------------------------------------------------------------

    def record_consent(
        self,
        user_doc: Dict[str, Any],
        *,
        consent_version: str = CURRENT_CONSENT_VERSION,
        accepted_health_data: bool,
        accepted_ai_processing: bool,
        acknowledged_medical_disclaimer: bool,
        locale: str = "vi",
    ) -> Dict[str, Any]:
        """Validate all 3 mandatory consent flags, update users.consent, and append immutable audit log."""
        if not (
            accepted_health_data is True
            and accepted_ai_processing is True
            and acknowledged_medical_disclaimer is True
        ):
            raise ValueError(
                "All three mandatory legal acknowledgements "
                "(accepted_health_data, accepted_ai_processing, acknowledged_medical_disclaimer) "
                "must be explicitly accepted (True)."
            )

        cleaned_version = (consent_version or "").strip() or CURRENT_CONSENT_VERSION
        cleaned_locale = (locale or "vi").strip() or "vi"
        accepted_at = _utc_now_iso()

        ident = self._extract_identifiers(user_doc)
        if not ident["id_variants"] and not ident["email_variants"]:
            raise ValueError("Cannot record consent without a valid user identifier.")

        consent_record: Dict[str, Any] = {
            "consent_version": cleaned_version,
            "accepted_at": accepted_at,
            "accepted_health_data": True,
            "accepted_ai_processing": True,
            "acknowledged_medical_disclaimer": True,
            "locale": cleaned_locale,
        }

        users_col = self._get_collection("users")
        if users_col is not None:
            user_filter = (
                {"_id": ident["raw_id"]}
                if ident["raw_id"] is not None
                else _safe_or_filter(_build_field_match_clauses("email", ident["email_variants"]))
            )
            if user_filter is not None:
                users_col.update_one(user_filter, {"$set": {"consent": consent_record}})

        consents_col = self._get_collection("user_consents")
        if consents_col is not None:
            audit_entry: Dict[str, Any] = {
                "user_id": ident["user_id_str"],
                "user_email": ident["email"],
                "consent_version": cleaned_version,
                "accepted_at": accepted_at,
                "accepted_health_data": True,
                "accepted_ai_processing": True,
                "acknowledged_medical_disclaimer": True,
                "locale": cleaned_locale,
                "recorded_at": datetime.now(timezone.utc),
            }
            consents_col.insert_one(audit_entry)

        has_consented = cleaned_version == CURRENT_CONSENT_VERSION
        return {
            "has_consented": has_consented,
            "required_version": CURRENT_CONSENT_VERSION,
            "consent_version": cleaned_version,
            "accepted_at": accepted_at,
            "accepted_health_data": True,
            "accepted_ai_processing": True,
            "acknowledged_medical_disclaimer": True,
        }

    # -----------------------------------------------------------------------
    # 3. GET Export Personal Data
    # -----------------------------------------------------------------------

    def export_user_data(
        self,
        user_doc: Dict[str, Any],
        *,
        account_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Export user's personal data as a JSON-safe dictionary with all secret fields scrubbed."""
        ident = self._extract_identifiers(user_doc, account_id=account_id)
        if not ident["id_variants"] and not ident["email_variants"] and not ident["account_id"]:
            raise ValueError("Cannot export data without a valid user identifier.")

        # Prefer freshest user document from DB when available
        profile_source: Dict[str, Any] = dict(user_doc) if isinstance(user_doc, dict) else {}
        users_col = self._get_collection("users")
        if users_col is not None:
            user_filter = (
                {"_id": ident["raw_id"]}
                if ident["raw_id"] is not None
                else _safe_or_filter(_build_field_match_clauses("email", ident["email_variants"]))
            )
            if user_filter is not None:
                try:
                    fresh = users_col.find_one(user_filter)
                    if isinstance(fresh, dict):
                        profile_source = fresh
                except Exception:
                    pass

        scrubbed_profile = _scrub_document(profile_source, _is_user_root=True)

        # Standard user filter for personal collections
        standard_user_ids = _dedupe_non_empty(
            [*ident["id_variants"], ident["account_id"]]
        )
        standard_clauses: List[Dict[str, Any]] = []
        standard_clauses.extend(_build_field_match_clauses("user_id", standard_user_ids))
        standard_clauses.extend(_build_field_match_clauses("user_email", ident["email_variants"]))
        standard_clauses.extend(_build_field_match_clauses("email", ident["email_variants"]))
        standard_filter = _safe_or_filter(standard_clauses)

        # Video stories filter (account_id / user_id / user_email)
        video_clauses: List[Dict[str, Any]] = []
        if ident["account_id"]:
            video_clauses.append({"account_id": ident["account_id"]})
        video_clauses.extend(_build_field_match_clauses("user_id", standard_user_ids))
        video_clauses.extend(_build_field_match_clauses("user_email", ident["email_variants"]))
        video_filter = _safe_or_filter(video_clauses)

        def _export_list(col_name: str, filt: Optional[Dict[str, Any]]) -> List[Dict[str, Any]]:
            raw_docs = self._safe_find_docs(col_name, filt)
            return [_scrub_document(d) for d in raw_docs]

        raw_conversations = self._safe_find_docs("conversations", standard_filter)
        conversations_summary: List[Dict[str, Any]] = []
        for conv in raw_conversations:
            scrubbed_conv = _scrub_document(conv)
            conversations_summary.append(
                {
                    "id": scrubbed_conv.get("_id") or scrubbed_conv.get("id"),
                    "title": scrubbed_conv.get("title"),
                    "created_at": scrubbed_conv.get("created_at"),
                    "updated_at": scrubbed_conv.get("updated_at"),
                }
            )

        raw_video_stories = self._safe_find_docs("workout_video_stories", video_filter)
        video_stories_metadata = [_scrub_document(doc) for doc in raw_video_stories]

        return {
            "exported_at": _utc_now_iso(),
            "schema_version": EXPORT_SCHEMA_VERSION,
            "profile": scrubbed_profile,
            "consents": _export_list("user_consents", standard_filter),
            "workout_history": _export_list("workout_history", standard_filter),
            "custom_plans": _export_list("custom_plans", standard_filter),
            "nutrition_plans": _export_list("nutrition_plans", standard_filter),
            "story_logs": _export_list("story_logs", standard_filter),
            "water_logs": _export_list("water_logs", standard_filter),
            "supplement_logs": _export_list("supplement_logs", standard_filter),
            "user_foods": _export_list("user_foods", standard_filter),
            "weight_history": _export_list("weight_history", standard_filter),
            "journeys": _export_list("journeys", standard_filter),
            "workout_video_stories": video_stories_metadata,
            "conversations": conversations_summary,
        }

    # -----------------------------------------------------------------------
    # 4. DELETE Account (R2 Cleanup + Full 36 Collections + user_consents)
    # -----------------------------------------------------------------------

    def delete_user_account(
        self,
        user_doc: Dict[str, Any],
        *,
        account_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Permanently delete a user's R2 media objects and all tenant-scoped data across 37 collections.

        Strict tenant isolation:
        - Refuses to execute if no non-empty user identifier is available.
        - Every delete/update filter is constructed exclusively from non-empty user identifiers.
        - R2 object deletion is fault-tolerant per file so a storage error never blocks erasure.
        - `users` document is deleted LAST after all dependent collections are cleaned.
        """
        ident = self._extract_identifiers(user_doc, account_id=account_id)
        if not ident["id_variants"] and not ident["email_variants"] and not ident["account_id"]:
            raise ValueError("Cannot delete user account without a valid non-empty user identifier.")

        id_variants = ident["id_variants"]
        email_variants = ident["email_variants"]
        acct_id = ident["account_id"]
        subject_hashes = ident["subject_hashes"]
        user_hashes = ident["user_hashes"]

        user_and_acct_ids = _dedupe_non_empty([*id_variants, acct_id])
        revenue_user_ids = _dedupe_non_empty([*id_variants, acct_id, *email_variants])

        # -------------------------------------------------------------------
        # Step 1: Collect & delete user's workout video objects on Cloudflare R2
        # -------------------------------------------------------------------
        video_clauses: List[Dict[str, Any]] = []
        if acct_id:
            video_clauses.append({"account_id": acct_id})
        video_clauses.extend(_build_field_match_clauses("user_id", user_and_acct_ids))
        video_clauses.extend(_build_field_match_clauses("user_email", email_variants))
        video_filter = _safe_or_filter(video_clauses)

        r2_deleted_count = 0
        r2_failed_count = 0
        video_docs = self._safe_find_docs("workout_video_stories", video_filter, limit=10000)
        storage_keys: List[str] = []
        seen_keys: Set[str] = set()
        for vdoc in video_docs:
            raw_key = vdoc.get("storage_key")
            if isinstance(raw_key, str) and raw_key.strip():
                key_clean = raw_key.strip()
                if key_clean not in seen_keys:
                    seen_keys.add(key_clean)
                    storage_keys.append(key_clean)

        if storage_keys:
            storage = self._get_media_storage()
            for storage_key in storage_keys:
                try:
                    ok = bool(storage.delete_object(storage_key)) if storage is not None else False
                    if ok:
                        r2_deleted_count += 1
                    else:
                        r2_failed_count += 1
                except Exception as exc:
                    logger.warning(
                        "R2 object deletion failed for storage_key=%s: %s",
                        storage_key,
                        exc,
                    )
                    r2_failed_count += 1

        # -------------------------------------------------------------------
        # Step 2: Clean all 36 Wave-0 collections + user_consents (37 total)
        # -------------------------------------------------------------------
        collections_cleaned = 0
        total_documents_deleted = 0

        def _clean(col_name: str, filt: Optional[Dict[str, Any]]) -> None:
            nonlocal collections_cleaned, total_documents_deleted
            processed, deleted = self._safe_delete_many(col_name, filt)
            if processed:
                collections_cleaned += 1
                total_documents_deleted += deleted

        # 2A. Core User Data (10 collections incl. user_consents)
        core_clauses: List[Dict[str, Any]] = []
        core_clauses.extend(_build_field_match_clauses("user_id", user_and_acct_ids))
        core_clauses.extend(_build_field_match_clauses("user_email", email_variants))
        core_clauses.extend(_build_field_match_clauses("email", email_variants))
        core_filter = _safe_or_filter(core_clauses)

        for col_name in USER_CORE_DATA_COLLECTIONS:
            _clean(col_name, core_filter)

        # 2B. Auth / OTP (otps)
        otp_clauses: List[Dict[str, Any]] = []
        otp_clauses.extend(_build_field_match_clauses("email", email_variants))
        otp_clauses.extend(_build_field_match_clauses("user_email", email_variants))
        otp_clauses.extend(_build_field_match_clauses("user_id", id_variants))
        _clean("otps", _safe_or_filter(otp_clauses))

        # 2C. AI Chat (conversations, messages, chat_operations, chat_training_logs)
        conv_docs = self._safe_find_docs("conversations", core_filter, limit=10000)
        conv_ids: List[Any] = []
        for cdoc in conv_docs:
            cid = cdoc.get("_id")
            if cid is not None:
                conv_ids.append(cid)
                cid_str = str(cid).strip()
                if cid_str:
                    conv_ids.append(cid_str)
            alt_cid = cdoc.get("conversation_id")
            if alt_cid is not None and str(alt_cid).strip():
                conv_ids.append(alt_cid)
        conv_ids = _dedupe_non_empty(conv_ids)

        _clean("conversations", core_filter)

        msg_clauses: List[Dict[str, Any]] = list(core_clauses)
        if conv_ids:
            msg_clauses.extend(_build_field_match_clauses("conversation_id", conv_ids))
        _clean("messages", _safe_or_filter(msg_clauses))

        chat_op_clauses: List[Dict[str, Any]] = list(core_clauses)
        if conv_ids:
            chat_op_clauses.extend(_build_field_match_clauses("resolved_conversation_id", conv_ids))
            chat_op_clauses.extend(_build_field_match_clauses("conversation_id", conv_ids))
        _clean("chat_operations", _safe_or_filter(chat_op_clauses))

        training_clauses: List[Dict[str, Any]] = []
        training_clauses.extend(_build_field_match_clauses("user_hash", user_hashes))
        training_clauses.extend(_build_field_match_clauses("user_id", id_variants))
        _clean("chat_training_logs", _safe_or_filter(training_clauses))

        # 2D. Video & CV Telemetry (workout_video_stories, workout_cv_telemetry)
        _clean("workout_video_stories", video_filter)

        telemetry_clauses: List[Dict[str, Any]] = []
        telemetry_clauses.extend(_build_field_match_clauses("subject_hash", subject_hashes))
        telemetry_clauses.extend(_build_field_match_clauses("user_id", user_and_acct_ids))
        if acct_id:
            telemetry_clauses.append({"account_id": acct_id})
        _clean("workout_cv_telemetry", _safe_or_filter(telemetry_clauses))

        # 2E. Community & DM (9 collections)
        author_clauses: List[Dict[str, Any]] = []
        author_clauses.extend(_build_field_match_clauses("author_id", id_variants))
        author_clauses.extend(_build_field_match_clauses("user_id", id_variants))
        author_clauses.extend(_build_field_match_clauses("author.id", id_variants))
        author_filter = _safe_or_filter(author_clauses)

        _clean("community_posts", author_filter)
        _clean("community_comments", author_filter)
        _clean("community_answers", author_filter)
        _clean("community_answer_votes", _safe_or_filter(_build_field_match_clauses("user_id", id_variants)))
        _clean("community_interactions", _safe_or_filter(_build_field_match_clauses("user_id", id_variants)))

        follow_clauses: List[Dict[str, Any]] = []
        follow_clauses.extend(_build_field_match_clauses("follower_id", id_variants))
        follow_clauses.extend(_build_field_match_clauses("following_id", id_variants))
        _clean("community_follows", _safe_or_filter(follow_clauses))

        notif_clauses: List[Dict[str, Any]] = []
        notif_clauses.extend(_build_field_match_clauses("recipient_id", id_variants))
        notif_clauses.extend(_build_field_match_clauses("actor_id", id_variants))
        _clean("community_notifications", _safe_or_filter(notif_clauses))

        _clean("community_messages", _safe_or_filter(_build_field_match_clauses("sender_id", id_variants)))

        # community_conversations: $pull user from shared conversations, delete solo conversations
        dm_conv_col = self._get_collection("community_conversations")
        if dm_conv_col is not None and id_variants:
            dm_conv_filter = _safe_or_filter(_build_field_match_clauses("participants", id_variants))
            if dm_conv_filter is not None:
                try:
                    id_str_set = {str(v) for v in id_variants}
                    matched_convs = list(dm_conv_col.find(dm_conv_filter))
                    solo_ids: List[Any] = []
                    shared_ids: List[Any] = []
                    for conv_doc in matched_convs:
                        if not isinstance(conv_doc, dict) or "_id" not in conv_doc:
                            continue
                        participants = conv_doc.get("participants")
                        if not isinstance(participants, list):
                            solo_ids.append(conv_doc["_id"])
                            continue
                        remaining = [p for p in participants if str(p) not in id_str_set]
                        if not remaining:
                            solo_ids.append(conv_doc["_id"])
                        else:
                            shared_ids.append(conv_doc["_id"])

                    if solo_ids:
                        del_res = dm_conv_col.delete_many({"_id": {"$in": solo_ids}})
                        total_documents_deleted += int(getattr(del_res, "deleted_count", 0) or 0)
                    if shared_ids:
                        pull_expr: Any = (
                            id_variants[0] if len(id_variants) == 1 else {"$in": id_variants}
                        )
                        dm_conv_col.update_many(
                            {"_id": {"$in": shared_ids}},
                            {"$pull": {"participants": pull_expr}},
                        )
                    collections_cleaned += 1
                except Exception as exc:
                    logger.warning("Cleanup failed on community_conversations: %s", exc)

        # 2F. Journal (2 collections)
        for col_name in USER_JOURNAL_COLLECTIONS:
            _clean(col_name, core_filter)

        # 2G. Revenue & Payments (8 collections)
        revenue_clauses: List[Dict[str, Any]] = []
        revenue_clauses.extend(_build_field_match_clauses("user_id", revenue_user_ids))
        if acct_id:
            revenue_clauses.append({"account_id": acct_id})
        revenue_clauses.extend(_build_field_match_clauses("email", email_variants))
        revenue_clauses.extend(_build_field_match_clauses("user_email", email_variants))
        revenue_filter = _safe_or_filter(revenue_clauses)

        for col_name in USER_REVENUE_COLLECTIONS:
            _clean(col_name, revenue_filter)

        # 2H. Users document — ALWAYS deleted LAST after all dependent collections are clean
        user_delete_clauses: List[Dict[str, Any]] = []
        if id_variants:
            user_delete_clauses.extend(_build_field_match_clauses("_id", id_variants))
        elif email_variants:
            user_delete_clauses.extend(_build_field_match_clauses("email", email_variants))
        elif acct_id:
            user_delete_clauses.append({"account_id": acct_id})
        _clean("users", _safe_or_filter(user_delete_clauses))

        return {
            "deleted": True,
            "collections_cleaned": collections_cleaned,
            "total_documents_deleted": total_documents_deleted,
            "r2_objects_deleted": r2_deleted_count,
            "r2_objects_failed": r2_failed_count,
        }
