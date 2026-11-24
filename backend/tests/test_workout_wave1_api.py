import copy
from datetime import datetime, timedelta, timezone
import threading
import unittest

from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pymongo.errors import DuplicateKeyError

from backend.auth_utils import get_current_user
import backend.routers.workout as workout_module


class MemoryWorkoutCollection:
    def __init__(self):
        self.documents = []
        self._lock = threading.Lock()

    def insert_one(self, document):
        stored = copy.deepcopy(document)
        if "_id" not in stored:
            stored["_id"] = ObjectId()
        with self._lock:
            if any(doc["_id"] == stored["_id"] for doc in self.documents):
                raise DuplicateKeyError(
                    "E11000 duplicate key error collection: workout_history index: _id_"
                )
            self.documents.append(stored)

        class InsertResult:
            def __init__(self, inserted_id):
                self.inserted_id = inserted_id

        return InsertResult(stored["_id"])

    def find(self, query):
        def _match(doc):
            if "$and" in query:
                return all(self._match_subquery(doc, q) for q in query["$and"])
            return self._match_subquery(doc, query)

        results = [copy.deepcopy(doc) for doc in self.documents if _match(doc)]

        class Cursor:
            def __init__(self, data):
                self.data = data

            def sort(self, sort_spec):
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

    def find_one(self, query):
        data = list(self.find(query))
        return data[0] if data else None

    def count_documents(self, query):
        return len(list(self.find(query)))

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


class TestWorkoutWave1Api(unittest.TestCase):
    def setUp(self):
        self.orig_history = workout_module.workout_history_collection
        self.orig_exercises = workout_module.exercises_collection

        self.memory_history = MemoryWorkoutCollection()
        self.memory_exercises = MemoryWorkoutCollection()
        workout_module.workout_history_collection = self.memory_history
        workout_module.exercises_collection = self.memory_exercises

        self.app = FastAPI()
        self.app.include_router(workout_module.router)

        self.user_a = {
            "_id": ObjectId("650000000000000000000011"),
            "email": "wave1_a@saman.test",
            "full_name": "Wave1 User A",
        }
        self.user_b = {
            "_id": ObjectId("650000000000000000000022"),
            "email": "wave1_b@saman.test",
            "full_name": "Wave1 User B",
        }
        self.active_user = self.user_a
        self.app.dependency_overrides[get_current_user] = lambda: self.active_user
        self.client = TestClient(self.app)

    def tearDown(self):
        workout_module.workout_history_collection = self.orig_history
        workout_module.exercises_collection = self.orig_exercises
        self.app.dependency_overrides.clear()

    # ── 1. Backward Compatibility ────────────────────────────────────────────

    def test_legacy_document_defaults_in_history_and_detail(self):
        legacy_id = ObjectId("65000000000000000000aaaa")
        cv_summary = {
            "valid_reps": 10,
            "fast_reps": 1,
            "avg_elbow_angle_deg": 88.5,
            "avg_tempo_sec": 2.4,
            "abort_count": 0,
        }
        self.memory_history.documents.append({
            "_id": legacy_id,
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "plan_name": "Legacy Push Day",
            "started_at": datetime(2026, 10, 20, 10, 0, 0, tzinfo=timezone.utc),
            "finished_at": datetime(2026, 10, 20, 10, 40, 0, tzinfo=timezone.utc),
            "exercise_logs": [
                {
                    "exercise_id": "ex-bench",
                    "exercise_slug": "barbell-bench-press",
                    "set_number": 1,
                    "reps_completed": 8,
                    "weight_kg": 60.0,
                    "is_completed": True,
                    "cv_detected": True,
                    "cv_form_summary": cv_summary,
                }
            ],
            "total_duration_minutes": 40,
            "total_volume_kg": 480,
            "cv_form_summary": cv_summary,
        })

        hist_res = self.client.get("/api/workouts/history")
        self.assertEqual(hist_res.status_code, 200)
        hist_sessions = hist_res.json()["sessions"]
        self.assertEqual(len(hist_sessions), 1)
        hist_log = hist_sessions[0]["exerciseLogs"][0]
        self.assertEqual(hist_log["setType"], "normal")
        self.assertIsNone(hist_log["rpe"])
        self.assertIsNone(hist_log["note"])
        self.assertIsNone(hist_log["supersetGroupId"])
        self.assertIs(hist_log["isPr"], False)
        self.assertEqual(hist_log["cvFormSummary"], cv_summary)
        self.assertEqual(hist_sessions[0]["cvFormSummary"], cv_summary)

        detail_res = self.client.get(f"/api/workouts/sessions/{legacy_id}")
        self.assertEqual(detail_res.status_code, 200)
        detail_session = detail_res.json()["session"]
        detail_log = detail_session["exerciseLogs"][0]
        self.assertEqual(detail_log["setType"], "normal")
        self.assertIsNone(detail_log["rpe"])
        self.assertIsNone(detail_log["note"])
        self.assertIsNone(detail_log["supersetGroupId"])
        self.assertIs(detail_log["isPr"], False)
        self.assertEqual(detail_session["cvFormSummary"], cv_summary)

    # ── 2. New Fields Logging & Validation ───────────────────────────────────

    def test_log_session_with_wave1_fields_and_validation(self):
        payload = {
            "planName": "Hypertrophy Upper",
            "startedAt": "2026-11-20T10:00:00Z",
            "finishedAt": "2026-11-20T10:45:00Z",
            "exerciseLogs": [
                {
                    "exerciseId": "bench-1",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 1,
                    "repsCompleted": 12,
                    "weightKg": 40.0,
                    "isCompleted": True,
                    "setType": "warmup",
                    "rpe": 5.0,
                    "note": "Warmup shoulder mobility",
                    "supersetGroupId": None,
                },
                {
                    "exerciseId": "bench-1",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 2,
                    "repsCompleted": 8,
                    "weightKg": 80.0,
                    "isCompleted": True,
                    "setType": "normal",
                    "rpe": 8.5,
                    "note": "Clean bar path",
                    "supersetGroupId": "ss-A",
                },
                {
                    "exerciseId": "row-1",
                    "exerciseSlug": "barbell-row",
                    "setNumber": 1,
                    "repsCompleted": 10,
                    "weightKg": 60.0,
                    "isCompleted": True,
                    "setType": "drop",
                    "rpe": 9.0,
                    "note": "Drop set to finish",
                    "supersetGroupId": "ss-A",
                },
                {
                    "exerciseId": "curl-1",
                    "exerciseSlug": "bicep-curl",
                    "setNumber": 1,
                    "repsCompleted": 12,
                    "weightKg": 15.0,
                    "isCompleted": True,
                    "set_type": "failure",
                    "rpe": 10.0,
                    "note": "Strict form to failure",
                    "superset_group_id": "ss-B",
                },
            ],
            "totalDurationMinutes": 45,
            "totalVolumeKg": 1800,
        }

        res = self.client.post("/api/workouts/sessions", json=payload)
        self.assertEqual(res.status_code, 201)
        body = res.json()
        logs = body["session"]["exerciseLogs"]
        self.assertEqual(len(logs), 4)

        self.assertEqual(logs[0]["setType"], "warmup")
        self.assertEqual(logs[0]["rpe"], 5.0)
        self.assertEqual(logs[0]["note"], "Warmup shoulder mobility")
        self.assertIsNone(logs[0]["supersetGroupId"])
        self.assertIs(logs[0]["isPr"], False)

        self.assertEqual(logs[1]["setType"], "normal")
        self.assertEqual(logs[1]["rpe"], 8.5)
        self.assertEqual(logs[1]["supersetGroupId"], "ss-A")

        self.assertEqual(logs[2]["setType"], "drop")
        self.assertEqual(logs[2]["rpe"], 9.0)
        self.assertEqual(logs[2]["supersetGroupId"], "ss-A")

        self.assertEqual(logs[3]["setType"], "failure")
        self.assertEqual(logs[3]["rpe"], 10.0)
        self.assertEqual(logs[3]["supersetGroupId"], "ss-B")

        # Persisted in DB and readable via GET
        session_id = body["session_id"]
        detail = self.client.get(f"/api/workouts/sessions/{session_id}")
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.json()["session"]["exerciseLogs"][2]["setType"], "drop")
        self.assertEqual(detail.json()["session"]["exerciseLogs"][3]["supersetGroupId"], "ss-B")

    def test_validation_rejects_invalid_rpe_set_type_and_long_note(self):
        base_log = {
            "exerciseId": "bench-1",
            "exerciseSlug": "barbell-bench-press",
            "setNumber": 1,
            "repsCompleted": 8,
            "weightKg": 60.0,
            "isCompleted": True,
        }

        for invalid_rpe in (0.5, 0, -1, 10.1, 11):
            bad_log = {**base_log, "rpe": invalid_rpe}
            res = self.client.post(
                "/api/workouts/sessions",
                json={"planName": "Bad RPE", "exerciseLogs": [bad_log]},
            )
            self.assertEqual(res.status_code, 422, f"Expected 422 for rpe={invalid_rpe}")

        res_type = self.client.post(
            "/api/workouts/sessions",
            json={"planName": "Bad SetType", "exerciseLogs": [{**base_log, "setType": "cluster"}]},
        )
        self.assertEqual(res_type.status_code, 422)

        res_note = self.client.post(
            "/api/workouts/sessions",
            json={"planName": "Long Note", "exerciseLogs": [{**base_log, "note": "x" * 301}]},
        )
        self.assertEqual(res_note.status_code, 422)

    # ── 3. PR Detection & Idempotency ────────────────────────────────────────

    def test_pr_detection_warmup_first_session_weight_1rm_and_no_pr(self):
        # Session 1: first time doing bench press -> warmup ignored, best working set is PR (both)
        s1_payload = {
            "planName": "Bench Day 1",
            "startedAt": "2026-11-18T10:00:00Z",
            "exerciseLogs": [
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 1,
                    "repsCompleted": 10,
                    "weightKg": 90.0,
                    "isCompleted": True,
                    "setType": "warmup",
                },
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 2,
                    "repsCompleted": 8,
                    "weightKg": 70.0,
                    "isCompleted": True,
                    "setType": "normal",
                },
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 3,
                    "repsCompleted": 10,
                    "weightKg": 80.0,  # 1RM = 80 * (1 + 10/30) = 106.67
                    "isCompleted": True,
                    "setType": "normal",
                },
            ],
        }
        r1 = self.client.post("/api/workouts/sessions", json=s1_payload)
        self.assertEqual(r1.status_code, 201)
        b1 = r1.json()
        self.assertIs(b1["session"]["exerciseLogs"][0]["isPr"], False)
        self.assertIs(b1["session"]["exerciseLogs"][1]["isPr"], False)
        self.assertIs(b1["session"]["exerciseLogs"][2]["isPr"], True)
        self.assertEqual(len(b1["new_prs"]), 1)
        self.assertEqual(b1["new_prs"][0]["setNumber"], 3)
        self.assertEqual(b1["new_prs"][0]["weightKg"], 80.0)
        self.assertEqual(b1["new_prs"][0]["repsCompleted"], 10)
        self.assertEqual(b1["new_prs"][0]["estimated1Rm"], 106.67)
        self.assertEqual(b1["new_prs"][0]["prType"], "both")

        # Session 2: does NOT beat 80kg or 106.67 1RM -> no PRs
        s2_payload = {
            "planName": "Bench Day 2 - Light",
            "startedAt": "2026-11-19T10:00:00Z",
            "exerciseLogs": [
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 1,
                    "repsCompleted": 8,
                    "weightKg": 80.0,  # 1RM = 101.33 <= 106.67, weight = 80 <= 80
                    "isCompleted": True,
                    "setType": "normal",
                },
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 2,
                    "repsCompleted": 15,
                    "weightKg": 120.0,
                    "isCompleted": True,
                    "setType": "warmup",  # warmup never counts
                },
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 3,
                    "repsCompleted": 12,
                    "weightKg": 100.0,
                    "isCompleted": False,  # incomplete never counts
                    "setType": "normal",
                },
            ],
        }
        r2 = self.client.post("/api/workouts/sessions", json=s2_payload)
        self.assertEqual(r2.status_code, 201)
        b2 = r2.json()
        self.assertEqual(b2["new_prs"], [])
        self.assertTrue(all(not log["isPr"] for log in b2["session"]["exerciseLogs"]))

        # Session 3: Set 1 beats weight only (85kg x 5 -> 1RM 99.17 < 106.67),
        # Set 2 beats 1RM only (82.5kg x 10 -> 1RM 110.0 > 106.67, weight 82.5 < 85),
        # Set 3 beats both (90kg x 8 -> 1RM 114.0 > 110.0, weight 90 > 85).
        s3_payload = {
            "planName": "Bench Day 3 - PRs",
            "startedAt": "2026-11-20T10:00:00Z",
            "exerciseLogs": [
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 1,
                    "repsCompleted": 5,
                    "weightKg": 85.0,
                    "isCompleted": True,
                    "setType": "normal",
                },
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 2,
                    "repsCompleted": 10,
                    "weightKg": 82.5,
                    "isCompleted": True,
                    "setType": "normal",
                },
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 3,
                    "repsCompleted": 8,
                    "weightKg": 90.0,
                    "isCompleted": True,
                    "setType": "failure",
                },
            ],
        }
        r3 = self.client.post("/api/workouts/log-session", json=s3_payload)
        self.assertEqual(r3.status_code, 201)
        b3 = r3.json()
        self.assertEqual(len(b3["new_prs"]), 3)
        self.assertEqual(b3["new_prs"][0]["prType"], "weight")
        self.assertEqual(b3["new_prs"][0]["estimated1Rm"], 99.17)
        self.assertEqual(b3["new_prs"][1]["prType"], "1rm")
        self.assertEqual(b3["new_prs"][1]["estimated1Rm"], 110.0)
        self.assertEqual(b3["new_prs"][2]["prType"], "both")
        self.assertEqual(b3["new_prs"][2]["estimated1Rm"], 114.0)
        self.assertTrue(all(log["isPr"] for log in b3["session"]["exerciseLogs"]))

    def test_pr_detection_idempotent_retry_does_not_compare_against_self(self):
        client_id = "ws-abcdef0123456789abcdef0123456789"
        payload = {
            "id": client_id,
            "planName": "Idempotent Bench",
            "startedAt": "2026-11-21T10:00:00Z",
            "finishedAt": "2026-11-21T10:30:00Z",
            "exerciseLogs": [
                {
                    "exerciseId": "ex-bench",
                    "exerciseSlug": "barbell-bench-press",
                    "setNumber": 1,
                    "repsCompleted": 8,
                    "weightKg": 75.0,
                    "isCompleted": True,
                    "setType": "normal",
                    "rpe": 8.0,
                    "note": "Solid",
                    "supersetGroupId": "ss-1",
                }
            ],
            "totalDurationMinutes": 30,
            "totalVolumeKg": 600,
        }

        first = self.client.post("/api/workouts/sessions", json=payload)
        self.assertEqual(first.status_code, 201)
        first_body = first.json()
        self.assertEqual(len(first_body["new_prs"]), 1)
        self.assertIs(first_body["session"]["exerciseLogs"][0]["isPr"], True)

        # Retry identical payload: must return 201, same session_id, same session, same new_prs
        retry = self.client.post("/api/workouts/sessions", json=payload)
        self.assertEqual(retry.status_code, 201)
        retry_body = retry.json()
        self.assertEqual(len(self.memory_history.documents), 1)
        self.assertEqual(retry_body["session_id"], first_body["session_id"])
        self.assertEqual(retry_body["session"], first_body["session"])
        self.assertEqual(retry_body["new_prs"], first_body["new_prs"])

        # Retry with modified client field (e.g. different rpe) -> 409 Conflict
        modified = copy.deepcopy(payload)
        modified["exerciseLogs"][0]["rpe"] = 9.5
        conflict = self.client.post("/api/workouts/sessions", json=modified)
        self.assertEqual(conflict.status_code, 409)

    def test_pr_detection_user_isolation(self):
        self.active_user = self.user_a
        self.client.post(
            "/api/workouts/sessions",
            json={
                "planName": "User A Heavy",
                "exerciseLogs": [
                    {
                        "exerciseId": "ex-squat",
                        "exerciseSlug": "barbell-squat",
                        "setNumber": 1,
                        "repsCompleted": 5,
                        "weightKg": 180.0,
                        "isCompleted": True,
                    }
                ],
            },
        )

        # User B lifting 100kg is still User B's first PR
        self.active_user = self.user_b
        res_b = self.client.post(
            "/api/workouts/sessions",
            json={
                "planName": "User B First Squat",
                "exerciseLogs": [
                    {
                        "exerciseId": "ex-squat",
                        "exerciseSlug": "barbell-squat",
                        "setNumber": 1,
                        "repsCompleted": 5,
                        "weightKg": 100.0,
                        "isCompleted": True,
                    }
                ],
            },
        )
        self.assertEqual(res_b.status_code, 201)
        self.assertEqual(len(res_b.json()["new_prs"]), 1)
        self.assertEqual(res_b.json()["new_prs"][0]["prType"], "both")

    # ── 4. Muscle Recovery Endpoint ──────────────────────────────────────────

    def test_muscle_recovery_empty_history_returns_all_six_ready(self):
        res = self.client.get("/api/workouts/muscle-recovery")
        self.assertEqual(res.status_code, 200)
        body = res.json()
        self.assertIn("generatedAt", body)
        muscles = body["muscles"]
        self.assertEqual(len(muscles), 6)
        self.assertEqual(
            [m["muscleGroup"] for m in muscles],
            ["chest", "back", "legs", "shoulders", "arms", "core"],
        )
        for m in muscles:
            self.assertEqual(m["recoveryPercent"], 100)
            self.assertEqual(m["status"], "ready")
            self.assertIsNone(m["lastTrainedAt"])
            self.assertIsNone(m["hoursSinceLastTrained"])
            self.assertEqual(m["recentSets"], 0)

    def test_muscle_recovery_recent_heavy_vs_64h_recovered_and_old_ignored(self):
        now_utc = datetime.now(timezone.utc)

        # 1) Heavy chest workout 2 hours ago (8 normal sets @ RPE 8.5)
        recent_dt = now_utc - timedelta(hours=2)
        chest_logs = [
            {
                "exercise_id": "bench-press",
                "exercise_slug": "barbell-bench-press",
                "set_number": i + 1,
                "reps_completed": 8,
                "weight_kg": 80.0,
                "is_completed": True,
                "set_type": "normal",
                "rpe": 8.5,
            }
            for i in range(8)
        ]
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "plan_name": "Heavy Chest",
            "started_at": recent_dt - timedelta(minutes=45),
            "finished_at": recent_dt,
            "exercise_logs": chest_logs,
        })

        # 2) Heavy back workout 64 hours ago (8 normal sets @ RPE 8.5) -> should be 85-100% ready
        recovered_dt = now_utc - timedelta(hours=64)
        back_logs = [
            {
                "exercise_id": "barbell-row",
                "exercise_slug": "barbell-row",
                "set_number": i + 1,
                "reps_completed": 10,
                "weight_kg": 70.0,
                "is_completed": True,
                "set_type": "normal",
                "rpe": 8.5,
            }
            for i in range(8)
        ]
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "plan_name": "Older Back Day",
            "started_at": recovered_dt - timedelta(minutes=45),
            "finished_at": recovered_dt,
            "exercise_logs": back_logs,
        })

        # 3) Very old legs workout 80 hours ago -> outside 72h window, should be ignored (100% ready)
        old_dt = now_utc - timedelta(hours=80)
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "plan_name": "Old Leg Day",
            "started_at": old_dt,
            "finished_at": old_dt,
            "exercise_logs": [
                {
                    "exercise_id": "squat",
                    "exercise_slug": "barbell-squat",
                    "set_number": i + 1,
                    "reps_completed": 8,
                    "weight_kg": 100.0,
                    "is_completed": True,
                }
                for i in range(10)
            ],
        })

        res = self.client.get("/api/workouts/muscle-recovery")
        self.assertEqual(res.status_code, 200)
        by_muscle = {m["muscleGroup"]: m for m in res.json()["muscles"]}

        chest = by_muscle["chest"]
        self.assertGreaterEqual(chest["recoveryPercent"], 25)
        self.assertLessEqual(chest["recoveryPercent"], 50)
        self.assertIn(chest["status"], ("fatigued", "recovering"))
        self.assertEqual(chest["recentSets"], 8)
        self.assertIsNotNone(chest["lastTrainedAt"])
        self.assertAlmostEqual(chest["hoursSinceLastTrained"], 2.0, delta=0.5)

        back = by_muscle["back"]
        self.assertGreaterEqual(back["recoveryPercent"], 85)
        self.assertLessEqual(back["recoveryPercent"], 100)
        self.assertEqual(back["status"], "ready")
        self.assertEqual(back["recentSets"], 8)
        self.assertAlmostEqual(back["hoursSinceLastTrained"], 64.0, delta=0.5)

        legs = by_muscle["legs"]
        self.assertEqual(legs["recoveryPercent"], 100)
        self.assertEqual(legs["status"], "ready")
        self.assertEqual(legs["recentSets"], 0)
        self.assertIsNone(legs["lastTrainedAt"])

        for untrained in ("shoulders", "arms", "core"):
            self.assertEqual(by_muscle[untrained]["recoveryPercent"], 100)
            self.assertEqual(by_muscle[untrained]["status"], "ready")

    def test_muscle_recovery_uses_exercises_collection_primary_and_secondary(self):
        # Register custom exercise in exercises_collection with secondary muscles
        self.memory_exercises.documents.append({
            "_id": ObjectId(),
            "id": "custom-press-01",
            "slug": "custom-incline-movement",
            "muscleGroup": "chest",
            "secondaryMuscles": ["triceps", "front_delts"],
        })

        now_utc = datetime.now(timezone.utc)
        recent_dt = now_utc - timedelta(hours=1)
        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "plan_name": "DB Exercise Lookup",
            "started_at": recent_dt,
            "finished_at": recent_dt,
            "exercise_logs": [
                {
                    "exercise_id": "custom-press-01",
                    "exercise_slug": "custom-incline-movement",
                    "set_number": i + 1,
                    "reps_completed": 10,
                    "weight_kg": 60.0,
                    "is_completed": True,
                    "set_type": "normal",
                    "rpe": 8.0,
                }
                for i in range(6)
            ],
        })

        res = self.client.get("/api/workouts/muscle-recovery")
        self.assertEqual(res.status_code, 200)
        by_muscle = {m["muscleGroup"]: m for m in res.json()["muscles"]}

        # Primary chest should be significantly more fatigued than secondary arms & shoulders
        self.assertLess(by_muscle["chest"]["recoveryPercent"], by_muscle["arms"]["recoveryPercent"])
        self.assertLess(by_muscle["chest"]["recoveryPercent"], by_muscle["shoulders"]["recoveryPercent"])
        self.assertLess(by_muscle["arms"]["recoveryPercent"], 100)
        self.assertLess(by_muscle["shoulders"]["recoveryPercent"], 100)
        self.assertEqual(by_muscle["legs"]["recoveryPercent"], 100)

    def test_muscle_recovery_fallback_slug_mapping_and_user_isolation(self):
        # Force fallback path with exercises_collection = None
        workout_module.exercises_collection = None
        now_utc = datetime.now(timezone.utc)
        recent_dt = now_utc - timedelta(hours=3)

        self.memory_history.documents.append({
            "_id": ObjectId(),
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "plan_name": "Full Body Fallback",
            "started_at": recent_dt,
            "finished_at": recent_dt,
            "exercise_logs": [
                {"exercise_id": "1", "exercise_slug": "push-up", "set_number": 1, "reps_completed": 20, "is_completed": True},
                {"exercise_id": "2", "exercise_slug": "lat-pulldown", "set_number": 1, "reps_completed": 12, "is_completed": True},
                {"exercise_id": "3", "exercise_slug": "leg-curl", "set_number": 1, "reps_completed": 12, "is_completed": True},
                {"exercise_id": "4", "exercise_slug": "face-pull", "set_number": 1, "reps_completed": 15, "is_completed": True},
                {"exercise_id": "5", "exercise_slug": "tricep-pushdown", "set_number": 1, "reps_completed": 12, "is_completed": True},
                {"exercise_id": "6", "exercise_slug": "hanging-leg-raise", "set_number": 1, "reps_completed": 15, "is_completed": True},
                {"exercise_id": "7", "exercise_slug": "plank", "set_number": 2, "reps_completed": 1, "is_completed": False},
            ],
        })

        res_a = self.client.get("/api/workouts/muscle-recovery")
        self.assertEqual(res_a.status_code, 200)
        by_muscle_a = {m["muscleGroup"]: m for m in res_a.json()["muscles"]}
        for group in ("chest", "back", "legs", "shoulders", "arms", "core"):
            self.assertEqual(by_muscle_a[group]["recentSets"], 1, f"Expected 1 set for {group}")
            self.assertLess(by_muscle_a[group]["recoveryPercent"], 100)

        # User B should still see 100% ready for all muscles
        self.active_user = self.user_b
        res_b = self.client.get("/api/workouts/muscle-recovery")
        self.assertEqual(res_b.status_code, 200)
        for m in res_b.json()["muscles"]:
            self.assertEqual(m["recoveryPercent"], 100)
            self.assertEqual(m["recentSets"], 0)


if __name__ == "__main__":
    unittest.main()
