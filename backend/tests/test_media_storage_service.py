"""Offline unit tests for backend.app.services.media_storage_service."""

from __future__ import annotations

import builtins
import sys
import types
from pathlib import Path
from unittest.mock import MagicMock

import pytest

_REPO_ROOT = str(Path(__file__).resolve().parents[2])
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

from backend.app.services.media_storage_service import (
    MediaStorageConfig,
    MediaStorageConfigError,
    MediaStorageService,
    MediaStorageUploadError,
    MediaUploadResult,
    PresignedUploadResult,
    get_media_storage_service,
    reset_media_storage_service,
)


def _s3_env(**overrides: str) -> dict[str, str]:
    base = {
        "ENVIRONMENT": "production",
        "MEDIA_STORAGE_PROVIDER": "s3",
        "S3_ENDPOINT_URL": "https://acct123.r2.cloudflarestorage.com",
        "S3_REGION": "auto",
        "S3_BUCKET": "saman-media",
        "S3_ACCESS_KEY_ID": "test-access-key",
        "S3_SECRET_ACCESS_KEY": "test-secret-key",
        "S3_PUBLIC_BASE_URL": "https://cdn.saman.app/",
    }
    base.update(overrides)
    return base


# ---------------------------------------------------------------------------
# S3 / Cloudflare R2 Tests
# ---------------------------------------------------------------------------


def test_s3_upload_bytes_success_with_r2_endpoint(monkeypatch: pytest.MonkeyPatch) -> None:
    fake_client = MagicMock()
    captured_client_kwargs: dict = {}

    fake_boto3 = types.ModuleType("boto3")

    def _fake_client(**kwargs):
        captured_client_kwargs.update(kwargs)
        return fake_client

    fake_boto3.client = _fake_client
    monkeypatch.setitem(sys.modules, "boto3", fake_boto3)

    cfg = MediaStorageConfig.from_env(_s3_env())
    svc = MediaStorageService(cfg)

    payload = b"\xff\xd8\xff\xe0fake-jpeg-bytes"
    res = svc.upload_bytes(
        data=payload,
        key_prefix="saman/community",
        filename="../../my photo.jpg",
        content_type="image/jpeg",
    )

    assert isinstance(res, MediaUploadResult)
    assert res.provider == "s3"
    assert res.size_bytes == len(payload)
    assert res.storage_key.startswith("saman/community/")
    assert res.storage_key.endswith(".jpg")
    assert ".." not in res.storage_key
    assert res.url == f"https://cdn.saman.app/{res.storage_key}"
    assert "//saman/" not in res.url

    assert captured_client_kwargs["service_name"] == "s3"
    assert captured_client_kwargs["endpoint_url"] == "https://acct123.r2.cloudflarestorage.com"
    assert captured_client_kwargs["region_name"] == "auto"
    assert captured_client_kwargs["aws_access_key_id"] == "test-access-key"
    assert captured_client_kwargs["aws_secret_access_key"] == "test-secret-key"

    fake_client.put_object.assert_called_once_with(
        Bucket="saman-media",
        Key=res.storage_key,
        Body=payload,
        ContentType="image/jpeg",
    )


def test_s3_missing_boto3_raises_config_error(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delitem(sys.modules, "boto3", raising=False)
    real_import = builtins.__import__

    def _blocked_boto3_import(name, *args, **kwargs):
        if name == "boto3":
            raise ImportError("No module named 'boto3'")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", _blocked_boto3_import)

    cfg = MediaStorageConfig.from_env(_s3_env())
    svc = MediaStorageService(cfg)

    with pytest.raises(MediaStorageConfigError, match="boto3"):
        svc.upload_bytes(
            data=b"abc",
            key_prefix="saman/community",
            filename="pic.png",
            content_type="image/png",
        )


def test_s3_generate_presigned_upload_url_success() -> None:
    fake_client = MagicMock()
    fake_client.generate_presigned_url.return_value = (
        "https://acct123.r2.cloudflarestorage.com/saman-media/saman/workouts/clip.mp4?X-Amz-Signature=abc"
    )

    cfg = MediaStorageConfig.from_env(_s3_env())
    svc = MediaStorageService(cfg, s3_client=fake_client)

    res = svc.generate_presigned_upload_url(
        storage_key="saman/workouts/user1_clip.mp4",
        content_type="video/mp4",
        max_bytes=50 * 1024 * 1024,
        expires_in=600,
    )

    assert isinstance(res, PresignedUploadResult)
    assert res.upload_url.startswith("https://acct123.r2.cloudflarestorage.com/")
    assert res.public_url == "https://cdn.saman.app/saman/workouts/user1_clip.mp4"
    assert res.storage_key == "saman/workouts/user1_clip.mp4"
    assert res.headers == {"Content-Type": "video/mp4"}
    assert res.expires_in == 600

    fake_client.generate_presigned_url.assert_called_once_with(
        "put_object",
        Params={
            "Bucket": "saman-media",
            "Key": "saman/workouts/user1_clip.mp4",
            "ContentType": "video/mp4",
        },
        ExpiresIn=600,
    )


@pytest.mark.parametrize(
    "bad_key,max_bytes,expires_in",
    [
        ("saman/workouts/../secret.mp4", 1024, 900),
        ("saman/workouts/../../etc/passwd", 1024, 900),
        ("other/bucket/video.mp4", 1024, 900),
        ("saman/workouts/", 1024, 900),
        ("", 1024, 900),
        ("saman/workouts/clip.mp4", 0, 900),
        ("saman/workouts/clip.mp4", -10, 900),
        ("saman/workouts/clip.mp4", 1024, 30),
        ("saman/workouts/clip.mp4", 1024, 7200),
    ],
)
def test_s3_generate_presigned_upload_url_rejects_invalid_inputs(
    bad_key: str, max_bytes: int, expires_in: int
) -> None:
    fake_client = MagicMock()
    svc = MediaStorageService(MediaStorageConfig.from_env(_s3_env()), s3_client=fake_client)

    with pytest.raises(ValueError):
        svc.generate_presigned_upload_url(
            storage_key=bad_key,
            content_type="video/mp4",
            max_bytes=max_bytes,
            expires_in=expires_in,
        )
    fake_client.generate_presigned_url.assert_not_called()


def test_presigned_upload_url_rejects_non_s3_provider(tmp_path: Path) -> None:
    cfg = MediaStorageConfig.from_env(
        {
            "ENVIRONMENT": "development",
            "MEDIA_STORAGE_PROVIDER": "local",
            "MEDIA_LOCAL_STATIC_ROOT": str(tmp_path),
        }
    )
    svc = MediaStorageService(cfg)

    with pytest.raises(MediaStorageConfigError, match="s3"):
        svc.generate_presigned_upload_url(
            storage_key="saman/workouts/demo.mp4",
            content_type="video/mp4",
            max_bytes=1024,
        )


def test_s3_delete_object_valid_and_blocked_keys() -> None:
    fake_client = MagicMock()
    svc = MediaStorageService(MediaStorageConfig.from_env(_s3_env()), s3_client=fake_client)

    assert svc.delete_object("saman/community/post_123.jpg") is True
    fake_client.delete_object.assert_called_once_with(
        Bucket="saman-media",
        Key="saman/community/post_123.jpg",
    )

    fake_client.reset_mock()
    for bad_key in (
        "",
        "saman/community/../avatars/a.jpg",
        "private/keys/secret.pem",
        "/saman/community/a.jpg",
        "saman/community/",
    ):
        assert svc.delete_object(bad_key) is False
    fake_client.delete_object.assert_not_called()


# ---------------------------------------------------------------------------
# Cloudinary Tests
# ---------------------------------------------------------------------------


def test_cloudinary_upload_bytes_success(monkeypatch: pytest.MonkeyPatch) -> None:
    fake_cloudinary = types.ModuleType("cloudinary")
    fake_uploader = types.ModuleType("cloudinary.uploader")

    config_mock = MagicMock()
    upload_mock = MagicMock(
        return_value={
            "secure_url": "https://res.cloudinary.com/demo/image/upload/v1/saman/stories/meal_123.jpg",
            "public_id": "saman/stories/meal_123",
        }
    )
    fake_cloudinary.config = config_mock
    fake_cloudinary.uploader = fake_uploader
    fake_uploader.upload = upload_mock

    monkeypatch.setitem(sys.modules, "cloudinary", fake_cloudinary)
    monkeypatch.setitem(sys.modules, "cloudinary.uploader", fake_uploader)

    cfg = MediaStorageConfig.from_env(
        {
            "ENVIRONMENT": "production",
            "MEDIA_STORAGE_PROVIDER": "cloudinary",
            "CLOUDINARY_CLOUD_NAME": "demo",
            "CLOUDINARY_API_KEY": "key123",
            "CLOUDINARY_API_SECRET": "secret456",
        }
    )
    svc = MediaStorageService(cfg)

    payload = b"fake-story-image"
    res = svc.upload_bytes(
        data=payload,
        key_prefix="saman/stories",
        filename="meal.jpg",
        content_type="image/jpeg",
    )

    assert res.provider == "cloudinary"
    assert res.url == "https://res.cloudinary.com/demo/image/upload/v1/saman/stories/meal_123.jpg"
    assert res.storage_key == "saman/stories/meal_123"
    assert res.size_bytes == len(payload)

    config_mock.assert_called_once_with(
        cloud_name="demo",
        api_key="key123",
        api_secret="secret456",
        secure=True,
    )
    upload_mock.assert_called_once()
    call_kwargs = upload_mock.call_args.kwargs
    assert call_kwargs["folder"] == "saman/stories"
    assert call_kwargs["resource_type"] == "auto"
    assert call_kwargs["overwrite"] is False


# ---------------------------------------------------------------------------
# Fail-Closed Configuration Tests
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "env_map",
    [
        {
            "ENVIRONMENT": "production",
            "MEDIA_STORAGE_PROVIDER": "local",
            "ALLOW_LOCAL_MEDIA_STORAGE": "false",
        },
        {
            "ENVIRONMENT": "PRODUCTION",
            "MEDIA_STORAGE_PROVIDER": "local",
        },
        {
            "ENVIRONMENT": "production",
        },
    ],
)
def test_fail_closed_production_local_storage(env_map: dict[str, str]) -> None:
    cfg = MediaStorageConfig.from_env(env_map)
    with pytest.raises(MediaStorageConfigError, match="Local media storage is disabled"):
        MediaStorageService(cfg)


@pytest.mark.parametrize(
    "missing_field",
    [
        "S3_BUCKET",
        "S3_ACCESS_KEY_ID",
        "S3_SECRET_ACCESS_KEY",
        "S3_PUBLIC_BASE_URL",
    ],
)
def test_fail_closed_s3_missing_required_config(missing_field: str) -> None:
    env_map = _s3_env()
    env_map.pop(missing_field)
    cfg = MediaStorageConfig.from_env(env_map)

    with pytest.raises(MediaStorageConfigError, match=missing_field):
        MediaStorageService(cfg)


# ---------------------------------------------------------------------------
# Local Dev Fallback Tests
# ---------------------------------------------------------------------------


def test_local_dev_upload_and_delete(tmp_path: Path) -> None:
    cfg = MediaStorageConfig.from_env(
        {
            "ENVIRONMENT": "development",
            "MEDIA_STORAGE_PROVIDER": "local",
            "MEDIA_LOCAL_STATIC_ROOT": str(tmp_path),
        }
    )
    svc = MediaStorageService(cfg)

    payload = b"hello-local-media"
    res = svc.upload_bytes(
        data=payload,
        key_prefix="saman/community",
        filename="../nested/photo.png",
        content_type="image/png",
    )

    assert res.provider == "local"
    assert res.size_bytes == len(payload)
    assert res.storage_key.startswith("saman/community/")
    assert res.url.startswith("/static/community/")
    assert res.url.endswith(".png")
    assert ".." not in res.url

    filename = res.url.split("/")[-1]
    written_file = tmp_path / "community" / filename
    assert written_file.is_file()
    assert written_file.read_bytes() == payload

    assert svc.delete_object(res.storage_key) is True
    assert not written_file.exists()
    assert svc.delete_object(res.storage_key) is False


def test_local_dev_upload_with_explicit_dir_and_url_override(tmp_path: Path) -> None:
    custom_dir = tmp_path / "dm_uploads"
    cfg = MediaStorageConfig.from_env(
        {
            "ENVIRONMENT": "development",
            "MEDIA_STORAGE_PROVIDER": "local",
            "MEDIA_LOCAL_STATIC_ROOT": str(tmp_path),
        }
    )
    svc = MediaStorageService(cfg)

    res = svc.upload_bytes(
        data=b"voice-bytes",
        key_prefix="saman/community_dm",
        filename="voice_note.m4a",
        content_type="audio/mp4",
        local_dir=custom_dir,
        local_url_prefix="/static/community_dm",
    )

    assert res.url.startswith("/static/community_dm/")
    assert res.url.endswith(".m4a")
    saved_path = custom_dir / res.url.split("/")[-1]
    assert saved_path.is_file()
    assert saved_path.read_bytes() == b"voice-bytes"


def test_upload_empty_bytes_raises_upload_error(tmp_path: Path) -> None:
    cfg = MediaStorageConfig.from_env(
        {
            "ENVIRONMENT": "development",
            "MEDIA_STORAGE_PROVIDER": "local",
            "MEDIA_LOCAL_STATIC_ROOT": str(tmp_path),
        }
    )
    svc = MediaStorageService(cfg)

    with pytest.raises(MediaStorageUploadError):
        svc.upload_bytes(
            data=b"",
            key_prefix="saman/community",
            filename="empty.jpg",
            content_type="image/jpeg",
        )


def test_singleton_factory_reload(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    reset_media_storage_service()
    monkeypatch.setenv("ENVIRONMENT", "development")
    monkeypatch.setenv("MEDIA_STORAGE_PROVIDER", "local")
    monkeypatch.setenv("MEDIA_LOCAL_STATIC_ROOT", str(tmp_path))

    svc1 = get_media_storage_service()
    svc2 = get_media_storage_service()
    assert svc1 is svc2
    assert svc1.provider == "local"

    svc3 = get_media_storage_service(force_reload=True)
    assert svc3 is not svc1
    reset_media_storage_service()
