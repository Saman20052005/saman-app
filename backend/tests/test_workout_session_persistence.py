import asyncio
import copy
import datetime
import threading
from bson import ObjectId
from pymongo.errors import DuplicateKeyError
import unittest
from fastapi import FastAPI
from fastapi.testclient import TestClient

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
        # Mirrors MongoDB's built-in unique _id index.
        with self._lock:
            if any(doc["_id"] == stored["_id"] for doc in self.documents):
                raise DuplicateKeyError("E11000 duplicate key error collection: workout_history index: _id_")
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
                # Simple sort implementation
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
        cursor = self.find(query)
        data = list(cursor)
        return data[0] if data else None

    def count_documents(self, query):
        cursor = self.find(query)
        return len(list(cursor))

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


class TestWorkoutSessionPersistence(unittest.TestCase):
    def setUp(self):
        self.orig_collection = workout_module.workout_history_collection
        self.memory_collection = MemoryWorkoutCollection()
        workout_module.workout_history_collection = self.memory_collection

        self.app = FastAPI()
        self.app.include_router(workout_module.router)

        self.user_a = {
            "_id": ObjectId("650000000000000000000001"),
            "email": "user_a@saman.test",
            "full_name": "User Alpha",
        }
        self.user_b = {
            "_id": ObjectId("650000000000000000000002"),
            "email": "user_b@saman.test",
            "full_name": "User Beta",
        }
        self.active_user = self.user_a
        self.app.dependency_overrides[get_current_user] = lambda: self.active_user
        self.client = TestClient(self.app)

    def tearDown(self):
        workout_module.workout_history_collection = self.orig_collection
        self.app.dependency_overrides.clear()

    def test_post_session_and_canonical_id_and_date(self):
        self.active_user = self.user_a

        # UTC timestamp corresponding to 2026-10-12 18:30:00 in Vietnam (UTC+7)
        # 18:30 VN = 11:30 UTC on 2026-10-12
        payload = {
            "id": "demo-session-client-1",
            "planName": "Upper Body Strength",
            "startedAt": "2026-10-12T11:30:00.000Z",
            "finishedAt": "2026-10-12T12:05:00.000Z",
            "exerciseLogs": [
                {
                    "exerciseId": "db-bench-press",
                    "exerciseSlug": "dumbbell-bench-press",
                    "setNumber": 1,
                    "repsCompleted": 10,
                    "unit": "reps",
                    "secondsCompleted": None,
                    "weightKg": 20.0,
                    "isCompleted": True,
                    "restTakenSeconds": 60,
                    "cvDetected": False,
                },
                {
                    "exerciseId": "plank",
                    "exerciseSlug": "plank",
                    "setNumber": 2,
                    "repsCompleted": 0,
                    "unit": "seconds",
                    "secondsCompleted": 60,
                    "weightKg": 0.0,
                    "isCompleted": True,
                    "restTakenSeconds": 45,
                    "cvDetected": False,
                },
            ],
            "totalDurationMinutes": 35,
            "totalVolumeKg": 200,
        }

        res = self.client.post("/api/workouts/sessions", json=payload)
        self.assertEqual(res.status_code, 201)

        body = res.json()
        self.assertIn("session_id", body)
        self.assertIn("session", body)

        session_out = body["session"]
        canonical_id = body["session_id"]
        self.assertEqual(session_out["id"], canonical_id)
        self.assertEqual(session_out["planName"], "Upper Body Strength")
        self.assertEqual(session_out["totalDurationMinutes"], 35)
        self.assertEqual(session_out["totalVolumeKg"], 200)
        self.assertEqual(len(session_out["exerciseLogs"]), 2)
        self.assertEqual(session_out["exerciseLogs"][1]["unit"], "seconds")
        self.assertEqual(session_out["exerciseLogs"][1]["secondsCompleted"], 60)

        # Check DB doc directly
        stored = self.memory_collection.documents[0]
        self.assertEqual(stored["user_id"], str(self.user_a["_id"]))
        self.assertIsNone(stored["plan_id"])
        self.assertEqual(stored["plan_name"], "Upper Body Strength")
        self.assertEqual(stored["date"], "2026-10-12")

    def test_untrusted_client_owner_is_ignored(self):
        self.active_user = self.user_a
        payload = {
            "id": "client-id",
            "planName": "Free Workout",
            "startedAt": "2026-10-12T10:00:00Z",
            "finishedAt": "2026-10-12T10:30:00Z",
            "user_id": "malicious_spoofed_user",
            "email": "spoof@evil.com",
            "exerciseLogs": [],
            "totalDurationMinutes": 30,
            "totalVolumeKg": 0,
        }

        res = self.client.post("/api/workouts/sessions", json=payload)
        self.assertEqual(res.status_code, 201)

        stored = self.memory_collection.documents[0]
        # Must be authenticated user_id, NOT spoofed
        self.assertEqual(stored["user_id"], str(self.user_a["_id"]))
        self.assertEqual(stored["email"], self.user_a["email"])

    def test_history_and_detail_cross_user_isolation(self):
        # User A logs a session
        self.active_user = self.user_a
        res_a = self.client.post("/api/workouts/sessions", json={
            "planName": "User A Workout",
            "startedAt": "2026-10-12T10:00:00Z",
            "finishedAt": "2026-10-12T10:45:00Z",
            "exerciseLogs": [],
            "totalDurationMinutes": 45,
            "totalVolumeKg": 500,
        })
        self.assertEqual(res_a.status_code, 201)
        session_a_id = res_a.json()["session_id"]

        # User B logs a session
        self.active_user = self.user_b
        res_b = self.client.post("/api/workouts/sessions", json={
            "planName": "User B Workout",
            "startedAt": "2026-10-12T11:00:00Z",
            "finishedAt": "2026-10-12T11:30:00Z",
            "exerciseLogs": [],
            "totalDurationMinutes": 30,
            "totalVolumeKg": 300,
        })
        self.assertEqual(res_b.status_code, 201)
        session_b_id = res_b.json()["session_id"]

        # Check History for User A
        self.active_user = self.user_a
        res_hist_a = self.client.get("/api/workouts/history")
        self.assertEqual(res_hist_a.status_code, 200)
        hist_a_body = res_hist_a.json()
        self.assertIn("sessions", hist_a_body)
        self.assertEqual(len(hist_a_body["sessions"]), 1)
        self.assertEqual(hist_a_body["sessions"][0]["id"], session_a_id)
        self.assertEqual(hist_a_body["sessions"][0]["planName"], "User A Workout")

        # Check Detail for User A on Session A (Success)
        res_detail_a = self.client.get(f"/api/workouts/sessions/{session_a_id}")
        self.assertEqual(res_detail_a.status_code, 200)
        self.assertEqual(res_detail_a.json()["session"]["id"], session_a_id)

        # User B attempts to access User A's session -> Must return 404 (isolation)
        self.active_user = self.user_b
        res_detail_b_on_a = self.client.get(f"/api/workouts/sessions/{session_a_id}")
        self.assertEqual(res_detail_b_on_a.status_code, 404)

        # Invalid or non-existent session ID -> 404
        res_invalid = self.client.get("/api/workouts/sessions/650000000000000000009999")
        self.assertEqual(res_invalid.status_code, 404)


class BarrierWorkoutCollection(MemoryWorkoutCollection):
    """Forces concurrent writers to reach insert_one together."""

    def __init__(self, parties):
        super().__init__()
        self.barrier = threading.Barrier(parties, timeout=10)

    def insert_one(self, document):
        self.barrier.wait()
        return super().insert_one(document)


class TestWorkoutSessionIdempotency(unittest.TestCase):
    CLIENT_ID = "ws-0123456789abcdef0123456789abcdef"

    def setUp(self):
        self.orig_collection = workout_module.workout_history_collection
        self.memory_collection = MemoryWorkoutCollection()
        workout_module.workout_history_collection = self.memory_collection

        self.app = FastAPI()
        self.app.include_router(workout_module.router)
        self.user_a = {"_id": ObjectId("650000000000000000000001"), "email": "user_a@saman.test"}
        self.user_b = {"_id": ObjectId("650000000000000000000002"), "email": "user_b@saman.test"}
        self.active_user = self.user_a
        self.app.dependency_overrides[get_current_user] = lambda: self.active_user
        self.client = TestClient(self.app)

    def tearDown(self):
        workout_module.workout_history_collection = self.orig_collection
        self.app.dependency_overrides.clear()

    def _payload(self, client_id=None, weight=22.0, started="2026-10-28T14:08:15.860Z"):
        return {
            "id": client_id or self.CLIENT_ID,
            "planName": "Barbell Bench Press",
            "startedAt": started,
            "finishedAt": "2026-10-28T14:10:02.123Z",
            "exerciseLogs": [{
                "exerciseId": "barbell-bench-press",
                "exerciseSlug": "barbell-bench-press",
                "setNumber": 1,
                "repsCompleted": 9,
                "weightKg": weight,
                "isCompleted": True,
            }],
            "totalDurationMinutes": 1,
            "totalVolumeKg": int(round(weight * 9)),
        }

    def test_retry_after_committed_save_returns_same_canonical_id(self):
        first = self.client.post("/api/workouts/sessions", json=self._payload())
        # Response lost in transit (e.g. gateway 503); client retries the same snapshot.
        retry = self.client.post("/api/workouts/sessions", json=self._payload())

        self.assertEqual(first.status_code, 201)
        self.assertEqual(retry.status_code, 201)
        self.assertEqual(len(self.memory_collection.documents), 1)
        canonical_id = first.json()["session_id"]
        self.assertEqual(retry.json()["session_id"], canonical_id)
        self.assertEqual(retry.json()["session"]["id"], canonical_id)
        self.assertEqual(retry.json()["session"], first.json()["session"])
        self.assertTrue(ObjectId.is_valid(canonical_id))
        stored = self.memory_collection.documents[0]
        self.assertEqual(stored["client_id"], self.CLIENT_ID)
        self.assertEqual(stored["exercise_logs"][0]["weight_kg"], 22.0)
        self.assertEqual(stored["exercise_logs"][0]["reps_completed"], 9)
        self.assertEqual(stored["total_volume_kg"], 198)

        detail = self.client.get(f"/api/workouts/sessions/{canonical_id}")
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.json()["session"]["totalVolumeKg"], 198)

    def test_concurrent_requests_same_identity_create_one_document(self):
        collection = BarrierWorkoutCollection(parties=2)
        workout_module.workout_history_collection = collection
        results, errors = [], []

        def worker():
            try:
                session = workout_module.WorkoutSession(**self._payload())
                results.append(asyncio.run(workout_module.log_workout_session(session, self.user_a)))
            except Exception as exc:  # recorded and asserted below
                errors.append(exc)

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=15)

        self.assertEqual(errors, [])
        self.assertEqual(len(results), 2)
        self.assertEqual(len(collection.documents), 1)
        self.assertEqual(results[0]["session_id"], results[1]["session_id"])
        self.assertEqual(results[0]["session_id"], str(collection.documents[0]["_id"]))

    def test_conflicting_payload_for_same_identity_is_rejected_without_overwrite(self):
        first = self.client.post("/api/workouts/sessions", json=self._payload())
        conflict = self.client.post("/api/workouts/sessions", json=self._payload(weight=30.0))

        self.assertEqual(first.status_code, 201)
        self.assertEqual(conflict.status_code, 409)
        self.assertEqual(len(self.memory_collection.documents), 1)
        stored = self.memory_collection.documents[0]
        self.assertEqual(stored["exercise_logs"][0]["weight_kg"], 22.0)
        self.assertEqual(stored["total_volume_kg"], 198)

    def test_same_client_identity_for_two_users_stays_isolated(self):
        res_a = self.client.post("/api/workouts/sessions", json=self._payload())
        self.active_user = self.user_b
        res_b = self.client.post("/api/workouts/sessions", json=self._payload())

        self.assertEqual(res_a.status_code, 201)
        self.assertEqual(res_b.status_code, 201)
        id_a, id_b = res_a.json()["session_id"], res_b.json()["session_id"]
        self.assertNotEqual(id_a, id_b)
        self.assertEqual(len(self.memory_collection.documents), 2)
        self.assertEqual(self.client.get(f"/api/workouts/sessions/{id_a}").status_code, 404)
        self.assertEqual(self.client.get(f"/api/workouts/sessions/{id_b}").status_code, 200)
        self.assertEqual([s["id"] for s in self.client.get("/api/workouts/history").json()["sessions"]], [id_b])

    def test_legacy_client_ids_are_never_deduplicated(self):
        first = self.client.post("/api/workouts/sessions", json=self._payload(client_id="demo-session-2"))
        second = self.client.post(
            "/api/workouts/sessions",
            json=self._payload(client_id="demo-session-2", started="2026-10-28T14:20:00.000Z"),
        )

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 201)
        self.assertNotEqual(first.json()["session_id"], second.json()["session_id"])
        self.assertEqual(len(self.memory_collection.documents), 2)

    def test_legacy_documents_remain_readable(self):
        legacy_id = ObjectId("6ae2007f4cbce547f0e0fba9")
        self.memory_collection.documents.append({
            "_id": legacy_id,
            "user_id": str(self.user_a["_id"]),
            "client_id": "demo-session-1",
            "plan_name": "Barbell Bench Press",
            "started_at": datetime.datetime(2026, 10, 28, 14, 2, 0),
            "finished_at": datetime.datetime(2026, 10, 28, 14, 4, 0),
            "exercise_logs": [{
                "exercise_id": "barbell-bench-press",
                "exercise_slug": "barbell-bench-press",
                "set_number": 1,
                "reps_completed": 9,
                "weight_kg": 22.0,
                "is_completed": True,
            }],
            "total_volume_kg": 198,
        })

        detail = self.client.get(f"/api/workouts/sessions/{legacy_id}")
        by_client_id = self.client.get("/api/workouts/sessions/demo-session-1")
        history = self.client.get("/api/workouts/history")

        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.json()["session"]["id"], str(legacy_id))
        self.assertEqual(detail.json()["session"]["totalVolumeKg"], 198)
        self.assertEqual(by_client_id.status_code, 200)
        self.assertEqual(history.json()["sessions"][0]["id"], str(legacy_id))


if __name__ == "__main__":
    unittest.main()
