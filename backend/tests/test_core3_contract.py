import unittest
from datetime import datetime, timedelta, timezone

from backend.app.services.core3_context import build_core3_context
from backend.app.services.core3_provider import (
    MAX_INPUT_TOKENS,
    MAX_OUTPUT_TOKENS,
    Core3PromptTooLarge,
    GeminiCore3Provider,
    _estimate_tokens,
    render_prompt,
)


class _Cursor(list):
    def sort(self, value):
        return self

    def limit(self, value):
        self.limit_value = value
        return _Cursor(self[:value])


class _Collection:
    def __init__(self, rows):
        self.rows = rows
        self.calls = []

    def find(self, query, projection):
        self.calls.append((query, projection))
        return _Cursor(self.rows)

    def find_one(self, query, projection):
        self.calls.append((query, projection))
        return {"goal": "fitness", "email": "private@example.test", "full_name": "Private"}


class _FakeGemini:
    def __init__(self):
        self.calls = []

    def generate_content(self, prompt, generation_config):
        self.calls.append((prompt, generation_config))
        return type("Result", (), {"text": "Advisory response"})()


class Core3ContractTests(unittest.TestCase):
    def test_context_queries_are_bounded_and_allowlisted(self):
        nutrition = _Collection([{"date": "2026-11-04", "total_calories": 100} for _ in range(501)])
        workout = _Collection([{"_id": i, "exercise_logs": [{"exercise_slug": "squat"}] * 400} for i in range(12)])
        users = _Collection([])
        principal = {"_id": "user-a", "email": "a@example.test"}
        ctx = build_core3_context(principal=principal, nutrition_collection=nutrition,
            workout_collection=workout, users_collection=users,
            now=datetime(2026, 11, 4, 12, tzinfo=timezone.utc))
        self.assertEqual(nutrition.calls[0][0]["user_email"], "a@example.test")
        self.assertEqual(nutrition.calls[0][1]["_id"], 0)
        self.assertTrue(ctx["nutrition"]["coverage_truncated"])
        self.assertLessEqual(len(ctx["nutrition"]["summary"]), 7)
        self.assertEqual(workout.calls[0][0]["user_id"], "user-a")
        self.assertEqual(workout.calls[0][1]["exercise_logs"], {"$slice": 400})
        self.assertTrue(ctx["workout"]["coverage_truncated"])
        self.assertNotIn("email", ctx["profile"]["data"])
        self.assertNotIn("full_name", ctx["profile"]["data"])

        empty = build_core3_context(principal=principal,
            nutrition_collection=_Collection([]), workout_collection=_Collection([]),
            users_collection=_Collection([]), now=datetime(2026, 11, 4, 12, tzinfo=timezone.utc))
        self.assertTrue(empty["nutrition"]["coverage_missing"])
        self.assertTrue(empty["workout"]["coverage_missing"])

    def test_prompt_trims_oldest_history_and_caps_budget(self):
        history = [{"role": "user", "content": "old " * 5000}, {"role": "assistant", "content": "new"}]
        prompt = render_prompt("question", history, {"optional": "context"})
        self.assertLessEqual(_estimate_tokens(prompt), MAX_INPUT_TOKENS)
        self.assertNotIn("old old", prompt)

    def test_mandatory_oversize_rejects_before_fake_provider_dispatch(self):
        engine = _FakeGemini()
        provider = GeminiCore3Provider(engine)
        with self.assertRaises(Core3PromptTooLarge):
            render_prompt("x" * 20000, [], {})
        self.assertEqual(engine.calls, [])

    def test_fake_gemini_and_output_cap(self):
        engine = _FakeGemini()
        provider = GeminiCore3Provider(engine)
        import asyncio
        self.assertEqual(asyncio.run(provider.generate("small prompt")), "Advisory response")
        self.assertEqual(engine.calls[0][1]["max_output_tokens"], MAX_OUTPUT_TOKENS)


if __name__ == "__main__":
    unittest.main()
