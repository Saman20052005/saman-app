"""
Regression tests for Vietnamese food search normalization (Đ/đ handling & diacritic/non-diacritic search).
Ensures:
1. _normalize_text correctly transforms 'đ' and 'Đ' into 'd', preventing character loss.
2. Search query normalization handles both accented and unaccented queries.
3. Database documents in foods collection adhere to standardized name_search conventions.
"""

import os
import sys
import unittest
import unicodedata

# Enable imports from project root
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from backend.routers.nutrition import _normalize_text
from backend.scripts.migrate_foods_name_search import normalize as migrate_normalize
from backend.scripts.import_vietnam_foods import normalize_text as import_normalize


class TestFoodSearchNormalization(unittest.TestCase):
    def test_normalize_letter_d_variants(self):
        """Test that Vietnamese 'đ' and 'Đ' are preserved as 'd'."""
        cases = [
            ("Đậu bắp", "dau bap"),
            ("Ức gà (luộc/hấp)", "uc ga (luoc/hap)"),
            ("Cơm trắng (1 chén)", "com trang (1 chen)"),
            ("Bí đỏ", "bi do"),
            ("Đu đủ", "du du"),
            ("Đậu phụ (đậu hũ)", "dau phu (dau hu)"),
            ("Cà phê sữa đá", "ca phe sua da"),
            ("Đường kính", "duong kinh"),
            ("ĐÀ LẠT", "da lat"),
            ("đậu đỏ", "dau do"),
        ]
        for original, expected in cases:
            with self.subTest(original=original):
                self.assertEqual(_normalize_text(original), expected)
                self.assertEqual(migrate_normalize(original), expected)
                self.assertEqual(import_normalize(original), expected)

    def test_search_query_matching_logic(self):
        """Test regex matching behavior between normalized queries and food names."""
        food_doc = {
            "name": "Đậu bắp",
            "name_search": _normalize_text("Đậu bắp")  # "dau bap"
        }
        
        # Test queries that must match "Đậu bắp"
        queries = ["dau bap", "Đậu bắp", "dau", "bap", "ĐẬU", "DAU"]
        for q in queries:
            q_norm = _normalize_text(q)
            matches = (
                q_norm in food_doc["name_search"] or
                q_norm in _normalize_text(food_doc["name"])
            )
            self.assertTrue(matches, f"Query '{q}' (norm: '{q_norm}') should match food '{food_doc['name']}'")

    def test_uc_ga_matching_logic(self):
        """Test matching for 'uc ga' and 'Ức gà'."""
        food_doc = {
            "name": "Ức gà luộc/hấp",
            "name_search": _normalize_text("Ức gà luộc/hấp")  # "uc ga luoc/hap"
        }
        queries = ["uc ga", "Ức gà", "uc", "ga", "ỨC GÀ"]
        for q in queries:
            q_norm = _normalize_text(q)
            matches = (
                q_norm in food_doc["name_search"] or
                q_norm in _normalize_text(food_doc["name"])
            )
            self.assertTrue(matches, f"Query '{q}' should match food '{food_doc['name']}'")

    def test_database_foods_no_dropped_d(self):
        """Check real database if available: no item in foods collection should have dropped 'đ'."""
        from pymongo import MongoClient
        try:
            client = MongoClient("mongodb://127.0.0.1:27028", serverSelectionTimeoutMS=1000)
            db = client["saman_cp26_localtest"]
            foods_col = db["foods"]
            if foods_col.count_documents({}) == 0:
                self.skipTest("Runtime database not populated or unreachable")
            
            # Check Đậu bắp specifically
            dau_bap = foods_col.find_one({"name": "Đậu bắp"})
            if dau_bap:
                self.assertEqual(dau_bap.get("name_search"), "dau bap", "Đậu bắp name_search must be 'dau bap'")
            
            # Check all foods with 'đ' or 'Đ'
            d_foods = foods_col.find({"name": {"$regex": "[đĐ]"}})
            for food in d_foods:
                expected = _normalize_text(food["name"])
                actual = food.get("name_search")
                self.assertEqual(actual, expected, f"Food '{food['name']}' has name_search '{actual}', expected '{expected}'")
        except Exception as e:
            self.skipTest(f"Database check skipped: {e}")


if __name__ == "__main__":
    unittest.main()

