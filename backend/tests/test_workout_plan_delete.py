import copy
import datetime
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pymongo.errors import PyMongoError

import backend.routers.workout as workout_module
from backend.tests.test_workout_plan_update import MemoryCollection


class DeletableMemoryCollection(MemoryCollection):
    def delete_one(self, query):
        for index, document in enumerate(self.documents):
            if self._match(document, query):
                del self.documents[index]
                return SimpleNamespace(deleted_count=1)
        return SimpleNamespace(deleted_count=0)


class TestWorkoutPlanDelete(unittest.TestCase):
    def setUp(self):
        self.user_a = {"_id": ObjectId(), "email": "delete_a@saman.test"}
        self.user_b = {"_id": ObjectId(), "email": "delete_b@saman.test"}
        self.active_user = self.user_a
        self.plan_id = ObjectId()
        self.plans = DeletableMemoryCollection()
        self.plans.insert_one({
            "_id": self.plan_id,
            "user_id": str(self.user_a["_id"]),
            "email": self.user_a["email"],
            "name": "Owner A plan",
            "exercises": [],
        })
        self.plans_before = copy.deepcopy(self.plans.documents)
        self.history_data = MemoryCollection()
        self.history_data.insert_one({
            "user_id": str(self.user_a["_id"]),
            "plan_id": str(self.plan_id),
            "plan_name": "Completed session must survive plan deletion",
        })
        self.history_before = copy.deepcopy(self.history_data.documents)
        self.history = Mock(wraps=self.history_data)
        self.enterContext(patch.object(workout_module, "custom_plans_collection", self.plans))
        self.enterContext(patch.object(workout_module, "workout_history_collection", self.history))
        self.enterContext(patch.object(workout_module.user_repo, "get_by_email", side_effect=lambda email: self.active_user))
        self.app = FastAPI()
        self.app.include_router(workout_module.router)
        self.app.dependency_overrides[workout_module.verify_token] = lambda: self.active_user["email"]
        self.client = TestClient(self.app)
        self.addCleanup(self.client.close)

    def tearDown(self):
        self.assertEqual(self.history.mock_calls, [], "Plan deletion must not access workout history")
        self.assertEqual(self.history_data.documents, self.history_before)
        self.app.dependency_overrides.clear()

    def test_owner_delete_preserves_success_contract_and_history(self):
        response = self.client.delete(f"/api/workouts/plans/{self.plan_id}")
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(set(body), {"id", "message", "deleted_at"})
        self.assertEqual(body["id"], str(self.plan_id))
        self.assertEqual(body["message"], "Workout plan deleted successfully")
        datetime.datetime.fromisoformat(body["deleted_at"])
        self.assertEqual(self.plans.documents, [])

    def test_missing_object_id_returns_404_without_mutation(self):
        response = self.client.delete(f"/api/workouts/plans/{ObjectId()}")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json(), {"detail": "Workout plan not found"})
        self.assertEqual(self.plans.documents, self.plans_before)

    def test_missing_legacy_id_returns_404_without_mutation(self):
        response = self.client.delete("/api/workouts/plans/missing-legacy-plan")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json(), {"detail": "Workout plan not found"})
        self.assertEqual(self.plans.documents, self.plans_before)

    def test_cross_account_returns_404_and_preserves_owner_plan(self):
        self.active_user = self.user_b
        response = self.client.delete(f"/api/workouts/plans/{self.plan_id}")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json(), {"detail": "Workout plan not found"})
        self.assertEqual(self.plans.documents, self.plans_before)

    def test_database_failure_preserves_500_contract_without_mutation(self):
        with patch.object(self.plans, "delete_one", side_effect=PyMongoError("Synthetic database failure")) as delete:
            response = self.client.delete(f"/api/workouts/plans/{self.plan_id}")
        self.assertEqual(response.status_code, 500)
        self.assertEqual(response.json(), {"detail": "Synthetic database failure"})
        delete.assert_called_once()
        self.assertEqual(self.plans.documents, self.plans_before)


if __name__ == "__main__":
    unittest.main()
