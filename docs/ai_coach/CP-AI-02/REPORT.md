# CP-AI-02 — Workout Plan Ownership Filter

## Status

**PASS for the scoped source/query fix and isolated tests.** The two CP-AI-01 ownership failures are now passing against the current handler function body and a fake collection that evaluates Mongo-style `$and`, `$or`, and array membership.

**HTTP/auth integration and runtime Mongo behavior remain UNVERIFIED.** The current interpreter has no FastAPI, PyMongo, BSON, or HTTPX packages; no dependencies were installed and no application/database module was imported.

## Workspace and WIP

| Check | Before | After |
|---|---|---|
| Workspace | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` | Same |
| Branch | `agent/nutrition-active-localhost-f02` | Same |
| HEAD | `10be1ab1971214acd2487ef893df3fcc80212fc9` | Same |
| Git status with all untracked files | 67 tracked-status entries; 931 untracked files; 998 entries | 67 tracked-status entries; 933 untracked files; 1000 entries |

The two additional untracked files are the new `backend/tests/test_ai02_plan_ownership_route.py` and this report. Existing WIP was retained. `backend/routers/workout.py` was already modified before this checkpoint; its prior diff included unrelated imports and workout-session persistence code. Those hunks were preserved, and this checkpoint changed only the `/plans` query/filter block. `backend/tests/test_ai01_plan_query_ownership.py` was also a pre-existing untracked CP-AI-01 file; its assertions were preserved and additional ownership/filter cases were added. No concurrent edit in the target query block was observed at preflight.

Only the following allowed paths were changed by this checkpoint:

- `backend/routers/workout.py`
- `backend/tests/test_ai01_plan_query_ownership.py`
- `backend/tests/test_ai02_plan_ownership_route.py`
- `docs/ai_coach/CP-AI-02/REPORT.md`

No add, commit, push, merge, checkout, reset, clean, or stash was performed.

## Root cause and visibility contract

Before the fix, `get_workout_plans` built one `$or` containing both owner predicates (`email`, `user_id`) and muscle predicates (`target_muscles`, `muscle_groups`). A plan matched by muscle alone could therefore be returned regardless of owner; any owned plan could also satisfy the same `$or` without matching the requested muscle.

The pre-fix isolated test run confirmed this:

- `test_muscle_filter_is_intersected_with_ownership`: **FAIL**; the result included `plan-b-chest` and `plan-a-legs`.
- `test_user_a_muscle_filter_does_not_disclose_user_b_private_plan`: **FAIL**; User A received User B's matching Chest plan.
- The other 2 ownership tests passed.

Source verification found:

- Plan creation stores the authenticated email and, when available, the user's string `_id` as `user_id`.
- The existing `/plans` visibility query supports either `email == authenticated email` or `user_id == authenticated user ID`. Regression fixtures confirm both email-only legacy and user-ID-only records remain visible to the matching owner.
- The plan model and `/plans` route do not define a shared/system/public visibility field or branch. Such a policy is **UNVERIFIED**; this change adds no visibility branch and makes no claim about intended shared-plan policy.

Root-cause source location before the fix: `backend/routers/workout.py`, `get_workout_plans`, originally lines 274-282 in the pre-edit working tree.

## Patch

The route now keeps the existing owner alternatives in `owner_query`. A requested muscle is a separate `$or` over `target_muscles` and `muscle_groups`, combined with the owner query using `$and`. The existing difficulty predicate remains an independent conjunction. Thus muscle alternatives retain Mongo's existing array-element equality behavior, while muscle matching can only narrow authorized plans.

No response fields, route/auth dependencies, create/update/delete behavior, sorting, or pagination were changed.

## Verification

Interpreter: `C:\Users\GL\AppData\Local\Programs\Python\Python311\python.exe`, Python 3.11.9.

### Before the patch

```text
python -B -m unittest backend.tests.test_ai01_plan_query_ownership -v
```

Exit code **1**; 4 tests run, 2 passed, 2 failed, 0 skipped. The two failures are listed above.

### After the patch

```text
python -B -m unittest discover -s backend\tests -p "test_ai01_*.py" -v
```

Exit code **0**; 13 tests run, 13 passed, 0 failed, 0 skipped.

```text
python -B -m unittest backend.tests.test_ai02_plan_ownership_route -v
```

Exit code **0**; 2 tests run, 2 passed, 0 failed, 0 skipped.

Combined confirmation:

```text
python -B -m unittest backend.tests.test_ai01_plan_query_ownership backend.tests.test_ai01_catalog_history_contract backend.tests.test_ai02_plan_ownership_route -v
```

Exit code **0**; 15 tests run, 15 passed, 0 failed, 0 skipped.

Python AST syntax parsing of the changed route and test files also passed without writing bytecode.

The isolated tests extract the actual current `get_workout_plans` function body and evaluate its generated query against in-memory fixtures; they do not hardcode the expected query. They verify the original A/B ownership cases, matching and nonmatching muscles, both owner field formats, `muscle_groups`, array membership, difficulty conjunction, and response/filter shape. The `test_ai02_plan_ownership_route.py` name does not imply an HTTP request was made: FastAPI could not be imported in the available interpreter. Existing route tests also import the app/database modules, and cannot be run without unavailable dependencies; those tests were not attempted. No database or external service was accessed.

## Acceptance results

- [x] Root cause verified from source and reproduced before editing.
- [x] The two CP-AI-01 failure assertions now pass unchanged.
- [x] Muscle filters do not expand owner visibility.
- [x] Existing `email`/`user_id` owner alternatives are preserved.
- [x] Shared/system/public visibility remains UNVERIFIED; no new policy is assumed.
- [x] Difficulty and muscle predicates narrow the authorized set; response/filter shape is unchanged.
- [x] Isolated regression tests pass.
- [x] Production change is confined to the query/filter block of `get_workout_plans`.
- [x] No data, dependencies, configuration, or runtime were changed.
- [x] WIP preserved; no commit/push/merge performed.

## Remaining risks and CP-AI-03

- Validate the route through FastAPI dependency overrides and an in-memory collection when a local environment with existing dependencies is available; verify Mongo query semantics without connecting to a real database.
- Define and verify whether shared/system plans exist and their intended visibility before adding any corresponding query branch.
- Do not enable recommendations yet. CP-AI-01 found that the Flutter curated Library and backend exercise catalog are not proven equivalent, and Chat's latest-workout helper does not read canonical `exercise_logs`.
- CP-AI-03 should address the single authoritative catalog/ID-resolution decision and history normalization/read-error contract before recommendation output or UI is implemented. Recommendation readiness remains **NOT READY**.
