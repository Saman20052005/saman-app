"""
Unit and Integration Tests for Saman Community Wave 4 Social Core API.
Covers:
- MongoDB indexes & TTL index definition (ensure_community_indexes)
- Social Settings (GET/PATCH, extra=forbid, who_can_comment enforcement, hide_like_counts)
- Block (2-way isolation across feed/discover/detail/comments/answers/profile/follow + auto-unfollow)
- Mute (1-way isolation in feed/discover/stories)
- Content Reporting (idempotency, validation, target verification)
- Stories 24h (TTL expiry, photo/text validation, followers_only privacy, grouping, view count, owner-only delete)
- Post Share (share_count increment, audience & block enforcement)
"""

from datetime import datetime, timedelta, timezone
import re
import unittest
from unittest.mock import patch
from bson import ObjectId
from fastapi.testclient import TestClient
import jwt
from pymongo.errors import DuplicateKeyError

from backend.app.database_community import ensure_community_indexes
from backend.main import app
from backend.routers.community import JWT_ALGORITHM, JWT_SECRET


def _get_nested(doc, dotted_key):
    cur = doc
    for part in dotted_key.split("."):
        if isinstance(cur, dict):
            if part not in cur:
                return None, False
            cur = cur[part]
        elif isinstance(cur, list) and part.isdigit():
            idx = int(part)
            if idx >= len(cur):
                return None, False
            cur = cur[idx]
        else:
            return None, False
    return cur, True


def _norm_dt(v):
    if isinstance(v, datetime):
        return v.replace(tzinfo=timezone.utc) if v.tzinfo is None else v.astimezone(timezone.utc)
    return v


def _match_condition(val, exists, cond):
    if isinstance(cond, dict) and any(k.startswith("$") for k in cond):
        for op, expected in cond.items():
            if op == "$exists":
                if bool(exists) != bool(expected):
                    return False
            elif op == "$ne":
                if exists and val == expected:
                    return False
            elif op == "$in":
                if not exists:
                    if None not in expected:
                        return False
                elif val not in expected and str(val) not in [str(x) for x in expected if x is not None]:
                    return False
            elif op == "$nin":
                if exists and (val in expected or str(val) in [str(x) for x in expected]):
                    return False
            elif op == "$gt":
                if not exists or val is None or _norm_dt(val) <= _norm_dt(expected):
                    return False
            elif op == "$lt":
                if not exists or val is None or _norm_dt(val) >= _norm_dt(expected):
                    return False
            elif op == "$regex":
                flags = re.IGNORECASE if "i" in str(cond.get("$options", "")) else 0
                if not exists or not isinstance(val, str) or re.search(expected, val, flags) is None:
                    return False
            elif op == "$options":
                continue
        return True
    if not exists:
        return cond is None
    if isinstance(val, ObjectId) or isinstance(cond, ObjectId):
        return str(val) == str(cond)
    return val == cond


def _match_query(doc, query):
    if not query:
        return True
    for k, v in query.items():
        if k == "$and":
            if not all(_match_query(doc, sub) for sub in v):
                return False
        elif k == "$or":
            if not any(_match_query(doc, sub) for sub in v):
                return False
        else:
            val, exists = _get_nested(doc, k)
            if not _match_condition(val, exists, v):
                return False
    return True


class FakeCursor:
    def __init__(self, docs):
        self._docs = list(docs)

    def sort(self, sort_spec, direction=None):
        if isinstance(sort_spec, str):
            sort_spec = [(sort_spec, direction or 1)]
        for field, order in reversed(sort_spec):
            def _key(d, f=field):
                val, _ = _get_nested(d, f)
                if isinstance(val, datetime):
                    return (0, _norm_dt(val).timestamp())
                if isinstance(val, ObjectId):
                    return (0, str(val))
                if val is None:
                    return (1, "")
                return (0, val)
            self._docs.sort(key=_key, reverse=(order < 0))
        return self

    def limit(self, n):
        self._docs = self._docs[:n]
        return self

    def __iter__(self):
        return iter(self._docs)


class FakeCollection:
    def __init__(self, name):
        self.name = name
        self.docs = []
        self._indexes = {}

    def create_index(self, keys, name=None, unique=False, **kwargs):
        idx_name = name or "_".join(f"{k}_{d}" for k, d in keys)
        info = {"key": list(keys), "unique": bool(unique), **kwargs}
        self._indexes[idx_name] = info
        return idx_name

    def index_information(self):
        return dict(self._indexes)

    def _check_unique(self, candidate, skip_oid=None):
        for idx in self._indexes.values():
            if not idx.get("unique"):
                continue
            pfe = idx.get("partialFilterExpression")
            if pfe:
                skip = False
                for pk, pcond in pfe.items():
                    if isinstance(pcond, dict) and pcond.get("$type") == "string":
                        if not isinstance(candidate.get(pk), str):
                            skip = True
                            break
                if skip:
                    continue
            key_fields = [k for k, _ in idx["key"]]
            cand_tuple = tuple(_get_nested(candidate, f)[0] for f in key_fields)
            for existing in self.docs:
                if skip_oid is not None and existing.get("_id") == skip_oid:
                    continue
                if pfe:
                    es = False
                    for pk, pcond in pfe.items():
                        if isinstance(pcond, dict) and pcond.get("$type") == "string":
                            if not isinstance(existing.get(pk), str):
                                es = True
                                break
                    if es:
                        continue
                ex_tuple = tuple(_get_nested(existing, f)[0] for f in key_fields)
                if cand_tuple == ex_tuple:
                    raise DuplicateKeyError(f"Duplicate key on {self.name}: {key_fields}")

    def insert_one(self, doc):
        rec = dict(doc)
        if "_id" not in rec:
            rec["_id"] = ObjectId()
        self._check_unique(rec)
        self.docs.append(rec)
        return type("InsertResult", (), {"inserted_id": rec["_id"]})()

    def find_one(self, query=None):
        for d in self.docs:
            if _match_query(d, query or {}):
                return dict(d)
        return None

    def find(self, query=None, projection=None):
        matched = [dict(d) for d in self.docs if _match_query(d, query or {})]
        return FakeCursor(matched)

    def count_documents(self, query=None):
        return sum(1 for d in self.docs if _match_query(d, query or {}))

    def update_one(self, query, update, upsert=False):
        for idx, d in enumerate(self.docs):
            if _match_query(d, query):
                updated = dict(d)
                for k, v in (update.get("$set") or {}).items():
                    updated[k] = v
                for k, v in (update.get("$addToSet") or {}).items():
                    arr = list(updated.get(k) or [])
                    if v not in arr:
                        arr.append(v)
                    updated[k] = arr
                for k, v in (update.get("$pull") or {}).items():
                    arr = [x for x in (updated.get(k) or []) if x != v]
                    updated[k] = arr
                self._check_unique(updated, skip_oid=d.get("_id"))
                self.docs[idx] = updated
                return type("UpdateResult", (), {"matched_count": 1, "modified_count": 1})()
        if upsert:
            rec = {}
            for k, v in query.items():
                if not k.startswith("$"):
                    rec[k] = v
            for k, v in (update.get("$setOnInsert") or {}).items():
                rec[k] = v
            for k, v in (update.get("$set") or {}).items():
                rec[k] = v
            if "_id" not in rec:
                rec["_id"] = ObjectId()
            self._check_unique(rec)
            self.docs.append(rec)
            return type("UpdateResult", (), {"matched_count": 0, "modified_count": 0, "upserted_id": rec["_id"]})()
        return type("UpdateResult", (), {"matched_count": 0, "modified_count": 0})()

    def delete_one(self, query):
        for idx, d in enumerate(self.docs):
            if _match_query(d, query):
                self.docs.pop(idx)
                return type("DeleteResult", (), {"deleted_count": 1})()
        return type("DeleteResult", (), {"deleted_count": 0})()

    def delete_many(self, query):
        kept = []
        deleted = 0
        for d in self.docs:
            if _match_query(d, query):
                deleted += 1
            else:
                kept.append(d)
        self.docs = kept
        return type("DeleteResult", (), {"deleted_count": deleted})()

    def aggregate(self, pipeline):
        docs = [dict(d) for d in self.docs]
        for stage in pipeline:
            if "$match" in stage:
                docs = [d for d in docs if _match_query(d, stage["$match"])]
            elif "$group" in stage:
                spec = stage["$group"]
                id_expr = spec["_id"]
                field = id_expr[1:] if isinstance(id_expr, str) and id_expr.startswith("$") else None
                buckets = {}
                for d in docs:
                    k = _get_nested(d, field)[0] if field else id_expr
                    buckets[k] = buckets.get(k, 0) + 1
                docs = [{"_id": k, "count": v} for k, v in buckets.items()]
        return docs


class FakeDB:
    def __init__(self):
        self._cols = {}

    def __getitem__(self, name):
        if name not in self._cols:
            self._cols[name] = FakeCollection(name)
        return self._cols[name]


class TestCommunityWave4CoreApi(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.fake_db = FakeDB()
        self.created_indexes = ensure_community_indexes(self.fake_db)

        self.user_a_id = "674000000000000000000001"
        self.user_b_id = "674000000000000000000002"
        self.user_c_id = "674000000000000000000003"

        self.fake_db["users"].insert_one({
            "_id": self.user_a_id,
            "id": self.user_a_id,
            "email": "user_a@saman.test",
            "name": "Athlete A",
            "title": "Runner",
            "hashed_password": "secret_hash_a",
        })
        self.fake_db["users"].insert_one({
            "_id": self.user_b_id,
            "id": self.user_b_id,
            "email": "user_b@saman.test",
            "name": "Coach B",
            "title": "Strength Coach",
            "is_verified": True,
            "hashed_password": "secret_hash_b",
        })
        self.fake_db["users"].insert_one({
            "_id": self.user_c_id,
            "id": self.user_c_id,
            "email": "user_c@saman.test",
            "name": "Nutritionist C",
            "title": "Nutritionist",
            "hashed_password": "secret_hash_c",
        })

        now = datetime.now(timezone.utc)
        self.post_a_id = "post_a_public"
        self.post_b_id = "post_b_public"
        self.post_b_private_id = "post_b_private"
        self.post_c_id = "post_c_public"
        self.qa_c_id = "qa_c_public"

        self.fake_db["community_posts"].insert_one({
            "_id": ObjectId("674100000000000000000001"),
            "id": self.post_a_id,
            "type": "photo",
            "author_id": self.user_a_id,
            "author": {"id": self.user_a_id, "name": "Athlete A"},
            "caption": "Morning run 10km",
            "photo_urls": ["https://example.com/a1.jpg"],
            "topic": "#TậpLuyện",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "allow_comments": True,
            "like_count": 7,
            "created_at": now - timedelta(minutes=30),
        })
        self.fake_db["community_posts"].insert_one({
            "_id": ObjectId("674100000000000000000002"),
            "id": self.post_b_id,
            "type": "photo",
            "author_id": self.user_b_id,
            "author": {"id": self.user_b_id, "name": "Coach B"},
            "caption": "Bench press form tips",
            "photo_urls": ["https://example.com/b1.jpg"],
            "topic": "#TậpLuyện",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "allow_comments": True,
            "like_count": 12,
            "created_at": now - timedelta(minutes=20),
        })
        self.fake_db["community_posts"].insert_one({
            "_id": ObjectId("674100000000000000000003"),
            "id": self.post_b_private_id,
            "type": "photo",
            "author_id": self.user_b_id,
            "author": {"id": self.user_b_id, "name": "Coach B"},
            "caption": "Private coach notes",
            "photo_urls": ["https://example.com/b_priv.jpg"],
            "topic": "#KỷLuật",
            "privacy": "private",
            "status": "published",
            "is_deleted": False,
            "allow_comments": True,
            "like_count": 0,
            "created_at": now - timedelta(minutes=15),
        })
        self.fake_db["community_posts"].insert_one({
            "_id": ObjectId("674100000000000000000004"),
            "id": self.post_c_id,
            "type": "photo",
            "author_id": self.user_c_id,
            "author": {"id": self.user_c_id, "name": "Nutritionist C"},
            "caption": "High protein lunch bowl",
            "photo_urls": ["https://example.com/c1.jpg"],
            "topic": "#BữaĂn",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "allow_comments": True,
            "like_count": 3,
            "created_at": now - timedelta(minutes=10),
        })
        self.fake_db["community_posts"].insert_one({
            "_id": ObjectId("674100000000000000000005"),
            "id": self.qa_c_id,
            "type": "qa",
            "author_id": self.user_c_id,
            "author": {"id": self.user_c_id, "name": "Nutritionist C"},
            "caption": "",
            "qa_info": {"question": "Best recovery meal?", "category_tag": "HỎI ĐÁP • DINH DƯỠNG"},
            "topic": "Dinh dưỡng",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "allow_comments": True,
            "created_at": now - timedelta(minutes=5),
        })

        self.headers_a = self._auth_headers(self.user_a_id, "user_a@saman.test", "Athlete A")
        self.headers_b = self._auth_headers(self.user_b_id, "user_b@saman.test", "Coach B")
        self.headers_c = self._auth_headers(self.user_c_id, "user_c@saman.test", "Nutritionist C")

    def _auth_headers(self, uid, email, name):
        token = jwt.encode(
            {"sub": uid, "user_id": uid, "email": email, "name": name},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )
        return {"Authorization": f"Bearer {token}"}

    # 1. INDEXES & TTL
    def test_ensure_community_indexes_creates_all_wave4_indexes_and_ttl(self):
        self.assertIn("idx_user_settings_unique", self.fake_db["community_user_settings"].index_information())
        self.assertTrue(self.fake_db["community_user_settings"].index_information()["idx_user_settings_unique"]["unique"])

        block_idxs = self.fake_db["community_blocks"].index_information()
        self.assertIn("idx_block_unique", block_idxs)
        self.assertTrue(block_idxs["idx_block_unique"]["unique"])
        self.assertIn("idx_blocked_reverse", block_idxs)

        mute_idxs = self.fake_db["community_mutes"].index_information()
        self.assertIn("idx_mute_unique", mute_idxs)
        self.assertTrue(mute_idxs["idx_mute_unique"]["unique"])

        report_idxs = self.fake_db["community_reports"].index_information()
        self.assertIn("idx_report_unique", report_idxs)
        self.assertTrue(report_idxs["idx_report_unique"]["unique"])

        story_idxs = self.fake_db["community_stories"].index_information()
        self.assertIn("idx_stories_ttl_expires", story_idxs)
        self.assertEqual(story_idxs["idx_stories_ttl_expires"]["key"], [("expires_at", 1)])
        self.assertEqual(story_idxs["idx_stories_ttl_expires"]["expireAfterSeconds"], 0)
        self.assertIn("idx_stories_user_created", story_idxs)

        view_idxs = self.fake_db["community_story_views"].index_information()
        self.assertIn("idx_story_view_unique", view_idxs)
        self.assertTrue(view_idxs["idx_story_view_unique"]["unique"])

        share_idxs = self.fake_db["community_post_shares"].index_information()
        self.assertIn("idx_post_shares_lookup", share_idxs)

    # 2. SETTINGS + WHO_CAN_COMMENT + HIDE_LIKE_COUNTS
    def test_settings_get_defaults_patch_and_validation(self):
        with patch("backend.routers.community.db", self.fake_db):
            res_default = self.client.get("/api/community/settings", headers=self.headers_a)
            self.assertEqual(res_default.status_code, 200)
            self.assertEqual(res_default.json(), {
                "is_private_account": False,
                "who_can_dm": "everyone",
                "who_can_comment": "everyone",
                "hide_like_counts": False,
                "show_activity_status": True,
                "muted_keywords": [],
            })

            res_patch = self.client.patch(
                "/api/community/settings",
                headers=self.headers_a,
                json={
                    "is_private_account": True,
                    "who_can_dm": "followers",
                    "who_can_comment": "nobody",
                    "hide_like_counts": True,
                    "show_activity_status": False,
                    "muted_keywords": ["spoiler", "spam", "Spoiler"],
                },
            )
            self.assertEqual(res_patch.status_code, 200)
            patched = res_patch.json()
            self.assertTrue(patched["is_private_account"])
            self.assertEqual(patched["who_can_dm"], "followers")
            self.assertEqual(patched["who_can_comment"], "nobody")
            self.assertTrue(patched["hide_like_counts"])
            self.assertFalse(patched["show_activity_status"])
            self.assertEqual(patched["muted_keywords"], ["spoiler", "spam"])

            # Verify persisted on GET
            res_get2 = self.client.get("/api/community/settings", headers=self.headers_a)
            self.assertEqual(res_get2.json(), patched)

            # Extra field rejected (extra="forbid")
            res_extra = self.client.patch(
                "/api/community/settings",
                headers=self.headers_a,
                json={"unknown_flag": True},
            )
            self.assertEqual(res_extra.status_code, 422)

            # More than 20 muted keywords rejected
            res_too_many = self.client.patch(
                "/api/community/settings",
                headers=self.headers_a,
                json={"muted_keywords": [f"kw{i}" for i in range(21)]},
            )
            self.assertEqual(res_too_many.status_code, 422)

    def test_who_can_comment_enforcement(self):
        with patch("backend.routers.community.db", self.fake_db):
            # B sets who_can_comment = nobody
            self.assertEqual(
                self.client.patch(
                    "/api/community/settings",
                    headers=self.headers_b,
                    json={"who_can_comment": "nobody"},
                ).status_code,
                200,
            )
            # A cannot comment on B's post -> 403
            res_nobody = self.client.post(
                f"/api/community/posts/{self.post_b_id}/comments",
                headers={**self.headers_a, "X-Idempotency-Key": "cmt_key_nobody_0001"},
                json={"content": "Nice form!"},
            )
            self.assertEqual(res_nobody.status_code, 403)

            # B can still comment on own post
            res_self = self.client.post(
                f"/api/community/posts/{self.post_b_id}/comments",
                headers={**self.headers_b, "X-Idempotency-Key": "cmt_key_self_00001"},
                json={"content": "Author update!"},
            )
            self.assertEqual(res_self.status_code, 200)

            # B sets who_can_comment = followers
            self.client.patch(
                "/api/community/settings",
                headers=self.headers_b,
                json={"who_can_comment": "followers"},
            )
            # A is not following B -> 403
            res_non_follower = self.client.post(
                f"/api/community/posts/{self.post_b_id}/comments",
                headers={**self.headers_a, "X-Idempotency-Key": "cmt_key_nonfol_0001"},
                json={"content": "Can I comment?"},
            )
            self.assertEqual(res_non_follower.status_code, 403)

            # A follows B -> now commenting succeeds
            self.assertEqual(
                self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=self.headers_a).status_code,
                200,
            )
            res_follower = self.client.post(
                f"/api/community/posts/{self.post_b_id}/comments",
                headers={**self.headers_a, "X-Idempotency-Key": "cmt_key_fol_000001"},
                json={"content": "Following now, great tips!"},
            )
            self.assertEqual(res_follower.status_code, 200)

    def test_hide_like_counts_hides_for_others_but_shows_for_author(self):
        with patch("backend.routers.community.db", self.fake_db):
            # B enables hide_like_counts
            self.assertEqual(
                self.client.patch(
                    "/api/community/settings",
                    headers=self.headers_b,
                    json={"hide_like_counts": True},
                ).status_code,
                200,
            )
            # Like post B as A so authoritative count > 0
            self.assertEqual(
                self.client.put(f"/api/community/posts/{self.post_b_id}/like", headers=self.headers_a).status_code,
                200,
            )

            # Other user (A) sees like_count=0 and is_like_count_hidden=True in Detail & Feed
            det_a = self.client.get(f"/api/community/posts/{self.post_b_id}", headers=self.headers_a).json()
            self.assertEqual(det_a["like_count"], 0)
            self.assertTrue(det_a["is_like_count_hidden"])

            feed_a = self.client.get("/api/community/feed?tab=for_you", headers=self.headers_a).json()
            post_b_in_feed = next(p for p in feed_a["items"] if p["id"] == self.post_b_id)
            self.assertEqual(post_b_in_feed["like_count"], 0)
            self.assertTrue(post_b_in_feed["is_like_count_hidden"])

            # Author (B) still sees real like_count and is_like_count_hidden=False
            det_b = self.client.get(f"/api/community/posts/{self.post_b_id}", headers=self.headers_b).json()
            self.assertEqual(det_b["like_count"], 1)
            self.assertFalse(det_b["is_like_count_hidden"])

            feed_b = self.client.get("/api/community/feed?tab=for_you", headers=self.headers_b).json()
            post_b_own_feed = next(p for p in feed_b["items"] if p["id"] == self.post_b_id)
            self.assertEqual(post_b_own_feed["like_count"], 1)
            self.assertFalse(post_b_own_feed["is_like_count_hidden"])

    # 3. BLOCK (2-WAY), MUTE (1-WAY), REPORTING
    def test_block_two_way_removes_follows_and_filters_everywhere(self):
        with patch("backend.routers.community.db", self.fake_db):
            # Setup mutual follows A <-> B
            self.assertEqual(
                self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=self.headers_a).status_code,
                200,
            )
            self.assertEqual(
                self.client.put(f"/api/community/authors/{self.user_a_id}/follow", headers=self.headers_b).status_code,
                200,
            )

            # Both A and B comment on C's post and answer C's question
            self.assertEqual(
                self.client.post(
                    f"/api/community/posts/{self.post_c_id}/comments",
                    headers={**self.headers_a, "X-Idempotency-Key": "cmt_a_on_c_0000001"},
                    json={"content": "Comment from A"},
                ).status_code,
                200,
            )
            self.assertEqual(
                self.client.post(
                    f"/api/community/posts/{self.post_c_id}/comments",
                    headers={**self.headers_b, "X-Idempotency-Key": "cmt_b_on_c_0000001"},
                    json={"content": "Comment from B"},
                ).status_code,
                200,
            )
            self.assertEqual(
                self.client.post(
                    f"/api/community/questions/{self.qa_c_id}/answers",
                    headers={**self.headers_a, "X-Idempotency-Key": "ans_a_on_c_0000001"},
                    json={"content": "Answer from A"},
                ).status_code,
                200,
            )
            self.assertEqual(
                self.client.post(
                    f"/api/community/questions/{self.qa_c_id}/answers",
                    headers={**self.headers_b, "X-Idempotency-Key": "ans_b_on_c_0000001"},
                    json={"content": "Answer from B"},
                ).status_code,
                200,
            )

            # Both create stories
            self.assertEqual(
                self.client.post(
                    "/api/community/stories",
                    headers=self.headers_a,
                    json={"media_type": "text", "caption": "Story from A"},
                ).status_code,
                200,
            )
            self.assertEqual(
                self.client.post(
                    "/api/community/stories",
                    headers=self.headers_b,
                    json={"media_type": "text", "caption": "Story from B"},
                ).status_code,
                200,
            )

            # Self-block rejected (400)
            self.assertEqual(
                self.client.put(f"/api/community/users/{self.user_a_id}/block", headers=self.headers_a).status_code,
                400,
            )

            # A blocks B (idempotent PUT)
            res_blk = self.client.put(f"/api/community/users/{self.user_b_id}/block", headers=self.headers_a)
            self.assertEqual(res_blk.status_code, 200)
            self.assertEqual(res_blk.json(), {"target_user_id": self.user_b_id, "is_blocked": True})
            res_blk_dup = self.client.put(f"/api/community/users/{self.user_b_id}/block", headers=self.headers_a)
            self.assertEqual(res_blk_dup.status_code, 200)

            # Both follow directions removed automatically
            self.assertEqual(self.fake_db["community_follows"].count_documents({}), 0)

            # Neither can follow the other -> 403
            self.assertEqual(
                self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=self.headers_a).status_code,
                403,
            )
            self.assertEqual(
                self.client.put(f"/api/community/authors/{self.user_a_id}/follow", headers=self.headers_b).status_code,
                403,
            )

            # Feed isolation (2-way)
            feed_a_ids = [p["id"] for p in self.client.get("/api/community/feed", headers=self.headers_a).json()["items"]]
            self.assertNotIn(self.post_b_id, feed_a_ids)
            self.assertIn(self.post_c_id, feed_a_ids)

            feed_b_ids = [p["id"] for p in self.client.get("/api/community/feed", headers=self.headers_b).json()["items"]]
            self.assertNotIn(self.post_a_id, feed_b_ids)
            self.assertIn(self.post_c_id, feed_b_ids)

            # Discover isolation (2-way: grid + creators)
            disc_a = self.client.get("/api/community/discover", headers=self.headers_a).json()
            self.assertNotIn(self.post_b_id, [g["post_id"] for g in disc_a["grid_items"]])
            self.assertNotIn(self.user_b_id, [c["id"] for c in disc_a["recommended_creators"]])

            disc_b = self.client.get("/api/community/discover", headers=self.headers_b).json()
            self.assertNotIn(self.post_a_id, [g["post_id"] for g in disc_b["grid_items"]])
            self.assertNotIn(self.user_a_id, [c["id"] for c in disc_b["recommended_creators"]])

            # Post detail 404 (2-way)
            self.assertEqual(self.client.get(f"/api/community/posts/{self.post_b_id}", headers=self.headers_a).status_code, 404)
            self.assertEqual(self.client.get(f"/api/community/posts/{self.post_a_id}", headers=self.headers_b).status_code, 404)

            # Author profile & posts 404 (2-way)
            self.assertEqual(self.client.get(f"/api/community/authors/{self.user_b_id}", headers=self.headers_a).status_code, 404)
            self.assertEqual(self.client.get(f"/api/community/authors/{self.user_a_id}", headers=self.headers_b).status_code, 404)
            self.assertEqual(self.client.get(f"/api/community/authors/{self.user_b_id}/posts", headers=self.headers_a).status_code, 404)
            self.assertEqual(self.client.get(f"/api/community/authors/{self.user_a_id}/posts", headers=self.headers_b).status_code, 404)

            # Comments & answers hidden (2-way) on shared C post/question
            cmts_a = self.client.get(f"/api/community/posts/{self.post_c_id}/comments", headers=self.headers_a).json()
            self.assertEqual([c["author"]["id"] for c in cmts_a["items"]], [self.user_a_id])
            cmts_b = self.client.get(f"/api/community/posts/{self.post_c_id}/comments", headers=self.headers_b).json()
            self.assertEqual([c["author"]["id"] for c in cmts_b["items"]], [self.user_b_id])

            ans_a = self.client.get(f"/api/community/questions/{self.qa_c_id}/answers", headers=self.headers_a).json()
            self.assertEqual([a["author"]["id"] for a in ans_a["items"]], [self.user_a_id])
            ans_b = self.client.get(f"/api/community/questions/{self.qa_c_id}/answers", headers=self.headers_b).json()
            self.assertEqual([a["author"]["id"] for a in ans_b["items"]], [self.user_b_id])

            # Stories hidden (2-way)
            stories_a = [g["author"]["id"] for g in self.client.get("/api/community/stories", headers=self.headers_a).json()["items"]]
            self.assertNotIn(self.user_b_id, stories_a)
            stories_b = [g["author"]["id"] for g in self.client.get("/api/community/stories", headers=self.headers_b).json()["items"]]
            self.assertNotIn(self.user_a_id, stories_b)

            # Commenting on blocked user's public post -> 403
            res_cmt_blocked = self.client.post(
                f"/api/community/posts/{self.post_a_id}/comments",
                headers={**self.headers_b, "X-Idempotency-Key": "cmt_b_blocked_0001"},
                json={"content": "Blocked attempt"},
            )
            self.assertEqual(res_cmt_blocked.status_code, 403)

            # Blocked list endpoint returns B (sanitized)
            blocked_list = self.client.get("/api/community/settings/blocked", headers=self.headers_a).json()
            self.assertEqual(blocked_list["total_count"], 1)
            self.assertEqual(blocked_list["items"][0]["id"], self.user_b_id)
            self.assertNotIn("email", blocked_list["items"][0])
            self.assertNotIn("hashed_password", blocked_list["items"][0])

            # Unblock restores access & follow
            res_unblk = self.client.delete(f"/api/community/users/{self.user_b_id}/block", headers=self.headers_a)
            self.assertEqual(res_unblk.status_code, 200)
            self.assertEqual(res_unblk.json(), {"target_user_id": self.user_b_id, "is_blocked": False})
            self.assertEqual(self.client.get(f"/api/community/posts/{self.post_b_id}", headers=self.headers_a).status_code, 200)
            self.assertEqual(self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=self.headers_a).status_code, 200)

    def test_mute_one_way_filters_muter_only(self):
        with patch("backend.routers.community.db", self.fake_db):
            # A follows B, both post stories
            self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=self.headers_a)
            self.client.post("/api/community/stories", headers=self.headers_a, json={"media_type": "text", "caption": "A story"})
            self.client.post("/api/community/stories", headers=self.headers_b, json={"media_type": "text", "caption": "B story"})

            # Self-mute rejected
            self.assertEqual(
                self.client.put(f"/api/community/users/{self.user_a_id}/mute", headers=self.headers_a).status_code,
                400,
            )

            # A mutes B
            res_mute = self.client.put(f"/api/community/users/{self.user_b_id}/mute", headers=self.headers_a)
            self.assertEqual(res_mute.status_code, 200)
            self.assertEqual(res_mute.json(), {"target_user_id": self.user_b_id, "is_muted": True})

            # Follow is preserved
            self.assertEqual(self.fake_db["community_follows"].count_documents({"follower_id": self.user_a_id, "following_id": self.user_b_id}), 1)

            # A does not see B in feed, discover, or stories
            feed_a = [p["id"] for p in self.client.get("/api/community/feed", headers=self.headers_a).json()["items"]]
            self.assertNotIn(self.post_b_id, feed_a)
            disc_a = self.client.get("/api/community/discover", headers=self.headers_a).json()
            self.assertNotIn(self.post_b_id, [g["post_id"] for g in disc_a["grid_items"]])
            self.assertNotIn(self.user_b_id, [c["id"] for c in disc_a["recommended_creators"]])
            stories_a = [g["author"]["id"] for g in self.client.get("/api/community/stories", headers=self.headers_a).json()["items"]]
            self.assertNotIn(self.user_b_id, stories_a)

            # B STILL sees A in feed, discover, and stories (1-way)
            feed_b = [p["id"] for p in self.client.get("/api/community/feed", headers=self.headers_b).json()["items"]]
            self.assertIn(self.post_a_id, feed_b)
            stories_b = [g["author"]["id"] for g in self.client.get("/api/community/stories", headers=self.headers_b).json()["items"]]
            self.assertIn(self.user_a_id, stories_b)

            # Muted list endpoint
            muted_list = self.client.get("/api/community/settings/muted", headers=self.headers_a).json()
            self.assertEqual(muted_list["total_count"], 1)
            self.assertEqual(muted_list["items"][0]["id"], self.user_b_id)

            # Unmute restores B in A's feed
            res_unmute = self.client.delete(f"/api/community/users/{self.user_b_id}/mute", headers=self.headers_a)
            self.assertEqual(res_unmute.status_code, 200)
            self.assertEqual(res_unmute.json(), {"target_user_id": self.user_b_id, "is_muted": False})
            feed_a_after = [p["id"] for p in self.client.get("/api/community/feed", headers=self.headers_a).json()["items"]]
            self.assertIn(self.post_b_id, feed_a_after)

    def test_report_idempotent_and_validation(self):
        with patch("backend.routers.community.db", self.fake_db):
            res1 = self.client.post(
                "/api/community/reports",
                headers=self.headers_a,
                json={
                    "target_type": "post",
                    "target_id": self.post_b_id,
                    "reason": "spam",
                    "details": "Repeated spam link",
                },
            )
            self.assertEqual(res1.status_code, 200)
            r1 = res1.json()
            self.assertFalse(r1["already_reported"])
            self.assertEqual(r1["status"], "received")

            # Duplicate report is idempotent
            res2 = self.client.post(
                "/api/community/reports",
                headers=self.headers_a,
                json={
                    "target_type": "post",
                    "target_id": self.post_b_id,
                    "reason": "spam",
                    "details": "Duplicate click",
                },
            )
            self.assertEqual(res2.status_code, 200)
            r2 = res2.json()
            self.assertTrue(r2["already_reported"])
            self.assertEqual(r2["report_id"], r1["report_id"])
            self.assertEqual(self.fake_db["community_reports"].count_documents({}), 1)

            # Validation errors: extra field, invalid reason, self-report, non-existent target
            self.assertEqual(
                self.client.post(
                    "/api/community/reports",
                    headers=self.headers_a,
                    json={"target_type": "post", "target_id": self.post_b_id, "reason": "spam", "extra_field": 1},
                ).status_code,
                422,
            )
            self.assertEqual(
                self.client.post(
                    "/api/community/reports",
                    headers=self.headers_a,
                    json={"target_type": "post", "target_id": self.post_b_id, "reason": "unknown_reason"},
                ).status_code,
                422,
            )
            self.assertEqual(
                self.client.post(
                    "/api/community/reports",
                    headers=self.headers_a,
                    json={"target_type": "user", "target_id": self.user_a_id, "reason": "other"},
                ).status_code,
                400,
            )
            self.assertEqual(
                self.client.post(
                    "/api/community/reports",
                    headers=self.headers_a,
                    json={"target_type": "post", "target_id": "nonexistent_post_xyz", "reason": "spam"},
                ).status_code,
                404,
            )

    # 4. STORIES 24H
    def test_stories_create_validation_and_expiration(self):
        with patch("backend.routers.community.db", self.fake_db):
            # Photo story without media_url -> 422
            self.assertEqual(
                self.client.post(
                    "/api/community/stories",
                    headers=self.headers_a,
                    json={"media_type": "photo", "caption": "No photo url"},
                ).status_code,
                422,
            )
            # Text story with blank caption -> 422
            self.assertEqual(
                self.client.post(
                    "/api/community/stories",
                    headers=self.headers_a,
                    json={"media_type": "text", "caption": "   "},
                ).status_code,
                422,
            )
            # Extra field -> 422
            self.assertEqual(
                self.client.post(
                    "/api/community/stories",
                    headers=self.headers_a,
                    json={"media_type": "text", "caption": "Hello", "foo": "bar"},
                ).status_code,
                422,
            )

            # Valid photo story sets expires_at = created_at + 24h
            res_photo = self.client.post(
                "/api/community/stories",
                headers=self.headers_a,
                json={
                    "media_type": "photo",
                    "media_url": "/static/community/story1.jpg",
                    "caption": "Post-workout glow",
                    "privacy": "public",
                },
            )
            self.assertEqual(res_photo.status_code, 200)
            s_photo = res_photo.json()
            dt_created = datetime.fromisoformat(s_photo["created_at"])
            dt_expires = datetime.fromisoformat(s_photo["expires_at"])
            self.assertEqual(int((dt_expires - dt_created).total_seconds()), 24 * 3600)

            # Insert an already-expired story directly in DB
            expired_id = ObjectId()
            past = datetime.now(timezone.utc) - timedelta(hours=25)
            self.fake_db["community_stories"].insert_one({
                "_id": expired_id,
                "user_id": self.user_b_id,
                "author": {"id": self.user_b_id, "name": "Coach B"},
                "media_type": "text",
                "caption": "Old expired story",
                "privacy": "public",
                "is_deleted": False,
                "created_at": past,
                "expires_at": past + timedelta(hours=24),
            })

            # GET /stories excludes expired story
            feed = self.client.get("/api/community/stories", headers=self.headers_a).json()
            all_story_ids = [s["id"] for g in feed["items"] for s in g["stories"]]
            self.assertIn(s_photo["id"], all_story_ids)
            self.assertNotIn(str(expired_id), all_story_ids)

            # Viewing expired story returns 404
            self.assertEqual(
                self.client.post(f"/api/community/stories/{expired_id}/view", headers=self.headers_a).status_code,
                404,
            )

    def test_stories_followers_only_grouping_views_and_owner_delete(self):
        with patch("backend.routers.community.db", self.fake_db):
            # A creates public story, B creates followers_only story
            s_a = self.client.post(
                "/api/community/stories",
                headers=self.headers_a,
                json={"media_type": "text", "caption": "My story", "background_color": "#1A2B3C"},
            ).json()
            s_b = self.client.post(
                "/api/community/stories",
                headers=self.headers_b,
                json={"media_type": "text", "caption": "Followers only story", "privacy": "followers_only"},
            ).json()

            # Before A follows B: A does NOT see B's followers_only story, and cannot view it (404)
            feed_before = self.client.get("/api/community/stories", headers=self.headers_a).json()
            self.assertEqual(len(feed_before["items"]), 1)
            self.assertEqual(feed_before["items"][0]["author"]["id"], self.user_a_id)
            self.assertTrue(feed_before["items"][0]["is_self"])
            self.assertEqual(
                self.client.post(f"/api/community/stories/{s_b['id']}/view", headers=self.headers_a).status_code,
                404,
            )

            # After A follows B: A sees own group first, then B's group with has_unviewed=True
            self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=self.headers_a)
            feed_after = self.client.get("/api/community/stories", headers=self.headers_a).json()
            self.assertEqual([g["author"]["id"] for g in feed_after["items"]], [self.user_a_id, self.user_b_id])
            self.assertTrue(feed_after["items"][1]["has_unviewed"])

            # A views B's story twice -> idempotent view_count = 1
            v1 = self.client.post(f"/api/community/stories/{s_b['id']}/view", headers=self.headers_a)
            self.assertEqual(v1.status_code, 200)
            self.assertEqual(v1.json(), {"story_id": s_b["id"], "is_viewed": True, "view_count": 1})
            v2 = self.client.post(f"/api/community/stories/{s_b['id']}/view", headers=self.headers_a)
            self.assertEqual(v2.json()["view_count"], 1)

            # Now B's group has has_unviewed=False for A
            feed_viewed = self.client.get("/api/community/stories", headers=self.headers_a).json()
            b_group = next(g for g in feed_viewed["items"] if g["author"]["id"] == self.user_b_id)
            self.assertFalse(b_group["has_unviewed"])
            self.assertEqual(b_group["stories"][0]["view_count"], 1)
            self.assertTrue(b_group["stories"][0]["is_viewed"])

            # Non-owner (A) cannot delete B's story -> 404
            self.assertEqual(
                self.client.delete(f"/api/community/stories/{s_b['id']}", headers=self.headers_a).status_code,
                404,
            )
            # Owner (B) deletes own story -> 200, then disappears from feed
            res_del = self.client.delete(f"/api/community/stories/{s_b['id']}", headers=self.headers_b)
            self.assertEqual(res_del.status_code, 200)
            self.assertTrue(res_del.json()["success"])
            feed_after_del = self.client.get("/api/community/stories", headers=self.headers_a).json()
            self.assertEqual([g["author"]["id"] for g in feed_after_del["items"]], [self.user_a_id])
            self.assertEqual(s_a["background_color"], "#1A2B3C")

    # 5. POST SHARE
    def test_post_share_increments_and_enforces_audience(self):
        with patch("backend.routers.community.db", self.fake_db):
            # Initial share_count is 0
            det0 = self.client.get(f"/api/community/posts/{self.post_b_id}", headers=self.headers_a).json()
            self.assertEqual(det0["share_count"], 0)

            # Share by A -> 1
            sh1 = self.client.post(f"/api/community/posts/{self.post_b_id}/share", headers=self.headers_a)
            self.assertEqual(sh1.status_code, 200)
            self.assertEqual(sh1.json(), {"post_id": self.post_b_id, "share_count": 1})

            # Share by C -> 2
            sh2 = self.client.post(f"/api/community/posts/{self.post_b_id}/share", headers=self.headers_c)
            self.assertEqual(sh2.status_code, 200)
            self.assertEqual(sh2.json(), {"post_id": self.post_b_id, "share_count": 2})

            # Reflected in Post Detail & Feed
            det2 = self.client.get(f"/api/community/posts/{self.post_b_id}", headers=self.headers_a).json()
            self.assertEqual(det2["share_count"], 2)
            feed_items = self.client.get("/api/community/feed", headers=self.headers_a).json()["items"]
            post_b_feed = next(p for p in feed_items if p["id"] == self.post_b_id)
            self.assertEqual(post_b_feed["share_count"], 2)

            # Private post cannot be shared by non-owner -> 404
            self.assertEqual(
                self.client.post(f"/api/community/posts/{self.post_b_private_id}/share", headers=self.headers_a).status_code,
                404,
            )

            # Blocked user's post cannot be shared -> 404
            self.client.put(f"/api/community/users/{self.user_b_id}/block", headers=self.headers_a)
            self.assertEqual(
                self.client.post(f"/api/community/posts/{self.post_b_id}/share", headers=self.headers_a).status_code,
                404,
            )


if __name__ == "__main__":
    unittest.main()
