"""Opt-in real backend process + local MongoDB + HTTP. No OAuth/auth overrides."""
import io
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import unittest
import uuid
from urllib.parse import urlparse

import requests
from PIL import Image
from pymongo import MongoClient


@unittest.skipUnless(os.getenv("AVATAR_TEST_MONGO_URI"), "isolated local MongoDB required")
class AvatarLiveTests(unittest.TestCase):
    def test_http_upload_switch_and_restart_persistence(self):
        uri = os.environ["AVATAR_TEST_MONGO_URI"]
        self.assertIn(urlparse(uri).hostname, ("127.0.0.1", "localhost"))
        evidence = Path(os.environ["AVATAR_EVIDENCE_DIR"])
        assets = evidence / ("live-assets-" + uuid.uuid4().hex[:8])
        assets.mkdir()
        root = Path(__file__).resolve().parents[2]
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        base = f"http://127.0.0.1:{port}"
        env = dict(os.environ, PYTHON_DOTENV_DISABLED="1", MONGO_URI=uri,
                   DB_NAME="avatar_codex_test", ENVIRONMENT="test",
                   ALLOW_LOCAL_AVATAR_STORAGE="true", AVATAR_LOCAL_DIR=str(assets),
                   AVATAR_BASE_URL=base, CLOUDINARY_URL="", CLOUDINARY_CLOUD_NAME="",
                   CLOUDINARY_API_KEY="", CLOUDINARY_API_SECRET="", PYTHONIOENCODING="utf-8")
        client = MongoClient(uri, serverSelectionTimeoutMS=2000)
        self.addCleanup(client.close)
        col = client["avatar_codex_test"]["users"]
        from backend.auth_utils import hash_password
        email = f"avatar-{uuid.uuid4().hex}@example.com"
        fixture = {"email": email, "full_name": "Avatar HTTP Fixture",
                   "password": hash_password("fixture-password"),
                   "google_avatar": "https://lh3.googleusercontent.com/fixture",
                   "avatar_source": "google", "avatar": "https://lh3.googleusercontent.com/fixture"}
        owner = col.insert_one(fixture).inserted_id
        self.addCleanup(lambda: col.delete_one({"_id": owner}))
        process = None
        log = (evidence / "live_backend_process.log").open("ab")
        self.addCleanup(log.close)

        def start():
            proc = subprocess.Popen([sys.executable, "-m", "uvicorn", "backend.main:app",
                "--host", "127.0.0.1", "--port", str(port), "--lifespan", "off"],
                cwd=root, env=env, stdout=log, stderr=log,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            for _ in range(100):
                if proc.poll() is not None:
                    self.fail("Backend exited: see live_backend_process.log")
                try:
                    if requests.get(base + "/health", timeout=1).status_code == 200:
                        return proc
                except requests.ConnectionError:
                    pass
                time.sleep(0.1)
            proc.terminate(); proc.wait(timeout=10)
            self.fail("Backend startup timeout")

        def stop(proc):
            proc.terminate(); proc.wait(timeout=15)

        try:
            process = start()
            login = requests.post(base + "/api/auth/login", json={"email": email, "password": "fixture-password"}, timeout=5)
            self.assertEqual(login.status_code, 200)
            headers = {"Authorization": "Bearer " + login.json()["access_token"]}
            image = io.BytesIO()
            Image.new("RGB", (80, 160), (20, 90, 180)).save(image, "PNG")
            upload = requests.post(base + "/api/user/avatar/upload", headers=headers,
                files={"file": ("portrait.png", image.getvalue(), "image/png")}, timeout=10)
            self.assertEqual(upload.status_code, 200, upload.text)
            avatar = upload.json()["avatar"]
            profile = requests.get(base + "/api/user/profile", headers=headers, timeout=5).json()
            self.assertEqual(profile["avatar"], avatar)
            self.assertEqual(profile["avatar_source"], "custom")
            photo = requests.get(avatar, timeout=5)
            self.assertEqual(photo.status_code, 200)
            self.assertEqual(photo.content[:2], b"\xff\xd8")
            with Image.open(io.BytesIO(photo.content)) as normalized:
                self.assertEqual(normalized.size, (80, 160))
            # Failures must preserve the previous valid avatar.
            invalid = requests.post(base + "/api/user/avatar/upload", headers=headers,
                files={"file": ("bad.jpg", b"not-image", "image/jpeg")}, timeout=5)
            self.assertEqual(invalid.status_code, 422)
            self.assertEqual(col.find_one({"_id": owner})["avatar"], avatar)
            switch = requests.post(base + "/api/user/avatar/use-google", headers=headers, timeout=5)
            self.assertEqual(switch.status_code, 200)
            self.assertEqual(switch.json()["avatar_source"], "google")
            self.assertEqual(col.find_one({"_id": owner})["custom_avatar"], avatar)
            self.assertEqual(requests.get(avatar, timeout=5).status_code, 200)
            first_pid = process.pid
            stop(process); process = start()
            self.assertNotEqual(process.pid, first_pid)
            restored = requests.get(base + "/api/user/profile", headers=headers, timeout=5).json()
            self.assertEqual(restored["avatar"], fixture["google_avatar"])
            self.assertEqual(restored["avatar_source"], "google")
            self.assertEqual(requests.get(avatar, timeout=5).content, photo.content)
            print("HTTP upload/profile/image/switch/rejected-file + backend PID restart PASS; local MongoDB/PyMongo; Google URL is a fixture")
        finally:
            if process is not None and process.poll() is None:
                stop(process)
            # Only this run's generated images in its dedicated directory.
            for asset in assets.glob("avatar_*.jpg"):
                asset.unlink()


if __name__ == "__main__":
    unittest.main()
