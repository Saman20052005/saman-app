import unittest
import sys
import os

# Ensure backend root is on sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from backend.app.models.user import UserProfileInput
from backend.app.models.common import Gender, ActivityLevel, Goal
from backend.services.health_engine import HealthEngine


class TestHealthEngineValidation(unittest.TestCase):
    def test_partial_profile_missing_height_raises_value_error(self):
        partial_input = UserProfileInput(
            age=25,
            gender=Gender.male,
            height=None,
            weight=70.0,
            activity_level=ActivityLevel.medium,
            goal=Goal.maintain_weight,
        )
        with self.assertRaises(ValueError) as ctx:
            HealthEngine.calculate_stats(partial_input)
        self.assertIn("required", str(ctx.exception).lower())

    def test_partial_profile_missing_weight_raises_value_error(self):
        partial_input = UserProfileInput(
            age=25,
            gender=Gender.male,
            height=175.0,
            weight=None,
            activity_level=ActivityLevel.medium,
            goal=Goal.maintain_weight,
        )
        with self.assertRaises(ValueError) as ctx:
            HealthEngine.calculate_stats(partial_input)
        self.assertIn("required", str(ctx.exception).lower())

    def test_partial_profile_missing_age_raises_value_error(self):
        partial_input = UserProfileInput(
            age=None,
            gender=Gender.male,
            height=175.0,
            weight=70.0,
            activity_level=ActivityLevel.medium,
            goal=Goal.maintain_weight,
        )
        with self.assertRaises(ValueError) as ctx:
            HealthEngine.calculate_stats(partial_input)
        self.assertIn("required", str(ctx.exception).lower())

    def test_valid_profile_calculates_bmi_and_calories(self):
        valid_input = UserProfileInput(
            age=25,
            gender=Gender.male,
            height=175.0,
            weight=70.0,
            activity_level=ActivityLevel.medium,
            goal=Goal.maintain_weight,
        )
        stats = HealthEngine.calculate_stats(valid_input)
        self.assertIsNotNone(stats.bmi)
        self.assertAlmostEqual(stats.bmi, 22.9, places=1)
        self.assertGreater(stats.daily_calories, 1500)
        self.assertGreater(stats.target_protein, 50)


if __name__ == "__main__":
    unittest.main()
