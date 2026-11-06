# [File: backend/services/avatar_service.py]
import io
import os
import time
import uuid
import logging
from urllib.parse import urlparse, unquote
from typing import Optional, Tuple
from PIL import Image, ImageOps

try:
    import cloudinary
    import cloudinary.uploader
    HAS_CLOUDINARY = True
except ImportError:
    cloudinary = None
    HAS_CLOUDINARY = False

logger = logging.getLogger(__name__)

# Max file size: 5 MB
MAX_AVATAR_BYTES = 5 * 1024 * 1024
# Max pixel dimension
MAX_PIXEL_DIMENSION = 1024
# Max decoded pixels before raster allocation (16 Megapixels, e.g. 4000x4000)
MAX_DECODED_PIXELS = 16_000_000
# Allowed image formats
ALLOWED_FORMATS = {"JPEG", "PNG", "WEBP"}

# Local storage path for dev / testing
LOCAL_AVATAR_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "static", "avatars"
)
if os.getenv("ENVIRONMENT", "development").lower() in ("development", "test"):
    LOCAL_AVATAR_DIR = os.getenv("AVATAR_LOCAL_DIR", LOCAL_AVATAR_DIR)


def is_google_avatar_url(url: Optional[str]) -> bool:
    """
    Checks if a URL reliably points to an authentic Google profile picture.
    Strictly verifies scheme (http/https) and hostname against known Google avatar hosts:
      - *.googleusercontent.com (e.g. lh3.googleusercontent.com)
      - *.ggpht.com (legacy Google photo CDN)
    Rejects spoofed domains (e.g. evilgoogle.com, googleusercontent.com.evil.com),
    and rejects generic google.com URLs not tied to profile image hosts.
    """
    if not url or not isinstance(url, str):
        return False
    try:
        parsed = urlparse(url.strip())
        if parsed.scheme not in ("http", "https"):
            return False
        hostname = (parsed.hostname or "").lower()
        if not hostname:
            return False

        if hostname == "googleusercontent.com" or hostname.endswith(".googleusercontent.com"):
            return True
        if hostname == "ggpht.com" or hostname.endswith(".ggpht.com"):
            return True

        return False
    except Exception:
        return False


def is_cloudinary_configured() -> bool:
    """
    Checks if Cloudinary is configured via either CLOUDINARY_URL
    or the tuple (CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET).
    """
    if not HAS_CLOUDINARY:
        return False
    if os.getenv("CLOUDINARY_URL"):
        return True
    cloud_name = os.getenv("CLOUDINARY_CLOUD_NAME")
    api_key = os.getenv("CLOUDINARY_API_KEY")
    api_secret = os.getenv("CLOUDINARY_API_SECRET")
    return bool(cloud_name and api_key and api_secret)


def configure_cloudinary():
    """
    Configures Cloudinary with existing environment credentials.
    """
    if not is_cloudinary_configured():
        return
    c_url = os.getenv("CLOUDINARY_URL")
    if c_url:
        parsed = urlparse(c_url)
        if parsed.scheme != "cloudinary" or not parsed.hostname or not parsed.username or not parsed.password:
            raise RuntimeError("Invalid Cloudinary configuration")
        cloudinary.config(
            cloud_name=parsed.hostname,
            api_key=unquote(parsed.username),
            api_secret=unquote(parsed.password),
            secure=True,
        )
    else:
        cloudinary.config(
            cloud_name=os.getenv("CLOUDINARY_CLOUD_NAME"),
            api_key=os.getenv("CLOUDINARY_API_KEY"),
            api_secret=os.getenv("CLOUDINARY_API_SECRET"),
        )


def is_local_storage_enabled() -> bool:
    """
    Local storage is ONLY permissible when explicitly enabled for development or testing,
    and NEVER in production environments.
    """
    env = os.getenv("ENVIRONMENT", "development").lower()
    if env not in ("development", "test"):
        return False
    allow_local = os.getenv("ALLOW_LOCAL_AVATAR_STORAGE", "").lower()
    return allow_local in ("true", "1", "yes")


def is_storage_configured() -> bool:
    """
    Returns True if either Cloudinary or authorized local storage is ready.
    """
    return is_cloudinary_configured() or is_local_storage_enabled()


def get_local_avatar_base_url() -> str:
    """
    Returns the base URL for locally served avatars.
    Can be customized via AVATAR_BASE_URL (e.g. http://10.0.2.2:8000 for Android emulator).
    """
    return os.getenv("AVATAR_BASE_URL", "http://localhost:8000").rstrip("/")


def resolve_avatar_state(user: dict) -> dict:
    """
    Unified resolver for user avatar state.
    Priority & compatibility rules:
    - If user explicitly chose 'custom' and has valid custom_avatar -> use custom.
    - If user explicitly chose 'google' and has valid google_avatar -> use google.
    - If no source chosen:
        * Has custom_avatar -> custom
        * Has google_avatar -> google
        * Legacy user with avatar only:
            - If URL is verified Google domain -> classify as google_avatar
            - Otherwise -> classify as custom_avatar
    - Otherwise -> None (initials fallback).
    """
    avatar_source = user.get("avatar_source")
    custom_avatar = user.get("custom_avatar")
    google_avatar = user.get("google_avatar")
    legacy_avatar = user.get("avatar")

    # Backward compatibility inference for legacy documents:
    if avatar_source not in ("custom", "google") and not custom_avatar and not google_avatar and legacy_avatar:
        if is_google_avatar_url(legacy_avatar):
            google_avatar = legacy_avatar
            if not avatar_source:
                avatar_source = "google"
        else:
            custom_avatar = legacy_avatar
            if not avatar_source:
                avatar_source = "custom"

    effective_avatar = None
    resolved_source = "none"

    if avatar_source == "custom":
        if custom_avatar:
            effective_avatar = custom_avatar
            resolved_source = "custom"
        elif legacy_avatar:
            effective_avatar = legacy_avatar
            resolved_source = "custom"
        elif google_avatar:
            effective_avatar = google_avatar
            resolved_source = "google"
        else:
            effective_avatar = None
            resolved_source = "none"
    elif avatar_source == "google":
        if google_avatar:
            effective_avatar = google_avatar
            resolved_source = "google"
        elif legacy_avatar:
            effective_avatar = legacy_avatar
            resolved_source = "google"
        elif custom_avatar:
            effective_avatar = custom_avatar
            resolved_source = "custom"
        else:
            effective_avatar = None
            resolved_source = "none"
    else:
        # Preserve a legacy active URL whose provenance is still unknown.
        if legacy_avatar and not is_google_avatar_url(legacy_avatar) and not custom_avatar:
            effective_avatar = legacy_avatar
            resolved_source = "custom"
        elif custom_avatar:
            effective_avatar = custom_avatar
            resolved_source = "custom"
        elif google_avatar:
            effective_avatar = google_avatar
            resolved_source = "google"
        elif legacy_avatar:
            if is_google_avatar_url(legacy_avatar):
                effective_avatar = legacy_avatar
                resolved_source = "google"
            else:
                effective_avatar = legacy_avatar
                resolved_source = "custom"
        else:
            effective_avatar = None
            resolved_source = "none"

    can_use_google = bool(google_avatar and resolved_source != "google")

    return {
        "avatar": effective_avatar,
        "avatar_source": resolved_source,
        "custom_avatar": custom_avatar,
        "google_avatar": google_avatar,
        "can_use_google_avatar": can_use_google,
    }


def process_and_normalize_avatar(file_bytes: bytes) -> bytes:
    """
    Validates, corrects EXIF orientation, resizes if exceeding max dimensions,
    and normalizes avatar image into clean JPEG bytes (stripping non-image metadata).
    Guards pixel limits BEFORE decompressing raster into memory to prevent decompression bombs.
    Raises ValueError on invalid image or unsupported format.
    """
    if len(file_bytes) > MAX_AVATAR_BYTES:
        raise ValueError("Dung lượng ảnh vượt quá giới hạn 5 MB")

    if not file_bytes:
        raise ValueError("File ảnh rỗng")

    try:
        raw_io = io.BytesIO(file_bytes)
        img = Image.open(raw_io)
        img_format = img.format
        if not img_format or img_format.upper() not in ALLOWED_FORMATS:
            raise ValueError(f"Định dạng ảnh không được hỗ trợ: {img_format}. Chỉ chấp nhận JPG, PNG, WEBP")

        # Guard pixel resolution from header BEFORE decompressing raster into memory
        width, height = img.size
        if width <= 0 or height <= 0:
            raise ValueError("Kích thước ảnh không hợp lệ.")
        if width * height > MAX_DECODED_PIXELS:
            raise ValueError(
                f"Độ phân giải ảnh quá lớn ({width}x{height} = {width * height} pixels). "
                f"Tối đa cho phép là {MAX_DECODED_PIXELS} pixels (16 MP)."
            )

        # Verify image integrity
        img.verify()
    except Exception as e:
        if isinstance(e, ValueError):
            raise
        raise ValueError(f"File ảnh không hợp lệ hoặc bị hỏng: {e}")

    # Re-open image after verify() since verify() destroys internal image data
    raw_io.seek(0)
    img = Image.open(raw_io)

    # Correct EXIF orientation
    try:
        img = ImageOps.exif_transpose(img)
    except Exception:
        pass

    # Resize if either dimension exceeds MAX_PIXEL_DIMENSION
    width, height = img.size
    if width > MAX_PIXEL_DIMENSION or height > MAX_PIXEL_DIMENSION:
        img.thumbnail((MAX_PIXEL_DIMENSION, MAX_PIXEL_DIMENSION), Image.Resampling.LANCZOS)

    # Convert to RGB (removing transparency/alpha channel for clean JPEG compression)
    if img.mode in ("RGBA", "LA", "P"):
        background = Image.new("RGB", img.size, (255, 255, 255))
        if img.mode == "P":
            img = img.convert("RGBA")
        background.paste(img, mask=img.split()[-1] if img.mode == "RGBA" else None)
        img = background
    elif img.mode != "RGB":
        img = img.convert("RGB")

    output_io = io.BytesIO()
    # A new pixel-only image strips ICC, EXIF, comments and other source metadata.
    clean = Image.new("RGB", img.size)
    clean.paste(img)
    clean.save(output_io, format="JPEG", quality=85, optimize=True)
    return output_io.getvalue()


def upload_avatar_sync(normalized_bytes: bytes, user_id: str) -> dict:
    """
    Synchronous upload handler supporting Cloudinary (primary) and authorized Local Storage (dev/test fallback).
    Raises RuntimeError if neither storage backend is configured.
    """
    if not is_storage_configured():
        raise RuntimeError("No avatar storage backend is configured on this server")

    timestamp = int(time.time())
    rand_suffix = uuid.uuid4().hex[:8]

    if is_cloudinary_configured():
        configure_cloudinary()
        public_id = f"user_{user_id}_{timestamp}_{rand_suffix}"
        folder = "saman/avatars"

        result = cloudinary.uploader.upload(
            normalized_bytes,
            folder=folder,
            public_id=public_id,
            overwrite=False,
            resource_type="image",
        )
        return {
            "secure_url": result.get("secure_url"),
            "public_id": result.get("public_id"),
            "storage_type": "cloudinary",
        }

    if is_local_storage_enabled():
        os.makedirs(LOCAL_AVATAR_DIR, exist_ok=True)
        filename = f"avatar_{user_id}_{timestamp}_{rand_suffix}.jpg"
        filepath = os.path.join(LOCAL_AVATAR_DIR, filename)

        with open(filepath, "wb") as f:
            f.write(normalized_bytes)

        base_url = get_local_avatar_base_url()
        url = f"{base_url}/api/static/avatars/{filename}"
        return {
            "secure_url": url,
            "public_id": f"local:{filename}",
            "storage_type": "local",
        }

    raise RuntimeError("Storage backend unavailable")


def destroy_avatar_sync(public_id: Optional[str]) -> bool:
    """
    Deletes an avatar asset on Cloudinary or local storage.
    Strictly safeguards that only assets in 'saman/avatars/' or local avatars can be destroyed.
    """
    if not public_id or not isinstance(public_id, str):
        return False

    # Local storage deletion
    if public_id.startswith("local:"):
        filename = public_id[len("local:"):]
        # Only locally generated avatar names belong to this storage backend.
        if filename != os.path.basename(filename) or not filename.startswith("avatar_") or not filename.endswith(".jpg"):
            return False
        if not is_local_storage_enabled():
            return False
        clean_name = filename
        target_path = os.path.join(LOCAL_AVATAR_DIR, clean_name)
        if os.path.exists(target_path):
            try:
                os.remove(target_path)
                logger.info("Local avatar file removed: %s", clean_name)
                return True
            except Exception as e:
                logger.warning("Failed to delete local avatar file %s: %s", clean_name, e)
                return False
        return False

    # Cloudinary deletion
    if not public_id.startswith("saman/avatars/"):
        logger.warning("Refusing to delete asset outside saman/avatars/: %s", public_id)
        return False

    if not is_cloudinary_configured():
        logger.warning("Cannot destroy asset: Cloudinary not configured")
        return False

    try:
        configure_cloudinary()
        res = cloudinary.uploader.destroy(public_id, resource_type="image")
        logger.info("Cloudinary asset destroyed: %s, result: %s", public_id, res)
        return True
    except Exception as e:
        logger.warning("Failed to destroy old Cloudinary asset %s: %s", public_id, e)
        return False


AVATAR_STATE_FIELDS = ("avatar", "avatar_source", "google_avatar", "custom_avatar", "custom_avatar_public_id")


def avatar_state_filter(user: dict) -> dict:
    """Compare the complete observed avatar state using stable MongoDB identity."""
    return {"_id": user["_id"], **{key: user.get(key) for key in AVATAR_STATE_FIELDS}}


def sync_google_avatar(collection, user: dict, picture: str) -> dict:
    """Retry a stale read; never reclassify an explicitly selected source."""
    for _ in range(8):
        changes = {"google_avatar": picture}
        source = user.get("avatar_source")
        legacy = user.get("avatar")
        if source == "google":
            changes.update(avatar=picture)
        elif source not in ("custom", "google"):
            if legacy and not is_google_avatar_url(legacy) and not user.get("custom_avatar"):
                changes.update(custom_avatar=legacy, avatar_source="custom")
            elif not user.get("custom_avatar"):
                changes.update(avatar=picture, avatar_source="google")
        result = collection.update_one(avatar_state_filter(user), {"$set": changes})
        fresh = collection.find_one({"_id": user["_id"]})
        if fresh is None:
            raise RuntimeError("Avatar owner no longer exists")
        if result.matched_count:
            return fresh
        user = fresh
    raise RuntimeError("Concurrent avatar updates; retry login")


def cleanup_unreferenced_avatar(collection, public_id, url):
    """Only acknowledged, retired assets are candidates; uncertain writes are retained.

    Avatar writers never reintroduce retired IDs: uploads use unique IDs, Google
    selection retains custom metadata and legacy migration compares the full state.
    A read failure therefore retains the asset for later manual reconciliation.
    """
    if not public_id or not url:
        return False
    try:
        referenced = collection.find_one({"$or": [
            {"custom_avatar_public_id": public_id}, {"avatar": url}, {"custom_avatar": url},
            {"google_avatar": url},
        ]})
    except Exception:
        logger.warning("Avatar reference check unavailable; retaining asset")
        return False
    if referenced:
        return False
    return destroy_avatar_sync(public_id)
