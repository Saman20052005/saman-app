import asyncio
import unittest

from backend.tests.test_ai01_plan_query_ownership import (
    FakeUserRepository,
    MemoryPlanCollection,
    _load_current_handler,
)


class PlanOwnershipRouteFunctionTests(unittest.TestCase):
    def setUp(self):
        self.collection = MemoryPlanCollection([
            {
                "_id": "plan-a-target-muscles",
                "user_id": "user-a-id",
                "target_muscles": ["Chest", "Triceps"],
                "difficulty": "beginner",
            },
            {
                "_id": "plan-a-legacy-muscle-groups",
                "email": "a@example.test",
                "muscle_groups": ["Chest"],
                "difficulty": "intermediate",
            },
            {
                "_id": "plan-b-target-muscles",
                "user_id": "user-b-id",
                "target_muscles": ["Chest"],
                "difficulty": "beginner",
            },
        ])
        self.namespace = _load_current_handler()
        self.namespace["user_repo"] = FakeUserRepository({
            "a@example.test": {"_id": "user-a-id", "email": "a@example.test"},
            "b@example.test": {"_id": "user-b-id", "email": "b@example.test"},
        })
        self.namespace["custom_plans_collection"] = self.collection
        self.handler = self.namespace["get_workout_plans"]

    def _get_plans(self, *, email, target_muscle=None, difficulty=None):
        return asyncio.run(self.handler(
            difficulty=difficulty,
            target_muscle=target_muscle,
            email=email,
        ))

    def test_muscle_filter_keeps_array_membership_and_both_supported_fields(self):
        response = self._get_plans(
            email="a@example.test",
            target_muscle="Chest",
        )

        self.assertEqual(
            {"plan-a-target-muscles", "plan-a-legacy-muscle-groups"},
            {plan["_id"] for plan in response["plans"]},
        )
        self.assertEqual(2, response["total_count"])
        self.assertEqual(
            {
                "difficulty": None,
                "target_muscle": "Chest",
            },
            response["filters_applied"],
        )

    def test_difficulty_and_muscle_filters_do_not_expand_owner_visibility(self):
        response = self._get_plans(
            email="a@example.test",
            target_muscle="Chest",
            difficulty="beginner",
        )

        self.assertEqual(
            {"plan-a-target-muscles"},
            {plan["_id"] for plan in response["plans"]},
        )


if __name__ == "__main__":
    unittest.main()
