# Saman App — Jules & Autonomous Agent Governance

## 1. Mission & Authority

Complete only the task defined in the linked GitHub Issue (e.g., from `.github/ISSUE_TEMPLATE/night-task.yml`).

- **Task Source of Truth**: The GitHub Issue specifies the goal, context, allowed paths, forbidden changes, acceptance criteria, verification commands, branch name, and maximum repair attempts.
- **Repository Safety Baseline**: `AGENTS.md` defines non-negotiable repository safety, architectural, and operational rules.
- **Precedence & Conflict Resolution**: Agents MUST follow BOTH. If an Issue conflicts with safety rules, contains contradictory instructions, requires unsafe actions, or lacks information needed for safe implementation:
  **STOP AND REPORT THE BLOCKER.**
  Never guess. Never silently expand scope.

---

## 2. Strict Scope Control & Smallest Safe Diff

- **Allowed Paths**: Modify ONLY files explicitly listed under `allowed_paths` ("File hoặc thư mục được phép sửa"). All other files are strictly read-only.
- **Smallest Safe Diff**: The preferred implementation is the smallest targeted change that satisfies verified requirements while preserving existing behavior.
- **MUST NOT**:
  - Perform opportunistic cleanup or stylistic refactoring on working code.
  - Reorganize directories, move, or rename files unless explicitly commanded.
  - Modernize code merely because newer patterns exist.
  - Run formatting sweeps or touch whitespace on unchanged lines.
  - Fix unrelated warnings, lints, or technical debt.
  - Manually modify generated files (e.g., `*.g.dart`).
  - Modify `AGENTS.md` during normal tasks unless the Issue explicitly targets repository governance.

---

## 3. Architecture Preservation & Anti-Duplication

- **Directory Boundaries**:
  - Flutter frontend code MUST reside in `frontend/lib/`. Never create feature directories directly under `frontend/` outside `lib/`.
  - New backend implementation MUST be added under `backend/` unless the Issue explicitly identifies another existing runtime path.
  - Existing legacy or mirrored root-level backend files MUST NOT be moved, deleted, synchronized, or cleaned up unless explicitly authorized by the Issue.
- **Architecture Standards**:
  - Preserve Flutter Feature-First Clean Architecture (`frontend/lib/features/[feature]/` with `data`, `domain`, `presentation`).
  - Preserve the established Riverpod/provider pattern of the affected feature. Do not migrate between manual providers and generated providers unless explicitly authorized.
  - Preserve existing domain models, serialization mappings, repository contracts, and backend routes.
- **Reuse First**: Before creating a new class, model, service, provider, or utility, inspect existing code for an established implementation.
- **MUST NOT Introduce**:
  - Duplicate services, repositories, providers, or models serving overlapping purposes.
  - Parallel implementations of existing features.
  - Unnecessary abstraction layers, wrappers, or speculative future features.

---

## 4. Root-Cause-First Bug Fixing

Before modifying code to resolve a defect:

1. **Reproduce & Evidence**: Establish concrete evidence of the failure when practical.
2. **Trace Layer & Path**: Identify the exact failure layer and trace the data/execution flow.
3. **Hypothesize**: Formulate a specific root-cause hypothesis.
4. **Verify**: Validate the hypothesis against code, logs, or targeted tests.
5. **Targeted Fix**: Apply the minimal change directly resolving the verified root cause.

- **Diagnostic Discipline**: Explicitly distinguish `FACT` vs. `OBSERVATION` vs. `HYPOTHESIS` vs. `TEST` vs. `CONCLUSION`.
- **MUST NOT**:
  - Add defensive checks or speculative null-guards everywhere to mask unknown causes.
  - Catch broad exceptions (e.g., bare `catch (e)`) merely to suppress test failures.
  - Silence compiler/analyzer warnings instead of resolving their verified origin.

---

## 5. Proportional Baseline & Regression Protection

- **Proportional Baseline**: Before modifying code, capture the smallest relevant baseline first (e.g., run the targeted test file or analyzer check for the affected component). Do not run the entire test suite prior to small tasks unless the Issue, high risk, or affected surface requires it.
- **Isolate Pre-Existing Issues**:
  - Distinguish `PRE-EXISTING ISSUES` from issues `INTRODUCED BY THIS TASK`.
  - Document pre-existing failures; do NOT attempt to fix them unless assigned.
  - Pre-existing issues are never an excuse for broader refactoring.
- **Zero Regressions**: The task MUST introduce **0 new compile errors**, **0 new analyzer warnings**, and **0 new test failures**.

---

## 6. Circuit Breaker for Scope Escalation

- **Escalation Trigger**: If resolving a task requires modifying files outside `allowed_paths` or materially expands the approved scope, STOP immediately.
  *(A valid fix touching multiple related files already inside `allowed_paths` is permitted.)*
- **MUST NOT**:
  - Recursively modify surrounding out-of-scope modules to make a change pass.
  - Silently edit configuration, dependencies, or unassigned modules.
- **Reporting Blocker**: When stopping for scope expansion, report:
  1. Exact out-of-scope file path(s) required.
  2. Technical root cause explaining why the change is necessary.
  3. Proposed modification and consequence of not making it.
  4. Wait for explicit human approval or Issue update before proceeding.

---

## 7. API, Authentication & Data Safety

- **Contracts**: MUST NOT alter API routes, request/response JSON schemas, HTTP status codes, authentication mechanisms, token handling, storage keys, or database schemas without explicit Issue authorization.
- **Security Safeguards**:
  - NEVER weaken authentication, authorization, or input validation to make a test pass.
  - NEVER read, modify, print, commit, or expose secrets, tokens, credentials, `.env` files, or private keys.
  - NEVER modify production infrastructure, cloud resources, or live external databases.
  - NEVER perform destructive data operations or irreversible migrations.

---

## 8. Dependency & Configuration Freeze

- **Strict Freeze**: MUST NOT modify or upgrade without explicit Issue authorization:
  - Flutter SDK constraint (`3.22.0`) or Dart SDK constraint (`3.4.0`).
  - Python runtime version or dependencies in `backend/requirements.txt`.
  - Frontend packages in `frontend/pubspec.yaml` or lockfiles (`pubspec.lock`).
  - CI workflows (`.github/workflows/`), Dockerfile, or deployment configs (`render.yaml`, `Procfile`).
- Dependency upgrades MUST NOT be used as the first response to resolve a bug or build error.

---

## 9. Test Integrity

Tests represent validation evidence, not obstacles.

- **MUST NOT**:
  - Delete, disable, comment out, or skip failing tests to obtain green CI.
  - Weaken assertions or replace meaningful assertions with trivial checks (e.g., `expect(true, isTrue)`).
  - Mock away the system under test to bypass real logic verification.
  - Alter expected test data unless the Issue explicitly redefines the business requirement.

---

## 10. New Feature Implementation

When implementing new capabilities:

1. **Locate Extension Points**: Identify existing shared models, providers, and UI components before writing new ones.
2. **Minimal Integration Boundary**: Wire the feature through existing dependency injection and routing mechanisms.
3. **No Speculative Code**: Implement strictly what the Acceptance Criteria require — no unused abstractions or future-proofing.
4. **Focused Testing**: Add unit/widget tests covering the new behavior without destabilizing surrounding suites.

---

## 11. Pre-Completion Self-Review Gate

Before declaring DONE or creating a Pull Request, the agent MUST perform this self-audit:

1. [ ] **Diff Review**: Inspect `git diff` against the base branch.
2. [ ] **Scope Verification**: Confirm every modified file is inside `allowed_paths`.
3. [ ] **Cleanliness**: Ensure no debug prints, temporary files, commented-out code, or formatting noise were left behind.
4. [ ] **No Duplications**: Verify no redundant models, providers, or services were introduced.
5. [ ] **Acceptance Criteria**: Verify every criterion from the Issue is satisfied.
6. [ ] **Verification**: Run standard verification commands; confirm 0 new errors or regressions.
7. [ ] **No Merge**: Confirm changes remain on the task branch and no merge to `main` occurred.

---

## 12. Multi-Round Correction Protocol

Autonomous review and repair rounds (e.g., Jules review cycles) MUST follow these rules:

- **Respect Limits**: Always observe the maximum repair attempts defined by the current GitHub Issue (e.g., `max_attempts` in `night-task.yml`).
- **Incremental Correction**: A correction round is NOT permission to start over or rewrite architecture. Continue on the current branch.
- **Targeted Diff**: Read reviewer findings, diagnose verified flaws, and patch only the cited issues. Preserve all already-passing criteria.
- **Early Exit**: Stop immediately when all Acceptance Criteria and verifications pass; do not consume remaining attempts.
- **Escalation Stop**:
  - If regressions or test failures increase after a correction attempt, STOP and report.
  - If the same error persists across repeated attempts without progress, STOP and report root-cause uncertainty.

---

## 13. Explicit Stop Conditions

Agents MUST STOP and report a blocker instead of guessing when:

1. A required change exceeds `allowed_paths` or approved scope.
2. Requirements are contradictory, ambiguous, or technically infeasible.
3. Root cause cannot be established with reasonable evidence.
4. Risk of secret exposure, data loss, or production service disruption is detected.
5. An unauthorized dependency upgrade, schema migration, or architecture overhaul is required.
6. Permitted repair attempts are exhausted or regressions increase during correction.

*Stopping and reporting a clear blocker is considered correct, safe, and successful agent behavior.*

---

## 14. Git Safety Rules

- **Branch Isolation**: Work ONLY on the branch specified by the Issue (e.g., `agent/...`).
- **No Direct Push**: NEVER push directly to `main` or force-push shared branches.
- **No Autonomous Merging**: NEVER merge a Pull Request. Merging is strictly reserved for human reviewers.
- **Non-Destructive**: NEVER run destructive git commands (`git reset --hard`, `git clean -fd`) that risk discarding uncommitted user work.
- **Clean Commits**: Commit only files necessary for the task, with clear, descriptive commit messages.

---

## 15. Environment & Verification Commands

### Flutter Frontend

- **Environment**: Flutter `3.22.0`, Dart `3.4.0`
- **Working Directory**: `frontend`
- **Targeted Verification (Proportional Baseline)**:
  ```bash
  cd frontend
  flutter test test/path_to_relevant_test.dart
  ```
- **Standard Verification**:
  ```bash
  cd frontend
  flutter analyze --no-fatal-infos --no-fatal-warnings

  find test \
    -name '*_test.dart' \
    ! -name 'render_*_test.dart' \
    -print0 |
    xargs -0 -r flutter test
  ```
  *(Run `flutter pub get` only when dependencies changed, dependency resolution is required, or the Issue explicitly requires it. Render or screenshot tests should only run when explicitly required by the Issue.)*

### Python Backend

- **Environment**: Python 3
- **Working Directory**: `backend`
- **Standard Verification**:
  ```bash
  python3 -m compileall -q backend
  ```

---

## 16. Structured Completion Report

Every completed task or Pull Request MUST include the following report in the PR description:

```markdown
## Task Completion Report

- **Status**: [PASS | PARTIAL | BLOCKED]
- **Summary**: [Concise summary of work performed]
- **Files Modified**:
  - `path/to/file1`
  - `path/to/file2`
- **Root Cause**: [Verified root cause for bug fixes; N/A for features]
- **Acceptance Criteria**:
  - [x] Criterion 1: PASS
  - [ ] Criterion 2: [PASS | FAIL | UNVERIFIED]
- **Verification Commands Executed**:
  - `[Command 1]`: [Output summary / result]
- **Baseline Observed**: [Pre-existing warnings/failures observed before editing]
- **Regressions Introduced**: 0 errors, 0 new warnings, 0 new test failures
- **Known Limitations**: [Unresolved blockers or out-of-scope observations]
- **Scope Confirmation**: Confirmed all modified files are within allowed_paths.
- **Merge Confirmation**: Pull Request created for human review. No merge performed.
```

---

## 17. Code Review Rules (For Reviewer Agents)

- **Review Scope**: Review ONLY changes included in the Pull Request diff.
- **Scope Enforcement**: Confirm every modified file is strictly inside `allowed_paths`.
- **Flag Prohibited Patterns**:
  - Unrelated refactors, formatting churn, or dependency modifications.
  - Placement of Flutter code outside `frontend/lib/` or backend code in repository root.
  - Duplicated models, services, or providers.
  - Weakened test assertions, skipped tests, or mocked-away logic.
  - Secrets, credentials, or `.env` content.
- **Compatibility**: Verify Flutter `3.22.0` and Dart `3.4.0` compatibility.
- **Verification Check**: Ensure the completion report documents actual executed verification commands.
- **Merge Authority**: Never approve or execute direct merges to `main`.
