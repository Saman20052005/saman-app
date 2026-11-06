# JCOM-05-08 — Text Posts & Local Q&A Publishing

## Task Completion Report

- **Status**: **PASS for the requested local/test checkpoint**. Text publication retains its prior PASS; Q&A publication is now implemented and verified on final source. Stop at JCOM-05-08.
- **Authority**: Attached JCOM-05-08 prompt replaces the linked Issue. The user's explicit resume decision permits immediate local/test questions after deliberate Đăng and successful backend confirmation; production moderation is excluded. This resolves the historical product blocker in readiness §6.3 without modifying that handoff or inventing production policy.
- **Branch/HEAD**: `agent/nutrition-active-localhost-f02` / `10be1ab1971214acd2487ef893df3fcc80212fc9`, verified before resume and at handoff. Extensive inherited tracked/untracked WIP retained; no reset/clean/stash.
- **Summary**: Reused the text endpoint, canonical-author checks, durable index/replay and existing composer notifier for a strict Q&A alternative. R08 has explicit supported audience, title/details/topic validation and an independent session draft/key provider. Canonical success selects Q&A Feed; existing R15 loads the same ID. Unknown outcomes freeze payload/key and support same-key retry. Account invalidation clears both visible editors and ignores late A responses.

## Files modified during Q&A resume

- `backend/app/models/community.py`: strict question request alongside text.
- `backend/routers/community.py`: same publication endpoint/index/receipt path, canonical qa_info and server publication state.
- `backend/tests/test_community_publish_mongo.py`:3 additional real-Mongo question tests, existing7 text tests retained.
- `frontend/lib/features/community/domain/repositories/community_repository.dart`
- `frontend/lib/features/community/data/repositories/community_repository_impl.dart`
- `frontend/lib/features/community/presentation/providers/community_composer_provider.dart`
- `frontend/lib/features/community/presentation/providers/community_providers.dart`
- `frontend/lib/features/community/presentation/screens/compose/community_ask_question_screen.dart`
- `frontend/lib/config/app_translations.dart`
- `frontend/test/features/community/community_publish_test.dart`
- `runtime_evidence/jcom0508_publish/run_questions_runtime.py`
- `docs/jcom0508_publish_acceptance/`: exact scope/contract/report, `resume_qa_baseline.json`, `qa_verification.txt`, updated `source_review.json`; existing text baseline/log/run evidence preserved.
- `docs/CONTINUOUS_RUN_STATUS.md` and the exact Q&A run/build/provenance directories added to scope before creation.

The existing publication index script, remote datasource, domain post model, text screen, create sheet, Feed routing, R15 and prior-checkpoint sources needed no additional edits during this resume. Their checkpoint-level text integration remains in place. No overlapping publication service/repository/provider implementation was introduced: two provider instances reuse the same notifier with separate state.

## Contract and behavior

One authenticated `POST /api/community/posts`, same durable `X-Idempotency-Key` and partial unique `(user_id,request_key)` index. Strict body alternative is typeqa/title/body/privacy/topic. Title is trimmed, nonblank,1–150 characters; optional details default empty, trimmed,0–2000. Topics are the existing five R08 labels. Privacy is public/private/followers_only; Friends is not mapped to Followers. Unknown/client author/status/counter/media/health-attachment fields reject422. Full contract: `JCOM0508_CONTRACT.md`.

Server stores published only after validation, with canonical database author, server ID/time and qa_info question/details/category/count. Q&A caption stays empty, matching the established Q&A model and rendering the title once. The existing unique index covers both text and Q&A; same-key changed/cross-type payload conflicts409. No transaction, TTL, process lock or new startup migration. Current identity/audience/publication guards run before replay/conflict and before response projection; unpublished/deleted/revoked operations cannot return old content or resurrect.

R08 exposes audience before Đăng. Opening/restoring/changing settings never posts. Canonical success upserts one ID into Q&A Feed. Unknown network outcomes retain/freeze title/details/topic/audience/key; subsequent rejection retains the unknown operation. Remote errors never fall back to fake publication. Back/reopen keeps the session draft; account invalidation clears that account's visible draft and ignores pending responses. Text and question drafts are independent; persistent drafts remain excluded.

## Acceptance criteria

- [x] Existing text persistence/idempotency/audience/recovery: prior browser PASS preserved; shared backend/frontend text regressions PASS during Q&A integration.
- [x] Canonical question validation, extra-field rejection, server published state and privacy/topic projection: PASS real Mongo tests.
- [x] Same key/same payload, changed/cross-type conflict,16 concurrent sends produce one record, fresh-connection persistence: PASS.
- [x] Main app real Login A → Home → Journal → Community → R08, actual keyboard title/details and explicit Đăng → Q&A Feed → canonical R15 → reload: PASS on final source/build.
- [x] Independent B real login: public Feed and R15 projection; private hidden; followers-only correct relation direction, reverse relation insufficient, valid follow grants and revocation removes access: PASS (runtime Feed traversal; direct detail denial also covered by backend tests).
- [x] Actual server persist200 followed by explicit response-delivery abort → UI retry same key → same canonical ID, no duplicate: PASS.
- [x] An independently persisted unknown operation changed to draft in the isolated fixture → same-key UI replay404 with only detail, record retained and no resurrection: PASS. Current owner/identity revocation guards are also covered by the shared backend module.
- [x] Unknown payload/key retention, double-tap/stale/new-draft guards, separate text/question draft and late-account response isolation: PASS focused frontend tests; both R08 title/details visibly clear on account change.
- [x] Scoped analyzer/build/syntax checks: no new compile errors/warnings or remaining executed test failures. No next-checkpoint work or external publishing.

## Actual verification and observed baseline

`qa_verification.txt` lists actual commands and corrections; old text `verification.txt` remains its historical record.

- Pre-resume publication test baseline: **11 PASS**.
- `python -X utf8 -m unittest backend.tests.test_community_publish_mongo -q` through existing CP7 Python, real standalone Mongo27048/test-prefixed random databases: **10 PASS**, after integration and after final backend refinement.7 text +3 question cases; no skipped test or mock persistence.
- `flutter test --no-pub test/features/community/community_publish_test.dart test/features/community/community_compose_flow_test.dart`: **29 PASS** (14 publication +15 compose). After local decoration/caption refinement, publication file **14 PASS**. Later directly affected R08 account/details widget **1 PASS** and question mapping/recovery/late-response cases **3 PASS** separately. No invented combined count.
- Scoped Community analyzer: **0 errors,0 warnings**,2 inherited const infos in remote-read test. Final R08-only analyzer after pending-legibility changes: **No issues found**. Initial own unused import/const infos were corrected.
- Backend compileall: **PASS** after final source. Main-entrypoint web builds to unique Q&A output:99.9s,102.3s and final **98.6s PASS**. All use --no-pub, remote Community/Journal and backend18098. No old build/evidence overwrite or dependencies installed.
- Final runtime: `runtime_evidence/jcom0508_publish/runs/qa_ui_20261103T031117Z_d2e575/runtime.json`: **PASS**. All5 operations match real keyboard title/details to canonical DB fields;0 page errors; source hashes unchanged at end. Independent post-run audit:5 own-actor records,4 published/1 retained draft,5 distinct keys,0 duplicate keys. A's public detail and answers endpoints each loaded with the same ID before and after reload; B also loaded canonical public R15.

**Baseline observed**: Existing broad unrelated WIP; Pydantic/JWT configuration, unrelated shop import and imported global MongoClient ResourceWarning;2 inherited analyzer infos; inherited translation EOF blank line. These were documented and left alone. Old full Community/checkpoint suites and text browser acceptance were not repeated.

**Regressions introduced**:0 new compile errors,0 analyzer warnings,0 remaining executed test failures. One initial own backend-test insertion caused an IndentationError before collection; corrected placement before running the10 passing tests. The old policy-blocker test was updated because the user explicitly changed the requirement; security/recovery assertions were retained and extended, no test skipped or disabled.

## Root cause and evidence-led corrections

**FACT/OBSERVATION**: The first successful canonical Q&A Feed capture showed the title twice. **HYPOTHESIS/TEST**: New publication assigned title to both caption and qa_info, while the existing fake Q&A model uses empty caption and the card already renders qa_info. **CONCLUSION**: Preserve that existing model shape; backend regression asserts empty caption and canonical title/details separately. No card/R15 rewrite.

**FACT/OBSERVATION**: R08 used white text while inherited theme filled its fields white. New pending error/audience text also inherited dark foreground. Browser captures showed unreadable input/pending labels. **CONCLUSION**: Targeted local InputDecoration disables inherited fill; existing tokens supply audience/error/counter/disabled-topic colors. Same keyboard/retry probe cleared final source with readable pending draft/audience/message. No global theme edits.

The text-stage stale failed-refetch race remains fixed by its existing publication revision guard and passing regression. Initial Q&A runtime failures were automation: ambiguous multiple-textarea locator, wrong semantics focus target and guessed comment coordinates. The harness now uses measured native field clicks, waits for active TEXTAREA, reads its value without assigning state, and opens the visible “Tham gia thảo luận” control. Final R15 entry requires fresh canonical detail and answers HTTP events. Early failed runs and the earlier functional PASS remain separate, immutable records; only the final run below clears final source.

## Final fingerprint and evidence

- Final frontend/source manifest: `runtime_evidence/jcom0508_publish/runs/qa_clearing_20261103T030900Z/server.json`.
- Backend launch provenance/source captured **before launch**: `runtime_evidence/jcom0508_publish/runs/qa_final_20261103T030500Z/source_before_start.json`, process/native-cwd/startup logs and final server manifest. Backend source mtimes precede actual process start, hashes match captured files; live OpenAPI includes strict question title150/body2000 schema. This is not a health200-only version claim.
- Final source fingerprint: `34346683ba09938b8995fa2cd12a5c2856e5e9a715ba543b9958f0636fbc8d00`.
- Final main.dart.js SHA256: `7fe7b9adb61d9f7de3d72a8c68775ef1008f36ff462f710dd1ac51b9a1d40ed0`.
- Exact executed Q&A harness snapshot `runtime_evidence/jcom0508_publish/runs/qa_ui_20261103T031117Z_d2e575/harness.py`, SHA256 `313b844749da07be9367808cb802e841fd8bdfcb15cf8c3fce1d95f984694c00`; current harness matches. Read-only text helper hash also remains unchanged.
- Public canonical Q&A ID `6ae950efda93e86e5b0867da`; Feed/R15/reload all use it.
- Actual persisted200/dropped-response operation `6ae95110da93e86e5b0867dd`; same-key retry returns this ID once.
- Second dropped-response operation `6ae9514dda93e86e5b0867de` is retained as draft by the explicit fixture; replay404 contains only detail and no resurrection.

Final screenshots00–09 plus06a show R08, Q&A Feed/R15/reload, unknown outcome/retry, B public R15/followers/revocation and denied replay. Credentials/tokens/authorization headers/request bodies are omitted from recorded HTTP evidence. Synthetic accounts use ordinary complete profiles, real login/profile gate and independent browser contexts; no session injection or preview entrypoint.

**Real HTTP vs fault injection**: `route.fetch()` sends a real POST and obtains actual canonical200 after Mongo persistence; `route.abort()` deliberately drops browser delivery. This is controlled response-loss injection, not naturally observed packet loss. Follow direction/revocation and unpublished status are controlled fixtures in the dedicated test database, not claims that follow/edit/delete mutation UI was tested. Data is retained, not deleted.

Text clearing remains `runtime_evidence/jcom0508_publish/runs/ui_20261103T020143Z_c0188a` (five native/canonical matches; source/build manifest final_20261103T015247Z_72e65d). Its raw JSON/screenshots/harness/build were not changed or rerun. Older text run015533 has a known first-character mismatch and is not exact-input clearing evidence; the later020143 clearing remains authoritative. Original baseline/backend log/verification and historical source review are retained.

## Process ownership and handoff

Fresh handoff listeners: own Mongo **PID14064/parent14260,127.0.0.1:27048**; final backend **PID18028/launcher17964,127.0.0.1:18098**. Commands/native workspace/parent/start time are recorded. Only independent DB `saman_jcom0508_test_runtime_5342f95c5261` and Mongo path `D:/SamanDev/runtime/jcom0508/server_20261103T010826Z_d5172c/mongo` are used. Both services and all synthetic data remain running/retained. Harness Chrome and temporary IPv4 static3000 are closed; no3000 listener remains.

Before each authorized backend restart, listener/command/parent/native workspace/test DB were verified. During final stop, the own launcher exited between existence check and Stop-Process; the command reported `NoProcessFoundForGivenId`. Child and launcher were then confirmed absent and same port free before the authorized same-port start. This was an ordinary process-exit race, not an approval rejection. Tools accepted service management; **no approval blocker remains**. No other runtime/Sony/database was managed or cleaned.

**Known limitations**: This PASS applies to the requested local/test text+Q&A scope and fixed main-app browser scenario; it does not settle production moderation or claim broad responsive/accessibility/performance certification. Media/health attachments, notifications, persistent drafts, post edit/delete and deployment remain excluded.

**Scope confirmation**: Exact allowlist in `JCOM0508_SCOPE.md`; before-resume identities in `resume_qa_baseline.json`; final source/DB/harness/process audit under `source_review.json.qa_resume`, with the original text audit preserved under text_handoff_historical. Community input includes untracked WIP, so focused source review and baseline hashes supplement git diff. No auth/Profile/Journal/Workout/Nutrition/dependency/AGENTS/global-theme edits. Index setup/datasource/R15 reuse introduces no duplicate implementation.

**Merge confirmation**: All changes remain local on the same branch. No PR/commit/push/merge/deploy/release. Product blocker resolved; no remaining checkpoint acceptance blocker. Stop at **JCOM-05-08 PASS**.
