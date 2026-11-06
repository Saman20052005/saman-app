# CP-AI-04 — Generated Catalog & Canonical ID Resolution

## Status

**PASS — local CP-AI-04 acceptance, including explicit-date Chat HTTP
regression.** The guarded in-process regression and all 13 Chat workout
grounding tests pass against generated Library metadata. Real-token auth,
live Mongo, and deployment packaging remain unverified; no runtime E2E claim
is made.

## Workspace and preservation

| Check | Before implementation | After implementation |
|---|---|---|
| Workspace | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` | Same |
| Branch | `agent/nutrition-active-localhost-f02` | `agent/nutrition-active-localhost-f02` |
| HEAD | `10be1ab1971214acd2487ef893df3fcc80212fc9` | Same |
| Git status | 68 tracked-status entries and 2,089 untracked files observed after baseline tests | 68 tracked-status entries and 2,117 untracked files at final verification. Same branch/HEAD; existing WIP retained. New concurrent JCOM0508 work under `runtime_evidence/` and `docs/` was also present and untouched. |

No Context File was present in the workspace root. The CP-AI-03 report,
catalog decision, and proposal were read. Their proposed paths differed from
the execution allowlist; this implementation used only the execution
allowlist. `backend/routers/chat.py` already contained CP-AI-03 WIP and was
extended surgically. The CP-AI-03 test files were already untracked WIP and
were preserved while updating only the superseded identity assertions.

No add, commit, push, merge, reset, clean, stash, or checkout was performed.
`AGENTS.md`, dependency manifests/lockfiles, Library source/model, assets,
Mongo seed/data, and deployment configuration were not modified.

## Files changed by CP-AI-04

- `frontend/tool/export_ai_exercise_catalog.dart`
- `backend/app/data/ai_exercise_catalog.generated.json`
- `backend/app/services/exercise_catalog_resolver.py`
- `backend/routers/chat.py` (CP-AI-03 WIP retained; resolver/history wiring added)
- `backend/tests/test_ai04_catalog_resolver.py`
- `backend/tests/test_ai03_workout_history_context.py`
- `backend/tests/test_ai01_catalog_history_contract.py`
- `backend/tests/test_chat_workout_grounding.py` (additional path authorized
  by the user during this session)
- `frontend/test/ai_exercise_catalog_export_test.dart`
- `docs/ai_coach/CP-AI-04/REPORT.md`
- `docs/ai_coach/CP-AI-04/CATALOG_CONTRACT.md`
- `docs/ai_coach/CP-AI-04/CP_AI_05_PROPOSAL.md`

Root cause: N/A (new generated-catalog/resolution capability).

## Source and generated artifact

The Library provider `exerciseLibraryListProvider` returns
`curatedExerciseLibrary`; the exporter imports and serializes that same
runtime Dart list. The Flutter contract test confirms provider identity and
compares every exported field against each `Exercise.toJson()` value.

- Current artifact: `backend/app/data/ai_exercise_catalog.generated.json`
- Source: `frontend/lib/presentation/providers/exercise_providers.dart` —
  `curatedExerciseLibrary`
- Current count: **49 exercises**
- Unique nonempty IDs: **49**
- Unique normalized slugs (`trim + lowercase`): **49**
- Schema version: **1**
- Source digest: `7298842f560edb74de741b1091832d824a1daf32619c8c8bdc9dfd87381ff470`
- Deliberately different canonical ID/slug pairs remain intact:
  `db-bench-press` / `dumbbell-bench-press`,
  `db-shoulder-press` / `dumbbell-shoulder-press`, and
  `db-bicep-curl` / `dumbbell-bicep-curl`.

The artifact preserves the model's actual identifiers, names, muscle and
equipment lists, difficulty, thumbnail/video values, cues, mistakes, default
prescription, rest, rep type, and CV fields. It contains no generated time or
machine-specific path. Duplicate, empty, unsupported, or synthetic canonical
IDs fail before writing. The artifact is explicitly marked generated and is
not to be edited by hand.

## Resolver and history integration

The backend resolver reads the artifact relative to its own package location
using only Python standard-library modules. It does not import the database,
application providers, or Flutter. Chat loads this leaf module by file path to avoid the existing eager
`backend.app.services` package initializer. The CP-AI-03 latest-workout
normalizer and the explicit-date history formatter both use this resolver.
The legacy Mongo/seed identity lookup was removed from
`resolve_exercise_name`; history formatting does not query Mongo for exercise
metadata. The public Chat response and workout-history query behavior remain
unchanged.

- Canonical IDs are exact and case-sensitive.
- Slugs resolve by exact `strip + lowercase` normalization; display names and
  fuzzy matching are never used.
- A known ID with a slug that does not resolve to that same record is a
  conflict and remains unresolved.
- An unknown non-synthetic ID remains unresolved even if its slug happens to
  be known. With no ID, an exact slug may resolve.
- `plan_ex_*` is never treated as a canonical ID. It may resolve only by an
  exact catalog slug; the recorded synthetic ID and exact-slug provenance are
  retained separately from the canonical ID.
- Missing, malformed, duplicate, or synthetic-ID artifacts make resolution
  unavailable. Both Chat history formatters keep the history record and
  logged values, report the catalog limitation, and do not fall back to
  Mongo.
- The backend validates the serialized-record digest before building resolver
  indexes.
- Returned metadata is defensive-copied. History source and identity
  resolution provenance are retained. Catalog prescription values are
  reference metadata only and never replace recorded reps, weight, duration,
  completion, or volume.

CP-AI-03 history behavior was verified with the production resolver and
normalization helpers in isolated tests. At the initial verification, the
system interpreter lacked Chat HTTP test dependencies; the subsequent
guarded in-process HTTP verification and its limitations are recorded below.

## Verification

Environment: Python 3.11.9; Flutter 3.22.0; Dart 3.4.0. No dependency
installation or `pub get` was run.

| Command | Result |
|---|---|
| `python -B -m unittest backend.tests.test_ai03_workout_history_context backend.tests.test_ai03_catalog_contract backend.tests.test_ai01_catalog_history_contract -v` (baseline) | Exit 0; 18 passed. |
| `Set-Location frontend; flutter test test\workout_exercise_catalog_test.dart` (baseline) | Exit 0; 76 passed. |
| `Set-Location frontend; dart run tool\export_ai_exercise_catalog.dart` | Exit 0; artifact generated from runtime Library data. |
| `Set-Location frontend; flutter test test\ai_exercise_catalog_export_test.dart test\workout_exercise_catalog_test.dart` | Exit 0; 80 passed. |
| `python -B -m unittest backend.tests.test_ai04_catalog_resolver backend.tests.test_ai03_workout_history_context backend.tests.test_ai03_catalog_contract backend.tests.test_ai01_catalog_history_contract -v` | Exit 0; 31 passed, 0 failed. |
| `python -B -m unittest backend.tests.test_chat_workout_grounding -v` (initial system interpreter) | Not runnable with that interpreter: `bson`, FastAPI, and PyMongo were absent. No packages were installed. Follow-up found an existing Saman backend venv; guarded results are recorded below. |
| `Set-Location frontend; dart run tool\export_ai_exercise_catalog.dart --check` | Exit 0; current artifact. SHA-256 before/after was identical: `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33`. |
| `python -B -c "import ast,pathlib,sys; [ast.parse(pathlib.Path(p).read_text(encoding='utf-8'), filename=p) for p in sys.argv[1:]]" ...` | Exit 0; changed Python source and tests parsed without importing the app/database. |
| `git diff --check -- backend/routers/chat.py backend/tests/test_chat_workout_grounding.py` | Exit 0; scoped tracked changes are whitespace-clean. A repository-wide check reports whitespace/EOF issues in unrelated existing WIP; those files were not changed. |

The first exporter invocation used the wrong local package URI and exited 254;
it was corrected to the package name in `frontend/pubspec.yaml`, then
generation and tests passed. An initial backend run exposed a test-only
temporary-directory cleanup ordering issue; the test was corrected and the
final focused run passed. These were corrected during this task, not left as
failures.

## Explicit-date HTTP verification follow-up (2026-11-03)

Workspace rechecked at
`D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840`;
branch remains `agent/nutrition-active-localhost-f02` and HEAD remains
`10be1ab1971214acd2487ef893df3fcc80212fc9`. No Context File was found at the
workspace root. Existing WIP was preserved. The prior verification updated
only this report; this closeout changed only the two approved expected-name
assertions in `backend/tests/test_chat_workout_grounding.py` and this report.

**Interpreter:** `D:\SamanDev\runtime\saman-cp7-python\Scripts\python.exe`,
Python 3.11.9. Required imports were available in this existing environment:
FastAPI 0.143.0, PyMongo 4.18.3/BSON, HTTPX 0.28.1, Starlette, and Pydantic
2.14.0, plus `python-dotenv` 1.2.4, PyJWT 2.15.1, bcrypt 5.0.0, and certifi.
No packages were installed.

**Isolation:** The test module itself does not block database startup:
importing Chat imports `backend/app/database.py`, which constructs a
`MongoClient` and calls `client.admin.command('ping')`. To avoid any real
database, the in-process runner replaced `pymongo.MongoClient` with a
constructor guard *before* importing the test/app, disabled `dotenv.load_dotenv`
before imports, and blanked provider-key variables in the child process. The
constructor guard was exercised once and raised before any ping/client
connection. The test creates a fresh `FastAPI` app with no startup/shutdown
hooks and uses `TestClient` in-process (no server/listener); its
`get_current_user` dependency is overridden, and workout history,
conversations, and exercise collections are in-memory fakes. The provider
path was guarded and invoked zero times.

| Follow-up command/test | Result |
|---|---|
| Guarded `python -B -` runner invoking `TestChatWorkoutGrounding.test_generated_catalog_exercise_resolution_without_database_fallback` | Exit 0; 1 passed. Assertions confirmed one in-process `POST /api/chat`, `SPECIFIC_DATE`, one session read from the fake workout collection, active auth override, generated artifact's `seated-cable-row` metadata/provenance, zero exercise-collection lookups, Mongo creation blocked before ping, and zero AI-provider calls. |
| Initial guarded targeted invocation of the same test | Exit 1 after the unittest itself passed (1 test); an additional runner postcondition comparing non-ASCII text failed. The runner was corrected to use ASCII postconditions and the successful rerun is listed above. |
| Guarded `python -B -` runner loading `backend.tests.test_chat_workout_grounding` once (pre-closeout baseline) | Exit 1; 13 tests run, 11 passed, 2 failed. `test_specific_date_query_grounding` and `test_today_query_grounding` had stale expected display names; see resolution below. |

**Prior failure evidence (resolved):** The generated artifact record at
`backend/app/data/ai_exercise_catalog.generated.json` (ID/slug `pull-up`,
lines 1039–1042) matches the Library source at
`frontend/lib/presentation/providers/exercise_providers.dart` (lines
870–873): `nameVi = "Hít xà"`, `name = "Pull-Up"`. The failures were stale
assertions in the grounding test, not catalog/export drift.

**Closeout changes and verification (2026-11-03):** Changed only the two
expected display strings in `test_specific_date_query_grounding` and
`test_today_query_grounding`, from `Kéo xà (Pull-up)` to `Hít xà (Pull-Up)`.
The generated-catalog provenance assertion and the explicit-date assertion
that `self.memory_exercises_col.queries` equals an empty list were left
unchanged.

Interpreter: `D:\SamanDev\runtime\saman-cp7-python\Scripts\python.exe`
(Python 3.11.9), same existing Saman backend venv as the earlier HTTP probe.
No packages were installed. Both runs used the guarded `python -B -` harness
documented above: Mongo construction was blocked before ping, dotenv loading
was disabled before app imports, requests used the test module's in-process
`TestClient`, history/conversation/exercise stores were fakes,
`get_current_user` was overridden, and AI-provider calls were guarded.

| Closeout command/test | Result |
|---|---|
| Guarded `python -B -` runner loading `backend.tests.test_chat_workout_grounding` once | Exit 0; **13 passed, 0 failed, 0 skipped**. Includes both corrected display assertions and the generated-catalog/no-exercise-lookup regression. |
| Guarded `python -B -` runner invoking `TestChatWorkoutGrounding.test_generated_catalog_exercise_resolution_without_database_fallback` | Exit 0; **1 passed**. One in-process `/api/chat` request; `SPECIFIC_DATE`, one fake-history read, active auth override, generated `seated-cable-row` metadata/provenance, `EXERCISE_METADATA_LOOKUPS=0`, Mongo constructor guard exercised before ping, AI-provider calls 0. |
| `git diff --check -- backend/tests/test_chat_workout_grounding.py` | Exit 0. |

The full module passed against the current Library and artifact. The
explicit-date test retained its date/history/source/zero-query checks; no
additional production files were changed in this closeout.

## Acceptance and limitations

- [x] Artifact is generated from the exact list returned by the Library provider.
- [x] No manually maintained second catalog was added.
- [x] Output is deterministic; check mode detects drift and does not write.
- [x] IDs, slugs, ordering, and metadata match current runtime Dart values.
- [x] Backend resolver is independent of DB, cwd, and Flutter runtime.
- [x] Unknown, conflicting, synthetic, and unavailable states are explicit.
- [x] CP-AI-03 latest-workout normalization uses the resolver without changing
  logged metrics or ownership, empty/error, legacy, or text-return contracts.
- [x] Explicit-date Chat history uses only the generated resolver; the
  regression asserts generated-catalog provenance and no exercise DB query.
- [x] Targeted explicit-date Chat HTTP regression executed in-process with
  fake history, auth override, generated catalog, zero metadata DB queries,
  and Mongo/provider guards.
- [x] Full Chat grounding module passes: 13/13 under the guarded in-process
  harness.
- [x] Library offline behavior, assets/CV source, public contracts, and
  dependency/runtime configuration were not changed.
- [x] Targeted Flutter and resolver/history Python suites pass.
- [x] Existing WIP was preserved; no Git history or remote operations occurred.

**Known limitations:** Real-token auth, live Mongo behavior, and deployed
artifact packaging remain unverified. Closeout used an auth dependency
override, fake collections, and an in-process HTTP client; it does not claim
external-service or production deployment verification.

Whether deployment packaging includes
`backend/app/data/ai_exercise_catalog.generated.json` was not verified;
packaging configuration was outside scope and unchanged.

**Scope confirmation:** all files written by this task are within the
CP-AI-04 allowed paths, including the additional Chat regression-test path
authorized by the user. **Merge confirmation:** no commit, push, or merge.
