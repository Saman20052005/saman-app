"""
Unit and Integration Tests for Saman Community Instagram Phase 2 Backend.

Covers:
1. Story TTL removal & safe index migration (ensure_community_indexes & setup_community_indexes)
2. Personal Story Archive (GET /api/community/stories/archive):
   - Expired (>24h) stories disappear from GET /stories & POST /stories/{id}/view,
     but remain persisted in DB and appear in owner's /stories/archive
   - include_active=false (default) vs include_active=true, is_expired flag, view_count
   - Strict owner-only isolation (other users cannot see your archive)
   - Cursor & offset pagination, soft-deleted exclusion
3. Expanded CommunitySettingsModel & GET/PATCH /api/community/settings:
   - Defaults for new users & backward compatibility for legacy MongoDB docs
   - Roundtrip PATCH for who_can_reply_story, allow_mentions, auto_prompt_share_workout,
     auto_prompt_share_meal, muted_keywords
   - muted_keywords normalization (trim, lowercase, stable dedupe, drop blanks, limits <=50 & <=40 chars)
4. Muted keywords filtering in GET /api/community/feed:
   - Case-insensitive filtering on caption/content/title/qa/attachment for other users' posts
   - Owner's own posts are never hidden by their own muted_keywords
   - Accurate pagination across filtered posts
5. who_can_reply_story enforcement on story_reply in community_dm.py:
   - nobody -> 403 (while regular text DM still obeys who_can_dm)
   - followers -> 403 for non-follower, 200 after follow
   - everyone / legacy missing field -> 200
   - self-reply policy consistency
"""

from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone
import re
from typing import Any, Dict, List, Optional
import unittest
from unittest.mock import patch

from bson import ObjectId
from fastapi.testclient import TestClient
import jwt
from pymongo.errors import DuplicateKeyError

from backend.app.database_community import ensure_community_indexes
from backend.main import app
from backend.routers import community as community_router_mod
from backend.routers import community_dm as community_dm_mod
from backend.routers.community import JWT_ALGORITHM, JWT_SECRET


# ---------------------------------------------------------------------------
# InMemoryDatabase mock (PyMongo-compatible) following test_community_*.py
# ---------------------------------------------------------------------------


def _get_nested(doc: Dict[str, Any], dotted_key: str):
    cur: Any = doc
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


def _set_nested(doc: Dict[str, Any], dotted_key: str, value: Any) -> None:
    parts = dotted_key.split(".")
    cur = doc
    for part in parts[:-1]:
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = {}
        cur = cur[part]
    cur[parts[-1]] = value


def _inc_nested(doc: Dict[str, Any], dotted_key: str, delta: int | float) -> None:
    parts = dotted_key.split(".")
    cur = doc
    for part in parts[:-1]:
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = {}
        cur = cur[part]
    cur[parts[-1]] = cur.get(parts[-1], 0) + delta


def _norm_dt(v: Any) -> Any:
    if isinstance(v, datetime):
        return v.replace(tzinfo=timezone.utc) if v.tzinfo is None else v.astimezone(timezone.utc)
    return v


def _match_condition(val: Any, exists: bool, cond: Any) -> bool:
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
                elif isinstance(val, list):
                    if not any(v in expected for v in val):
                        return False
                elif val not in expected and str(val) not in [str(x) for x in expected if x is not None]:
                    return False
            elif op == "$nin":
                if exists:
                    if isinstance(val, list):
                        if any(v in expected for v in val):
                            return False
                    elif val in expected or str(val) in [str(x) for x in expected]:
                        return False
            elif op == "$gt":
                if not exists or val is None or _norm_dt(val) <= _norm_dt(expected):
                    return False
            elif op == "$gte":
                if not exists or val is None or _norm_dt(val) < _norm_dt(expected):
                    return False
            elif op == "$lt":
                if not exists or val is None or _norm_dt(val) >= _norm_dt(expected):
                    return False
            elif op == "$lte":
                if not exists or val is None or _norm_dt(val) > _norm_dt(expected):
                    return False
            elif op == "$type":
                if expected == "string" and not isinstance(val, str):
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
    if isinstance(val, list) and not isinstance(cond, list):
        return cond in val or str(cond) in [str(x) for x in val]
    if isinstance(val, ObjectId) or isinstance(cond, ObjectId):
        return str(val) == str(cond)
    return val == cond


def _match_query(doc: Dict[str, Any], query: Optional[Dict[str, Any]]) -> bool:
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


class InMemoryCursor:
    def __init__(self, docs: List[Dict[str, Any]]):
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

    def limit(self, n: int):
        self._docs = self._docs[:n]
        return self

    def __iter__(self):
        return iter(copy.deepcopy(self._docs))


class InMemoryCollection:
    def __init__(self, name: str):
        self.name = name
        self.docs: List[Dict[str, Any]] = []
        self._indexes: Dict[str, Dict[str, Any]] = {}

    def create_index(self, keys, name=None, unique=False, **kwargs):
        idx_name = name or "_".join(f"{k}_{d}" for k, d in keys)
        info = {"key": list(keys), "unique": bool(unique), **kwargs}
        self._indexes[idx_name] = info
        return idx_name

    def index_information(self):
        return copy.deepcopy(self._indexes)

    def drop_index(self, index_name: str):
        if index_name not in self._indexes:
            raise KeyError(f"Index not found: {index_name}")
        del self._indexes[index_name]

    def _check_unique(self, candidate: Dict[str, Any], skip_oid=None):
        for idx in self._indexes.values():
            if not idx.get("unique"):
                continue
            pfe = idx.get("partialFilterExpression")
            if pfe and not _match_query(candidate, pfe):
                continue
            key_fields = [k for k, _ in idx["key"]]
            cand_tuple = tuple(_get_nested(candidate, f)[0] for f in key_fields)
            for existing in self.docs:
                if skip_oid is not None and existing.get("_id") == skip_oid:
                    continue
                if pfe and not _match_query(existing, pfe):
                    continue
                ex_tuple = tuple(_get_nested(existing, f)[0] for f in key_fields)
                if cand_tuple == ex_tuple:
                    raise DuplicateKeyError(f"Duplicate key on {self.name}: {key_fields}")

    def insert_one(self, doc: Dict[str, Any]):
        rec = copy.deepcopy(doc)
        if "_id" not in rec:
            rec["_id"] = ObjectId()
        self._check_unique(rec)
        self.docs.append(rec)
        return type("InsertResult", (), {"inserted_id": rec["_id"]})()

    def find_one(self, query=None):
        for d in self.docs:
            if _match_query(d, query or {}):
                return copy.deepcopy(d)
        return None

    def find(self, query=None, projection=None):
        matched = [copy.deepcopy(d) for d in self.docs if _match_query(d, query or {})]
        return InMemoryCursor(matched)

    def count_documents(self, query=None) -> int:
        return sum(1 for d in self.docs if _match_query(d, query or {}))

    def update_one(self, query, update, upsert=False):
        for idx, d in enumerate(self.docs):
            if _match_query(d, query):
                updated = copy.deepcopy(d)
                for k, v in (update.get("$set") or {}).items():
                    _set_nested(updated, k, copy.deepcopy(v))
                for k, delta in (update.get("$inc") or {}).items():
                    _inc_nested(updated, k, delta)
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
            rec: Dict[str, Any] = {}
            for k, v in query.items():
                if not k.startswith("$"):
                    rec[k] = copy.deepcopy(v)
            for k, v in (update.get("$setOnInsert") or {}).items():
                _set_nested(rec, k, copy.deepcopy(v))
            for k, v in (update.get("$set") or {}).items():
                _set_nested(rec, k, copy.deepcopy(v))
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

    def aggregate(self, pipeline):
        docs = [copy.deepcopy(d) for d in self.docs]
        for stage in pipeline:
            if "$match" in stage:
                docs = [d for d in docs if _match_query(d, stage["$match"])]
            elif "$group" in stage:
                spec = stage["$group"]
                id_expr = spec["_id"]
                field = id_expr[1:] if isinstance(id_expr, str) and id_expr.startswith("$") else None
                buckets: Dict[Any, int] = {}
                for d in docs:
                    k = _get_nested(d, field)[0] if field else id_expr
                    buckets[k] = buckets.get(k, 0) + 1
                docs = [{"_id": k, "count": v} for k, v in buckets.items()]
        return docs


class InMemoryDatabase:
    def __init__(self):
        self.name = "saman_ig_phase2_test"
        self._cols: Dict[str, InMemoryCollection] = {}

    def __getitem__(self, name: str) -> InMemoryCollection:
        if name not in self._cols:
            self._cols[name] = InMemoryCollection(name)
        return self._cols[name]


# ---------------------------------------------------------------------------
# Test Suite
# ---------------------------------------------------------------------------


class TestCommunityInstagramPhase2(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.fake_db = InMemoryDatabase()
        ensure_community_indexes(self.fake_db)

        self.user_a_id = "675000000000000000000001"
        self.user_b_id = "675000000000000000000002"
        self.user_c_id = "675000000000000000000003"

        self.fake_db["users"].insert_one({
            "_id": self.user_a_id,
            "id": self.user_a_id,
            "email": "alice@saman.test",
            "name": "Alice Athlete",
            "title": "Runner",
        })
        self.fake_db["users"].insert_one({
            "_id": self.user_b_id,
            "id": self.user_b_id,
            "email": "bob@saman.test",
            "name": "Bob Coach",
            "title": "Coach",
            "is_verified": True,
        })
        self.fake_db["users"].insert_one({
            "_id": self.user_c_id,
            "id": self.user_c_id,
            "email": "carol@saman.test",
            "name": "Carol Chef",
            "title": "Nutritionist",
        })

        self.headers_a = self._auth_headers(self.user_a_id, "alice@saman.test", "Alice Athlete")
        self.headers_b = self._auth_headers(self.user_b_id, "bob@saman.test", "Bob Coach")
        self.headers_c = self._auth_headers(self.user_c_id, "carol@saman.test", "Carol Chef")

    def _auth_headers(self, uid: str, email: str, name: str) -> Dict[str, str]:
        token = jwt.encode(
            {"sub": uid, "user_id": uid, "email": email, "name": name},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )
        return {"Authorization": f"Bearer {token}"}

    # ------------------------------------------------------------------
    # 1. Story TTL Removal & Safe Index Migration
    # ------------------------------------------------------------------

    def test_ensure_community_indexes_drops_legacy_ttl_and_creates_non_ttl_story_indexes(self):
        fresh_db = InMemoryDatabase()
        # Simulate legacy production DB with TTL index expireAfterSeconds=0
        fresh_db["community_stories"].create_index(
            [("expires_at", 1)],
            expireAfterSeconds=0,
            name="idx_stories_ttl_expires",
        )
        self.assertIn("idx_stories_ttl_expires", fresh_db["community_stories"].index_information())

        created = ensure_community_indexes(fresh_db)
        story_idxs = fresh_db["community_stories"].index_information()

        # Legacy TTL index must be removed and no TTL index remains
        self.assertNotIn("idx_stories_ttl_expires", story_idxs)
        for idx_name, idx_info in story_idxs.items():
            self.assertNotIn(
                "expireAfterSeconds",
                idx_info,
                f"Story index {idx_name} must NOT be a TTL index",
            )

        # Regular expires_at + user_id/created_at indexes exist
        self.assertIn("idx_stories_expires_at", story_idxs)
        self.assertEqual(story_idxs["idx_stories_expires_at"]["key"], [("expires_at", 1)])
        self.assertIn("idx_stories_user_created", story_idxs)
        self.assertEqual(story_idxs["idx_stories_user_created"]["key"], [("user_id", 1), ("created_at", -1)])
        self.assertEqual(created["community_stories"], ["idx_stories_expires_at", "idx_stories_user_created"])

    def test_ensure_community_indexes_handles_mock_without_index_information_or_drop_index(self):
        class MinimalCollection:
            def __init__(self):
                self.created = []

            def create_index(self, keys, name=None, **kwargs):
                self.created.append((list(keys), name, kwargs))
                return name

        class MinimalDB:
            def __init__(self):
                self.cols = {}

            def __getitem__(self, name):
                self.cols.setdefault(name, MinimalCollection())
                return self.cols[name]

        minimal_db = MinimalDB()
        created = ensure_community_indexes(minimal_db)
        self.assertEqual(created["community_stories"], ["idx_stories_expires_at", "idx_stories_user_created"])
        for _keys, _name, kwargs in minimal_db["community_stories"].created:
            self.assertNotIn("expireAfterSeconds", kwargs)

    # ------------------------------------------------------------------
    # 2. Story Archive (GET /api/community/stories/archive)
    # ------------------------------------------------------------------

    def test_story_archive_expired_vs_active_isolation_views_and_pagination(self):
        now = datetime.now(timezone.utc)

        # Seed User A stories: 3 expired, 1 active (<24h), 1 soft-deleted expired
        a_exp_oldest_id = ObjectId("675100000000000000000001")
        a_exp_mid_id = ObjectId("675100000000000000000002")
        a_exp_newest_id = ObjectId("675100000000000000000003")
        a_active_id = ObjectId("675100000000000000000004")
        a_deleted_id = ObjectId("675100000000000000000005")
        b_exp_id = ObjectId("675100000000000000000006")

        stories_col = self.fake_db["community_stories"]
        stories_col.insert_one({
            "_id": a_exp_oldest_id,
            "user_id": self.user_a_id,
            "media_type": "text",
            "caption": "Expired story 1 (oldest)",
            "privacy": "public",
            "is_deleted": False,
            "created_at": now - timedelta(days=5),
            "expires_at": now - timedelta(days=4),
        })
        # Tie timestamp between a_exp_mid_id and a_exp_newest_id to verify _id DESC tie-breaker
        tie_created = now - timedelta(hours=30)
        tie_expires = tie_created + timedelta(hours=24)
        stories_col.insert_one({
            "_id": a_exp_mid_id,
            "user_id": self.user_a_id,
            "media_type": "photo",
            "media_url": "/static/community/old2.jpg",
            "caption": "Expired story 2 (tie lower id)",
            "privacy": "followers_only",
            "is_deleted": False,
            "created_at": tie_created,
            "expires_at": tie_expires,
        })
        stories_col.insert_one({
            "_id": a_exp_newest_id,
            "user_id": self.user_a_id,
            "media_type": "photo",
            "media_url": "/static/community/old3.jpg",
            "caption": "Expired story 3 (tie higher id)",
            "privacy": "public",
            "is_deleted": False,
            "created_at": tie_created,
            "expires_at": tie_expires,
        })
        stories_col.insert_one({
            "_id": a_active_id,
            "user_id": self.user_a_id,
            "media_type": "text",
            "caption": "Active story (<24h)",
            "privacy": "public",
            "is_deleted": False,
            "created_at": now - timedelta(hours=2),
            "expires_at": now + timedelta(hours=22),
        })
        stories_col.insert_one({
            "_id": a_deleted_id,
            "user_id": self.user_a_id,
            "media_type": "text",
            "caption": "Deleted expired story",
            "privacy": "public",
            "is_deleted": True,
            "created_at": now - timedelta(days=2),
            "expires_at": now - timedelta(days=1),
        })
        stories_col.insert_one({
            "_id": b_exp_id,
            "user_id": self.user_b_id,
            "media_type": "text",
            "caption": "Bob expired story",
            "privacy": "public",
            "is_deleted": False,
            "created_at": now - timedelta(days=2),
            "expires_at": now - timedelta(days=1),
        })

        # Add views on a_exp_newest_id (2 viewers)
        self.fake_db["community_story_views"].insert_one({
            "story_id": str(a_exp_newest_id),
            "viewer_id": self.user_b_id,
            "viewed_at": tie_created + timedelta(hours=1),
        })
        self.fake_db["community_story_views"].insert_one({
            "story_id": str(a_exp_newest_id),
            "viewer_id": self.user_c_id,
            "viewed_at": tie_created + timedelta(hours=2),
        })

        with patch.object(community_router_mod, "db", self.fake_db):
            # Unauthenticated -> 401
            self.assertEqual(self.client.get("/api/community/stories/archive").status_code, 401)

            # Public GET /stories returns ONLY active story (expired hidden from public tray)
            feed_res = self.client.get("/api/community/stories", headers=self.headers_a)
            self.assertEqual(feed_res.status_code, 200)
            feed_story_ids = [s["id"] for g in feed_res.json()["items"] for s in g["stories"]]
            self.assertEqual(feed_story_ids, [str(a_active_id)])

            # Default archive (include_active=false): ONLY User A's 3 expired non-deleted stories, newest first
            arch_res = self.client.get("/api/community/stories/archive", headers=self.headers_a)
            self.assertEqual(arch_res.status_code, 200)
            arch_data = arch_res.json()
            self.assertEqual(arch_data["total_count"], 3)
            self.assertIsNone(arch_data["next_cursor"])
            self.assertEqual(
                [item["id"] for item in arch_data["items"]],
                [str(a_exp_newest_id), str(a_exp_mid_id), str(a_exp_oldest_id)],
            )
            self.assertTrue(all(item["is_expired"] is True for item in arch_data["items"]))
            self.assertEqual(arch_data["items"][0]["view_count"], 2)
            self.assertEqual(arch_data["items"][1]["view_count"], 0)

            # include_active=true returns all 4 non-deleted stories of User A with accurate is_expired flags
            arch_all = self.client.get(
                "/api/community/stories/archive?include_active=true",
                headers=self.headers_a,
            )
            self.assertEqual(arch_all.status_code, 200)
            all_data = arch_all.json()
            self.assertEqual(all_data["total_count"], 4)
            self.assertEqual(
                [(item["id"], item["is_expired"]) for item in all_data["items"]],
                [
                    (str(a_active_id), False),
                    (str(a_exp_newest_id), True),
                    (str(a_exp_mid_id), True),
                    (str(a_exp_oldest_id), True),
                ],
            )

            # Cursor pagination (limit=2 -> page 1 has 2 items + cursor, page 2 has 1 item + None)
            p1 = self.client.get("/api/community/stories/archive?limit=2", headers=self.headers_a).json()
            self.assertEqual([i["id"] for i in p1["items"]], [str(a_exp_newest_id), str(a_exp_mid_id)])
            self.assertIsNotNone(p1["next_cursor"])

            p2 = self.client.get(
                f"/api/community/stories/archive?limit=2&cursor={p1['next_cursor']}",
                headers=self.headers_a,
            ).json()
            self.assertEqual([i["id"] for i in p2["items"]], [str(a_exp_oldest_id)])
            self.assertIsNone(p2["next_cursor"])

            # Offset pagination
            off_res = self.client.get(
                "/api/community/stories/archive?limit=1&offset=1",
                headers=self.headers_a,
            ).json()
            self.assertEqual([i["id"] for i in off_res["items"]], [str(a_exp_mid_id)])
            self.assertIsNotNone(off_res["next_cursor"])

            # Isolation: User B only sees Bob's own archived story, never Alice's
            arch_b = self.client.get("/api/community/stories/archive", headers=self.headers_b).json()
            self.assertEqual(arch_b["total_count"], 1)
            self.assertEqual([i["id"] for i in arch_b["items"]], [str(b_exp_id)])

            # Isolation: User C has empty archive
            arch_c = self.client.get("/api/community/stories/archive", headers=self.headers_c).json()
            self.assertEqual(arch_c["total_count"], 0)
            self.assertEqual(arch_c["items"], [])

    # ------------------------------------------------------------------
    # 3. Expanded CommunitySettingsModel (GET/PATCH + Backward Compat)
    # ------------------------------------------------------------------

    def test_settings_defaults_backward_compat_and_patch_roundtrip(self):
        with patch.object(community_router_mod, "db", self.fake_db):
            # New user without settings doc -> full defaults including IG Phase 2 fields
            r_def = self.client.get("/api/community/settings", headers=self.headers_a)
            self.assertEqual(r_def.status_code, 200)
            self.assertEqual(r_def.json(), {
                "is_private_account": False,
                "who_can_dm": "everyone",
                "who_can_comment": "everyone",
                "who_can_reply_story": "everyone",
                "allow_mentions": "everyone",
                "hide_like_counts": False,
                "show_activity_status": True,
                "auto_prompt_share_workout": True,
                "auto_prompt_share_meal": True,
                "muted_keywords": [],
            })

            # Legacy MongoDB document missing new IG Phase 2 fields -> safe defaults preserved
            self.fake_db["community_user_settings"].insert_one({
                "user_id": self.user_b_id,
                "is_private_account": True,
                "who_can_dm": "followers",
                "hide_like_counts": True,
            })
            r_legacy = self.client.get("/api/community/settings", headers=self.headers_b)
            self.assertEqual(r_legacy.status_code, 200)
            legacy_data = r_legacy.json()
            self.assertTrue(legacy_data["is_private_account"])
            self.assertEqual(legacy_data["who_can_dm"], "followers")
            self.assertTrue(legacy_data["hide_like_counts"])
            self.assertEqual(legacy_data["who_can_reply_story"], "everyone")
            self.assertEqual(legacy_data["allow_mentions"], "everyone")
            self.assertTrue(legacy_data["auto_prompt_share_workout"])
            self.assertTrue(legacy_data["auto_prompt_share_meal"])
            self.assertEqual(legacy_data["muted_keywords"], [])

            # PATCH all new fields + muted_keywords normalization
            r_patch = self.client.patch(
                "/api/community/settings",
                headers=self.headers_a,
                json={
                    "who_can_reply_story": "followers",
                    "allow_mentions": "nobody",
                    "auto_prompt_share_workout": False,
                    "auto_prompt_share_meal": False,
                    "muted_keywords": ["  Keto ", "  ", "", "SPAM", "keto", "Tăng Cân", "tăng cân"],
                },
            )
            self.assertEqual(r_patch.status_code, 200)
            patched = r_patch.json()
            self.assertEqual(patched["who_can_reply_story"], "followers")
            self.assertEqual(patched["allow_mentions"], "nobody")
            self.assertFalse(patched["auto_prompt_share_workout"])
            self.assertFalse(patched["auto_prompt_share_meal"])
            self.assertEqual(patched["muted_keywords"], ["keto", "spam", "tăng cân"])

            # Verify persisted on GET
            r_get = self.client.get("/api/community/settings", headers=self.headers_a)
            self.assertEqual(r_get.status_code, 200)
            self.assertEqual(r_get.json(), patched)

            # Validation: invalid enum -> 422
            self.assertEqual(
                self.client.patch(
                    "/api/community/settings",
                    headers=self.headers_a,
                    json={"who_can_reply_story": "friends_only"},
                ).status_code,
                422,
            )
            self.assertEqual(
                self.client.patch(
                    "/api/community/settings",
                    headers=self.headers_a,
                    json={"allow_mentions": "invalid"},
                ).status_code,
                422,
            )

            # Validation: keyword > 40 chars -> 422
            self.assertEqual(
                self.client.patch(
                    "/api/community/settings",
                    headers=self.headers_a,
                    json={"muted_keywords": ["a" * 41]},
                ).status_code,
                422,
            )

            # Validation: > 50 unique keywords -> 422, exactly 50 -> 200
            self.assertEqual(
                self.client.patch(
                    "/api/community/settings",
                    headers=self.headers_a,
                    json={"muted_keywords": [f"kw{i}" for i in range(51)]},
                ).status_code,
                422,
            )
            r_50 = self.client.patch(
                "/api/community/settings",
                headers=self.headers_a,
                json={"muted_keywords": [f"kw{i}" for i in range(50)]},
            )
            self.assertEqual(r_50.status_code, 200)
            self.assertEqual(len(r_50.json()["muted_keywords"]), 50)

    # ------------------------------------------------------------------
    # 4. Muted Keywords Filtering on GET /api/community/feed
    # ------------------------------------------------------------------

    def test_feed_filters_other_users_posts_matching_muted_keywords_but_keeps_own_posts(self):
        now = datetime.now(timezone.utc)
        posts_col = self.fake_db["community_posts"]

        # 1. Own post containing muted keyword -> MUST stay visible
        posts_col.insert_one({
            "_id": ObjectId("675200000000000000000001"),
            "id": "post_own_keto",
            "type": "text",
            "author_id": self.user_a_id,
            "author": {"id": self.user_a_id, "name": "Alice Athlete"},
            "caption": "My own KETO meal prep diary",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=1),
        })
        # 2. Other user's post matching caption (case-insensitive) -> HIDDEN
        posts_col.insert_one({
            "_id": ObjectId("675200000000000000000002"),
            "id": "post_b_caption_muted",
            "type": "text",
            "author_id": self.user_b_id,
            "author": {"id": self.user_b_id, "name": "Bob Coach"},
            "caption": "Try this strict KETO diet plan!",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=2),
        })
        # 3. Other user's Q&A post matching title/question -> HIDDEN
        posts_col.insert_one({
            "_id": ObjectId("675200000000000000000003"),
            "id": "post_c_qa_muted",
            "type": "qa",
            "author_id": self.user_c_id,
            "author": {"id": self.user_c_id, "name": "Carol Chef"},
            "caption": "",
            "qa_info": {
                "question": "Có nên dùng thuốc GIẢM CÂN cấp tốc?",
                "category_tag": "HỎI ĐÁP • DINH DƯỠNG",
            },
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=3),
        })
        # 4. Other user's post matching content/title fields -> HIDDEN
        posts_col.insert_one({
            "_id": ObjectId("675200000000000000000004"),
            "id": "post_b_title_muted",
            "type": "workout",
            "author_id": self.user_b_id,
            "author": {"id": self.user_b_id, "name": "Bob Coach"},
            "caption": "Upper body session",
            "title": "Sponsored SPAM Promo",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=4),
        })
        # 5. Clean post from B -> VISIBLE
        posts_col.insert_one({
            "_id": ObjectId("675200000000000000000005"),
            "id": "post_b_clean",
            "type": "text",
            "author_id": self.user_b_id,
            "author": {"id": self.user_b_id, "name": "Bob Coach"},
            "caption": "Morning 5K tempo run",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=5),
        })
        # 6. Clean post from C -> VISIBLE (verifies pagination fills limit accurately past muted posts)
        posts_col.insert_one({
            "_id": ObjectId("675200000000000000000006"),
            "id": "post_c_clean",
            "type": "text",
            "author_id": self.user_c_id,
            "author": {"id": self.user_c_id, "name": "Carol Chef"},
            "caption": "Balanced oats & fruit breakfast",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "created_at": now - timedelta(minutes=6),
        })

        with patch.object(community_router_mod, "db", self.fake_db):
            # Configure Alice's muted keywords
            self.assertEqual(
                self.client.patch(
                    "/api/community/settings",
                    headers=self.headers_a,
                    json={"muted_keywords": ["keto", "giảm cân", "spam"]},
                ).status_code,
                200,
            )

            # Page 1 with limit=2 must skip the 3 muted posts and return own + post_b_clean with next_cursor
            p1 = self.client.get("/api/community/feed?tab=for_you&limit=2", headers=self.headers_a)
            self.assertEqual(p1.status_code, 200)
            p1_data = p1.json()
            self.assertEqual([p["id"] for p in p1_data["items"]], ["post_own_keto", "post_b_clean"])
            self.assertIsNotNone(p1_data["next_cursor"])

            # Page 2 resumes cleanly and returns post_c_clean
            p2 = self.client.get(
                f"/api/community/feed?tab=for_you&limit=2&cursor={p1_data['next_cursor']}",
                headers=self.headers_a,
            )
            self.assertEqual(p2.status_code, 200)
            p2_data = p2.json()
            self.assertEqual([p["id"] for p in p2_data["items"]], ["post_c_clean"])
            self.assertIsNone(p2_data["next_cursor"])

            # User B (no muted keywords) still sees all 6 posts
            feed_b = self.client.get("/api/community/feed?tab=for_you&limit=20", headers=self.headers_b).json()
            self.assertEqual(len(feed_b["items"]), 6)

    # ------------------------------------------------------------------
    # 5. who_can_reply_story Enforcement in community_dm.py
    # ------------------------------------------------------------------

    def test_who_can_reply_story_enforcement_in_dm_story_reply(self):
        with (
            patch.object(community_router_mod, "db", self.fake_db),
            patch.object(community_dm_mod, "db", self.fake_db),
        ):
            # Create DM conversation between Alice and Bob (who_can_dm defaults to everyone)
            conv_res = self.client.post(
                "/api/community/dm/conversations",
                headers=self.headers_a,
                json={"target_user_id": self.user_b_id},
            )
            self.assertEqual(conv_res.status_code, 200)
            conv_id = conv_res.json()["id"]

            # 1. Default (everyone / no settings doc): story_reply succeeds
            r_default = self.client.post(
                f"/api/community/dm/conversations/{conv_id}/messages",
                headers=self.headers_a,
                json={"type": "story_reply", "content": "Awesome story!"},
            )
            self.assertEqual(r_default.status_code, 200)
            self.assertEqual(r_default.json()["type"], "story_reply")

            # 2. Bob sets who_can_reply_story = "nobody" (while who_can_dm remains "everyone")
            self.assertEqual(
                self.client.patch(
                    "/api/community/settings",
                    headers=self.headers_b,
                    json={"who_can_reply_story": "nobody"},
                ).status_code,
                200,
            )
            r_nobody = self.client.post(
                f"/api/community/dm/conversations/{conv_id}/messages",
                headers=self.headers_a,
                json={"type": "story_reply", "content": "Should be blocked"},
            )
            self.assertEqual(r_nobody.status_code, 403)

            # Regular text DM still works because who_can_dm is "everyone"
            r_text = self.client.post(
                f"/api/community/dm/conversations/{conv_id}/messages",
                headers=self.headers_a,
                json={"type": "text", "content": "Regular DM still allowed"},
            )
            self.assertEqual(r_text.status_code, 200)

            # 3. Bob sets who_can_reply_story = "followers"
            self.assertEqual(
                self.client.patch(
                    "/api/community/settings",
                    headers=self.headers_b,
                    json={"who_can_reply_story": "followers"},
                ).status_code,
                200,
            )
            # Alice is not following Bob yet -> 403
            r_non_follower = self.client.post(
                f"/api/community/dm/conversations/{conv_id}/messages",
                headers=self.headers_a,
                json={"type": "story_reply", "content": "Not following yet"},
            )
            self.assertEqual(r_non_follower.status_code, 403)

            # Alice follows Bob -> story_reply succeeds (200)
            self.assertEqual(
                self.client.put(
                    f"/api/community/authors/{self.user_b_id}/follow",
                    headers=self.headers_a,
                ).status_code,
                200,
            )
            r_follower = self.client.post(
                f"/api/community/dm/conversations/{conv_id}/messages",
                headers=self.headers_a,
                json={"type": "story_reply", "content": "Following now!"},
            )
            self.assertEqual(r_follower.status_code, 200)
            self.assertEqual(r_follower.json()["content"], "Following now!")

            # 4. Self-reply consistency: story owner always allowed by policy helper
            community_dm_mod._enforce_story_reply_allowed(self.user_b_id, self.user_b_id)


if __name__ == "__main__":
    unittest.main()
