import ast
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BACKEND_CATALOG = ROOT / "backend" / "app" / "data" / "exercises" / "back.py"


def _load_backend_catalog():
    tree = ast.parse(BACKEND_CATALOG.read_text(encoding="utf-8"))
    assignment = next(
        node for node in tree.body
        if isinstance(node, ast.Assign)
        and any(
            isinstance(target, ast.Name) and target.id == "BACK_EXERCISES"
            for target in node.targets
        )
    )
    return ast.literal_eval(assignment.value)


class CatalogContractTests(unittest.TestCase):
    def test_backend_source_catalog_has_unique_slugs_and_no_canonical_ids(self):
        records = _load_backend_catalog()
        slugs = [record.get("slug") for record in records]
        self.assertEqual(len(records), 10)
        self.assertTrue(all(isinstance(slug, str) and slug for slug in slugs))
        self.assertEqual(len(slugs), len(set(slugs)))
        self.assertTrue(all("id" not in record for record in records))


if __name__ == "__main__":
    unittest.main()
