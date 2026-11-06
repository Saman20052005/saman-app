"""Explicit isolated JCOM0508 index setup. No application-startup migrations."""
import argparse
from urllib.parse import urlparse
from pymongo import MongoClient


def validate_target(uri, name):
    target=urlparse(uri)
    if target.scheme != "mongodb" or target.hostname not in ("127.0.0.1", "localhost") or target.port != 27048:
        raise ValueError("Dedicated JCOM0508 loopback Mongo27048 required")
    if not name.startswith("saman_jcom0508_test_"):
        raise ValueError("Independent JCOM0508 test DB required")


def setup_indexes(db):
    db.community_posts.create_index([("user_id",1),("request_key",1)],unique=True,
        partialFilterExpression={"request_key":{"$type":"string"}},name="publish_request_unique")


if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--uri',required=True); parser.add_argument('--database',required=True)
    args=parser.parse_args(); validate_target(args.uri,args.database)
    with MongoClient(args.uri,serverSelectionTimeoutMS=2000) as client:
        client.admin.command('ping'); setup_indexes(client[args.database])
