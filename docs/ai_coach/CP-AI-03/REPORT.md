# CP-AI-03 — Workout History Context & Catalog ID Contract

## Status

**PASS for the scoped Chat source change and isolated tests.** Canonical
`exercise_logs` now feed the latest-workout context, and read state, legacy
fallback, set metrics, and unresolved identities are explicit.

**HTTP/auth route integration and live Mongo behavior remain UNVERIFIED.**
The available Python interpreter lacks FastAPI, PyMongo, BSON, and HTTPX.
No dependencies were installed, no application/database module was imported,
and no database or provider was contacted.

Recommendation readiness remains **NOT READY**. This checkpoint makes no
canonical Flutter catalog resolver and does not implement recommendations.

## Identity and worktree

| Check | Before | After |
|---|---|---|
| Workspace | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` | Same |
| Branch | `agent/nutrition-active-localhost-f02` | Same |
| HEAD | `10be1ab1971214acd2487ef893df3fcc80212fc9` | Same |
| Git status | 67 tracked-status entries; 1,331 untracked files at resume preflight | 68 tracked-status entries; 1,340 untracked files |

The supplied reference of 1,257 untracked files was not reproduced at resume;
the 74-file difference was present before edits and was not attributed or
cleaned. Existing WIP was retained. No reset, clean, stash, checkout, add,
commit, push, or merge was performed. No CP-AI-01 report was changed.

## Root cause and patch

**FACT — source:** `_build_latest_workout_context` in
[`backend/routers/chat.py`](../../backend/routers/chat.py) queried owner
records but read only `completed_exercises`/`exercises`; it ignored the
canonical `exercise_logs` written by the workout-session route.

**FACT — source:** query exceptions were converted to an empty list, then
returned the same “no data” context as a successful empty query. Fallback
queries also swallowed their errors.

**TEST — before change:** the updated canonical-history regression failed
because `db-bench-press` was absent from the returned context.

**CONCLUSION — patch:** the helper now returns a typed internal result with
`available`, `empty`, or `unavailable` status. It issues the existing owner
`$or` query once (email, legacy `user_email`, authenticated `user_id`); a
failed read is logged by exception type only and is never represented as empty.
The query ownership predicates were not broadened.
The existing `_build_latest_workout_context` text-returning helper remains
compatible; `build_health_context` consumes the structured internal result.

Normalization behavior:

- Canonical `exercise_logs` wins whenever the field is present. Empty or
  malformed canonical data is reported; it never falls through to a legacy
  representation from the same session.
- Canonical sets are grouped by their stored ID/slug pair. Completion is
  `completed`, `incomplete`, or `unknown`; missing flags do not default to
  completed. Reps and seconds remain separate units.
- Volume is calculated only for completed repetition sets with explicit,
  valid reps and weight. Partial volume is labelled partial; missing or
  malformed metrics are not filled with defaults.
- Legacy names remain readable only when canonical `exercise_logs` is absent.
  Legacy names are labelled as recorded, not resolved; legacy set/volume
  values are not inferred.
- Current evidence does not establish a shared Flutter/backend catalog ID
  mapping. All IDs remain unresolved in this context, including
  `plan_ex_*`, conflicting ID/slug pairs, and IDs without a verified mapping.
  A stored exercise name may be shown as a recorded label, without catalog
  metadata.
- If any returned record has a missing or invalid timestamp, the helper does
  not select an older record as “latest”; it reports the limitation instead.
  The existing legacy ordering is preserved, with canonical `started_at`
  added after `start_time`. Dates continue to use the current Vietnam-time
  normalization.
- The database query has no limit or pagination and reads all matching owner
  records; the prompt states this and the number read. The displayed context
  caps output at five exercises and five sets per exercise and reports
  truncation.
- For explicit workout-history questions, the general latest-workout summary
  is omitted so it is not duplicated by the existing history-grounding block.
  Meal, water, action, and stored conversation-history paths were not changed.

## Catalog decision evidence

**VERIFIED—SOURCE / ISOLATED TEST:**

- Flutter's `curatedExerciseLibrary` is the current Library data source and the
  provider/repository return that in-process list. The existing Flutter
  catalog test confirms 49 entries and 49 unique IDs and slugs.
- Backend `BACK_EXERCISES` contains 10 records, 10 unique slugs, and no
  canonical `id` fields. The CP-AI-03 contract test reads the Python literal
  with `ast.literal_eval`, not a broad text match.
- CP-AI-01's source comparison found five exact slug overlaps, three Flutter
  ID/slug pairs that intentionally differ, and metadata/schema mismatches:
  backend equipment is a scalar rather than a list, backend `defaultReps` is
  numeric rather than the Flutter string/range, backend records lack Flutter
  IDs and bundled thumbnail paths, and several overlapping metadata values
  differ.
- The workout API reads Mongo `exercises`; the inspected static seed does not
  prove the deployed collection is populated or equivalent. Mongo/deployed
  catalog contents remain **UNVERIFIED**.

The preferred future direction and its proposed paths are recorded in
[`CATALOG_DECISION.md`](./CATALOG_DECISION.md). CP-AI-03 does not change
Library data, seed data, Mongo, Flutter, or the backend catalog source.

## Verification

Interpreter: `C:\Users\GL\AppData\Local\Programs\Python\Python311\python.exe`,
Python 3.11.9. The available SDK is Flutter 3.22.0 / Dart 3.4.0.

| Command | Result |
|---|---|
| `python -B -m unittest backend.tests.test_ai01_catalog_history_contract -v` (pre-edit baseline) | Exit 0; 7 passed. |
| `python -B -m unittest backend.tests.test_ai01_catalog_history_contract.CatalogHistoryCurrentContractTests.test_latest_helper_reads_canonical_logs_without_resolving_catalog_identity -v` (new regression, before source fix) | Exit 1; expected failure: canonical exercise ID missing from context. |
| `python -B -m unittest backend.tests.test_ai03_workout_history_context backend.tests.test_ai03_catalog_contract backend.tests.test_ai01_catalog_history_contract -v` (after fix) | Exit 0; 18 passed, 0 failed, 0 skipped. The Chat helper and normalizer are extracted from current source and exercised with in-memory fakes; this is **VERIFIED—ISOLATED TEST**, not HTTP/runtime E2E. |
| `Set-Location frontend; flutter test test\workout_exercise_catalog_test.dart` | Exit 0; 76 Flutter tests passed, including the 49-entry/unique-ID/slug contract. |
| `python -B -c "import ast,pathlib,sys; [ast.parse(pathlib.Path(p).read_text(encoding='utf-8'), filename=p) for p in sys.argv[1:]]" backend\routers\chat.py backend\tests\test_ai01_catalog_history_contract.py backend\tests\test_ai03_workout_history_context.py backend\tests\test_ai03_catalog_contract.py` | Exit 0; all four files parsed. |

An initial isolated-test import attempt reached `backend.app.services` package
initialization and failed because PyMongo is not installed. No dependency was
installed. To avoid package/import side effects, the final tests extract the
actual production helper bodies from `chat.py` and execute them with fake
collections; the normalization implementation remains in the allowed Chat
helper file.

Existing HTTP/chat tests were not run: their imports require the unavailable
runtime dependencies and may initialize the application/database. No real
database, external provider, route, or authentication flow was invoked.

## Acceptance and scope

- [x] Canonical `exercise_logs` appear in the latest-workout context.
- [x] Legacy fallback is absent-only; canonical empty/malformed records do not
  silently fall back or double-count.
- [x] Successful empty and failed reads have different statuses and prompts.
- [x] Existing ownership predicates remain unchanged; two-user isolation is
  covered by an isolated fake-collection test.
- [x] Unknown, conflicting, and `plan_ex_*` identities remain unresolved.
- [x] No missing reps, weight, duration, completion, muscle, equipment, or
  catalog data is invented.
- [x] The regression fails before the patch and passes after it; targeted
  isolated tests pass.
- [x] Catalog evidence and one preferred generated-source direction are
  documented; Library migration is deferred.
- [x] No Flutter/catalog data, database, seed, auth, API schema, runtime
  dependency, or configuration was changed.
- [x] WIP preserved; no Git history or remote operations performed.

### Files changed by this checkpoint

- `backend/routers/chat.py`
- `backend/tests/test_ai01_catalog_history_contract.py` (authorized assertion
  update; unrelated catalog/history assertions retained)
- `backend/tests/test_ai03_workout_history_context.py`
- `backend/tests/test_ai03_catalog_contract.py`
- `docs/ai_coach/CP-AI-03/REPORT.md`
- `docs/ai_coach/CP-AI-03/CATALOG_DECISION.md`
- `docs/ai_coach/CP-AI-03/CP_AI_04_PROPOSAL.md`

**Known limitations:** in-process HTTP/auth integration, runtime Mongo query
behavior, deployed catalog state, and historical data quality are unverified.
Recommendation readiness is still **NOT READY**. All changes remain local;
there was no commit, push, or merge.
