# JCOM-05-09 — Workout & Meal Attachment Snapshots

## Task Completion Report

- **Status**: **PASS for local/test JCOM-05-09**. Both attachment kinds completed the main-app UI/HTTP/Mongo acceptance on final source. Stop at this checkpoint.
- **Authority**: User's GO and subsequent full “Workout & Meal Attachment Snapshots” prompt replace the linked GitHub Issue only for JCOM-05-09. No unresolved product decision remains. Exact paths were added to `JCOM0509_SCOPE.md` before edits/run creation.
- **Branch/HEAD**: `agent/nutrition-active-localhost-f02` / `10be1ab1971214acd2487ef893df3fcc80212fc9`, verified before edits and handoff. WIP retained; no reset/clean/stash.
- **Summary**: Added read-only canonical owned-source adapters and strict field projections, selected-preview fingerprints, durable stored snapshots using the existing publication key/index, remote R07 selection/review/error/retry, full R06D and Feed/R05 snapshot rendering, field/audience draft recovery and account isolation. Source changes before a new post require review; retries of saved operations return frozen snapshots without re-reading the edited source. Original Workout/Nutrition APIs/storage logic are untouched.

## Source and field allowlist

Read paths surveyed: Workout `/sessions` and its existing history repository store canonical `workout_history` documents owned by authenticated `user_id`; Nutrition `/logs/{date}` and its repository read `nutrition_plans` owned by canonical `user_email`. The Community adapter resolves the current canonical database user, then applies those same ownership keys. Unfinished/deleted/foreign workouts are excluded. No source mutation in application code; test fixtures are separate and explicit.

The approved R07 controls are the basis, together with the existing R07 fake preview examples (duration, exercise names, aggregate load/set summary, food names and totals). The schema is not copied from private source models. Full matrix and request contract: `JCOM0509_CONTRACT.md`.

| Shared snapshot field | Actual source | Default | R07/R06D/Feed/R05 |
| --- | --- | --- | --- |
| kind/title/date/category | workout plan_name/date; meal_type/date; static category | Included after explicit attach | Same canonical metadata in preview/card |
| duration_minutes | Workout total_duration_minutes/duration_minutes | ON workout | Selected minutes only |
| exercises / exercise_count | Completed exercise_logs; existing public catalog name or slug display fallback | ON | Names/count only; no internal IDs/per-set records |
| foods | Meal foods[].name | ON | Names only; no quantities/food IDs/nested macros |
| set_count / load_kg | Completed log count / canonical total_volume_kg | **OFF** | Explicit sensitive opt-in; aggregate only |
| calories/protein_grams/carbs_grams/fat_grams | Canonical Nutrition total_* | **OFF** | Explicit sensitive opt-in; totals only |
| Meal duration | No source field | OFF, disabled | Explicitly explained as unavailable; never invented |

Notes, email/user/source/plan/food/exercise IDs, CV/rest information, images, quantities and other private fields are not shareable. Images/uploads and Q&A attachments remain excluded. Workout set count follows the sensitive switch, not the exercise-list switch. Every off metric/list is absent from the saved post and response, including nested objects; no null/zero placeholder reconstructs it.

## Behavior and security contract

Private owner-only source list/preview endpoints return selected projections with source reference and preview hash for R07. A strict publication alternative on existing POST `/api/community/posts` accepts typeworkout/meal, caption/audience/topic/comments and only source reference, choices and preview hash. Unknown/extra fields or unsupported choices reject. Missing/foreign sources404 do not expose content.

Backend reconstructs the selected whitelist projection and hashes source identity plus visible content. A changed **shared** projection rejects409 before insertion, keeping editable draft for fresh preview/explicit Share. Hidden-only source edits need no review. Existing same-key records are checked first: after current account/audience/publication guards, matching normalized payload returns the saved post/snapshot even when the source changed/deleted; changed payload conflicts409. Existing partial unique `(user_id,request_key)` index gives durable atomic deduplication on standalone Mongo; no transaction/TTL/startup migration.

Stored snapshot is separate from source data. Feed/detail/replay project that stored snapshot through the public whitelist and never join the source again. Public response contains no internal origin reference, preview hash or operation key; those stay only in the internal operation payload. Text/Q&A contracts remain supported.

R07 has loading/empty/error/retry and live selected preview. Meal duration is off/disabled with an explanation. R06D shows every included field and selected audience before explicit Share. Removing attachment keeps caption and emits no request. Unknown outcomes freeze caption/snapshot/choices/audience/key; retries keep the same operation, including after later rejection. Account change clears visible source lists, preview and composer; generation guards discard late responses. Remote flow never falls back to fake data or fake publish.

## Files modified

- `backend/app/models/community.py`
- `backend/routers/community.py`
- `backend/app/services/community_attachment_service.py`
- `backend/scripts/setup_community_attachment_indexes.py`
- `backend/tests/test_community_attachment_snapshots_mongo.py`
- `frontend/lib/features/community/domain/models/post_attachment_snapshot.dart`
- `frontend/lib/features/community/domain/models/community_post.dart`
- `frontend/lib/features/community/domain/repositories/community_repository.dart`
- `frontend/lib/features/community/data/datasources/community_remote_datasource.dart`
- `frontend/lib/features/community/data/repositories/community_repository_impl.dart`
- `frontend/lib/features/community/presentation/providers/community_composer_provider.dart`
- `frontend/lib/features/community/presentation/providers/community_providers.dart`
- `frontend/lib/features/community/presentation/screens/compose/community_select_attachment_screen.dart`
- `frontend/lib/features/community/presentation/screens/compose/post_compose_publish_screen.dart`
- `frontend/lib/features/community/presentation/widgets/create_content_bottom_sheet.dart`
- `frontend/lib/features/community/presentation/widgets/community_activity_snapshot_card.dart`
- `frontend/lib/features/community/presentation/widgets/post_card_view.dart`
- `frontend/lib/features/community/presentation/screens/community_post_detail_screen.dart`
- `frontend/lib/config/app_translations.dart`
- `frontend/test/features/community/community_attachment_snapshots_test.dart`
- `frontend/test/features/community/community_publish_test.dart`
- `frontend/test/features/community/community_remote_read_test.dart`
- `frontend/test/features/community/community_follow_test.dart`
- `frontend/test/features/community/community_interactions_test.dart`
- `frontend/test/features/community/community_timeout_reconciliation_test.dart`

Documentation/evidence: this directory's scope/contract/baseline/verification/source review/report; `docs/CONTINUOUS_RUN_STATUS.md`; `runtime_evidence/jcom0509_attachments/run_attachment_runtime.py`; exact immutable run/build/provenance directories and own Mongo data path listed in scope. The four existing remote test mocks implement the added source-read boundary explicitly; their assertions remain. Generated builds/bytecode are tool output, not manually edited source.

## Acceptance criteria and evidence

- [x] Workout R07 → R06D → real Share → canonical Feed/R05 → reload: **PASS**.
- [x] Meal same flow with private audience and canonical snapshot: **PASS**.
- [x] Preview/UI/HTTP/DB agree on selected snapshot; disabled fields are absent, including nested source metadata: **PASS**, backend tests + actual runtime + independent DB audit.
- [x] B's main-app Feed shows public workout and excludes private meal; B's R07 lists no A sources: **PASS**.
- [x] Actual authenticated negative HTTP: B cannot preview or attach either A source; private meal GET404 with only detail; B creates0 posts: **PASS**. Negative API probes are explicitly separate from successful UI publication.
- [x] Both kinds: real server persist200 → injected browser-response loss → synthetic source changed → real UI retry same key → same ID and original snapshot, exactly1 post per kind: **PASS**.
- [x] New post from stale shared preview409/no insert; hidden-only edit allowed; changed payload conflict; concurrent requests/fresh-connection persistence; current publication/audience denial before replay: **PASS** real Mongo tests.
- [x] Draft/key freezing, review error without auto-submit, removal preserving caption, source-preview/account guards, visible R07 account isolation/error/retry: **PASS** frontend tests.
- [x] Shared text/Q&A publish and compose regressions, scoped analyze/syntax/release build: **PASS**. Existing JCOM0508 evidence retained, no old browser acceptance rerun.

## Exact final run / HTTP / database

`runtime_evidence/jcom0509_attachments/runs/ui_20261103T135359Z_988e52/runtime.json`: **PASS**,0 page errors. Main entrypoint `lib/main.dart`, existing remote Journal/Community flags, actual form login/profile gate and native keyboard caption input. No session injection or preview entrypoint. Screenshots for each kind01–06 cover R07, R06D preview, unknown outcome, canonical Feed/R05 and reload; B01–02 show audience/source isolation.

| Kind | Canonical post ID | Final selected snapshot | Own-actor DB count |
| --- | --- | --- | --- |
| Workout | `6ae9e79178752d0357e5f960` | Metadata +41 minutes; exercise list/count, set/load absent |1|
| Meal | `6ae9e7a578752d0357e5f961` | Metadata +original Rice name; calories/macros/quantity/IDs absent |1|

For workout the fixture changed canonical duration41→99 and title after persist; retry/render/reload still show41 and the original title. Meal source title/foods changed after persist; retry/render/reload still show original title/Rice. Final actor A has2 posts/2 distinct keys, B0. Post-run Mongo audit verifies both stored snapshots equal canonical HTTP results and all disabled/private fields are absent from the entire post document (internal reference/options/hash are retained only for idempotency).

**Real HTTP vs injection**: Playwright route.fetch sends a real POST and obtains actual canonical server200 after the backend Mongo insert. route.abort deliberately removes browser delivery; after explicit isolated source edits, clicking Share retries using the original key. This is controlled response-loss injection, not a naturally observed packet-loss claim. Source/users/profile/follow-free fixtures are synthetic records in the verified independent database. The separate B negative probes use a real HTTP login for that synthetic B, without injecting any session into the app. Credentials/tokens/authorization headers and request bodies are not recorded.

## Verification actually executed

See `verification.txt` for exact commands and intermediate corrections.

- Before edits existing publication+compose files: **29 PASS**. After shared integration: **29 PASS** again. Old unsupported-attachment expectation became the newly authorized R07/no-auto-publish expectation; unsupported media is still rejected.
- New backend standalone Mongo module: **6 PASS**. Combined new module + unchanged existing publication module: **PASS** (6 attachment +10 text/Q&A cases), after strict query selection validation. Both-kind concurrency and fresh-connection checks use real storage, no skip/mock persistence or database cleanup.
- New frontend attachment module: initial verified account-isolation regression failed, then **5 PASS** after its fix. Added removal case produced final **6 PASS**. Subsequent affected Retry contrast/account widget **1 PASS** and canonical snapshot/omission mapping **1 PASS** separately. No invented combined result.
- Shared late-account/visible text draft checks: **2 PASS** after identity integration.
- Final scoped Community analyzer: **0 errors,0 warnings**,2 inherited const infos in remote-read test. Backend compileall: **PASS**.
- Main-entrypoint initial release build **95.4s PASS**. One own intermediate build was interrupted before completion to include verified Retry contrast correction; its directory is explicitly ABORTED, never PASS. Final unique clearing build **97.4s PASS**. No dependencies installed and no old build overwritten.
- Initial functional browser run `ui_20261103T134231Z_1becbc`:PASS, retained. Final source/visibility clearing `ui_20261103T135359Z_988e52`:PASS. Final read-only source/build/harness/DB/scope/branch/process audit:PASS.

**Baseline observed**: Broad inherited tracked/untracked WIP, Pydantic/JWT configuration warnings, unrelated shop import warning, imported global MongoClient ResourceWarning,2 inherited analyzer infos and inherited translations EOF blank line. These were not hidden or repaired outside scope.

**Regressions introduced**:0 new compile errors,0 analyzer warnings,0 remaining executed test failures. A new test initially had an extra parenthesis; corrected. A widget fixture initially awaited Dio outside fake-clock pumping and stalled; only that own run was interrupted, fixture setup corrected without skipping assertions. No failing tests disabled or security expectations weakened.

## Verified root causes and targeted fixes

- **FACT/OBSERVATION**: Focused R07 widget test kept2 visible A activity titles after account reset. Composer invalidation alone did not clear the screen's local list/preview. **TEST/CONCLUSION**: An explicit existing-session identity revision triggers clear/reload; local request generation and repository generation reject stale results. The same account-isolation assertion then passed. No auth/Profile changes.
- Source inspection found legacy snapshot sanitize grouped setCount with exercises even though the approved sensitive toggle groups sets with load. It now respects that switch. Real backend default/off-field tests and runtime absence checks pass; no historical live-data leak is claimed.
- Runtime inspection verified inherited white-filled caption/white text and low-visibility remove/status controls in R06D. Local decoration/text-token changes make caption, pending message and remove action readable; no theme edit. Focused R07 Retry check observed low foreground luminance0.113; explicit token fixes it, with final contrast≥4.5 test. Unsupported meal duration has an explicit localized explanation.

These are small integration fixes, not a source-feature rewrite. No internal Workout/Nutrition models were used as an implicit share allowlist.

## Source/build attribution

- Final manifest: `runtime_evidence/jcom0509_attachments/runs/clearing_20261103T135056Z_599c43/server.json`.
- Backend provenance: `runtime_evidence/jcom0509_attachments/runs/server_20261103T133125Z_501574/source_before_start.json`, process/native-cwd/startup logs and server manifest. Backend files were hashed **before launch**, mtimes precede actual process start, current hashes match and live OpenAPI includes the strict attachment request. No health200-only version inference.
- Final source fingerprint: `a15981b97ea8c157f65814bf10e7e934a9cc1da4d23084af4506ce514d03be3e`.
- Final main.dart.js SHA256: `298e8d6def095b16b16a474f44081a42804507c54e39aa7f0d2b7593acddd4a9`.
- OpenAPI SHA256: `385fd07eb092d94db04ad017679014a5b75e4ceb9d46b0ee062176cdf6a0d942`.
- Executed immutable harness snapshot `runtime_evidence/jcom0509_attachments/runs/ui_20261103T135359Z_988e52/harness.py`, SHA256 `7bb16b920ccadf5a96b98f869dc5233f707b1f758e8582fca0c6898eb2411e69`; current script matches.

No previous JCOM0508 JSON/screenshots/harness/build/baseline files were edited. Legacy approved screenshot assets were inspected; their glyph capture limitation is not used to invent field semantics. Text labels/defaults in the approved R07 source and existing preview examples establish the field basis.

## Runtime ownership / scope / handoff

Fresh handoff: own Mongo **16980/parent2284** on127.0.0.1:27048; own backend **15280/launcher17272**, launcher parent16620, on127.0.0.1:18099. Commands/native workspace/start/source/DB were verified; no old PID was used for management. Prior JCOM0508 listeners were absent before a new Mongo was started on the freshly free port with a **new** data directory. Only `saman_jcom0509_test_runtime_72af2812abea` and independent test-prefixed databases were written.

Mongo data path `D:/SamanDev/runtime/jcom0509/server_20261103T133125Z_501574/mongo`, backend/Mongo and synthetic data are retained/running. Browser harness Chrome and its temporary IPv4 static3000 close at exit. Unrelated IPv6 localhost3000 Flutter **PID1348**, targeting backend8000, remains untouched. Own interrupted test/build processes were verified no longer running; backend/Mongo were not restarted or stopped. No approval-review rejection/blocker occurred and no workaround was attempted.

**Known limitations**:PASS is scoped to local/test attachments and the executed450×850 main-app browser scenario. The source list is the latest20 owned records; old Workout records without canonical user_id/completion are not exposed. Meal duration is unavailable. Uploads, Q&A attachments, source-log editing, production moderation, persistent drafts, notifications and broad performance/responsive certification remain excluded.

**Scope confirmation**: All session edits are in the exact allowlist; input identities in baseline.json, final review in source_review.json. Inherited untracked Community WIP means git diff alone is not an input-to-output patch; focused review/hashes supplement it. No AGENTS/auth/Profile/Workout/Nutrition/Journal/dependency/global-theme implementation edits, shared/live/remote DB writes or unrelated runtime management.

**Merge confirmation**: No PR, commit, push, merge, deploy or release. Changes remain local. Stop at **JCOM-05-09 PASS**.
