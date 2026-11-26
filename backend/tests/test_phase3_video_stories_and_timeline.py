"""Unit tests for Phase 3: Workout Video Stories, Storage Presign/Complete/Read,
and RepTimeline additive integration with Workout Sessions.
"""

from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import threading
from typing import Any, Dict, List, Optional
from unittest.mock import MagicMock, patch

import pytest
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))
BACKEND_DIR = REPO_ROOT / "backend"
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

import backend.app.database as app_db
from backend.app.database_revenue import (
    COLL_SUBSCRIPTIONS,
    COLL_USAGE_BUCKETS,
    COLL_USAGE_OPERATIONS,
    COLL_ENTITLEMENT_GRANTS,
)
from backend.app.models.revenue import MembershipTier, SubscriptionStatus
from backend.app.models.workout_video_story import (
    MAX_VIDEO_STORY_BYTES,
    RepTimelineItem,
)
from backend.app.services.media_storage_service import (
    MediaStorageConfigError,
    PresignedUploadResult,
)
from backend.auth_utils import get_current_user
import backend.routers.workout as workout_mod


# ---------------------------------------------------------------------------
# In-memory MongoDB Mock
# ---------------------------------------------------------------------------

class FakeCollection:
    def __init__(self, name: str):
        self.name = name
        self.docs: List[Dict[str, Any]] = []
        self._lock = threading.Lock()

    def _matches(self, doc: Dict[str, Any], query: Optional[Dict[str, Any]]) -> bool:
        if not query:
            return True
        for k, v in query.items():
            if k == "$or":
                if not any(self._matches(doc, clause) for clause in v):
                    return False
                continue
            if k == "$and":
                if not all(self._matches(doc, clause) for clause in v):
                    return False
                continue
            doc_val = doc.get(k)
            if isinstance(v, dict):
                if "$in" in v and doc_val not in v["$in"]:
                    return False
                if "$exists" in v:
                    exists = k in doc and doc[k] is not None
                    if exists != v["$exists"]:
                        return False
                if "$lte" in v and not (doc_val is not None and doc_val <= v["$lte"]):
                    return False
                if "$gte" in v and not (doc_val is not None and doc_val >= v["$gte"]):
                    return False
            else:
                if doc_val != v:
                    return False
        return True

    def find(self, query: Optional[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
        with self._lock:
            return [deepcopy(d) for d in self.docs if self._matches(d, query)]

    def find_one(self, query: Optional[Dict[str, Any]] = None, projection: Any = None) -> Optional[Dict[str, Any]]:
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    return deepcopy(d)
            return None

    def insert_one(self, doc: Dict[str, Any]):
        with self._lock:
            d = deepcopy(doc)
            if "_id" not in d:
                d["_id"] = ObjectId()
            self.docs.append(d)
            return type("InsertRes", (), {"inserted_id": d["_id"]})()

    def update_one(self, query: Dict[str, Any], update: Dict[str, Any], upsert: bool = False):
        with self._lock:
            for d in self.docs:
                if self._matches(d, query):
                    self._apply_update(d, update)
                    return type("UpdateRes", (), {"matched_count": 1, "modified_count": 1})()
            if upsert:
                new_doc: Dict[str, Any] = {}
                for k, v in query.items():
                    if not k.startswith("$") and not isinstance(v, dict):
                        new_doc[k] = deepcopy(v)
                self._apply_update(new_doc, update)
                if "_id" not in new_doc:
                    new_doc["_id"] = ObjectId()
                self.docs.append(new_doc)
                return type("UpdateRes", (), {"matched_count": 0, "modified_count": 1, "upserted_id": new_doc["_id"]})()
            return type("UpdateRes", (), {"matched_count": 0, "modified_count": 0})()

    def update_many(self, query: Dict[str, Any], update: Dict[str, Any]):
        with self._lock:
            matched = 0
            for d in self.docs:
                if self._matches(d, query):
                    self._apply_update(d, update)
                    matched += 1
            return type("UpdateRes", (), {"matched_count": matched, "modified_count": matched})()

    def _apply_update(self, doc: Dict[str, Any], update: Dict[str, Any]) -> None:
        if "$set" in update:
            for k, v in update["$set"].items():
                doc[k] = deepcopy(v)
        if "$inc" in update:
            for k, v in update["$inc"].items():
                doc[k] = doc.get(k, 0) + v

    def count_documents(self, query: Dict[str, Any]) -> int:
        return len(self.find(query))

    def create_index(self, keys, **kwargs):
        return kwargs.get("name", "idx")


class FakeDB:
    def __init__(self):
        self._cols: Dict[str, FakeCollection] = {}

    def __getitem__(self, name: str) -> FakeCollection:
        if name not in self._cols:
            self._cols[name] = FakeCollection(name)
        return self._cols[name]


def _seed_user_and_tier(db: FakeDB, email: str, account_id: str, tier: Optional[MembershipTier] = None) -> dict:
    uid = ObjectId()
    user_doc = {
        "_id": uid,
        "email": email,
        "account_id": account_id,
        "name": email.split("@")[0].title(),
    }
    db["users"].docs.append(user_doc)
    if tier and tier != MembershipTier.FREE:
        now = datetime.now(timezone.utc)
        sub_doc = {
            "_id": ObjectId(),
            "subscription_id": f"sub_{account_id}",
            "user_id": account_id,
            "tier": tier.value if hasattr(tier, "value") else str(tier),
            "status": SubscriptionStatus.ACTIVE.value,
            "current_period_start": now - timedelta(days=1),
            "current_period_end": now + timedelta(days=30),
            "cancel_at_period_end": False,
        }
        db[COLL_SUBSCRIPTIONS].docs.append(sub_doc)
    return user_doc


# ---------------------------------------------------------------------------
# Test Fixture
# ---------------------------------------------------------------------------

@pytest.fixture
def test_env(monkeypatch):
    fake_db = FakeDB()
    monkeypatch.setattr(app_db, "db", fake_db)
    monkeypatch.setattr(workout_mod._db_mod, "db", fake_db)

    app = FastAPI()
    app.include_router(workout_mod.router)

    current_user_holder: Dict[str, Any] = {}

    def _get_current_user_override():
        return current_user_holder.get("user")

    app.dependency_overrides[get_current_user] = _get_current_user_override

    monkeypatch.setattr(workout_mod, "workout_history_collection", fake_db["workout_history"])
    monkeypatch.setattr(workout_mod, "workout_video_stories_collection", fake_db["workout_video_stories"])
    monkeypatch.setattr(app_db, "workout_video_stories_collection", fake_db["workout_video_stories"])

    client = TestClient(app)

    return {
        "db": fake_db,
        "client": client,
        "user_holder": current_user_holder,
    }


# ---------------------------------------------------------------------------
# 1. Backward Compatibility: POST /api/workouts/sessions
# ---------------------------------------------------------------------------

def test_workout_session_backward_compatibility_old_payload(test_env):
    """Old session payload without rep_timeline or video_story_id must return 200/201

    and preserve the 5 cv_form_summary keys.
    """
    db = test_env["db"]
    client = test_env["client"]
    account_id = "acct_" + "1" * 32
    user = _seed_user_and_tier(db, "free_legacy@example.com", account_id, None)
    test_env["user_holder"]["user"] = user

    cv_summary = {
        "score": 88,
        "rep_count": 10,
        "tempo_fast_count": 1,
        "avg_duration": 2.5,
        "dominant_issue": "knee_valgus",
    }
    payload = {
        "planName": "Leg Day Legacy",
        "exerciseLogs": [
            {
                "exerciseId": "ex_squat",
                "exerciseSlug": "barbell-squat",
                "setNumber": 1,
                "repsCompleted": 10,
                "weightKg": 80.0,
                "cvDetected": True,
                "cvFormSummary": cv_summary,
            }
        ],
        "cvFormSummary": cv_summary,
    }

    res = client.post("/api/workouts/sessions", json=payload)
    assert res.status_code == 201, res.text
    data = res.json()
    assert data["message"] == "Workout session logged successfully"
    session_data = data["session"]

    # cvFormSummary preserved
    assert session_data["cvFormSummary"] == cv_summary
    assert len(session_data["exerciseLogs"]) == 1
    log_item = session_data["exerciseLogs"][0]
    assert log_item["cvFormSummary"] == cv_summary
    assert log_item["repTimeline"] is None
    assert log_item["videoStoryId"] is None


def test_workout_session_with_rep_timeline_and_video_story_id(test_env):
    """New session payload with repTimeline and videoStoryId must save and serialize cleanly."""
    db = test_env["db"]
    client = test_env["client"]
    account_id = "acct_" + "2" * 32
    user = _seed_user_and_tier(db, "pro_athlete@example.com", account_id, MembershipTier.PRO)
    test_env["user_holder"]["user"] = user

    timeline = [
        {
            "repIndex": 1,
            "startSec": 0.5,
            "bottomSec": 1.5,
            "endSec": 2.5,
            "durationSec": 2.0,
            "metricAngleDeg": 85.0,
            "isValid": True,
            "issueType": "none",
            "viewAngle": "side",
            "visibilityConfidence": 0.98,
        },
        {
            "repIndex": 2,
            "startSec": 3.0,
            "bottomSec": 4.2,
            "endSec": 5.4,
            "durationSec": 2.4,
            "metricAngleDeg": 72.0,
            "isValid": False,
            "issueType": "knee_valgus",
            "viewAngle": "front",
            "visibilityConfidence": 0.95,
        },
    ]

    # Pre-seed an unlinked story in workout_video_stories
    story_id = "story_test_xyz_123"
    db["workout_video_stories"].docs.append({
        "_id": ObjectId(),
        "story_id": story_id,
        "account_id": account_id,
        "user_id": str(user["_id"]),
        "workout_session_id": None,
    })

    payload = {
        "planName": "Pro Squat Day",
        "exerciseLogs": [
            {
                "exerciseId": "ex_squat",
                "exerciseSlug": "barbell-squat",
                "setNumber": 1,
                "repsCompleted": 2,
                "weightKg": 100.0,
                "cvDetected": True,
                "repTimeline": timeline,
                "videoStoryId": story_id,
            }
        ],
    }

    res = client.post("/api/workouts/sessions", json=payload)
    assert res.status_code == 201, res.text
    data = res.json()
    saved_session = data["session"]
    ex_log = saved_session["exerciseLogs"][0]

    assert ex_log["videoStoryId"] == story_id
    assert len(ex_log["repTimeline"]) == 2
    assert ex_log["repTimeline"][0]["repIndex"] == 1
    assert ex_log["repTimeline"][0]["metricAngleDeg"] == 85.0
    assert ex_log["repTimeline"][1]["issueType"] == "knee_valgus"

    # Confirm story in database was auto-linked to this session
    updated_story = db["workout_video_stories"].find_one({"story_id": story_id})
    assert updated_story is not None
    assert updated_story["workout_session_id"] == data["session_id"]


# ---------------------------------------------------------------------------
# 2. POST /api/workouts/video-stories/presign
# ---------------------------------------------------------------------------

def test_presign_free_tier_forbidden(test_env):
    """Free user has 0 MB storage limit and receives 403 entitlement_required."""
    db = test_env["db"]
    client = test_env["client"]
    account_id = "acct_" + "3" * 32
    user = _seed_user_and_tier(db, "free_user@example.com", account_id, None)
    test_env["user_holder"]["user"] = user

    payload = {
        "exerciseSlug": "barbell-squat",
        "contentType": "video/mp4",
        "sizeBytes": 5 * 1024 * 1024,
    }
    res = client.post("/api/workouts/video-stories/presign", json=payload)
    assert res.status_code == 403, res.text
    data = res.json()["detail"]
    assert data["code"] == "entitlement_required"
    assert data["benefit_id"] == "workout.video_story.cloud_mb"
    assert data["limit_mb"] == 0


def test_presign_file_too_large(test_env):
    """Upload request exceeding MAX_VIDEO_STORY_BYTES (15 MB) returns 413."""
    db = test_env["db"]
    client = test_env["client"]
    account_id = "acct_" + "4" * 32
    user = _seed_user_and_tier(db, "pro_user@example.com", account_id, MembershipTier.PRO)
    test_env["user_holder"]["user"] = user

    payload = {
        "exerciseSlug": "barbell-squat",
        "contentType": "video/mp4",
        "sizeBytes": 16 * 1024 * 1024,  # 16 MB > 15 MB
    }
    res = client.post("/api/workouts/video-stories/presign", json=payload)
    assert res.status_code == 413, res.text


def test_presign_storage_quota_exceeded(test_env):
    """Plus user (500 MB limit) exceeding storage quota returns 429."""
    db = test_env["db"]
    client = test_env["client"]
    account_id = "acct_" + "5" * 32
    user = _seed_user_and_tier(db, "plus_user@example.com", account_id, MembershipTier.PLUS)
    test_env["user_holder"]["user"] = user

    # Pre-occupy 498 MB in DB
    db["workout_video_stories"].docs.append({
        "_id": ObjectId(),
        "account_id": account_id,
        "size_bytes": 498 * 1024 * 1024,
    })

    # Try to request 5 MB (498 + 5 = 503 MB > 500 MB)
    payload = {
        "exerciseSlug": "barbell-squat",
        "contentType": "video/mp4",
        "sizeBytes": 5 * 1024 * 1024,
    }
    res = client.post("/api/workouts/video-stories/presign", json=payload)
    assert res.status_code == 429, res.text
    data = res.json()["detail"]
    assert data["code"] == "storage_quota_exceeded"
    assert data["limit_mb"] == 500


def test_presign_success_pro_tier(test_env):
    """Pro user receives valid presigned URL and storage_key prefixed with account_id."""
    db = test_env["db"]
    client = test_env["client"]
    account_id = "acct_" + "6" * 32
    user = _seed_user_and_tier(db, "pro_user2@example.com", account_id, MembershipTier.PRO)
    test_env["user_holder"]["user"] = user

    mock_presigned = PresignedUploadResult(
        upload_url=f"https://r2.example.com/saman/workouts/{account_id}/story123.mp4?sig=xyz",
        public_url=f"https://media.saman.app/saman/workouts/{account_id}/story123.mp4",
        storage_key=f"saman/workouts/{account_id}/story123.mp4",
        headers={"Content-Type": "video/mp4"},
        expires_in=900,
    )

    with patch("backend.routers.workout.get_media_storage_service") as mock_get_svc:
        mock_svc = MagicMock()
        mock_svc.generate_presigned_upload_url.return_value = mock_presigned
        mock_get_svc.return_value = mock_svc

        payload = {
            "exerciseSlug": "barbell-squat",
            "contentType": "video/mp4",
            "sizeBytes": 8 * 1024 * 1024,
        }
        res = client.post("/api/workouts/video-stories/presign", json=payload)
        assert res.status_code == 200, res.text
        data = res.json()
        assert data["uploadUrl"] == mock_presigned.upload_url
        assert data["storageKey"].startswith(f"saman/workouts/{account_id}/")
        assert data["limitMb"] == 5000
        assert data["usedBytes"] == 0


def test_presign_media_storage_unconfigured_503(test_env):
    """When media storage service raises MediaStorageConfigError, return HTTP 503."""
    db = test_env["db"]
    client = test_env["client"]
    account_id = "acct_" + "7" * 32
    user = _seed_user_and_tier(db, "ultra_user@example.com", account_id, MembershipTier.ULTRA)
    test_env["user_holder"]["user"] = user

    with patch("backend.routers.workout.get_media_storage_service") as mock_get_svc:
        mock_svc = MagicMock()
        mock_svc.generate_presigned_upload_url.side_effect = MediaStorageConfigError("S3 not configured")
        mock_get_svc.return_value = mock_svc

        payload = {
            "exerciseSlug": "barbell-squat",
            "contentType": "video/mp4",
            "sizeBytes": 2 * 1024 * 1024,
        }
        res = client.post("/api/workouts/video-stories/presign", json=payload)
        assert res.status_code == 503, res.text


# ---------------------------------------------------------------------------
# 3. POST /api/workouts/video-stories/complete & Anti-tampering
# ---------------------------------------------------------------------------

def test_complete_anti_tampering_different_user_key(test_env):
    """Attempting to complete upload with another user's storage key returns 403."""
    db = test_env["db"]
    client = test_env["client"]
    account_id_a = "acct_" + "8" * 32
    account_id_b = "acct_" + "9" * 32
    user_a = _seed_user_and_tier(db, "user_a@example.com", account_id_a, MembershipTier.PRO)
    test_env["user_holder"]["user"] = user_a

    # storage_key claims to belong to account_id_b
    payload = {
        "storyId": "story_fake_999",
        "storageKey": f"saman/workouts/{account_id_b}/story_fake_999.mp4",
        "videoUrl": f"https://media.saman.app/saman/workouts/{account_id_b}/story_fake_999.mp4",
        "exerciseSlug": "barbell-squat",
        "durationSec": 12.5,
        "sizeBytes": 5 * 1024 * 1024,
    }
    res = client.post("/api/workouts/video-stories/complete", json=payload)
    assert res.status_code == 403, res.text
    assert "Access denied" in res.json()["detail"]


def test_complete_success_with_retention_policy(test_env):
    """Pro user completes upload: doc persisted, 14-day retention calculated, used_bytes updated."""
    db = test_env["db"]
    client = test_env["client"]
    account_id = "acct_" + "a" * 32
    user = _seed_user_and_tier(db, "pro_retention@example.com", account_id, MembershipTier.PRO)
    test_env["user_holder"]["user"] = user

    story_id = "story_complete_ok_1"
    storage_key = f"saman/workouts/{account_id}/{story_id}.mp4"
    video_url = f"https://media.saman.app/{storage_key}"

    timeline = [
        {
            "repIndex": 1,
            "startSec": 1.0,
            "bottomSec": 2.0,
            "endSec": 3.0,
            "durationSec": 2.0,
            "isValid": True,
        }
    ]

    payload = {
        "storyId": story_id,
        "storageKey": storage_key,
        "videoUrl": video_url,
        "exerciseSlug": "bench-press",
        "durationSec": 15.0,
        "sizeBytes": 4 * 1024 * 1024,
        "repTimeline": timeline,
    }

    res = client.post("/api/workouts/video-stories/complete", json=payload)
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["videoStoryId"] == story_id
    assert data["usedBytes"] == 4 * 1024 * 1024
    assert data["limitMb"] == 5000
    assert data["retentionExpiresAt"] is not None

    # Check database doc
    saved_doc = db["workout_video_stories"].find_one({"story_id": story_id})
    assert saved_doc is not None
    assert saved_doc["account_id"] == account_id
    assert saved_doc["exercise_slug"] == "bench-press"
    assert len(saved_doc["rep_timeline"]) == 1


# ---------------------------------------------------------------------------
# 4. GET /api/workouts/video-stories/{story_id} & Isolation
# ---------------------------------------------------------------------------

def test_get_video_story_detail_and_isolation(test_env):
    """Owner can retrieve video story (200), other user receives 404."""
    db = test_env["db"]
    client = test_env["client"]

    account_owner = "acct_" + "b" * 32
    account_intruder = "acct_" + "c" * 32

    user_owner = _seed_user_and_tier(db, "owner@example.com", account_owner, MembershipTier.PRO)
    user_other = _seed_user_and_tier(db, "intruder@example.com", account_intruder, MembershipTier.PRO)

    story_id = "story_secret_123"
    db["workout_video_stories"].docs.append({
        "_id": ObjectId(),
        "story_id": story_id,
        "video_story_id": story_id,
        "account_id": account_owner,
        "user_id": str(user_owner["_id"]),
        "workout_session_id": "session_abc",
        "exercise_slug": "deadlift",
        "date": "2026-11-26",
        "created_at": "2026-11-26T12:00:00Z",
        "storage_key": f"saman/workouts/{account_owner}/{story_id}.mp4",
        "video_url": f"https://media.saman.app/saman/workouts/{account_owner}/{story_id}.mp4",
        "thumbnail_url": None,
        "duration_sec": 20.5,
        "size_bytes": 10 * 1024 * 1024,
        "resolution": "1080p",
        "retention_expires_at": "2026-12-10T12:00:00Z",
        "cv_form_summary": {"score": 95},
        "rep_timeline": [
            {
                "rep_index": 1,
                "start_sec": 1.0,
                "bottom_sec": 2.5,
                "end_sec": 4.0,
                "duration_sec": 3.0,
                "metric_angle_deg": 45.0,
                "is_valid": True,
                "issue_type": "none",
                "view_angle": "side",
                "visibility_confidence": 1.0,
            }
        ],
    })

    # 1. Owner requests -> 200 OK
    test_env["user_holder"]["user"] = user_owner
    res_owner = client.get(f"/api/workouts/video-stories/{story_id}")
    assert res_owner.status_code == 200, res_owner.text
    detail = res_owner.json()
    assert detail["videoStoryId"] == story_id
    assert detail["exerciseSlug"] == "deadlift"
    assert len(detail["repTimeline"]) == 1
    assert detail["repTimeline"][0]["repIndex"] == 1
    assert detail["cvFormSummary"]["score"] == 95

    # 2. Intruder requests -> 404 Not Found (isolated)
    test_env["user_holder"]["user"] = user_other
    res_intruder = client.get(f"/api/workouts/video-stories/{story_id}")
    assert res_intruder.status_code == 404, res_intruder.text
