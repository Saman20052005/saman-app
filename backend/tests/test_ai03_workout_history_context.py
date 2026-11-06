import ast
import copy
import importlib.util
import math
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal, NamedTuple
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[2]
CHAT_SOURCE = ROOT / "backend" / "routers" / "chat.py"
RESOLVER_SOURCE = (
    ROOT / "backend" / "app" / "services" / "exercise_catalog_resolver.py"
)


def _load_resolver_class():
    spec = importlib.util.spec_from_file_location(
        "ai03_history_exercise_catalog_resolver", RESOLVER_SOURCE
    )
    if spec is None or spec.loader is None:
        raise AssertionError("Could not load the production resolver module.")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.ExerciseCatalogResolver


ExerciseCatalogResolver = _load_resolver_class()
EXERCISE_CATALOG_RESOLVER = ExerciseCatalogResolver()


def _load_chat_helpers():
    tree = ast.parse(CHAT_SOURCE.read_text(encoding="utf-8"))
    names = {
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
        "build_health_context",
    }
    functions = []
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name in names:
            node.decorator_list = []
            node.returns = None
            for argument in node.args.posonlyargs + node.args.args:
                argument.annotation = None
            functions.append(node)
        elif isinstance(node, ast.ClassDef) and node.name == "WorkoutHistoryContext":
            functions.append(node)
    expected_names = names | {"WorkoutHistoryContext"}
    if {node.name for node in functions} != expected_names:
        missing = expected_names - {node.name for node in functions}
        raise AssertionError(f"Workout context helpers are missing from chat.py: {missing}")

    namespace = {
        "datetime": datetime,
        "timezone": timezone,
        "math": math,
        "Literal": Literal,
        "NamedTuple": NamedTuple,
        "VN_TZ": ZoneInfo("Asia/Ho_Chi_Minh"),
        "logger": QuietLogger(),
        "users_col": None,
        "nutrition_col": None,
        "workout_history_col": None,
        "exercise_catalog_resolver": EXERCISE_CATALOG_RESOLVER,
        "water_col": None,
        "_build_user_profile_context": lambda user: "PROFILE",
        "_build_today_nutrition_context": lambda email, collection: "NUTRITION",
        "_build_today_water_context": lambda email, collection: "WATER",
        "_build_trends_context": lambda email, user_id, nutrition, workout: "",
        "_build_preferences_context": lambda user: "",
    }
    module = ast.fix_missing_locations(ast.Module(body=functions, type_ignores=[]))
    exec(compile(module, str(CHAT_SOURCE), "exec"), namespace)
    return namespace


class QuietLogger:
    def __init__(self):
        self.warnings = []

    def warning(self, message, value):
        self.warnings.append((message, value))


def _matches(document, query):
    for key, expected in query.items():
        if key == "$or":
            if not any(_matches(document, clause) for clause in expected):
                return False
        elif key == "$and":
            if not all(_matches(document, clause) for clause in expected):
                return False
        elif document.get(key) != expected:
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
            if _matches(document, query)
        ]


CHAT_HELPERS = _load_chat_helpers()
BUILD_CONTEXT = CHAT_HELPERS["_read_latest_workout_context"]


class WorkoutHistoryContextTests(unittest.TestCase):
    def test_existing_latest_context_helper_keeps_its_text_return_type(self):
        context = CHAT_HELPERS["_build_latest_workout_context"](
            "a@example.test",
            "user-a",
            MemoryHistoryCollection(
                [
                    {
                        "email": "a@example.test",
                        "start_time": "2026-11-02T10:00:00Z",
                        "completed_exercises": [{"name": "Legacy Row"}],
                    }
                ]
            ),
        )
        self.assertIsInstance(context, str)
        self.assertIn("Legacy Row", context)

    def test_canonical_sets_keep_units_completion_and_only_valid_volume(self):
        session = {
            "email": "a@example.test",
            "user_id": "user-a",
            "started_at": "2026-11-02T10:00:00Z",
            "finished_at": "2026-11-02T10:45:00Z",
            "total_duration_minutes": 45,
            "completed_exercises": [{"name": "Duplicate legacy representation"}],
            "exercise_logs": [
                {
                    "exercise_id": "db-bench-press",
                    "exercise_slug": "dumbbell-bench-press",
                    "name": "Recorded Bench Press",
                    "set_number": 1,
                    "reps_completed": 8,
                    "unit": "reps",
                    "weight_kg": 20,
                    "is_completed": True,
                },
                {
                    "exercise_id": "db-bench-press",
                    "exercise_slug": "dumbbell-bench-press",
                    "set_number": 2,
                    "reps_completed": 10,
                    "unit": "reps",
                    "weight_kg": 20,
                    "is_completed": False,
                },
                {
                    "exercise_id": "plank",
                    "exercise_slug": "plank",
                    "set_number": 1,
                    "reps_completed": 0,
                    "seconds_completed": 35,
                    "unit": "seconds",
                    "weight_kg": 0,
                    "is_completed": True,
                },
                {
                    "exercise_id": "plan_ex_0",
                    "exercise_slug": "plan_ex_0",
                    "set_number": 3,
                    "reps_completed": 5,
                    "unit": "reps",
                    "weight_kg": 10,
                },
            ],
        }

        result = BUILD_CONTEXT(
            "a@example.test", "user-a", MemoryHistoryCollection([session])
        )

        self.assertEqual(result.status, "available")
        self.assertIn("8 reps", result.context)
        self.assertIn("35 giây", result.context)
        self.assertIn("1 hoàn thành, 1 chưa hoàn thành, 0 trạng thái chưa rõ", result.context)
        self.assertIn("0 hoàn thành, 0 chưa hoàn thành, 1 trạng thái chưa rõ", result.context)
        self.assertIn("160 kg", result.context)
        self.assertNotIn("200 kg", result.context)
        self.assertNotIn("Duplicate legacy representation", result.context)
        self.assertIn("Bài tập đã xác minh: Dumbbell Bench Press", result.context)
        self.assertIn("canonical ID=db-bench-press", result.context)
        self.assertNotIn("catalog chưa xác định: ID/slug conflict", result.context)
        self.assertIn("catalog chưa xác định: synthetic plan ID", result.context)
        self.assertIn("Catalog tham chiếu (không phải số liệu đã log)", result.context)
        self.assertIn("nhóm cơ=Chest", result.context)

    def test_canonical_empty_or_malformed_never_falls_back_to_legacy(self):
        for canonical_logs in ([], None, {"invalid": "shape"}):
            with self.subTest(canonical_logs=canonical_logs):
                session = {
                    "email": "a@example.test",
                    "started_at": "2026-11-02T10:00:00Z",
                    "exercise_logs": canonical_logs,
                    "completed_exercises": [{"name": "Must not be used"}],
                }
                result = BUILD_CONTEXT(
                    "a@example.test", None, MemoryHistoryCollection([session])
                )
                self.assertEqual(result.status, "available")
                self.assertNotIn("Must not be used", result.context)
                if canonical_logs == []:
                    self.assertIn("canonical rỗng; không fallback", result.context)
                else:
                    self.assertIn("không thay bằng dữ liệu legacy", result.context)

    def test_legacy_only_names_remain_available_and_unresolved(self):
        session = {
            "user_id": "user-a",
            "start_time": "2026-11-02T10:00:00Z",
            "completed_exercises": [
                {"name": "Legacy Row", "sets": 3, "reps": 10, "weight": 25}
            ],
        }
        result = BUILD_CONTEXT(
            "a@example.test", "user-a", MemoryHistoryCollection([session])
        )
        self.assertEqual(result.status, "available")
        self.assertIn("Legacy Row", result.context)
        self.assertIn("catalog chưa xác định", result.context)
        self.assertIn("không suy ra thông tin hiệp", result.context)
        self.assertNotIn("3 hiệp", result.context)

    def test_empty_and_failed_reads_have_distinct_statuses(self):
        empty = BUILD_CONTEXT(
            "a@example.test", "user-a", MemoryHistoryCollection()
        )
        failed = BUILD_CONTEXT(
            "a@example.test", "user-a", MemoryHistoryCollection(fail=True)
        )
        unavailable_collection = BUILD_CONTEXT("a@example.test", "user-a", None)
        self.assertEqual(empty.status, "empty")
        self.assertEqual(failed.status, "unavailable")
        self.assertEqual(unavailable_collection.status, "unavailable")
        self.assertNotEqual(empty.context, failed.context)
        self.assertNotIn("synthetic read failure", failed.context)

    def test_explicit_workout_grounding_can_omit_the_general_latest_context(self):
        collection = MemoryHistoryCollection()
        build_health_context = CHAT_HELPERS["build_health_context"]
        user = {"email": "a@example.test", "_id": "user-a"}

        without_latest = build_health_context(
            user,
            workout_col_ref=collection,
            include_workout_context=False,
        )
        self.assertIn("NUTRITION", without_latest)
        self.assertIn("WATER", without_latest)
        self.assertNotIn("TẬP LUYỆN GẦN NHẤT", without_latest)
        self.assertEqual(collection.queries, [])

        with_latest = build_health_context(
            user,
            workout_col_ref=collection,
            include_workout_context=True,
        )
        self.assertIn("TẬP LUYỆN GẦN NHẤT", with_latest)
        self.assertEqual(len(collection.queries), 1)

    def test_authenticated_owner_query_excludes_other_user_records(self):
        collection = MemoryHistoryCollection(
            [
                {
                    "user_id": "user-a",
                    "email": "a@example.test",
                    "started_at": "2026-11-02T10:00:00Z",
                    "name": "A session",
                },
                {
                    "user_id": "user-b",
                    "email": "b@example.test",
                    "started_at": "2026-11-02T11:00:00Z",
                    "name": "B private session",
                },
            ]
        )
        result = BUILD_CONTEXT("a@example.test", "user-a", collection)
        self.assertIn("A session", result.context)
        self.assertNotIn("B private session", result.context)
        self.assertEqual(len(collection.queries), 1)
        self.assertEqual(
            collection.queries[0],
            {
                "$or": [
                    {"email": "a@example.test"},
                    {"user_email": "a@example.test"},
                    {"user_id": "user-a"},
                ]
            },
        )

    def test_latest_valid_timestamp_is_selected_and_malformed_rows_block_fallback(self):
        collection = MemoryHistoryCollection(
            [
                {
                    "email": "a@example.test",
                    "started_at": "2026-11-01T10:00:00Z",
                    "plan_name": "Older session",
                },
                {
                    "email": "a@example.test",
                    "started_at": "2026-11-02T10:00:00Z",
                    "plan_name": "Latest session",
                },
            ]
        )
        result = BUILD_CONTEXT("a@example.test", None, collection)
        self.assertIn("Latest session", result.context)
        self.assertNotIn("Older session", result.context)
        self.assertEqual(result.record_count, 2)
        self.assertIn("không có limit/phân trang", result.context)

        malformed = MemoryHistoryCollection(
            [
                {
                    "email": "a@example.test",
                    "started_at": "2026-11-01T10:00:00Z",
                    "plan_name": "Older session",
                },
                {
                    "email": "a@example.test",
                    "started_at": "not-a-time",
                    "plan_name": "Malformed session",
                },
            ]
        )
        uncertain = BUILD_CONTEXT("a@example.test", None, malformed)
        self.assertTrue(uncertain.latest_uncertain)
        self.assertNotIn("Older session", uncertain.context)
        self.assertIn("không thay bằng một bản ghi cũ hơn", uncertain.context)

    def test_malformed_partial_sets_are_safe_and_do_not_invent_values(self):
        normalized = CHAT_HELPERS["normalize_exercise_logs"](
            {
                "exercise_logs": [
                    None,
                    {
                        "exercise_id": "removed-exercise",
                        "exercise_slug": "nearby-name",
                        "set_number": "first",
                        "reps_completed": "12",
                        "unit": "reps",
                        "weight_kg": -3,
                        "is_completed": True,
                    },
                    {
                        "exercise_id": "partial",
                        "unit": "seconds",
                        "seconds_completed": "30",
                        "is_completed": "true",
                    },
                ]
            }
        )
        self.assertEqual(normalized["source"], "canonical")
        self.assertEqual(normalized["malformed_records"], 1)
        self.assertEqual(len(normalized["exercises"]), 2)
        self.assertEqual(normalized["exercises"][0]["identity_status"], "unresolved")
        self.assertIsNone(normalized["exercises"][0]["volume_kg"])
        self.assertIsNone(normalized["exercises"][1]["sets"][0]["seconds_completed"])
        self.assertEqual(
            normalized["exercises"][1]["sets"][0]["completion"], "unknown"
        )

    def test_synthetic_history_id_resolves_only_by_exact_slug_and_preserves_metrics(self):
        source = {
            "exercise_logs": [
                {
                    "exercise_id": "plan_ex_12",
                    "exercise_slug": "lat-pulldown",
                    "name": "Saved Lat Pulldown",
                    "set_number": 2,
                    "reps_completed": 7,
                    "unit": "reps",
                    "weight_kg": 32.5,
                    "is_completed": True,
                }
            ]
        }
        original = copy.deepcopy(source)

        normalized = CHAT_HELPERS["normalize_exercise_logs"](source)
        exercise = normalized["exercises"][0]

        self.assertEqual(source, original)
        self.assertEqual(exercise["exercise_id"], "plan_ex_12")
        self.assertEqual(exercise["canonical_exercise_id"], "lat-pulldown")
        self.assertEqual(exercise["identity_status"], "resolved")
        self.assertEqual(
            exercise["identity_provenance"]["kind"],
            "synthetic_id+exact_slug",
        )
        self.assertEqual(exercise["history_source"], "exercise_logs")
        self.assertEqual(exercise["sets"][0]["reps_completed"], 7)
        self.assertEqual(exercise["sets"][0]["weight_kg"], 32.5)

    def test_unknown_and_conflicting_history_identities_stay_unresolved(self):
        normalized = CHAT_HELPERS["normalize_exercise_logs"](
            {
                "exercise_logs": [
                    {
                        "exercise_id": "removed-exercise-99",
                        "exercise_slug": "dumbbell-bench-press",
                        "reps_completed": 8,
                        "unit": "reps",
                        "weight_kg": 20,
                        "is_completed": True,
                    },
                    {
                        "exercise_id": "db-bench-press",
                        "exercise_slug": "lat-pulldown",
                        "reps_completed": 5,
                        "unit": "reps",
                        "weight_kg": 12,
                        "is_completed": True,
                    },
                ]
            }
        )

        self.assertEqual(
            [exercise["identity_status"] for exercise in normalized["exercises"]],
            ["unresolved", "conflict"],
        )
        for exercise in normalized["exercises"]:
            self.assertIsNone(exercise["catalog_metadata"])
            self.assertNotIn("canonical_exercise_id", exercise)
        self.assertEqual(normalized["exercises"][0]["sets"][0]["reps_completed"], 8)
        self.assertEqual(normalized["exercises"][1]["sets"][0]["weight_kg"], 12)

    def test_catalog_unavailable_does_not_turn_history_into_empty(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            unavailable_resolver = ExerciseCatalogResolver(
                Path(temporary_directory) / "missing.json"
            )
            result = BUILD_CONTEXT(
                "a@example.test",
                "user-a",
                MemoryHistoryCollection(
                    [
                        {
                            "email": "a@example.test",
                            "started_at": "2026-11-02T10:00:00Z",
                            "exercise_logs": [
                                {
                                    "exercise_id": "db-bench-press",
                                    "exercise_slug": "dumbbell-bench-press",
                                    "reps_completed": 8,
                                    "unit": "reps",
                                    "weight_kg": 20,
                                    "is_completed": True,
                                }
                            ],
                        }
                    ]
                ),
                unavailable_resolver,
            )
            empty_history = BUILD_CONTEXT(
                "a@example.test",
                "user-a",
                MemoryHistoryCollection(),
                unavailable_resolver,
            )

        self.assertEqual(result.status, "available")
        self.assertIn("Catalog không khả dụng", result.context)
        self.assertIn("8 reps", result.context)
        self.assertEqual(empty_history.status, "empty")
        self.assertNotIn("Catalog không khả dụng", empty_history.context)

    def test_partial_volume_excludes_completed_rep_sets_missing_weight(self):
        normalized = CHAT_HELPERS["normalize_exercise_logs"](
            {
                "exercise_logs": [
                    {
                        "exercise_id": "row",
                        "exercise_slug": "row",
                        "set_number": 1,
                        "reps_completed": 5,
                        "unit": "reps",
                        "weight_kg": 2,
                        "is_completed": True,
                    },
                    {
                        "exercise_id": "row",
                        "exercise_slug": "row",
                        "set_number": 2,
                        "reps_completed": 3,
                        "unit": "reps",
                        "is_completed": True,
                    },
                ]
            }
        )
        exercise = normalized["exercises"][0]
        self.assertEqual(exercise["volume_status"], "partial")
        self.assertEqual(exercise["volume_kg"], 10)

    def test_workout_status_and_skipped_exercises_labels(self):
        # 1. Active session (finished_at is None) with skipped exercise
        active_session = {
            "email": "a@example.test",
            "started_at": "2026-11-04T10:00:00Z",
            "finished_at": None,
            "exercise_logs": [
                {
                    "exercise_id": "db-bench-press",
                    "exercise_slug": "dumbbell-bench-press",
                    "set_number": 1,
                    "reps_completed": 8,
                    "unit": "reps",
                    "weight_kg": 20,
                    "is_completed": True,
                },
                {
                    "exercise_id": "push-up",
                    "exercise_slug": "push-up",
                    "set_number": 1,
                    "reps_completed": 0,
                    "unit": "reps",
                    "weight_kg": 0,
                    "is_completed": False,
                },
            ],
        }
        res_active = BUILD_CONTEXT(
            "a@example.test", None, MemoryHistoryCollection([active_session])
        )
        self.assertIn("[Trạng thái: Đang tập (Active)]", res_active.context)
        self.assertIn("Các bài tập đã bỏ qua: Push-Up", res_active.context)

        # 2. Completed session (finished_at is present)
        completed_session = {
            "email": "a@example.test",
            "started_at": "2026-11-04T10:00:00Z",
            "finished_at": "2026-11-04T10:45:00Z",
            "exercise_logs": [
                {
                    "exercise_id": "db-bench-press",
                    "exercise_slug": "dumbbell-bench-press",
                    "set_number": 1,
                    "reps_completed": 8,
                    "unit": "reps",
                    "weight_kg": 20,
                    "is_completed": True,
                },
            ],
        }
        res_completed = BUILD_CONTEXT(
            "a@example.test", None, MemoryHistoryCollection([completed_session])
        )
        self.assertIn("[Trạng thái: Đã hoàn thành (Completed)]", res_completed.context)
        self.assertNotIn("Các bài tập đã bỏ qua:", res_completed.context)


if __name__ == "__main__":
    unittest.main()
