# CP-AI-01 — Catalog, History & Ownership Verification

## Status

**Checkpoint: PARTIAL.** The source audit and isolated contract tests are complete. The ownership tests reproduce two failures in the current `/plans` handler. No production source, API, database, seed, dependency, or runtime was changed.

**Recommendation readiness: NOT READY.** The backend cannot currently establish that a recommended exercise belongs to the Flutter Library, canonical workout logs are not consumed by the latest-workout Chat helper, and filtered private plans are exposed by the current query.

## Identity and worktree

| Check | Before | After |
|---|---|---|
| Workspace | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` | Same |
| Branch | `agent/nutrition-active-localhost-f02` | Same |
| HEAD | `10be1ab1971214acd2487ef893df3fcc80212fc9` | Same |
| Git status | `git status --short`: 67 tracked modifications; 142 untracked status entries (directory-collapsed) | `git status --short -uall`: 67 tracked modifications, 925 untracked files, 992 total entries (five CP-AI-01 files added) |

The supplied CP-AI-00 count of 918 untracked items was not reproduced as a comparable pre-edit `-uall` count; the fresh preflight used the default collapsed status. The final count leaves 920 untracked files other than the five created here, a difference of two from that reference which cannot be attributed from the available preflight snapshot. Those paths were not modified. The workspace already contained extensive WIP. No existing file at any of the five allowed output paths existed during preflight. The two test-created `.pyc` files were removed; pre-existing cache files were left untouched. No checkout, reset, clean, stash, add, commit, push, or merge was performed.

## Findings and acceptance

| Acceptance item | Result | Evidence |
|---|---|---|
| Identity and WIP preserved | PASS | Branch and HEAD unchanged; existing tracked modifications remained at 67. |
| Catalog/UI sources and backend gap identified | PASS—SOURCE; database population UNVERIFIED | Flutter Library uses `curatedExerciseLibrary` (49 entries); backend has a separate 10-entry slug catalog. No database was queried. |
| Canonical ID direction selected without a second manual list | PARTIAL | Contract proposes Flutter `Exercise.id` as the stable ID and requires one shared, authoritative catalog source before server recommendations. No production mapping was created. |
| Canonical, legacy, and plan history analyzed | PASS—SOURCE; normalization MISSING | Session writers and Chat readers differ; see the contract. |
| Ownership checked by isolated test | FAIL—VERIFIED—ISOLATED TEST | Two expected-ownership assertions fail against the actual handler body and a fake collection that evaluates the generated Mongo-style query. |
| Test failures reported honestly | PASS | 9 passed, 2 failed, 0 skipped; the two failures are retained and are not rewritten to match current behavior. |
| Authorized-context contract proposed | PASS—PROPOSAL | See `CATALOG_HISTORY_CONTRACT.md`; it is not implemented. |
| No recommendation UI/API/service or provider calls added | PASS | Only the two test files and three requested documents were created. |
| No data/runtime/dependency/production-source changes | PASS | No database, seed, external service, or AI provider was accessed. |

### Ownership result

The isolated tests cover:

- User A can see A's private plan: PASS.
- User A cannot see B's private plan without a muscle filter: PASS.
- A muscle filter matching B's private plan does not expose it: **FAIL**.
- A muscle filter is intersected with A's ownership and excludes A's nonmatching plan: **FAIL**.

At `backend/routers/workout.py:274-282`, the handler puts email ownership, user-ID ownership, and both muscle alternatives into the same `$or`. Consequently, any document matching a muscle branch satisfies the query without matching either owner branch; and a matching owner branch bypasses the muscle filter. The proposed minimal correction is an owner `$or` ANDed with a muscle `$or`, retaining the existing top-level difficulty predicate. No route change was made.

The route reads `custom_plans` and its create path stores the authenticated email and `user_id`. No shared, system, or public visibility field or policy was found in this route. Those visibility rules remain **UNVERIFIED** and are intentionally not invented or asserted by the tests.

### Verification

Command:

```text
python -m unittest discover -s backend\tests -p "test_ai01_*.py" -v
```

Result: **exit code 1; 11 tests run; 9 passed, 2 failed, 0 skipped.** The failures are the two expected ownership failures described above.

The tests load only the current handler/helper function bodies from source and run them with in-memory fakes. The fake plan collection evaluates the query expression produced by the handler, including `$or` and array membership; it does not return preselected expected results. No backend module was imported. Importing the normal application modules is unsafe for this isolated task because `backend/app/database.py` calls `load_dotenv()`, creates a `MongoClient`, and pings MongoDB at import time. The available Python 3.11.9 environment also has no FastAPI, PyMongo, or BSON package. Therefore these are isolated source-function tests, **not** HTTP, database, or runtime E2E tests; the injected email represents the identity returned by the existing token dependency, whose JWT path was not exercised.

No existing test suite was run: relevant existing tests import the application/database modules, and this environment lacks their runtime dependencies. No full suite, build, analyzer, API call, or app startup was run.

## Files created by this checkpoint

- `backend/tests/test_ai01_plan_query_ownership.py`
- `backend/tests/test_ai01_catalog_history_contract.py`
- `docs/ai_coach/CP-AI-01/REPORT.md`
- `docs/ai_coach/CP-AI-01/CATALOG_HISTORY_CONTRACT.md`
- `docs/ai_coach/CP-AI-01/CP_AI_02_PROPOSAL.md`

No concurrent change to an allowed output file was present at preflight. The initial default status collapsed untracked directories, so a path-for-path comparison with the supplied 918-item reference is unavailable; the two-item untracked-count difference remains unattributed.

## Completion

- **Root cause (ownership):** the `$or` at `backend/routers/workout.py:274` is extended with muscle predicates at lines 281-282 rather than applying a separate muscle predicate under `$and`.
- **Pre-existing issues:** the ownership query defect is in the pre-existing source and is reproduced by the new isolated tests.
- **Regressions introduced:** no production-source, API, dependency, or tracked-WIP changes. The test command exits nonzero because it faithfully exposes the existing defect.
- **Scope:** all five created files are among the explicitly allowed paths.
- **Merge/commit:** none.
- **Recommendation implementation readiness:** NOT READY; catalog equivalence and history normalization are missing, and the ownership defect remains unfixed.
