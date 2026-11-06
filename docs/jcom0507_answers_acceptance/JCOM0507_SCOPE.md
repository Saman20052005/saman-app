# JCOM-05-07 exact allowlist

Authority: direct attached user prompt replaces linked Issue for this checkpoint.
Branch agent/nutrition-active-localhost-f02; HEAD10be1ab1971214acd2487ef893df3fcc80212fc9. Preserve all inherited WIP. No commit/push/merge/deploy/release. No auth/Profile/Journal/Workout/Nutrition/dependencies/global theme/AGENTS edits.

Allowed paths:
- `backend/app/models/community.py`
- `backend/routers/community.py`
- `backend/scripts/setup_community_answer_indexes.py`
- `backend/tests/test_community_answers_mongo.py`
- `frontend/lib/features/community/domain/models/question_answer.dart`
- `frontend/lib/features/community/domain/models/community_post.dart`
- `frontend/lib/features/community/domain/repositories/community_repository.dart`
- `frontend/lib/features/community/data/datasources/community_remote_datasource.dart`
- `frontend/lib/features/community/data/repositories/community_repository_impl.dart`
- `frontend/lib/features/community/presentation/providers/community_providers.dart`
- `frontend/lib/features/community/presentation/screens/qa/community_question_detail_screen.dart`
- `frontend/lib/features/community/presentation/widgets/community_answer_composer.dart`
- `frontend/lib/config/app_translations.dart`
- `frontend/test/features/community/community_answers_test.dart`
- `frontend/test/features/community/community_remote_read_test.dart`
- `frontend/test/features/community/community_follow_test.dart`
- `frontend/test/features/community/community_interactions_test.dart`
- `frontend/test/features/community/community_timeout_reconciliation_test.dart`
- `docs/CONTINUOUS_RUN_STATUS.md`
- `runtime_evidence/jcom0507_answers/run_answers_runtime.py`
- `docs/jcom0507_answers_acceptance/JCOM0507_SCOPE.md`
- `docs/jcom0507_answers_acceptance/JCOM0507_CONTRACT.md`
- `docs/jcom0507_answers_acceptance/JCOM0507_REPORT.md`
- `docs/jcom0507_answers_acceptance/baseline.json`
- `docs/jcom0507_answers_acceptance/verification.txt`

Runtime: new JCOM0507-owned backend only, independent test DB on verified loopback Mongo27046. Do not stop/restart the existing JCOM0506 backend14152/15192 or any other runtime. Source/build artifacts and each browser run go to a fresh concrete run directory added here before creation. No data deletion. A tool rejection stops that action, with no workaround.

- `docs/jcom0507_answers_acceptance/verification_backend.tmp` (initial retained raw output, moved to final log)
- `docs/jcom0507_answers_acceptance/verification_backend.log`

- `runtime_evidence/jcom0507_answers/runs/server_20261102T152050Z_441b72/` (exact isolated server/build run directory; generated web output, server logs and fingerprint)

- `runtime_evidence/jcom0507_answers/runs/ui_20261102T152421Z_a07bf0/` (immutable browser run: runtime.json, stage screenshots)

- `runtime_evidence/jcom0507_answers/runs/server_20261102T152722Z_96c98c/` (final strict-publication backend run, logs/source fingerprint; original immutable frontend artifact reused)

- `runtime_evidence/jcom0507_answers/runs/ui_20261102T152759Z_ede4cf/` (immutable browser run: runtime.json, stage screenshots)

- `docs/jcom0507_answers_acceptance/source_review.json` (final baseline/source/build/scope audit)

Generated tool artifact (not manually edited): `runtime_evidence/jcom0507_answers/__pycache__/run_answers_runtime.cpython-311.pyc`. Python module execution created this cache during authorized runtime verification.

- `docs/jcom0507_answers_acceptance/verification_backend_readable.log` (derived UTF-8 transcript; original raw bytes preserved)
