# CP-AI-07 — Flutter Web acceptance for workout recommendations

## Status

**PASS — required local Flutter Web acceptance cases completed.** Standard
login, isolated MongoDB, A/B separation, the read-only mixed request, and the
main UI scenarios have runtime evidence. This result is limited to the local
test stack; it is not a production or deployment-packaging claim.

## Workspace and preservation

| Check | Result |
|---|---|
| Workspace | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` |
| Branch / HEAD | `agent/nutrition-active-localhost-f02` / `10be1ab1971214acd2487ef893df3fcc80212fc9` |
| Existing worktree status | 231 entries; preserved |
| App source | Unchanged |
| Git operations | No commit, push, merge, reset, clean, stash, or checkout |

Only this report and test harness/fixture/evidence files under the approved
CP-AI-07 runtime evidence directory were written. The retained test database
and all evidence remain in place.

## Runtime and fingerprints

| Component | Runtime |
|---|---|
| MongoDB test instance | MongoDB 7.0.14; loopback port 27049; PID 14032 at final verification |
| Test database | `saman_cpai07_20261103t052553z` |
| Backend | Loopback port 18099; PID 4940 at final verification; bound to the test database |
| Flutter Web | Retained release build served on loopback ports 8086 and 8087; listener PIDs 4364 and 9208 |
| Browser | Headed Microsoft Edge 156.0.4314.50 via Playwright; three separate browser contexts |
| Toolchain | Flutter 3.22.0; Dart 3.4.0; Python 3.11.9 |
| Fixture timezone/date | `Asia/Ho_Chi_Minh`; fixture date 2026-11-03; A's target session is 2026-11-02 |

The app's compiled `main.dart.js` points at `http://127.0.0.1:18099`.
Runtime SHA-256 fingerprints were unchanged from the prior CP-AI-07 report:

| Runtime input | SHA-256 |
|---|---|
| `backend/routers/chat.py` | `2AB7DBF23E2B0DAC0AD89970087BDE5A20682C68469B1538F38C272530488F36` |
| `backend/app/services/workout_recommendation.py` | `090C18EA166D745034F6041475D3A0D0CE08566D472212940C95AF2C4CFB04F7` |
| `backend/app/services/exercise_catalog_resolver.py` | `92107F79CDD92FA1B2CE71A5336A315173CB3A18755EA0783E0EB0E5C8DF6075` |
| `backend/app/data/ai_exercise_catalog.generated.json` | `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33` |
| Retained Flutter Web `main.dart.js` | `69EACACF34919B94358B03406D6544B8A1118E44180E2F72995D3566742491AD` |

## Fixture and UI/backend results

The isolated database contains three synthetic accounts and seven workout
history records: A has six, B has one, and C has none. The suite reset only
these synthetic accounts to a random in-memory test password; credentials,
tokens, and authorization headers were not saved or logged. Each Chat case
was entered in the UI and produced exactly one `POST /api/chat` with HTTP 200.
The three normal UI logins each returned HTTP 200.

The final acceptance run is
`D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-07\run-20261103T105300Z\attempt-10`.
Its sanitized `case-results.jsonl`, `network-summary.json`, and
`db-final-summary.json` contain the structured evidence.

| Case | Expected | Actual | Result and UI evidence |
|---|---|---|---|
| A — chest top five | Five unique chest exercises in A's backend order, with history/muscle reasons | Barbell Bench Press; Dumbbell Bench Press; Push-Up; Cable Chest Fly; Incline Barbell Bench Press. One POST, HTTP 200, no action | **PASS** — `a-chest-top5.png`; case checks and order in `case-results.jsonl` |
| A — supported filter | Ab Wheel + Abs filter yields only its one valid candidate | Exactly Ab Wheel Rollout; filter acknowledgements shown; one POST, HTTP 200, no action | **PASS** — `a-ab-wheel-filter.png`; case checks in `case-results.jsonl` |
| C — cold start | No-history wording, without implying personalized history | UI says no matching readable history and that the list is not personalized by history; five general catalog results; one POST, HTTP 200 | **PASS** — `c-cold-start.png`; case checks in `case-results.jsonl` |
| A — yesterday history | Correct A session for yesterday in app timezone; no B data; no recommendation routing | Retrieval metadata: `grounded=true`, `query_type=SPECIFIC_DATE`, `sessions_found=1`; reply contains “CP-AI-07 Fixture A Yesterday” and “Cable Chest Fly”; one POST, HTTP 200, no action | **PASS for fixture/session identity** — `a-yesterday-history.png`; local deterministic stub limitation below |
| A — recommend and save-plan request | Read-only response; no workout plan, workout history/session, or profile write | `action=null`; profile hash unchanged; workout history remains seven records with identical hash; custom workout plans remain zero; conversation count unchanged and embedded conversation messages increase by two | **PASS** — `a-mixed-read-only.png`; before/after in `db-final-summary.json` |
| B — chest top five and isolation | B-specific ranking; no A history or conversation leakage | Cable Chest Fly; Dumbbell Bench Press; Incline Barbell Bench Press; Incline Dumbbell Flyes; Incline Dumbbell Press. B logged in through a separate context and has one owned conversation; A and C each have one | **PASS** — `b-chest-top5-isolation.png`; case and owner counts in the JSON evidence |

Recommendation names were mapped to the expected generated-catalog IDs in the
acceptance harness. The previously passing focused
`flutter test test/workout_exercise_catalog_test.dart` (77 tests) and CP-AI-06
chat suite (10 tests) were reused because all relevant source fingerprints
match. The test suite validates catalog/library identity; the Workout Library
screen itself was not opened for a separate visual comparison.

Conversation messages are stored inside each `conversations` document; the
separate `messages` collection remains empty by design. The mixed-request
before/after check therefore counts embedded messages and confirms the two
conversation messages are separate from workout-plan/profile/history writes.

## Provider boundary and unverified cases

The local backend ran with fake-provider mode and no external AI-provider keys.
The local history stub was invoked once for each successful history question
(three times across the successful resume runs); the recommendation requests
did not increase its count. The stub audit contains only fixture-presence
booleans and prompt length. The history answer used correct fixture/session
and exercise names, but its Vietnamese sentence contains literal `?` in place
of some accented characters due to the test stub's text encoding. Natural
language quality against a live provider is therefore **UNVERIFIED**; no
application source change was made.

The browser also requested ancillary UI/auth/payment asset hosts
(`gstatic`, Google accounts, jsDelivr, and Stripe). No AI-provider endpoint
request was observed, and no AI-provider key was configured; this was not a
blanket outbound-network denial.

| Check | Status |
|---|---|
| Runtime history-read failure distinct from empty history | **UNVERIFIED** — no permitted isolated read-failure injector was available |
| Natural-language answer quality from a live AI provider | **UNVERIFIED** — history used the local deterministic stub |
| Production/deployment packaging | **OUT OF SCOPE / UNVERIFIED** |

## Verification and process disposition

The resumed Edge run completed six UI Chat submissions and three standard
login flows with zero browser page errors. Source-related CP-AI-06 and catalog
tests were reused rather than rerun because their recorded fingerprints
matched the running app. No app build or test regression was introduced.

At final verification the checkpoint-owned listeners were MongoDB PID 14032
(27049), backend PID 4940 (18099), and Flutter Web PIDs 4364 (8086) and 9208
(8087). These processes were stopped after evidence capture; the test
database and evidence were retained. No production service was accessed.
The stopped-process and port verification is retained in
`attempt-10/process-shutdown.log`.

**Conclusion:** the specified local Flutter Web cases, real UI authentication,
isolated MongoDB, A/B account separation, and no-workout-plan-write check have
runtime evidence. The report does not extend those results to production,
deployment packaging, read-failure injection, or live-provider wording.
