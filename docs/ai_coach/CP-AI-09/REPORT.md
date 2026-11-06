# CP-AI-09 — Final acceptance and handoff

## Status

**PARTIAL — Flutter Web acceptance PASS; packaged-catalog acceptance BLOCKED
by the local build environment.**

GitHub Issue [#26](https://github.com/Saman20052005/saman-app/issues/26)
was confirmed as the applicable task and authorizes the two acceptance
areas below. The required local Flutter Web cases passed. The Dockerfile
packaging path could not be run because Docker and other package-build tools
are unavailable; catalog inclusion and resolver behavior from a built
package remain unverified.

## Workspace, governance, and preservation

| Check | Result |
|---|---|
| Workspace root | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` |
| Branch / HEAD | `agent/nutrition-active-localhost-f02` / `10be1ab1971214acd2487ef893df3fcc80212fc9` |
| Git remote | `origin` → `https://github.com/Saman20052005/saman-app.git` |
| Project Context File | **MISSING** in the active workspace; the earlier CP-AI-08 report also recorded it missing |
| Applicable issue | [#26 — CP-AI-09 — Saman AI Coach final local acceptance](https://github.com/Saman20052005/saman-app/issues/26) |
| Allowed paths | This report and `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-09\<run_id>\**` |
| Git status before / after | 3,762 porcelain entries at both checks; existing WIP preserved |
| Files changed in the repository | `docs/ai_coach/CP-AI-09/REPORT.md` only |
| Git mutations | None: no add, commit, push, merge, checkout, reset, clean, or stash |
| Source/configuration/dependencies | Unchanged |
| Real data / production / deployment | Not used |

The local source tree contains extensive pre-existing WIP, including the
recommendation implementation. It was treated as user-owned work and not
reverted, rewritten, or staged.

## Runtime snapshot and fingerprints

Run ID: `run-20261103T130300Z`

Evidence directory:
`D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-09\run-20261103T130300Z`

| Component | Result |
|---|---|
| Test database | Isolated copy at `mongo-data`; database `saman_cpai07_20261103t052553z`; synthetic fixtures only |
| MongoDB | MongoDB 7.0.14 on `127.0.0.1:27050`; ping succeeded |
| Backend | Local test backend on `127.0.0.1:18099`; `/openapi.json` returned 200 and `/api/chat` was present |
| Flutter Web | CP-AI-07 release bundle copy served from the evidence directory on `127.0.0.1:8086`; HTTP 200 |
| Browser | Microsoft Edge through the installed Playwright harness, headed at 1366×900 |
| Synthetic fixture | 3 users; 7 history records distributed 6/1/0; 3 conversations; 0 custom plans |
| Provider | Fake/local path; no provider keys configured; Gemini/OpenAI call guard installed |
| Source relationship | Browser used the retained release bundle; local backend loaded the current source tree. No package or source-tree-isolation claim is made for this run. |
| Process disposition | MongoDB PID 5824, backend PIDs 11680/2892, and web-server PIDs 928/14316 stopped; ports 27050/18099/8086 closed; copied test DB retained |

The retained `main.dart.js` SHA-256 is
`69EACACF34919B94358B03406D6544B8A1118E44180E2F72995D3566742491AD`,
matching CP-AI-07. Relevant current-source fingerprints also match the prior
acceptance snapshots:

| Runtime input | SHA-256 |
|---|---|
| `backend/routers/chat.py` | `2AB7DBF23E2B0DAC0AD89970087BDE5A20682C68469B1538F38C272530488F36` |
| `backend/app/services/workout_recommendation.py` | `090C18EA166D745034F6041475D3A0D0CE08566D472212940C95AF2C4CFB04F7` |
| `backend/app/services/exercise_catalog_resolver.py` | `92107F79CDD92FA1B2CE71A5336A315173CB3A18755EA0783E0EB0E5C8DF6075` |
| `backend/app/data/ai_exercise_catalog.generated.json` | `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33` |

The source JSON catalog has 49 records. This is **source-only** evidence and
does not establish that the catalog is in a backend build artifact.

## Flutter Web acceptance

The harness used the visible Chat composer, the normal login flow, and three
separate `POST /api/chat` submissions. Each login returned HTTP 200 and each
Chat submission returned HTTP 200. The history error was injected at
`chat._read_recommendation_context.read_history` by the external launcher;
the launcher logged a sanitized boundary event and did not record owner IDs.

| Case | Expected | Actual | Result / evidence |
|---|---|---|---|
| C — empty history | Explicit readable-empty wording; do not imply a read error; general catalog baseline | UI distinguished empty history from failure and rendered the rule-based catalog baseline; one POST, HTTP 200 | **PASS** — `case-empty-history.png`; response/checks in `case-results.jsonl` |
| C — injected history read failure | Error wording, not empty wording; fallback not presented as history-personalized | Boundary injector fired exactly once; UI showed “Không đọc được lịch sử tập…” and not empty-history wording; one POST, HTTP 200 | **PASS** — `case-history-read-error.png`; sanitized event in `history-injection.jsonl` |
| A — successful history after removing injection | Correct history signal and ranking after recovery | Injection was absent; expected top five IDs were `barbell-bench-press`, `db-bench-press`, `push-up`, `cable-chest-fly`, `incline-barbell-bench-press`; one POST, HTTP 200 | **PASS** — `case-history-recovered.png`; response/checks in `case-results.jsonl` |
| Side effects per case | No provider call or profile, plan, history/session writes; verify conversation persistence separately | All per-case checks passed: profile hash unchanged; 7 history records and hash unchanged; 0 custom plans; 0 provider calls; conversation documents unchanged while embedded messages increased by 2 per Chat submission | **PASS** — per-case before/after records in `case-results.jsonl`; final DB counts in `db-final-summary.json` |

The dedicated `messages` collection remains empty by design; conversation
messages are embedded in their conversation documents. After the three
submissions, embedded conversation messages increased from 48 to 54. The
final DB summary contains 3 synthetic users, 7 history records, 0 custom
plans, 3 conversations, and 0 standalone messages.

`network-summary.json` records zero browser page errors and zero provider
calls. The browser did request non-AI asset hosts (Google fonts/accounts,
jsDelivr, and Stripe assets); this run did not claim blanket outbound network
blocking. No AI provider key was configured, and the backend provider guard
would fail and log any attempted Gemini/OpenAI call. The `provider-calls.jsonl`
file was not created, which represents zero guarded provider-call attempts.

### Commands and execution results

| Command / check | Exit / actual |
|---|---|
| `python -B -X utf8 -c "import ast; ast.parse(...browser_acceptance_cpai09.py...)"` | 0 — harness syntax valid |
| Launch MongoDB with cloned `mongo-data`, loopback bind, port 27050 | 0 — MongoDB ping succeeded; fixture counts verified |
| Launch backend via external `backend_launcher.py` with `-X utf8` | 0 — backend readiness succeeded; OpenAPI 200; chat route present |
| Launch `python -m http.server 8086 --bind 127.0.0.1 --directory <run>\web-build` | 0 — Flutter bundle served; HTTP 200 |
| Parse source catalog JSON; hash file bytes; count `payload["exercises"]` | 0 — 49 records; SHA-256 matches the fingerprint above |
| `python -B -X utf8 browser_acceptance_cpai09.py` | 0 — final JSON reports 2 logins, 3 Chat POSTs with `[200, 200, 200]`, 0 provider calls, and all checks true |
| Graceful MongoDB shutdown; stop backend/web PIDs; verify test DB and ports | 0 — all CP-owned ports closed; test DB retained (28 files, 315,730,493 bytes) |
| First backend start without UTF-8 output | 1 — process exited before API readiness because an existing Unicode startup log could not encode under Windows `cp1252`; rerun with `-X utf8` succeeded. No app source/configuration change was needed. |
| `Get-Command docker,podman,buildah,pyinstaller,uv` availability check | All **NOT_FOUND** |

Harness evidence includes sanitized network and DB summaries, case responses,
three UI screenshots, and the injection event. Test passwords were random
in-memory values applied only to the copied synthetic DB; passwords, tokens,
authorization headers, and account identifiers are not included in evidence.
Shutdown and test-DB retention are recorded in `process-shutdown.json`.
The harness's body-text extraction flag was false for all three responses.
The three screenshots were visually inspected and show the corresponding
Chat replies; the visual review and this text-extraction limitation are
recorded in `visual-review.json`. No DOM-text assertion is claimed.

## Backend package and production resolver

The repository's configured package path is the root `Dockerfile`: it copies
`backend/requirements.txt`, installs those requirements, then `COPY . .` and
starts `uvicorn backend.main:app`. The root and backend compose files describe
MongoDB services, not an alternative backend image builder.

Expected package command:
`docker build -f Dockerfile -t saman-cp-ai-09-local .`

It was **not run** because `docker`, `podman`, `buildah`, and `pyinstaller`
were not available. No package artifact was produced; therefore no in-package
catalog hash/count, isolated package launch, or production-resolver canonical
ID resolution was observed. The source catalog's 49 records and source-tree
resolver are not substitutes for that evidence.

## Prior checkpoints and handoff

| Checkpoint | Reusable evidence | Still not established |
|---|---|---|
| CP-AI-07 | PASS for local Flutter Web, normal login, synthetic isolated MongoDB, and earlier Chat cases; relevant fingerprints and retained release bundle match this run | Injected history-read failure and catalog packaged in a built backend |
| CP-AI-08 | PASS for 6/6 offline synthetic scenarios and 41 baseline tests | Runtime injected history failure and catalog packaged in a built backend |
| CP-AI-09 | PASS for the three required local Flutter Web cases and their side-effect checks | Backend package inclusion/resolver; production, real provider, and real-user quality |

The active ranker remains a deterministic **rule-based baseline**, not a
trained ML model. Training work is out of scope and should be considered only
if requested by the instructor and permitted data is available.

### VERIFIED

- Issue #26 applies and the execution stayed within its allowed paths.
- Local Flutter Web displayed the distinct empty-history and history-read
  error states, then recovered to the successful-history ranking.
- Each browser request was a single `POST /api/chat` with HTTP 200.
- Zero guarded AI provider calls; profile/history/plans remained unchanged;
  conversation persistence was assessed independently and passed.
- Source catalog fingerprint and 49-record count; source fingerprints match
  CP-AI-07/08.

### UNVERIFIED

- Catalog inclusion in a backend package and resolver execution from that
  package (build tool unavailable).
- Production behavior, a real AI provider, and recommendation quality on
  real users. No production service, real user data, or AI provider was used.

### MISSING

- A backend package artifact and its catalog SHA-256/count comparison.
- Isolated resolver-from-package evidence resolving a canonical exercise ID.

## Completion report

- **Status**: PARTIAL
- **Summary**: Completed and passed local Flutter Web history empty/error/recovery acceptance; package acceptance is blocked by unavailable build tooling.
- **Files Modified**: `docs/ai_coach/CP-AI-09/REPORT.md`; external harness/evidence under the run directory above.
- **Root Cause**: N/A for feature changes. Packaging could not be verified because the configured Docker build tool and alternative builders were absent.
- **Acceptance Criteria**:
  - [x] Empty history, injected history-read error, and successful recovery on Flutter Web.
  - [x] Zero provider calls and zero profile/plan/history writes; conversation persistence checked separately.
  - [ ] Catalog hash/count and canonical-ID resolution from the backend package: UNVERIFIED.
- **Verification Commands Executed**: See command/result table above; runtime acceptance succeeded, package build was not executed.
- **Baseline Observed**: Existing WIP preserved; first backend start exposed a Windows output-encoding issue, resolved by starting with UTF-8 mode.
- **Regressions Introduced**: No app-source/configuration change or test regression introduced.
- **Known Limitations**: Package verification remains outstanding; external non-AI assets were requested by the browser.
- **Scope Confirmation**: Repository change limited to the allowed report; all run artifacts are under the allowed external evidence directory.
- **Merge Confirmation**: No commit, push, merge, or other Git mutation performed.

## Docker verification recheck — 2026-11-03 20:31 +07:00

The recheck was limited to the active workspace and this report. No image was
built and no source, Dockerfile, or build configuration was changed.

### Active snapshot and reusable Flutter evidence

| Check | Result |
|---|---|
| Workspace | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` |
| `git branch --show-current` | Exit 0 — `agent/nutrition-active-localhost-f02` |
| `git rev-parse HEAD` | Exit 0 — `10be1ab1971214acd2487ef893df3fcc80212fc9` |
| `git status --porcelain=v1` | Exit 0 — 234 entries at the start of this recheck; report is untracked and allowed. |
| Current source fingerprint vs. accepted fingerprint | All four hashes below match the values recorded above for CP-AI-09. This validates the relevant files, not the entire dirty worktree. |
| Retained Flutter Web bundle | `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-09\run-20261103T130300Z\web-build\main.dart.js` — SHA-256 `69EACACF34919B94358B03406D6544B8A1118E44180E2F72995D3566742491AD`; matches the accepted value. |
| Source catalog | `backend/app/data/ai_exercise_catalog.generated.json` — 49 exercises; SHA-256 `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33`. |

| Relevant source file | Current SHA-256 |
|---|---|
| `backend/routers/chat.py` | `2AB7DBF23E2B0DAC0AD89970087BDE5A20682C68469B1538F38C272530488F36` |
| `backend/app/services/workout_recommendation.py` | `090C18EA166D745034F6041475D3A0D0CE08566D472212940C95AF2C4CFB04F7` |
| `backend/app/services/exercise_catalog_resolver.py` | `92107F79CDD92FA1B2CE71A5336A315173CB3A18755EA0783E0EB0E5C8DF6075` |
| `backend/app/data/ai_exercise_catalog.generated.json` | `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33` |

The previous report recorded 3,762 status entries; this recheck observed 234
at the start. After the report update, the count was 235; the added status was
the untracked `backend/tests/test_community_attachment_snapshots_mongo.py`.
It was not opened or modified. Therefore HEAD equality is not treated as proof
of full-worktree identity. The relevant source hashes and retained web-bundle
hash do match, so the existing Flutter Web acceptance evidence remains
applicable to those inputs.

### Docker CLI, engine, and package result

| Command / probe | Exit / result |
|---|---|
| `Get-Command docker,podman,buildah,nerdctl,containerd,pyinstaller,uv` | Exit 0 — all not found. |
| `docker --version` | Exit 1 — `docker` is not recognized. |
| `docker info --format '{{.ServerVersion}}'` | Exit 1 — unavailable because the Docker CLI is not installed; no engine version could be queried. |
| Local engine checks | `\\.\pipe\docker_engine` absent; Docker/containerd Windows services not found; `DOCKER_HOST` is unset. |
| `wsl.exe --list --quiet` | Exit 1 — WSL returned usage text; no accessible WSL build environment was established. |
| Package build | Not run; no Docker-compatible CLI/engine or alternative builder is available in this environment. |

The repository package configuration remains the root `Dockerfile` with
repository-root build context. The expected build command is
`docker build -f Dockerfile -t saman-cp-ai-09-local .`. From that Dockerfile's
`WORKDIR /app` and the production resolver's default relative path, the
expected in-image catalog path is
`/app/backend/app/data/ai_exercise_catalog.generated.json`.

| Package acceptance item | Result |
|---|---|
| Image ID | **N/A — no image built.** |
| Catalog at resolver path / packaged SHA-256 / packaged count | **UNVERIFIED** — source catalog hash/count above are not package evidence. |
| Offline, unmounted production-resolver smoke test | **NOT RUN** — no image exists to test. |
| Canonical exercise ID resolved from image | **NONE** — no image smoke test ran; no canonical ID is claimed as resolved. |

**Status remains PARTIAL.** Continue when a Docker CLI and reachable engine,
or an authorized compatible builder, is available in an environment that can
build this exact active workspace. Run the stated Docker build, record its
image ID, inspect the catalog at the resolver path and compare its SHA-256 and
49-record count, then run the production resolver from that image with
network disabled and no source mount and record a successfully resolved
canonical exercise ID. No source or Dockerfile changes are indicated by this
environment blocker.

## Docker verification recheck — 2026-11-04 08:10 +07:00

Issue #26 and `AGENTS.md` were re-read. This follow-up remained on the Active
workspace and made no changes outside this report.

| Snapshot check | Result |
|---|---|
| Workspace | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` |
| Branch / HEAD | `agent/nutrition-active-localhost-f02` / `10be1ab1971214acd2487ef893df3fcc80212fc9` |
| `git status --porcelain=v1` | 235 entries; existing WIP preserved. This includes the report and unrelated existing work; no WIP was overwritten. |
| Relevant snapshot fingerprints | All four source-file hashes in the preceding section still match. Catalog source SHA-256 remains `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33`; count remains 49. |
| Reused Flutter Web evidence | Retained `main.dart.js` SHA-256 remains `69EACACF34919B94358B03406D6544B8A1118E44180E2F72995D3566742491AD`; relevant hashes match the accepted run, so its three Flutter cases remain applicable. |

| Builder / engine probe | Result |
|---|---|
| `Get-Command docker,podman,buildah,nerdctl,containerd,pyinstaller,uv` | Exit 0; all unavailable. |
| `docker --version` | Could not execute; PowerShell reports `docker` is not recognized. |
| `docker info --format '{{.ServerVersion}}'` | Could not execute for the same reason; no engine version can be queried. |
| Standard Docker executable locations | `C:\Program Files\Docker\Docker\resources\bin\docker.exe`, Docker backend executable, and Chocolatey shim are absent. |
| Engine checks | Docker engine pipe absent; no Docker/containerd Windows service found; `DOCKER_HOST` unset. |
| `wsl.exe --status` / `wsl.exe --list --quiet` | Exit codes 50 / 1; WSL is not usable and no distribution was listed. |

**Blocker: no Docker CLI or reachable Docker engine is installed, and no
compatible local builder or usable WSL environment is available on this
machine.** Consequently `docker build -f Dockerfile -t saman-cp-ai-09-local .`
was not run (not applicable; no executable, so no build exit code). No image
ID exists; the catalog path
`/app/backend/app/data/ai_exercise_catalog.generated.json` has no in-image
SHA-256 or count to compare; and the offline, source-unmounted production
resolver smoke test did not run. No canonical exercise ID was resolved from
an image.

**Disposition remains PARTIAL.** Continue when a Docker-compatible builder
and engine are available in an environment able to build this exact Active
workspace. Then build with the repository Dockerfile/context above, verify
the image ID and catalog digest/count at the resolver path, and run the
production resolver from that image with networking disabled and no source
mount. No source or Dockerfile change is needed for the observed blocker.

## Docker verification recheck — 2026-11-04 08:14 +07:00

Issue #26, `AGENTS.md`, and this report were re-read. The Active workspace
still identifies branch `agent/nutrition-active-localhost-f02` at HEAD
`10be1ab1971214acd2487ef893df3fcc80212fc9`. `git status --porcelain=v1`
reported 235 entries. The worktree is dirty; identical HEAD is not treated as
proof that all files match the earlier snapshot.

| Fingerprint check | Current value / result |
|---|---|
| `backend/routers/chat.py` | `2AB7DBF23E2B0DAC0AD89970087BDE5A20682C68469B1538F38C272530488F36` — matches acceptance report |
| `backend/app/services/workout_recommendation.py` | `090C18EA166D745034F6041475D3A0D0CE08566D472212940C95AF2C4CFB04F7` — matches acceptance report |
| `backend/app/services/exercise_catalog_resolver.py` | `92107F79CDD92FA1B2CE71A5336A315173CB3A18755EA0783E0EB0E5C8DF6075` — matches acceptance report |
| `backend/app/data/ai_exercise_catalog.generated.json` | `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33`; 49 exercises — matches acceptance report |
| Retained Flutter `main.dart.js` | `69EACACF34919B94358B03406D6544B8A1118E44180E2F72995D3566742491AD` — matches accepted evidence; prior Flutter Web cases remain applicable |
| Current Dockerfile build input | `Dockerfile` SHA-256 `F69A27354571CF1F8EC105BFE222C027C4428B0B7EC9AA4F5697CA0910411A7C` |
| Current requirements build input | `backend/requirements.txt` SHA-256 `D75A9622E546A94392E0D90236DABCA58F82E78636F6B4B257B0E5C4443FA0C9` |

| Engine check | Result |
|---|---|
| `docker --version` via `cmd.exe /c` | Exit 1 — `'docker' is not recognized as an internal or external command` |
| `docker info --format "{{.ServerVersion}}"` via `cmd.exe /c` | Exit 1 for the same missing CLI; engine cannot be queried |
| Docker named pipe / `DOCKER_HOST` | `\\.\pipe\docker_engine` absent; `DOCKER_HOST` unset |
| Docker executable and engine service probes | Docker CLI, backend executable, Chocolatey shim, and Docker/containerd services not found |

The relevant source fingerprints and retained web bundle still match the
accepted evidence. The Dockerfile and `backend/requirements.txt` hashes above
identify the current package inputs; no previously recorded hashes for these
two files were available for a historical equality claim.

**Blocker remains: this environment has no Docker CLI or reachable engine.**
The repository build command
`docker build -f Dockerfile -t saman-cp-ai-09-local .` was not run because
the CLI/engine are unavailable (no build exit code). No image ID was
produced; `/app/backend/app/data/ai_exercise_catalog.generated.json` was not
inspected inside an image; no in-image SHA-256/count comparison or
`--network none`, source-unmounted production-resolver smoke test could run.
No canonical exercise ID is claimed as resolved from an image. No Flutter
Web scenarios were repeated.

**Status remains PARTIAL.** Resume the image build and verification on an
environment with a Docker-compatible CLI and engine that can access this
exact Active workspace. No source, Dockerfile, or dependency changes were
made; existing WIP was preserved.


## Docker verification recheck — 2026-11-04 15:02 +07:00 (Run run-20261104T080200Z)

Issue #26, `AGENTS.md`, and this report were re-read. In accordance with the
Execution Spec, an automated execution was initiated to attempt local Docker
image build, catalog integrity verification inside the image, and isolated
resolver smoke test.

### 1. Active Snapshot and Workspace Status

| Check | Result |
|---|---|
| Workspace | `D:\SamanDev\workspace\saman-main-verified-CP26_20261025_072840` |
| Branch / HEAD | `agent/nutrition-active-localhost-f02` / `10be1ab1971214acd2487ef893df3fcc80212fc9` |
| `git status --porcelain=v1` | 263 entries; existing uncommitted WIP preserved intact |
| Retained Flutter Web bundle | `D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-09\run-20261103T130300Z\web-build\main.dart.js` (SHA-256 `69EACACF34919B94358B03406D6544B8A1118E44180E2F72995D3566742491AD`) — PASS for 3 Flutter Web cases retained from initial run |

### 2. Relevant Source & Package Input Fingerprints

| Source / build input | SHA-256 | Notes |
|---|---|---|
| `backend/routers/chat.py` | `4CE16AC1D8622F3E48609661C5AB5BE6175692FC01116B3BF21AA108F420F5CC` | 172,539 bytes; local uncommitted WIP |
| `backend/app/services/workout_recommendation.py` | `090C18EA166D745034F6041475D3A0D0CE08566D472212940C95AF2C4CFB04F7` | 20,807 bytes; matches prior checkpoints |
| `backend/app/services/exercise_catalog_resolver.py` | `92107F79CDD92FA1B2CE71A5336A315173CB3A18755EA0783E0EB0E5C8DF6075` | 9,133 bytes; matches prior checkpoints |
| `backend/app/data/ai_exercise_catalog.generated.json` | `FB955CB9F2DFE962952C6FA9FBCA0E2DE65D19480584BBD2A715FDECA0221C33` | 56,755 bytes; **exactly 49 exercise records** |
| `Dockerfile` | `F69A27354571CF1F8EC105BFE222C027C4428B0B7EC9AA4F5697CA0910411A7C` | 410 bytes; root build config |
| `backend/requirements.txt` | `D75A9622E546A94392E0D90236DABCA58F82E78636F6B4B257B0E5C4443FA0C9` | 521 bytes |

### 3. Docker CLI & Engine Verification

Execution Spec rule: *"Kiểm tra Docker CLI (docker --version, docker info). Nếu không có, dừng ngay và báo BLOCKED."*

| Command / Check | Exit code | Result / Diagnostic |
|---|---|---|
| `docker --version` | Non-zero (`-1`) | PowerShell / System: `CommandNotFoundException` / `[WinError 2] The system cannot find the file specified` |
| `docker info` | Non-zero (`-1`) | PowerShell / System: `CommandNotFoundException` / `[WinError 2] The system cannot find the file specified` |
| `podman --version` | Non-zero (`-1`) | `[WinError 2] The system cannot find the file specified` |
| `nerdctl --version` | Non-zero (`-1`) | `[WinError 2] The system cannot find the file specified` |
| Named pipe `\\.\pipe\docker_engine` | N/A | Absent (`False`) |
| `DOCKER_HOST` env | N/A | Unset (`None`) |
| Windows Services probe | N/A | No Docker or containerd Windows services found |

### 4. Acceptance Checklist

- [ ] **Docker Engine hoạt động**: **FAIL / BLOCKED** (Docker CLI and Engine are not installed or reachable in this Windows host environment).
- [ ] **Image build thành công, có Image ID**: **BLOCKED** (Command `docker build -t saman-backend-ai:cp-ai-09 -f Dockerfile .` cannot execute without Docker).
- [ ] **SHA-256 của catalog trong image khớp với source local**: **UNVERIFIED** (No container image artifact available to inspect).
- [ ] **Catalog trong image chứa chính xác 49 bản ghi**: **UNVERIFIED inside image** (Local source catalog verified: exactly 49 records).
- [ ] **Resolver chạy thành công trong container (network=none, không mount), trả về đúng canonical ID**: **UNVERIFIED / NOT RUN**.

### 5. Runtime Evidence Directory

All execution diagnostics and probe results are persisted at:
`D:\SamanDev\runtime_evidence\saman-ai-coach\CP-AI-09\run-20261104T080200Z\`
- `docker-probe.json`
- `docker-probe.log`

### 6. Summary Status & Blocker Report

- **Status**: **PARTIAL**
- **Blocker**: **BLOCKED do môi trường (Docker CLI/Engine không tồn tại trên máy Windows hiện tại)**.
- **Scope Compliance**: Read-only source code inspection. Zero modifications to source code, zero modifications to Dockerfile, zero commits/pushes/merges. Existing WIP preserved.
