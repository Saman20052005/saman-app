# [File: backend/tests/test_avatar_api_integration.py]
import os
import io
import unittest
from PIL import Image
from fastapi.testclient import TestClient

# Configure environment for testing before loading app
os.environ["ENVIRONMENT"] = "development"
os.environ["ALLOW_LOCAL_AVATAR_STORAGE"] = "true"

from backend.main import app
from backend.services.avatar_service import (
    LOCAL_AVATAR_DIR,
    upload_avatar_sync,
    destroy_avatar_sync,
    resolve_avatar_state,
    is_google_avatar_url,
)


class TestAvatarApiIntegration(unittest.TestCase):
    def setUp(self):
        from unittest.mock import patch
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {"ENVIRONMENT": "test", "ALLOW_LOCAL_AVATAR_STORAGE": "true"}).start()
        patch("backend.services.avatar_service.is_cloudinary_configured", return_value=False).start()
        self.client = TestClient(app)
        os.makedirs(LOCAL_AVATAR_DIR, exist_ok=True)

    def test_http_get_static_avatar_endpoint(self):
        # 1. Create a real sample image and upload via local storage
        img = Image.new("RGB", (100, 100), color=(34, 197, 94))
        buf = io.BytesIO()
        img.save(buf, format="JPEG")
        image_bytes = buf.getvalue()

        user_id = "test_athlete_123"
        upload_result = upload_avatar_sync(image_bytes, user_id)
        public_id = upload_result["public_id"]
        filename = public_id[len("local:"):]

        try:
            # 2. HTTP GET to the real registered route
            response = self.client.get(f"/api/static/avatars/{filename}")
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.headers["content-type"], "image/jpeg")
            self.assertEqual(response.content[:2], b"\xff\xd8")  # Valid JPEG binary

            # 3. A fresh TestClient checks the same process/file, NOT a process restart.
            fresh_client = TestClient(app)
            restart_response = fresh_client.get(f"/api/static/avatars/{filename}")
            self.assertEqual(restart_response.status_code, 200)
            self.assertEqual(restart_response.content, response.content)
        finally:
            destroy_avatar_sync(public_id)

    def test_http_get_static_avatar_not_found(self):
        response = self.client.get("/api/static/avatars/non_existent_avatar_9999.jpg")
        self.assertEqual(response.status_code, 404)
        self.assertIn("Avatar image not found", response.json()["detail"])

    def test_dictionary_fixture_google_login_preserves_custom_avatar(self):
        """
        Simulates the MongoDB conditional update sequence in social_login.
        Verifies that an existing custom avatar is NEVER overwritten by Google login.
        """
        db_record = {
            "email": "athlete@test.com",
            "avatar": "https://res.cloudinary.com/saman/custom.jpg",
            "custom_avatar": "https://res.cloudinary.com/saman/custom.jpg",
            "avatar_source": "custom",
            "google_avatar": "https://lh3.googleusercontent.com/old_photo",
        }

        new_google_picture = "https://lh3.googleusercontent.com/new_google_photo"

        # Step 2: update google_avatar
        db_record["google_avatar"] = new_google_picture

        # Step 3: conditional update using the atomic $or condition
        is_or_match = (
            db_record.get("avatar_source") == "google"
            or (
                db_record.get("avatar_source") in [None, "none"]
                and not db_record.get("custom_avatar")
            )
        )
        if is_or_match:
            db_record["avatar"] = new_google_picture
            db_record["avatar_source"] = "google"

        # Verify state from DB record
        resolved = resolve_avatar_state(db_record)
        self.assertEqual(resolved["avatar"], "https://res.cloudinary.com/saman/custom.jpg")
        self.assertEqual(resolved["avatar_source"], "custom")
        self.assertEqual(resolved["google_avatar"], new_google_picture)
        self.assertTrue(resolved["can_use_google_avatar"])

    def test_google_sync_updates_active_avatar_when_source_is_google_even_with_stored_custom(self):
        """
        CRITICAL REGRESSION TEST:
        Scenario:
        1. User previously uploaded custom avatar ('https://custom.jpg') -> avatar_source: 'custom'
        2. User clicked 'Dùng ảnh Google' -> avatar_source becomes 'google', avatar becomes old Google pic.
           Notice: 'custom_avatar' is STILL preserved in DB!
        3. User changes their Google account picture to 'new_google_photo'.
        4. User logs in with Google again.
        Requirement:
        Active avatar MUST be updated to 'new_google_photo' because the chosen source is 'google',
        and 'custom_avatar' MUST remain stored in DB for future switching.
        """
        db_record = {
            "email": "athlete_switch@test.com",
            "avatar": "https://lh3.googleusercontent.com/old_google_photo",
            "custom_avatar": "https://res.cloudinary.com/saman/stored_custom.jpg",
            "avatar_source": "google",
            "google_avatar": "https://lh3.googleusercontent.com/old_google_photo",
        }

        new_google_picture = "https://lh3.googleusercontent.com/new_google_photo_v2"

        # Step 2: Always update google_avatar
        db_record["google_avatar"] = new_google_picture

        # Step 3: MongoDB atomic update with $or condition:
        is_or_match = (
            db_record.get("avatar_source") == "google"
            or (
                db_record.get("avatar_source") in [None, "none"]
                and not db_record.get("custom_avatar")
            )
        )
        if is_or_match:
            db_record["avatar"] = new_google_picture
            db_record["avatar_source"] = "google"

        # Verify state
        resolved = resolve_avatar_state(db_record)
        # Active avatar MUST update to new Google photo!
        self.assertEqual(resolved["avatar"], new_google_picture)
        self.assertEqual(resolved["avatar_source"], "google")
        self.assertEqual(resolved["google_avatar"], new_google_picture)
        # Custom avatar MUST be preserved on the record!
        self.assertEqual(db_record["custom_avatar"], "https://res.cloudinary.com/saman/stored_custom.jpg")
        # Since active avatar is now Google, can_use_google_avatar is False
        self.assertFalse(resolved["can_use_google_avatar"])

    def test_dictionary_fixture_google_login_backfills_legacy_custom_avatar(self):
        """
        Simulates legacy user who only has 'avatar' pointing to an external non-Google CDN.
        Verifies that Google login backfills custom_avatar and does NOT overwrite it.
        """
        db_record = {
            "email": "legacy@test.com",
            "avatar": "https://res.cloudinary.com/saman/legacy_uploaded.jpg",
        }

        new_google_picture = "https://lh3.googleusercontent.com/google_photo"

        # Step 1: Backfill legacy custom avatar if avatar is not from Google
        legacy_avatar = db_record.get("avatar")
        if legacy_avatar and not is_google_avatar_url(legacy_avatar) and not db_record.get("custom_avatar"):
            db_record["custom_avatar"] = legacy_avatar
            db_record["avatar_source"] = "custom"

        # Step 2: update google_avatar
        db_record["google_avatar"] = new_google_picture

        # Step 3: conditional update
        is_or_match = (
            db_record.get("avatar_source") == "google"
            or (
                db_record.get("avatar_source") in [None, "none"]
                and not db_record.get("custom_avatar")
            )
        )
        if is_or_match:
            db_record["avatar"] = new_google_picture
            db_record["avatar_source"] = "google"

        resolved = resolve_avatar_state(db_record)
        # Must preserve legacy uploaded avatar
        self.assertEqual(resolved["avatar"], "https://res.cloudinary.com/saman/legacy_uploaded.jpg")
        self.assertEqual(resolved["avatar_source"], "custom")
        self.assertTrue(resolved["can_use_google_avatar"])


if __name__ == "__main__":
    unittest.main()
