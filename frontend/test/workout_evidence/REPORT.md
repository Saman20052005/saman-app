# Workout local verification — 2026-10-07

- **Status**: PASS for the requested local Workout flow. Historical pre-restore uncommitted plugin edits remain UNVERIFIABLE; see audit below.
- **Workspace**: `C:/Users/GL/Desktop/SamanDev/workspace/saman-app-redesign`
- **Branch / HEAD**: `feature/workout-redesign-v2` / `c0075f92d14928ba9aa45ff1dcae5bcc82c1aa3b` (unchanged).
- **Git status**: local modified/deleted/untracked files; nothing staged. No commit, push, merge, reset, restore or clean command performed.
- **PR**: GitHub REST query for all PRs with head `Saman20052005:feature/workout-redesign-v2` returned zero matches. No PR URL exists in that result; no PR created.
- **Scope**: only frontend Workout implementation, related tests and verification artifacts. No backend, dependency, generated source, SDK or deployment edits.

## Verified behavior and root cause

FACT: inherited Finish and Detail Start were placeholder sheets; Home Start/Quick Start were snackbars. Create Plan simulated a delay without persistence. Active initialized with a nonempty default session and ignored supplied exercises; conversion also discarded exercise IDs/media/rest prescription. The inherited render test replaced FlutterError.onError and could hide failures.

Implemented through existing Riverpod providers and existing WorkoutSession/WorkoutPlan/ExerciseRepository contracts:

- Home Start -> scheduled demo Active (5 exercises).
- Quick Start -> current Library picker -> one selected exercise in Active.
- Library -> Detail -> Start exercise -> only that exercise, preserving ID, slug, sets and rest.
- My Plans -> Create -> current Library picker -> local save -> My Plans -> edit -> start -> delete.
- Active -> log sets -> next exercise / exercise queue -> Finish -> Review.
- Finish never writes. Review pauses the timer. System Back / Keep Training preserve sets, rest, elapsed time and previous pause status.
- Save persists only logged sets, once per session ID; double tap, repeated save and repository duplicates do not add a second row. Empty sessions cannot save. Failed save retains active data and supports retry.
- Successful Save replaces Active with History; row opens local Session Detail; History Back returns to the caller. New session receives a new identity.
- Demo labels on Review, History and plan screens explicitly state memory-only and no server sync. Tests override Dio with a throwing provider to detect backend use in these flows.
- Preserved Stitch 04 layout. Fixed proven narrow-width overflow, actual reps interpolation, hardcoded progress count, and a Create Plan floating button that covered Save.

## Files changed in this turn (relative to inherited workspace)

Paths below are under `frontend/`.

| File | Reason |
|---|---|
| `lib/features/workout/data/repositories/mock_exercise_repository.dart` (new) | In-memory plans and idempotent session repository; implements existing contract. |
| `lib/presentation/providers/exercise_providers.dart` | Riverpod demo repository binding without Dio/backend. |
| `lib/presentation/providers/active_workout_providers.dart` | Session identity, initialization, saved state, exercise navigation. |
| `lib/presentation/providers/active_workout_state.dart` | Preserve exercise slug and original media. |
| `lib/presentation/providers/workout_history_providers.dart` | Save guard, actual completed logs, duration/volume and History refresh. |
| `lib/presentation/providers/create_plan_providers.dart` | Replace simulated save with real local create/update. |
| `lib/presentation/screens/active_workout_screen.dart` | Entry initialization, Review/History navigation, queue/progress and reps display. Most of this file's large HEAD diff was already present on takeover. |
| `lib/presentation/screens/workout_review_sheet.dart` (new) | Review, explicit Save, Keep Training and local/demo disclosure. |
| `lib/presentation/screens/workout_history_screen.dart` | Local label, distinct exercise count and title width. |
| `lib/presentation/screens/workout_home_screen.dart` | Start/Quick Start routes and proven text overflow. |
| `lib/presentation/screens/exercise_detail_screen.dart` | Start a single exercise instead of placeholder. |
| `lib/presentation/screens/exercise_library_screen.dart` | Reuse current Library for exercise selection. |
| `lib/presentation/screens/create_plan_screen.dart` | Await actual save, current Library selection, load error, unobstructed Save. |
| `lib/presentation/screens/my_plans_screen.dart` | Local label; preserve plan name at Start. |
| `lib/presentation/widgets/exercise_card.dart` | Wrap metadata to avoid overflow in Create Plan. |
| `test/active_workout_screen_test.dart` | Review contract replaces obsolete In Development expectation. |
| `test/exercise_library_detail_flow_test.dart` | Assert real one-exercise start and Back. |
| `test/workout_home_redesign_test.dart` | Assert real Active route instead of blocked sheet. |
| `test/workout_session_flow_test.dart` (new) | End-to-end widget/provider coverage, no backend, duplicate/failure/retry guards. |
| `test/render_active_workout_screen_test.dart` (inherited untracked, repaired) | Fail on render errors; render full flow at four widths; save real PNGs. |
| `test/workout_evidence/` (new) | Report, executed output and Active/Review/History PNGs. |

The inherited untracked `test/active_workout_actual.png` was not overwritten.

## Audit of the four inherited deletions

| Deleted on takeover | Callers in HEAD before deletion | Current decision |
|---|---|---|
| `lib/screens/workout_screen.dart` | No external import/caller in `lib`; old screen itself routed to old Active/Create. Main/Home already imported `presentation/screens/workout_home_screen.dart`. | Keep inherited deletion: Home, Library, My Plans, Start now operate through current UI. |
| `lib/screens/active_workout_screen.dart` | Only old `screens/workout_screen.dart`. | Keep inherited deletion: active tracking/rest/review/save replaced by current UI and local repository; old backend logging/calorie simulation intentionally not wired. |
| `lib/screens/create_plan_screen.dart` | Only old `screens/workout_screen.dart`. | Recovered from HEAD using `git show`, not `git restore`; no current caller. Preserve freeform fields not fully replaced in demo editor. |
| `lib/screens/plan_screen.dart` | No imports/callers in HEAD `lib`. Also defines a separate CreatePlanScreen. | Recovered from HEAD using `git show`; no current caller. No new route to this form. |

Recovered Git blob IDs equal HEAD: `create_plan_screen.dart` = `60bd15f0e506701671822532d6db9a38ef42ae1d`; `plan_screen.dart` = `f058cf636c1127383ac51994d03d4e7f8c7bd18c`. No semantic diff. Current import/caller search finds only presentation Active/Create routes.

## Audit of 10 restored plugin files

Compared SHA-256 content with sibling `saman-app` and `saman-app-recovery`: all ten identical. Compared `saman-app-incomplete`: four available files differ only LF/CRLF and are text-identical after normalization; six are absent. All ten current Git blob IDs also equal HEAD. No evidence of recoverable functional changes; no generated file edited.

- `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
- `ios/Runner/GeneratedPluginRegistrant.h`
- `ios/Runner/GeneratedPluginRegistrant.m`
- `linux/flutter/generated_plugin_registrant.cc`
- `linux/flutter/generated_plugin_registrant.h`
- `linux/flutter/generated_plugins.cmake`
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- `windows/flutter/generated_plugin_registrant.cc`
- `windows/flutter/generated_plugin_registrant.h`
- `windows/flutter/generated_plugins.cmake`

The four available incomplete-copy files are the macOS Swift file and the three Windows files. These accessible copies cannot prove what uncommitted contents existed immediately before the prior git restore. Such lost content is unknown; no claim that it never existed.

## Executed verification

Flutter 3.22.0 / Dart 3.4.0. Commands run from `frontend`, using the installed `C:/Users/GL/Desktop/SamanDev/sdks/flutter/bin/flutter.bat`. All reported processes were collected to their final exit code.

| Command | Final result |
|---|---|
| `flutter test --no-pub test/active_workout_screen_test.dart test/workout_home_redesign_test.dart test/exercise_library_detail_flow_test.dart` (before editing) | Exit 0, 30 passed; baseline tested placeholders, not saving. |
| `flutter test --no-pub test/workout_session_flow_test.dart test/active_workout_screen_test.dart test/workout_home_redesign_test.dart test/exercise_library_detail_flow_test.dart test/render_active_workout_screen_test.dart` | Exit 0, 41 passed after final reps fix. See `targeted.log`. |
| `$tests=@(rg --files test -g '*_test.dart' -g '!render_*_test.dart'); flutter test --no-pub @tests` | Exit 0, 161 passed. See `full-suite-tail.log`. This full run preceded the final one-line reps interpolation fix; the 41 relevant tests were rerun afterward. |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | Exit 0. Baseline 104 findings/31 warnings; final 93 findings/27 warnings, zero errors and zero new warnings. Existing unrelated findings retained. See analyzer logs. |
| `git diff --check` | Exit 0. |

Screenshots `active.png`, `review.png`, `history.png` are actual Flutter widget render captures at 390x844, pixel ratio 2, following taps through the implemented flow. Render checks also passed at 320x600, 375x812 and 430x932. No FlutterError suppression. SDK Roboto/MaterialIcons and Windows monospace font loaded for readable captures. This is a Flutter test harness, not a physical-device/browser session; network exercise images use the real fallback because widget tests block HTTP.

## Remaining limitations

- Demo persistence is in memory, lost on restart. No backend, sync or disk persistence implemented or claimed.
- Video Guide, camera/CV Form Check and bookmarks remain unavailable as explicitly labeled by existing UI.
- Legacy custom category/level/calorie/freeform plan fields are retained in unreferenced source, not ported into the demo plan editor.
- Historical plugin contents immediately before the previous restore are not available, so loss beyond accessible snapshots cannot be determined.
- No PR created or merge performed. All changes remain local for developer review.
