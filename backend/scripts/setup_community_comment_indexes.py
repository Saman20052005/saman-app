"""Explicit local/test-only index setup; never imported for startup side effects."""
import argparse
from urllib.parse import urlparse
from pymongo import MongoClient


def setup_indexes(db):
    db.community_comments.create_index(
        [("user_id", 1), ("request_key", 1)], unique=True, name="comment_request_unique")
    db.community_comments.create_index(
        [("post_id", 1), ("created_at", 1), ("_id", 1)], name="comment_stream")


def validate_target(uri, name):
    target = urlparse(uri)
    if target.scheme != "mongodb" or target.hostname not in ("127.0.0.1", "localhost") or target.port != 27046:
        raise ValueError("Only dedicated JCOM0506 loopback port 27046 is allowed")
    if not name.startswith("saman_jcom0506_test_"):
        raise ValueError("Independent JCOM0506 test database required")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", required=True)
    parser.add_argument("--database", required=True)
    args = parser.parse_args()
    validate_target(args.uri, args.database)
    with MongoClient(args.uri, serverSelectionTimeoutMS=2000) as client:
        client.admin.command("ping")
        setup_indexes(client[args.database])
