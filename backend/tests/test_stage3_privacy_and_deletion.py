"""Offline unit & API tests for VN 2026 Privacy, Consent, Data Export, and Full Account Deletion.

100% in-memory fake MongoDB & mocked MediaStorageService — zero live Atlas or R2 calls.
"""

from __future__ import annotations

import copy
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import pytest
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.app.services.user_privacy_service import (
    ALL_DELETION_COLLECTIONS,
    CURRENT_CONSENT_VERSION,
    EXPORT_SCHEMA_VERSION,
    SECRET_USER_FIELDS,
    UserPrivacyService,
    compute_cv_telemetry_subject_hash,
    compute_training_log_user_hash,
)
from backend.routers.privacy import (
    get_privacy_service,
    privacy_router,
)
from backend.routers.user import get_current_user


# ---------------------------------------------------------------------------
# Strict In-Memory Fake MongoDB (Fail-Closed Against Empty Delete Filters)
# ---------------------------------------------------------------------------


def _get_nested_value(doc: Dict[str, Any], dotted_key: str) -> Any:
    if dotted_key in doc:
        return doc[dotted_key]
    parts = dotted_key.split(".")
    cur: Any = doc
    for part in parts:
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            return None
    return cur


def _matches_condition(doc_val: Any, cond: Any) -> bool:
    if isinstance(cond, dict):
        for op, expected in cond.items():
            if op == "$in":
                if isinstance(doc_val, list):
                    if not any(item in expected for item in doc_val):
                        return False
                elif doc_val not in expected:
                    return False
            elif op == "$ne":
                if doc_val == expected:
                    return False
            elif op == "$exists":
                exists = doc_val is not None
                if bool(expected) != exists:
                    return False
            else:
                raise NotImplementedError(f"Unsupported fake operator: {op}")
        return True

    if isinstance(doc_val, list):
        return cond in doc_val
    return doc_val == cond


def _matches_filter(doc: Dict[str, Any], filt: Dict[str, Any]) -> bool:
    if not filt:
        return True
    for key, expected in filt.items():
        if key == "$or":
            if not any(_matches_filter(doc, sub) for sub in expected):
                return False
        elif key == "$and":
            if not all(_matches_filter(doc, sub) for sub in expected):
                return False
        else:
            doc_val = _get_nested_value(doc, key)
            if not _matches_condition(doc_val, expected):
                return False
    return True


class _FakeResult:
    def __init__(self, *, deleted_count: int = 0, matched_count: int = 0, modified_count: int = 0, inserted_id: Any = None):
        self.deleted_count = deleted_count
        self.matched_count = matched_count
        self.modified_count = modified_count
        self.inserted_id = inserted_id


class _FakeCursor(list):
    def limit(self, n: int) -> "_FakeCursor":
        return _FakeCursor(self[:n])

    def sort(self, field: str, direction: int = 1) -> "_FakeCursor":
        reverse = direction < 0
        return _FakeCursor(sorted(self, key=lambda d: str(d.get(field) or ""), reverse=reverse))


class FakeCollection:
    def __init__(self, name: str) -> None:
        self.name = name
        self.docs: List[Dict[str, Any]] = []

    def insert_one(self, doc: Dict[str, Any]) -> _FakeResult:
        stored = copy.deepcopy(doc)
        if "_id" not in stored:
            stored["_id"] = ObjectId()
        self.docs.append(stored)
        return _FakeResult(inserted_id=stored["_id"])

    def find_one(self, filt: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        for doc in self.docs:
            if _matches_filter(doc, filt):
                return copy.deepcopy(doc)
        return None

    def find(self, filt: Optional[Dict[str, Any]] = None) -> _FakeCursor:
        effective = filt or {}
        return _FakeCursor(copy.deepcopy(d) for d in self.docs if _matches_filter(d, effective))

    def count_documents(self, filt: Optional[Dict[str, Any]] = None) -> int:
        return len(self.find(filt))

    def _apply_update(self, doc: Dict[str, Any], update: Dict[str, Any]) -> bool:
        modified = False
        if "$set" in update:
            for k, v in update["$set"].items():
                doc[k] = copy.deepcopy(v)
                modified = True
        if "$pull" in update:
            for field, pull_spec in update["$pull"].items():
                if isinstance(doc.get(field), list):
                    before = list(doc[field])
                    if isinstance(pull_spec, dict) and "$in" in pull_spec:
                        to_remove = pull_spec["$in"]
                        doc[field] = [x for x in before if x not in to_remove]
                    else:
                        doc[field] = [x for x in before if x != pull_spec]
                    if doc[field] != before:
                        modified = True
        return modified

    def update_one(self, filt: Dict[str, Any], update: Dict[str, Any], upsert: bool = False) -> _FakeResult:
        assert filt, f"SAFETY VIOLATION: empty filter in update_one on {self.name}"
        for doc in self.docs:
            if _matches_filter(doc, filt):
                mod = self._apply_update(doc, update)
                return _FakeResult(matched_count=1, modified_count=1 if mod else 0)
        if upsert:
            new_doc = copy.deepcopy(filt)
            self._apply_update(new_doc, update)
            self.insert_one(new_doc)
            return _FakeResult(matched_count=0, modified_count=1)
        return _FakeResult(matched_count=0, modified_count=0)

    def update_many(self, filt: Dict[str, Any], update: Dict[str, Any]) -> _FakeResult:
        assert filt, f"SAFETY VIOLATION: empty filter in update_many on {self.name}"
        matched = 0
        modified = 0
        for doc in self.docs:
            if _matches_filter(doc, filt):
                matched += 1
                if self._apply_update(doc, update):
                    modified += 1
        return _FakeResult(matched_count=matched, modified_count=modified)

    def delete_many(self, filt: Dict[str, Any]) -> _FakeResult:
        assert filt, f"SAFETY VIOLATION: empty filter in delete_many on {self.name}"
        kept: List[Dict[str, Any]] = []
        deleted = 0
        for doc in self.docs:
            if _matches_filter(doc, filt):
                deleted += 1
            else:
                kept.append(doc)
        self.docs = kept
        return _FakeResult(deleted_count=deleted)


class FakeDatabase:
    def __init__(self) -> None:
        self.collections: Dict[str, FakeCollection] = {}

    def __getitem__(self, name: str) -> FakeCollection:
        if name not in self.collections:
            self.collections[name] = FakeCollection(name)
        return self.collections[name]


class FakeMediaStorage:
    def __init__(
        self,
        *,
        fail_false_keys: Optional[set[str]] = None,
        raise_keys: Optional[set[str]] = None,
    ) -> None:
        self.deleted_keys: List[str] = []
        self.attempted_keys: List[str] = []
        self.fail_false_keys = fail_false_keys or set()
        self.raise_keys = raise_keys or set()

    def delete_object(self, storage_key: str) -> bool:
        self.attempted_keys.append(storage_key)
        if storage_key in self.raise_keys:
            raise RuntimeError(f"Simulated R2 network timeout for {storage_key}")
        if storage_key in self.fail_false_keys:
            return False
        self.deleted_keys.append(storage_key)
        return True


# ---------------------------------------------------------------------------
# Helpers & Fixtures
# ---------------------------------------------------------------------------


def _collect_all_keys(obj: Any) -> set[str]:
    keys: set[str] = set()
    if isinstance(obj, dict):
        for k, v in obj.items():
            keys.add(str(k))
            keys.update(_collect_all_keys(v))
    elif isinstance(obj, list):
        for item in obj:
            keys.update(_collect_all_keys(item))
    return keys


def _make_user_doc(
    *,
    email: str,
    full_name: str,
    account_id: str,
    consent: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    doc: Dict[str, Any] = {
        "_id": ObjectId(),
        "email": email,
        "full_name": full_name,
        "account_id": account_id,
        "profile": {"age": 27, "gender": "male", "height": 175, "weight": 70},
        "password": "plain-secret-never-export",
        "password_hash": "$2b$12$hashedsecret",
        "hashed_password": "$2b$12$legacyhashedsecret",
        "otp": "123456",
        "otp_code": "654321",
        "otp_expiry": datetime.now(timezone.utc),
        "otp_created_at": datetime.now(timezone.utc),
        "reset_token": "reset-tok-secret",
        "reset_code": "999888",
        "refresh_token": "refresh-tok-secret",
        "google_sub_secret": "g-sub-secret",
        "apple_sub_secret": "a-sub-secret",
        "created_at": datetime.now(timezone.utc),
    }
    if consent is not None:
        doc["consent"] = consent
    return doc


def _build_client(db: FakeDatabase, current_user: Dict[str, Any], storage: Optional[FakeMediaStorage] = None) -> TestClient:
    app = FastAPI()
    app.include_router(privacy_router)
    service = UserPrivacyService(db=db, media_storage=storage or FakeMediaStorage())
    app.dependency_overrides[get_current_user] = lambda: current_user
    app.dependency_overrides[get_privacy_service] = lambda: service
    return TestClient(app)


def _seed_all_37_collections(db: FakeDatabase, user_a: Dict[str, Any], user_b: Dict[str, Any]) -> Dict[str, Any]:
    """Seed both User A and User B across all 36 Wave-0 collections + user_consents (37 total)."""
    uid_a = str(user_a["_id"])
    uid_b = str(user_b["_id"])
    email_a = user_a["email"]
    email_b = user_b["email"]
    acct_a = user_a["account_id"]
    acct_b = user_b["account_id"]

    db["users"].insert_one(user_a)
    db["users"].insert_one(user_b)

    # 1-10: Core user data + user_consents
    for col_name in (
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
    ):
        db[col_name].insert_one({"user_id": uid_a, "user_email": email_a, "tag": f"{col_name}_a"})
        db[col_name].insert_one({"user_id": uid_b, "user_email": email_b, "tag": f"{col_name}_b"})

    # 11: otps
    db["otps"].insert_one({"email": email_a, "otp": "111222"})
    db["otps"].insert_one({"email": email_b, "otp": "333444"})

    # 12-15: AI Chat
    conv_a_id = ObjectId()
    conv_b_id = ObjectId()
    db["conversations"].insert_one({"_id": conv_a_id, "user_id": uid_a, "user_email": email_a, "title": "Chat A"})
    db["conversations"].insert_one({"_id": conv_b_id, "user_id": uid_b, "user_email": email_b, "title": "Chat B"})

    # Include one message linked ONLY via conversation_id (no user_id) to verify cascading deletion
    db["messages"].insert_one({"conversation_id": str(conv_a_id), "role": "user", "content": "Hello A"})
    db["messages"].insert_one({"conversation_id": conv_a_id, "user_id": uid_a, "role": "assistant", "content": "Hi A"})
    db["messages"].insert_one({"conversation_id": str(conv_b_id), "user_id": uid_b, "role": "user", "content": "Hello B"})

    db["chat_operations"].insert_one({"user_id": uid_a, "operation_id": "op_a", "resolved_conversation_id": conv_a_id})
    db["chat_operations"].insert_one({"user_id": uid_b, "operation_id": "op_b", "resolved_conversation_id": conv_b_id})

    db["chat_training_logs"].insert_one({"user_hash": compute_training_log_user_hash(uid_a), "operation_id": "op_a"})
    db["chat_training_logs"].insert_one({"user_hash": compute_training_log_user_hash(uid_b), "operation_id": "op_b"})

    # 16-17: Video Stories + CV Telemetry
    key_a_ok = f"saman/workouts/{acct_a}/clip_ok.mp4"
    key_a_false = f"saman/workouts/{acct_a}/clip_missing.mp4"
    key_a_raise = f"saman/workouts/{acct_a}/clip_error.mp4"
    key_b_keep = f"saman/workouts/{acct_b}/clip_b.mp4"

    db["workout_video_stories"].insert_one({"account_id": acct_a, "user_id": uid_a, "storage_key": key_a_ok})
    db["workout_video_stories"].insert_one({"account_id": acct_a, "user_id": uid_a, "storage_key": key_a_false})
    db["workout_video_stories"].insert_one({"account_id": acct_a, "user_id": uid_a, "storage_key": key_a_raise})
    db["workout_video_stories"].insert_one({"account_id": acct_b, "user_id": uid_b, "storage_key": key_b_keep})

    db["workout_cv_telemetry"].insert_one({"subject_hash": compute_cv_telemetry_subject_hash(acct_a), "exercise": "squat"})
    db["workout_cv_telemetry"].insert_one({"subject_hash": compute_cv_telemetry_subject_hash(acct_b), "exercise": "squat"})

    # 18-26: Community & DM
    db["community_posts"].insert_one({"author_id": uid_a, "author": {"id": uid_a}, "content": "Post A"})
    db["community_posts"].insert_one({"author_id": uid_b, "author": {"id": uid_b}, "content": "Post B"})

    db["community_comments"].insert_one({"user_id": uid_a, "content": "Comment A"})
    db["community_comments"].insert_one({"user_id": uid_b, "content": "Comment B"})

    db["community_answers"].insert_one({"user_id": uid_a, "content": "Answer A"})
    db["community_answers"].insert_one({"user_id": uid_b, "content": "Answer B"})

    db["community_answer_votes"].insert_one({"user_id": uid_a, "answer_id": "ans_1"})
    db["community_answer_votes"].insert_one({"user_id": uid_b, "answer_id": "ans_1"})

    db["community_interactions"].insert_one({"user_id": uid_a, "post_id": "p_1", "type": "like"})
    db["community_interactions"].insert_one({"user_id": uid_b, "post_id": "p_1", "type": "like"})

    db["community_follows"].insert_one({"follower_id": uid_a, "following_id": uid_b})
    db["community_follows"].insert_one({"follower_id": uid_b, "following_id": uid_a})
    db["community_follows"].insert_one({"follower_id": uid_b, "following_id": "user_c_external"})

    db["community_notifications"].insert_one({"recipient_id": uid_a, "actor_id": uid_b, "type": "like"})
    db["community_notifications"].insert_one({"recipient_id": uid_b, "actor_id": uid_a, "type": "follow"})
    db["community_notifications"].insert_one({"recipient_id": uid_b, "actor_id": "user_c_external", "type": "like"})

    db["community_messages"].insert_one({"sender_id": uid_a, "body": "DM from A"})
    db["community_messages"].insert_one({"sender_id": uid_b, "body": "DM from B"})

    shared_dm_id = ObjectId()
    solo_a_dm_id = ObjectId()
    solo_b_dm_id = ObjectId()
    db["community_conversations"].insert_one({"_id": shared_dm_id, "participants": [uid_a, uid_b]})
    db["community_conversations"].insert_one({"_id": solo_a_dm_id, "participants": [uid_a]})
    db["community_conversations"].insert_one({"_id": solo_b_dm_id, "participants": [uid_b, "user_c_external"]})

    # 27-28: Journal
    db["journal_reading_progress"].insert_one({"user_id": uid_a, "article_id": "art_1", "progress": 0.5})
    db["journal_reading_progress"].insert_one({"user_id": uid_b, "article_id": "art_1", "progress": 0.9})

    db["journal_bookmarks"].insert_one({"user_id": uid_a, "article_id": "art_1"})
    db["journal_bookmarks"].insert_one({"user_id": uid_b, "article_id": "art_1"})

    # 29-36: Revenue & Payments
    for col_name in (
        "payment_orders",
        "revenue_subscriptions",
        "revenue_entitlement_grants",
        "revenue_usage_buckets",
        "revenue_usage_operations",
        "food_analysis_idempotency_cache",
        "revenue_payment_transactions",
    ):
        db[col_name].insert_one({"user_id": acct_a, "account_id": acct_a, "email": email_a, "tag": f"{col_name}_a"})
        db[col_name].insert_one({"user_id": acct_b, "account_id": acct_b, "email": email_b, "tag": f"{col_name}_b"})

    db["revenue_provider_customers"].insert_one({"account_id": acct_a, "app_user_id": "rc_cus_aaaa"})
    db["revenue_provider_customers"].insert_one({"account_id": acct_b, "app_user_id": "rc_cus_bbbb"})

    return {
        "key_a_ok": key_a_ok,
        "key_a_false": key_a_false,
        "key_a_raise": key_a_raise,
        "key_b_keep": key_b_keep,
        "shared_dm_id": shared_dm_id,
        "solo_a_dm_id": solo_a_dm_id,
        "solo_b_dm_id": solo_b_dm_id,
    }


# ---------------------------------------------------------------------------
# Tests: Consent Endpoints
# ---------------------------------------------------------------------------


def test_get_consent_unconsented_defaults():
    db = FakeDatabase()
    user_a = _make_user_doc(email="alice@saman.vn", full_name="Alice", account_id="acct_a1111111111111111111111111111111")
    db["users"].insert_one(user_a)
    client = _build_client(db, user_a)

    resp = client.get("/api/user/consent")
    assert resp.status_code == 200
    body = resp.json()
    assert body["has_consented"] is False
    assert body["required_version"] == CURRENT_CONSENT_VERSION
    assert body["consent_version"] is None
    assert body["accepted_at"] is None
    assert body["accepted_health_data"] is False
    assert body["accepted_ai_processing"] is False
    assert body["acknowledged_medical_disclaimer"] is False


@pytest.mark.parametrize(
    "missing_field",
    [
        "accepted_health_data",
        "accepted_ai_processing",
        "acknowledged_medical_disclaimer",
    ],
)
def test_post_consent_missing_required_flag_returns_400(missing_field: str):
    db = FakeDatabase()
    user_a = _make_user_doc(email="alice@saman.vn", full_name="Alice", account_id="acct_a1111111111111111111111111111111")
    db["users"].insert_one(user_a)
    client = _build_client(db, user_a)

    payload = {
        "consent_version": CURRENT_CONSENT_VERSION,
        "accepted_health_data": True,
        "accepted_ai_processing": True,
        "acknowledged_medical_disclaimer": True,
        "locale": "vi",
    }
    payload[missing_field] = False

    resp = client.post("/api/user/consent", json=payload)
    assert resp.status_code == 400
    assert db["user_consents"].count_documents({}) == 0
    stored_user = db["users"].find_one({"_id": user_a["_id"]})
    assert stored_user is not None
    assert "consent" not in stored_user


def test_post_consent_success_updates_user_and_writes_immutable_audit_log():
    db = FakeDatabase()
    user_a = _make_user_doc(email="alice@saman.vn", full_name="Alice", account_id="acct_a1111111111111111111111111111111")
    db["users"].insert_one(user_a)
    client = _build_client(db, user_a)

    payload = {
        "consent_version": CURRENT_CONSENT_VERSION,
        "accepted_health_data": True,
        "accepted_ai_processing": True,
        "acknowledged_medical_disclaimer": True,
        "locale": "vi",
    }
    resp = client.post("/api/user/consent", json=payload)
    assert resp.status_code == 200
    body = resp.json()
    assert body["has_consented"] is True
    assert body["required_version"] == CURRENT_CONSENT_VERSION
    assert body["consent_version"] == CURRENT_CONSENT_VERSION
    assert body["accepted_at"].endswith("Z")
    assert body["accepted_health_data"] is True
    assert body["accepted_ai_processing"] is True
    assert body["acknowledged_medical_disclaimer"] is True

    # Verify users.consent persisted
    stored_user = db["users"].find_one({"_id": user_a["_id"]})
    assert stored_user is not None
    assert stored_user["consent"]["consent_version"] == CURRENT_CONSENT_VERSION
    assert stored_user["consent"]["accepted_health_data"] is True

    # Verify immutable audit log appends without overwriting previous entries
    resp2 = client.post("/api/user/consent", json=payload)
    assert resp2.status_code == 200
    assert db["user_consents"].count_documents({"user_id": str(user_a["_id"])}) == 2

    # Subsequent GET using updated user_doc returns has_consented == True
    client_after = _build_client(db, stored_user)
    get_resp = client_after.get("/api/user/consent")
    assert get_resp.status_code == 200
    assert get_resp.json()["has_consented"] is True


def test_get_consent_outdated_version_returns_has_consented_false():
    db = FakeDatabase()
    user_a = _make_user_doc(
        email="alice@saman.vn",
        full_name="Alice",
        account_id="acct_a1111111111111111111111111111111",
        consent={
            "consent_version": "v0.9-old",
            "accepted_at": "2025-01-01T00:00:00Z",
            "accepted_health_data": True,
            "accepted_ai_processing": True,
            "acknowledged_medical_disclaimer": True,
        },
    )
    db["users"].insert_one(user_a)
    client = _build_client(db, user_a)

    resp = client.get("/api/user/consent")
    assert resp.status_code == 200
    body = resp.json()
    assert body["has_consented"] is False
    assert body["required_version"] == CURRENT_CONSENT_VERSION
    assert body["consent_version"] == "v0.9-old"


# ---------------------------------------------------------------------------
# Tests: Data Export Endpoint
# ---------------------------------------------------------------------------


def test_export_user_data_complete_tenant_scoped_and_scrubs_all_secrets():
    db = FakeDatabase()
    user_a = _make_user_doc(email="alice@saman.vn", full_name="Alice", account_id="acct_a1111111111111111111111111111111")
    user_b = _make_user_doc(email="bob@saman.vn", full_name="Bob", account_id="acct_b2222222222222222222222222222222")
    _seed_all_37_collections(db, user_a, user_b)

    client = _build_client(db, user_a)
    resp = client.get("/api/user/export")
    assert resp.status_code == 200
    assert 'attachment; filename="saman-user-export.json"' in resp.headers.get("content-disposition", "")

    data = resp.json()
    assert data["schema_version"] == EXPORT_SCHEMA_VERSION
    assert data["exported_at"].endswith("Z")
    assert data["profile"]["email"] == "alice@saman.vn"
    assert data["profile"]["full_name"] == "Alice"

    # Verify all exported collections contain User A's records and zero User B records
    for key in (
        "consents",
        "workout_history",
        "custom_plans",
        "nutrition_plans",
        "story_logs",
        "water_logs",
        "supplement_logs",
        "user_foods",
        "weight_history",
        "journeys",
        "conversations",
    ):
        assert len(data[key]) == 1, f"Expected 1 record in {key}, got {len(data[key])}"

    assert len(data["workout_video_stories"]) == 3
    for story in data["workout_video_stories"]:
        assert story["account_id"] == user_a["account_id"]

    # Confirm zero secret fields anywhere in exported JSON
    all_keys = _collect_all_keys(data)
    leaked = all_keys.intersection(SECRET_USER_FIELDS)
    assert not leaked, f"Secret fields leaked in export: {leaked}"
    for forbidden in ("password", "password_hash", "hashed_password", "otp", "otp_code", "reset_token", "refresh_token"):
        assert forbidden not in all_keys
    assert "bob@saman.vn" not in resp.text


# ---------------------------------------------------------------------------
# Tests: Account Deletion Endpoint & 37-Collection Tenant Isolation
# ---------------------------------------------------------------------------


def test_delete_account_wrong_confirm_text_returns_400_and_deletes_nothing():
    db = FakeDatabase()
    user_a = _make_user_doc(email="alice@saman.vn", full_name="Alice", account_id="acct_a1111111111111111111111111111111")
    user_b = _make_user_doc(email="bob@saman.vn", full_name="Bob", account_id="acct_b2222222222222222222222222222222")
    _seed_all_37_collections(db, user_a, user_b)
    storage = FakeMediaStorage()
    client = _build_client(db, user_a, storage=storage)

    resp = client.request("DELETE", "/api/user/account", json={"confirm_text": "WRONG"})
    assert resp.status_code == 400
    assert storage.attempted_keys == []
    assert db["users"].count_documents({"_id": user_a["_id"]}) == 1
    assert db["workout_history"].count_documents({"user_id": str(user_a["_id"])}) == 1


@pytest.mark.parametrize("confirm_text", ["XOA", "DELETE", "  xoa  ", "delete"])
def test_delete_account_cleans_all_37_collections_and_r2_preserving_user_b(confirm_text: str):
    assert len(ALL_DELETION_COLLECTIONS) == 37

    db = FakeDatabase()
    user_a = _make_user_doc(email="alice@saman.vn", full_name="Alice", account_id="acct_a1111111111111111111111111111111")
    user_b = _make_user_doc(email="bob@saman.vn", full_name="Bob", account_id="acct_b2222222222222222222222222222222")
    seeded = _seed_all_37_collections(db, user_a, user_b)

    storage = FakeMediaStorage(
        fail_false_keys={seeded["key_a_false"]},
        raise_keys={seeded["key_a_raise"]},
    )
    client = _build_client(db, user_a, storage=storage)

    resp = client.request("DELETE", "/api/user/account", json={"confirm_text": confirm_text})
    assert resp.status_code == 200
    summary = resp.json()

    assert summary["deleted"] is True
    assert summary["collections_cleaned"] == 37
    assert summary["total_documents_deleted"] > 35
    assert summary["r2_objects_deleted"] == 1
    assert summary["r2_objects_failed"] == 2

    # R2: User A's 3 keys were attempted; User B's key was NEVER touched
    assert set(storage.attempted_keys) == {
        seeded["key_a_ok"],
        seeded["key_a_false"],
        seeded["key_a_raise"],
    }
    assert storage.deleted_keys == [seeded["key_a_ok"]]
    assert seeded["key_b_keep"] not in storage.attempted_keys

    uid_a = str(user_a["_id"])
    uid_b = str(user_b["_id"])
    acct_a = user_a["account_id"]
    acct_b = user_b["account_id"]

    # Verify User A is 100% gone from all collections while User B is 100% intact
    assert db["users"].count_documents({"_id": user_a["_id"]}) == 0
    assert db["users"].count_documents({"_id": user_b["_id"]}) == 1

    assert db["otps"].count_documents({"email": user_a["email"]}) == 0
    assert db["otps"].count_documents({"email": user_b["email"]}) == 1

    for col_name in (
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
        "conversations",
        "chat_operations",
        "journal_reading_progress",
        "journal_bookmarks",
    ):
        assert db[col_name].count_documents({"user_id": uid_a}) == 0, f"User A leaked in {col_name}"
        assert db[col_name].count_documents({"user_id": uid_b}) == 1, f"User B harmed in {col_name}"

    # Messages (including message linked only by conversation_id)
    assert db["messages"].count_documents({}) == 1
    assert db["messages"].find_one({"user_id": uid_b}) is not None

    # Hashed telemetry & training logs
    assert db["chat_training_logs"].count_documents({"user_hash": compute_training_log_user_hash(uid_a)}) == 0
    assert db["chat_training_logs"].count_documents({"user_hash": compute_training_log_user_hash(uid_b)}) == 1
    assert db["workout_cv_telemetry"].count_documents({"subject_hash": compute_cv_telemetry_subject_hash(acct_a)}) == 0
    assert db["workout_cv_telemetry"].count_documents({"subject_hash": compute_cv_telemetry_subject_hash(acct_b)}) == 1

    # Video stories
    assert db["workout_video_stories"].count_documents({"account_id": acct_a}) == 0
    assert db["workout_video_stories"].count_documents({"account_id": acct_b}) == 1

    # Community & DM
    assert db["community_posts"].count_documents({"author_id": uid_a}) == 0
    assert db["community_posts"].count_documents({"author_id": uid_b}) == 1
    assert db["community_comments"].count_documents({"user_id": uid_a}) == 0
    assert db["community_comments"].count_documents({"user_id": uid_b}) == 1
    assert db["community_answers"].count_documents({"user_id": uid_a}) == 0
    assert db["community_answers"].count_documents({"user_id": uid_b}) == 1
    assert db["community_answer_votes"].count_documents({"user_id": uid_a}) == 0
    assert db["community_answer_votes"].count_documents({"user_id": uid_b}) == 1
    assert db["community_interactions"].count_documents({"user_id": uid_a}) == 0
    assert db["community_interactions"].count_documents({"user_id": uid_b}) == 1

    # Follows & notifications involving User A deleted; User B <-> C preserved
    assert db["community_follows"].count_documents({}) == 1
    assert db["community_follows"].find_one({"follower_id": uid_b, "following_id": "user_c_external"}) is not None
    assert db["community_notifications"].count_documents({}) == 1
    assert db["community_notifications"].find_one({"recipient_id": uid_b, "actor_id": "user_c_external"}) is not None

    # DM messages & conversations
    assert db["community_messages"].count_documents({"sender_id": uid_a}) == 0
    assert db["community_messages"].count_documents({"sender_id": uid_b}) == 1
    assert db["community_conversations"].find_one({"_id": seeded["solo_a_dm_id"]}) is None
    shared_conv = db["community_conversations"].find_one({"_id": seeded["shared_dm_id"]})
    assert shared_conv is not None
    assert shared_conv["participants"] == [uid_b]
    solo_b_conv = db["community_conversations"].find_one({"_id": seeded["solo_b_dm_id"]})
    assert solo_b_conv is not None
    assert solo_b_conv["participants"] == [uid_b, "user_c_external"]

    # Revenue & Payments
    for col_name in (
        "payment_orders",
        "revenue_subscriptions",
        "revenue_entitlement_grants",
        "revenue_usage_buckets",
        "revenue_usage_operations",
        "food_analysis_idempotency_cache",
        "revenue_payment_transactions",
        "revenue_provider_customers",
    ):
        assert db[col_name].count_documents({"account_id": acct_a}) == 0, f"User A leaked in {col_name}"
        assert db[col_name].count_documents({"account_id": acct_b}) == 1, f"User B harmed in {col_name}"


def test_service_refuses_empty_identity_for_deletion():
    db = FakeDatabase()
    user_b = _make_user_doc(email="bob@saman.vn", full_name="Bob", account_id="acct_b2222222222222222222222222222222")
    db["users"].insert_one(user_b)
    service = UserPrivacyService(db=db, media_storage=FakeMediaStorage())

    with pytest.raises(ValueError):
        service.delete_user_account({})

    assert db["users"].count_documents({"_id": user_b["_id"]}) == 1
