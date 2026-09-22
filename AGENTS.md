# Saman App — Jules Agent Instructions

## Mission

Complete only the task described in the GitHub Issue.

The Issue defines:

- Goal
- Allowed files and directories
- Forbidden changes
- Acceptance criteria
- Verification commands
- Maximum repair attempts
- Stop conditions

If information is missing or unsafe, stop and report the blocker instead of guessing.

## Scope rules

- Modify only paths listed under “File hoặc thư mục được phép sửa”.
- Do not make unrelated refactors or cleanup.
- Do not modify `AGENTS.md`, `.github/`, CI workflows, dependencies, configuration files, or generated files unless the Issue explicitly allows it.
- Preserve existing architecture, behavior, design system, naming conventions, and code style.
- Do not overwrite unrelated work.

## Security rules

- Never read, modify, print, commit, or expose secrets, tokens, credentials, `.env` files, or private keys.
- Do not add secrets to source code, logs, commits, or Pull Requests.
- Do not delete data or perform destructive operations.
- Do not modify production services or external databases.

## Codex review rules

- Codex checks Pull Request scope against issue task requirements and allowed paths.
- Codex flags secrets, credentials, tokens, and unsafe or destructive changes.
- Codex checks test execution and Flutter compatibility.
- Human review remains required before any merge into main.

## Git rules

- Never push directly to `main`.
- Never merge a Pull Request.
- Work on a separate branch.
- Commit only files required by the Issue.
- Create a Pull Request for human review.
- Keep commits and the Pull Request description clear and focused.

## Flutter environment

- Flutter: `3.22.0`
- Dart: `3.4.0`
- Flutter project directory: `frontend`

Standard verification:

```bash
cd frontend
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings

find test \
  -name '*_test.dart' \
  ! -name 'render_*_test.dart' \
  -print0 |
  xargs -0 -r flutter test
```

Render or screenshot tests should only run when explicitly required by the Issue.

## Python environment

Backend directory: `backend`

Standard verification:

```bash
python3 -m compileall -q backend
```

## Retry and stop rules

- Respect the maximum repair attempts specified in the Issue.
- Stop when a requested change requires files outside the allowed paths.
- Stop if tests still fail after the permitted attempts.
- Stop if there is risk of data loss, secret exposure, or an unsafe change.
- Stop and explain clearly when requirements are contradictory or insufficient.

## Completion report

The Pull Request must include:

- Summary of completed work
- List of modified files
- Verification commands executed
- Test and analysis results
- Known limitations or unresolved blockers
- Confirmation that no files outside the allowed scope were changed
