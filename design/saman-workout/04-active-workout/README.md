# Screen Design Reference: 04 - Active Workout Session

## Status: COMPLETE / UNBLOCKED (Acquired from `stitch_saman_workout_active_in_design`)

### Provenance & Export Artifacts
In the previous intake batch, Screen 04 was missing. In the CP0 intake batch from `D:\design\screen-workout\stitch_saman_workout_active_in_design`, the authentic Stitch export was verified and ingested:
- `code.html`: 17,473 bytes (Stitch export prototype HTML)
- `screen.png`: 347,032 bytes (598 x 1600 px screenshot, SHA256: `4296040F6A7766D957C925FB8E1B76206A8348DCA4601DA60D786B539652060D`)
- `saman_fitness_master_prd_design_specification_v4.3.txt`: 25,596 bytes
- `code.reconstructed.html`: Retained as 0-byte historical stub
- `DESIGN.md`: Structural design reference document

---

## Design Specifications for Active Workout (from PRD & Stitch Prototype)

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
  - The active set row allows editing weight (kg) and reps via steppers.
  - Entering or adjusting kg/reps **does NOT** mark a set complete.
  - **`Log Set [N]`** (e.g., `Log Set 3`) at the bottom action dock is the **sole completion action** for that set.
  - Avoid a duplicate completion checkbox on the row.
- **Distinct Set States**:
  - Completed sets (e.g., Sets 1 & 2: `24 kg x 10`, `26 kg x 8` with emerald checkmark).
  - Active set (e.g., Set 3: `26 kg / 8 reps` with steppers in elevated `#1E2026` container).
  - Planned/upcoming sets (e.g., Set 4: `26 kg x 8 -` muted).
- **Rest Interval Strip**:
  - Positioned above set logging so it never obstructs inputs.
  - Shows circular countdown (`REST 01:14`), `+30s`, and `Skip`.
- **Current Exercise Anchor**:
  - Photo of exercise in execution.
  - `Video Guide` affordance to review form cues without losing session state.
- **Up Next Queue**:
  - Shows subsequent exercise (e.g., `Lat Pulldown (Wide Grip)`) and `View all 5 exercises`.