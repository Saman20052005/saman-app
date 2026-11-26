"""Offline end-to-end unit tests for cloud/local MediaStorageService integration
in backend/routers/community.py and backend/routers/community_dm.py.
"""

from __future__ import annotations

import io
import sys
import types
from pathlib import Path
from typing import Any, Dict
from unittest.mock import MagicMock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from PIL import Image

_REPO_ROOT = str(Path(__file__).resolve().parents[2])
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

from backend.app.services.media_storage_service import (
    MediaStorageConfigError,
    MediaStorageUploadError,
    reset_media_storage_service,
)
from backend.routers import community, community_dm


# ---------------------------------------------------------------------------
# Helpers & Fixtures
# ---------------------------------------------------------------------------


def _make_png_bytes(size: tuple[int, int] = (32, 32), color: str = "dodgerblue") -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", size, color=color).save(buf, format="PNG")
    return buf.getvalue()


def _make_m4a_bytes() -> bytes:
    return b"\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00M4A isom" + b"A" * 64


def _make_mp4_bytes() -> bytes:
    return b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom" + bytes(range(64))


def _fake_user() -> Dict[str, Any]:
    return {
        "_id": "user_cloud_test_001",
        "email": "cloud_test@saman.app",
        "name": "Cloud Tester",
    }


@pytest.fixture(autouse=True)
def _reset_storage_singleton():
    reset_media_storage_service()
    yield
    reset_media_storage_service()


@pytest.fixture()
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    comm_dir = tmp_path / "community"
    dm_dir = tmp_path / "community_dm"
    comm_dir.mkdir(parents=True, exist_ok=True)
    dm_dir.mkdir(parents=True, exist_ok=True)

    monkeypatch.setattr(community, "COMMUNITY_STATIC_DIR", str(comm_dir))
    monkeypatch.setattr(community_dm, "COMMUNITY_DM_STATIC_DIR", str(dm_dir))

    app = FastAPI()
    app.include_router(community.router)
    app.include_router(community_dm.router)
    app.dependency_overrides[community.get_required_current_user] = _fake_user
    app.dependency_overrides[community_dm.get_required_current_user] = _fake_user

    with TestClient(app) as test_client:
        yield {
            "client": test_client,
            "comm_dir": comm_dir,
            "dm_dir": dm_dir,
        }


def _configure_mock_s3(monkeypatch: pytest.MonkeyPatch) -> MagicMock:
    fake_s3_client = MagicMock()
    fake_boto3 = types.ModuleType("boto3")
    fake_boto3.client = MagicMock(return_value=fake_s3_client)
    monkeypatch.setitem(sys.modules, "boto3", fake_boto3)

    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("MEDIA_STORAGE_PROVIDER", "s3")
    monkeypatch.setenv("S3_ENDPOINT_URL", "https://acct123.r2.cloudflarestorage.com")
    monkeypatch.setenv("S3_REGION", "auto")
    monkeypatch.setenv("S3_BUCKET", "saman-media")
    monkeypatch.setenv("S3_ACCESS_KEY_ID", "test-access-key")
    monkeypatch.setenv("S3_SECRET_ACCESS_KEY", "test-secret-key")
    monkeypatch.setenv("S3_PUBLIC_BASE_URL", "https://cdn.saman.app")
    reset_media_storage_service()
    return fake_s3_client


# ---------------------------------------------------------------------------
# 1. S3 / R2 Cloud Upload Tests
# ---------------------------------------------------------------------------


def test_community_media_upload_s3_mock(client, monkeypatch: pytest.MonkeyPatch) -> None:
    fake_s3 = _configure_mock_s3(monkeypatch)
    png_bytes = _make_png_bytes()

    resp = client["client"].post(
        "/api/community/media/upload",
        files={"file": ("post_photo.png", png_bytes, "image/png")},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()

    assert set(body.keys()) == {"media_url", "content_type", "file_name"}
    assert body["content_type"] == "image/png"
    assert body["file_name"] == "post_photo.png"

    media_url = body["media_url"]
    assert media_url.startswith("https://cdn.saman.app/saman/community/")
    assert media_url.endswith(".png")

    # Verify S3 put_object call used expected bucket and prefix
    fake_s3.put_object.assert_called_once()
    put_kwargs = fake_s3.put_object.call_args.kwargs
    assert put_kwargs["Bucket"] == "saman-media"
    assert put_kwargs["Key"].startswith("saman/community/")
    assert put_kwargs["Key"].endswith(".png")
    assert put_kwargs["Body"] == png_bytes
    assert put_kwargs["ContentType"] == "image/png"

    # Returned URL must pass community._validate_media_url
    assert community._validate_media_url(media_url) == media_url
    # Must NOT write to local disk in S3 mode
    assert list(client["comm_dir"].iterdir()) == []


def test_community_dm_media_upload_s3_mock_image_audio_video(
    client, monkeypatch: pytest.MonkeyPatch
) -> None:
    fake_s3 = _configure_mock_s3(monkeypatch)

    cases = [
        ("dm_pic.png", _make_png_bytes(), "image/png", "image", ".png"),
        ("dm_voice.m4a", _make_m4a_bytes(), "audio/mp4", "audio", ".m4a"),
        ("dm_clip.mp4", _make_mp4_bytes(), "video/mp4", "video", ".mp4"),
    ]

    for fname, payload, expected_ct, expected_kind, expected_ext in cases:
        fake_s3.put_object.reset_mock()
        resp = client["client"].post(
            "/api/community/dm/media/upload",
            files={"file": (fname, payload, expected_ct)},
        )
        assert resp.status_code == 200, f"{fname}: {resp.text}"
        body = resp.json()

        assert set(body.keys()) == {
            "media_url",
            "media_kind",
            "content_type",
            "file_name",
            "size_bytes",
        }
        assert body["media_kind"] == expected_kind
        assert body["content_type"] == expected_ct
        assert body["file_name"] == fname
        assert body["size_bytes"] == len(payload)

        media_url = body["media_url"]
        assert media_url.startswith("https://cdn.saman.app/saman/community_dm/")
        assert media_url.endswith(expected_ext)

        fake_s3.put_object.assert_called_once()
        put_kwargs = fake_s3.put_object.call_args.kwargs
        assert put_kwargs["Bucket"] == "saman-media"
        assert put_kwargs["Key"].startswith("saman/community_dm/")
        assert put_kwargs["Key"].endswith(expected_ext)
        assert put_kwargs["Body"] == payload
        assert put_kwargs["ContentType"] == expected_ct

        # Returned URL must pass community_dm._validate_media_url
        assert community_dm._validate_media_url(media_url) == media_url

    # Must NOT write to local disk in S3 mode
    assert list(client["dm_dir"].iterdir()) == []


# ---------------------------------------------------------------------------
# 2. Local Dev Mode Fallback Tests
# ---------------------------------------------------------------------------


def test_local_dev_mode_writes_files_and_returns_static_urls(
    client, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.setenv("MEDIA_STORAGE_PROVIDER", "local")
    monkeypatch.setenv("ALLOW_LOCAL_MEDIA_STORAGE", "true")
    reset_media_storage_service()

    png_bytes = _make_png_bytes()
    mp4_bytes = _make_mp4_bytes()

    # Community photo upload
    resp_comm = client["client"].post(
        "/api/community/media/upload",
        files={"file": ("local_pic.png", png_bytes, "image/png")},
    )
    assert resp_comm.status_code == 200, resp_comm.text
    comm_url = resp_comm.json()["media_url"]
    assert comm_url.startswith("/static/community/")
    assert comm_url.endswith(".png")
    comm_filename = comm_url.rsplit("/", 1)[-1]
    assert (client["comm_dir"] / comm_filename).read_bytes() == png_bytes

    # Local static GET works in dev mode
    get_comm = client["client"].get(comm_url)
    assert get_comm.status_code == 200
    assert get_comm.content == png_bytes

    # Community DM video upload
    resp_dm = client["client"].post(
        "/api/community/dm/media/upload",
        files={"file": ("local_clip.mp4", mp4_bytes, "video/mp4")},
    )
    assert resp_dm.status_code == 200, resp_dm.text
    dm_url = resp_dm.json()["media_url"]
    assert dm_url.startswith("/static/community_dm/")
    assert dm_url.endswith(".mp4")
    dm_filename = dm_url.rsplit("/", 1)[-1]
    assert (client["dm_dir"] / dm_filename).read_bytes() == mp4_bytes

    # Local static GET works in dev mode
    get_dm = client["client"].get(dm_url)
    assert get_dm.status_code == 200
    assert get_dm.content == mp4_bytes


# ---------------------------------------------------------------------------
# 3. Fail-Closed Error Mapping (503 Config Error & 502 Upload Error)
# ---------------------------------------------------------------------------


def test_fail_closed_config_error_returns_503_on_both_endpoints(
    client, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("MEDIA_STORAGE_PROVIDER", "local")
    monkeypatch.setenv("ALLOW_LOCAL_MEDIA_STORAGE", "false")
    reset_media_storage_service()

    png_bytes = _make_png_bytes()

    resp_comm = client["client"].post(
        "/api/community/media/upload",
        files={"file": ("pic.png", png_bytes, "image/png")},
    )
    assert resp_comm.status_code == 503
    assert resp_comm.json()["detail"] == "Media storage is not configured"

    resp_dm = client["client"].post(
        "/api/community/dm/media/upload",
        files={"file": ("pic.png", png_bytes, "image/png")},
    )
    assert resp_dm.status_code == 503
    assert resp_dm.json()["detail"] == "Media storage is not configured"


def test_fail_closed_config_error_from_service_method_returns_503(
    client, monkeypatch: pytest.MonkeyPatch
) -> None:
    broken_service = MagicMock()
    broken_service.upload_bytes.side_effect = MediaStorageConfigError("missing credentials")
    monkeypatch.setattr(community, "get_media_storage_service", lambda: broken_service)
    monkeypatch.setattr(community_dm, "get_media_storage_service", lambda: broken_service)

    png_bytes = _make_png_bytes()

    resp_comm = client["client"].post(
        "/api/community/media/upload",
        files={"file": ("pic.png", png_bytes, "image/png")},
    )
    assert resp_comm.status_code == 503
    assert "missing credentials" not in resp_comm.text

    resp_dm = client["client"].post(
        "/api/community/dm/media/upload",
        files={"file": ("pic.png", png_bytes, "image/png")},
    )
    assert resp_dm.status_code == 503
    assert "missing credentials" not in resp_dm.text


def test_fail_closed_upload_error_returns_502_on_both_endpoints(
    client, monkeypatch: pytest.MonkeyPatch
) -> None:
    failing_service = MagicMock()
    failing_service.upload_bytes.side_effect = MediaStorageUploadError("upstream R2 timeout")
    monkeypatch.setattr(community, "get_media_storage_service", lambda: failing_service)
    monkeypatch.setattr(community_dm, "get_media_storage_service", lambda: failing_service)

    png_bytes = _make_png_bytes()

    resp_comm = client["client"].post(
        "/api/community/media/upload",
        files={"file": ("pic.png", png_bytes, "image/png")},
    )
    assert resp_comm.status_code == 502
    assert resp_comm.json()["detail"] == "Failed to upload media"
    assert "upstream R2 timeout" not in resp_comm.text

    resp_dm = client["client"].post(
        "/api/community/dm/media/upload",
        files={"file": ("pic.png", png_bytes, "image/png")},
    )
    assert resp_dm.status_code == 502
    assert resp_dm.json()["detail"] == "Failed to upload media"
    assert "upstream R2 timeout" not in resp_dm.text


# ---------------------------------------------------------------------------
# 4. Production Static GET Guard (404 when local storage disabled)
# ---------------------------------------------------------------------------


def test_static_get_routes_return_404_in_production_when_local_disabled(
    client, monkeypatch: pytest.MonkeyPatch
) -> None:
    png_bytes = _make_png_bytes()
    (client["comm_dir"] / "legacy_post.png").write_bytes(png_bytes)
    (client["dm_dir"] / "legacy_dm.png").write_bytes(png_bytes)

    # Confirm files are served in development
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.setenv("ALLOW_LOCAL_MEDIA_STORAGE", "true")
    assert client["client"].get("/static/community/legacy_post.png").status_code == 200
    assert client["client"].get("/static/community_dm/legacy_dm.png").status_code == 200

    # In production with ALLOW_LOCAL_MEDIA_STORAGE=false -> clean 404
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("ALLOW_LOCAL_MEDIA_STORAGE", "false")

    res_comm = client["client"].get("/static/community/legacy_post.png")
    assert res_comm.status_code == 404
    assert res_comm.json()["detail"] == "Not found"

    res_dm = client["client"].get("/static/community_dm/legacy_dm.png")
    assert res_dm.status_code == 404
    assert res_dm.json()["detail"] == "Not found"
