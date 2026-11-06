# JCOM-05-06 - Exact allowlist

Authority: takeover prompt plus explicit user exception dated 2026-11-02.
Branch: agent/nutrition-active-localhost-f02. Verified HEAD: 10be1ab.
No commit/push/merge/deploy. Preserve all inherited WIP. No auth/Profile, dependencies, Workout/Nutrition or production/shared DB writes.

## allowed_paths

- `backend/app/models/community.py`
- `backend/routers/community.py`
- `backend/scripts/setup_community_comment_indexes.py`
- `backend/tests/test_community_comments_mongo.py`
- `frontend/lib/features/community/domain/models/community_comment.dart`
- `frontend/lib/features/community/domain/repositories/community_repository.dart`
- `frontend/lib/features/community/data/datasources/community_remote_datasource.dart`
- `frontend/lib/features/community/data/repositories/community_repository_impl.dart`
- `frontend/lib/features/community/presentation/providers/community_providers.dart`
- `frontend/lib/features/community/presentation/screens/community_post_detail_screen.dart`
- `frontend/lib/features/community/presentation/widgets/community_comment_composer.dart`
- `frontend/lib/config/app_translations.dart`
- `frontend/test/features/community/community_comments_test.dart`
- `frontend/test/features/community/community_remote_read_test.dart`
- `frontend/test/features/community/community_follow_test.dart`
- `frontend/test/features/community/community_interactions_test.dart`
- `frontend/test/features/community/community_timeout_reconciliation_test.dart`
- `docs/CONTINUOUS_RUN_STATUS.md`
- `docs/jcom0506_comments_acceptance/JCOM0506_SCOPE.md`
- `docs/jcom0506_comments_acceptance/JCOM0506_CONTRACT.md`
- `docs/jcom0506_comments_acceptance/JCOM0506_REPORT.md`
- `docs/jcom0506_comments_acceptance/baseline.json`
- `docs/jcom0506_comments_acceptance/verification.txt`
- `runtime_evidence/jcom0506_comments/run_comments_runtime.py`
- `runtime_evidence/jcom0506_comments/runtime.json`

## Baseline

Frontend targeted baseline: 19 tests PASS. Default Python lacks bson; use existing D:/SamanDev/runtime/saman-cp7-python/Scripts/python.exe. No historical ports assumed active. Existing Community files are inherited untracked WIP; translations and status also contain inherited work. Record SHA256 before editing.

## Runtime evidence additions (before creation)

- `docs/jcom0506_comments_acceptance/01_login.png`
- `docs/jcom0506_comments_acceptance/02_home.png`
- `docs/jcom0506_comments_acceptance/03_journal.png`
- `docs/jcom0506_comments_acceptance/04_feed.png`
- `docs/jcom0506_comments_acceptance/05_comment.png`
- `docs/jcom0506_comments_acceptance/06_reply.png`
- `docs/jcom0506_comments_acceptance/07_reload.png`
- `docs/jcom0506_comments_acceptance/08_timeout.png`
- `docs/jcom0506_comments_acceptance/09_viewer_b.png`
- `docs/jcom0506_comments_acceptance/runtime_blocker.png`
- `docs/jcom0506_comments_acceptance/10_feed_count.png`
- `docs/jcom0506_comments_acceptance/11_private_feed.png`

## Resume: read-only browser probes and focused diagnostic evidence

- `runtime_evidence/jcom0506_comments/reply_diagnosis.json`
- `docs/jcom0506_comments_acceptance/reply_diagnosis.png`
- `runtime_evidence/jcom0506_comments/reply_diagnosis_before_fix.json`
- `docs/jcom0506_comments_acceptance/reply_diagnosis_before_fix.png`

Resume authorization: user request to diagnose reply on the existing test runtime.
No backend process start/stop/restart, replacement port, proxy, or approval bypass.
The existing harness may serve the already-built static frontend on its original
IPv4 origin 127.0.0.1:3000; this is a temporary client fixture, never a backend.
Do not touch the unrelated IPv6 localhost:3000 Flutter process.
Existing screenshots 01-05 and accepted suites are preserved and not rerun.

## Latest authorization: final-backend acceptance

The user's subsequent direct instruction permits stopping/restarting only the
freshly verified JCOM test backend on 127.0.0.1:18096 in this workspace, using
MongoDB 127.0.0.1:27046 / saman_jcom0506_test_runtime_20261102_codex.
This supersedes the preceding resume prohibition, but never tool approval.
If rejected, stop that action without a different command/port/process workaround.
No auth/CORS/dependency changes, test-data deletion or other runtime management.
Additional exact evidence paths, reserved before creation:
- `runtime_evidence/jcom0506_comments/backend_version.json`
- `docs/jcom0506_comments_acceptance/12_revoked_thread.png`
- `docs/jcom0506_comments_acceptance/13_final_runtime_blocker.png`
