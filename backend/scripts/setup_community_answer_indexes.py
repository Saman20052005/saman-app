"""Explicit JCOM0507 isolated test index setup, never automatic startup migration."""
import argparse
from urllib.parse import urlparse
from pymongo import MongoClient


def validate_target(uri, name):
    target = urlparse(uri)
    if target.scheme != "mongodb" or target.hostname not in ("127.0.0.1", "localhost") or target.port != 27046:
        raise ValueError("Dedicated loopback Mongo27046 required")
    if not name.startswith("saman_jcom0507_test_"):
        raise ValueError("Independent JCOM0507 test database required")


def setup_indexes(db):
    db.community_answers.create_index([("user_id", 1), ("request_key", 1)], unique=True, name="answer_request_unique",
        partialFilterExpression={"request_key": {"$type": "string"}})
    db.community_answers.create_index([("question_id", 1), ("created_at", 1), ("_id", 1)], name="answer_stream")
    db.community_answer_votes.create_index([("user_id", 1), ("answer_id", 1)], unique=True, name="answer_vote_unique")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--uri", required=True); parser.add_argument("--database", required=True)
    args = parser.parse_args(); validate_target(args.uri, args.database)
    with MongoClient(args.uri, serverSelectionTimeoutMS=2000) as client:
        client.admin.command("ping"); setup_indexes(client[args.database])
