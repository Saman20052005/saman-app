import copy
import datetime
from bson import ObjectId
import unittest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.auth_utils import get_current_user
import backend.routers.workout as workout_module


class MemoryWorkoutCollection:
    def __init__(self):
        self.documents = []

    def insert_one(self, document):
        stored = copy.deepcopy(document)
        if "_id" not in stored:
            stored["_id"] = ObjectId()
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


if __name__ == "__main__":
    unittest.main()
