"""Explicit JCOM0509 isolated index setup; no startup migration."""
from urllib.parse import urlparse
from backend.scripts.setup_community_publish_indexes import setup_indexes

def validate_target(uri, name):
    value = urlparse(uri)
    if value.scheme != "mongodb" or value.hostname not in ("localhost", "127.0.0.1") or value.port != 27048 or not name.startswith("saman_jcom0509_test_"):
        raise ValueError("Dedicated JCOM0509 loopback test database required")
