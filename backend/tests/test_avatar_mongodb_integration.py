"""Real PyMongo tests. Google verification/storage are explicit fixtures, not live OAuth/cloud."""
import asyncio
import copy
import io
import os
import unittest
from unittest.mock import patch
from PIL import Image
from pymongo import MongoClient
from pymongo.errors import AutoReconnect, WriteError
from fastapi import HTTPException, UploadFile


@unittest.skipUnless(os.getenv("AVATAR_TEST_MONGO_URI"), "isolated MongoDB URI required")
class AvatarMongoTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from backend.routers import auth, user
        cls.auth, cls.user = auth, user
        cls.client = MongoClient(os.environ["AVATAR_TEST_MONGO_URI"], serverSelectionTimeoutMS=2000)
        cls.client.admin.command("ping")
        cls.col = cls.client["avatar_codex_test"]["avatar_race_fixtures"]

    @classmethod
    def tearDownClass(cls):
        cls.client.close()

    def setUp(self):
        self.doc = {"email": "avatar-fixture@example.invalid", "full_name": "Fixture",
                    "avatar": "https://legacy.example/avatar.jpg"}
        self.doc["_id"] = self.col.insert_one(copy.deepcopy(self.doc)).inserted_id
        self.addCleanup(lambda: self.col.delete_one({"_id": self.doc["_id"]}))

    def login(self, initial=None, interleave=None, picture="https://lh3.googleusercontent.com/new"):
        col = self.col
        class InterleavedCollection:
            fired = False
            def find_one(inner, query):
                return col.find_one(query)
            def update_one(inner, query, change, **kwargs):
                if interleave and not inner.fired:
                    inner.fired = True
                    interleave()
                return col.update_one(query, change, **kwargs)
        with patch.object(self.auth, "users_collection", InterleavedCollection()), \
             patch.object(self.auth, "safe_find_one", return_value=initial or self.col.find_one({"_id": self.doc["_id"]})), \
             patch.object(self.auth, "verify_google", return_value={"email": self.doc["email"], "picture": picture}):
            result = self.auth.social_login(self.auth.SocialLoginRequest(provider="google", token="fixture-only"))
        return result["user"], self.col.find_one({"_id": self.doc["_id"]})

    def test_stale_backfill_cannot_replace_explicit_google_choice(self):
        def choose_google():
            self.col.update_one({"_id": self.doc["_id"]}, {"$set": {
                "avatar_source": "google", "avatar": "https://lh3.googleusercontent.com/selected",
                "google_avatar": "https://lh3.googleusercontent.com/selected"}})
        response, stored = self.login(interleave=choose_google)
        self.assertEqual(stored["avatar_source"], "google")
        self.assertEqual(response["avatar"], "https://lh3.googleusercontent.com/new")
        self.assertFalse(stored.get("custom_avatar"))

    def test_explicit_google_is_not_reclassified_from_unknown_active_url(self):
        self.col.update_one({"_id": self.doc["_id"]}, {"$set": {"avatar_source": "google"}})
        response, stored = self.login()
        self.assertEqual(response["avatar_source"], "google")
        self.assertFalse(stored.get("custom_avatar"))

    def test_google_selected_with_retained_custom_updates_everywhere(self):
        self.col.update_one({"_id": self.doc["_id"]}, {"$set": {
            "avatar_source": "google", "custom_avatar": "https://custom.example/old"}})
        response, stored = self.login()
        self.assertEqual(response["avatar"], stored["avatar"])
        self.assertEqual(stored["avatar"], "https://lh3.googleusercontent.com/new")
        self.assertEqual(stored["custom_avatar"], "https://custom.example/old")

    def test_upload_interleaves_with_sync_and_remains_selected(self):
        def upload():
            self.col.update_one({"_id": self.doc["_id"]}, {"$set": {
                "avatar_source": "custom", "custom_avatar": "https://custom.example/new",
                "avatar": "https://custom.example/new"}})
        response, stored = self.login(interleave=upload)
        self.assertEqual(response["avatar"], "https://custom.example/new")
        self.assertEqual(stored["google_avatar"], "https://lh3.googleusercontent.com/new")

    def test_missing_google_picture_preserves_legacy(self):
        response, stored = self.login(picture=None)
        self.assertEqual(response["avatar"], self.doc["avatar"])
        self.assertEqual(stored, self.doc)

    def test_uncertain_write_must_not_destroy_committed_asset(self):
        col = self.col
        class UncertainWrite:
            def update_one(inner, query, change):
                col.update_one(query, change)
                raise AutoReconnect("fixture: reply lost after committed write")
            def find_one(inner, query):
                return col.find_one(query)
        buf = io.BytesIO()
        Image.new("RGB", (12, 12)).save(buf, "PNG")
        asset = {"secure_url": "https://storage.example/unique", "public_id": "saman/avatars/fixture"}
        with patch.object(self.user, "users_collection", UncertainWrite()), \
             patch.object(self.user, "is_storage_configured", return_value=True), \
             patch.object(self.user, "upload_avatar_sync", return_value=asset), \
             patch("backend.services.avatar_service.destroy_avatar_sync") as destroy:
            with self.assertRaises(HTTPException):
                asyncio.run(self.user.upload_avatar(UploadFile(io.BytesIO(buf.getvalue()), filename="avatar.png"), self.doc))
            destroy.assert_not_called()
        self.assertEqual(col.find_one({"_id": self.doc["_id"]})["avatar"], asset["secure_url"])

    def test_legacy_google_tracks_latest_verified_picture(self):
        self.col.update_one({"_id": self.doc["_id"]}, {"$set": {"avatar": "https://lh3.googleusercontent.com/old"}})
        response, stored = self.login()
        self.assertEqual(response["avatar"], "https://lh3.googleusercontent.com/new")
        self.assertEqual(stored["avatar_source"], "google")

    def test_new_google_user_with_and_without_picture(self):
        import uuid
        for picture in (None, "https://lh3.googleusercontent.com/fixture"):
            email = "new-avatar-" + uuid.uuid4().hex + "@example.com"
            self.addCleanup(lambda email=email: self.col.delete_one({"email": email}))
            with patch.object(self.auth, "users_collection", self.col), \
                 patch.object(self.auth, "verify_google", return_value={"email": email, "picture": picture}):
                response = self.auth.social_login(self.auth.SocialLoginRequest(provider="google", token="fixture-only"))["user"]
            stored = self.col.find_one({"email": email})
            self.assertEqual(response["avatar"], picture)
            self.assertEqual(stored["avatar_source"], "google" if picture else "none")

    def test_use_google_retries_when_google_sync_changes_picture(self):
        col = self.col
        col.update_one({"_id": self.doc["_id"]}, {"$set": {
            "google_avatar": "https://lh3.googleusercontent.com/old", "avatar_source": "custom"}})
        class Interleaved:
            fired = False
            def find_one(inner, query):
                return col.find_one(query)
            def update_one(inner, query, changes):
                if not inner.fired:
                    inner.fired = True
                    col.update_one({"_id": self.doc["_id"]}, {"$set": {"google_avatar": "https://lh3.googleusercontent.com/latest"}})
                return col.update_one(query, changes)
        with patch.object(self.user, "users_collection", Interleaved()):
            response = asyncio.run(self.user.use_google_avatar(self.doc))
        stored = col.find_one({"_id": self.doc["_id"]})
        self.assertEqual(stored["avatar"], stored["google_avatar"])
        self.assertEqual(response.avatar, stored["avatar"])

    def test_definitely_rejected_write_cleans_only_new_asset(self):
        col = self.col
        class RejectedWrite:
            def update_one(inner, query, change):
                raise WriteError("fixture: validation rejection", code=121, details={"code": 121})
            def find_one(inner, query):
                return col.find_one(query)
        buf = io.BytesIO(); Image.new("RGB", (12, 12)).save(buf, "PNG")
        asset = {"secure_url": "https://storage.example/rejected", "public_id": "saman/avatars/rejected"}
        with patch.object(self.user, "users_collection", RejectedWrite()), \
             patch.object(self.user, "is_storage_configured", return_value=True), \
             patch.object(self.user, "upload_avatar_sync", return_value=asset), \
             patch("backend.services.avatar_service.destroy_avatar_sync") as destroy:
            with self.assertRaises(HTTPException):
                asyncio.run(self.user.upload_avatar(UploadFile(io.BytesIO(buf.getvalue()), filename="avatar.png"), self.doc))
            destroy.assert_called_once_with(asset["public_id"])
        self.assertEqual(col.find_one({"_id": self.doc["_id"]})["avatar"], self.doc["avatar"])

    def test_cleanup_retains_assets_referenced_by_another_profile(self):
        from backend.services.avatar_service import cleanup_unreferenced_avatar
        public_id, url = "saman/avatars/shared", "https://storage.example/shared"
        self.col.update_one({"_id": self.doc["_id"]}, {"$set": {"custom_avatar_public_id": public_id, "custom_avatar": url}})
        with patch("backend.services.avatar_service.destroy_avatar_sync") as destroy:
            self.assertFalse(cleanup_unreferenced_avatar(self.col, public_id, url))
            destroy.assert_not_called()


if __name__ == "__main__":
    unittest.main()
