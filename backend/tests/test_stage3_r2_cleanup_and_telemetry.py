"""Unit and API tests for Stage 3 R2 expired video cleanup and client error telemetry."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import backend.app.database as _db_mod
from backend.app.services.r2_retention_service import (
    CLIENT_ERROR_TTL_INDEX_NAME,
    CLIENT_ERROR_TTL_SECONDS,
    _parse_utc_datetime,
    cleanup_expired_r2_videos,
    ensure_client_error_ttl_index,
    scrub_client_error_text,
)
from backend.routers.maintenance import maintenance_router
from backend.scripts import cleanup_expired_r2_videos as cli_script


class _FakeCursor:
    def __init__(self, docs: list[dict[str, Any]]) -> None:
        self._docs = list(docs)

    def limit(self, n: int) -> "_FakeCursor":
        return _FakeCursor(self._docs[:n])

    def __iter__(self):
        return iter(self._docs)


class _InMemoryStoryCollection:
    """Minimal in-memory Mongo-like collection for testing cleanup logic & idempotency."""

    def __init__(self, docs: list[dict[str, Any]]) -> None:
        self.docs = [dict(d) for d in docs]
        self.last_query: dict[str, Any] | None = None
        self.update_calls: list[tuple[dict[str, Any], dict[str, Any]]] = []

    def find(self, query: dict[str, Any]) -> _FakeCursor:
        self.last_query = query
        # Return all docs so Python double-check & idempotency are exercised end-to-end
        # while still mimicking Mongo's deleted_at filtering.
        matched = [d for d in self.docs if d.get("deleted_at") is None]
        return _FakeCursor(matched)

    def update_one(self, flt: dict[str, Any], update: dict[str, Any]) -> MagicMock:
        self.update_calls.append((flt, update))
        for doc in self.docs:
            if all(doc.get(k) == v for k, v in flt.items()):
                for k, v in update.get("$set", {}).items():
                    doc[k] = v
                break
        res = MagicMock()
        res.modified_count = 1
        return res


@pytest.fixture
def test_app() -> FastAPI:
    app = FastAPI()
    app.include_router(maintenance_router)
    return app


# ---------------------------------------------------------------------------
# _parse_utc_datetime
# ---------------------------------------------------------------------------


def test_parse_utc_datetime_handles_iso_strings_datetimes_and_invalid():
    dt_z = _parse_utc_datetime("2026-11-26T10:00:00Z")
    assert dt_z == datetime(2026, 11, 26, 10, 0, 0, tzinfo=timezone.utc)

    dt_offset = _parse_utc_datetime("2026-11-26T17:00:00+07:00")
    assert dt_offset == datetime(2026, 11, 26, 10, 0, 0, tzinfo=timezone.utc)

    dt_naive = _parse_utc_datetime(datetime(2026, 11, 26, 10, 0, 0))
    assert dt_naive == datetime(2026, 11, 26, 10, 0, 0, tzinfo=timezone.utc)

    dt_aware = _parse_utc_datetime(
        datetime(2026, 11, 26, 17, 0, 0, tzinfo=timezone(timedelta(hours=7)))
    )
    assert dt_aware == datetime(2026, 11, 26, 10, 0, 0, tzinfo=timezone.utc)

    assert _parse_utc_datetime(None) is None
    assert _parse_utc_datetime("") is None
    assert _parse_utc_datetime("not-a-timestamp") is None
    assert _parse_utc_datetime(12345) is None
    assert _parse_utc_datetime(True) is None


# ---------------------------------------------------------------------------
# cleanup_expired_r2_videos
# ---------------------------------------------------------------------------


def _sample_stories(now: datetime) -> list[dict[str, Any]]:
    return [
        {
            "_id": "id_expired_iso",
            "story_id": "story_iso",
            "storage_key": "saman/workouts/acc1/story_iso.mp4",
            "size_bytes": 1_500_000,
            "retention_expires_at": (now - timedelta(hours=2)).isoformat().replace("+00:00", "Z"),
        },
        {
            "_id": "id_expired_dt",
            "story_id": "story_dt",
            "storage_key": "saman/workouts/acc1/story_dt.mp4",
            "size_bytes": 2_500_000,
            "retention_expires_at": now - timedelta(days=1),
        },
        {
            "_id": "id_expired_naive_dt",
            "story_id": "story_naive",
            "storage_key": "saman/workouts/acc2/story_naive.mp4",
            "size_bytes": 500_000,
            "retention_expires_at": (now - timedelta(minutes=5)).replace(tzinfo=None),
        },
        {
            "_id": "id_future_iso",
            "story_id": "story_future",
            "storage_key": "saman/workouts/acc1/story_future.mp4",
            "size_bytes": 3_000_000,
            "retention_expires_at": (now + timedelta(days=7)).isoformat().replace("+00:00", "Z"),
        },
        {
            "_id": "id_no_expiry",
            "story_id": "story_forever",
            "storage_key": "saman/workouts/acc1/story_forever.mp4",
            "size_bytes": 4_000_000,
            "retention_expires_at": None,
        },
        {
            "_id": "id_already_deleted",
            "story_id": "story_deleted",
            "storage_key": "saman/workouts/acc1/story_deleted.mp4",
            "size_bytes": 900_000,
            "retention_expires_at": (now - timedelta(days=5)).isoformat().replace("+00:00", "Z"),
            "deleted_at": (now - timedelta(days=1)).isoformat().replace("+00:00", "Z"),
            "storage_deleted": True,
        },
    ]


def test_cleanup_expired_r2_videos_dry_run_does_not_delete_or_mutate():
    now = datetime(2026, 11, 27, 12, 0, 0, tzinfo=timezone.utc)
    col = _InMemoryStoryCollection(_sample_stories(now))
    storage = MagicMock()

    result = cleanup_expired_r2_videos(
        col,
        media_storage=storage,
        now_utc=now,
        dry_run=True,
        batch_limit=200,
    )

    assert result["dry_run"] is True
    assert result["scanned"] == 5  # 6 total minus 1 already deleted
    assert result["eligible"] == 3
    assert result["deleted"] == 0
    assert result["failed"] == 0
    assert result["freed_bytes"] == 4_500_000
    assert result["executed_at"].endswith("Z")

    storage.delete_object.assert_not_called()
    assert len(col.update_calls) == 0


def test_cleanup_expired_r2_videos_live_and_idempotent():
    now = datetime(2026, 11, 27, 12, 0, 0, tzinfo=timezone.utc)
    col = _InMemoryStoryCollection(_sample_stories(now))
    storage = MagicMock()
    storage.delete_object.return_value = True

    first = cleanup_expired_r2_videos(
        col,
        media_storage=storage,
        now_utc=now,
        dry_run=False,
    )

    assert first["dry_run"] is False
    assert first["eligible"] == 3
    assert first["deleted"] == 3
    assert first["failed"] == 0
    assert first["freed_bytes"] == 4_500_000
    assert storage.delete_object.call_count == 3

    deleted_keys = {call.args[0] for call in storage.delete_object.call_args_list}
    assert deleted_keys == {
        "saman/workouts/acc1/story_iso.mp4",
        "saman/workouts/acc1/story_dt.mp4",
        "saman/workouts/acc2/story_naive.mp4",
    }

    # Verify DB flags: expired marked deleted, future & None untouched
    by_id = {d["_id"]: d for d in col.docs}
    for exp_id in ("id_expired_iso", "id_expired_dt", "id_expired_naive_dt"):
        assert by_id[exp_id]["storage_deleted"] is True
        assert by_id[exp_id]["deleted_at"] == first["executed_at"]
    assert "deleted_at" not in by_id["id_future_iso"]
    assert "deleted_at" not in by_id["id_no_expiry"]

    # Second run MUST be idempotent: 0 eligible, 0 deleted, no extra storage calls
    second = cleanup_expired_r2_videos(
        col,
        media_storage=storage,
        now_utc=now,
        dry_run=False,
    )
    assert second["eligible"] == 0
    assert second["deleted"] == 0
    assert second["failed"] == 0
    assert second["freed_bytes"] == 0
    assert storage.delete_object.call_count == 3


def test_cleanup_expired_r2_videos_retries_on_storage_failure():
    now = datetime(2026, 11, 27, 12, 0, 0, tzinfo=timezone.utc)
    col = _InMemoryStoryCollection(
        [
            {
                "_id": "id_false",
                "story_id": "story_false",
                "storage_key": "saman/workouts/acc1/false.mp4",
                "size_bytes": 1000,
                "retention_expires_at": (now - timedelta(hours=1)).isoformat().replace("+00:00", "Z"),
            },
            {
                "_id": "id_boom",
                "story_id": "story_boom",
                "storage_key": "saman/workouts/acc1/boom.mp4",
                "size_bytes": 2000,
                "retention_expires_at": (now - timedelta(hours=1)).isoformat().replace("+00:00", "Z"),
            },
        ]
    )

    storage = MagicMock()
    storage.delete_object.side_effect = [False, RuntimeError("R2 timeout")]

    result = cleanup_expired_r2_videos(col, media_storage=storage, now_utc=now, dry_run=False)
    assert result["eligible"] == 2
    assert result["deleted"] == 0
    assert result["failed"] == 2
    assert result["freed_bytes"] == 0

    # Neither record should have deleted_at so the next cron run retries
    for doc in col.docs:
        assert doc.get("deleted_at") is None
        assert doc.get("storage_deleted") is None


# ---------------------------------------------------------------------------
# scrub_client_error_text & TTL index
# ---------------------------------------------------------------------------


def test_scrub_client_error_text_redacts_pii_and_secrets_and_truncates():
    raw = (
        "Failed request with Authorization: Bearer super_secret_token_999 "
        "and jwt eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTYifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c "
        "for user alice.tester+1@example.com "
        "calling https://generativelanguage.googleapis.com/v1?key=AIzaSyD1234567890_abcdef&token=tok123&password=pw999&secret=sec777"
    )
    scrubbed = scrub_client_error_text(raw, max_len=2000)

    assert "eyJhbGci" not in scrubbed
    assert "super_secret_token_999" not in scrubbed
    assert "alice.tester+1@example.com" not in scrubbed
    assert "AIzaSyD1234567890_abcdef" not in scrubbed
    assert "tok123" not in scrubbed
    assert "pw999" not in scrubbed
    assert "sec777" not in scrubbed

    assert "[REDACTED_JWT]" in scrubbed
    assert "Bearer [REDACTED]" in scrubbed
    assert "[REDACTED_EMAIL]" in scrubbed
    assert "key=[REDACTED]" in scrubbed
    assert "token=[REDACTED]" in scrubbed
    assert "password=[REDACTED]" in scrubbed
    assert "secret=[REDACTED]" in scrubbed

    long_stack = "Frame\n" * 1000
    assert len(scrub_client_error_text(long_stack, max_len=2000)) == 2000
    assert scrub_client_error_text(None) == ""


def test_ensure_client_error_ttl_index():
    col = MagicMock()
    col.create_index.return_value = CLIENT_ERROR_TTL_INDEX_NAME

    idx = ensure_client_error_ttl_index(col)
    assert idx == CLIENT_ERROR_TTL_INDEX_NAME
    col.create_index.assert_called_once_with(
        [("created_at", 1)],
        expireAfterSeconds=CLIENT_ERROR_TTL_SECONDS,
        name=CLIENT_ERROR_TTL_INDEX_NAME,
    )


# ---------------------------------------------------------------------------
# POST /api/internal/maintenance/cleanup-expired-videos
# ---------------------------------------------------------------------------


def test_cleanup_endpoint_fail_closed_when_secret_missing_or_invalid(test_app, monkeypatch):
    client = TestClient(test_app)

    # 1. Env var unset -> 403 even if header supplied
    monkeypatch.delenv("MAINTENANCE_CRON_SECRET", raising=False)
    resp_unset = client.post(
        "/api/internal/maintenance/cleanup-expired-videos",
        headers={"X-Maintenance-Secret": "anything"},
    )
    assert resp_unset.status_code == 403
    assert resp_unset.json()["detail"]["code"] == "forbidden"

    # 2. Env var empty/whitespace -> 403
    monkeypatch.setenv("MAINTENANCE_CRON_SECRET", "   ")
    resp_empty = client.post(
        "/api/internal/maintenance/cleanup-expired-videos",
        headers={"X-Maintenance-Secret": "   "},
    )
    assert resp_empty.status_code == 403

    # 3. Env var configured, header missing or wrong -> 403
    monkeypatch.setenv("MAINTENANCE_CRON_SECRET", "prod-cron-secret-xyz")
    resp_missing = client.post("/api/internal/maintenance/cleanup-expired-videos")
    assert resp_missing.status_code == 403

    resp_wrong = client.post(
        "/api/internal/maintenance/cleanup-expired-videos",
        headers={"X-Maintenance-Secret": "wrong-secret"},
    )
    assert resp_wrong.status_code == 403


def test_cleanup_endpoint_authorized_returns_summary(test_app, monkeypatch):
    monkeypatch.setenv("MAINTENANCE_CRON_SECRET", "prod-cron-secret-xyz")
    now = datetime.now(timezone.utc)
    story_col = _InMemoryStoryCollection(_sample_stories(now))

    with patch.object(_db_mod, "workout_video_stories_collection", story_col):
        client = TestClient(test_app)
        resp = client.post(
            "/api/internal/maintenance/cleanup-expired-videos?dry_run=true&limit=100",
            headers={"X-Maintenance-Secret": "prod-cron-secret-xyz"},
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["dry_run"] is True
    assert body["eligible"] == 3
    assert body["deleted"] == 0
    assert body["freed_bytes"] == 4_500_000


# ---------------------------------------------------------------------------
# POST /api/telemetry/client-error
# ---------------------------------------------------------------------------


def test_client_error_telemetry_accepts_without_jwt_and_scrubs_payload(test_app):
    inserted_docs: list[dict[str, Any]] = []
    err_col = MagicMock()
    err_col.insert_one.side_effect = lambda doc: inserted_docs.append(doc)

    db_mock = {"client_error_logs": err_col}
    with patch.object(_db_mod, "db", db_mock):
        client = TestClient(test_app)
        resp = client.post(
            "/api/telemetry/client-error",
            json={
                "error_type": "DioException for user@example.com",
                "message": "401 Bearer secret_tok_abc key=AIzaSyTestKey12345",
                "stack_preview": ("x" * 2500),
                "app_version": "1.0.0+12",
                "platform": "android",
                "screen": "/login?token=abc123",
                "is_fatal": True,
            },
        )

    assert resp.status_code == 201
    data = resp.json()
    assert data["accepted"] is True
    assert isinstance(data["log_id"], str) and len(data["log_id"]) > 0

    assert len(inserted_docs) == 1
    stored = inserted_docs[0]
    assert "user@example.com" not in stored["error_type"]
    assert "secret_tok_abc" not in stored["message"]
    assert "AIzaSyTestKey12345" not in stored["message"]
    assert "abc123" not in stored["screen"]
    assert len(stored["stack_preview"]) == 2000
    assert stored["is_fatal"] is True
    assert isinstance(stored["created_at"], datetime)
    assert stored["created_at"].tzinfo == timezone.utc


def test_client_error_telemetry_returns_202_when_db_unavailable_or_fails(test_app):
    # Case 1: DB is None
    with patch.object(_db_mod, "db", None), patch.object(_db_mod, "get_db", return_value=None):
        client = TestClient(test_app)
        resp = client.post(
            "/api/telemetry/client-error",
            json={
                "error_type": "StateError",
                "message": "Widget disposed",
            },
        )
    assert resp.status_code == 202
    assert resp.json()["accepted"] is True

    # Case 2: insert_one raises
    err_col = MagicMock()
    err_col.insert_one.side_effect = RuntimeError("Mongo write timeout")
    with patch.object(_db_mod, "db", {"client_error_logs": err_col}):
        client = TestClient(test_app)
        resp2 = client.post(
            "/api/telemetry/client-error",
            json={
                "error_type": "StateError",
                "message": "Widget disposed",
            },
        )
    assert resp2.status_code == 202
    assert resp2.json()["accepted"] is True


# ---------------------------------------------------------------------------
# CLI script & config files
# ---------------------------------------------------------------------------


def test_cli_cleanup_script_dry_run_prints_json(capsys):
    now = datetime.now(timezone.utc)
    story_col = _InMemoryStoryCollection(_sample_stories(now))

    with patch.object(_db_mod, "workout_video_stories_collection", story_col):
        exit_code = cli_script.main(["--dry-run", "--limit", "50"])

    assert exit_code == 0
    captured = capsys.readouterr()
    parsed = json.loads(captured.out.strip())
    assert parsed["dry_run"] is True
    assert parsed["eligible"] == 3
    assert parsed["deleted"] == 0


def test_env_example_and_render_yaml_include_maintenance_secret_without_hardcoded_value():
    repo_root = Path(__file__).resolve().parents[2]
    env_example = (repo_root / "backend" / ".env.example").read_text(encoding="utf-8")
    render_yaml = (repo_root / "backend" / "render.yaml").read_text(encoding="utf-8")

    assert "\nMAINTENANCE_CRON_SECRET=\n" in f"{env_example}\n"
    assert "- key: MAINTENANCE_CRON_SECRET" in render_yaml
    idx = render_yaml.index("- key: MAINTENANCE_CRON_SECRET")
    snippet = render_yaml[idx : idx + 80]
    assert "sync: false" in snippet
