# CP-AI-05 — Authorized Context & Baseline Workout Ranking

## Status

**PASS — local rule-based baseline and isolated tests.** This checkpoint adds
an internal read-only service only. It does not wire the service into Chat,
call an AI provider, or change the UI.

## Identity, scope, and preservation

- Workspace: `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840`
- Branch: `agent/nutrition-active-localhost-f02`
- HEAD: `10be1ab1971214acd2487ef893df3fcc80212fc9`
- Initial Git status: 228 status entries, including unrelated tracked/untracked
  WIP. The existing resolver source was itself untracked CP-AI-04 WIP; its
  contents were preserved and only the authorized catalog-list method was
  added. Final status: 230 entries; the two new backend files account for the
  added status lines, while the new docs are under the pre-existing untracked
  `docs/ai_coach/` directory. No initial status entries disappeared.
- No Context File was found. `AGENTS.md` and the CP-AI-04 handoff were read.
- The initial CP-AI-04 resolver/history baseline passed 23 tests.
- The first implementation test run found two test-fixture assumptions
  (canonical ID versus slug, and a fake resolver accepting a synthetic ID).
  The fixtures were corrected; no production defect or prior test failure
  remained.

The original allowlist was extended only after explicit authorization to add
`backend/app/services/exercise_catalog_resolver.py` for its missing
read-only catalog enumeration API. All other changes are within the original
allowlist. No route, schema, catalog artifact, seed, dependency, UI, or other
feature area was changed.

## Files changed

- `backend/app/services/workout_recommendation.py`
- `backend/app/services/exercise_catalog_resolver.py` (authorized extension:
  defensive-copy `list_exercises()`)
- `backend/tests/test_ai05_workout_recommendation.py`
- `docs/ai_coach/CP-AI-05/REPORT.md`
- `docs/ai_coach/CP-AI-05/BASELINE_CONTRACT.md`
- `docs/ai_coach/CP-AI-05/CP_AI_06_PROPOSAL.md`

Root cause: N/A (new internal capability).

## Implementation

- Context is loaded only from an authenticated principal supplied by the
  trusted caller. The service derives the profile lookup email and history
  owner ID from that principal; it accepts no client-supplied owner, profile,
  or history object.
- Profile and history reads, CP-AI-03/04 exercise normalization, and timestamp
  normalization are injected dependencies. No router import, DB connection,
  write, or AI provider is used by this service.
- Profile/history ownership is checked before use. A profile identity
  mismatch is unavailable; history rows for another owner are excluded.
- The validated generated-catalog resolver is now the sole candidate source.
  Its listing method returns defensive copies from the resolver's validated
  records; the service re-resolves IDs before scoring.
- Explicit muscle and available-equipment filters fail closed when required
  candidate metadata is missing. The deterministic score is documented in
  `BASELINE_CONTRACT.md`; output is capped at five unique canonical IDs.
- Persisted activity level and goal are preserved with field provenance but
  are not scoring signals. Workout experience, equipment access, injuries,
  and schedule remain unknown because they are not in the persisted profile
  contract.

## Verification

Interpreter: `D:\SamanDev\runtime\saman-cp7-python\Scripts\python.exe`,
Python 3.11.9. No dependencies were installed.

| Command | Exit | Result |
|---|---:|---|
| Baseline: `python -B -m unittest backend.tests.test_ai04_catalog_resolver backend.tests.test_ai03_workout_history_context -v` | 0 | 23 passed before changes. |
| `D:\SamanDev\runtime\saman-cp7-python\Scripts\python.exe -B -m unittest backend.tests.test_ai05_workout_recommendation backend.tests.test_ai04_catalog_resolver backend.tests.test_ai03_workout_history_context backend.tests.test_ai01_catalog_history_contract` | 0 | 48 passed, 0 failed, 0 skipped. |
| Focused AST parse for the service, resolver, and CP-AI-05 test | 0 | 3 Python files parsed. |
| UTF-8 trailing-whitespace/final-newline check on the six changed files | 0 | Passed. |
| `git diff --check -- backend/app/services/exercise_catalog_resolver.py` | 0 | Passed. |

These are isolated unit tests with synthetic readers and fixtures. The history
tests reuse the existing CP-AI-03 normalization helper through its AST-based
test harness. There was no HTTP in-process test, real token-auth test, live
Mongo test, provider call, or deployed-runtime check. Chat grounding was not
rerun because no route/call path was changed.

## Acceptance

- [x] Context derives owner selectors from the trusted principal and keeps
  missing, empty, read-error, and ownership-mismatch states distinguishable.
- [x] Deterministic baseline returns at most five unique canonical Library IDs.
- [x] Reasons and score components trace to explicit request/history signals;
  unsupported or missing profile fields remain unused/unknown.
- [x] Tests cover owner isolation, identity resolution, filters, ranking,
  catalog failure, and empty/fewer-than-five/more-than-five candidates.
- [x] Changed files are in the approved paths, including the explicitly
  authorized resolver addition. Existing WIP was preserved.

## Unverified and limitations

- The service is intentionally not connected to Chat, authentication routes,
  an AI provider, or UI in CP-AI-05.
- Test readers exercise owner selection and service filtering; no real Mongo
  query or real bearer token was exercised.
- No deployment packaging/runtime check was made.
- The CP-AI-04 handoff's live Mongo, real-token, and packaging limitations
  remain unchanged.
- The existing history reader may return an unbounded result set; the
  recommendation service only uses records in its 90-day window. Any future
  route integration should use an appropriately bounded read.
- No offline relevance experiment was run. The report makes no quality,
  training, or AI-model claim.

**Scope confirmation:** only the listed files were changed; the one resolver
path was explicitly authorized after the missing-interface blocker was
reported. **Merge confirmation:** no commit, push, merge, reset, clean, stash,
or checkout was performed.
