# Screen Design Reference: 04 - Active Workout (BLOCKED / Missing Assets)

## Status: BLOCKED — Screen Assets Missing from Local Downloads

### Finding Summary
In the provided local Downloads batch:
1. `stitch_saman_workout-home_design` → Screen 01 (Workout Home / Workout tab)
2. `stitch_saman_workout_EL_design` → Screen 02 (Exercise Library)
3. `stitch_saman_workout_Active-Workout_design` → Actually Screen 03 (Exercise Detail: Dumbbell Bench Press)!
4. `stitch_saman_workout_tab_design` → Actually Screen 05 (Live Form Check: Wide Grip Pull-up)
5. `stitch_saman_workout_livet_design` → Screen 05 (Live Form Check: Wide Grip Pull-up)

**None** of the 5 folders in `C:\Users\Administrator\Downloads\workout-screen` or `C:\Users\Administrator\Downloads` contain the actual export for Screen 04: **Active Workout Execution Screen**.

In accordance with repository safety rules (`AGENTS.md`) and task instructions:
- We **do NOT fabricate or synthesize fake HTML or fake screenshots** for missing screens.
- We report Screen 04 as **BLOCKED / Missing Assets** until the export (HTML + screenshot) is exported from Stitch.

---

## Required Design Specifications for Active Workout (from PRD Section 4.4 & FORM-CHECK-NOTES.md)

When the export is obtained, it must satisfy these verified criteria:

### 1. Viewport & Navigation Mode
- **Suppressed Global Navigation**: The global 5-tab bottom navigation bar MUST BE HIDDEN during active workout execution to prevent accidental exits during lifting.
- **Top Bar**:
  - Discreet minimize chevron (`expand_more` / back) to pause or background the session safely.
  - Title: Session name (e.g., `Upper Body Strength`).
  - Live chronometer: Elapsed time (e.g., `18:42` with quiet emerald pulse).
  - Top-right action: `Finish` button.

### 2. Operational Contracts & Action Rules
- **"Finish" Action**: Tapping `Finish` opens **Workout Review & Save**; it NEVER silently marks the workout completed or automatically commits it to History.
- **"Pause Workout" Action**: Pauses the session timer; does not finish, discard, or save.
- **Set Logging Contract**:
  - The active set row allows editing weight (kg) and reps.
  - Entering or adjusting kg/reps **does NOT** mark a set complete.
  - **`Log Set [N]`** (e.g., `Log Set 3`) at the bottom action dock is the **sole completion action** for that set.
  - Avoid a duplicate completion checkbox on the row.
- **Distinct Set States**:
  - Completed sets (e.g., Sets 1 & 2: `24 kg × 10`, `26 kg × 8` with emerald checkmark).
  - Active set (e.g., Set 3: `26 kg / 8 reps` with steppers).
  - Planned/upcoming sets (e.g., Set 4: `26 kg × 8 -` muted).
  - Mockup values are **illustrative examples**, not verified user history. Planned targets differ from recorded results.
- **Rest Interval Strip**:
  - Positioned above set logging so it never obstructs inputs.
  - Shows countdown (e.g., `REST 01:14`), `+30s`, and `Skip`.
- **Current Exercise Anchor**:
  - Photo of exercise in execution.
  - `Video Guide` affordance to review form cues without losing session state.
- **Form Check Entry (Future)**:
  - When supported by CV, `Check my form` can be offered beside guidance.
  - Opening or closing CV must NOT automatically log a set.
