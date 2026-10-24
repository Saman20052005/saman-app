import copy
import datetime
from bson import ObjectId
import unittest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import backend.routers.workout as workout_module


class MemoryCollection:
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

    def find_one(self, query):
        for doc in self.documents:
            if self._match(doc, query):
                return copy.deepcopy(doc)
        return None

    def update_one(self, query, update):
        target = None
        for doc in self.documents:
            if self._match(doc, query):
                target = doc
                break

        class UpdateResult:
            def __init__(self, matched_count, modified_count):
                self.matched_count = matched_count
                self.modified_count = modified_count

        if not target:
            return UpdateResult(0, 0)

        if "$set" in update:
            for k, v in update["$set"].items():
                target[k] = copy.deepcopy(v)

        return UpdateResult(1, 1)

    def _match(self, doc, query):
        for k, v in query.items():
            if k == "$or":
                if not any(self._match_subquery(doc, opt) for opt in v):
                    return False
            elif k == "$and":
                if not all(self._match(doc, opt) for opt in v):
                    return False
            else:
                if doc.get(k) != v:
                    return False
        return True

    def _match_subquery(self, doc, query):
        for k, v in query.items():
            if doc.get(k) != v:
                return False
        return True


class TestWorkoutPlanUpdate(unittest.TestCase):
    def setUp(self):
        self.orig_custom_plans = workout_module.custom_plans_collection
        self.orig_workout_history = workout_module.workout_history_collection
        self.orig_get_by_email = workout_module.user_repo.get_by_email

        self.memory_custom_plans = MemoryCollection()
        self.memory_workout_history = MemoryCollection()

        workout_module.custom_plans_collection = self.memory_custom_plans
        workout_module.workout_history_collection = self.memory_workout_history

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

        def fake_get_by_email(email):
            if email == self.user_a["email"]:
                return self.user_a
            elif email == self.user_b["email"]:
                return self.user_b
            return None

        workout_module.user_repo.get_by_email = fake_get_by_email

        self.app = FastAPI()
        self.app.include_router(workout_module.router)

        self.active_user = self.user_a
        self.app.dependency_overrides[workout_module.get_current_user] = lambda: self.active_user
        self.app.dependency_overrides[workout_module.verify_token] = lambda: self.active_user["email"]
        self.client = TestClient(self.app)

    def tearDown(self):
        workout_module.custom_plans_collection = self.orig_custom_plans
        workout_module.workout_history_collection = self.orig_workout_history
        workout_module.user_repo.get_by_email = self.orig_get_by_email
        self.app.dependency_overrides.clear()

    def _valid_plan_payload(self, name="Updated Plan Name"):
        return {
            "name": name,
            "description": "Updated description with more focus",
            "difficulty": "intermediate",
            "duration_minutes": 45,
            "target_muscles": ["chest", "triceps"],
            "exercises": [
                {
                    "name": "Push-up",
                    "sets": 4,
                    "reps": 15,
                    "weight": 0.0,
                    "rest_time": 60,
                },
                {
                    "name": "Triceps Dips",
                    "sets": 3,
                    "reps": 12,
                    "weight": 0.0,
                    "rest_time": 45,
                },
            ],
        }

    def test_update_workout_plan_success(self):
        # Create a plan belonging to user A
        plan_id = ObjectId()
        self.memory_custom_plans.insert_one({
            "_id": plan_id,
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "name": "Original Plan",
            "description": "Original description",
            "difficulty": "beginner",
            "duration_minutes": 30,
            "target_muscles": ["chest"],
            "exercises": [
                {
                    "name": "Push-up",
                    "sets": 3,
                    "reps": 10,
                    "weight": 0.0,
                    "rest_time": 60,
                }
            ],
            "created_at": datetime.datetime.now(datetime.timezone.utc),
        })

        self.active_user = self.user_a
        update_payload = self._valid_plan_payload()

        res = self.client.put(f"/api/workouts/plans/{plan_id}", json=update_payload)
        self.assertEqual(res.status_code, 200)

        body = res.json()
        self.assertIn("plan", body)
        self.assertEqual(body["message"], "Workout plan updated successfully")
        updated_plan = body["plan"]
        self.assertEqual(body["id"], str(plan_id))
        self.assertEqual(updated_plan["_id"], str(plan_id))
        self.assertEqual(updated_plan["name"], "Updated Plan Name")
        self.assertEqual(updated_plan["duration_minutes"], 45)
        self.assertEqual(updated_plan["difficulty"], "intermediate")
        self.assertEqual(len(updated_plan["exercises"]), 2)

        # Invariant: workout_history_collection must be completely untouched
        self.assertEqual(len(self.memory_workout_history.documents), 0)

    def test_update_workout_plan_cross_user_isolation(self):
        # Plan belongs to user A
        plan_id = ObjectId()
        self.memory_custom_plans.insert_one({
            "_id": plan_id,
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "name": "User A Secret Plan",
            "description": "User A only",
            "difficulty": "advanced",
            "duration_minutes": 60,
            "target_muscles": ["legs"],
            "exercises": [],
        })

        # User B tries to update User A's plan
        self.active_user = self.user_b
        res = self.client.put(f"/api/workouts/plans/{plan_id}", json=self._valid_plan_payload("Hacked Plan"))
        self.assertEqual(res.status_code, 404)

        # Verify plan was NOT updated
        stored = self.memory_custom_plans.find_one({"_id": plan_id})
        self.assertEqual(stored["name"], "User A Secret Plan")

        # Invariant: 0 writes to workout history
        self.assertEqual(len(self.memory_workout_history.documents), 0)

    def test_update_workout_plan_not_found_or_invalid_id(self):
        self.active_user = self.user_a

        # Non-existent valid ObjectId
        non_existent_id = ObjectId()
        res = self.client.put(f"/api/workouts/plans/{non_existent_id}", json=self._valid_plan_payload())
        self.assertEqual(res.status_code, 404)

        # Invalid ObjectId format
        res_invalid = self.client.put("/api/workouts/plans/invalid-id-123", json=self._valid_plan_payload())
        self.assertEqual(res_invalid.status_code, 404)

        # Invariant: 0 writes to workout history
        self.assertEqual(len(self.memory_workout_history.documents), 0)


if __name__ == "__main__":
    unittest.main()
