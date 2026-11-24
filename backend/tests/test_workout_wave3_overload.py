import copy
from datetime import datetime, timezone
import unittest

from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.auth_utils import get_current_user
import backend.routers.workout as workout_module


class MemoryWorkoutCollection:
    def __init__(self):
        self.documents = []

    def find(self, query):
        results = [copy.deepcopy(doc) for doc in self.documents if self._match_subquery(doc, query)]

        class Cursor:
            def __init__(self, data):
                self.data = data

            def sort(self, sort_spec):
                for field, direction in reversed(sort_spec):
                    reverse = direction == -1
                    self.data.sort(
                        key=lambda d: (d.get(field) is not None, d.get(field) or datetime.min.replace(tzinfo=timezone.utc)),
                        reverse=reverse,
                    )
                return self

            def skip(self, n):
                self.data = self.data[n:]
                return self

            def limit(self, n):
                if n is not None:
                    self.data = self.data[:n]
                return self

            def __iter__(self):
                return iter(self.data)

        return Cursor(results)

    def _match_subquery(self, doc, query):
        for k, v in query.items():
            if k == "$or":
                if not any(self._match_subquery(doc, option) for option in v):
                    return False
            elif k == "$and":
                if not all(self._match_subquery(doc, option) for option in v):
                    return False
            else:
                if doc.get(k) != v:
                    return False
        return True


class TestWorkoutWave3CvOverload(unittest.TestCase):
    def setUp(self):
        self.orig_history = workout_module.workout_history_collection
        self.memory_history = MemoryWorkoutCollection()
        workout_module.workout_history_collection = self.memory_history

        self.app = FastAPI()
        self.app.include_router(workout_module.router)

        self.user = {
            "_id": ObjectId("650000000000000000000099"),
            "email": "wave3_cv@saman.test",
            "full_name": "Wave3 CV Tester",
        }
        self.app.dependency_overrides[get_current_user] = lambda: self.user
        self.client = TestClient(self.app)

    def tearDown(self):
        workout_module.workout_history_collection = self.orig_history
        self.app.dependency_overrides.clear()

    def test_cv_form_verified_add_weight_when_score_ge_85_and_low_fast_ratio(self):
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user["_id"]),
            "email": self.user["email"],
            "started_at": datetime(2026, 11, 20, 9, 0, 0, tzinfo=timezone.utc),
            "exercise_logs": [
                {
                    "exercise_id": "lat-pulldown",
                    "exercise_slug": "lat-pulldown",
                    "set_number": 1,
                    "reps_completed": 10,
                    "weight_kg": 60.0,
                    "is_completed": True,
                    "cv_detected": True,
                    "cv_form_summary": {
                        "valid_reps": 9,
                        "fast_reps": 1,
                        "avg_elbow_angle_deg": 86.0,
                        "avg_tempo_sec": 2.3,
                        "abort_count": 0,
                    },
                }
            ],
        })

        res = self.client.get(
            "/api/workouts/last-performance",
            params={"exercise_ids": "lat-pulldown"},
        )
        self.assertEqual(res.status_code, 200)
        perf = res.json()["items"]["lat-pulldown"]
        self.assertEqual(perf["last_weight_kg"], 60.0)
        self.assertEqual(perf["last_reps"], 10)
        self.assertEqual(perf["suggested_weight_kg"], 62.5)
        self.assertEqual(perf["suggested_reps"], 10)
        self.assertEqual(perf["suggestion_reason"], "cv_form_verified_add_weight")
        self.assertEqual(perf["cv_form_score"], 90)
        self.assertEqual(perf["cv_fast_reps"], 1)

    def test_cv_form_verified_add_rep_for_bodyweight_exercise(self):
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user["_id"]),
            "email": self.user["email"],
            "started_at": datetime(2026, 11, 20, 9, 0, 0, tzinfo=timezone.utc),
            "exercise_logs": [
                {
                    "exercise_id": "pull-up",
                    "exercise_slug": "pull-up",
                    "set_number": 1,
                    "reps_completed": 10,
                    "weight_kg": 0.0,
                    "is_completed": True,
                    "cv_detected": True,
                    "cv_form_summary": {
                        "valid_reps": 10,
                        "fast_reps": 0,
                        "avg_elbow_angle_deg": 82.0,
                        "avg_tempo_sec": 2.5,
                        "abort_count": 0,
                    },
                }
            ],
        })

        res = self.client.get(
            "/api/workouts/last-performance",
            params={"exercise_ids": "pull-up"},
        )
        self.assertEqual(res.status_code, 200)
        perf = res.json()["items"]["pull-up"]
        self.assertEqual(perf["suggested_weight_kg"], 0.0)
        self.assertEqual(perf["suggested_reps"], 11)
        self.assertEqual(perf["suggestion_reason"], "cv_form_verified_add_rep")
        self.assertEqual(perf["cv_form_score"], 100)
        self.assertEqual(perf["cv_fast_reps"], 0)

    def test_cv_form_refine_technique_when_score_below_70(self):
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user["_id"]),
            "email": self.user["email"],
            "started_at": datetime(2026, 11, 20, 9, 0, 0, tzinfo=timezone.utc),
            "exercise_logs": [
                {
                    "exercise_id": "barbell-squat",
                    "exercise_slug": "barbell-squat",
                    "set_number": 1,
                    "reps_completed": 10,
                    "weight_kg": 80.0,
                    "is_completed": True,
                    "cv_detected": True,
                    "cv_form_summary": {
                        "valid_reps": 6,
                        "fast_reps": 4,
                        "avg_elbow_angle_deg": 102.0,
                        "avg_tempo_sec": 1.1,
                        "abort_count": 2,
                    },
                }
            ],
        })

        res = self.client.get(
            "/api/workouts/last-performance",
            params={"exercise_ids": "barbell-squat"},
        )
        self.assertEqual(res.status_code, 200)
        perf = res.json()["items"]["barbell-squat"]
        # 6/10 = 60, minus min(15, 2*5)=10 -> 50
        self.assertEqual(perf["cv_form_score"], 50)
        self.assertEqual(perf["cv_fast_reps"], 4)
        self.assertEqual(perf["suggested_weight_kg"], 80.0)
        self.assertEqual(perf["suggested_reps"], 10)
        self.assertEqual(perf["suggestion_reason"], "cv_form_refine_technique")

    def test_cv_form_moderate_score_maintains_current_load(self):
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user["_id"]),
            "email": self.user["email"],
            "started_at": datetime(2026, 11, 20, 9, 0, 0, tzinfo=timezone.utc),
            "exercise_logs": [
                {
                    "exercise_id": "bicep-curl",
                    "exercise_slug": "bicep-curl",
                    "set_number": 1,
                    "reps_completed": 10,
                    "weight_kg": 15.0,
                    "is_completed": True,
                    "cv_detected": True,
                    "cv_form_summary": {
                        "valid_reps": 8,
                        "fast_reps": 2,
                        "avg_elbow_angle_deg": 55.0,
                        "avg_tempo_sec": 1.8,
                        "abort_count": 0,
                    },
                }
            ],
        })

        res = self.client.get(
            "/api/workouts/last-performance",
            params={"exercise_ids": "bicep-curl"},
        )
        self.assertEqual(res.status_code, 200)
        perf = res.json()["items"]["bicep-curl"]
        self.assertEqual(perf["cv_form_score"], 80)
        self.assertEqual(perf["cv_fast_reps"], 2)
        self.assertEqual(perf["suggested_weight_kg"], 15.0)
        self.assertEqual(perf["suggested_reps"], 10)
        self.assertEqual(perf["suggestion_reason"], "maintain_current_load")

    def test_session_level_cv_summary_fallback(self):
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user["_id"]),
            "email": self.user["email"],
            "started_at": datetime(2026, 11, 20, 9, 0, 0, tzinfo=timezone.utc),
            "cv_form_summary": {
                "valid_reps": 9,
                "fast_reps": 1,
                "avg_elbow_angle_deg": 84.0,
                "avg_tempo_sec": 2.1,
                "abort_count": 0,
            },
            "exercise_logs": [
                {
                    "exercise_id": "overhead-press",
                    "exercise_slug": "overhead-press",
                    "set_number": 1,
                    "reps_completed": 10,
                    "weight_kg": 40.0,
                    "is_completed": True,
                }
            ],
        })

        res = self.client.get(
            "/api/workouts/last-performance",
            params={"exercise_ids": "overhead-press"},
        )
        self.assertEqual(res.status_code, 200)
        perf = res.json()["items"]["overhead-press"]
        self.assertEqual(perf["cv_form_score"], 90)
        self.assertEqual(perf["suggested_weight_kg"], 42.5)
        self.assertEqual(perf["suggestion_reason"], "cv_form_verified_add_weight")

    def test_legacy_session_without_cv_summary_preserves_existing_behavior(self):
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user["_id"]),
            "email": self.user["email"],
            "started_at": datetime(2026, 11, 20, 9, 0, 0, tzinfo=timezone.utc),
            "exercise_logs": [
                {
                    "exercise_id": "barbell-bench-press",
                    "exercise_slug": "barbell-bench-press",
                    "set_number": 1,
                    "reps_completed": 8,
                    "weight_kg": 70.0,
                    "is_completed": True,
                },
                {
                    "exercise_id": "push-up",
                    "exercise_slug": "push-up",
                    "set_number": 1,
                    "reps_completed": 12,
                    "weight_kg": 0.0,
                    "is_completed": True,
                },
            ],
        })

        res = self.client.get(
            "/api/workouts/last-performance",
            params={"exercise_ids": "barbell-bench-press,push-up"},
        )
        self.assertEqual(res.status_code, 200)
        items = res.json()["items"]

        bench = items["barbell-bench-press"]
        self.assertEqual(bench["suggested_weight_kg"], 72.5)
        self.assertEqual(bench["suggested_reps"], 8)
        self.assertEqual(bench["suggestion_reason"], "completed_target_add_weight")
        self.assertIsNone(bench["cv_form_score"])
        self.assertIsNone(bench["cv_fast_reps"])

        pushup = items["push-up"]
        self.assertEqual(pushup["suggested_weight_kg"], 0.0)
        self.assertEqual(pushup["suggested_reps"], 13)
        self.assertEqual(pushup["suggestion_reason"], "completed_target_add_rep")
        self.assertIsNone(pushup["cv_form_score"])
        self.assertIsNone(pushup["cv_fast_reps"])


if __name__ == "__main__":
    unittest.main()
