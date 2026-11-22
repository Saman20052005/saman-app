"""
Comprehensive Contract & Integration Tests for Saman Community Wave 2 Backend API.

Covers:
- MongoDB index definitions in ensure_community_indexes (community_notifications, community_drafts).
- Auto-notification triggers for like, comment, reply, Q&A answer, and follow:
  - No self-notifications.
  - No duplicates on idempotent retries / replays.
  - Reply notifies both post owner and parent comment owner when distinct, without double-notifying post owner.
- Notifications endpoints:
  - Auth 401 enforcement.
  - Filters: all | interactions | system.
  - Cursor pagination (created_at DESC, _id DESC).
  - PATCH /notifications/{id}/read & POST /notifications/read-all.
  - Cross-user 404 isolation.
- Drafts CRUD:
  - Auth 401 enforcement, extra="forbid" 422 validation.
  - POST /drafts (auto ObjectId and client draft_id), PUT /drafts/{id} upsert, GET /drafts sorted updated_at DESC, DELETE /drafts/{id}.
  - Cross-user isolation (User B cannot read/update/delete User A's drafts -> 404).
- Author profile stats & privacy:
  - GET /authors/me (401 when anonymous, full safe projection when authenticated).
  - Real stats: post_count, workout_post_count, meal_post_count (type=meal, nutrition_info, attachment_snapshot.kind=meal),
    total_likes_received (non-deleted posts only).
  - GET /authors/{id}/posts: privacy enforcement (public, followers_only, private, deleted), tabs (all, workout, meal, qa), cursor pagination.
  - PATCH /profile: handle normalization (@strip, lowercase), 409 duplicate handle, <=3 interest_topics, author sync on posts, zero sensitive field leakage.
"""

from datetime import datetime, timedelta, timezone
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
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def _set_nested(doc, dotted_key, value):
    parts = dotted_key.split(".")
    cur = doc
    for part in parts[:-1]:
        if part not in cur or not isinstance(cur[part], dict):
            cur[part] = {}
        cur = cur[part]
    cur[parts[-1]] = value


def _normalize_dt(val):
    if isinstance(val, datetime) and val.tzinfo is None:
        return val.replace(tzinfo=timezone.utc)
    return val


def _matches_cond(val, cond):
    if isinstance(cond, dict):
        for op, expected in cond.items():
            if op == "$ne":
                if val == expected:
                    return False
            elif op == "$in":
                if val not in expected and str(val) not in [str(x) for x in expected if x is not None]:
                    if not (val is None and None in expected):
                        return False
            elif op == "$lt":
                if val is None:
                    return False
                if _normalize_dt(val) >= _normalize_dt(expected):
                    return False
            elif op == "$gt":
                if val is None:
                    return False
                if _normalize_dt(val) <= _normalize_dt(expected):
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
        if isinstance(key_or_list, str):
            specs = [(key_or_list, direction)]
        else:
            specs = list(key_or_list)

        result = list(self._docs)
        for field, order in reversed(specs):
            result.sort(
                key=lambda d: _normalize_dt(_get_nested(d, field)) if _get_nested(d, field) is not None else datetime.min.replace(tzinfo=timezone.utc),
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
        matched = [d for d in self.docs if _matches_query(d, query or {})]
        return _InMemoryCursor(matched)

    def count_documents(self, query=None):
        return sum(1 for d in self.docs if _matches_query(d, query or {}))

    def _apply_update(self, doc, update):
        if "$set" in update:
            for k, v in update["$set"].items():
                if "." in k:
                    _set_nested(doc, k, v)
                else:
                    doc[k] = v
        if "$inc" in update:
            for k, v in update["$inc"].items():
                doc[k] = doc.get(k, 0) + v
        if "$addToSet" in update:
            for k, v in update["$addToSet"].items():
                arr = doc.setdefault(k, [])
                if v not in arr:
                    arr.append(v)
        if "$pull" in update:
            for k, v in update["$pull"].items():
                if k in doc and v in doc[k]:
                    doc[k].remove(v)

    def update_one(self, query, update):
        for d in self.docs:
            if _matches_query(d, query):
                self._apply_update(d, update)
                return type("UpdateResult", (), {"matched_count": 1, "modified_count": 1})()
        return type("UpdateResult", (), {"matched_count": 0, "modified_count": 0})()

    def update_many(self, query, update):
        matched = 0
        for d in self.docs:
            if _matches_query(d, query):
                self._apply_update(d, update)
                matched += 1
        return type("UpdateResult", (), {"matched_count": matched, "modified_count": matched})()

    def delete_one(self, query):
        for idx, d in enumerate(self.docs):
            if _matches_query(d, query):
                self.docs.pop(idx)
                return type("DeleteResult", (), {"deleted_count": 1})()
        return type("DeleteResult", (), {"deleted_count": 0})()

    def aggregate(self, pipeline):
        docs = list(self.docs)
        for stage in pipeline:
            if "$match" in stage:
                docs = [d for d in docs if _matches_query(d, stage["$match"])]
            elif "$group" in stage:
                group_spec = stage["$group"]
                id_expr = group_spec["_id"]
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


class TestCommunityWave2Api(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.fake_db = InMemoryDatabase()
        ensure_community_indexes(self.fake_db)

        self.user_a_oid = ObjectId()
        self.user_b_oid = ObjectId()
        self.user_c_oid = ObjectId()
        self.user_a_id = str(self.user_a_oid)
        self.user_b_id = str(self.user_b_oid)
        self.user_c_id = str(self.user_c_oid)

        self.fake_db["users"].insert_one({
            "_id": self.user_a_oid,
            "email": "user_a@saman.test",
            "name": "Minh Tuấn",
            "handle": "minhtuan",
            "title": "HLV Sức Mạnh",
            "bio": "Tập đều mỗi sáng",
            "interest_topics": ["#TậpLuyện", "#BữaĂn"],
            "avatar_url": "https://example.com/a.jpg",
            "is_verified": True,
            "hashed_password": "secret_hash_never_expose",
            "health_metrics": {"weight": 72, "body_fat": 14},
        })
        self.fake_db["users"].insert_one({
            "_id": self.user_b_oid,
            "email": "user_b@saman.test",
            "name": "Lan Anh",
            "handle": "lananh",
            "title": "Runner",
            "avatar_url": "https://example.com/b.jpg",
            "hashed_password": "secret_hash_b",
        })
        self.fake_db["users"].insert_one({
            "_id": self.user_c_oid,
            "email": "user_c@saman.test",
            "name": "Hoàng Nam",
            "title": "Calisthenics",
            "avatar_url": "https://example.com/c.jpg",
            "hashed_password": "secret_hash_c",
        })

        self.headers_a = self._auth_headers(self.user_a_id, "user_a@saman.test", "Minh Tuấn")
        self.headers_b = self._auth_headers(self.user_b_id, "user_b@saman.test", "Lan Anh")
        self.headers_c = self._auth_headers(self.user_c_id, "user_c@saman.test", "Hoàng Nam")

        base_t = datetime.now(timezone.utc) - timedelta(hours=5)
        self.post_workout_pub = {
            "_id": ObjectId(),
            "id": "post_a_workout_pub",
            "author_id": self.user_a_id,
            "author": {"id": self.user_a_id, "name": "Minh Tuấn", "title": "HLV Sức Mạnh", "avatar_url": "https://example.com/a.jpg"},
            "type": "workout",
            "caption": "Buổi tập Pull Day 50 phút",
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "allow_comments": True,
            "created_at": base_t + timedelta(minutes=10),
        }
        self.post_meal_followers = {
            "_id": ObjectId(),
            "id": "post_a_meal_followers",
            "author_id": self.user_a_id,
            "author": {"id": self.user_a_id, "name": "Minh Tuấn"},
            "type": "meal",
            "caption": "Cơm gạo lứt ức gà áp chảo",
            "privacy": "followers_only",
            "status": "published",
            "is_deleted": False,
            "allow_comments": True,
            "created_at": base_t + timedelta(minutes=20),
        }
        self.post_photo_with_nutrition = {
            "_id": ObjectId(),
            "id": "post_a_photo_nutr",
            "author_id": self.user_a_id,
            "author": {"id": self.user_a_id, "name": "Minh Tuấn"},
            "type": "photo",
            "caption": "Bữa sáng giàu đạm",
            "nutrition_info": {"calories": 480, "protein_grams": 38.0},
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "allow_comments": True,
            "created_at": base_t + timedelta(minutes=30),
        }
        self.post_snapshot_meal_private = {
            "_id": ObjectId(),
            "id": "post_a_meal_private",
            "author_id": self.user_a_id,
            "author": {"id": self.user_a_id, "name": "Minh Tuấn"},
            "type": "photo",
            "caption": "Nhật ký macro riêng tư",
            "attachment_snapshot": {"kind": "meal", "title": "Dinner"},
            "privacy": "private",
            "status": "published",
            "is_deleted": False,
            "allow_comments": True,
            "created_at": base_t + timedelta(minutes=40),
        }
        self.post_qa_pub = {
            "_id": ObjectId(),
            "id": "post_a_qa_pub",
            "author_id": self.user_a_id,
            "author": {"id": self.user_a_id, "name": "Minh Tuấn"},
            "type": "qa",
            "caption": "",
            "qa_info": {"question": "Nên uống Creatine lúc nào?", "category_tag": "HỎI ĐÁP • DINH DƯỠNG"},
            "privacy": "public",
            "status": "published",
            "is_deleted": False,
            "created_at": base_t + timedelta(minutes=50),
        }
        self.post_deleted = {
            "_id": ObjectId(),
            "id": "post_a_deleted",
            "author_id": self.user_a_id,
            "author": {"id": self.user_a_id, "name": "Minh Tuấn"},
            "type": "workout",
            "caption": "Đã xóa",
            "privacy": "public",
            "status": "published",
            "is_deleted": True,
            "created_at": base_t + timedelta(minutes=60),
        }
        for p in [
            self.post_workout_pub,
            self.post_meal_followers,
            self.post_photo_with_nutrition,
            self.post_snapshot_meal_private,
            self.post_qa_pub,
            self.post_deleted,
        ]:
            self.fake_db["community_posts"].insert_one(p)

    def _auth_headers(self, user_id: str, email: str, name: str):
        token = jwt.encode(
            {"sub": user_id, "user_id": user_id, "email": email, "name": name},
            JWT_SECRET,
            algorithm=JWT_ALGORITHM,
        )
        return {"Authorization": f"Bearer {token}"}

    def _patch_db(self):
        return patch("backend.routers.community.db", self.fake_db)

    # 1. Index verification
    def test_ensure_community_indexes_wave2_collections(self):
        fresh_db = InMemoryDatabase()
        created = ensure_community_indexes(fresh_db)

        self.assertIn("community_notifications", created)
        self.assertIn("idx_notifications_recipient_created", created["community_notifications"])
        self.assertIn("idx_notifications_recipient_unread", created["community_notifications"])
        notif_idx = fresh_db["community_notifications"].index_information()
        self.assertEqual(
            notif_idx["idx_notifications_recipient_created"]["key"],
            [("recipient_id", 1), ("created_at", -1), ("_id", -1)],
        )
        self.assertEqual(
            notif_idx["idx_notifications_recipient_unread"]["key"],
            [("recipient_id", 1), ("is_read", 1)],
        )

        self.assertIn("community_drafts", created)
        self.assertIn("idx_drafts_user_updated", created["community_drafts"])
        draft_idx = fresh_db["community_drafts"].index_information()
        self.assertEqual(
            draft_idx["idx_drafts_user_updated"]["key"],
            [("user_id", 1), ("updated_at", -1), ("_id", -1)],
        )

    # 2. Auto-notifications: like, comment, reply, answer, follow + no self-notify + no duplicates
    def test_auto_notifications_like_and_idempotency_and_self(self):
        with self._patch_db():
            # Self-like -> NO notification
            r_self = self.client.put("/api/community/posts/post_a_workout_pub/like", headers=self.headers_a)
            self.assertEqual(r_self.status_code, 200)
            self.assertEqual(self.fake_db["community_notifications"].count_documents({}), 0)

            # User B likes User A's post -> 1 notification
            r1 = self.client.put("/api/community/posts/post_a_workout_pub/like", headers=self.headers_b)
            self.assertEqual(r1.status_code, 200)
            # Duplicate like by User B -> still 1 notification
            r2 = self.client.put("/api/community/posts/post_a_workout_pub/like", headers=self.headers_b)
            self.assertEqual(r2.status_code, 200)

            res = self.client.get("/api/community/notifications", headers=self.headers_a)
            self.assertEqual(res.status_code, 200)
            data = res.json()
            self.assertEqual(data["unread_count"], 1)
            self.assertEqual(len(data["items"]), 1)
            n = data["items"][0]
            self.assertEqual(n["type"], "like")
            self.assertEqual(n["actor_id"], self.user_b_id)
            self.assertEqual(n["actor_name"], "Lan Anh")
            self.assertEqual(n["action_text"], "đã thích bài viết của bạn")
            self.assertEqual(n["target_post_id"], "post_a_workout_pub")
            self.assertTrue(n["is_unread"])

    def test_auto_notifications_comment_reply_and_idempotent_replay(self):
        with self._patch_db():
            # User B comments on User A's post
            idem_b = "idem_cmt_user_b_00001"
            r_b1 = self.client.post(
                "/api/community/posts/post_a_workout_pub/comments",
                json={"content": "Buổi tập chất lượng quá!"},
                headers={**self.headers_b, "X-Idempotency-Key": idem_b},
            )
            self.assertEqual(r_b1.status_code, 200)
            parent_cmt_id = r_b1.json()["comment"]["id"]

            # Replay same idempotency key -> no duplicate notification
            r_b2 = self.client.post(
                "/api/community/posts/post_a_workout_pub/comments",
                json={"content": "Buổi tập chất lượng quá!"},
                headers={**self.headers_b, "X-Idempotency-Key": idem_b},
            )
            self.assertEqual(r_b2.status_code, 200)
            self.assertEqual(
                self.fake_db["community_notifications"].count_documents({"recipient_id": self.user_a_id}),
                1,
            )

            # User C replies to User B's comment on User A's post
            # -> User A gets post-comment notification; User B gets reply notification
            r_c = self.client.post(
                "/api/community/posts/post_a_workout_pub/comments",
                json={"content": "Chuẩn luôn bạn ơi", "parent_comment_id": parent_cmt_id},
                headers={**self.headers_c, "X-Idempotency-Key": "idem_cmt_user_c_00002"},
            )
            self.assertEqual(r_c.status_code, 200)

            notifs_a = self.client.get("/api/community/notifications", headers=self.headers_a).json()["items"]
            self.assertEqual(len(notifs_a), 2)
            self.assertEqual(notifs_a[0]["action_text"], "đã bình luận về bài viết của bạn")
            self.assertEqual(notifs_a[0]["actor_id"], self.user_c_id)

            notifs_b = self.client.get("/api/community/notifications", headers=self.headers_b).json()["items"]
            self.assertEqual(len(notifs_b), 1)
            self.assertEqual(notifs_b[0]["type"], "comment")
            self.assertEqual(notifs_b[0]["actor_id"], self.user_c_id)
            self.assertEqual(notifs_b[0]["action_text"], "đã trả lời bình luận của bạn")

            # User A (post author) replies to User B's comment -> only User B notified, NOT User A
            r_a_reply = self.client.post(
                "/api/community/posts/post_a_workout_pub/comments",
                json={"content": "Cảm ơn Lan Anh nhé!", "parent_comment_id": parent_cmt_id},
                headers={**self.headers_a, "X-Idempotency-Key": "idem_cmt_user_a_00003"},
            )
            self.assertEqual(r_a_reply.status_code, 200)
            self.assertEqual(
                self.fake_db["community_notifications"].count_documents({"recipient_id": self.user_a_id}),
                2,
            )
            self.assertEqual(
                self.fake_db["community_notifications"].count_documents({"recipient_id": self.user_b_id}),
                2,
            )

            # User A creates root comment, User C replies to User A -> User A gets ONLY 1 new notification (not 2)
            r_a_root = self.client.post(
                "/api/community/posts/post_a_workout_pub/comments",
                json={"content": "Mọi người nhớ khởi động kỹ"},
                headers={**self.headers_a, "X-Idempotency-Key": "idem_cmt_user_a_00004"},
            )
            self.assertEqual(r_a_root.status_code, 200)
            a_root_id = r_a_root.json()["comment"]["id"]

            r_c_reply_a = self.client.post(
                "/api/community/posts/post_a_workout_pub/comments",
                json={"content": "Đã ghi chú ạ", "parent_comment_id": a_root_id},
                headers={**self.headers_c, "X-Idempotency-Key": "idem_cmt_user_c_00005"},
            )
            self.assertEqual(r_c_reply_a.status_code, 200)
            # Was 2, now 3 (not 4)
            self.assertEqual(
                self.fake_db["community_notifications"].count_documents({"recipient_id": self.user_a_id}),
                3,
            )

    def test_auto_notifications_answer_and_follow(self):
        with self._patch_db():
            # Self-answer -> no notification
            r_self_ans = self.client.post(
                "/api/community/questions/post_a_qa_pub/answers",
                json={"content": "Bổ sung thêm bối cảnh"},
                headers={**self.headers_a, "X-Idempotency-Key": "idem_ans_self_a_00001"},
            )
            self.assertEqual(r_self_ans.status_code, 200)
            self.assertEqual(self.fake_db["community_notifications"].count_documents({}), 0)

            # User B answers User A's question
            idem_ans = "idem_ans_user_b_00002"
            r1 = self.client.post(
                "/api/community/questions/post_a_qa_pub/answers",
                json={"content": "Uống 5g mỗi ngày lúc nào cũng được, ưu tiên sau tập."},
                headers={**self.headers_b, "X-Idempotency-Key": idem_ans},
            )
            self.assertEqual(r1.status_code, 200)
            # Replay same key -> no duplicate notification
            r2 = self.client.post(
                "/api/community/questions/post_a_qa_pub/answers",
                json={"content": "Uống 5g mỗi ngày lúc nào cũng được, ưu tiên sau tập."},
                headers={**self.headers_b, "X-Idempotency-Key": idem_ans},
            )
            self.assertEqual(r2.status_code, 200)

            # User B follows User A twice -> only 1 follow notification
            rf1 = self.client.put(f"/api/community/authors/{self.user_a_id}/follow", headers=self.headers_b)
            self.assertEqual(rf1.status_code, 200)
            rf2 = self.client.put(f"/api/community/authors/{self.user_a_id}/follow", headers=self.headers_b)
            self.assertEqual(rf2.status_code, 200)

            notifs_a = self.client.get("/api/community/notifications", headers=self.headers_a).json()["items"]
            self.assertEqual(len(notifs_a), 2)
            by_type = {n["type"]: n for n in notifs_a}
            self.assertIn("answer", by_type)
            self.assertEqual(by_type["answer"]["action_text"], "đã trả lời câu hỏi của bạn")
            self.assertEqual(by_type["answer"]["target_post_type"], "qa")
            self.assertEqual(by_type["answer"]["target_post_id"], "post_a_qa_pub")

            self.assertIn("follow", by_type)
            self.assertEqual(by_type["follow"]["action_text"], "đã bắt đầu theo dõi bạn")
            self.assertEqual(by_type["follow"]["actor_id"], self.user_b_id)

    # 3. Notifications filters, pagination, mark-read, read-all, cross-user 404 isolation
    def test_notifications_filters_pagination_read_and_isolation(self):
        with self._patch_db():
            # Unauthenticated -> 401
            self.assertEqual(self.client.get("/api/community/notifications").status_code, 401)
            self.assertEqual(self.client.patch("/api/community/notifications/abc/read").status_code, 401)
            self.assertEqual(self.client.post("/api/community/notifications/read-all").status_code, 401)

            t0 = datetime.now(timezone.utc) - timedelta(minutes=30)
            n1_id = ObjectId()
            n2_id = ObjectId()
            n3_id = ObjectId()
            n_b_id = ObjectId()
            self.fake_db["community_notifications"].insert_one({
                "_id": n1_id,
                "recipient_id": self.user_a_id,
                "actor_id": self.user_b_id,
                "actor_name": "Lan Anh",
                "action_text": "đã thích bài viết của bạn",
                "type": "like",
                "is_read": False,
                "created_at": t0 + timedelta(minutes=1),
            })
            self.fake_db["community_notifications"].insert_one({
                "_id": n2_id,
                "recipient_id": self.user_a_id,
                "actor_id": None,
                "actor_name": "Saman Coach",
                "action_text": "Bạn vừa đạt chuỗi 7 ngày liên tiếp!",
                "type": "system",
                "is_read": False,
                "created_at": t0 + timedelta(minutes=2),
            })
            self.fake_db["community_notifications"].insert_one({
                "_id": n3_id,
                "recipient_id": self.user_a_id,
                "actor_id": self.user_c_id,
                "actor_name": "Hoàng Nam",
                "action_text": "đã bắt đầu theo dõi bạn",
                "type": "follow",
                "is_read": False,
                "created_at": t0 + timedelta(minutes=3),
            })
            self.fake_db["community_notifications"].insert_one({
                "_id": n_b_id,
                "recipient_id": self.user_b_id,
                "actor_id": self.user_a_id,
                "actor_name": "Minh Tuấn",
                "action_text": "đã thích bài viết của bạn",
                "type": "like",
                "is_read": False,
                "created_at": t0 + timedelta(minutes=4),
            })

            # Filter interactions
            res_inter = self.client.get("/api/community/notifications?filter=interactions", headers=self.headers_a)
            self.assertEqual(res_inter.status_code, 200)
            d_inter = res_inter.json()
            self.assertEqual(d_inter["unread_count"], 3)
            self.assertEqual([i["type"] for i in d_inter["items"]], ["follow", "like"])

            # Filter system
            res_sys = self.client.get("/api/community/notifications?filter=system", headers=self.headers_a)
            self.assertEqual(res_sys.status_code, 200)
            self.assertEqual([i["type"] for i in res_sys.json()["items"]], ["system"])

            # Invalid filter -> 400
            self.assertEqual(
                self.client.get("/api/community/notifications?filter=unknown", headers=self.headers_a).status_code,
                400,
            )

            # Cursor pagination
            p1 = self.client.get("/api/community/notifications?limit=2", headers=self.headers_a).json()
            self.assertEqual(len(p1["items"]), 2)
            self.assertIsNotNone(p1["next_cursor"])
            p2 = self.client.get(
                f"/api/community/notifications?limit=2&cursor={p1['next_cursor']}",
                headers=self.headers_a,
            ).json()
            self.assertEqual(len(p2["items"]), 1)
            self.assertIsNone(p2["next_cursor"])
            seen_ids = [i["id"] for i in p1["items"]] + [i["id"] for i in p2["items"]]
            self.assertEqual(seen_ids, [str(n3_id), str(n2_id), str(n1_id)])

            # Cross-user isolation: User B cannot mark User A's notification read -> 404
            r_cross = self.client.patch(
                f"/api/community/notifications/{n1_id}/read",
                headers=self.headers_b,
            )
            self.assertEqual(r_cross.status_code, 404)

            # Owner marks one read
            r_read = self.client.patch(
                f"/api/community/notifications/{n1_id}/read",
                headers=self.headers_a,
            )
            self.assertEqual(r_read.status_code, 200)
            self.assertFalse(r_read.json()["is_unread"])
            self.assertEqual(r_read.json()["unread_count"], 2)

            # Owner read-all
            r_all = self.client.post("/api/community/notifications/read-all", headers=self.headers_a)
            self.assertEqual(r_all.status_code, 200)
            self.assertEqual(r_all.json()["unread_count"], 0)

            # User B's unread count unaffected
            res_b = self.client.get("/api/community/notifications", headers=self.headers_b).json()
            self.assertEqual(res_b["unread_count"], 1)

    # 4. Drafts CRUD & cross-user isolation
    def test_drafts_crud_and_cross_user_isolation(self):
        with self._patch_db():
            # Auth required
            self.assertEqual(self.client.get("/api/community/drafts").status_code, 401)
            self.assertEqual(self.client.post("/api/community/drafts", json={}).status_code, 401)

            # extra="forbid" validation
            r_extra = self.client.post(
                "/api/community/drafts",
                json={"caption": "hi", "unexpected_field": 123},
                headers=self.headers_a,
            )
            self.assertEqual(r_extra.status_code, 422)

            # Create draft with client id
            r_create = self.client.post(
                "/api/community/drafts",
                json={
                    "id": "draft_123",
                    "caption": "Nháp bữa trưa",
                    "media_urls": ["/static/community/img1.jpg"],
                    "topic": "#BữaĂn",
                    "allow_comments": True,
                },
                headers=self.headers_a,
            )
            self.assertEqual(r_create.status_code, 200)
            d1 = r_create.json()
            self.assertEqual(d1["id"], "draft_123")
            self.assertEqual(d1["user_id"], self.user_a_id)
            self.assertEqual(d1["caption"], "Nháp bữa trưa")

            # Create second draft without id (auto ObjectId)
            r_auto = self.client.post(
                "/api/community/drafts",
                json={"caption": "Nháp Q&A", "question_title": "Tập sáng hay tối?"},
                headers=self.headers_a,
            )
            self.assertEqual(r_auto.status_code, 200)
            auto_id = r_auto.json()["id"]
            self.assertTrue(ObjectId.is_valid(auto_id))

            # PUT update existing client draft_123
            r_upd = self.client.put(
                "/api/community/drafts/draft_123",
                json={"caption": "Nháp bữa trưa (đã chỉnh)", "rotation": 90, "brightness": 0.2},
                headers=self.headers_a,
            )
            self.assertEqual(r_upd.status_code, 200)
            self.assertEqual(r_upd.json()["caption"], "Nháp bữa trưa (đã chỉnh)")
            self.assertEqual(r_upd.json()["rotation"], 90)

            # PUT upsert new id
            r_upsert = self.client.put(
                "/api/community/drafts/draft_new_456",
                json={"caption": "Tạo trực tiếp qua PUT"},
                headers=self.headers_a,
            )
            self.assertEqual(r_upsert.status_code, 200)
            self.assertEqual(r_upsert.json()["id"], "draft_new_456")

            # GET list for User A sorted updated_at DESC
            list_a = self.client.get("/api/community/drafts", headers=self.headers_a).json()["items"]
            self.assertEqual(len(list_a), 3)
            self.assertEqual(list_a[0]["id"], "draft_new_456")

            # Cross-user isolation for User B
            list_b = self.client.get("/api/community/drafts", headers=self.headers_b).json()["items"]
            self.assertEqual(len(list_b), 0)

            r_b_put = self.client.put(
                "/api/community/drafts/draft_123",
                json={"caption": "User B cố ghi đè"},
                headers=self.headers_b,
            )
            self.assertEqual(r_b_put.status_code, 404)

            r_b_post_hijack = self.client.post(
                "/api/community/drafts",
                json={"id": "draft_123", "caption": "User B hijack"},
                headers=self.headers_b,
            )
            self.assertEqual(r_b_post_hijack.status_code, 404)

            r_b_del = self.client.delete("/api/community/drafts/draft_123", headers=self.headers_b)
            self.assertEqual(r_b_del.status_code, 404)

            # Confirm User A's draft is completely intact
            list_a_after = self.client.get("/api/community/drafts", headers=self.headers_a).json()["items"]
            d123 = next(x for x in list_a_after if x["id"] == "draft_123")
            self.assertEqual(d123["caption"], "Nháp bữa trưa (đã chỉnh)")

            # Owner delete succeeds, second delete returns 404
            r_del = self.client.delete("/api/community/drafts/draft_123", headers=self.headers_a)
            self.assertEqual(r_del.status_code, 200)
            r_del2 = self.client.delete("/api/community/drafts/draft_123", headers=self.headers_a)
            self.assertEqual(r_del2.status_code, 404)

    # 5. Author profile real stats & privacy on GET /authors/{id}/posts
    def test_author_profile_real_stats_and_me_endpoint(self):
        with self._patch_db():
            # /authors/me without auth -> 401
            self.assertEqual(self.client.get("/api/community/authors/me").status_code, 401)

            # Seed likes: 2 on post_a_workout_pub, 1 on post_a_photo_nutr, 2 on deleted post (must be excluded)
            for uid, pid in [
                (self.user_b_id, "post_a_workout_pub"),
                (self.user_c_id, "post_a_workout_pub"),
                (self.user_b_id, "post_a_photo_nutr"),
                (self.user_b_id, "post_a_deleted"),
                (self.user_c_id, "post_a_deleted"),
            ]:
                self.fake_db["community_interactions"].insert_one({
                    "user_id": uid,
                    "post_id": pid,
                    "interaction_type": "like",
                    "created_at": datetime.now(timezone.utc),
                })

            res = self.client.get("/api/community/authors/me", headers=self.headers_a)
            self.assertEqual(res.status_code, 200)
            p = res.json()
            self.assertEqual(p["id"], self.user_a_id)
            self.assertEqual(p["name"], "Minh Tuấn")
            self.assertEqual(p["handle"], "minhtuan")
            self.assertEqual(p["bio"], "Tập đều mỗi sáng")
            self.assertEqual(p["interest_topics"], ["#TậpLuyện", "#BữaĂn"])
            self.assertEqual(p["avatar_url"], "https://example.com/a.jpg")
            # 5 non-deleted published posts: workout(1), meal(1) + photo_with_nutrition(1) + snapshot_meal(1) = 3 meals, qa(1)
            self.assertEqual(p["post_count"], 5)
            self.assertEqual(p["workout_post_count"], 1)
            self.assertEqual(p["meal_post_count"], 3)
            self.assertEqual(p["total_likes_received"], 3)

            # Zero sensitive leakage
            for forbidden in ("email", "password", "hashed_password", "health_metrics"):
                self.assertNotIn(forbidden, p)

    def test_author_posts_privacy_tabs_and_pagination(self):
        with self._patch_db():
            # /authors/me/posts without auth -> 401
            self.assertEqual(self.client.get("/api/community/authors/me/posts").status_code, 401)

            # Anonymous viewer sees ONLY public non-deleted posts
            anon_ids = [
                p["id"]
                for p in self.client.get(f"/api/community/authors/{self.user_a_id}/posts").json()["items"]
            ]
            self.assertEqual(anon_ids, ["post_a_qa_pub", "post_a_photo_nutr", "post_a_workout_pub"])

            # Non-follower User C sees ONLY public posts
            c_ids = [
                p["id"]
                for p in self.client.get(
                    f"/api/community/authors/{self.user_a_id}/posts",
                    headers=self.headers_c,
                ).json()["items"]
            ]
            self.assertEqual(c_ids, ["post_a_qa_pub", "post_a_photo_nutr", "post_a_workout_pub"])

            # User B follows User A -> now sees public + followers_only, NEVER private or deleted
            self.client.put(f"/api/community/authors/{self.user_a_id}/follow", headers=self.headers_b)
            b_ids = [
                p["id"]
                for p in self.client.get(
                    f"/api/community/authors/{self.user_a_id}/posts",
                    headers=self.headers_b,
                ).json()["items"]
            ]
            self.assertEqual(
                b_ids,
                ["post_a_qa_pub", "post_a_photo_nutr", "post_a_meal_followers", "post_a_workout_pub"],
            )
            self.assertNotIn("post_a_meal_private", b_ids)
            self.assertNotIn("post_a_deleted", b_ids)

            # Owner via /authors/me/posts sees public + followers_only + private (never deleted)
            me_ids = [
                p["id"]
                for p in self.client.get("/api/community/authors/me/posts", headers=self.headers_a).json()["items"]
            ]
            self.assertEqual(
                me_ids,
                [
                    "post_a_qa_pub",
                    "post_a_meal_private",
                    "post_a_photo_nutr",
                    "post_a_meal_followers",
                    "post_a_workout_pub",
                ],
            )

            # Tabs for owner
            self.assertEqual(
                [p["id"] for p in self.client.get("/api/community/authors/me/posts?tab=workout", headers=self.headers_a).json()["items"]],
                ["post_a_workout_pub"],
            )
            self.assertEqual(
                [p["id"] for p in self.client.get("/api/community/authors/me/posts?tab=meal", headers=self.headers_a).json()["items"]],
                ["post_a_meal_private", "post_a_photo_nutr", "post_a_meal_followers"],
            )
            self.assertEqual(
                [p["id"] for p in self.client.get("/api/community/authors/me/posts?tab=qa", headers=self.headers_a).json()["items"]],
                ["post_a_qa_pub"],
            )

            # Tabs for anonymous (private & followers_only meals still hidden!)
            self.assertEqual(
                [p["id"] for p in self.client.get(f"/api/community/authors/{self.user_a_id}/posts?tab=meal").json()["items"]],
                ["post_a_photo_nutr"],
            )

            # Pagination
            page1 = self.client.get("/api/community/authors/me/posts?limit=2", headers=self.headers_a).json()
            self.assertEqual(len(page1["items"]), 2)
            self.assertIsNotNone(page1["next_cursor"])
            page2 = self.client.get(
                f"/api/community/authors/me/posts?limit=2&cursor={page1['next_cursor']}",
                headers=self.headers_a,
            ).json()
            self.assertEqual(len(page2["items"]), 2)
            self.assertEqual(
                [p["id"] for p in page1["items"]] + [p["id"] for p in page2["items"]],
                ["post_a_qa_pub", "post_a_meal_private", "post_a_photo_nutr", "post_a_meal_followers"],
            )

    # 6. PATCH /api/community/profile
    def test_patch_profile_validation_duplicate_handle_and_sync(self):
        with self._patch_db():
            # Auth required
            self.assertEqual(self.client.patch("/api/community/profile", json={"name": "X"}).status_code, 401)

            # extra="forbid"
            self.assertEqual(
                self.client.patch(
                    "/api/community/profile",
                    json={"name": "Ok", "email": "hack@evil.com"},
                    headers=self.headers_a,
                ).status_code,
                422,
            )

            # > 3 interest topics -> 422
            self.assertEqual(
                self.client.patch(
                    "/api/community/profile",
                    json={"interest_topics": ["#A", "#B", "#C", "#D"]},
                    headers=self.headers_a,
                ).status_code,
                422,
            )

            # Invalid handle characters -> 422
            self.assertEqual(
                self.client.patch(
                    "/api/community/profile",
                    json={"handle": "@bad handle!"},
                    headers=self.headers_a,
                ).status_code,
                422,
            )

            # Duplicate handle owned by User B ("lananh") -> 409
            r_dup = self.client.patch(
                "/api/community/profile",
                json={"handle": "@LanAnh"},
                headers=self.headers_a,
            )
            self.assertEqual(r_dup.status_code, 409)

            # Valid update with @strip & lowercase normalization
            r_ok = self.client.patch(
                "/api/community/profile",
                json={
                    "name": "Coach Minh Tuấn",
                    "handle": "@Coach_Minh.01",
                    "title": "Head Coach",
                    "bio": "Kỷ luật tạo tự do",
                    "interest_topics": ["#TậpLuyện", "#PhụcHồi", "#KỷLuật"],
                    "avatar_url": "/static/community/new_avatar.jpg",
                },
                headers=self.headers_a,
            )
            self.assertEqual(r_ok.status_code, 200)
            prof = r_ok.json()
            self.assertEqual(prof["name"], "Coach Minh Tuấn")
            self.assertEqual(prof["handle"], "coach_minh.01")
            self.assertEqual(prof["title"], "Head Coach")
            self.assertEqual(prof["bio"], "Kỷ luật tạo tự do")
            self.assertEqual(prof["interest_topics"], ["#TậpLuyện", "#PhụcHồi", "#KỷLuật"])
            self.assertEqual(prof["avatar_url"], "/static/community/new_avatar.jpg")
            for forbidden in ("email", "password", "hashed_password", "health_metrics"):
                self.assertNotIn(forbidden, prof)

            # Same user keeping own handle -> 200 (not 409)
            r_same = self.client.patch(
                "/api/community/profile",
                json={"handle": "@coach_minh.01", "bio": "Updated bio"},
                headers=self.headers_a,
            )
            self.assertEqual(r_same.status_code, 200)
            self.assertEqual(r_same.json()["bio"], "Updated bio")

            # Another user trying to claim User A's new handle -> 409
            r_b_dup = self.client.patch(
                "/api/community/profile",
                json={"handle": "COACH_MINH.01"},
                headers=self.headers_b,
            )
            self.assertEqual(r_b_dup.status_code, 409)

            # Author summary synced on User A's posts
            post_res = self.client.get("/api/community/posts/post_a_workout_pub").json()
            self.assertEqual(post_res["author"]["name"], "Coach Minh Tuấn")
            self.assertEqual(post_res["author"]["title"], "Head Coach")
            self.assertEqual(post_res["author"]["avatar_url"], "/static/community/new_avatar.jpg")


if __name__ == "__main__":
    unittest.main()
