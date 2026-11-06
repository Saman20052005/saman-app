import ast
import asyncio
import copy
import unittest
from pathlib import Path


WORKOUT_SOURCE = Path(__file__).resolve().parents[1] / "routers" / "workout.py"


def _matches(document, query):
    for key, expected in query.items():
        if key == "$or":
            if not any(_matches(document, branch) for branch in expected):
                return False
        elif key == "$and":
            if not all(_matches(document, branch) for branch in expected):
                return False
        else:
            actual = document.get(key)
            if isinstance(actual, list) and not isinstance(expected, list):
                if expected not in actual:
                    return False
            elif actual != expected:
                return False
    return True


class MemoryPlanCollection:
    def __init__(self, documents):
        self.documents = copy.deepcopy(documents)
        self.queries = []

    def find(self, query):
        self.queries.append(copy.deepcopy(query))
        return [
            copy.deepcopy(document)
            for document in self.documents
            if _matches(document, query)
        ]


class FakeUserRepository:
    def __init__(self, users):
        self.users = users

    def get_by_email(self, email):
        return copy.deepcopy(self.users.get(email))


class IsolatedHTTPException(Exception):
    def __init__(self, status_code, detail):
        super().__init__(detail)
        self.status_code = status_code


def _load_current_handler():
    tree = ast.parse(WORKOUT_SOURCE.read_text(encoding="utf-8"))
    handler = next(
        node for node in tree.body
        if isinstance(node, ast.AsyncFunctionDef)
        and node.name == "get_workout_plans"
    )
    handler.decorator_list = []
    handler.returns = None
    for argument in handler.args.posonlyargs + handler.args.args:
        argument.annotation = None
    handler.args.defaults = []
    namespace = {
        "_safe_find": lambda collection, query: list(collection.find(query)),
        "_serialize_mongo": lambda value: value,
        "HTTPException": IsolatedHTTPException,
    }
    module = ast.fix_missing_locations(ast.Module(body=[handler], type_ignores=[]))
    exec(compile(module, str(WORKOUT_SOURCE), "exec"), namespace)
    return namespace


class PlanQueryOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.users = {
            "a@example.test": {"_id": "user-a-id", "email": "a@example.test"},
            "b@example.test": {"_id": "user-b-id", "email": "b@example.test"},
        }
        self.plans = [
            {
                "_id": "plan-a-chest",
                "email": "a@example.test",
                "user_id": "user-a-id",
                "target_muscles": ["Chest"],
                "difficulty": "beginner",
                "name": "A Chest Plan",
            },
            {
                "_id": "plan-a-legs",
                "email": "a@example.test",
                "user_id": "user-a-id",
                "target_muscles": ["Legs"],
                "difficulty": "beginner",
                "name": "A Leg Plan",
            },
            {
                "_id": "plan-b-chest",
                "email": "b@example.test",
                "user_id": "user-b-id",
                "target_muscles": ["Chest"],
                "difficulty": "beginner",
                "name": "B Chest Plan",
            },
        ]
        self.collection = MemoryPlanCollection(self.plans)
        self.namespace = _load_current_handler()
        self.namespace["user_repo"] = FakeUserRepository(self.users)
        self.namespace["custom_plans_collection"] = self.collection
        self.handler = self.namespace["get_workout_plans"]

    def _plans_for_authenticated_email(
        self,
        email,
        target_muscle=None,
        difficulty=None,
    ):
        return asyncio.run(
            self.handler(
                difficulty=difficulty,
                target_muscle=target_muscle,
                email=email,
            )
        )["plans"]

    def test_user_a_can_view_own_private_plan(self):
        plans = self._plans_for_authenticated_email("a@example.test")
        self.assertIn("plan-a-chest", {plan["_id"] for plan in plans})

    def test_user_a_cannot_view_user_b_private_plan_without_filter(self):
        plans = self._plans_for_authenticated_email("a@example.test")
        self.assertNotIn("plan-b-chest", {plan["_id"] for plan in plans})

    def test_user_a_muscle_filter_does_not_disclose_user_b_private_plan(self):
        plans = self._plans_for_authenticated_email(
            "a@example.test",
            target_muscle="Chest",
        )
        self.assertNotIn("plan-b-chest", {plan["_id"] for plan in plans})

    def test_muscle_filter_is_intersected_with_ownership(self):
        plans = self._plans_for_authenticated_email(
            "a@example.test",
            target_muscle="Chest",
        )
        self.assertEqual(
            {"plan-a-chest"},
            {plan["_id"] for plan in plans},
        )

    def test_owner_email_and_user_id_alternatives_remain_supported(self):
        self.collection.documents.extend([
            {
                "_id": "plan-a-email-only",
                "email": "a@example.test",
                "target_muscles": ["Back"],
            },
            {
                "_id": "plan-a-user-id-only",
                "user_id": "user-a-id",
                "target_muscles": ["Back"],
            },
        ])

        plans = self._plans_for_authenticated_email("a@example.test")

        self.assertIn(
            "plan-a-email-only",
            {plan["_id"] for plan in plans},
        )
        self.assertIn(
            "plan-a-user-id-only",
            {plan["_id"] for plan in plans},
        )

    def test_difficulty_filter_remains_intersected_with_owner_and_muscle(self):
        self.collection.documents.append({
            "_id": "plan-a-advanced-chest",
            "email": "a@example.test",
            "user_id": "user-a-id",
            "target_muscles": ["Chest"],
            "difficulty": "advanced",
        })

        plans = self._plans_for_authenticated_email(
            "a@example.test",
            target_muscle="Chest",
            difficulty="beginner",
        )

        self.assertEqual(
            {"plan-a-chest"},
            {plan["_id"] for plan in plans},
        )


if __name__ == "__main__":
    unittest.main()
