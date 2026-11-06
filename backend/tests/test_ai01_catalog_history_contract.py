import ast
import copy
import importlib.util
import json
import math
import unittest
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal, NamedTuple
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[2]
CHAT_SOURCE = ROOT / "backend" / "routers" / "chat.py"
BACK_CATALOG_SOURCE = (
    ROOT / "backend" / "app" / "data" / "exercises" / "back.py"
)
GENERATED_CATALOG = (
    ROOT
    / "backend"
    / "app"
    / "data"
    / "ai_exercise_catalog.generated.json"
)
RESOLVER_SOURCE = (
    ROOT / "backend" / "app" / "services" / "exercise_catalog_resolver.py"
)


def _load_resolver_class():
    spec = importlib.util.spec_from_file_location(
        "ai01_history_exercise_catalog_resolver", RESOLVER_SOURCE
    )
    if spec is None or spec.loader is None:
        raise AssertionError("Could not load the production resolver module.")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.ExerciseCatalogResolver


ExerciseCatalogResolver = _load_resolver_class()
EXERCISE_CATALOG_RESOLVER = ExerciseCatalogResolver()


def _load_backend_catalog():
    tree = ast.parse(BACK_CATALOG_SOURCE.read_text(encoding="utf-8"))
    assignment = next(
        node for node in tree.body
        if isinstance(node, ast.Assign)
        and any(
            isinstance(target, ast.Name) and target.id == "BACK_EXERCISES"
            for target in node.targets
        )
    )
    return ast.literal_eval(assignment.value)


def _load_functions(source_path, names, namespace):
    tree = ast.parse(source_path.read_text(encoding="utf-8"))
    functions = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name in names:
            node.decorator_list = []
            node.returns = None
            for argument in node.args.posonlyargs + node.args.args:
                argument.annotation = None
            functions.append(node)
        elif isinstance(node, ast.ClassDef) and node.name == "WorkoutHistoryContext":
            functions.append(node)
    loaded = {node.name for node in functions}
    expected_names = set(names) | {"WorkoutHistoryContext"}
    if loaded != expected_names:
        raise AssertionError(f"Missing source helpers: {expected_names - loaded}")
    module = ast.fix_missing_locations(ast.Module(body=functions, type_ignores=[]))
    exec(compile(module, str(source_path), "exec"), namespace)
    return namespace


def _catalog_matches(document, query):
    for key, expected in query.items():
        if key == "$or":
            if not any(_catalog_matches(document, branch) for branch in expected):
                return False
        elif key == "$and":
            if not all(_catalog_matches(document, branch) for branch in expected):
                return False
        else:
            actual = document.get(key)
            if isinstance(actual, list) and not isinstance(expected, list):
                if expected not in actual:
                    return False
            elif actual != expected:
                return False
    return True


class MemoryHistoryCollection:
    def __init__(self, documents=(), fail=False):
        self.documents = copy.deepcopy(list(documents))
        self.fail = fail
        self.queries = []

    def find(self, query):
        self.queries.append(copy.deepcopy(query))
        if self.fail:
            raise RuntimeError("synthetic read failure")
        return [
            copy.deepcopy(document)
            for document in self.documents
            if _catalog_matches(document, query)
        ]


class QuietLogger:
    def warning(self, *args):
        return None


BACK_EXERCISES = _load_backend_catalog()
CHAT_HELPERS = _load_functions(
    CHAT_SOURCE,
    {
        "_parse_valid_datetime",
        "_normalize_to_vn_datetime",
        "_text_value",
        "_integer_value",
        "_number_value",
        "_first_value",
        "_normalize_canonical_logs",
        "_resolve_history_exercises",
        "normalize_exercise_logs",
        "_read_latest_workout_context",
        "_build_latest_workout_context",
        "is_session_completed",
        "resolve_exercise_name",
        "fetch_user_workout_sessions",
    },
    {
        "datetime": datetime,
        "timezone": timezone,
        "math": math,
        "Literal": Literal,
        "NamedTuple": NamedTuple,
        "ZoneInfo": ZoneInfo,
        "VN_TZ": ZoneInfo("Asia/Ho_Chi_Minh"),
        "ICT_ZONE": ZoneInfo("Asia/Ho_Chi_Minh"),
        "REPO_EXERCISES_MAP": {
            exercise["slug"]: exercise for exercise in BACK_EXERCISES
        },
        "exercise_catalog_resolver": EXERCISE_CATALOG_RESOLVER,
        "exercises_collection": None,
        "exercises_col": None,
        "workout_history_collection": None,
        "workout_history_col": None,
        "logger": QuietLogger(),
    },
)


class CatalogHistoryCurrentContractTests(unittest.TestCase):
    def test_generated_library_ids_and_slugs_are_nonempty_and_unique(self):
        artifact = json.loads(GENERATED_CATALOG.read_text(encoding="utf-8"))
        entries = artifact["exercises"]
        ids = [record["id"] for record in entries]
        slugs = [record["slug"] for record in entries]
        self.assertTrue(all(ids))
        self.assertTrue(all(slugs))
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len(slugs), len(set(slugs)))
        self.assertEqual(artifact["schema_version"], 1)

    def test_ui_catalog_record_fixture_resolves_from_generated_catalog(self):
        display, source = CHAT_HELPERS["resolve_exercise_name"](
            "db-bench-press",
            "dumbbell-bench-press",
        )
        self.assertIn("Đẩy ngực với tạ đơn", display)
        self.assertIn("Dumbbell Bench Press", display)
        self.assertIn("generated catalog (canonical_id+exact_slug)", source)

    def test_plan_generated_and_removed_ids_remain_unresolved(self):
        resolve = CHAT_HELPERS["resolve_exercise_name"]
        for exercise_id in ("plan_ex_0", "removed-exercise-99"):
            with self.subTest(exercise_id=exercise_id):
                display, source = resolve(exercise_id, exercise_id)
                self.assertIn(exercise_id, display)
                self.assertIn("chưa xác định", source)

    def test_latest_helper_reads_and_resolves_canonical_history(self):
        canonical_session = {
            "user_id": "user-a",
            "email": "a@example.test",
            "started_at": "2026-11-02T10:00:00Z",
            "finished_at": "2026-11-02T10:45:00Z",
            "exercise_logs": [
                {
                    "exercise_id": "db-bench-press",
                    "exercise_slug": "dumbbell-bench-press",
                    "set_number": 1,
                    "reps_completed": 8,
                    "unit": "reps",
                    "weight_kg": 20,
                    "is_completed": True,
                }
            ],
        }
        self.assertTrue(CHAT_HELPERS["is_session_completed"](canonical_session))
        context = CHAT_HELPERS["_build_latest_workout_context"](
            "a@example.test",
            "user-a",
            MemoryHistoryCollection([canonical_session]),
        )
        self.assertIn("db-bench-press", context)
        self.assertIn("8 reps", context)
        self.assertIn("Bài tập đã xác minh: Dumbbell Bench Press", context)
        self.assertIn("identity resolution=canonical_id+exact_slug", context)
        self.assertNotIn("catalog chưa xác định", context)

    def test_legacy_record_fixture_supplies_name_to_latest_helper(self):
        legacy_session = {
            "user_id": "user-a",
            "email": "a@example.test",
            "start_time": "2026-11-02T10:00:00Z",
            "completed_exercises": [
                {"name": "Legacy Row", "sets": 3, "reps": 10, "weight": 25}
            ],
        }
        context = CHAT_HELPERS["_build_latest_workout_context"](
            "a@example.test",
            "user-a",
            MemoryHistoryCollection([legacy_session]),
        )
        self.assertIn("Legacy Row", context)

    def test_latest_helper_distinguishes_empty_from_failed_reads(self):
        build_context = CHAT_HELPERS["_read_latest_workout_context"]
        no_rows = build_context(
            "a@example.test", "user-a", MemoryHistoryCollection()
        )
        read_error = build_context(
            "a@example.test", "user-a", MemoryHistoryCollection(fail=True)
        )
        self.assertEqual(no_rows.status, "empty")
        self.assertEqual(read_error.status, "unavailable")
        self.assertNotEqual(no_rows.context, read_error.context)

    def test_user_b_history_is_not_returned_for_user_a(self):
        sessions = [
            {"user_id": "user-a", "id": "session-a"},
            {"user_id": "user-b", "id": "session-b"},
        ]
        collection = MemoryHistoryCollection(sessions)
        CHAT_HELPERS["workout_history_collection"] = collection
        try:
            result = CHAT_HELPERS["fetch_user_workout_sessions"]("user-a")
        finally:
            CHAT_HELPERS["workout_history_collection"] = None
        self.assertEqual(["session-a"], [session["id"] for session in result])
        self.assertEqual([{"user_id": "user-a"}], collection.queries)


if __name__ == "__main__":
    unittest.main()
