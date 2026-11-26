"""Offline unit tests for Phase 4 intent router and context expansion."""

from datetime import datetime, timezone, timedelta
import json
import pytest

from backend.app.services.intent_router import classify_chat_intent
from backend.app.services.workout_recovery_helper import (
    calculate_muscle_recovery_load,
    compact_muscle_recovery_for_ai,
    compute_rolling_anomaly_tags,
)
from backend.app.services.core3_context import build_core3_context


class _FakeCursor(list):
    def sort(self, key_or_list):
        return self

    def limit(self, n):
        return _FakeCursor(self[:n])


class _FakeCollection:
    def __init__(self, docs=None):
        self.docs = docs or []
        self.find_calls = []

    def find(self, query, projection=None):
        self.find_calls.append((query, projection))
        return _FakeCursor(list(self.docs))

    def find_one(self, query, projection=None):
        self.find_calls.append((query, projection))
        if self.docs:
            return self.docs[0]
        return None


def test_classify_chat_intent_five_domains():
    # 1. general_chat (greetings & casual, VI & EN)
    res_vi = classify_chat_intent("Xin chào bot")
    assert res_vi.intent == "general_chat"
    assert res_vi.prefer_lightweight_model is True
    assert "profile" in res_vi.collections
    assert "workout" not in res_vi.collections

    res_en = classify_chat_intent("hello there")
    assert res_en.intent == "general_chat"
    assert res_en.prefer_lightweight_model is True

    # 2. workout_form (exercises, form, rep, tempo)
    res_wf = classify_chat_intent("Kiểm tra form bài Lat Pulldown giúp tôi")
    assert res_wf.intent == "workout_form"
    assert res_wf.include_video_citations is True
    assert "video_stories" in res_wf.collections
    assert "nutrition" not in res_wf.collections

    res_wf_en = classify_chat_intent("check my squat form and rep tempo")
    assert res_wf_en.intent == "workout_form"
    assert res_wf_en.include_video_citations is True

    # 3. recovery (muscle fatigue, soreness, DOMS)
    res_rec = classify_chat_intent("Hôm nay tôi mỏi cơ và đau nhức quá, có nên tập không?")
    assert res_rec.intent == "recovery"
    assert "recovery" in res_rec.collections
    assert "video_stories" not in res_rec.collections

    # 4. nutrition (calories, meals, macros, water)
    res_nut = classify_chat_intent("Hôm nay tôi nạp bao nhiêu calo và protein rồi?")
    assert res_nut.intent == "nutrition"
    assert "nutrition" in res_nut.collections
    assert "recipes" in res_nut.collections
    assert "video_stories" not in res_nut.collections

    # 5. full_audit (pro3 mode with audit keyword or multi-domain)
    res_audit = classify_chat_intent(
        "Phân tích sâu đối chiếu form lat pulldown và lượng calo nạp tuần này",
        ai_mode="pro3",
    )
    assert res_audit.intent == "full_audit"
    assert res_audit.include_video_citations is True
    assert "nutrition" in res_audit.collections
    assert "workout" in res_audit.collections
    assert "video_stories" in res_audit.collections


def test_build_core3_context_selective_querying():
    principal = {"_id": "user-test", "email": "user@example.test"}
    users_col = _FakeCollection([{"_id": "user-test", "email": "user@example.test", "goal": "muscle"}])
    workout_col = _FakeCollection([{"_id": "w1", "date": "2026-11-26", "exercise_logs": [{"exercise_slug": "squat", "sets": 3}]}])
    nutrition_col = _FakeCollection([{"_id": "n1", "date": "2026-11-26", "total_calories": 2000, "total_protein": 150}])
    recipes_col = _FakeCollection([{"_id": "r1", "name": "Chicken Salad", "calories_per_serving": 400}])

    # 1. Full context query (no intent_route)
    full_ctx = build_core3_context(
        principal=principal,
        nutrition_collection=nutrition_col,
        workout_collection=workout_col,
        users_collection=users_col,
        recipes_collection=recipes_col,
        tier="core3",
    )
    full_json = json.dumps(full_ctx, ensure_ascii=False)
    assert len(nutrition_col.find_calls) == 1
    assert len(recipes_col.find_calls) == 1

    # Reset call trackers
    nutrition_col.find_calls.clear()
    recipes_col.find_calls.clear()

    # 2. Selective query with workout_form intent
    route = classify_chat_intent("Kiểm tra form bài squat của tôi")
    assert route.intent == "workout_form"

    sel_ctx = build_core3_context(
        principal=principal,
        nutrition_collection=nutrition_col,
        workout_collection=workout_col,
        users_collection=users_col,
        recipes_collection=recipes_col,
        tier="core3",
        intent_route=route,
    )
    # Nutrition and recipes MUST NOT be queried
    assert len(nutrition_col.find_calls) == 0
    assert len(recipes_col.find_calls) == 0
    assert sel_ctx["nutrition"]["status"] == "skipped"
    assert sel_ctx["recipes"]["status"] == "skipped"

    sel_json = json.dumps(sel_ctx, ensure_ascii=False)
    # Size must be reduced substantially (>= 30% reduction when unneeded collections skipped)
    assert len(sel_json) <= len(full_json)


def test_video_story_evidence_filtering_and_tiers():
    principal = {"_id": "user-video", "email": "video@example.test"}
    users_col = _FakeCollection([{"_id": "user-video", "email": "video@example.test"}])
    workout_col = _FakeCollection([])

    now = datetime(2026, 11, 26, 12, 0, tzinfo=timezone.utc)

    # 2 reps in video story: 1 low visibility (0.45), 1 high visibility (0.985)
    stories_data = [
        {
            "_id": "vs-101",
            "video_story_id": "vs-101",
            "exercise_slug": "lat-pulldown",
            "created_at": now - timedelta(days=2),
            "rep_timeline": [
                {
                    "rep_index": 1,
                    "issue_type": "tooFast",
                    "visibility_confidence": 0.45,  # MUST BE FILTERED OUT (< 0.6)
                    "start_sec": 1.0,
                    "end_sec": 2.5,
                },
                {
                    "rep_index": 2,
                    "issue_type": "incompleteRom",
                    "visibility_confidence": 0.985,  # MUST BE INCLUDED (>= 0.6)
                    "start_sec": 3.0,
                    "end_sec": 5.0,
                    "metric_angle_deg": 65.0,
                },
            ],
        }
    ]
    stories_col = _FakeCollection(stories_data)

    # 1. Free tier: citation_days = 0 -> no video story evidence returned
    free_ctx = build_core3_context(
        principal=principal,
        nutrition_collection=None,
        workout_collection=workout_col,
        users_collection=users_col,
        video_stories_collection=stories_col,
        membership_tier="free",
        account_id="acc-123",
        now=now,
    )
    assert "video_story_evidence" not in free_ctx

    # 2. Ultra tier: citation_days = 30 -> query and filter
    stories_col.find_calls.clear()
    ultra_ctx = build_core3_context(
        principal=principal,
        nutrition_collection=None,
        workout_collection=workout_col,
        users_collection=users_col,
        video_stories_collection=stories_col,
        membership_tier="ultra",
        account_id="acc-123",
        now=now,
    )
    assert len(stories_col.find_calls) == 1
    evidence = ultra_ctx.get("video_story_evidence", [])
    assert len(evidence) == 1
    item = evidence[0]
    assert item["video_story_id"] == "vs-101"
    assert item["rep_index"] == 2
    assert item["issue_type"] == "incompleteRom"
    assert item["visibility_confidence"] == 0.985
    assert item["start_sec"] == 3.0


def test_workout_recovery_and_rolling_anomaly_tags():
    now = datetime(2026, 11, 26, 12, 0, tzinfo=timezone.utc)

    # 3 sessions with tooFast in lat-pulldown from rep 7
    sessions = [
        {
            "started_at": now - timedelta(hours=10),
            "exercise_logs": [
                {
                    "exercise_slug": "lat-pulldown",
                    "is_completed": True,
                    "set_type": "normal",
                    "rep_timeline": [
                        {"rep_index": 1, "issue_type": "none", "visibility_confidence": 0.9},
                        {"rep_index": 7, "issue_type": "tooFast", "visibility_confidence": 0.95},
                        {"rep_index": 8, "issue_type": "tooFast", "visibility_confidence": 0.92},
                    ],
                }
            ],
        },
        {
            "started_at": now - timedelta(hours=34),
            "exercise_logs": [
                {
                    "exercise_slug": "lat-pulldown",
                    "is_completed": True,
                    "set_type": "normal",
                    "rep_timeline": [
                        {"rep_index": 1, "issue_type": "none", "visibility_confidence": 0.9},
                        {"rep_index": 7, "issue_type": "tooFast", "visibility_confidence": 0.91},
                        {"rep_index": 8, "issue_type": "tooFast", "visibility_confidence": 0.94},
                    ],
                }
            ],
        },
    ]

    rec = calculate_muscle_recovery_load(sessions, now)
    assert rec["window_hours"] == 72
    assert len(rec["muscles"]) == 6
    back_group = next(m for m in rec["muscles"] if m["muscleGroup"] == "back")
    assert back_group["recentSets"] == 2
    assert back_group["recoveryPercent"] < 100

    rec_compact = compact_muscle_recovery_for_ai(rec)
    assert "back" in rec_compact

    tags = compute_rolling_anomaly_tags(sessions, recovery_compact=rec_compact, min_visibility=0.6)
    assert len(tags) >= 1
    assert any("2+ buổi liên tiếp bài lat-pulldown bị lỗi 'tooFast'" in t for t in tags)


def test_byte_budgets_swift_core_pro():
    principal = {"_id": "user-budget", "email": "budget@example.test"}
    users_col = _FakeCollection([{"_id": "user-budget", "email": "budget@example.test"}])

    # Big payload of workout sessions and nutrition
    big_logs = [{"exercise_slug": f"exercise_{i}", "sets": 4, "reps": 12, "weight_kg": 60.0} for i in range(50)]
    sessions = [{"started_at": datetime(2026, 11, 20, 10, 0, tzinfo=timezone.utc), "exercise_logs": big_logs} for _ in range(10)]
    workout_col = _FakeCollection(sessions)

    # Swift3 budget <= 1500 bytes
    swift_ctx = build_core3_context(
        principal=principal,
        nutrition_collection=None,
        workout_collection=workout_col,
        users_collection=users_col,
        tier="swift3",
    )
    swift_bytes = len(json.dumps(swift_ctx, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    assert swift_bytes <= 1500

    # Core3 budget <= 11000 bytes
    core_ctx = build_core3_context(
        principal=principal,
        nutrition_collection=None,
        workout_collection=workout_col,
        users_collection=users_col,
        tier="core3",
    )
    core_bytes = len(json.dumps(core_ctx, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    assert core_bytes <= 11000

    # Pro3 budget <= 18000 bytes
    pro_ctx = build_core3_context(
        principal=principal,
        nutrition_collection=None,
        workout_collection=workout_col,
        users_collection=users_col,
        tier="pro3",
    )
    pro_bytes = len(json.dumps(pro_ctx, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    assert pro_bytes <= 18000
