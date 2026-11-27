# [File: backend/tests/test_phase5_cv_telemetry.py]
import base64
import gzip
import json
import pytest
from unittest.mock import MagicMock, patch
from bson import ObjectId
from fastapi.testclient import TestClient
from fastapi import FastAPI

import backend.app.database as _db_mod
from backend.routers.workout import (
    router as workout_router,
    _compute_anonymous_subject_hash,
    _is_user_cv_telemetry_opted_in,
)
from backend.auth_utils import get_current_user
from backend.app.database import ensure_workout_cv_telemetry_indexes


@pytest.fixture
def mock_db():
    users_mock = MagicMock()
    telemetry_mock = MagicMock()
    story_mock = MagicMock()

    db_mock = MagicMock()
    db_mock["users"] = users_mock
    db_mock["workout_cv_telemetry"] = telemetry_mock
    db_mock["workout_video_stories"] = story_mock

    with patch.object(_db_mod, "db", db_mock), \
         patch.object(_db_mod, "users_collection", users_mock), \
         patch.object(_db_mod, "workout_cv_telemetry_collection", telemetry_mock), \
         patch.object(_db_mod, "workout_video_stories_collection", story_mock):
        yield {
            "db": db_mock,
            "users": users_mock,
            "telemetry": telemetry_mock,
        }


@pytest.fixture
def test_app():
    app = FastAPI()
    app.include_router(workout_router)
    return app


def _make_gzip_b64(data: dict) -> str:
    raw_json = json.dumps(data).encode("utf-8")
    compressed = gzip.compress(raw_json)
    return base64.b64encode(compressed).decode("utf-8")


def test_helper_opt_in_detection():
    assert _is_user_cv_telemetry_opted_in({}) is False
    assert _is_user_cv_telemetry_opted_in({"preferences": {"cv_telemetry_opt_in": False}}) is False
    assert _is_user_cv_telemetry_opted_in({"preferences": {"cv_telemetry_opt_in": "true"}}) is False
    assert _is_user_cv_telemetry_opted_in({"preferences": {"cv_telemetry_opt_in": True}}) is True
    assert _is_user_cv_telemetry_opted_in({"profile": {"preferences": {"cv_telemetry_opt_in": True}}}) is True


def test_anonymous_subject_hash():
    h1 = _compute_anonymous_subject_hash("user_123")
    h2 = _compute_anonymous_subject_hash("user_123")
    h3 = _compute_anonymous_subject_hash("user_456")
    assert len(h1) == 16
    assert h1 == h2
    assert h1 != h3


def test_telemetry_indexes(mock_db):
    col = mock_db["telemetry"]
    col.create_index.side_effect = ["idx1", "idx2", "idx3"]
    indexes = ensure_workout_cv_telemetry_indexes(col)
    assert len(indexes) == 3
    assert col.create_index.call_count == 3


def test_submit_telemetry_opt_in_required_403(test_app, mock_db):
    user_id = ObjectId()
    current_user_no_opt_in = {
        "_id": user_id,
        "email": "test@example.com",
        "account_id": "acc_1",
        "preferences": {"cv_telemetry_opt_in": False},
    }
    mock_db["users"].find_one.return_value = current_user_no_opt_in

    test_app.dependency_overrides[get_current_user] = lambda: current_user_no_opt_in

    client = TestClient(test_app)
    b64_payload = _make_gzip_b64({"frames": []})

    resp = client.post(
        "/api/workouts/cv/telemetry",
        json={
            "exerciseSlug": "squat",
            "viewAngle": "side_left",
            "fps": 30.0,
            "frameCount": 120,
            "cvReps": 5,
            "finalLoggedReps": 5,
            "compressedPayloadB64": b64_payload,
        },
    )

    assert resp.status_code == 403
    data = resp.json()
    assert data["detail"]["code"] == "telemetry_opt_in_required"


def test_submit_telemetry_success_and_anonymity(test_app, mock_db):
    user_id = ObjectId()
    user_opted_in = {
        "_id": user_id,
        "email": "athlete@example.com",
        "full_name": "Nguyen Van A",
        "account_id": "acc_athlete",
        "preferences": {"cv_telemetry_opt_in": True},
    }
    mock_db["users"].find_one.return_value = user_opted_in
    mock_db["telemetry"].insert_one.return_value = MagicMock(acknowledged=True)

    test_app.dependency_overrides[get_current_user] = lambda: user_opted_in

    client = TestClient(test_app)
    dummy_keypoints = {"t_ms": [0, 33, 66], "landmarks": [[[0.5, 0.5, 0.0, 0.9]] * 33] * 3}
    b64_payload = _make_gzip_b64(dummy_keypoints)

    resp = client.post(
        "/api/workouts/cv/telemetry",
        json={
            "exerciseSlug": "pushup",
            "viewAngle": "side_right",
            "fps": 30.0,
            "frameCount": 90,
            "cvReps": 10,
            "finalLoggedReps": 8,  # Rep adjusted by user!
            "compressedPayloadB64": b64_payload,
        },
    )

    assert resp.status_code == 201
    data = resp.json()
    assert data["exerciseSlug"] == "pushup"
    assert data["userAdjustedReps"] is True
    assert data["priorityBucket"] == "high_rep_correction"
    assert len(data["subjectHash"]) == 16
    assert data["telemetryId"].startswith("tel_")

    # Assert document in database has NO PII
    insert_call_args = mock_db["telemetry"].insert_one.call_args[0][0]
    assert "email" not in insert_call_args
    assert "full_name" not in insert_call_args
    assert "user_email" not in insert_call_args
    assert "video_url" not in insert_call_args
    assert insert_call_args["subject_hash"] == data["subjectHash"]
    assert insert_call_args["user_adjusted_reps"] is True
    assert insert_call_args["priority_bucket"] == "high_rep_correction"


def test_submit_telemetry_payload_too_large_413(test_app, mock_db):
    user_opted_in = {
        "_id": ObjectId(),
        "account_id": "acc_test",
        "preferences": {"cv_telemetry_opt_in": True},
    }
    mock_db["users"].find_one.return_value = user_opted_in
    test_app.dependency_overrides[get_current_user] = lambda: user_opted_in

    client = TestClient(test_app)
    # Exceed 256 KB
    huge_data = b"x" * (257 * 1024)
    b64_huge = base64.b64encode(huge_data).decode("utf-8")

    resp = client.post(
        "/api/workouts/cv/telemetry",
        json={
            "exerciseSlug": "squat",
            "frameCount": 100,
            "cvReps": 5,
            "compressedPayloadB64": b64_huge,
        },
    )

    assert resp.status_code == 413


def test_submit_telemetry_forbidden_pii_keys_in_payload_400(test_app, mock_db):
    user_opted_in = {
        "_id": ObjectId(),
        "account_id": "acc_test",
        "preferences": {"cv_telemetry_opt_in": True},
    }
    mock_db["users"].find_one.return_value = user_opted_in
    test_app.dependency_overrides[get_current_user] = lambda: user_opted_in

    client = TestClient(test_app)
    # Payload contains sensitive key "email"
    leaked_data = {"email": "sneaky@example.com", "landmarks": []}
    b64_payload = _make_gzip_b64(leaked_data)

    resp = client.post(
        "/api/workouts/cv/telemetry",
        json={
            "exerciseSlug": "squat",
            "frameCount": 100,
            "cvReps": 5,
            "compressedPayloadB64": b64_payload,
        },
    )

    assert resp.status_code == 400
    assert "sensitive/forbidden key" in resp.json()["detail"]


def test_get_telemetry_stats(test_app, mock_db):
    user_id = ObjectId()
    user_opted_in = {
        "_id": user_id,
        "account_id": "acc_stats_user",
        "profile": {"preferences": {"cv_telemetry_opt_in": True}},
    }
    mock_db["users"].find_one.return_value = user_opted_in
    test_app.dependency_overrides[get_current_user] = lambda: user_opted_in

    def mock_count(query):
        if query.get("user_adjusted_reps") is True:
            return 3
        return 10

    mock_db["telemetry"].count_documents.side_effect = mock_count

    client = TestClient(test_app)
    resp = client.get("/api/workouts/cv/telemetry/stats")

    assert resp.status_code == 200
    data = resp.json()
    assert data["cvTelemetryOptIn"] is True
    assert data["totalClipsContributed"] == 10
    assert data["repCorrectionClips"] == 3
    assert len(data["subjectHash"]) == 16
