# [File: backend/tests/test_avatar.py]
import io
import os
import unittest
from unittest.mock import patch
from PIL import Image
from backend.services.avatar_service import (
    is_google_avatar_url,
    resolve_avatar_state,
    process_and_normalize_avatar,
    destroy_avatar_sync,
    upload_avatar_sync,
    is_storage_configured,
    is_local_storage_enabled,
    LOCAL_AVATAR_DIR,
    MAX_AVATAR_BYTES,
    MAX_PIXEL_DIMENSION,
    MAX_DECODED_PIXELS,
)


class TestAvatarService(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_is_google_avatar_url_authentic_domains(self):
        self.assertTrue(is_google_avatar_url("https://lh3.googleusercontent.com/a/ACg8ocKS=s96-c"))
        self.assertTrue(is_google_avatar_url("https://lh5.googleusercontent.com/photo.jpg"))
        self.assertTrue(is_google_avatar_url("https://lh3.ggpht.com/a/xyz=s96-c"))
        self.assertTrue(is_google_avatar_url("http://googleusercontent.com/avatar.png"))

    def test_is_google_avatar_url_rejects_spoofed_and_invalid_domains(self):
        # Subdomain spoofing
        self.assertFalse(is_google_avatar_url("https://googleusercontent.com.evil.example/pic.jpg"))
        self.assertFalse(is_google_avatar_url("https://ggpht.com.attacker.org/avatar.jpg"))
        # Evil name matching
        self.assertFalse(is_google_avatar_url("https://evilgoogle.com/pic.jpg"))
        self.assertFalse(is_google_avatar_url("https://notgoogle.com/photo.jpg"))
        # Path and query tricks
        self.assertFalse(is_google_avatar_url("https://evil.com/googleusercontent.com/pic.jpg"))
        self.assertFalse(is_google_avatar_url("https://evil.com/?ref=googleusercontent.com"))
        self.assertFalse(is_google_avatar_url("https://evil.com/?q=https://lh3.googleusercontent.com"))
        # Generic google.com (not an avatar host)
        self.assertFalse(is_google_avatar_url("https://google.com/search?q=avatar"))
        self.assertFalse(is_google_avatar_url("https://www.google.com/"))
        # Non-http/https schemes
        self.assertFalse(is_google_avatar_url("javascript:alert(1)"))
        self.assertFalse(is_google_avatar_url("file:///etc/passwd"))
        # Other CDNs
        self.assertFalse(is_google_avatar_url("https://res.cloudinary.com/saman/image/upload/v1/avatar.jpg"))
        self.assertFalse(is_google_avatar_url("https://example.com/my_avatar.png"))
        self.assertFalse(is_google_avatar_url(""))
        self.assertFalse(is_google_avatar_url(None))

    def test_resolve_avatar_state_new_google_user(self):
        user = {
            "avatar": "https://lh3.googleusercontent.com/a/google_pic",
            "avatar_source": "google",
            "google_avatar": "https://lh3.googleusercontent.com/a/google_pic",
            "custom_avatar": None,
        }
        res = resolve_avatar_state(user)
        self.assertEqual(res["avatar"], "https://lh3.googleusercontent.com/a/google_pic")
        self.assertEqual(res["avatar_source"], "google")
        self.assertFalse(res["can_use_google_avatar"])

    def test_resolve_avatar_state_custom_selected(self):
        user = {
            "avatar": "https://res.cloudinary.com/saman/avatar_custom.jpg",
            "avatar_source": "custom",
            "custom_avatar": "https://res.cloudinary.com/saman/avatar_custom.jpg",
            "google_avatar": "https://lh3.googleusercontent.com/a/google_pic",
        }
        res = resolve_avatar_state(user)
        self.assertEqual(res["avatar"], "https://res.cloudinary.com/saman/avatar_custom.jpg")
        self.assertEqual(res["avatar_source"], "custom")
        self.assertTrue(res["can_use_google_avatar"])

    def test_resolve_avatar_state_reverted_to_google_with_custom_still_saved(self):
        # User previously uploaded custom, then clicked "Dùng ảnh Google"
        # Must resolve to google_avatar despite custom_avatar existing in the record!
        user = {
            "avatar": "https://lh3.googleusercontent.com/a/google_pic",
            "avatar_source": "google",
            "custom_avatar": "https://res.cloudinary.com/saman/avatar_custom.jpg",
            "google_avatar": "https://lh3.googleusercontent.com/a/google_pic",
        }
        res = resolve_avatar_state(user)
        self.assertEqual(res["avatar"], "https://lh3.googleusercontent.com/a/google_pic")
        self.assertEqual(res["avatar_source"], "google")
        self.assertFalse(res["can_use_google_avatar"])

    def test_resolve_avatar_state_legacy_google_avatar(self):
        # Old user with only avatar field pointing to authentic googleusercontent
        user = {
            "avatar": "https://lh3.googleusercontent.com/a/legacy_google=s96-c",
        }
        res = resolve_avatar_state(user)
        self.assertEqual(res["avatar"], "https://lh3.googleusercontent.com/a/legacy_google=s96-c")
        self.assertEqual(res["avatar_source"], "google")
        self.assertFalse(res["can_use_google_avatar"])

    def test_resolve_avatar_state_legacy_custom_avatar(self):
        # Old user with only avatar field pointing to non-google source
        user = {
            "avatar": "https://res.cloudinary.com/saman/legacy_custom.jpg",
        }
        res = resolve_avatar_state(user)
        self.assertEqual(res["avatar"], "https://res.cloudinary.com/saman/legacy_custom.jpg")
        self.assertEqual(res["avatar_source"], "custom")
        self.assertFalse(res["can_use_google_avatar"])

    def test_resolve_avatar_state_no_avatar(self):
        user = {
            "email": "user@example.com",
            "full_name": "Athlete",
        }
        res = resolve_avatar_state(user)
        self.assertIsNone(res["avatar"])
        self.assertEqual(res["avatar_source"], "none")
        self.assertFalse(res["can_use_google_avatar"])

    def test_google_login_does_not_overwrite_custom_avatar(self):
        # Simulating user with custom avatar logging in again with Google
        user = {
            "email": "athlete@example.com",
            "avatar": "https://res.cloudinary.com/saman/my_custom_photo.jpg",
            "avatar_source": "custom",
            "custom_avatar": "https://res.cloudinary.com/saman/my_custom_photo.jpg",
            "google_avatar": "https://lh3.googleusercontent.com/old_google_pic",
        }
        new_google_pic = "https://lh3.googleusercontent.com/new_google_pic"
        current_state = resolve_avatar_state(user)
        update_fields = {"google_avatar": new_google_pic}
        if current_state["avatar_source"] != "custom":
            update_fields["avatar"] = new_google_pic
            update_fields["avatar_source"] = "google"
        user.update(update_fields)

        final_state = resolve_avatar_state(user)
        self.assertEqual(final_state["avatar"], "https://res.cloudinary.com/saman/my_custom_photo.jpg")
        self.assertEqual(final_state["avatar_source"], "custom")
        self.assertEqual(final_state["google_avatar"], new_google_pic)
        self.assertTrue(final_state["can_use_google_avatar"])

    def test_google_login_updates_avatar_when_source_is_google(self):
        user = {
            "email": "athlete@example.com",
            "avatar": "https://lh3.googleusercontent.com/old_pic",
            "avatar_source": "google",
            "google_avatar": "https://lh3.googleusercontent.com/old_pic",
        }
        new_google_pic = "https://lh3.googleusercontent.com/updated_pic"
        current_state = resolve_avatar_state(user)
        update_fields = {"google_avatar": new_google_pic}
        if current_state["avatar_source"] != "custom":
            update_fields["avatar"] = new_google_pic
            update_fields["avatar_source"] = "google"
        user.update(update_fields)

        final_state = resolve_avatar_state(user)
        self.assertEqual(final_state["avatar"], new_google_pic)
        self.assertEqual(final_state["avatar_source"], "google")

    def test_process_and_normalize_avatar_valid_image(self):
        img = Image.new("RGB", (500, 400), color=(255, 128, 0))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        raw_bytes = buf.getvalue()

        normalized = process_and_normalize_avatar(raw_bytes)
        self.assertIsInstance(normalized, bytes)
        self.assertGreater(len(normalized), 0)

        out_img = Image.open(io.BytesIO(normalized))
        self.assertEqual(out_img.format, "JPEG")
        self.assertLessEqual(out_img.width, MAX_PIXEL_DIMENSION)
        self.assertLessEqual(out_img.height, MAX_PIXEL_DIMENSION)

    def test_process_and_normalize_avatar_resizes_large_images(self):
        img = Image.new("RGB", (2400, 1600), color=(10, 20, 30))
        buf = io.BytesIO()
        img.save(buf, format="JPEG")
        raw_bytes = buf.getvalue()

        normalized = process_and_normalize_avatar(raw_bytes)
        out_img = Image.open(io.BytesIO(normalized))
        self.assertLessEqual(out_img.width, MAX_PIXEL_DIMENSION)
        self.assertLessEqual(out_img.height, MAX_PIXEL_DIMENSION)
        self.assertEqual(out_img.width, 1024)
        self.assertIn(out_img.height, (682, 683))

    def test_process_and_normalize_avatar_rejects_decompression_bomb(self):
        # 4200 x 4000 = 16.8 MP > MAX_DECODED_PIXELS (16 MP)
        img = Image.new("RGB", (4200, 4000), color=(0, 0, 0))
        buf = io.BytesIO()
        img.save(buf, format="JPEG")
        raw_bytes = buf.getvalue()

        with self.assertRaises(ValueError) as ctx:
            process_and_normalize_avatar(raw_bytes)
        self.assertIn("Độ phân giải ảnh quá lớn", str(ctx.exception))

    def test_process_and_normalize_avatar_rejects_corrupted_bytes(self):
        fake_bytes = b"this is not an image file at all"
        with self.assertRaises(ValueError) as ctx:
            process_and_normalize_avatar(fake_bytes)
        self.assertIn("File ảnh không hợp lệ", str(ctx.exception))

    def test_process_and_normalize_avatar_rejects_empty_bytes(self):
        with self.assertRaises(ValueError) as ctx:
            process_and_normalize_avatar(b"")
        self.assertIn("File ảnh rỗng", str(ctx.exception))

    def test_process_and_normalize_avatar_rejects_oversized_file(self):
        huge_bytes = b"0" * (MAX_AVATAR_BYTES + 10)
        with self.assertRaises(ValueError) as ctx:
            process_and_normalize_avatar(huge_bytes)
        self.assertIn("vượt quá giới hạn 5 MB", str(ctx.exception))

    def test_destroy_avatar_safeguard_non_avatar_assets(self):
        self.assertFalse(destroy_avatar_sync("saman/stories/story_123"))
        self.assertFalse(destroy_avatar_sync("https://lh3.googleusercontent.com/photo"))
        self.assertFalse(destroy_avatar_sync(""))
        self.assertFalse(destroy_avatar_sync(None))

    def test_local_storage_lifecycle_and_persistence(self):
        # Enable local storage for testing
        os.environ["ALLOW_LOCAL_AVATAR_STORAGE"] = "true"
        os.environ["ENVIRONMENT"] = "development"
        self.assertTrue(is_local_storage_enabled())
        self.assertTrue(is_storage_configured())

        # Generate a small valid image
        img = Image.new("RGB", (200, 200), color=(50, 150, 250))
        buf = io.BytesIO()
        img.save(buf, format="JPEG")
        image_bytes = buf.getvalue()

        user_id = "test_user_persistence_99"
        result = upload_avatar_sync(image_bytes, user_id)

        self.assertEqual(result["storage_type"], "local")
        self.assertTrue(result["public_id"].startswith("local:"))
        filename = result["public_id"][len("local:"):]
        filepath = os.path.join(LOCAL_AVATAR_DIR, filename)

        # 1. Verify file exists on disk
        self.assertTrue(os.path.exists(filepath))
        # 2. Verify bytes on disk match JPEG header
        with open(filepath, "rb") as f:
            disk_bytes = f.read()
        self.assertEqual(disk_bytes[:2], b"\xff\xd8")  # JPEG magic bytes

        # 3. Simulate backend restart: file remains on disk and can be read by a fresh process
        self.assertTrue(os.path.isfile(filepath))

        # 4. Destroy avatar
        deleted = destroy_avatar_sync(result["public_id"])
        self.assertTrue(deleted)
        # 5. File must be gone from disk
        self.assertFalse(os.path.exists(filepath))

    def test_local_storage_blocks_path_traversal(self):
        # Attempt to delete file outside LOCAL_AVATAR_DIR
        self.assertFalse(destroy_avatar_sync("local:../../secret.txt"))

    def test_local_storage_strictly_disabled_in_production(self):
        os.environ["ENVIRONMENT"] = "production"
        os.environ["ALLOW_LOCAL_AVATAR_STORAGE"] = "true"
        self.assertFalse(is_local_storage_enabled())

    def test_normalization_strips_metadata_and_rotates_exif(self):
        image = Image.new("RGB", (40, 80), color=(10, 30, 50))
        exif = Image.Exif(); exif[274] = 6; exif[315] = "fixture-author"
        buf = io.BytesIO()
        image.save(buf, "JPEG", exif=exif, icc_profile=b"fixture-profile")
        normalized = process_and_normalize_avatar(buf.getvalue())
        with Image.open(io.BytesIO(normalized)) as clean:
            self.assertEqual(clean.size, (80, 40))
            self.assertFalse(clean.getexif())
            self.assertNotIn("icc_profile", clean.info)

    def test_unknown_environment_does_not_enable_local_storage(self):
        with patch.dict(os.environ, {"ENVIRONMENT": "staging", "ALLOW_LOCAL_AVATAR_STORAGE": "true"}):
            self.assertFalse(is_local_storage_enabled())

    def test_legacy_unknown_url_remains_active_with_google_metadata(self):
        result = resolve_avatar_state({"avatar": "https://unknown.example/legacy",
                                       "google_avatar": "https://lh3.googleusercontent.com/new"})
        self.assertEqual(result["avatar"], "https://unknown.example/legacy")

    def test_cloudinary_url_configuration_is_parsed(self):
        from backend.services import avatar_service as service
        if not service.HAS_CLOUDINARY:
            self.skipTest("Cloudinary package not installed")
        # Deliberately fake fixture credentials; no external request.
        with patch.dict(os.environ, {"CLOUDINARY_URL": "cloudinary://fixture-key:fixture-value@fixture-cloud"}), \
             patch.object(service.cloudinary, "config") as config:
            service.configure_cloudinary()
            config.assert_called_once_with(cloud_name="fixture-cloud", api_key="fixture-key",
                                           api_secret="fixture-value", secure=True)


if __name__ == "__main__":
    unittest.main()
