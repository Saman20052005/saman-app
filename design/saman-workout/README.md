# Saman Workout — Approved Design Handoff

## Source of Truth Priority

1. **Packaged Screenshots in Screen Folders** (`screen.png`, `screen-v4.2-350w.png`)
   - Final visual reference for layout, hierarchy, spacing, density, and typography.
   - Use for exact visual alignment.
2. **Stitch Design Specifications & PRD** (`briefs/`, screen `DESIGN.md`)
   - Structured layout information, typography scale, component design system, and rationale.
3. **Existing Flutter Code**
   - Source of truth for functionality, state management (Riverpod), navigation routes, models, and business logic.
4. **HTML Prototypes** (`code.html`)
   - Visual/layout reference only.
   - **Do NOT** copy-paste or treat generated Tailwind HTML as production code.
5. **Historical Reconstructed Files** (`code.reconstructed.html`)
   - Historical stubs retained for provenance/traceability; not authentic Stitch export code.

---

## Screen Directory Structure

```text
design/saman-workout/
|-- 01-workout-home/       # Screen 01: Workout Tab / Main Operational Hub
|   |-- screen.png
|   |-- code.html
|   |-- saman_fitness_master_prd_design_specification_v2.6.md
|   |-- saman_fitness_master_prd_design_specification_v4.1.txt
|   `-- DESIGN.md
|-- 02-exercise-library/   # Screen 02: Exercise Discovery & Filtering Subpage
|   |-- screen.png
|   |-- code.html
|   |-- saman_fitness_master_prd_design_specification_v2.7.txt
|   |-- saman_fitness_master_prd_design_specification_v4.0.txt
|   `-- DESIGN.md
|-- 03-exercise-detail/    # Screen 03: Exercise Guidance (Dumbbell Bench Press)
|   |-- screen.png (390x1283 px primary)
|   |-- screen-v4.2-350w.png (350x1154 px authentic Stitch export)
|   |-- code.html
|   |-- saman_fitness_master_prd_design_specification_v2.8.md
|   |-- saman_fitness_master_prd_design_specification_v4.2.txt
|   `-- DESIGN.md
|-- 04-active-workout/     # Screen 04: In-Session Active Workout (COMPLETE / UNBLOCKED)
|   |-- screen.png (598x1600 px)
|   |-- code.html (authentic Stitch export, 17,473 B)
|   |-- code.reconstructed.html (0-byte historical stub retained for reference)
|   |-- saman_fitness_master_prd_design_specification_v3.7.txt
|   |-- saman_fitness_master_prd_design_specification_v4.3.txt
|   |-- DESIGN.md
|   `-- README.md
|-- 05-live-form-check/    # Screen 05: Future CV Tracking (Wide Grip Pull-up) - Deferred Reference
|   |-- screen.png (706x1600 px)
|   |-- code.html (8,647 B)
|   |-- saman_fitness_master_prd_design_specification_v3.1.txt
|   |-- saman_fitness_master_prd_design_specification_v3.2.txt
|   |-- saman_fitness_master_prd_design_specification_v4.4.txt
|   |-- DESIGN.md
|   `-- future-feedback-states/  # Deferred real-time feedback states (States A, B, C, D)
|       |-- state-a-form-correction/
|       |-- state-b-positive-confirmation/
|       |-- state-c-between-reps/
|       |-- state-d-tracking-interrupted/
|       `-- README.md
|-- briefs/                # PRD Specification Archive (v2.6 - v4.8)
|   |-- INDEX.md
|   `-- saman_fitness_master_prd_design_specification_v*.txt
|-- [MISSING] Workout Review & Save  # No design export exists across 6 sources; PRD requires navigation on Finish
|-- FORM-CHECK-NOTES.md    # Reviewed screens and implementation handoff boundaries
|-- MANIFEST.md            # Inventory, versioning basis, and operational rules
`-- README.md              # This document
```

---

## Screen Inventory Summary

| Screen / Flow | Directory / Artifact | Export Source | Status | Implementation Role |
| :--- | :--- | :--- | :--- | :--- |
| **01. Workout Home** | [`01-workout-home/`](./01-workout-home/) | `stitch_saman_workout_home-scren_design` | **Complete** | Primary Workout Tab Hub |
| **02. Exercise Library** | [`02-exercise-library/`](./02-exercise-library/) | `stitch_saman_workout_Lbry-screen_design` | **Complete** | Exercise Discovery & Search |
| **03. Exercise Detail** | [`03-exercise-detail/`](./03-exercise-detail/) | `stitch_saman_workout_active_design` | **Complete** | Movement Guidance (Dumbbell Bench Press) |
| **04. Active Workout** | [`04-active-workout/`](./04-active-workout/) | `stitch_saman_workout_active_in_design` | **Complete** | Active In-Session Tracker |
| **Workout Review & Save** | *None* | *None across 6 source folders* | **MISSING** | Required by PRD upon `Finish`; needs UI design |
| **05. Live Form Check** | [`05-live-form-check/`](./05-live-form-check/) | `stitch_saman_workout_live_design` | **Complete** | Reference Only (Deferred CV Flow) |
| **Feedback States (A-D)** | [`future-feedback-states/`](./05-live-form-check/future-feedback-states/) | `stitch_saman_workout_feadback-live_design` | **Complete** | Reference Only (Deferred CV Flow) |

---

## Non-Negotiable Operational Rules

1. **Active Workout**:
   - Editing kg/reps does NOT mark a set complete.
   - `Log Set [N]` is the sole completion action for that set.
   - `Finish` opens Workout Review & Save; only explicit confirmation on the review screen commits to History.
2. **Mockup Data**:
   - Values in mockups are illustrative. Planned targets are distinct from recorded results.
3. **Guidance vs. Tracking**:
   - `Video Guide` = pre-recorded instructional demonstration.
   - `Live Form Check` = real-time camera tracking.
4. **Live Form Check**:
   - Future CV design pass; not implemented in current Workout redesign checkpoint.
   - `Reps observed` is an optical metric, not an auto-logged set.
   - Real-time notification states (correction, positive, reminder, tracking interrupted) are deferred.