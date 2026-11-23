"""
Comprehensive Contract & Security Tests for Saman Community Wave 3 Backend API.

Covers:
1. GET /api/community/discover:
   - Strict privacy isolation: never exposes private, followers_only, deleted, or draft/unpublished posts
     in grid_items OR trending_topics counts (even for authenticated owners/followers).
   - Topic chip filtering: all, workout, meal, recipe, qna, journey, and explicit #hashtag (e.g. #TậpLuyện).
   - Keyword search `q`: Vietnamese case-insensitive search across caption, topic, qa_info.question,
     attachment_snapshot.title, author.name, trending hashtags, and recommended creators; ReDoS/regex injection safety.
   - Grid items: authoritative like_count from community_interactions, has_multi_photo=True for >1 photos,
     created_at DESC sorting, and limit enforcement.
   - Trending topics: sorted by public post count DESC, max 5, exact format `f"{count} bài viết thảo luận"`.
   - Recommended creators: excludes self when logged in, sorted by follower_count DESC, max 10,
     accurate is_following, and strict _sanitize_author_projection (zero email/password/health leakage).
2. POST /api/community/posts (type="photo"):
   - Accepts 1..10 valid photo_urls (/static/community/... and http(s)://).
   - Rejects 422 for 0 photos, 11 photos, blank URLs, invalid schemes, or path traversal URLs.
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
                return None
            cur = cur[part]
        elif isinstance(cur, list) and part.isdigit():
            idx = int(part)
            if idx < 0 or idx >= len(cur):
                return None
            cur = cur[idx]
        else:
            return None
    return cur


def _normalize_dt(val):
    if isinstance(val, datetime) and val.tzinfo is None:
        return val.replace(tzinfo=timezone.utc)
    return val


def _matches_cond(val, cond):
    if isinstance(cond, dict):
        if "$regex" in cond:
            if not isinstance(val, str):
                return False
            flags = re.IGNORECASE if "i" in str(cond.get("$options", "")) else 0
            return re.search(cond["$regex"], val, flags) is not None

        for op, expected in cond.items():
            if op == "$ne":
                if val == expected:
                    return False
            elif op == "$in":
                if val not in expected and str(val) not in [str(x) for x in expected if x is not None]:
                    if not (val is None and None in expected):
                        return False
            elif op == "$lt":
                if val is None or _normalize_dt(val) >= _normalize_dt(expected):
                    return False
            elif op == "$gt":
                if val is None or _normalize_dt(val) <= _normalize_dt(expected):
                    return False
            elif op == "$exists":
                exists = val is not None
                if bool(expected) != exists:
                    return False
            else:
                if val != cond:
                    return False
        return True
    if isinstance(val, ObjectId) and isinstance(cond, ObjectId):
        return val == cond
    if isinstance(val, datetime) and isinstance(cond, datetime):
        return _normalize_dt(val) == _normalize_dt(cond)
    return val == cond


def _matches_query(doc, query):
    if not query:
        return True
    for k, v in query.items():
        if k == "$and":
            if not all(_matches_query(doc, sub) for sub in v):
                return False
        elif k == "$or":
            if not any(_matches_query(doc, sub) for sub in v):
                return False
        else:
            val = _get_nested(doc, k) if "." in k else doc.get(k)
            if not _matches_cond(val, v):
                return False
    return True


class _InMemoryCursor:
    def __init__(self, docs):
        self._docs = list(docs)

    def sort(self, key_or_list, direction=1):
        specs = [(key_or_list, direction)] if isinstance(key_or_list, str) else list(key_or_list)
        result = list(self._docs)
        for field, order in reversed(specs):
            result.sort(
                key=lambda d: _normalize_dt(_get_nested(d, field))
                if _get_nested(d, field) is not None
                else datetime.min.replace(tzinfo=timezone.utc),
                reverse=(order < 0),
            )
        return _InMemoryCursor(result)

    def limit(self, n):
        return _InMemoryCursor(self._docs[:n])

    def __iter__(self):
        return iter(self._docs)


class InMemoryCollection:
    def __init__(self, name="", unique_keys=None):
        self.name = name
        self.docs = []
        self._indexes = {}
        self._unique_keys = list(unique_keys or [])
        for idx_i, keys in enumerate(self._unique_keys):
            self._indexes[f"uniq_{idx_i}"] = {"key": list(keys), "unique": True}

    def create_index(self, keys, name=None, unique=False, partialFilterExpression=None):
        idx_name = name or "_".join(f"{k}_{d}" for k, d in keys)
        self._indexes[idx_name] = {
            "key": list(keys),
            "unique": bool(unique),
            "partialFilterExpression": partialFilterExpression,
        }
        if unique and list(keys) not in self._unique_keys:
            self._unique_keys.append(list(keys))
        return idx_name

    def index_information(self):
        return dict(self._indexes)

    def insert_one(self, doc):
        rec = dict(doc)
        if "_id" not in rec:
            rec["_id"] = ObjectId()
        for keys in self._unique_keys:
            key_fields = [k for k, _ in keys]
            if any(rec.get(f) is None for f in key_fields):
                continue
            for existing in self.docs:
                if all(existing.get(f) == rec.get(f) for f in key_fields):
                    raise DuplicateKeyError(f"Duplicate key on {key_fields}")
        self.docs.append(rec)
        return type("InsertResult", (), {"inserted_id": rec["_id"]})()

    def find_one(self, query):
        for d in self.docs:
            if _matches_query(d, query):
                return d
        return None

    def find(self, query=None, projection=None):
        return _InMemoryCursor([d for d in self.docs if _matches_query(d, query or {})])

    def count_documents(self, query=None):
        return sum(1 for d in self.docs if _matches_query(d, query or {}))

    def aggregate(self, pipeline):
        docs = list(self.docs)
        for stage in pipeline:
            if "$match" in stage:
                docs = [d for d in docs if _matches_query(d, stage["$match"])]
            elif "$group" in stage:
                id_expr = stage["$group"]["_id"]
                field_name = id_expr[1:] if isinstance(id_expr, str) and id_expr.startswith("$") else id_expr
                counts = {}
                for d in docs:
                    k = d.get(field_name)
                    counts[k] = counts.get(k, 0) + 1
                docs = [{"_id": k, "count": v} for k, v in counts.items()]
        return docs


class InMemoryDatabase:
    def __init__(self):
        self._cols = {}

    def __getitem__(self, name):
        if name not in self._cols:
            self._cols[name] = InMemoryCollection(name=name)
        return self._cols[name]


class TestCommunityWave3Api(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.fake_db = InMemoryDatabase()
        ensure_community_indexes(self.fake_db)
        # Ensure publish unique index on community_posts for POST /api/community/posts
        self.fake_db["community_posts"].create_index(
            [("user_id", 1), ("request_key", 1)],
            unique=True,
            name="publish_request_unique",
        )

        self.viewer_oid = ObjectId()
        self.creator_top_oid = ObjectId()
        self.creator_mid_oid = ObjectId()
        self.creator_low_oid = ObjectId()
        self.viewer_id = str(self.viewer_oid)
        self.creator_top_id = str(self.creator_top_oid)
        self.creator_mid_id = str(self.creator_mid_oid)
        self.creator_low_id = str(self.creator_low_oid)

        self.fake_db["users"].insert_one({
            "_id": self.viewer_oid,
            "email": "viewer@saman.test",
            "name": "Người Xem",
            "handle": "viewer_saman",
            "title": "Member",
            "password": "secret-viewer-password",
            "health_stats": {"weight": 68, "body_fat": 16},
        })
        self.fake_db["users"].insert_one({
            "_id": self.creator_top_oid,
            "email": "coach_top@saman.test",
            "name": "HLV Minh Khôi",
            "handle": "minhkhoi_coach",
            "title": "HLV Sức Mạnh & Dinh Dưỡng",
            "avatar_url": "https://cdn.example.com/minhkhoi.jpg",
            "is_verified": True,
            "password": "secret-top-password",
            "hashed_password": "hashed-top-password",
            "health_stats": {"vo2max": 58, "weight": 75},
        })
        self.fake_db["users"].insert_one({
            "_id": self.creator_mid_oid,
            "email": "chef_mid@saman.test",
            "name": "Thảo Vy Kitchen",
            "handle": "thaovy_eatclean",
            "title": "Eat Clean Chef",
            "avatar_url": "https://cdn.example.com/thaovy.jpg",
            "is_verified": False,
            "password": "secret-mid-password",
            "health_metrics": {"bmr": 1400},
        })
        self.fake_db["users"].insert_one({
            "_id": self.creator_low_oid,
            "email": "runner_low@saman.test",
            "name": "Quốc Bảo",
            "handle": "quocbao_run",
            "title": "Marathoner",
            "avatar_url": "https://cdn.example.com/quocbao.jpg",
        })

        # Follows: creator_top has 2 followers (viewer + creator_low), creator_mid has 1 follower (creator_top)
        self.fake_db["community_follows"].insert_one({
            "follower_id": self.viewer_id,
            "following_id": self.creator_top_id,
        })
        self.fake_db["community_follows"].insert_one({
            "follower_id": self.creator_low_id,
            "following_id": self.creator_top_id,
        })
        self.fake_db["community_follows"].insert_one({
            "follower_id": self.creator_top_id,
            "following_id": self.creator_mid_id,
        })

        self.headers_viewer = self._auth_headers(self.viewer_id, "viewer@saman.test", "Người Xem")

        base_t = datetime.now(timezone.utc) - timedelta(hours=3)
        posts = [
            # 1. Public workout multi-photo
            {
                "_id": ObjectId(),
                "id": "pub_workout_multi",
                "author_id": self.creator_top_id,
                "author": {"id": self.creator_top_id, "name": "HLV Minh Khôi"},
                "type": "workout",
                "topic": "#TậpLuyện",
                "caption": "Buổi tập Squat & Deadlift sáng nay cực cháy!",
                "photo_urls": ["/static/community/w1.jpg", "/static/community/w2.jpg", "/static/community/w3.jpg"],
                "attachment_snapshot": {"kind": "workout", "title": "Lower Body Power"},
                "privacy": "public",
                "status": "published",
                "is_deleted": False,
                "created_at": base_t + timedelta(minutes=50),
            },
            # 2. Public meal single photo
            {
                "_id": ObjectId(),
                "id": "pub_meal_single",
                "author_id": self.creator_mid_id,
                "author": {"id": self.creator_mid_id, "name": "Thảo Vy Kitchen"},
                "type": "meal",
                "topic": "#BữaĂn",
                "caption": "Công thức ức gà áp chảo sốt chanh dây 450 kcal",
                "photo_urls": ["https://cdn.example.com/meal1.jpg"],
                "attachment_snapshot": {"kind": "meal", "title": "Ức gà sốt chanh dây"},
                "privacy": "public",
                "status": "published",
                "is_deleted": False,
                "created_at": base_t + timedelta(minutes=40),
            },
            # 3. Public Q&A with photo
            {
                "_id": ObjectId(),
                "id": "pub_qa_photo",
                "author_id": self.creator_low_id,
                "author": {"id": self.creator_low_id, "name": "Quốc Bảo"},
                "type": "qa",
                "topic": "#PhụcHồi",
                "caption": "Đau cơ sau chạy 21km",
                "qa_info": {"question": "Nên giãn cơ hay chườm đá sau khi chạy bán marathon?", "category_tag": "HỎI ĐÁP"},
                "photo_urls": ["/static/community/qa_knee.jpg"],
                "privacy": "public",
                "status": "published",
                "is_deleted": False,
                "created_at": base_t + timedelta(minutes=30),
            },
            # 4. Public journey photo (with status None to verify status in ("published", None))
            {
                "_id": ObjectId(),
                "id": "pub_journey_legacy",
                "author_id": self.creator_low_id,
                "author": {"id": self.creator_low_id, "name": "Quốc Bảo"},
                "type": "photo",
                "topic": "#KỷLuật",
                "caption": "Hành trình 90 ngày không bỏ buổi nào (công thức kỷ luật)",
                "photo_urls": ["/static/community/journey1.jpg"],
                "privacy": "public",
                "status": None,
                "is_deleted": False,
                "created_at": base_t + timedelta(minutes=20),
            },
            # 5. Public text-only post (no photo_urls -> excluded from grid, INCLUDED in trending count)
            {
                "_id": ObjectId(),
                "id": "pub_workout_text_only",
                "author_id": self.creator_top_id,
                "author": {"id": self.creator_top_id, "name": "HLV Minh Khôi"},
                "type": "text",
                "topic": "#TậpLuyện",
                "caption": "Nhắc mọi người khởi động khớp vai trước khi đẩy ngực",
                "photo_urls": [],
                "privacy": "public",
                "status": "published",
                "is_deleted": False,
                "created_at": base_t + timedelta(minutes=15),
            },
            # 6. PRIVATE photo post -> MUST NEVER appear in grid or trending count
            {
                "_id": ObjectId(),
                "id": "priv_secret_post",
                "author_id": self.viewer_id,
                "author": {"id": self.viewer_id, "name": "Người Xem"},
                "type": "photo",
                "topic": "#BíMậtRiêngTư",
                "caption": "Ảnh riêng tư Squat không bao giờ được lộ",
                "photo_urls": ["/static/community/private_leak.jpg"],
                "privacy": "private",
                "status": "published",
                "is_deleted": False,
                "created_at": base_t + timedelta(minutes=60),
            },
            # 7. FOLLOWERS_ONLY photo post by creator_top (whom viewer FOLLOWS) -> STILL MUST NEVER appear in Discover!
            {
                "_id": ObjectId(),
                "id": "followers_only_post",
                "author_id": self.creator_top_id,
                "author": {"id": self.creator_top_id, "name": "HLV Minh Khôi"},
                "type": "workout",
                "topic": "#TậpLuyện",
                "caption": "Bài chỉ dành cho follower - Squat nâng cao",
                "photo_urls": ["/static/community/followers_only.jpg"],
                "privacy": "followers_only",
                "status": "published",
                "is_deleted": False,
                "created_at": base_t + timedelta(minutes=55),
            },
            # 8. DELETED public post -> MUST NEVER appear in grid or trending count
            {
                "_id": ObjectId(),
                "id": "deleted_pub_post",
                "author_id": self.creator_top_id,
                "author": {"id": self.creator_top_id, "name": "HLV Minh Khôi"},
                "type": "photo",
                "topic": "#ĐãXóa",
                "caption": "Bài đã xóa",
                "photo_urls": ["/static/community/deleted.jpg"],
                "privacy": "public",
                "status": "published",
                "is_deleted": True,
                "created_at": base_t + timedelta(minutes=58),
            },
            # 9. UNPUBLISHED public post -> MUST NEVER appear in grid or trending count
            {
                "_id": ObjectId(),
                "id": "unpublished_pub_post",
                "author_id": self.creator_top_id,
                "author": {"id": self.creator_top_id, "name": "HLV Minh Khôi"},
                "type": "photo",
                "topic": "#NhápẨn",
                "caption": "Bài chưa phát hành",
                "photo_urls": ["/static/community/unpublished.jpg"],
                "privacy": "public",
                "status": "unpublished",
                "is_deleted": False,
                "created_at": base_t + timedelta(minutes=59),
            },
        ]
        for p in posts:
            self.fake_db["community_posts"].insert_one(p)

        # Interactions: 3 likes on pub_workout_multi, 1 like on pub_meal_single
        for uid in [self.viewer_id, self.creator_mid_id, self.creator_low_id]:
            self.fake_db["community_interactions"].insert_one({
                "user_id": uid,
                "post_id": "pub_workout_multi",
                "interaction_type": "like",
            })
        self.fake_db["community_interactions"].insert_one({
            "user_id": self.viewer_id,
            "post_id": "pub_meal_single",
            "interaction_type": "like",
        })

    def _auth_headers(self, user_id: str, email: str, name: str):
        token = jwt.encode(
            {"sub": user_id, "user_id": user_id, "email": email, "name": name},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )
        return {"Authorization": f"Bearer {token}"}

    def _patch_db(self):
        return patch("backend.routers.community.db", self.fake_db)

    def test_discover_privacy_isolation_grid_trending_and_multi_photo(self):
        with self._patch_db():
            # Even when logged in as viewer (owner of priv_secret_post AND follower of creator_top),
            # Discover must strictly show ONLY public published/None non-deleted posts.
            res = self.client.get("/api/community/discover", headers=self.headers_viewer)
            self.assertEqual(res.status_code, 200)
            data = res.json()

            self.assertEqual(data["topic_chips"], ["all", "workout", "meal", "recipe", "qna", "journey"])
            self.assertEqual(data["active_topic"], "all")

            grid_ids = [item["post_id"] for item in data["grid_items"]]
            self.assertEqual(
                grid_ids,
                ["pub_workout_multi", "pub_meal_single", "pub_qa_photo", "pub_journey_legacy"],
            )
            # Zero leaks of private, followers_only, deleted, or unpublished posts
            for forbidden_id in ("priv_secret_post", "followers_only_post", "deleted_pub_post", "unpublished_pub_post"):
                self.assertNotIn(forbidden_id, grid_ids)

            # Verify multi-photo flag and authoritative like_count from community_interactions
            first_item = data["grid_items"][0]
            self.assertEqual(first_item["id"], "pub_workout_multi")
            self.assertEqual(first_item["image_url"], "/static/community/w1.jpg")
            self.assertTrue(first_item["has_multi_photo"])
            self.assertEqual(first_item["like_count"], 3)

            second_item = data["grid_items"][1]
            self.assertEqual(second_item["id"], "pub_meal_single")
            self.assertFalse(second_item["has_multi_photo"])
            self.assertEqual(second_item["like_count"], 1)

            # Trending topics must count ONLY public posts:
            # #TậpLuyện has 2 public posts (pub_workout_multi + pub_workout_text_only); followers_only_post MUST NOT be counted!
            trending = data["trending_topics"]
            self.assertLessEqual(len(trending), 5)
            trending_by_tag = {t["hashtag"]: t for t in trending}
            self.assertEqual(trending[0]["hashtag"], "#TậpLuyện")
            self.assertEqual(trending[0]["post_count_formatted"], "2 bài viết thảo luận")
            self.assertNotIn("#BíMậtRiêngTư", trending_by_tag)
            self.assertNotIn("#ĐãXóa", trending_by_tag)
            self.assertNotIn("#NhápẨn", trending_by_tag)

    def test_discover_topic_filters(self):
        with self._patch_db():
            # workout chip
            r_workout = self.client.get("/api/community/discover?topic=workout")
            self.assertEqual(r_workout.status_code, 200)
            self.assertEqual(r_workout.json()["active_topic"], "workout")
            self.assertEqual([i["post_id"] for i in r_workout.json()["grid_items"]], ["pub_workout_multi"])

            # meal chip
            r_meal = self.client.get("/api/community/discover?topic=meal")
            self.assertEqual(r_meal.status_code, 200)
            self.assertEqual([i["post_id"] for i in r_meal.json()["grid_items"]], ["pub_meal_single"])

            # recipe chip (matches #BữaĂn/#Mẹo OR caption containing "công thức")
            r_recipe = self.client.get("/api/community/discover?topic=recipe")
            self.assertEqual(r_recipe.status_code, 200)
            self.assertEqual(
                [i["post_id"] for i in r_recipe.json()["grid_items"]],
                ["pub_meal_single", "pub_journey_legacy"],
            )

            # qna chip
            r_qna = self.client.get("/api/community/discover?topic=qna")
            self.assertEqual(r_qna.status_code, 200)
            self.assertEqual([i["post_id"] for i in r_qna.json()["grid_items"]], ["pub_qa_photo"])

            # journey chip
            r_journey = self.client.get("/api/community/discover?topic=journey")
            self.assertEqual(r_journey.status_code, 200)
            self.assertEqual(
                [i["post_id"] for i in r_journey.json()["grid_items"]],
                ["pub_qa_photo", "pub_journey_legacy"],
            )

            # explicit hashtag filter (#TậpLuyện)
            r_hash = self.client.get("/api/community/discover", params={"topic": "#TậpLuyện"})
            self.assertEqual(r_hash.status_code, 200)
            self.assertEqual(r_hash.json()["active_topic"], "#TậpLuyện")
            self.assertEqual([i["post_id"] for i in r_hash.json()["grid_items"]], ["pub_workout_multi"])

    def test_discover_keyword_search_vietnamese_and_regex_injection_safe(self):
        with self._patch_db():
            # Vietnamese search matching qa_info.question
            r_vn_qa = self.client.get("/api/community/discover", params={"q": "bán marathon"})
            self.assertEqual(r_vn_qa.status_code, 200)
            self.assertEqual([i["post_id"] for i in r_vn_qa.json()["grid_items"]], ["pub_qa_photo"])

            # Vietnamese search matching attachment_snapshot.title & caption
            r_vn_meal = self.client.get("/api/community/discover", params={"q": "ỨC GÀ"})
            self.assertEqual(r_vn_meal.status_code, 200)
            self.assertEqual([i["post_id"] for i in r_vn_meal.json()["grid_items"]], ["pub_meal_single"])

            # Search matching hashtag and creator name/title
            r_tag = self.client.get("/api/community/discover", params={"q": "TậpLuyện"})
            self.assertEqual(r_tag.status_code, 200)
            self.assertEqual([i["post_id"] for i in r_tag.json()["grid_items"]], ["pub_workout_multi"])
            self.assertEqual([t["hashtag"] for t in r_tag.json()["trending_topics"]], ["#TậpLuyện"])

            # Search matching creator handle/title
            r_creator = self.client.get("/api/community/discover", params={"q": "eatclean"})
            self.assertEqual(r_creator.status_code, 200)
            creator_ids = [c["id"] for c in r_creator.json()["recommended_creators"]]
            self.assertEqual(creator_ids, [self.creator_mid_id])

            # Regex injection / ReDoS payload must be escaped via re.escape and return 200 safely
            malicious_q = "(((a+)+)+)$[invalid*regex?.*"
            r_redos = self.client.get("/api/community/discover", params={"q": malicious_q})
            self.assertEqual(r_redos.status_code, 200)
            self.assertEqual(r_redos.json()["grid_items"], [])
            self.assertEqual(r_redos.json()["trending_topics"], [])
            self.assertEqual(r_redos.json()["recommended_creators"], [])

            # Regex metacharacters in hashtag topic filter must also be escaped safely
            r_hash_redos = self.client.get("/api/community/discover", params={"topic": "#(a+)+$["})
            self.assertEqual(r_hash_redos.status_code, 200)
            self.assertEqual(r_hash_redos.json()["grid_items"], [])

    def test_discover_recommended_creators_sanitization_order_and_follow_state(self):
        with self._patch_db():
            res = self.client.get("/api/community/discover", headers=self.headers_viewer)
            self.assertEqual(res.status_code, 200)
            creators = res.json()["recommended_creators"]

            # Self (viewer_id) MUST be excluded
            creator_ids = [c["id"] for c in creators]
            self.assertNotIn(self.viewer_id, creator_ids)
            self.assertEqual(creator_ids, [self.creator_top_id, self.creator_mid_id, self.creator_low_id])

            # Follower counts & is_following accuracy
            self.assertEqual(creators[0]["follower_count"], 2)
            self.assertTrue(creators[0]["is_following"])
            self.assertEqual(creators[1]["follower_count"], 1)
            self.assertFalse(creators[1]["is_following"])
            self.assertEqual(creators[2]["follower_count"], 0)
            self.assertFalse(creators[2]["is_following"])

            # Strict security barrier: NO sensitive user fields leaked
            forbidden_fields = {"email", "password", "hashed_password", "health_stats", "health_metrics", "tokens"}
            for c in creators:
                self.assertFalse(forbidden_fields & set(c.keys()), f"Sensitive field leaked in creator: {c}")

            # Limit grid_items respected
            r_lim = self.client.get("/api/community/discover?limit=2")
            self.assertEqual(r_lim.status_code, 200)
            self.assertEqual(len(r_lim.json()["grid_items"]), 2)

    def test_publish_photo_post_multi_photo_1_to_10_and_validation(self):
        with self._patch_db():
            # 1 photo succeeds
            r_one = self.client.post(
                "/api/community/posts",
                headers={**self.headers_viewer, "X-Idempotency-Key": "wave3_photo_single_0001"},
                json={
                    "type": "photo",
                    "content": "1 ảnh bữa sáng",
                    "photo_urls": ["/static/community/single_1.jpg"],
                    "privacy": "public",
                    "topic": "#BữaĂn",
                    "allow_comments": True,
                },
            )
            self.assertEqual(r_one.status_code, 200, r_one.text)
            self.assertEqual(len(r_one.json()["photo_urls"]), 1)

            # 10 photos (mix of /static/community/ and https://) succeeds
            ten_urls = [f"/static/community/gallery_{i}.png" for i in range(1, 6)] + [
                f"https://cdn.example.com/photo_{i}.webp" for i in range(6, 11)
            ]
            r_ten = self.client.post(
                "/api/community/posts",
                headers={**self.headers_viewer, "X-Idempotency-Key": "wave3_photo_ten_0000002"},
                json={
                    "type": "photo",
                    "content": "Album 10 ảnh buổi tập cuối tuần",
                    "photo_urls": ten_urls,
                    "privacy": "public",
                    "topic": "#TậpLuyện",
                    "allow_comments": True,
                },
            )
            self.assertEqual(r_ten.status_code, 200, r_ten.text)
            self.assertEqual(r_ten.json()["photo_urls"], ten_urls)

            # Verify newly published 10-photo post shows up in Discover with has_multi_photo=True
            r_disc = self.client.get("/api/community/discover?topic=workout")
            self.assertEqual(r_disc.status_code, 200)
            top_grid = r_disc.json()["grid_items"][0]
            self.assertEqual(top_grid["post_id"], r_ten.json()["id"])
            self.assertTrue(top_grid["has_multi_photo"])

            # 0 photos -> 422
            r_zero = self.client.post(
                "/api/community/posts",
                headers={**self.headers_viewer, "X-Idempotency-Key": "wave3_photo_zero_000003"},
                json={
                    "type": "photo",
                    "content": "Không có ảnh",
                    "photo_urls": [],
                    "privacy": "public",
                    "topic": "#TậpLuyện",
                    "allow_comments": True,
                },
            )
            self.assertEqual(r_zero.status_code, 422)

            # 11 photos -> 422
            eleven_urls = [f"/static/community/over_{i}.jpg" for i in range(1, 12)]
            r_eleven = self.client.post(
                "/api/community/posts",
                headers={**self.headers_viewer, "X-Idempotency-Key": "wave3_photo_eleven_0004"},
                json={
                    "type": "photo",
                    "content": "11 ảnh vượt giới hạn",
                    "photo_urls": eleven_urls,
                    "privacy": "public",
                    "topic": "#TậpLuyện",
                    "allow_comments": True,
                },
            )
            self.assertEqual(r_eleven.status_code, 422)

            # Invalid URLs (empty string, javascript:, path traversal) -> 422
            for idx, bad_url in enumerate(
                ["", "   ", "javascript:alert(1)", "ftp://example.com/a.jpg", "/static/community/../secret.jpg"],
                start=5,
            ):
                r_bad = self.client.post(
                    "/api/community/posts",
                    headers={**self.headers_viewer, "X-Idempotency-Key": f"wave3_photo_bad_{idx:07d}"},
                    json={
                        "type": "photo",
                        "content": "Invalid URL",
                        "photo_urls": [bad_url],
                        "privacy": "public",
                        "topic": "#TậpLuyện",
                        "allow_comments": True,
                    },
                )
                self.assertEqual(r_bad.status_code, 422, f"Expected 422 for bad URL {bad_url!r}")


if __name__ == "__main__":
    unittest.main()
