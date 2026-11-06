# JCOM-05-07 — Persistent Q&A Answers & Helpful Votes

## Task Completion Report

- **Status**: PASS for Q&A Answers/Helpful Votes verified on local/test. Stop at JCOM-05-07. This does not declare all Community production-ready.
- **Authority**: Direct attached takeover prompt specifically replaces the linked Issue requirement and permits scope/branch from inspection. AGENTS.md unchanged. Branch `agent/nutrition-active-localhost-f02`, HEAD `10be1ab1971214acd2487ef893df3fcc80212fc9` verified; extensive inherited WIP preserved.
- **Summary**: Added canonical persisted answers, durable replay/conflict/concurrency protection, desired-state helpful/unhelpful, authoritative counts and stable pagination. Wired existing remote datasource/repository/providers to R15 and Q&A Feed count. Added session draft/key recovery, vote reconciliation, current-audience enforcement, account isolation, stable composer and EN/VI states, preserving the established screen design.
- **Scope / baseline**: Exact paths in JCOM0507_SCOPE.md; before-task hashes/git status in baseline.json. Shared Community sources were inherited untracked WIP; translations and unrelated modules already had tracked modifications. No reset/clean/stash or recreation from base. Existing Comments runtime acceptance was not repeated.
- **Contracts / permission / recovery**: JCOM0507_CONTRACT.md.

## Source and test changes

- Backend: `backend/app/models/community.py`, `backend/routers/community.py`, new explicit test-only `backend/scripts/setup_community_answer_indexes.py`, new real-Mongo `backend/tests/test_community_answers_mongo.py`.
- Domain: `question_answer.dart`, `community_post.dart`, `community_repository.dart` under `frontend/lib/features/community/domain/`.
- Integration: existing `community_remote_datasource.dart`, `community_repository_impl.dart`, `community_providers.dart`.
- UI: existing `presentation/screens/qa/community_question_detail_screen.dart`, new named `presentation/widgets/community_answer_composer.dart`; localization `frontend/lib/config/app_translations.dart`. R03 consumes the updated existing qaInfo projection; no Feed visual redesign.
- Tests: new `frontend/test/features/community/community_answers_test.dart`; existing remote mock contracts updated in `community_remote_read_test.dart`, `community_follow_test.dart`, `community_interactions_test.dart`, `community_timeout_reconciliation_test.dart`. Existing assertions retained. The R15 remote-read fixture now provides the canonical question required by the remote screen.
- Docs/evidence: exact scope/contract/report/baseline/verification/source_review, continuous status, new JCOM0507 harness and unique server/browser directories. Previous checkpoint evidence untouched.

## Verified findings and targeted corrections

**FACT / OBSERVATION**: R15 previously read answers remotely, but remote send/vote were explicitly unsupported. The old answer endpoint combined pinned/vote ranking with a chronological cursor comparison that did not match that order. New persistence requires a consistent chronological stream and authoritative record counts; no surrounding refactor was performed.

**TEST / CONCLUSION — publication boundary**: Reusing the Comments audience helper also inherited its legacy allowance for status=None. Q&A explicitly requires published. A targeted real-Mongo regression expecting404 for status=None failed on the initial implementation (200 !=404), then passed after a single Q&A-specific condition required `status == published`. Comments behavior stayed unchanged. Only that affected test was rerun after this backend refinement.

**OBSERVATION / CONCLUSION — runtime automation**: First browser run `ui_20261102T152421Z_a07bf0` reached canonical answer, reload/count and real lost-response retry, then timed out before any B vote request. Flutter exposed Mark helpful as a tooltip label on a role-less semantics wrapper. The harness's button-name locator was wrong. Measured label geometry (56x32) supplied the actual click target; the corrected label locator produced real PUT/DELETE and a complete clearing run. This was a harness defect, not evidence of a failed application vote. The first run and screenshots remain intact.

**Frontend checks**: New tests initially had a missing loadPosts argument and a widget-test await that needed pumping the controlled asynchronous transport. These harness/test mistakes were corrected without weakening assertions. The legacy fake R15 initialPost preview was preserved, while remote R15 uses only its fetched canonical question. Pending/error insertion retains the same EditableTextState/controller; a real existing TextInput client accepts further text without reconnection after an error row is inserted. No speculative application workaround or auth change.

## Acceptance criteria

- [x] Auth, trim/length/extra-field validation, canonical author and Q&A-only explicitly published resource.
- [x] Durable same-key replay/conflict and concurrent retries create one answer on real standalone Mongo; fresh connection confirms persistence.
- [x] Public/private/followers_only, deletion/unpublished/unknown audience and current-user revocation checks, including read/send/replay/vote; safe public author projection.
- [x] Desired-state helpful/unhelpful and viewer+answer uniqueness, repeat/concurrent requests, authoritative counts, stable timestamp/ID pagination under changing votes.
- [x] Self-vote remains disabled (403); helpful does not select best answer or create notifications.
- [x] Answer count synchronized across R15/Feed; stale Feed reads cannot reduce a confirmed session count. No cached DB counter writes.
- [x] Unknown answer outcomes retain content/key, same-key retry merges canonical ID; vote timeout resolves from the canonical server; no remote fake fallback.
- [x] Late A answer/vote responses cannot update B; visible draft clears on account switch. Stable composer/controller/editor across pending/error changes.
- [x] Main app Login A -> Home -> Journal -> Community -> Q&A -> R15, actual keyboard answer, reload/persistence/count.
- [x] Independent B projection, vote/unvote/reload persistence and controlled response-loss reconciliation.
- [x] Runtime revoked read/replay/vote all404 with only detail; UI hides question/answers/count; no duplicate on replay.

## Commands and actual evidence

1. Before editing, `flutter test --no-pub test/features/community/community_flow_test.dart test/features/community/community_remote_read_test.dart`: **19 PASS**. Existing backend read baseline: **11 PASS**. No dependency resolution/install.
2. Initial new real-Mongo module: **8 PASS**. Subsequent read+answers combined run with explicit isolated MONGO_URI/DB_NAME: **19 PASS**. An earlier combined invocation omitted that environment before imports and returned503 in the old mocked read test; it was an invalid test environment, not fixed by changing application availability rules. Raw evidence retained in verification_backend.log.
3. Publication refinement: `python -X utf8 -m unittest backend.tests.test_community_answers_mongo.AnswersMongoTest.test_deleted_unpublished_unknown_audience_and_identity -q`: expected pre-fix **1 FAIL**, final **1 PASS**, now includes status=None. The19-test run predates this one-line refinement; no invented final aggregate count.
4. Focused frontend clearing command using `community_answers_test.dart` and the existing R15 case in `community_features_test.dart`, with `--name 'canonical answer|persisted timeout|helpful timeout|pagination merges|late answer|late vote|pending and error|R15 CommunityQuestionDetailScreen'`: **8 PASS** (7 new +1 existing R15). Prior remote-read file and other existing features cases passed in the combined attempt; the initially failed legacy R15 case was the one cleared by the targeted rerun.
5. Strengthened direct checks `flutter test --no-pub test/features/community/community_answers_test.dart --name 'late answer|pending and error'`: **2 PASS**, including unchanged B state/cache and continued input through the same client after error insertion. This is a separate run, not an additional combined suite count.
6. `flutter analyze --no-pub lib/features/community test/features/community --no-fatal-infos --no-fatal-warnings`: **0 errors, 0 warnings**, two inherited const-constructor infos in the remote-read test. Introduced infos from implementation were resolved. No unrelated lints repaired.
7. `flutter build web --release --no-pub --dart-define=BACKEND_URL=http://127.0.0.1:18097 --dart-define=USE_REMOTE_JOURNAL=true --dart-define=USE_REMOTE_COMMUNITY=true --output=<unique JCOM0507 server run>/web`: **PASS,110.4s**, production lib/main.dart. Existing build/web and JCOM0506 static artifact not replaced. Backend-only publication fix did not require another frontend build.
8. Final browser command: CP7 Python `-X utf8 -m runtime_evidence.jcom0507_answers.run_answers_runtime --server-dir runtime_evidence/jcom0507_answers/runs/server_20261102T152722Z_96c98c`: **PASS**, `ui_20261102T152759Z_ede4cf`, no page errors. Initial PARTIAL run preserved separately.
9. `python -X utf8 -m compileall -q backend`: **PASS**. Harness ast.parse and source/build/harness identity checks: **PASS**. No unrelated suite rerun or Comments browser acceptance rerun.

**Baseline observed**: inherited Pydantic V2 configuration warning, JWT key-length warning, missing optional ML models/mock service messages, unrelated shop-router import warning, global MongoClient resource warning in existing import lifecycle, two const test infos. None was suppressed by source/dependency changes.

**Regressions introduced**:0 current compile errors,0 new analyzer warnings,0 final executed test failures. Initial development/harness failures and their corrections are disclosed above; they are not counted as passing evidence.

## Final runtime / source attribution

The accepted server action created only a new JCOM0507 backend on18097 with isolated Mongo27046 / `saman_jcom0507_test_runtime_32b5ffd0fe44e264`. JCOM0506 backend14152/15192 was never stopped/restarted by this checkpoint. The first JCOM0507-owned backend11076/7876 was freshly identified and stopped only to load the strict-publication fix; its logs/fingerprint remain in `server_20261102T152050Z_441b72`. The final server has listener **11864**, launcher **1368**, native process cwd verified as this workspace, explicit test DB startup evidence and source mtimes before process creation. Tools accepted these actions; no approval rejection/workaround occurred in this checkpoint.

- Final server manifest: `runtime_evidence/jcom0507_answers/runs/server_20261102T152722Z_96c98c/server.json`.
- Source fingerprint: `3597f2860f390fa9eaf2deffab31fb56e2e7ce622ad4058ebf137af5b19f91d2`.
- Router SHA256: `f9ee78d6794f77503e14af0d3bbb32448af65340c9ec721eb16fc6d821c6882d`.
- Model SHA256: `dbea8216849c6b25516503b6a8f2cec964d730439bf347d23087caa4f2ff5897`.
- Main frontend artifact: `4e0efd8278278bfee5943a6fd4299f8d9beaf5f6cd5a04c0e9e31faedd617982`.
- Executed harness: `ae86923e4680886d2c2510456d11900518fef20c8d6b86f3db0aa8de0a2ff467`.
- `source_review.json` confirms current source matches acceptance, frontend source mtimes predate that artifact and executed harness remains unchanged. Version attribution does not rely on health200 or git HEAD alone for uncommitted WIP.

Final real question `qa_ui_20261102T152759Z_ede4cf`: A answer `6ae8ac1818928cfbc65368ec`; persisted-drop/recovered answer `6ae8ac2718928cfbc65368ed`, same canonical ID on actual UI retry. Independent B selected/reloaded/unselected helpful, then lost a real PUT response and reconciled selected/count1 through GET. A fourth real persisted answer retained ID `6ae8ac6a18928cfbc65368f1`; after fixture audience became private, replay returned404 without another insert. Final DB assertions at acceptance: **4 answers,1 retained helpful vote**.

Screenshots01–10 and runtime.json are all under the final unique UI run directory. They cover answer, Feed count, reload, lost response, B vote/unvote/reconcile and revoked read/replay/vote. Actual HTTP responses and fault injection are recorded separately. Synthetic account/profile/question/follow fixtures are restricted to the independent test DB, actual login is through the ordinary form/profile gate, and answers use actual keyboard input. No token/controller/DOM-value injection or direct API mutation substitutes for UI acceptance. Real vote DELETE is the requested unvote operation; no test cleanup/delete was performed.

## Handoff state — 2026-11-03 Asia/Bangkok

On resume after interruption, completed runtime.json was already PASS. Read-only checks found **no current listeners** at18097/18096/27046/8096/3000 and none of the recorded backend/Mongo/static/Flutter PIDs. The cause of their later disappearance is not inferred. This agent performed no end-of-run service cleanup and did not stop another checkpoint/runtime. During the successful browser run only its own Chrome contexts and temporary IPv4 static3000 were closed normally. Test data was retained; no databases/evidence were deleted or previous run paths overwritten.

No current approval blocker and no unverified required local Q&A criterion remains. Scope confirmed against exact allowlist; all inherited WIP preserved. No AGENTS/auth/Profile/Workout/Nutrition/Journal/dependency/global-theme source edits, no question publish/media/notifications/persistent-draft/edit/delete/best-answer feature, no commit/push/merge/deploy/release or next checkpoint. **JCOM-05-07 local acceptance PASS; stop and hand off.**
