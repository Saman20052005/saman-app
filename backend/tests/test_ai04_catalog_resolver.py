import ast
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RESOLVER_SOURCE = (
    ROOT / "backend" / "app" / "services" / "exercise_catalog_resolver.py"
)
ARTIFACT = ROOT / "backend" / "app" / "data" / "ai_exercise_catalog.generated.json"
CHAT_SOURCE = ROOT / "backend" / "routers" / "chat.py"


def _load_resolver_class():
    spec = importlib.util.spec_from_file_location(
        "ai04_exercise_catalog_resolver", RESOLVER_SOURCE
    )
    if spec is None or spec.loader is None:
        raise AssertionError("Could not load the production resolver module.")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.ExerciseCatalogResolver


def _refresh_record_digest(payload):
    serialized = json.dumps(
        payload["exercises"],
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    payload["source_sha256"] = hashlib.sha256(serialized).hexdigest()
    return payload


ExerciseCatalogResolver = _load_resolver_class()


class ExerciseCatalogResolverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.artifact = json.loads(ARTIFACT.read_text(encoding="utf-8"))
        cls.resolver = ExerciseCatalogResolver()

    def test_artifact_records_resolve_by_exact_id_and_slug(self):
        records = self.artifact["exercises"]
        ids = [record["id"] for record in records]
        slugs = [record["slug"].casefold() for record in records]
        self.assertTrue(records)
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len(slugs), len(set(slugs)))

        for record in records:
            with self.subTest(exercise_id=record["id"]):
                result = self.resolver.resolve(record["id"], record["slug"])
                self.assertEqual(result["status"], "resolved")
                self.assertEqual(result["exercise"]["id"], record["id"])
                self.assertEqual(result["exercise"]["slug"], record["slug"])

    def test_exact_id_and_normalized_slug_resolve_without_database(self):
        result = self.resolver.resolve("db-bench-press", " DUMBBELL-BENCH-PRESS ")
        self.assertEqual(result["status"], "resolved")
        self.assertEqual(result["exercise"]["id"], "db-bench-press")
        self.assertEqual(result["provenance"]["kind"], "canonical_id+exact_slug")
        slug_only = self.resolver.resolve(None, "DUMBBELL-BENCH-PRESS")
        self.assertEqual(slug_only["status"], "resolved")
        self.assertEqual(slug_only["exercise"]["id"], "db-bench-press")
        self.assertEqual(slug_only["provenance"]["kind"], "exact_slug")

    def test_unknown_id_is_not_promoted_by_a_known_slug(self):
        result = self.resolver.resolve(
            "removed-exercise-99", "dumbbell-bench-press"
        )
        self.assertEqual(result["status"], "unresolved")
        self.assertEqual(result["reason"], "unknown canonical ID")
        self.assertIsNone(result["exercise"])

    def test_synthetic_id_resolves_only_with_an_exact_slug_and_keeps_provenance(self):
        record = self.resolver.resolve("plan_ex_7", "dumbbell-bench-press")
        self.assertEqual(record["status"], "resolved")
        self.assertEqual(record["exercise"]["id"], "db-bench-press")
        self.assertEqual(
            record["provenance"],
            {
                "kind": "synthetic_id+exact_slug",
                "synthetic_id": "plan_ex_7",
                "exact_slug": "dumbbell-bench-press",
            },
        )

        without_slug = self.resolver.resolve("plan_ex_7", "plan_ex_7")
        self.assertEqual(without_slug["status"], "unresolved")
        self.assertIn("requires an exact catalog slug", without_slug["reason"])

    def test_known_id_with_a_different_slug_fails_closed(self):
        result = self.resolver.resolve("db-bench-press", "lat-pulldown")
        self.assertEqual(result["status"], "conflict")
        self.assertEqual(result["reason"], "ID/slug conflict")
        self.assertIsNone(result["exercise"])

    def test_unknown_identity_and_unknown_slug_remain_unresolved(self):
        unknown_id = self.resolver.resolve("removed-exercise-99", None)
        unknown_slug = self.resolver.resolve(None, "nearby-name")
        self.assertEqual(unknown_id["status"], "unresolved")
        self.assertEqual(unknown_slug["status"], "unresolved")
        self.assertIsNone(unknown_id["exercise"])
        self.assertIsNone(unknown_slug["exercise"])

    def test_returned_metadata_is_a_defensive_copy(self):
        first = self.resolver.resolve("db-bench-press", "dumbbell-bench-press")
        original_equipment = list(first["exercise"]["equipment"])
        first["exercise"]["equipment"].append("caller mutation")
        first["exercise"]["cues"].clear()

        second = self.resolver.resolve("db-bench-press", "dumbbell-bench-press")
        self.assertEqual(second["exercise"]["equipment"], original_equipment)
        self.assertTrue(second["exercise"]["cues"])

    def test_default_artifact_path_is_independent_of_current_directory(self):
        original_directory = os.getcwd()
        with tempfile.TemporaryDirectory() as temporary_directory:
            try:
                os.chdir(temporary_directory)
                resolver = ExerciseCatalogResolver()
                self.assertTrue(resolver.available)
                self.assertEqual(
                    resolver.resolve("db-bench-press")["status"], "resolved"
                )
            finally:
                os.chdir(original_directory)

    def test_chat_loader_imports_leaf_resolver_without_services_initializer(self):
        tree = ast.parse(CHAT_SOURCE.read_text(encoding="utf-8"))
        loader = next(
            node
            for node in tree.body
            if isinstance(node, ast.FunctionDef)
            and node.name == "_create_exercise_catalog_resolver"
        )
        namespace = {
            "Path": Path,
            "importlib": importlib,
            "__file__": str(CHAT_SOURCE),
        }
        module = ast.fix_missing_locations(
            ast.Module(body=[loader], type_ignores=[])
        )
        exec(compile(module, str(CHAT_SOURCE), "exec"), namespace)
        previously_loaded = set(sys.modules)

        resolver = namespace["_create_exercise_catalog_resolver"]()

        newly_loaded_services = {
            name
            for name in set(sys.modules) - previously_loaded
            if name in {"app.services", "backend.app.services"}
            or name.startswith("backend.app.services.")
        }
        self.assertTrue(resolver.available)
        self.assertEqual(newly_loaded_services, set())

    def test_missing_malformed_and_duplicate_artifacts_are_unavailable(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            missing = ExerciseCatalogResolver(root / "missing.json")
            self.assertFalse(missing.available)
            self.assertEqual(
                missing.resolve("db-bench-press")["status"], "unavailable"
            )

            malformed_path = root / "malformed.json"
            malformed_path.write_text("{", encoding="utf-8")
            malformed = ExerciseCatalogResolver(malformed_path)
            self.assertFalse(malformed.available)
            self.assertEqual(
                malformed.resolve("db-bench-press")["status"], "unavailable"
            )

            deeply_nested_path = root / "deeply-nested.json"
            deeply_nested_path.write_text(
                f'{"[" * 2000}0{"]" * 2000}',
                encoding="utf-8",
            )
            deeply_nested = ExerciseCatalogResolver(deeply_nested_path)
            self.assertFalse(deeply_nested.available)
            self.assertEqual(
                deeply_nested.resolve("db-bench-press")["status"],
                "unavailable",
            )

            stale_payload = json.loads(json.dumps(self.artifact))
            stale_payload["exercises"][0]["name"] = "Edited without digest update"
            stale_path = root / "stale-digest.json"
            stale_path.write_text(json.dumps(stale_payload), encoding="utf-8")
            stale = ExerciseCatalogResolver(stale_path)
            self.assertFalse(stale.available)
            self.assertEqual(
                stale.resolve("db-bench-press")["status"], "unavailable"
            )

            for field in ("id", "slug"):
                with self.subTest(duplicate_field=field):
                    duplicate_payload = json.loads(json.dumps(self.artifact))
                    duplicate_payload["exercises"][1][field] = duplicate_payload[
                        "exercises"
                    ][0][field]
                    _refresh_record_digest(duplicate_payload)
                    duplicate_path = root / f"duplicate-{field}.json"
                    duplicate_path.write_text(
                        json.dumps(duplicate_payload), encoding="utf-8"
                    )
                    duplicate = ExerciseCatalogResolver(duplicate_path)
                    self.assertFalse(duplicate.available)
                    self.assertEqual(
                        duplicate.resolve("db-bench-press")["status"],
                        "unavailable",
                    )

            duplicate_key_path = root / "duplicate-key.json"
            duplicate_key_path.write_text(
                '{"schema_version":1,"schema_version":1}',
                encoding="utf-8",
            )
            duplicate_key = ExerciseCatalogResolver(duplicate_key_path)
            self.assertFalse(duplicate_key.available)
            self.assertEqual(
                duplicate_key.resolve("db-bench-press")["status"],
                "unavailable",
            )

            synthetic_payload = json.loads(json.dumps(self.artifact))
            synthetic_payload["exercises"][0]["id"] = "plan_ex_0"
            _refresh_record_digest(synthetic_payload)
            synthetic_path = root / "synthetic-id.json"
            synthetic_path.write_text(
                json.dumps(synthetic_payload), encoding="utf-8"
            )
            synthetic = ExerciseCatalogResolver(synthetic_path)
            self.assertFalse(synthetic.available)
            self.assertEqual(
                synthetic.resolve("plan_ex_0", "dumbbell-bench-press")[
                    "status"
                ],
                "unavailable",
            )


if __name__ == "__main__":
    unittest.main()
