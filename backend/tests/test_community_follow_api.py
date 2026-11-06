"""
Unit and Integration Contract Tests for Saman Community Follow Relationships & Following Feed.
Subsystem: Saman Community (JCOM-05-05).

Covers:
- Auth required: 401 unauthenticated rejected for Follow and Unfollow.
- Self-follow rejection: 400 for self-follow and self-unfollow.
- Target existence: 404 for non-existent target author.
- Idempotent PUT and DELETE (no duplicate relationship, count stability).
- Author Profile R09 public security projection (no email, password, tokens, or health metrics).
- Followers/Following lists R10 with stable pagination and viewer is_following status.
- Following feed: only returns posts of followed authors.
- Following feed audience: does NOT expose private posts of followed authors.
- Audience change: followers_only post viewable when followed, 404/hidden when unfollowed.
- Post detail & feed author projection has accurate is_following and authoritative counts.
"""

from datetime import datetime, timezone, timedelta
import unittest
from unittest.mock import patch, MagicMock
from bson import ObjectId
from fastapi.testclient import TestClient
import jwt
from pymongo.errors import DuplicateKeyError

from backend.main import app
from backend.routers.community import JWT_ALGORITHM, JWT_SECRET


class InMemoryFollowsCol:
    def __init__(self):
        self.docs = []

    def insert_one(self, doc):
        for d in self.docs:
            if d.get("follower_id") == doc.get("follower_id") and d.get("following_id") == doc.get("following_id"):
                raise DuplicateKeyError("E11000 duplicate key error")
        record = dict(doc)
        if "_id" not in record:
            record["_id"] = ObjectId()
        if "created_at" not in record:
            record["created_at"] = datetime.now(timezone.utc)
        self.docs.append(record)
        return type("InsertResult", (), {"inserted_id": record["_id"]})()

    def delete_one(self, filter_query):
        for idx, d in enumerate(self.docs):
            match = True
            for k, v in filter_query.items():
                if str(d.get(k)) != str(v):
                    match = False
                    break
            if match:
                self.docs.pop(idx)
                return type("DeleteResult", (), {"deleted_count": 1})()
        return type("DeleteResult", (), {"deleted_count": 0})()

    def find(self, filter_query, projection=None):
        results = []
        fid = filter_query.get("follower_id")
        tid = filter_query.get("following_id")

        for d in self.docs:
            if fid:
                if isinstance(fid, dict) and "$in" in fid:
                    if str(d.get("follower_id")) not in [str(x) for x in fid["$in"]]:
                        continue
                elif str(d.get("follower_id")) != str(fid):
                    continue
            if tid:
                if isinstance(tid, dict) and "$in" in tid:
                    if str(d.get("following_id")) not in [str(x) for x in tid["$in"]]:
                        continue
                elif str(d.get("following_id")) != str(tid):
                    continue
            results.append(dict(d))

        class MockCursor:
            def __init__(self, data):
                self._data = data

            def sort(self, sort_spec):
                return self

            def limit(self, count):
                return MockCursor(self._data[:count])

            def __iter__(self):
                return iter(self._data)

        return MockCursor(results)

    def find_one(self, filter_query):
        for d in self.docs:
            match = True
            for k, v in filter_query.items():
                if str(d.get(k)) != str(v):
                    match = False
                    break
            if match:
                return dict(d)
        return None

    def count_documents(self, filter_query):
        fid = filter_query.get("follower_id")
        tid = filter_query.get("following_id")
        c = 0
        for d in self.docs:
            if fid and str(d.get("follower_id")) != str(fid):
                continue
            if tid and str(d.get("following_id")) != str(tid):
                continue
            c += 1
        return c

    def aggregate(self, pipeline):
        match_stage = None
        group_stage = None
        for stage in pipeline:
            if "$match" in stage:
                match_stage = stage["$match"]
            elif "$group" in stage:
                group_stage = stage["$group"]

        matched = []
        for d in self.docs:
            if match_stage:
                target_field = "following_id" if "following_id" in match_stage else "follower_id"
                allowed = match_stage.get(target_field, {}).get("$in", [])
                if str(d.get(target_field)) not in [str(x) for x in allowed]:
                    continue
            matched.append(d)

        counts = {}
        for d in matched:
            k = str(d.get("following_id"))
            counts[k] = counts.get(k, 0) + 1

        return [{"_id": k, "count": v} for k, v in counts.items()]


class InMemoryPostsCol:
    def __init__(self, initial_posts=None):
        self.docs = list(initial_posts or [])

    def find_one(self, filter_query):
        for d in self.docs:
            if "$or" in filter_query:
                matched_or = False
                for sub in filter_query["$or"]:
                    match_sub = True
                    for k, v in sub.items():
                        if str(d.get(k)) != str(v):
                            match_sub = False
                            break
                    if match_sub:
                        matched_or = True
                        break
                if matched_or:
                    return dict(d)
            else:
                match = True
                for k, v in filter_query.items():
                    if str(d.get(k)) != str(v):
                        match = False
                        break
                if match:
                    return dict(d)
        return None

    def find(self, filter_query):
        results = []
        for d in self.docs:
            if d.get("is_deleted", False):
                continue
            if filter_query.get("type") and d.get("type") != filter_query.get("type"):
                continue

            if "$and" in filter_query:
                matches_and = True
                for sub in filter_query["$and"]:
                    if "$or" in sub:
                        or_pass = False
                        for cond in sub["$or"]:
                            if "author_id" in cond and "$in" in cond["author_id"]:
                                allowed = [str(x) for x in cond["author_id"]["$in"]]
                                if str(d.get("author_id")) in allowed or str((d.get("author") or {}).get("id")) in allowed:
                                    or_pass = True
                                    break
                        if not or_pass:
                            matches_and = False
                            break
                    if "privacy" in sub and "$in" in sub["privacy"]:
                        p = d.get("privacy", "public")
                        if p not in sub["privacy"]["$in"]:
                            matches_and = False
                            break
                if not matches_and:
                    continue
            elif "$or" in filter_query:
                matched_or = False
                for sub in filter_query["$or"]:
                    p = sub.get("privacy")
                    if p:
                        if isinstance(p, dict) and "$in" in p:
                            if d.get("privacy", "public") in p["$in"]:
                                matched_or = True
                                break
                        elif d.get("privacy") == p:
                            matched_or = True
                            break
                    aid = sub.get("author_id")
                    if aid and (str(d.get("author_id")) == str(aid) or str((d.get("author") or {}).get("id")) == str(aid)):
                        matched_or = True
                        break
                if not matched_or:
                    continue

            results.append(dict(d))

        class MockCursor:
            def __init__(self, data):
                self._data = data

            def sort(self, sort_spec):
                return self

            def limit(self, count):
                return MockCursor(self._data[:count])

            def __iter__(self):
                return iter(self._data)

        return MockCursor(results)

    def count_documents(self, filter_query):
        c = 0
        for d in self.docs:
            if d.get("is_deleted", False):
                continue
            c += 1
        return c


class InMemoryUsersCol:
    def __init__(self, users=None):
        self.docs = list(users or [])

    def find_one(self, filter_query):
        for u in self.docs:
            if "$or" in filter_query:
                for sub in filter_query["$or"]:
                    for k, v in sub.items():
                        if str(u.get(k)) == str(v):
                            return dict(u)
            else:
                match = True
                for k, v in filter_query.items():
                    if str(u.get(k)) != str(v):
                        match = False
                        break
                if match:
                    return dict(u)
        return None


class TestCommunityFollowApi(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

        self.user_a_id = "user_athlete_a_001"
        self.user_b_id = "user_athlete_b_002"
        self.user_c_id = "user_athlete_c_003"

        self.users_col = InMemoryUsersCol([
            {
                "_id": ObjectId(),
                "id": self.user_a_id,
                "email": "athlete_a@example.com",
                "name": "Athlete A",
                "title": "Người tập cơ bản",
                "avatar": "https://example.com/avatar_a.png",
                "custom_avatar_public_id": "secret_public_id_a",
                "hashed_password": "$2b$12$super_secret_hash_a",
                "health_metrics": {"weight": 70, "heart_rate": 65},
            },
            {
                "_id": ObjectId(),
                "id": self.user_b_id,
                "email": "athlete_b@example.com",
                "name": "HLV Long",
                "title": "HLV Thể hình",
                "avatar": "https://example.com/avatar_b.png",
                "is_verified": True,
                "custom_avatar_public_id": "secret_public_id_b",
                "hashed_password": "$2b$12$super_secret_hash_b",
                "health_metrics": {"weight": 82, "heart_rate": 55},
            },
            {
                "_id": ObjectId(),
                "id": self.user_c_id,
                "email": "athlete_c@example.com",
                "name": "Thanh Mai",
                "title": "HLV Yoga",
                "avatar": "https://example.com/avatar_c.png",
                "is_verified": True,
            },
        ])

        self.posts_col = InMemoryPostsCol([
            {
                "_id": ObjectId(),
                "id": "post_b_public",
                "author_id": self.user_b_id,
                "author": {"id": self.user_b_id, "name": "HLV Long", "is_verified": True},
                "caption": "Bài tập phát triển cơ vai bài bản",
                "privacy": "public",
                "status": "published",
                "type": "workout",
                "created_at": datetime.now(timezone.utc),
            },
            {
                "_id": ObjectId(),
                "id": "post_b_private",
                "author_id": self.user_b_id,
                "author": {"id": self.user_b_id, "name": "HLV Long", "is_verified": True},
                "caption": "Nhật ký riêng tư không chia sẻ",
                "privacy": "private",
                "status": "published",
                "type": "photo",
                "created_at": datetime.now(timezone.utc),
            },
            {
                "_id": ObjectId(),
                "id": "post_b_followers_only",
                "author_id": self.user_b_id,
                "author": {"id": self.user_b_id, "name": "HLV Long", "is_verified": True},
                "caption": "Giáo án chuyên sâu dành riêng cho Followers",
                "privacy": "followers_only",
                "status": "published",
                "type": "workout",
                "created_at": datetime.now(timezone.utc),
            },
            {
                "_id": ObjectId(),
                "id": "post_c_public",
                "author_id": self.user_c_id,
                "author": {"id": self.user_c_id, "name": "Thanh Mai", "is_verified": True},
                "caption": "Bài tập giãn cơ buổi sáng",
                "privacy": "public",
                "status": "published",
                "type": "workout",
                "created_at": datetime.now(timezone.utc),
            },
        ])

        self.follows_col = InMemoryFollowsCol()

    def _make_token(self, user_id: str, email: str, name: str = "User") -> str:
        payload = {
            "sub": user_id,
            "user_id": user_id,
            "email": email,
            "name": name,
        }
        return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

    def test_unauthenticated_follow_and_unfollow_rejected_401(self):
        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col):
            # PUT without token
            res = self.client.put(f"/api/community/authors/{self.user_b_id}/follow")
            self.assertEqual(res.status_code, 401)

            # DELETE without token
            res = self.client.delete(f"/api/community/authors/{self.user_b_id}/follow")
            self.assertEqual(res.status_code, 401)

    def test_self_follow_and_unfollow_rejected_400(self):
        token_a = self._make_token(self.user_a_id, "athlete_a@example.com")
        headers = {"Authorization": f"Bearer {token_a}"}

        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col):
            # Follow self by id
            res = self.client.put(f"/api/community/authors/{self.user_a_id}/follow", headers=headers)
            self.assertEqual(res.status_code, 400)
            self.assertIn("Cannot follow yourself", res.json()["detail"])

            # Follow self by 'me'
            res = self.client.put("/api/community/authors/me/follow", headers=headers)
            self.assertEqual(res.status_code, 400)

            # Unfollow self
            res = self.client.delete(f"/api/community/authors/{self.user_a_id}/follow", headers=headers)
            self.assertEqual(res.status_code, 400)

    def test_invalid_target_user_rejected_404(self):
        token_a = self._make_token(self.user_a_id, "athlete_a@example.com")
        headers = {"Authorization": f"Bearer {token_a}"}

        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col), \
             patch("backend.routers.community.get_community_posts_collection", return_value=self.posts_col):
            res = self.client.put("/api/community/authors/non_existent_ghost_user_999/follow", headers=headers)
            self.assertEqual(res.status_code, 404)
            self.assertIn("Author not found", res.json()["detail"])

    def test_idempotent_put_and_delete(self):
        token_a = self._make_token(self.user_a_id, "athlete_a@example.com")
        headers = {"Authorization": f"Bearer {token_a}"}

        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col), \
             patch("backend.routers.community.get_community_posts_collection", return_value=self.posts_col):
            # 1. First PUT Follow
            res1 = self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=headers)
            self.assertEqual(res1.status_code, 200)
            data1 = res1.json()
            self.assertTrue(data1["is_following"])
            self.assertEqual(data1["follower_count"], 1)

            # 2. Repeated PUT Follow (Idempotent)
            res2 = self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=headers)
            self.assertEqual(res2.status_code, 200)
            data2 = res2.json()
            self.assertTrue(data2["is_following"])
            self.assertEqual(data2["follower_count"], 1)
            # Ensure DB only has 1 record
            self.assertEqual(self.follows_col.count_documents({"following_id": self.user_b_id}), 1)

            # 3. First DELETE Unfollow
            res3 = self.client.delete(f"/api/community/authors/{self.user_b_id}/follow", headers=headers)
            self.assertEqual(res3.status_code, 200)
            data3 = res3.json()
            self.assertFalse(data3["is_following"])
            self.assertEqual(data3["follower_count"], 0)

            # 4. Repeated DELETE Unfollow (Idempotent)
            res4 = self.client.delete(f"/api/community/authors/{self.user_b_id}/follow", headers=headers)
            self.assertEqual(res4.status_code, 200)
            data4 = res4.json()
            self.assertFalse(data4["is_following"])
            self.assertEqual(data4["follower_count"], 0)
            self.assertEqual(self.follows_col.count_documents({"following_id": self.user_b_id}), 0)

    def test_author_profile_security_projection_and_counts(self):
        token_a = self._make_token(self.user_a_id, "athlete_a@example.com")
        headers = {"Authorization": f"Bearer {token_a}"}

        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col), \
             patch("backend.routers.community.get_community_posts_collection", return_value=self.posts_col):

            # Initial Profile of User B (not yet followed)
            res = self.client.get(f"/api/community/authors/{self.user_b_id}", headers=headers)
            self.assertEqual(res.status_code, 200)
            p = res.json()
            self.assertEqual(p["id"], self.user_b_id)
            self.assertEqual(p["name"], "HLV Long")
            self.assertEqual(p["follower_count"], 0)
            self.assertFalse(p["is_following"])

            # SECURITY CHECK: Sensitive fields must NOT exist in response!
            self.assertNotIn("email", p)
            self.assertNotIn("hashed_password", p)
            self.assertNotIn("password", p)
            self.assertNotIn("custom_avatar_public_id", p)
            self.assertNotIn("health_metrics", p)
            self.assertNotIn("token", p)

            # Follow B
            self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=headers)

            # Re-read Profile: follower_count = 1, is_following = True
            res_after = self.client.get(f"/api/community/authors/{self.user_b_id}", headers=headers)
            p_after = res_after.json()
            self.assertEqual(p_after["follower_count"], 1)
            self.assertTrue(p_after["is_following"])

    def test_followers_and_following_lists(self):
        token_a = self._make_token(self.user_a_id, "athlete_a@example.com")
        headers = {"Authorization": f"Bearer {token_a}"}

        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col), \
             patch("backend.routers.community.get_community_posts_collection", return_value=self.posts_col):

            # User A follows User B
            self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=headers)

            # Check User B's followers: should list User A
            res_b_followers = self.client.get(f"/api/community/authors/{self.user_b_id}/followers", headers=headers)
            self.assertEqual(res_b_followers.status_code, 200)
            data = res_b_followers.json()
            self.assertEqual(data["total_count"], 1)
            self.assertEqual(len(data["items"]), 1)
            f_item = data["items"][0]
            self.assertEqual(f_item["id"], self.user_a_id)
            self.assertEqual(f_item["name"], "Athlete A")
            # Security verification
            self.assertNotIn("email", f_item)
            self.assertNotIn("hashed_password", f_item)

            # Check User A's following: should list User B
            res_a_following = self.client.get(f"/api/community/authors/{self.user_a_id}/following", headers=headers)
            self.assertEqual(res_a_following.status_code, 200)
            data_following = res_a_following.json()
            self.assertEqual(data_following["total_count"], 1)
            self.assertEqual(data_following["items"][0]["id"], self.user_b_id)
            self.assertTrue(data_following["items"][0]["is_following"])

    def test_following_feed_and_private_posts_isolation(self):
        token_a = self._make_token(self.user_a_id, "athlete_a@example.com")
        headers = {"Authorization": f"Bearer {token_a}"}

        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col), \
             patch("backend.routers.community.get_community_posts_collection", return_value=self.posts_col):

            # 1. Before User A follows anyone: Following feed is empty
            res = self.client.get("/api/community/feed?tab=following", headers=headers)
            self.assertEqual(res.status_code, 200)
            self.assertEqual(len(res.json()["items"]), 0)

            # 2. User A follows User B (not C)
            self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=headers)

            # 3. Following feed now contains User B's posts, but:
            # - Must contain post_b_public
            # - Must NOT contain post_c_public (not followed)
            # - Must NOT contain post_b_private (Follow does not grant access to private posts!)
            res = self.client.get("/api/community/feed?tab=following", headers=headers)
            self.assertEqual(res.status_code, 200)
            post_ids = [p["id"] for p in res.json()["items"]]
            self.assertIn("post_b_public", post_ids)
            self.assertNotIn("post_c_public", post_ids)
            self.assertNotIn("post_b_private", post_ids)

    def test_followers_only_audience_lifecycle(self):
        token_a = self._make_token(self.user_a_id, "athlete_a@example.com")
        headers = {"Authorization": f"Bearer {token_a}"}

        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col), \
             patch("backend.routers.community.get_community_posts_collection", return_value=self.posts_col):

            # Phase 1: Before Follow
            # Detail for followers_only post returns 404 (fail-closed)
            res_det = self.client.get("/api/community/posts/post_b_followers_only", headers=headers)
            self.assertEqual(res_det.status_code, 404)

            # Phase 2: Follow User B
            self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=headers)

            # Detail now returns 200 OK!
            res_det_after = self.client.get("/api/community/posts/post_b_followers_only", headers=headers)
            self.assertEqual(res_det_after.status_code, 200)
            self.assertEqual(res_det_after.json()["id"], "post_b_followers_only")

            # Following feed returns followers_only post
            res_feed = self.client.get("/api/community/feed?tab=following", headers=headers)
            feed_ids = [p["id"] for p in res_feed.json()["items"]]
            self.assertIn("post_b_followers_only", feed_ids)

            # Phase 3: Unfollow User B
            self.client.delete(f"/api/community/authors/{self.user_b_id}/follow", headers=headers)

            # Detail immediately returns 404 again!
            res_det_unfollowed = self.client.get("/api/community/posts/post_b_followers_only", headers=headers)
            self.assertEqual(res_det_unfollowed.status_code, 404)

            # Following feed no longer has the post
            res_feed_unfollowed = self.client.get("/api/community/feed?tab=following", headers=headers)
            feed_ids_unfollowed = [p["id"] for p in res_feed_unfollowed.json()["items"]]
            self.assertNotIn("post_b_followers_only", feed_ids_unfollowed)

            # Public post must still be accessible outside Following feed
            res_pub = self.client.get("/api/community/posts/post_b_public", headers=headers)
            self.assertEqual(res_pub.status_code, 200)

            # Private post must NEVER be accessible to follower
            res_priv = self.client.get("/api/community/posts/post_b_private", headers=headers)
            self.assertEqual(res_priv.status_code, 404)

    def test_jwt_security_token_expiration_and_tampering(self):
        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col), \
             patch("backend.routers.community.get_community_posts_collection", return_value=self.posts_col):

            # 1. Expired token -> 401
            expired_payload = {
                "sub": self.user_a_id,
                "email": "athlete_a@example.com",
                "exp": datetime.now(timezone.utc) - timedelta(minutes=10),
            }
            expired_token = jwt.encode(expired_payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
            res_exp = self.client.get("/api/community/feed?tab=for_you", headers={"Authorization": f"Bearer {expired_token}"})
            self.assertEqual(res_exp.status_code, 401)
            self.assertIn("Expired", res_exp.json().get("detail", ""))

            # 2. Tampered signature -> 401
            tampered_token = jwt.encode(expired_payload, "completely-wrong-tampered-secret", algorithm=JWT_ALGORITHM)
            res_tamp = self.client.get("/api/community/feed?tab=for_you", headers={"Authorization": f"Bearer {tampered_token}"})
            self.assertEqual(res_tamp.status_code, 401)
            self.assertIn("Invalid", res_tamp.json().get("detail", ""))

            # 3. Missing token on mutation -> 401
            res_no_tok = self.client.put(f"/api/community/authors/{self.user_b_id}/follow")
            self.assertEqual(res_no_tok.status_code, 401)

            # 4. Anonymous public read -> 200, no private leak
            res_anon = self.client.get("/api/community/feed?tab=for_you")
            self.assertEqual(res_anon.status_code, 200)
            for item in res_anon.json().get("items", []):
                self.assertNotEqual(item.get("privacy"), "private")

    def test_one_way_relation_viewer_b_perspective(self):
        token_a = self._make_token(self.user_a_id, "athlete_a@example.com")
        token_b = self._make_token(self.user_b_id, "athlete_b@example.com")
        headers_a = {"Authorization": f"Bearer {token_a}"}
        headers_b = {"Authorization": f"Bearer {token_b}"}

        with patch("backend.routers.community.get_community_follows_collection", return_value=self.follows_col), \
             patch("backend.routers.community.get_users_collection", return_value=self.users_col), \
             patch("backend.routers.community.get_community_posts_collection", return_value=self.posts_col):

            # Clear DB
            self.follows_col.docs = []

            # 1. Athlete A follows Athlete B
            self.client.put(f"/api/community/authors/{self.user_b_id}/follow", headers=headers_a)

            # DB assertion: Only 1 relation exists (A -> B)
            self.assertEqual(self.follows_col.count_documents({}), 1)
            db_doc = self.follows_col.find_one({"follower_id": self.user_a_id, "following_id": self.user_b_id})
            self.assertIsNotNone(db_doc)

            # DB assertion: Zero relation exists for B -> A
            b_to_a = self.follows_col.find_one({"follower_id": self.user_b_id, "following_id": self.user_a_id})
            self.assertIsNone(b_to_a, "A following B must NEVER reciprocate as B following A")

            # 2. Athlete B perspective:
            # - B views self: follower_count = 1, following_count = 0
            res_b_self = self.client.get(f"/api/community/authors/{self.user_b_id}", headers=headers_b)
            self.assertEqual(res_b_self.status_code, 200)
            self.assertEqual(res_b_self.json()["follower_count"], 1)
            self.assertEqual(res_b_self.json()["following_count"], 0)

            # - B views A: is_following is FALSE
            res_b_view_a = self.client.get(f"/api/community/authors/{self.user_a_id}", headers=headers_b)
            self.assertEqual(res_b_view_a.status_code, 200)
            self.assertFalse(res_b_view_a.json()["is_following"], "Viewer B does NOT follow A")

            # - B Following Feed is completely empty
            res_b_feed = self.client.get("/api/community/feed?tab=following", headers=headers_b)
            self.assertEqual(res_b_feed.status_code, 200)
            self.assertEqual(len(res_b_feed.json()["items"]), 0)


if __name__ == "__main__":
    unittest.main()

