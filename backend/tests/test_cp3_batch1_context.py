"""
Comprehensive unit & integration test suite for CP3 Batch 1 (CP3.1 & CP3.2):
1. Test CP3.1 (journey_context.py & core3_context.py):
   - tier="swift3" skips journeys query (status == "skipped").
   - tier="core3" & "pro3" match journey document whether stored with user_id (str / ObjectId)
     or user_email / email (case-insensitive).
   - Strict pinning to Asia/Ho_Chi_Minh timezone: passing now = datetime(2026, 11, 1, 17, 30, tzinfo=timezone.utc)
     (which is 00:30 on 2026-11-02 in VN) matches day record with date == "2026-11-02".
   - Accurately splits completed_tasks and pending_tasks, verifies day_index, total_days,
     is_rest_day, current_streak, and guarantees zero leakage of user_email / user_id.
2. Test CP3.2 (story_community_context.py & core3_context.py):
   - swift3 & core3 return status == "skipped" for story_logs & community.
   - pro3 retrieves up to 5 most recent story_logs with food_name, calories, note, no PII/email.
   - pro3 retrieves user's Q&A community_posts and up to 3 saved posts from community_interactions (interaction_type == "save").
   - Audience Isolation: saved posts marked is_deleted=True, status="unpublished",
     or privacy="private" by someone else, or privacy="followers_only" when viewer does not follow
     are strictly filtered out. followers_only posts with a valid follow record are retained.
3. Integration Test build_core3_context + ChatOperationService.handle:
   - Verifies swift3 JSON context UTF-8 encoded bytes <= 1500.
   - Verifies core3 feeds journey into LLM prompt, and pro3 feeds journey, story_logs, community into LLM prompt.
"""

import asyncio
from copy import deepcopy
from datetime import datetime, timezone
import functools
import json
from pathlib import Path
import sys
from types import SimpleNamespace

_repo_root = str(Path(__file__).parents[2])
if _repo_root not in sys.path:
    sys.path.insert(0, _repo_root)

import pytest
from bson import ObjectId

from backend.app.services.context_utils import build_user_query, get_vn_date_str, normalize_email
from backend.app.services.core3_context import build_core3_context
from backend.app.services.journey_context import build_journey_context
from backend.app.services.story_community_context import (
    build_community_context,
    build_story_logs_context,
)
from backend.app.services.chat_operation_service import ChatOperationService


# ---------------------------------------------------------------------------
# In-memory fake Mongo database & collections (zero real Mongo connection)
# ---------------------------------------------------------------------------

def _field_value(document, field):
    if not isinstance(document, dict):
        return None
    value = document
    for part in field.split("."):
        if isinstance(value, dict):
            value = value.get(part)
        else:
            return None
    return value


def _set_field(document, field, value):
    parts = field.split(".")
    target = document
    for part in parts[:-1]:
        if part not in target or not isinstance(target[part], dict):
            target[part] = {}
        target = target[part]
    target[parts[-1]] = value


def _matches(doc, query):
    if not isinstance(query, dict):
        return doc == query
    for field, expected in query.items():
        if field == "$and":
            if not all(_matches(doc, clause) for clause in expected):
                return False
        elif field == "$or":
            if not any(_matches(doc, clause) for clause in expected):
                return False
        elif field == "messages.operation_id":
            msgs = doc.get("messages") or []
            op_ids = [m.get("operation_id") for m in msgs if isinstance(m, dict)]
            if isinstance(expected, dict) and "$ne" in expected:
                if expected["$ne"] in op_ids:
                    return False
            elif expected not in op_ids:
                return False
        else:
            actual = _field_value(doc, field)
            if isinstance(expected, dict):
                for op, operand in expected.items():
                    if op == "$gte" and (actual is None or actual < operand):
                        return False
                    if op == "$lte" and (actual is None or actual > operand):
                        return False
                    if op == "$gt" and (actual is None or actual <= operand):
                        return False
                    if op == "$lt" and (actual is None or actual >= operand):
                        return False
                    if op == "$ne":
                        if isinstance(actual, list):
                            if operand in actual or str(operand) in [str(x) for x in actual]:
                                return False
                        elif str(actual) == str(operand):
                            return False
                    if op == "$in":
                        if actual not in operand and str(actual) not in [str(x) for x in operand]:
                            return False
                    if op == "$nin":
                        if actual in operand or str(actual) in [str(x) for x in operand]:
                            return False
                    if op == "$exists":
                        if (actual is not None) != operand:
                            return False
            elif isinstance(actual, list) and not isinstance(expected, list):
                if expected not in actual and str(expected) not in [str(x) for x in actual]:
                    return False
            else:
                if actual != expected and str(actual) != str(expected):
                    return False
    return True


def _apply_projection(doc, projection):
    if not projection:
        return deepcopy(doc)
    res = {}
    include_id = projection.get("_id", 1) != 0
    if include_id and "_id" in doc:
        res["_id"] = doc["_id"]
    for k, v in projection.items():
        if k == "_id":
            continue
        if isinstance(v, dict) and "$slice" in v:
            orig = _field_value(doc, k)
            if isinstance(orig, list):
                _set_field(res, k, orig[: v["$slice"]])
        elif v:
            val = _field_value(doc, k)
            if val is not None:
                _set_field(res, k, val)
    return deepcopy(res)


class FakeCursor:
    def __init__(self, documents, projection=None):
        self.documents = documents
        self.projection = projection

    def sort(self, key_or_spec, direction=None):
        sort_spec = key_or_spec if isinstance(key_or_spec, list) else [(key_or_spec, direction or 1)]
        for field, order in reversed(sort_spec):
            self.documents.sort(
                key=lambda doc: (
                    _field_value(doc, field) is not None,
                    str(_field_value(doc, field)) if _field_value(doc, field) is not None else "",
                ),
                reverse=order < 0,
            )
        return self

    def limit(self, count):
        self.documents = self.documents[:count]
        return self

    def __iter__(self):
        for doc in self.documents:
            yield _apply_projection(doc, self.projection)

    def __len__(self):
        return len(self.documents)


class FakeCollection:
    def __init__(self, name="collection", documents=None):
        self.name = name
        self.documents = [deepcopy(doc) for doc in (documents or [])]

    def find(self, query=None, projection=None):
        matches = [deepcopy(doc) for doc in self.documents if _matches(doc, query or {})]
        return FakeCursor(matches, projection)

    def find_one(self, query=None, projection=None):
        cursor = self.find(query, projection)
        results = list(cursor)
        return results[0] if results else None

    def insert_one(self, document):
        doc = deepcopy(document)
        doc.setdefault("_id", ObjectId())
        self.documents.append(doc)
        return SimpleNamespace(inserted_id=doc["_id"])

    def update_one(self, filter_query, update, upsert=False):
        matching_idx = None
        for idx, doc in enumerate(self.documents):
            if _matches(doc, filter_query):
                matching_idx = idx
                break

        if matching_idx is not None:
            target = self.documents[matching_idx]
            modified = False
            if "$set" in update:
                for k, v in update["$set"].items():
                    _set_field(target, k, deepcopy(v))
                modified = True
            if "$inc" in update:
                for k, v in update["$inc"].items():
                    curr = _field_value(target, k) or 0
                    _set_field(target, k, curr + v)
                modified = True
            if "$addToSet" in update:
                for k, v in update["$addToSet"].items():
                    curr = _field_value(target, k)
                    if not isinstance(curr, list):
                        curr = []
                        _set_field(target, k, curr)
                    if v not in curr:
                        curr.append(deepcopy(v))
                modified = True
            if "$push" in update:
                for k, v in update["$push"].items():
                    curr = _field_value(target, k)
                    if not isinstance(curr, list):
                        curr = []
                        _set_field(target, k, curr)
                    if isinstance(v, dict) and "$each" in v:
                        curr.extend(deepcopy(v["$each"]))
                    else:
                        curr.append(deepcopy(v))
                modified = True
            return SimpleNamespace(matched_count=1, modified_count=1 if modified else 0, upserted_id=None)

        if upsert:
            clean_doc = {}
            for k, v in filter_query.items():
                if not k.startswith("$") and not isinstance(v, dict):
                    clean_doc[k] = v
            clean_doc.setdefault("_id", ObjectId())
            if "$setOnInsert" in update:
                for k, v in update["$setOnInsert"].items():
                    _set_field(clean_doc, k, deepcopy(v))
            if "$set" in update:
                for k, v in update["$set"].items():
                    _set_field(clean_doc, k, deepcopy(v))
            self.documents.append(clean_doc)
            return SimpleNamespace(matched_count=0, modified_count=0, upserted_id=clean_doc["_id"])

        return SimpleNamespace(matched_count=0, modified_count=0, upserted_id=None)


class FakeProvider:
    def __init__(self, reply_text="Chào bạn! Tôi là huấn luyện viên AI của bạn."):
        self.reply_text = reply_text
        self.captured_prompts = []

    async def generate(self, prompt, *, ai_mode: str = "core3"):
        self.captured_prompts.append((prompt, ai_mode))
        return self.reply_text


# ---------------------------------------------------------------------------
# TEST SUITE 1: CP3.1 Journey Context
# ---------------------------------------------------------------------------

class TestCp31JourneyContext:
    """Verify tier skipping, user_id/email matching, VN timezone pinning, task splitting, and PII hygiene."""

    def test_swift3_tier_skips_journey_query(self):
        jc = FakeCollection("journeys", [
            {
                "user_id": "u123",
                "status": "active",
                "focus": "Fat Loss",
                "days": [{"date": "2026-11-02", "tasks": []}],
            }
        ])
        principal = {"identity_id": "u123", "email": "u123@example.com"}

        # Via build_journey_context directly
        res = build_journey_context(principal=principal, journeys_collection=jc, tier="swift3")
        assert res["status"] == "skipped"
        assert res["coverage_missing"] is False
        assert res["active_journey"] is None

        # Via build_core3_context
        full_ctx = build_core3_context(
            principal={"_id": "u123", "email": "u123@example.com"},
            nutrition_collection=None,
            workout_collection=None,
            users_collection=None,
            journeys_collection=jc,
            tier="swift3",
        )
        assert full_ctx["journey"]["status"] == "skipped"

    @pytest.mark.parametrize("id_format,email_field,email_value", [
        ("str", "user_email", "user@example.com"),
        ("str", "email", "USER@EXAMPLE.COM"),
        ("objectid", "user_email", "User@Example.Com"),
        ("objectid", "email", "user@example.com"),
    ])
    def test_core3_and_pro3_match_journey_by_id_or_email_variants(
        self, id_format, email_field, email_value
    ):
        raw_uid = "507f1f77bcf86cd799439011"
        stored_uid = ObjectId(raw_uid) if id_format == "objectid" else raw_uid

        journey_doc = {
            "user_id": stored_uid,
            email_field: normalize_email(email_value),
            "status": "active",
            "focus": "Muscle Gain",
            "total_days": 30,
            "current_streak": 5,
            "best_streak": 7,
            "completed_days_count": 4,
            "days": [
                {
                    "day_index": 5,
                    "date": "2026-11-02",
                    "is_rest_day": False,
                    "is_completed": False,
                    "tasks": [
                        {"type": "workout", "title": "Chest & Triceps", "is_completed": True},
                        {"type": "meal", "title": "Track Lunch", "subtitle": "Salad + Chicken", "is_completed": False},
                    ],
                }
            ],
        }
        jc = FakeCollection("journeys", [journey_doc])

        # Query using lowercase email and string identity_id
        for query_tier in ("core3", "pro3"):
            principal = {"identity_id": raw_uid, "email": "USER@EXAMPLE.COM"}
            res = build_journey_context(
                principal=principal,
                journeys_collection=jc,
                tier=query_tier,
                now=datetime(2026, 11, 2, 8, 0, tzinfo=timezone.utc),
            )
            assert res["status"] == "available", f"Failed for tier={query_tier}, id_format={id_format}, email={email_field}"
            journey = res["active_journey"]
            assert journey is not None
            assert journey["focus"] == "Muscle Gain"
            assert journey["current_streak"] == 5

    def test_asia_ho_chi_minh_timezone_pinning(self):
        """Passing now = datetime(2026, 11, 1, 17, 30, tzinfo=timezone.utc)
        must resolve to 00:30 on 2026-11-02 Asia/Ho_Chi_Minh and match date == '2026-11-02'.
        """
        now_utc = datetime(2026, 11, 1, 17, 30, tzinfo=timezone.utc)
        # Validate helper date string first
        assert get_vn_date_str(now=now_utc) == "2026-11-02"

        journey_doc = {
            "user_id": "u_vn_time",
            "status": "active",
            "focus": "Weight Loss",
            "total_days": 28,
            "days": [
                {
                    "day_index": 1,
                    "date": "2026-11-01",
                    "is_rest_day": True,
                    "is_completed": True,
                    "tasks": [{"type": "rest", "title": "Day 1 Rest", "is_completed": True}],
                },
                {
                    "day_index": 2,
                    "date": "2026-11-02",
                    "is_rest_day": False,
                    "is_completed": False,
                    "tasks": [
                        {"type": "workout", "title": "Day 2 Hiit", "is_completed": False, "subtitle": "20 mins"},
                    ],
                },
            ],
        }
        jc = FakeCollection("journeys", [journey_doc])
        principal = {"identity_id": "u_vn_time", "email": "vn@example.com"}

        res = build_journey_context(principal=principal, journeys_collection=jc, tier="core3", now=now_utc)
        assert res["status"] == "available"
        aj = res["active_journey"]
        assert aj["today_date"] == "2026-11-02"
        assert aj["day_index"] == 2
        assert aj["is_rest_day"] is False
        assert len(aj["pending_tasks"]) == 1
        assert aj["pending_tasks"][0]["title"] == "Day 2 Hiit"

    def test_journey_tasks_split_metrics_and_zero_pii_leakage(self):
        now = datetime(2026, 11, 2, 10, 0, tzinfo=timezone.utc)
        journey_doc = {
            "_id": ObjectId(),
            "user_id": "u_safe",
            "user_email": "private_user@secret.com",
            "status": "active",
            "focus": "Strength",
            "total_days": 60,
            "current_streak": 12,
            "best_streak": 20,
            "completed_days_count": 15,
            "days": [
                {
                    "day_index": 16,
                    "date": "2026-11-02",
                    "is_rest_day": False,
                    "is_completed": False,
                    "tasks": [
                        {"type": "workout", "title": "Squat 5x5", "is_completed": True},
                        {"type": "hydration", "title": "Drink 2L Water", "is_completed": True},
                        {"type": "nutrition", "title": "Log Dinner", "subtitle": "High protein meal", "is_completed": False},
                        {"type": "sleep", "title": "Sleep 8 hours", "subtitle": "Lights off by 11pm", "is_completed": False},
                    ],
                }
            ],
        }
        jc = FakeCollection("journeys", [journey_doc])
        principal = {"identity_id": "u_safe", "email": "private_user@secret.com"}

        res = build_journey_context(principal=principal, journeys_collection=jc, tier="core3", now=now)
        assert res["status"] == "available"
        aj = res["active_journey"]

        # Verify task separation
        assert len(aj["completed_tasks"]) == 2
        assert [t["title"] for t in aj["completed_tasks"]] == ["Squat 5x5", "Drink 2L Water"]
        assert len(aj["pending_tasks"]) == 2
        assert aj["pending_tasks"][0]["title"] == "Log Dinner"
        assert aj["pending_tasks"][0]["subtitle"] == "High protein meal"
        assert aj["pending_tasks"][1]["title"] == "Sleep 8 hours"

        # Verify metrics
        assert aj["day_index"] == 16
        assert aj["total_days"] == 60
        assert aj["is_rest_day"] is False
        assert aj["current_streak"] == 12
        assert aj["best_streak"] == 20
        assert aj["completed_days_count"] == 15

        # PII Hygiene: ensure no user_id, user_email, _id leaked in journey context
        serialized = json.dumps(res)
        assert "private_user@secret.com" not in serialized
        assert "u_safe" not in serialized
        assert "user_id" not in aj
        assert "user_email" not in aj
        assert "_id" not in aj


# ---------------------------------------------------------------------------
# TEST SUITE 2: CP3.2 Story Logs & Community Context
# ---------------------------------------------------------------------------

class TestCp32StoryAndCommunityContext:
    """Verify tier skipping, story_logs limit & projection, Q&A extraction, and audience isolation."""

    def test_swift3_and_core3_skip_story_logs_and_community(self):
        principal = {"identity_id": "u_pro", "email": "pro@example.com"}
        sc = FakeCollection("story_logs", [{"user_id": "u_pro", "food_name": "Phở Bò", "calories": 500}])
        posts_col = FakeCollection("community_posts", [{"user_id": "u_pro", "type": "qa", "question": "Hỏi cách squat?"}])
        inter_col = FakeCollection("community_interactions", [{"user_id": "u_pro", "interaction_type": "save", "post_id": "p1"}])

        for tier in ("swift3", "core3"):
            story_res = build_story_logs_context(principal=principal, story_logs_collection=sc, tier=tier)
            assert story_res["status"] == "skipped"
            assert story_res["entries"] == []

            comm_res = build_community_context(
                principal=principal,
                community_posts_collection=posts_col,
                community_interactions_collection=inter_col,
                tier=tier,
            )
            assert comm_res["status"] == "skipped"
            assert comm_res["questions"] == []
            assert comm_res["saved_posts"] == []

    def test_pro3_story_logs_retrieves_max_5_most_recent_without_pii(self):
        uid = "u_foodie"
        email = "foodie@test.com"
        # Insert 7 story logs with different timestamps
        docs = [
            {
                "user_id": uid,
                "user_email": email,
                "food_name": f"Food Item {i}",
                "calories": 200 + i * 50,
                "protein": 20 + i,
                "carbs": 30 + i,
                "fat": 5 + i,
                "note": f"Delicious meal #{i}",
                "date": f"2026-11-0{i}",
                "logged_at": datetime(2026, 11, i, 12, 0, tzinfo=timezone.utc),
                "created_at": datetime(2026, 11, i, 12, 0, tzinfo=timezone.utc),
            }
            for i in range(1, 8)
        ]
        sc = FakeCollection("story_logs", docs)
        principal = {"_id": uid, "email": email}

        res = build_story_logs_context(principal=principal, story_logs_collection=sc, tier="pro3")
        assert res["status"] == "available"
        assert len(res["entries"]) == 5

        # Most recent items (items 7, 6, 5, 4, 3) must be returned in descending order
        assert res["entries"][0]["food_name"] == "Food Item 7"
        assert res["entries"][0]["calories"] == 550
        assert res["entries"][0]["note"] == "Delicious meal #7"
        assert res["entries"][4]["food_name"] == "Food Item 3"

        # Check zero PII
        serialized = json.dumps(res)
        assert email not in serialized
        assert uid not in serialized
        for entry in res["entries"]:
            assert "user_id" not in entry
            assert "user_email" not in entry
            assert "_id" not in entry

    def test_pro3_community_extracts_user_qa_and_saved_posts(self):
        uid = "u_athlete"
        post_col = FakeCollection("community_posts", [
            # User's own QA post
            {
                "_id": ObjectId("607f1f77bcf86cd799439001"),
                "author_id": uid,
                "type": "qa",
                "topic": "Nutrition",
                "is_deleted": False,
                "status": "published",
                "qa_info": {
                    "question": "Nên nạp bao nhiêu gram protein sau tập?",
                    "details": "Mục tiêu tăng cơ giảm mỡ",
                    "respondent_count": 3,
                },
                "created_at": datetime(2026, 11, 2, 9, 0, tzinfo=timezone.utc),
            },
            # Saved Post 1: Public workout post
            {
                "_id": ObjectId("607f1f77bcf86cd799439002"),
                "id": "post_workout_1",
                "author_id": "other_author",
                "type": "workout",
                "topic": "Upper Body",
                "caption": "Buổi tập ngực và tay sau hiệu quả",
                "workout_attachment": {"title": "Chest & Triceps Routine"},
                "privacy": "public",
                "is_deleted": False,
                "status": "published",
                "created_at": datetime(2026, 11, 1, 8, 0, tzinfo=timezone.utc),
            },
        ])
        inter_col = FakeCollection("community_interactions", [
            {
                "user_id": uid,
                "interaction_type": "save",
                "post_id": "607f1f77bcf86cd799439002",
                "created_at": datetime(2026, 11, 2, 10, 0, tzinfo=timezone.utc),
            }
        ])

        principal = {"user_id": uid, "email": "athlete@gym.vn"}
        res = build_community_context(
            principal=principal,
            community_posts_collection=post_col,
            community_interactions_collection=inter_col,
            tier="pro3",
        )
        assert res["status"] == "available"
        assert len(res["questions"]) == 1
        assert res["questions"][0]["question"] == "Nên nạp bao nhiêu gram protein sau tập?"
        assert res["questions"][0]["respondent_count"] == 3

        assert len(res["saved_posts"]) == 1
        assert res["saved_posts"][0]["workout_title"] == "Chest & Triceps Routine"
        assert res["saved_posts"][0]["caption"] == "Buổi tập ngực và tay sau hiệu quả"

    def test_community_audience_isolation_enforcement(self):
        """Audience Isolation:
        1. is_deleted=True -> Filtered out.
        2. status='unpublished' -> Filtered out.
        3. privacy='private' of another user -> Filtered out.
        4. privacy='followers_only' when viewer does NOT follow the author -> Filtered out.
        5. privacy='followers_only' with valid follow record -> Retained.
        """
        viewer_id = "viewer_001"
        author_followed = "author_followed_777"
        author_unfollowed = "author_unfollowed_888"

        # Construct 5 distinct posts
        p_deleted_id = "607f1f77bcf86cd799439011"
        p_unpub_id = "607f1f77bcf86cd799439012"
        p_private_id = "607f1f77bcf86cd799439013"
        p_nofollow_id = "607f1f77bcf86cd799439014"
        p_followed_id = "607f1f77bcf86cd799439015"

        posts_data = [
            # 1. Deleted
            {
                "_id": ObjectId(p_deleted_id),
                "id": p_deleted_id,
                "author_id": author_followed,
                "privacy": "public",
                "is_deleted": True,
                "status": "published",
                "caption": "Deleted post",
            },
            # 2. Unpublished
            {
                "_id": ObjectId(p_unpub_id),
                "id": p_unpub_id,
                "author_id": author_followed,
                "privacy": "public",
                "is_deleted": False,
                "status": "unpublished",
                "caption": "Unpublished draft",
            },
            # 3. Private of another person
            {
                "_id": ObjectId(p_private_id),
                "id": p_private_id,
                "author_id": author_followed,
                "privacy": "private",
                "is_deleted": False,
                "status": "published",
                "caption": "Private diary of author",
            },
            # 4. Followers only by author_unfollowed (viewer does NOT follow)
            {
                "_id": ObjectId(p_nofollow_id),
                "id": p_nofollow_id,
                "author_id": author_unfollowed,
                "privacy": "followers_only",
                "is_deleted": False,
                "status": "published",
                "caption": "Followers only post (not following)",
            },
            # 5. Followers only by author_followed (viewer has valid follow record)
            {
                "_id": ObjectId(p_followed_id),
                "id": p_followed_id,
                "author_id": author_followed,
                "privacy": "followers_only",
                "is_deleted": False,
                "status": "published",
                "caption": "Followers only post (valid follower)",
            },
        ]
        post_col = FakeCollection("community_posts", posts_data)

        # Viewer saved all 5 posts
        inters = [
            {
                "user_id": viewer_id,
                "interaction_type": "save",
                "post_id": pid,
                "created_at": datetime(2026, 11, 2, i, 0, tzinfo=timezone.utc),
            }
            for i, pid in enumerate([p_deleted_id, p_unpub_id, p_private_id, p_nofollow_id, p_followed_id], start=1)
        ]
        inter_col = FakeCollection("community_interactions", inters)

        # Follow collection contains valid follow ONLY for author_followed
        follows_col = FakeCollection("community_follows", [
            {"follower_id": viewer_id, "following_id": author_followed}
        ])

        principal = {"_id": viewer_id, "email": "viewer@example.com"}

        # Run with follows collection configured
        res = build_community_context(
            principal=principal,
            community_posts_collection=post_col,
            community_interactions_collection=inter_col,
            community_follows_collection=follows_col,
            tier="pro3",
        )
        saved = res["saved_posts"]
        # Only the valid followed post must survive
        assert len(saved) == 1
        assert saved[0]["caption"] == "Followers only post (valid follower)"

        # Without follows collection, even p_followed_id must be filtered out
        res_no_follows = build_community_context(
            principal=principal,
            community_posts_collection=post_col,
            community_interactions_collection=inter_col,
            community_follows_collection=None,
            tier="pro3",
        )
        assert len(res_no_follows["saved_posts"]) == 0


# ---------------------------------------------------------------------------
# TEST SUITE 3: Integration build_core3_context + ChatOperationService.handle
# ---------------------------------------------------------------------------

class TestIntegrationCore3ContextAndChatService:
    """Verify Swift3 byte budget (<= 1500 bytes) and LLM prompt grounding for Core3 and Pro3."""

    def test_swift3_context_json_under_1500_utf8_bytes(self):
        """Even with huge database records, swift3 context must be <= 1500 UTF-8 bytes."""
        workout_col = FakeCollection("workouts", [
            {
                "user_id": "u_swift",
                "date": "2026-11-02",
                "plan_name": "Ultra Heavy Long Workout Session " * 5,
                "exercise_logs": [
                    {
                        "name": f"Heavy Compound Exercise {i}",
                        "sets": 10,
                        "weight": 150,
                        "reps": 12,
                        "reps_summary": "Clean reps with controlled negative eccentric motion",
                    }
                    for i in range(30)
                ],
            }
        ])
        user_col = FakeCollection("users", [
            {
                "_id": "u_swift",
                "preferences": {
                    "notes": "User has multiple complex dietary restrictions and equipment needs " * 10,
                },
                "health_stats": {f"extended_metric_{i}": 1234.56 for i in range(25)},
            }
        ])

        ctx = build_core3_context(
            principal={"_id": "u_swift", "email": "swift@domain.com"},
            nutrition_collection=None,
            workout_collection=workout_col,
            users_collection=user_col,
            tier="swift3",
        )

        encoded_bytes = json.dumps(ctx, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        assert len(encoded_bytes) <= 1500, f"Swift3 context exceeded 1500 bytes: {len(encoded_bytes)} bytes"

    def test_chat_operation_service_core3_includes_journey_in_llm_prompt(self):
        uid = "u_c3_chat"
        email = "c3@example.com"
        db = {"chat_operations": FakeCollection("chat_operations")}
        conv_col = FakeCollection("conversations")
        fake_provider = FakeProvider(reply_text="Tuyệt vời! Hành trình của bạn đang tiến triển rất tốt.")

        journey_col = FakeCollection("journeys", [
            {
                "user_id": uid,
                "status": "active",
                "focus": "Fat Loss & Muscle Retention",
                "total_days": 21,
                "current_streak": 7,
                "days": [
                    {
                        "day_index": 8,
                        "date": get_vn_date_str(),
                        "is_rest_day": False,
                        "tasks": [{"type": "workout", "title": "Morning HIIT", "is_completed": True}],
                    }
                ],
            }
        ])

        # Bind journeys_collection into context_builder
        context_builder_with_journey = functools.partial(
            build_core3_context,
            journeys_collection=journey_col,
        )

        service = ChatOperationService(
            db=db,
            conversations=conv_col,
            nutrition=FakeCollection("nutrition"),
            workouts=FakeCollection("workouts"),
            users=FakeCollection("users"),
            provider=fake_provider,
            context_builder=context_builder_with_journey,
        )

        op_id = "0123456789abcdef0123456789abcdef"
        res = asyncio.run(
            service.handle(
                principal={"_id": uid, "email": email},
                operation_id=op_id,
                contract_version="core3-local-v1",
                message="Hôm nay tôi nên tập gì tiếp theo?",
                ai_mode="core3",
            )
        )

        assert res["status"] == "success"
        assert len(fake_provider.captured_prompts) == 1
        prompt_text, mode = fake_provider.captured_prompts[0]
        assert mode == "core3"
        # Prompt must ground active journey
        assert "Fat Loss & Muscle Retention" in prompt_text
        assert "Morning HIIT" in prompt_text

    def test_chat_operation_service_pro3_includes_journey_story_community_in_llm_prompt(self):
        uid = "u_pro3_chat"
        email = "pro3@example.com"
        db = {"chat_operations": FakeCollection("chat_operations")}
        conv_col = FakeCollection("conversations")
        fake_provider = FakeProvider(reply_text="Dựa trên nhật ký ăn uống và cộng đồng, đây là phân tích của tôi.")

        journey_col = FakeCollection("journeys", [
            {
                "user_id": uid,
                "status": "active",
                "focus": "Marathon Endurance",
                "total_days": 90,
                "current_streak": 14,
                "days": [
                    {
                        "day_index": 15,
                        "date": get_vn_date_str(),
                        "is_rest_day": False,
                        "tasks": [{"type": "cardio", "title": "Long Run 12km", "is_completed": True}],
                    }
                ],
            }
        ])
        story_col = FakeCollection("story_logs", [
            {
                "user_id": uid,
                "food_name": "Yến mạch chuối mật ong",
                "calories": 420,
                "note": "Nạp carb trước chạy bộ",
                "created_at": datetime.now(timezone.utc),
            }
        ])
        posts_col = FakeCollection("community_posts", [
            {
                "_id": ObjectId("607f1f77bcf86cd799439099"),
                "author_id": uid,
                "type": "qa",
                "is_deleted": False,
                "status": "published",
                "qa_info": {
                    "question": "Cách tránh chuột rút khi chạy đường dài?",
                    "details": "Thường bị căng bắp chân sau 8km",
                    "respondent_count": 5,
                },
                "created_at": datetime.now(timezone.utc),
            }
        ])

        # Bind all Batch 1 collections into context builder
        context_builder_pro = functools.partial(
            build_core3_context,
            journeys_collection=journey_col,
            story_logs_collection=story_col,
            community_posts_collection=posts_col,
            community_interactions_collection=FakeCollection("community_interactions"),
            community_follows_collection=FakeCollection("community_follows"),
        )

        service = ChatOperationService(
            db=db,
            conversations=conv_col,
            nutrition=FakeCollection("nutrition"),
            workouts=FakeCollection("workouts"),
            users=FakeCollection("users"),
            provider=fake_provider,
            context_builder=context_builder_pro,
        )

        op_id = "fedcba9876543210fedcba9876543210"
        res = asyncio.run(
            service.handle(
                principal={"_id": uid, "email": email},
                operation_id=op_id,
                contract_version="core3-local-v1",
                message="Xin lời khuyên về năng lượng và cách hồi phục cho bài chạy hôm nay.",
                ai_mode="pro3",
            )
        )

        assert res["status"] == "success"
        assert len(fake_provider.captured_prompts) == 1
        prompt_text, mode = fake_provider.captured_prompts[0]
        assert mode == "pro3"

        # Verify all 3 Batch 1 dimensions are present in LLM prompt:
        # 1. Journey
        assert "Marathon Endurance" in prompt_text
        assert "Long Run 12km" in prompt_text
        # 2. Story logs
        assert "Yến mạch chuối mật ong" in prompt_text
        assert "Nạp carb trước chạy bộ" in prompt_text
        # 3. Community QA
        assert "Cách tránh chuột rút khi chạy đường dài?" in prompt_text
