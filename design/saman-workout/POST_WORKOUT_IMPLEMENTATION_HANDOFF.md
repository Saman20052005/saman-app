# Saman Workout — Review & Save / Workout Complete implementation handoff

**Place this file at:** `design/saman-workout/POST_WORKOUT_IMPLEMENTATION_HANDOFF.md`\
**Design references:** `06-review-save/` and `07-workout-complete/`\
**Scope:** Flutter frontend and local demo session flow only. This document is a handoff, not proof that the screens have been implemented or tested.

## A. Current state and evidence

- Reference branch at design review: `feature/workout-redesign-v2`, GitHub commit `5305ee1692a630d1156f55b8190a00ec58aec6ea`. Verify local branch, HEAD, working tree, and actual contents before editing; they may have changed.
- `frontend/lib/presentation/screens/active_workout_screen.dart`: Finish opens `_showReviewAndSaveModal`; successful save currently replaces Active Workout with `WorkoutHistoryScreen`.
- `frontend/lib/presentation/screens/workout_review_sheet.dart`: existing review is a bottom sheet, with Save and Keep Training actions.
- `frontend/lib/presentation/providers/active_workout_providers.dart`: `activeWorkoutSessionProvider` owns the current active session, logged sets, elapsed seconds, title, session ID, and start time.
- `frontend/lib/presentation/providers/workout_history_providers.dart`: `ActiveSessionSaver.saveCurrentSession()` builds `WorkoutSession`, calls the exercise repository, marks the active session saved after success, and invalidates history.
- `frontend/lib/data/models/exercise.dart`: `WorkoutSession` holds `id`, `planName`, `startedAt`, optional `finishedAt`, `exerciseLogs`, optional `totalDurationMinutes`, and `totalVolumeKg`. Each `ExerciseSetLog` has `exerciseId`, `exerciseSlug`, `setNumber`, `repsCompleted`, and `weightKg`.
- `frontend/lib/features/workout/data/repositories/mock_exercise_repository.dart`: saved sessions live in a repository instance's memory and are lost on app restart. This phase is a local demo, not server persistence.
- `frontend/lib/presentation/screens/workout_history_screen.dart` and `session_detail_screen.dart`: existing destinations for history and session details. Preserve their working behavior except for necessary navigation integration.
- `frontend/lib/presentation/tokens/saman_workout_tokens.dart`: current Workout palette. Use the approved `06`/`07` screen references for actual layout; generic design-system exports may describe conflicting button colors or radii.

Read root `AGENTS.md` and the relevant targeted tests before implementation. Read `docs/specs/saman_coach_blueprint.md` only if proposing backend/Chat data-flow work; backend work is outside this checkpoint.

## B. Decision and single checkpoint goal

**GO — frontend post-workout redesign.** Implement two full-screen destinations:

```text
Active Workout --Finish--> Review & Save --successful save--> Workout Complete
         ^                       |                                  |       |
         +---- Back/Keep training+                       View history   Workout tab
```

The Review screen replaces the old bottom-sheet presentation. Workout Complete is a distinct screen displayed only after the repository save succeeds. History remains a separate destination. Do not leave two competing review implementations reachable from Finish.

## C. Design source and precedence

1. `06-review-save/screen-top.png`, `screen-bottom.png`, and `code.html`: visual references for the Review screen.
2. `07-workout-complete/screen-top.png`, `screen-bottom.png`, and `code.html`: visual references for Complete.
3. Each screen's `DESIGN.md`: screen-specific interactions, responsive behavior, and exceptions.
4. Existing Flutter tokens and approved Workout Home: shared app consistency.

HTML and PNG are *references*, not runnable Flutter code or sources of real user data. The sample values `32 min`, `4 sets`, `2 exercises`, and `1,078 kg` must never be hardcoded into production widgets. If a screen-specific document contradicts the actual approved render or current repository contract, report the exact conflict and resolve it against the approved screen and working data flow without silently expanding scope.

## D. Data mapping and calculations

| UI field | Source / rule |
| --- | --- |
| Workout name | Active session title before save; saved session `planName` after save. |
| Date/time | Session timestamps converted for display to `Asia/Ho_Chi_Minh`; do not use a fixed sample date or device-default assumption. |
| Logged sets | Count only completed, valid recorded sets included in the saved `exerciseLogs`. |
| Exercises performed | Count distinct `exerciseId` values among those logged sets, not planned exercises. |
| Set display | Each saved set's `setNumber`, `weightKg`, and `repsCompleted`. Preserve decimal weights where applicable. |
| Per-exercise volume | Sum `weightKg × repsCompleted` over that exercise's saved sets. |
| Session volume | Sum the same logged-set volumes. Respect the existing `WorkoutSession.totalVolumeKg` integer contract; do not introduce a new persistence schema in this UI task. |
| Distribution | Per-exercise logged volume / total logged volume, only when total > 0. With one exercise, a single 100% segment is valid. If total is 0, omit the percentage chart rather than divide by zero. |
| Duration | Current active elapsed time for Review; saved duration or timestamps for Complete as supported by the existing model. Distinguish absent duration from a genuine `0 min` caused by flooring a session under one minute. Do not fabricate elapsed time. |

**Illustrative arithmetic only:** Bench Press `24×10 + 26×8 = 448 kg`; Lat Pulldown `35×10 + 35×8 = 630 kg`; total `1,078 kg`; shares approximately `41.6% / 58.4%`. These are visual QA examples, not default user data.

Exercise thumbnails or the photo hero should use an available, authorized app asset with a graceful fallback. Do not depend on a temporary Stitch image URL at runtime. Avoid displaying unverified muscle groups, PRs, calories, heart rate, RPE, or AI form metrics as session facts.

## E. Review & Save behavior (`06`)

- Finish navigates to a **full-screen route**, preserving the active session state.
- Back and Keep training return to the same Active Workout with logged sets, timer state, and draft inputs intact. Preserve the pre-review paused/running state deliberately; do not silently reset or start another session.
- Review shows unsaved logged data. Do not use “Saved”, “Session recorded”, or “Completed” as a persistence claim before save succeeds.
- Save is disabled when there are no completed sets. Prevent duplicate submission while saving.
- Reuse the existing `ActiveSessionSaver.saveCurrentSession()` path and repository, rather than creating a second save service. On failure, stay on Review, retain all logs, and offer Retry. On success, navigate once to Complete.
- Demo notice before saving should use future tense, e.g. “This demo saves your workout on this device until the app restarts.” Keep the notice legible without making it the visual hero.

## F. Workout Complete behavior (`07`)

- Render from the **exact session just saved**, preferably its confirmed saved value or stable ID. Do not query “latest history” and risk showing another session or a newly reset active state.
- Opening Complete must not save again. Back and “Back to Workout” return to the Workout tab, not to a finished Active Workout. “View workout history” opens the existing History screen. Avoid a navigation stack that lets Back revisit Review and resubmit the saved session.
- Include the honest local-demo notice: “Saved on this device for this demo. It clears when the app restarts.” Do not claim cloud synchronization or durable history.
- Missing duration: show a neutral “—” only if data is absent. For a real session shorter than one minute, choose an honest display such as “<1 min” if the available elapsed seconds support it; do not treat every zero minute value as missing.
- Exercise list, volume breakdown, long titles, one-exercise sessions, zero-volume sets, and image failure must remain readable. Content must scroll completely above the safe-area action region.

## G. Implementation boundaries

- Reuse Riverpod active-session state, current models, repository, and `SamanWorkoutTokens`; mock data belongs in provider/repository layers, not inside widget trees.
- Replace the reachable legacy review UI cleanly once the new route is working. Do not duplicate routes or leave both designs competing. Do not delete unrelated legacy backend mirrors.
- Do not change backend routes, authentication, MongoDB schema, Chat AI integration, package versions, generated Dart files, Workout Home, Exercise Library, or Profile as part of this checkpoint.
- Keep local changes focused. No `git add`, commit, push, or merge without a direct Developer instruction.

## H. Acceptance checks and evidence

- [ ] Finish opens full-screen Review; Back/Keep training preserve the original active session and logged sets.
- [ ] Zero sets cannot save; loading blocks repeat taps; failure leaves Review recoverable; Retry succeeds without duplicate session records.
- [ ] Successful save opens Complete exactly once with the same saved session ID and logged values; History contains that session once.
- [ ] Counts and volumes derive from completed logs, including one exercise, fractional weight, zero volume, and a short duration.
- [ ] The local-demo wording matches actual in-memory persistence; no cloud-sync claim or invented metric.
- [ ] Both Flutter screens match their approved top/bottom references at a practical phone viewport; no clipped hero, number wrapping, overflow, or content hidden by the action area.
- [ ] Existing Workout entry and History remain usable. No new analyzer errors or targeted test failures.

Capture a proportional baseline, then run relevant widget/session-flow tests and targeted analyzer checks. For the completion report, list changed files, exact tests and results, screenshots of both Flutter screens at top/bottom, remaining discrepancies, and any out-of-scope file needed. Do not label a static Stitch preview as evidence that the Flutter flow works.

**Chỉ sửa và test local. CẤM tự ý commit/push khi chưa có lệnh trực tiếp từ Developer.**
