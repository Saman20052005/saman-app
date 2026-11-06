import copy
import importlib.util
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RESOLVER_SOURCE = (
    ROOT / "backend" / "app" / "services" / "exercise_catalog_resolver.py"
)
RECOMMENDATION_SOURCE = (
    ROOT / "backend" / "app" / "services" / "workout_recommendation.py"
)
HISTORY_TEST_SOURCE = (
    ROOT / "backend" / "tests" / "test_ai03_workout_history_context.py"
)


def _load_module(name, source):
    spec = importlib.util.spec_from_file_location(name, source)
    if spec is None or spec.loader is None:
        raise AssertionError("Could not load production module: " + str(source))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


resolver_module = _load_module("ai05_exercise_catalog_resolver", RESOLVER_SOURCE)
recommendation_module = _load_module(
    "ai05_workout_recommendation", RECOMMENDATION_SOURCE
)
history_test_module = _load_module("ai05_ai03_history_test_helpers", HISTORY_TEST_SOURCE)
ExerciseCatalogResolver = resolver_module.ExerciseCatalogResolver
HISTORY_NORMALIZER = history_test_module.CHAT_HELPERS["normalize_exercise_logs"]
HISTORY_TIMESTAMP_PARSER = history_test_module.CHAT_HELPERS[
    "_normalize_to_vn_datetime"
]
_UNSET = object()
load_context = recommendation_module.load_workout_recommendation_context
recommend_workouts = recommendation_module.recommend_workouts


class StubCatalogResolver:
    def __init__(self, records, available=True, resolution_resolver=None):
        self.records = copy.deepcopy(list(records))
        self.available = available
        self.resolution_resolver = resolution_resolver

    def list_exercises(self):
        return copy.deepcopy(self.records)

    def resolve(self, exercise_id=None, exercise_slug=None):
        if self.resolution_resolver is not None:
            return self.resolution_resolver.resolve(exercise_id, exercise_slug)
        for record in self.records:
            if exercise_id is not None and record.get("id") != exercise_id:
                continue
            if exercise_slug is not None and (
                record.get("slug", "").strip().lower()
                != exercise_slug.strip().lower()
            ):
                continue
            return {
                "status": "resolved",
                "reason": None,
                "exercise": copy.deepcopy(record),
                "provenance": {"kind": "test_catalog"},
            }
        return {
            "status": "unresolved",
            "reason": "unknown canonical ID",
            "exercise": None,
            "provenance": {},
        }


class WorkoutRecommendationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.resolver = ExerciseCatalogResolver()
        if not cls.resolver.available:
            raise AssertionError("The generated catalog must be available.")
        cls.records = cls.resolver.list_exercises()

    def setUp(self):
        self.now = datetime(2026, 11, 3, 4, 0, tzinfo=timezone.utc)
        self.principal_a = {"_id": "user-a", "email": "a@example.test"}
        self.profile_a = {
            "_id": "user-a",
            "email": "a@example.test",
            "profile": {
                "activity_level": "moderate",
                "goal": "gain_muscle",
            },
        }

    def _session(self, owner_id, exercise_id, exercise_slug, when=None):
        return {
            "user_id": owner_id,
            "started_at": (when or self.now).isoformat(),
            "exercise_logs": [
                {
                    "exercise_id": exercise_id,
                    "exercise_slug": exercise_slug,
                    "set_number": 1,
                    "reps_completed": 8,
                    "unit": "reps",
                    "weight_kg": 20,
                    "is_completed": True,
                }
            ],
        }

    def _context(
        self,
        history=(),
        profile=_UNSET,
        profile_reader=None,
        history_reader=None,
        principal=None,
    ):
        profile_reads = []
        history_reads = []
        profile_record = self.profile_a if profile is _UNSET else profile

        def read_profile(email):
            profile_reads.append(email)
            if profile_reader is not None:
                return profile_reader(email)
            return copy.deepcopy(profile_record)

        def read_history(owner_id):
            history_reads.append(owner_id)
            if history_reader is not None:
                return history_reader(owner_id)
            return copy.deepcopy(list(history))

        result = load_context(
            principal or self.principal_a,
            read_profile,
            read_history,
            HISTORY_NORMALIZER,
            HISTORY_TIMESTAMP_PARSER,
            self.resolver,
            now=self.now,
        )
        return result, profile_reads, history_reads

    def test_owner_scoped_profile_and_history_reads_exclude_user_b(self):
        exercise_a, exercise_b = self.records[:2]
        history = [
            self._session("user-a", exercise_a["id"], exercise_a["slug"]),
            self._session("user-b", exercise_b["id"], exercise_b["slug"]),
        ]
        profiles = {
            "a@example.test": self.profile_a,
            "b@example.test": {
                "_id": "user-b",
                "email": "b@example.test",
                "profile": {
                    "activity_level": "very_active",
                    "goal": "lose_weight",
                },
            },
        }
        returned_history = []

        def read_profile(email):
            return copy.deepcopy(profiles.get(email))

        def read_history(owner_id):
            returned_history.append(owner_id)
            return copy.deepcopy(history)

        context, profile_reads, history_reads = self._context(
            profile_reader=read_profile,
            history_reader=read_history,
        )

        self.assertEqual(profile_reads, ["a@example.test"])
        self.assertEqual(history_reads, ["user-a"])
        self.assertEqual(returned_history, ["user-a"])
        self.assertEqual(context["profile_fields"]["activity_level"]["value"], "moderate")
        self.assertEqual(
            context["recent_exercise_session_counts"], {exercise_a["id"]: 1}
        )
        self.assertNotIn(exercise_b["id"], context["recent_exercise_session_counts"])

        b_only, _, _ = self._context(
            history=[self._session("user-b", exercise_b["id"], exercise_b["slug"])]
        )
        self.assertEqual(b_only["history_status"], "empty")

    def test_profile_owner_mismatch_is_unavailable_not_borrowed(self):
        wrong_profile = {
            "_id": "user-b",
            "email": "b@example.test",
            "profile": {"activity_level": "very_active", "goal": "lose_weight"},
        }
        context, profile_reads, _ = self._context(profile=wrong_profile)

        self.assertEqual(profile_reads, ["a@example.test"])
        self.assertEqual(context["profile_status"], "unavailable")
        self.assertEqual(context["profile_reason"], "profile_owner_mismatch")
        self.assertIsNone(context["profile_fields"]["activity_level"]["value"])

    def test_missing_and_failed_profile_reads_remain_distinct(self):
        missing, _, _ = self._context(profile=None)
        failed, _, _ = self._context(
            profile_reader=lambda email: (_ for _ in ()).throw(
                RuntimeError("synthetic profile failure")
            )
        )

        self.assertEqual(missing["profile_status"], "missing")
        self.assertIsNone(missing["profile_reason"])
        self.assertEqual(failed["profile_status"], "unavailable")
        self.assertEqual(
            failed["profile_reason"], "profile_read_error:RuntimeError"
        )

    def test_cold_history_and_read_failure_have_distinct_statuses(self):
        cold, _, _ = self._context(history=[])
        failed, _, _ = self._context(
            history_reader=lambda owner_id: (_ for _ in ()).throw(
                RuntimeError("synthetic read failure")
            )
        )

        self.assertEqual(cold["history_status"], "empty")
        self.assertEqual(cold["history_reason"], None)
        self.assertEqual(failed["history_status"], "unavailable")
        self.assertEqual(
            failed["history_reason"], "history_read_error:RuntimeError"
        )

    def test_root_profile_mirror_is_preserved_and_experience_stays_unknown(self):
        profile = {
            "_id": "user-a",
            "email": "a@example.test",
            "activity_level": "active",
            "goal": "maintain_weight",
        }
        context, _, _ = self._context(profile=profile)

        self.assertEqual(context["profile_fields"]["activity_level"]["value"], "active")
        self.assertEqual(
            context["profile_fields"]["activity_level"]["source"],
            "activity_level",
        )
        self.assertEqual(
            context["unknown_profile_fields"]["training_experience"],
            "not_persisted",
        )
        self.assertEqual(context["profile_fields_used"], [])

    def test_only_resolved_canonical_history_ids_are_used(self):
        by_id = {record["id"]: record for record in self.records}
        by_slug = {record["slug"]: record for record in self.records}
        canonical = by_id["db-bench-press"]
        synthetic = by_slug["lat-pulldown"]
        sessions = [
            self._session("user-a", canonical["id"], canonical["slug"]),
            self._session("user-a", "plan_ex_12", synthetic["slug"]),
            self._session("user-a", "removed-exercise", "dumbbell-bench-press"),
            self._session("user-a", "db-bench-press", "lat-pulldown"),
        ]
        context, _, _ = self._context(history=sessions)

        self.assertEqual(
            context["recent_exercise_session_counts"],
            {canonical["id"]: 1, synthetic["id"]: 1},
        )
        self.assertEqual(context["unresolved_history_exercises"], 2)
        self.assertIn(
            "synthetic_id+exact_slug",
            context["recent_exercise_provenance"][synthetic["id"]],
        )

    def test_history_window_excludes_old_sessions(self):
        exercise = self.records[0]
        old = self.now - recommendation_module.timedelta(days=91)
        context, _, _ = self._context(
            history=[self._session("user-a", exercise["id"], exercise["slug"], old)]
        )

        self.assertEqual(context["history_status"], "available")
        self.assertEqual(context["history_sessions_in_window"], 0)
        self.assertEqual(context["recent_exercise_session_counts"], {})

    def test_muscle_and_equipment_filters_require_verified_metadata(self):
        candidate = next(record for record in self.records if record["equipment"])
        requested_muscle = candidate["muscleGroup"]
        allowed_equipment = candidate["equipment"]
        context, _, _ = self._context()

        result = recommend_workouts(
            context,
            self.resolver,
            requested_muscle_groups=[requested_muscle],
            available_equipment=allowed_equipment,
        )

        self.assertEqual(result["status"], "ok")
        self.assertTrue(result["recommendations"])
        for item in result["recommendations"]:
            exercise = item["exercise"]
            self.assertIn("available_equipment_filter", item["reason_codes"])
            values = {
                exercise["muscleGroup"].casefold(),
                *(value.casefold() for value in exercise["targetMuscles"]),
                *(value.casefold() for value in exercise["secondaryMuscles"]),
            }
            self.assertIn(requested_muscle.casefold(), values)
            self.assertTrue(
                {value.casefold() for value in exercise["equipment"]}.issubset(
                    {value.casefold() for value in allowed_equipment}
                )
            )

    def test_filter_rejects_candidate_missing_required_equipment_metadata(self):
        record = copy.deepcopy(self.records[0])
        del record["equipment"]
        catalog = StubCatalogResolver([record])
        context, _, _ = self._context()

        result = recommend_workouts(
            context,
            catalog,
            available_equipment=["Dumbbells", "Bodyweight"],
        )

        self.assertEqual(result["status"], "no_candidates")
        self.assertEqual(result["recommendations"], [])

        record = copy.deepcopy(self.records[0])
        del record["muscleGroup"]
        catalog = StubCatalogResolver([record])
        muscle_result = recommend_workouts(
            context,
            catalog,
            requested_muscle_groups=["Chest"],
        )
        self.assertEqual(muscle_result["status"], "no_candidates")
        self.assertEqual(muscle_result["recommendations"], [])

    def test_no_matching_filter_returns_an_empty_explanation(self):
        context, _, _ = self._context()
        result = recommend_workouts(
            context,
            self.resolver,
            requested_muscle_groups=["synthetic-muscle-group"],
        )

        self.assertEqual(result["status"], "no_candidates")
        self.assertEqual(
            result["reason"], "no_candidates_match_explicit_filters"
        )
        self.assertEqual(result["recommendations"], [])

    def test_unknown_equipment_is_exposed_as_limited_context(self):
        context, _, _ = self._context()
        result = recommend_workouts(context, self.resolver)

        self.assertEqual(result["status"], "limited_context")
        self.assertEqual(result["reason"], "available_equipment_unknown")
        self.assertTrue(result["clarification_required"])
        self.assertEqual(result["clarification_fields"], ["available_equipment"])
        self.assertLessEqual(len(result["recommendations"]), 5)

    def test_catalog_unavailable_and_empty_are_distinct_fail_closed_states(self):
        context, _, _ = self._context()
        with tempfile.TemporaryDirectory() as temp_dir:
            unavailable = ExerciseCatalogResolver(Path(temp_dir) / "missing.json")
            unavailable_result = recommend_workouts(context, unavailable)
        empty_result = recommend_workouts(context, StubCatalogResolver([]))

        self.assertEqual(unavailable_result["status"], "catalog_unavailable")
        self.assertEqual(unavailable_result["recommendations"], [])
        self.assertEqual(empty_result["status"], "no_candidates")
        self.assertEqual(empty_result["reason"], "catalog_empty")
        self.assertEqual(empty_result["recommendations"], [])

    def test_candidate_count_is_bounded_and_every_id_resolves_in_artifact(self):
        context, _, _ = self._context()
        full = recommend_workouts(context, self.resolver)
        limited_catalog = StubCatalogResolver(self.records[:2])
        fewer = recommend_workouts(context, limited_catalog)

        self.assertEqual(len(full["recommendations"]), 5)
        self.assertEqual(len(fewer["recommendations"]), 2)
        ids = [item["canonical_id"] for item in full["recommendations"]]
        self.assertEqual(len(ids), len(set(ids)))
        for item in full["recommendations"]:
            resolution = self.resolver.resolve(item["canonical_id"])
            self.assertEqual(resolution["status"], "resolved")
            self.assertEqual(item["exercise"], resolution["exercise"])

    def test_tied_scores_are_stable_and_tie_broken_by_canonical_id(self):
        context, _, _ = self._context()
        first = recommend_workouts(context, self.resolver)
        second = recommend_workouts(context, self.resolver)
        expected = sorted(record["id"] for record in self.records)[:5]

        self.assertEqual(
            [item["canonical_id"] for item in first["recommendations"]],
            expected,
        )
        self.assertEqual(first["recommendations"], second["recommendations"])
        for item in first["recommendations"]:
            self.assertIn("canonical_id_tiebreak", item["reason_codes"])

    def test_reason_codes_and_score_components_match_real_signals(self):
        candidate = next(
            record
            for record in self.records
            if record["muscleGroup"] and record["equipment"]
        )
        history = [
            self._session("user-a", candidate["id"], candidate["slug"])
        ]
        context, _, _ = self._context(history=history)

        result = recommend_workouts(
            context,
            self.resolver,
            requested_muscle_groups=[candidate["muscleGroup"]],
            available_equipment=candidate["equipment"],
        )
        selected = next(
            item
            for item in result["recommendations"]
            if item["canonical_id"] == candidate["id"]
        )

        self.assertEqual(selected["score"], 90)
        self.assertEqual(
            selected["score_components"]["muscle_match"], 100
        )
        self.assertEqual(
            selected["score_components"]["recent_session_penalty"], -10
        )
        self.assertIn("requested_muscle_primary_match", selected["reason_codes"])
        self.assertIn("recent_history_variety", selected["reason_codes"])
        self.assertEqual(result["personalization_level"], "request_and_history")
        self.assertTrue(
            selected["score_components"]["history_provenance"]
        )

    def test_duplicate_and_unresolved_catalog_ids_never_duplicate_results(self):
        duplicate = copy.deepcopy(self.records[0])
        unknown = copy.deepcopy(self.records[1])
        unknown["id"] = "not-in-the-artifact"
        catalog = StubCatalogResolver(
            [self.records[0], duplicate, unknown],
            resolution_resolver=self.resolver,
        )
        context, _, _ = self._context()

        result = recommend_workouts(context, catalog)

        ids = [item["canonical_id"] for item in result["recommendations"]]
        self.assertEqual(ids, [self.records[0]["id"]])

    def test_catalog_listing_returns_defensive_copies(self):
        records = self.resolver.list_exercises()
        original_name = records[0]["name"]
        records[0]["name"] = "modified by caller"

        self.assertEqual(
            self.resolver.resolve(records[0]["id"])["exercise"]["name"],
            original_name,
        )

    def test_service_has_no_database_or_ai_provider_dependencies(self):
        context, profile_reads, history_reads = self._context()
        recommend_workouts(context, self.resolver)

        self.assertEqual(profile_reads, ["a@example.test"])
        self.assertEqual(history_reads, ["user-a"])
        self.assertNotIn("backend.app.database", recommendation_module.__dict__)
        self.assertNotIn("google.generativeai", recommendation_module.__dict__)


if __name__ == "__main__":
    unittest.main()
