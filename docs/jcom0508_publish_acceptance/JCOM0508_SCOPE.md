# JCOM-05-08 exact allowlist

Authority: direct attached prompt replaces linked Issue for this checkpoint. Branch agent/nutrition-active-localhost-f02; HEAD10be1ab1971214acd2487ef893df3fcc80212fc9. Preserve WIP, no AGENTS/auth/Profile/Workout/Nutrition/Journal/dependency/global theme edits. No commit/push/merge/deploy/release or unrelated runtime management.

Allowed paths:
- `backend/app/models/community.py`
- `backend/routers/community.py`
- `backend/scripts/setup_community_publish_indexes.py`
- `backend/tests/test_community_publish_mongo.py`
- `frontend/lib/features/community/domain/models/community_post.dart`
- `frontend/lib/features/community/domain/repositories/community_repository.dart`
- `frontend/lib/features/community/data/datasources/community_remote_datasource.dart`
- `frontend/lib/features/community/data/repositories/community_repository_impl.dart`
- `frontend/lib/features/community/presentation/providers/community_providers.dart`
- `frontend/lib/features/community/presentation/providers/community_composer_provider.dart`
- `frontend/lib/features/community/presentation/screens/compose/post_compose_publish_screen.dart`
- `frontend/lib/features/community/presentation/screens/compose/community_ask_question_screen.dart`
- `frontend/lib/features/community/presentation/widgets/create_content_bottom_sheet.dart`
- `frontend/lib/config/app_translations.dart`
- `frontend/test/features/community/community_publish_test.dart`
- `frontend/test/features/community/community_remote_read_test.dart`
- `frontend/test/features/community/community_follow_test.dart`
- `frontend/test/features/community/community_interactions_test.dart`
- `frontend/test/features/community/community_timeout_reconciliation_test.dart`
- `docs/CONTINUOUS_RUN_STATUS.md`
- `runtime_evidence/jcom0508_publish/run_publish_runtime.py`
- `docs/jcom0508_publish_acceptance/JCOM0508_SCOPE.md`
- `docs/jcom0508_publish_acceptance/JCOM0508_CONTRACT.md`
- `docs/jcom0508_publish_acceptance/JCOM0508_REPORT.md`
- `docs/jcom0508_publish_acceptance/baseline.json`
- `docs/jcom0508_publish_acceptance/verification.txt`
- `docs/jcom0508_publish_acceptance/source_review.json`
- `docs/jcom0508_publish_acceptance/backend_tests.log`
- `runtime_evidence/jcom0508_publish/runs/server_20261103T010826Z_d5172c/` (isolated service logs, build and fingerprint)
- `D:/SamanDev/runtime/jcom0508/server_20261103T010826Z_d5172c/` (new session-owned Mongo test data only; no cleanup/deletion)

Generated Python bytecode from authorized execution is tool output, not manually edited source. Each browser run directory is added here before creation and never overwritten. Backend18098/Mongo27048 are newly verified free test targets.

Product decision pending: JCOM05_READINESS_REPORT.md:345 leaves Q&A moderation policy unresolved. User clarification requested asynchronously; implement independent text publish without inventing moderation.

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T012032Z_d5b02b/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/frontend_20261103T012309Z_1b70ec/` (final frontend revision build/source fingerprint; same verified backend, no restart)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T012623Z_9f88b5/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T012809Z_e25ba7/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T013053Z_1f20b0/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T013323Z_ceabe3/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T013648Z_d0263d/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T013921Z_c62e56/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T014119Z_ebd8b5/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T014359Z_84e405/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T014702Z_774ed5/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/final_20261103T015247Z_72e65d/` (final minimal text-only frontend build/provenance; backend unchanged)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T015533Z_06826c/` (immutable browser run: sanitized runtime.json and screenshots)

- `runtime_evidence/jcom0508_publish/runs/ui_20261103T020143Z_c0188a/` (immutable browser run: sanitized runtime.json and screenshots)

## Authorized local Q&A resume (2026-11-03)

User explicitly chooses immediate question publication on successful backend confirmation in local/test; production moderation remains out of scope. Reuse all existing allowlisted publication source/test paths. Additional exact paths before edits:
- `docs/jcom0508_publish_acceptance/resume_qa_baseline.json`
- `docs/jcom0508_publish_acceptance/qa_verification.txt`
- `runtime_evidence/jcom0508_publish/run_questions_runtime.py`

R08 title1–150 characters, optional details0–2000, one of its existing five topic labels and public/private/followers_only. Same endpoint/key/index and current-permission replay as text. No media/health attachment/moderation. Existing R15/card read paths inspected; edit only if canonical integration demonstrably requires it and add exact path first.

- `runtime_evidence/jcom0508_publish/runs/qa_server_20261103T025650Z_499e06/` (new Q&A build/source/process evidence; same isolated backend target)

- `runtime_evidence/jcom0508_publish/runs/qa_ui_20261103T030003Z_02367e/` (immutable Q&A runtime evidence)

- `runtime_evidence/jcom0508_publish/runs/qa_ui_20261103T030052Z_409148/` (immutable Q&A runtime evidence)

- `runtime_evidence/jcom0508_publish/runs/qa_ui_20261103T030225Z_9abf47/` (immutable Q&A runtime evidence)

- `runtime_evidence/jcom0508_publish/runs/qa_final_20261103T030500Z/` (final Q&A source/build/provenance, isolated same-port restart)

- `runtime_evidence/jcom0508_publish/runs/qa_ui_20261103T030615Z_e7756c/` (immutable Q&A runtime evidence)

- `runtime_evidence/jcom0508_publish/runs/qa_clearing_20261103T030900Z/` (final pending-state legibility build/provenance; backend unchanged)

- `runtime_evidence/jcom0508_publish/runs/qa_ui_20261103T031117Z_d2e575/` (immutable Q&A runtime evidence)
