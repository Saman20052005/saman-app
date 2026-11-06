import copy
import os
import sys
import unittest
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import patch

import pymongo
from bson import ObjectId
import dotenv
from fastapi import FastAPI
from fastapi.testclient import TestClient


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

os.environ["GEMINI_API_KEY"] = ""
os.environ["OPENAI_API_KEY"] = ""
_MONGO_GUARD_CALLS = []


def _blocked_mongo_client(*args, **kwargs):
    _MONGO_GUARD_CALLS.append((args, kwargs))
    raise RuntimeError("MongoClient construction blocked by CP-AI-06 tests")


with patch.object(
    pymongo, "MongoClient", side_effect=_blocked_mongo_client
), patch.object(dotenv, "load_dotenv", return_value=False):
    from backend.auth_utils import get_current_user
    import backend.routers.chat as chat_module


class MemoryCollection:
    def __init__(self, documents=()):
        self.documents = copy.deepcopy(list(documents))
        self.queries = []
        self.write_calls = []
        self.read_error = None

    @staticmethod
    def _value_matches(actual, expected):
        return str(actual) == str(expected)

    def _matches(self, document, query):
        for key, expected in query.items():
            if key == "$or":
                if not any(self._matches(document, branch) for branch in expected):
                    return False
            elif key == "$and":
                if not all(
                    self._matches(document, branch) for branch in expected
                ):
                    return False
            elif not self._value_matches(document.get(key), expected):
                return False
        return True

    def find(self, query=None):
        query = query or {}
        self.queries.append(copy.deepcopy(query))
        if self.read_error is not None:
            raise self.read_error
        return [
            copy.deepcopy(document)
            for document in self.documents
            if self._matches(document, query)
        ]

    def find_one(self, query=None):
        results = self.find(query)
        return results[0] if results else None

    def insert_one(self, document):
        self.write_calls.append(("insert_one", copy.deepcopy(document)))
        stored = copy.deepcopy(document)
        stored.setdefault("_id", ObjectId())
        self.documents.append(stored)
        return SimpleNamespace(inserted_id=stored["_id"])

    def update_one(self, query, update):
        self.write_calls.append(
            ("update_one", copy.deepcopy(query), copy.deepcopy(update))
        )
        for document in self.documents:
            if not self._matches(document, query):
                continue
            for key, value in update.get("$set", {}).items():
                document[key] = copy.deepcopy(value)
            for key, value in update.get("$push", {}).items():
                messages = value.get("$each", [value])
                document.setdefault(key, []).extend(copy.deepcopy(messages))
            return SimpleNamespace(matched_count=1)
        return SimpleNamespace(matched_count=0)


class ChatWorkoutRecommendationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not _MONGO_GUARD_CALLS:
            raise AssertionError("MongoClient was not guarded before app import")
        cls.resolver = chat_module.exercise_catalog_resolver
        if not cls.resolver.available:
            raise AssertionError("The generated exercise catalog must be available")

    def setUp(self):
        self.user_a = {
            "_id": ObjectId("650000000000000000000001"),
            "email": "user_a@saman.test",
            "profile": {"activity_level": "moderate", "goal": "gain_muscle"},
        }
        self.user_b = {
            "_id": ObjectId("650000000000000000000002"),
            "email": "user_b@saman.test",
            "profile": {"activity_level": "very_active", "goal": "lose_weight"},
        }
        self.active_user = self.user_a
        self.users = MemoryCollection([self.user_a, self.user_b])
        self.history = MemoryCollection()
        self.conversations = MemoryCollection()
        self.plans = MemoryCollection()

        self.original_collections = {
            "users_col": chat_module.users_col,
            "workout_history_col": chat_module.workout_history_col,
            "workout_history_collection": chat_module.workout_history_collection,
            "conversations_col": chat_module.conversations_col,
            "custom_plans_col": chat_module.custom_plans_col,
            "resolver": chat_module.exercise_catalog_resolver,
        }
        chat_module.users_col = self.users
        chat_module.workout_history_col = self.history
        chat_module.workout_history_collection = self.history
        chat_module.conversations_col = self.conversations
        chat_module.custom_plans_col = self.plans

        self.app = FastAPI()
        self.app.include_router(chat_module.router)
        self.app.dependency_overrides[get_current_user] = lambda: self.active_user
        self.client = TestClient(self.app)

        async def forbidden_provider(prompt):
            self.assertIsInstance(prompt, str)
            raise AssertionError("Recommendation branch called the AI provider")

        self.provider_guard = patch.object(
            chat_module, "_generate_ai_reply", side_effect=forbidden_provider
        )
        self.provider_guard.start()
        self.addCleanup(self.provider_guard.stop)
        self.addCleanup(self.app.dependency_overrides.clear)
        self.addCleanup(self._restore_chat_module)

    def _restore_chat_module(self):
        chat_module.users_col = self.original_collections["users_col"]
        chat_module.workout_history_col = self.original_collections[
            "workout_history_col"
        ]
        chat_module.workout_history_collection = self.original_collections[
            "workout_history_collection"
        ]
        chat_module.conversations_col = self.original_collections[
            "conversations_col"
        ]
        chat_module.custom_plans_col = self.original_collections["custom_plans_col"]
        chat_module.exercise_catalog_resolver = self.original_collections["resolver"]

    def _history_session(self, owner, exercise, when=None):
        return {
            "user_id": str(owner["_id"]),
            "email": owner["email"],
            "started_at": (when or datetime.now(timezone.utc)).isoformat(),
            "exercise_logs": [
                {
                    "exercise_id": exercise["id"],
                    "exercise_slug": exercise["slug"],
                    "set_number": 1,
                    "reps_completed": 8,
                    "unit": "reps",
                    "weight_kg": 20,
                    "is_completed": True,
                }
            ],
        }

    def _assert_only_conversation_writes(self):
        self.assertEqual(self.users.write_calls, [])
        self.assertEqual(self.history.write_calls, [])
        self.assertEqual(self.plans.write_calls, [])
        self.assertTrue(self.conversations.write_calls)

    def test_explicit_recommendation_intents_and_exclusions(self):
        for message in (
            "Gợi ý bài tập ngực",
            "Goi y bai tap lung",
            "Recommend chest exercises",
            "What exercises should I do?",
        ):
            with self.subTest(message=message):
                self.assertTrue(
                    chat_module._detect_workout_recommendation_intent(message)
                )

        for message in (
            "Tôi muốn tập đều hơn",
            "Hôm qua tôi tập gì?",
            "Cách tập squat đúng?",
            "How do I perform a squat?",
        ):
            with self.subTest(message=message):
                self.assertFalse(
                    chat_module._detect_workout_recommendation_intent(message)
                )
        muscles, equipment, constraint_status = (
            chat_module._parse_workout_recommendation_constraints(
                "Recommend upper chest exercises with a cable machine"
            )
        )
        self.assertEqual(muscles, ["Upper Chest"])
        self.assertEqual(equipment, ["Cable Machine"])
        self.assertEqual(constraint_status, (False, False, False))

    def test_route_preserves_baseline_order_and_caps_at_five(self):
        ranked_results = []
        recommend = (
            chat_module.workout_recommendation_service.recommend_workouts
        )

        def capture_result(*args, **kwargs):
            result = recommend(*args, **kwargs)
            ranked_results.append(result)
            return result

        with patch.object(
            chat_module.workout_recommendation_service,
            "recommend_workouts",
            side_effect=capture_result,
        ):
            response = self.client.post(
                "/api/chat", json={"message": "Gợi ý bài tập ngực"}
            )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(
            set(body), {"reply", "status", "conversation_id", "action"}
        )
        self.assertEqual(body["status"], "success")
        self.assertIsNone(body["action"])
        recommendations = ranked_results[0]["recommendations"]
        self.assertEqual(len(recommendations), 5)
        self.assertEqual(
            [item["rank"] for item in recommendations], [1, 2, 3, 4, 5]
        )
        canonical_ids = [item["canonical_id"] for item in recommendations]
        self.assertEqual(len(canonical_ids), len(set(canonical_ids)))
        previous_position = -1
        for item in recommendations:
            resolved = self.resolver.resolve(item["canonical_id"], item["slug"])
            self.assertEqual(resolved["status"], "resolved")
            self.assertEqual(resolved["exercise"]["id"], item["canonical_id"])
            position = body["reply"].find(item["exercise"]["name"])
            self.assertGreater(position, previous_position)
            previous_position = position
        self.assertIn("không dùng mục tiêu hoặc mức độ hoạt động", body["reply"])
        self._assert_only_conversation_writes()

    def test_explicit_muscle_and_equipment_filters_can_return_fewer_than_five(self):
        ranked_results = []
        recommend = (
            chat_module.workout_recommendation_service.recommend_workouts
        )

        def capture_result(*args, **kwargs):
            result = recommend(*args, **kwargs)
            ranked_results.append(result)
            return result

        with patch.object(
            chat_module.workout_recommendation_service,
            "recommend_workouts",
            side_effect=capture_result,
        ):
            response = self.client.post(
                "/api/chat",
                json={"message": "Gợi ý bài tập bụng với Ab Wheel"},
            )

        self.assertEqual(response.status_code, 200)
        recommendations = ranked_results[0]["recommendations"]
        self.assertEqual(len(recommendations), 1)
        self.assertEqual(recommendations[0]["exercise"]["name"], "Ab Wheel Rollout")
        self.assertIn("Đã áp dụng bộ lọc thiết bị", response.json()["reply"])
        self._assert_only_conversation_writes()

    def test_principal_scopes_profile_and_history_despite_spoofed_payload(self):
        records = self.resolver.list_exercises()
        exercise_a, exercise_b = records[:2]
        self.history.documents = [
            self._history_session(self.user_a, exercise_a),
            self._history_session(self.user_b, exercise_b),
        ]
        observed_contexts = []
        recommend = (
            chat_module.workout_recommendation_service.recommend_workouts
        )

        def capture_context(context, *args, **kwargs):
            observed_contexts.append(copy.deepcopy(context))
            return recommend(context, *args, **kwargs)

        with patch.object(
            chat_module.workout_recommendation_service,
            "recommend_workouts",
            side_effect=capture_context,
        ):
            response = self.client.post(
                "/api/chat",
                json={
                    "message": "Gợi ý bài tập",
                    "owner_id": str(self.user_b["_id"]),
                    "user_id": str(self.user_b["_id"]),
                    "context": {"email": self.user_b["email"]},
                    "history": [self._history_session(self.user_b, exercise_b)],
                },
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(observed_contexts[0]["profile_status"], "available")
        self.assertEqual(
            observed_contexts[0]["recent_exercise_session_counts"],
            {exercise_a["id"]: 1},
        )
        profile_queries = [
            query for query in self.users.queries if query.get("email")
        ]
        self.assertEqual(profile_queries, [{"email": self.user_a["email"]}])
        history_query = self.history.queries[0]["$or"]
        self.assertTrue(history_query)
        self.assertTrue(
            all(
                str(value) != str(self.user_b["_id"])
                and value != self.user_b["email"]
                for clause in history_query
                for value in clause.values()
            )
        )
        self._assert_only_conversation_writes()

    def test_unknown_equipment_and_injury_constraints_fail_closed(self):
        response = self.client.post(
            "/api/chat",
            json={
                "message": "Gợi ý bài tập lưng với dây kháng lực",
            },
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn(
            "chưa áp dụng ràng buộc chưa hỗ trợ",
            response.json()["reply"].lower(),
        )
        self.assertEqual(self.users.queries, [])
        self.assertEqual(self.history.queries, [])

        muscle_response = self.client.post(
            "/api/chat", json={"message": "Gợi ý bài tập chân"}
        )
        self.assertEqual(muscle_response.status_code, 200)
        self.assertIn(
            "chưa áp dụng ràng buộc chưa hỗ trợ",
            muscle_response.json()["reply"].lower(),
        )
        self.assertEqual(self.users.queries, [])
        self.assertEqual(self.history.queries, [])

        injury_response = self.client.post(
            "/api/chat",
            json={"message": "Recommend exercises for back pain"},
        )
        self.assertEqual(injury_response.status_code, 200)
        self.assertIn("không thể xác nhận bài tập phù hợp", injury_response.json()["reply"])
        self.assertEqual(self.users.queries, [])
        self.assertEqual(self.history.queries, [])
        self._assert_only_conversation_writes()

    def test_mixed_recommendation_and_plan_write_stays_read_only(self):
        response = self.client.post(
            "/api/chat",
            json={
                "message": (
                    "Gợi ý bài tập ngực rồi thêm bài phù hợp vào kế hoạch của tôi"
                )
            },
        )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertIsNone(body["action"])
        self.assertIn("không ghi hồ sơ", body["reply"])
        self.assertEqual(self.plans.queries, [])
        self.assertEqual(self.plans.write_calls, [])
        self._assert_only_conversation_writes()

    def test_goal_experience_schedule_and_location_are_disclosed_as_unfiltered(self):
        response = self.client.post(
            "/api/chat",
            json={
                "message": (
                    "Gợi ý bài tập tăng cơ cho người mới, 3 buổi mỗi tuần ở nhà"
                )
            },
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn(
            "danh sách chưa được lọc theo mục tiêu, kinh nghiệm, lịch tập hoặc địa điểm",
            response.json()["reply"].lower(),
        )
        self._assert_only_conversation_writes()

    def test_empty_history_and_history_read_error_are_distinct(self):
        empty_response = self.client.post(
            "/api/chat", json={"message": "Gợi ý bài tập"}
        )
        self.assertIn(
            "Lịch sử đọc được không có bản ghi khớp",
            empty_response.json()["reply"],
        )

        self.history.read_error = RuntimeError("synthetic read failure")
        error_response = self.client.post(
            "/api/chat", json={"message": "Gợi ý bài tập"}
        )
        self.assertIn(
            "Không đọc được lịch sử tập",
            error_response.json()["reply"],
        )
        self.assertEqual(error_response.status_code, 200)
        self._assert_only_conversation_writes()

    def test_unavailable_generated_catalog_has_controlled_reply(self):
        with patch.object(chat_module, "exercise_catalog_resolver") as resolver:
            resolver.available = False
            response = self.client.post(
                "/api/chat", json={"message": "Gợi ý bài tập ngực"}
            )

        self.assertEqual(response.status_code, 200)
        self.assertIn(
            "danh mục bài tập đã xác minh hiện không khả dụng",
            response.json()["reply"].lower(),
        )
        self.assertNotIn("1.", response.json()["reply"])
        self._assert_only_conversation_writes()

    def test_historical_yesterday_question_stays_on_existing_grounding_path(self):
        yesterday = datetime.now(chat_module.ICT_ZONE).date() - timedelta(days=1)
        yesterday_iso = yesterday.strftime("%Y-%m-%d")
        exercise = self.resolver.list_exercises()[0]
        session = self._history_session(self.user_a, exercise)
        session["date"] = yesterday_iso
        session["started_at"] = datetime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            10,
            tzinfo=chat_module.ICT_ZONE,
        ).astimezone(timezone.utc).isoformat()
        session["finished_at"] = datetime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
            11,
            tzinfo=chat_module.ICT_ZONE,
        ).astimezone(timezone.utc).isoformat()
        self.history.documents.append(session)

        with patch.object(
            chat_module, "get_ai_reply", return_value="Buổi tập đã được tra cứu."
        ) as provider:
            response = self.client.post(
                "/api/chat", json={"message": "Hôm qua tôi tập gì?"}
            )

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["retrieval"]["query_type"], "SPECIFIC_DATE")
        self.assertEqual(body["retrieval"]["sessions_found"], 1)
        self.assertEqual(body["reply"], "Buổi tập đã được tra cứu.")
        provider.assert_called_once()
        self.assertEqual(self.history.write_calls, [])
        self.assertEqual(self.plans.write_calls, [])


if __name__ == "__main__":
    unittest.main()
