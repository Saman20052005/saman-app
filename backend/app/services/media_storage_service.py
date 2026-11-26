"""Unified media storage service supporting Cloudflare R2 / AWS S3, Cloudinary, and Local dev fallback."""

from __future__ import annotations

import logging
import os
import re
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Optional
from urllib.parse import unquote, urlparse

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SUPPORTED_PROVIDERS: tuple[str, ...] = ("s3", "cloudinary", "local")

ALLOWED_STORAGE_PREFIXES: tuple[str, ...] = (
    "saman/workouts/",
    "saman/community/",
    "saman/community_dm/",
    "saman/avatars/",
    "saman/stories/",
)

ALLOWED_MEDIA_EXTENSIONS: frozenset[str] = frozenset(
    {
        ".jpg",
        ".jpeg",
        ".png",
        ".webp",
        ".gif",
        ".heic",
        ".mp4",
        ".mov",
        ".webm",
        ".m4a",
        ".mp3",
        ".wav",
        ".ogg",
        ".aac",
        ".opus",
    }
)

CONTENT_TYPE_TO_EXTENSION: dict[str, str] = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
    "image/heic": ".heic",
    "video/mp4": ".mp4",
    "video/quicktime": ".mov",
    "video/webm": ".webm",
    "audio/mp4": ".m4a",
    "audio/x-m4a": ".m4a",
    "audio/mpeg": ".mp3",
    "audio/wav": ".wav",
    "audio/x-wav": ".wav",
    "audio/ogg": ".ogg",
    "audio/aac": ".aac",
    "audio/opus": ".opus",
    "audio/webm": ".webm",
}

MIN_PRESIGN_EXPIRES_SECONDS = 60
MAX_PRESIGN_EXPIRES_SECONDS = 3600

_SAFE_SEGMENT_RE = re.compile(r"^[A-Za-z0-9_-]+$")
_SAFE_STEM_CHARS_RE = re.compile(r"[^A-Za-z0-9_-]+")

DEFAULT_LOCAL_STATIC_ROOT = Path(__file__).resolve().parents[2] / "static"


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------


class MediaStorageError(Exception):
    """Base exception for all media storage operations."""


class MediaStorageConfigError(MediaStorageError):
    """Raised when media storage configuration is missing, invalid, or disallowed."""


class MediaStorageUploadError(MediaStorageError):
    """Raised when uploading, presigning, or handling media payloads fails."""


# ---------------------------------------------------------------------------
# Result & Config Models
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MediaUploadResult:
    """Result returned after storing media bytes."""

    url: str
    storage_key: str
    provider: str
    size_bytes: int


@dataclass(frozen=True)
class PresignedUploadResult:
    """Result returned when issuing a presigned direct-to-object-storage upload URL."""

    upload_url: str
    public_url: str
    storage_key: str
    headers: dict[str, str]
    expires_in: int


def _parse_bool_env(raw: Optional[str], default: bool) -> bool:
    if raw is None or not raw.strip():
        return default
    return raw.strip().lower() in ("true", "1", "yes", "on")


@dataclass(frozen=True)
class MediaStorageConfig:
    """Typed configuration for MediaStorageService (supports env loading and test injection)."""

    environment: str = "development"
    provider: str = "local"
    allow_local_media_storage: bool = True

    # S3 / Cloudflare R2
    s3_endpoint_url: Optional[str] = None
    s3_region: str = "auto"
    s3_bucket: Optional[str] = None
    s3_access_key_id: Optional[str] = None
    s3_secret_access_key: Optional[str] = None
    s3_public_base_url: Optional[str] = None

    # Cloudinary (aligned with backend/services/avatar_service.py & backend/routers/nutrition.py)
    cloudinary_url: Optional[str] = None
    cloudinary_cloud_name: Optional[str] = None
    cloudinary_api_key: Optional[str] = None
    cloudinary_api_secret: Optional[str] = None

    # Local dev fallback
    local_static_root: Path = DEFAULT_LOCAL_STATIC_ROOT
    local_url_base: str = "/static"

    @property
    def is_production(self) -> bool:
        return self.environment.strip().lower() == "production"

    @classmethod
    def from_env(cls, env: Optional[Mapping[str, str]] = None) -> "MediaStorageConfig":
        """Build configuration from environment variables (or a custom mapping for tests)."""
        source = os.environ if env is None else env

        environment = (source.get("ENVIRONMENT") or "development").strip().lower()
        is_prod = environment == "production"

        raw_provider = (source.get("MEDIA_STORAGE_PROVIDER") or "").strip().lower()
        provider = raw_provider if raw_provider else "local"

        allow_local = _parse_bool_env(
            source.get("ALLOW_LOCAL_MEDIA_STORAGE"),
            default=not is_prod,
        )

        raw_static_root = (source.get("MEDIA_LOCAL_STATIC_ROOT") or "").strip()
        local_static_root = Path(raw_static_root) if raw_static_root else DEFAULT_LOCAL_STATIC_ROOT

        local_url_base = (source.get("MEDIA_LOCAL_URL_BASE") or "/static").strip() or "/static"

        return cls(
            environment=environment,
            provider=provider,
            allow_local_media_storage=allow_local,
            s3_endpoint_url=(source.get("S3_ENDPOINT_URL") or "").strip() or None,
            s3_region=(source.get("S3_REGION") or "auto").strip() or "auto",
            s3_bucket=(source.get("S3_BUCKET") or "").strip() or None,
            s3_access_key_id=(source.get("S3_ACCESS_KEY_ID") or "").strip() or None,
            s3_secret_access_key=(source.get("S3_SECRET_ACCESS_KEY") or "").strip() or None,
            s3_public_base_url=(source.get("S3_PUBLIC_BASE_URL") or "").strip() or None,
            cloudinary_url=(source.get("CLOUDINARY_URL") or "").strip() or None,
            cloudinary_cloud_name=(source.get("CLOUDINARY_CLOUD_NAME") or "").strip() or None,
            cloudinary_api_key=(source.get("CLOUDINARY_API_KEY") or "").strip() or None,
            cloudinary_api_secret=(source.get("CLOUDINARY_API_SECRET") or "").strip() or None,
            local_static_root=local_static_root,
            local_url_base=local_url_base,
        )


# ---------------------------------------------------------------------------
# Path & Key Sanitization Helpers
# ---------------------------------------------------------------------------


def is_safe_storage_key(storage_key: str) -> bool:
    """Return True iff storage_key is under an allowed prefix and free of traversal tokens."""
    if not isinstance(storage_key, str):
        return False
    key = storage_key.strip()
    if not key or key != storage_key:
        return False
    if key.startswith("/") or "\\" in key or "\x00" in key or "//" in key:
        return False
    if ".." in key:
        return False

    matched_prefix = next(
        (prefix for prefix in ALLOWED_STORAGE_PREFIXES if key.startswith(prefix)),
        None,
    )
    if matched_prefix is None:
        return False

    remainder = key[len(matched_prefix) :]
    if not remainder or remainder.endswith("/"):
        return False

    segments = remainder.split("/")
    for seg in segments:
        if not seg or seg in (".", ".."):
            return False
    return True


def _normalize_key_prefix(key_prefix: str) -> str:
    """Normalize and validate a key prefix against ALLOWED_STORAGE_PREFIXES."""
    if not isinstance(key_prefix, str):
        raise ValueError("key_prefix must be a non-empty string")
    cleaned = key_prefix.strip().strip("/")
    if not cleaned or "\\" in cleaned or "\x00" in cleaned or ".." in cleaned or "//" in cleaned:
        raise ValueError(f"Invalid key_prefix: {key_prefix!r}")

    segments = cleaned.split("/")
    for seg in segments:
        if not _SAFE_SEGMENT_RE.match(seg):
            raise ValueError(f"Invalid segment {seg!r} in key_prefix: {key_prefix!r}")

    candidate_with_slash = f"{cleaned}/"
    if not any(candidate_with_slash.startswith(prefix) for prefix in ALLOWED_STORAGE_PREFIXES):
        raise ValueError(
            f"key_prefix {key_prefix!r} is outside allowed prefixes: {ALLOWED_STORAGE_PREFIXES}"
        )
    return cleaned


def _sanitize_filename(filename: str, content_type: str) -> tuple[str, str]:
    """Sanitize an incoming filename and return (safe_filename_with_ext, safe_stem_with_uid)."""
    if not isinstance(filename, str):
        raise ValueError("filename must be a string")
    if "\x00" in filename:
        raise ValueError("filename contains null byte")

    # Strip any directory components (both POSIX and Windows separators)
    base = filename.replace("\\", "/").split("/")[-1].strip()
    raw_stem, raw_ext = os.path.splitext(base)

    ext = raw_ext.lower()
    if ext not in ALLOWED_MEDIA_EXTENSIONS:
        normalized_ct = (content_type or "").split(";")[0].strip().lower()
        ext = CONTENT_TYPE_TO_EXTENSION.get(normalized_ct, "")
    if ext not in ALLOWED_MEDIA_EXTENSIONS:
        raise ValueError(
            f"Unsupported media file extension {raw_ext!r} for content_type {content_type!r}"
        )

    # Remove traversal dots and non-safe characters from stem
    cleaned_stem = _SAFE_STEM_CHARS_RE.sub("_", raw_stem.replace("..", "")).strip("_-")
    if not cleaned_stem:
        cleaned_stem = "media"
    cleaned_stem = cleaned_stem[:48]

    unique_stem = f"{cleaned_stem}_{uuid.uuid4().hex[:12]}"
    return f"{unique_stem}{ext}", unique_stem


def _join_public_url(base_url: str, storage_key: str) -> str:
    return f"{base_url.rstrip('/')}/{storage_key.lstrip('/')}"


def _cloudinary_resource_type_for_key(storage_key: str) -> str:
    ext = os.path.splitext(storage_key)[1].lower()
    if ext in (".mp4", ".mov", ".webm", ".m4a", ".mp3", ".wav", ".ogg", ".aac", ".opus"):
        return "video"
    return "image"


# ---------------------------------------------------------------------------
# Service Implementation
# ---------------------------------------------------------------------------


class MediaStorageService:
    """Unified media storage abstraction for S3/R2, Cloudinary, and local development."""

    def __init__(
        self,
        config: Optional[MediaStorageConfig] = None,
        *,
        s3_client: Any = None,
    ) -> None:
        self.config = config if config is not None else MediaStorageConfig.from_env()
        self._s3_client = s3_client
        self._cloudinary_configured = False
        self._validate_config()

    @property
    def provider(self) -> str:
        return self.config.provider

    def _validate_config(self) -> None:
        provider = self.config.provider
        if provider not in SUPPORTED_PROVIDERS:
            raise MediaStorageConfigError(
                f"Unsupported MEDIA_STORAGE_PROVIDER={provider!r}. "
                f"Expected one of: {', '.join(SUPPORTED_PROVIDERS)}."
            )

        if provider == "local":
            self._assert_local_allowed()
            return

        if provider == "s3":
            missing: list[str] = []
            if not self.config.s3_bucket:
                missing.append("S3_BUCKET")
            if not self.config.s3_access_key_id:
                missing.append("S3_ACCESS_KEY_ID")
            if not self.config.s3_secret_access_key:
                missing.append("S3_SECRET_ACCESS_KEY")
            if not self.config.s3_public_base_url:
                missing.append("S3_PUBLIC_BASE_URL")
            if missing:
                raise MediaStorageConfigError(
                    f"Incomplete S3/R2 media storage configuration. Missing: {', '.join(missing)}."
                )
            parsed_base = urlparse(self.config.s3_public_base_url or "")
            if parsed_base.scheme not in ("http", "https") or not parsed_base.netloc:
                raise MediaStorageConfigError(
                    "S3_PUBLIC_BASE_URL must be a valid http(s) URL."
                )
            return

        if provider == "cloudinary":
            if self.config.cloudinary_url:
                parsed = urlparse(self.config.cloudinary_url)
                if (
                    parsed.scheme != "cloudinary"
                    or not parsed.hostname
                    or not parsed.username
                    or not parsed.password
                ):
                    raise MediaStorageConfigError("Invalid CLOUDINARY_URL configuration.")
            elif not (
                self.config.cloudinary_cloud_name
                and self.config.cloudinary_api_key
                and self.config.cloudinary_api_secret
            ):
                raise MediaStorageConfigError(
                    "Incomplete Cloudinary configuration. Set CLOUDINARY_URL or "
                    "(CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET)."
                )

    def _assert_local_allowed(self) -> None:
        if self.config.is_production and not self.config.allow_local_media_storage:
            raise MediaStorageConfigError(
                "Local media storage is disabled in production "
                "(set MEDIA_STORAGE_PROVIDER='s3' or 'cloudinary', or explicitly "
                "set ALLOW_LOCAL_MEDIA_STORAGE='true' to override)."
            )

    def _get_s3_client(self) -> Any:
        if self._s3_client is not None:
            return self._s3_client

        try:
            import boto3  # type: ignore[import-not-found]
        except ImportError as exc:
            raise MediaStorageConfigError(
                "boto3 is required when MEDIA_STORAGE_PROVIDER='s3'. "
                "Install boto3 before using the S3/R2 storage backend."
            ) from exc

        client_kwargs: dict[str, Any] = {
            "service_name": "s3",
            "region_name": self.config.s3_region,
            "aws_access_key_id": self.config.s3_access_key_id,
            "aws_secret_access_key": self.config.s3_secret_access_key,
        }
        if self.config.s3_endpoint_url:
            client_kwargs["endpoint_url"] = self.config.s3_endpoint_url

        try:
            from botocore.config import Config as BotoConfig  # type: ignore[import-not-found]

            client_kwargs["config"] = BotoConfig(signature_version="s3v4")
        except ImportError:
            # Allow mocked boto3 in test environments without botocore installed.
            pass

        self._s3_client = boto3.client(**client_kwargs)
        return self._s3_client

    def _get_cloudinary_uploader(self) -> Any:
        try:
            import cloudinary  # type: ignore[import-not-found]
            import cloudinary.uploader  # type: ignore[import-not-found]
        except ImportError as exc:
            raise MediaStorageConfigError(
                "cloudinary package is required when MEDIA_STORAGE_PROVIDER='cloudinary'."
            ) from exc

        if not self._cloudinary_configured:
            if self.config.cloudinary_url:
                parsed = urlparse(self.config.cloudinary_url)
                cloudinary.config(
                    cloud_name=parsed.hostname,
                    api_key=unquote(parsed.username or ""),
                    api_secret=unquote(parsed.password or ""),
                    secure=True,
                )
            else:
                cloudinary.config(
                    cloud_name=self.config.cloudinary_cloud_name,
                    api_key=self.config.cloudinary_api_key,
                    api_secret=self.config.cloudinary_api_secret,
                    secure=True,
                )
            self._cloudinary_configured = True

        return cloudinary.uploader

    def _resolve_local_target(
        self,
        normalized_prefix: str,
        local_dir: Optional[Path],
        local_url_prefix: Optional[str],
    ) -> tuple[Path, str]:
        relative_subpath = (
            normalized_prefix[len("saman/") :]
            if normalized_prefix.startswith("saman/")
            else normalized_prefix
        )
        target_dir = (
            Path(local_dir)
            if local_dir is not None
            else self.config.local_static_root / relative_subpath
        )
        url_prefix = (
            local_url_prefix.rstrip("/")
            if local_url_prefix is not None
            else f"{self.config.local_url_base.rstrip('/')}/{relative_subpath}"
        )
        return target_dir, url_prefix

    def upload_bytes(
        self,
        data: bytes,
        key_prefix: str,
        filename: str,
        content_type: str,
        local_dir: Optional[Path] = None,
        local_url_prefix: Optional[str] = None,
    ) -> MediaUploadResult:
        """Upload raw bytes to the configured storage backend and return a normalized result."""
        if not isinstance(data, (bytes, bytearray)) or len(data) == 0:
            raise MediaStorageUploadError("Cannot upload empty media payload.")

        payload = bytes(data)
        normalized_prefix = _normalize_key_prefix(key_prefix)
        safe_filename, safe_stem = _sanitize_filename(filename, content_type)
        storage_key = f"{normalized_prefix}/{safe_filename}"

        if self.config.provider == "s3":
            client = self._get_s3_client()
            try:
                client.put_object(
                    Bucket=self.config.s3_bucket,
                    Key=storage_key,
                    Body=payload,
                    ContentType=content_type,
                )
            except MediaStorageError:
                raise
            except Exception as exc:
                raise MediaStorageUploadError(f"S3/R2 upload failed for {storage_key}: {exc}") from exc

            public_url = _join_public_url(self.config.s3_public_base_url or "", storage_key)
            return MediaUploadResult(
                url=public_url,
                storage_key=storage_key,
                provider="s3",
                size_bytes=len(payload),
            )

        if self.config.provider == "cloudinary":
            uploader = self._get_cloudinary_uploader()
            try:
                result = uploader.upload(
                    payload,
                    folder=normalized_prefix,
                    public_id=safe_stem,
                    overwrite=False,
                    resource_type="auto",
                )
            except MediaStorageError:
                raise
            except Exception as exc:
                raise MediaStorageUploadError(
                    f"Cloudinary upload failed for {storage_key}: {exc}"
                ) from exc

            secure_url = (result or {}).get("secure_url")
            if not secure_url:
                raise MediaStorageUploadError("Cloudinary upload did not return a secure_url.")
            public_id = (result or {}).get("public_id") or f"{normalized_prefix}/{safe_stem}"
            return MediaUploadResult(
                url=str(secure_url),
                storage_key=str(public_id),
                provider="cloudinary",
                size_bytes=len(payload),
            )

        if self.config.provider == "local":
            self._assert_local_allowed()
            target_dir, url_prefix = self._resolve_local_target(
                normalized_prefix=normalized_prefix,
                local_dir=local_dir,
                local_url_prefix=local_url_prefix,
            )
            try:
                target_dir.mkdir(parents=True, exist_ok=True)
                resolved_dir = target_dir.resolve()
                target_path = (resolved_dir / safe_filename).resolve()
                if target_path.parent != resolved_dir:
                    raise MediaStorageUploadError("Resolved local target path escapes base directory.")
                target_path.write_bytes(payload)
            except MediaStorageError:
                raise
            except Exception as exc:
                raise MediaStorageUploadError(f"Local media write failed for {storage_key}: {exc}") from exc

            return MediaUploadResult(
                url=f"{url_prefix}/{safe_filename}",
                storage_key=storage_key,
                provider="local",
                size_bytes=len(payload),
            )

        raise MediaStorageConfigError(f"Unsupported provider: {self.config.provider!r}")

    def generate_presigned_upload_url(
        self,
        storage_key: str,
        content_type: str,
        max_bytes: int,
        expires_in: int = 900,
    ) -> PresignedUploadResult:
        """Generate a presigned S3/R2 PUT URL for direct client uploads (e.g. Video Workout Story)."""
        if self.config.provider != "s3":
            raise MediaStorageConfigError(
                "generate_presigned_upload_url is only supported when MEDIA_STORAGE_PROVIDER='s3' "
                f"(current provider: {self.config.provider!r})."
            )

        if not is_safe_storage_key(storage_key):
            raise ValueError(
                f"Invalid storage_key {storage_key!r}. Must start with one of {ALLOWED_STORAGE_PREFIXES} "
                "and must not contain traversal sequences."
            )

        clean_content_type = (content_type or "").strip()
        if not clean_content_type or "/" not in clean_content_type:
            raise ValueError(f"Invalid content_type: {content_type!r}")

        if not isinstance(max_bytes, int) or isinstance(max_bytes, bool) or max_bytes <= 0:
            raise ValueError("max_bytes must be a positive integer.")

        if (
            not isinstance(expires_in, int)
            or isinstance(expires_in, bool)
            or not (MIN_PRESIGN_EXPIRES_SECONDS <= expires_in <= MAX_PRESIGN_EXPIRES_SECONDS)
        ):
            raise ValueError(
                f"expires_in must be between {MIN_PRESIGN_EXPIRES_SECONDS} "
                f"and {MAX_PRESIGN_EXPIRES_SECONDS} seconds."
            )

        client = self._get_s3_client()
        try:
            upload_url = client.generate_presigned_url(
                "put_object",
                Params={
                    "Bucket": self.config.s3_bucket,
                    "Key": storage_key,
                    "ContentType": clean_content_type,
                },
                ExpiresIn=expires_in,
            )
        except MediaStorageError:
            raise
        except Exception as exc:
            raise MediaStorageUploadError(
                f"Failed to generate presigned upload URL for {storage_key}: {exc}"
            ) from exc

        if not upload_url or not isinstance(upload_url, str):
            raise MediaStorageUploadError("Presigned URL generator returned an empty URL.")

        public_url = _join_public_url(self.config.s3_public_base_url or "", storage_key)
        return PresignedUploadResult(
            upload_url=upload_url,
            public_url=public_url,
            storage_key=storage_key,
            headers={"Content-Type": clean_content_type},
            expires_in=expires_in,
        )

    def delete_object(self, storage_key: str) -> bool:
        """Safely delete an object under ALLOWED_STORAGE_PREFIXES. Returns False if rejected or missing."""
        if not is_safe_storage_key(storage_key):
            logger.warning("Refusing to delete unsafe or out-of-scope storage_key: %r", storage_key)
            return False

        if self.config.provider == "s3":
            client = self._get_s3_client()
            try:
                client.delete_object(Bucket=self.config.s3_bucket, Key=storage_key)
                return True
            except Exception as exc:
                logger.warning("Failed to delete S3/R2 object %s: %s", storage_key, exc)
                return False

        if self.config.provider == "cloudinary":
            try:
                uploader = self._get_cloudinary_uploader()
                res = uploader.destroy(
                    storage_key,
                    resource_type=_cloudinary_resource_type_for_key(storage_key),
                )
                if isinstance(res, dict):
                    return res.get("result") == "ok"
                return bool(res)
            except Exception as exc:
                logger.warning("Failed to delete Cloudinary object %s: %s", storage_key, exc)
                return False

        if self.config.provider == "local":
            self._assert_local_allowed()
            relative_path = (
                storage_key[len("saman/") :]
                if storage_key.startswith("saman/")
                else storage_key
            )
            root_resolved = self.config.local_static_root.resolve()
            target_path = (root_resolved / relative_path).resolve()
            try:
                target_path.relative_to(root_resolved)
            except ValueError:
                logger.warning("Refusing to delete local file outside static root: %r", storage_key)
                return False
            if target_path.is_file():
                try:
                    target_path.unlink()
                    return True
                except Exception as exc:
                    logger.warning("Failed to delete local file %s: %s", target_path, exc)
                    return False
            return False

        return False


# ---------------------------------------------------------------------------
# Singleton / Factory Helpers
# ---------------------------------------------------------------------------

_default_service: Optional[MediaStorageService] = None


def get_media_storage_service(*, force_reload: bool = False) -> MediaStorageService:
    """Return a cached MediaStorageService instance configured from environment variables."""
    global _default_service
    if _default_service is None or force_reload:
        _default_service = MediaStorageService(MediaStorageConfig.from_env())
    return _default_service


def reset_media_storage_service() -> None:
    """Clear the cached MediaStorageService singleton (useful for tests)."""
    global _default_service
    _default_service = None
