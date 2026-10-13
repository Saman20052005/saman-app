# Saman Workout — Design Handoff Manifest (Post-CP0 Intake)

## 1. Executive Summary & Status

- **Checkpoint**: CP0 — DESIGN INTAKE
- **Repository Root**: `D:\SamanDev\workspace\saman-app-redesign`
- **Branch**: `feature/workout-redesign-v2`
- **Baseline HEAD**: `3ccfc6100887cb6b8211decf65fdc50a2667dbb2`
- **Design Target**: `design/saman-workout/`
- **Intake Sources (6 Folders)**:
  1. `D:\design\screen-workout\stitch_saman_workout_home-scren_design` -> Screen 01: Workout Home
  2. `D:\design\screen-workout\stitch_saman_workout_Lbry-screen_design` -> Screen 02: Exercise Library
  3. `D:\design\screen-workout\stitch_saman_workout_active_design` -> Screen 03: Exercise Detail (Dumbbell Bench Press)
  4. `D:\design\screen-workout\stitch_saman_workout_active_in_design` -> Screen 04: Active Workout Session (**UNBLOCKED / COMPLETE**)
  5. `D:\design\screen-workout\stitch_saman_workout_live_design` -> Screen 05: Live Form Check (Wide Grip Pull-up)
  6. `D:\design\screen-workout\stitch_saman_workout_feadback-live_design` -> Future Real-Time Form Check Feedback States (States A, B, C, D)

---

## 2. Screen Inventory & Classification Mapping

| Target Screen | Local Source Path (`D:\design\screen-workout\...`) | Destination Folder (Repo) | Selected Artifacts & Basis | File Status | Redesign Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **01. Workout Home / Workout tab** | `stitch_saman_workout_home-scren_design` | [`01-workout-home/`](./01-workout-home/) | Stitch export HTML (17,346 B) + `screen.png` (312x1014 px) + PRD v4.1 & v2.6 + `DESIGN.md`. Hero card, focus categories, quick actions, and 5-tab bar. | **Complete** | Design Reference |
| **02. Exercise Library** | `stitch_saman_workout_Lbry-screen_design` | [`02-exercise-library/`](./02-exercise-library/) | Stitch export HTML (16,404 B) + `screen.png` (312x733 px) + PRD v4.0 & v2.7 + `DESIGN.md`. Search bar, taxonomy tabs, filter chips, movement rows. | **Complete** | Design Reference |
| **03. Exercise Detail** | `stitch_saman_workout_active_design` | [`03-exercise-detail/`](./03-exercise-detail/) | Stitch export HTML (16,419 B) + primary `screen.png` (390x1283 px) + alternate `screen-v4.2-350w.png` (350x1154 px) + PRD v4.2 & v2.8 + `DESIGN.md`. Dumbbell Bench Press, 3 phases, cues, mistakes. | **Complete** | Design Reference |
| **04. Active Workout Session** | `stitch_saman_workout_active_in_design` | [`04-active-workout/`](./04-active-workout/) | **UNBLOCKED**: Authentic Stitch export HTML (`code.html`, 17,473 B) + `screen.png` (598x1600 px) + PRD v4.3 + `DESIGN.md` + historical stub `code.reconstructed.html` retained. In-session chrome, timer, set table, steppers, compact rest strip, up-next queue, `Log Set` CTA. | **Complete** | Ready for Implementation |
| **05. Live Form Check — Wide Grip Pull-up** | `stitch_saman_workout_live_design` | [`05-live-form-check/`](./05-live-form-check/) | Stitch export HTML (8,647 B) + `screen.png` (706x1600 px) + PRD v4.4 & v3.1/v3.2 + `DESIGN.md`. Real-time camera overlay, rep counter, form cue banner. | **Complete** | Design Reference (Deferred CV Flow) |
| **Workout Review & Save** | *None* | *N/A* | **MISSING**: No design export exists across all 6 source folders. PRD contract requires navigation to Review & Save when tapping `Finish` from Active Workout. | **MISSING** | Product Decision Required |

---

## 3. Comprehensive Pre-Copy & Intake File Mapping

| Source Folder & File | Actual Screen | Role | Origin & Provenance | Confidence | Destination Path in Repo | Action & Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `stitch_saman_workout_home-scren_design\code.html` | Screen 01: Workout Home | HTML Prototype | Genuine Stitch Export | High (100%) | `design/saman-workout/01-workout-home/code.html` | Exists in repo (CRLF identical text). Preserved. |
| `stitch_saman_workout_home-scren_design\screen.png` | Screen 01: Workout Home | Screenshot | Genuine Stitch Export | High (100%) | `design/saman-workout/01-workout-home/screen.png` | Exists in repo (SHA256 identical). Preserved. |
| `stitch_saman_workout_home-scren_design\saman_fitness_master_prd_...v4.1.txt` | Screen 01: Workout Home | PRD / Spec | Genuine Stitch Export | High (100%) | `design/saman-workout/01-workout-home/saman_fitness_master_prd_design_specification_v4.1.txt` & `briefs/` | Ingested into screen folder & `briefs/`. |
| `stitch_saman_workout_Lbry-screen_design\code.html` | Screen 02: Exercise Library | HTML Prototype | Genuine Stitch Export | High (100%) | `design/saman-workout/02-exercise-library/code.html` | Exists in repo (CRLF identical text). Preserved. |
| `stitch_saman_workout_Lbry-screen_design\screen.png` | Screen 02: Exercise Library | Screenshot | Genuine Stitch Export | High (100%) | `design/saman-workout/02-exercise-library/screen.png` | Exists in repo (SHA256 identical). Preserved. |
| `stitch_saman_workout_Lbry-screen_design\saman_fitness_master_prd_...v4.0.txt` | Screen 02: Exercise Library | PRD / Spec | Genuine Stitch Export | High (100%) | `design/saman-workout/02-exercise-library/saman_fitness_master_prd_design_specification_v4.0.txt` & `briefs/` | Ingested into screen folder & `briefs/`. |
| `stitch_saman_workout_active_design\code.html` | Screen 03: Exercise Detail | HTML Prototype | Genuine Stitch Export | High (100%) | `design/saman-workout/03-exercise-detail/code.html` | Exists in repo (CRLF identical text). Preserved. |
| `stitch_saman_workout_active_design\screen.png` | Screen 03: Exercise Detail | Screenshot (350w) | Genuine Stitch Export | High (100%) | `design/saman-workout/03-exercise-detail/screen-v4.2-350w.png` | Different resolution (350x1154) from existing (390x1283). Saved under distinct name; no silent overwrite. |
| `stitch_saman_workout_active_design\saman_fitness_master_prd_...v4.2.txt` | Screen 03: Exercise Detail | PRD / Spec | Genuine Stitch Export | High (100%) | `design/saman-workout/03-exercise-detail/saman_fitness_master_prd_design_specification_v4.2.txt` & `briefs/` | Ingested into screen folder & `briefs/`. |
| `stitch_saman_workout_active_in_design\code.html` | Screen 04: Active Workout | HTML Prototype | Genuine Stitch Export | High (100%) | `design/saman-workout/04-active-workout/code.html` | **NEW INGEST**: Real Stitch export added. Reconstructed 0-byte file preserved as `code.reconstructed.html`. |
| `stitch_saman_workout_active_in_design\screen.png` | Screen 04: Active Workout | Screenshot | Genuine Stitch Export | High (100%) | `design/saman-workout/04-active-workout/screen.png` | Exists in repo (SHA256 identical: `4296040F...`). Preserved. |
| `stitch_saman_workout_active_in_design\saman_fitness_master_prd_...v4.3.txt` | Screen 04: Active Workout | PRD / Spec | Genuine Stitch Export | High (100%) | `design/saman-workout/04-active-workout/saman_fitness_master_prd_design_specification_v4.3.txt` & `briefs/` | Ingested into screen folder & `briefs/`. |
| `stitch_saman_workout_live_design\code.html` | Screen 05: Live Form Check | HTML Prototype | Genuine Stitch Export | High (100%) | `design/saman-workout/05-live-form-check/code.html` | Exists in repo (CRLF identical text). Preserved. |
| `stitch_saman_workout_live_design\screen.png` | Screen 05: Live Form Check | Screenshot | Genuine Stitch Export | High (100%) | `design/saman-workout/05-live-form-check/screen.png` | Exists in repo (SHA256 identical). Preserved. |
| `stitch_saman_workout_live_design\saman_fitness_master_prd_...v4.4.txt` | Screen 05: Live Form Check | PRD / Spec | Genuine Stitch Export | High (100%) | `design/saman-workout/05-live-form-check/saman_fitness_master_prd_design_specification_v4.4.txt` & `briefs/` | Ingested into screen folder & `briefs/`. |
| `feadback-live\stitch_saman_workout_1_design\*` | State A: Form Correction | HTML, PNG, PRD | Genuine Stitch Export | High (100%) | `05-live-form-check/future-feedback-states/state-a-form-correction/` | HTML & PNG identical to existing. PRD v4.5 ingested into folder & `briefs/`. |
| `feadback-live\stitch_saman_workout_2_design\*` | State B: Positive Confirmation | HTML, PNG, PRD | Genuine Stitch Export | High (100%) | `05-live-form-check/future-feedback-states/state-b-positive-confirmation/` | HTML & PNG identical to existing. PRD v4.6 ingested into folder & `briefs/`. |
| `feadback-live\stitch_saman_workout_3_design\*` | State C: Between Reps | HTML, PNG, PRD | Genuine Stitch Export | High (100%) | `05-live-form-check/future-feedback-states/state-c-between-reps/` | HTML & PNG identical to existing. PRD v4.7 ingested into folder & `briefs/`. |
| `feadback-live\stitch_saman_workout_4_design\*` | State D: Tracking Interrupted | HTML, PNG, PRD | Genuine Stitch Export | High (100%) | `05-live-form-check/future-feedback-states/state-d-tracking-interrupted/` | HTML & PNG identical to existing. PRD v4.8 ingested into folder & `briefs/`. |

---

## 4. Deferred Feedback State Variants (Future Reference Only)

> **DEFERRED from active redesign checkpoint** — packaged as design reference only; not a current implementation requirement.

| State | Source Folder | Destination Subfolder | Screenshot | HTML | PRD | Role |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| **State A — Form Correction** | `stitch_saman_workout_1_design` | `state-a-form-correction/` | 706x1600 px | 8,173 B | v4.5 | "Keep shoulders down on next rep" banner |
| **State B — Positive Confirmation** | `stitch_saman_workout_2_design` | `state-b-positive-confirmation/` | 706x1600 px | 7,884 B | v4.6 | "Good rep - chin cleared the bar" confirmation |
| **State C — Between Reps** | `stitch_saman_workout_3_design` | `state-c-between-reps/` | 706x1600 px | 7,886 B | v4.7 | "Lower with control before next pull" pacing |
| **State D — Tracking Interrupted** | `stitch_saman_workout_4_design` | `state-d-tracking-interrupted/` | 706x1600 px | 8,494 B | v4.8 | "Subject out of view / move back" guidance |

---

## 5. Product Rules & Design Contracts Enforced

1. **Design Reference Only**: All mockups, screenshots, and HTML prototypes are static design references. They do **not** constitute proof of running functionality, live backend APIs, or real personal workout records.
2. **Active Workout Set Logging Contract**:
   - Typing or adjusting kg/reps on an active row **does NOT** mark a set as complete.
   - **`Log Set [N]`** is the **sole completion action** for logging that set.
   - Avoid duplicate completion checkboxes on active rows.
3. **Finish & History Contract**:
   - Tapping **`Finish`** opens **Workout Review & Save**.
   - It **never** silently completes or commits a session to History. Only explicit confirmation on the review screen commits the session into History.
4. **Mockup Values vs. Reality**:
   - Numbers shown in screenshots (durations, session counts, exercise history, target loads) are **illustrative examples**.
   - Planned targets (e.g., `Target: 26 kg x 8`) must remain visibly distinct from recorded results.
5. **Video Guide vs. Form Check**:
   - **Video Guide**: Pre-recorded instructional demonstration of proper technique.
   - **Form Check**: Real-time camera observing the athlete's movement. They are distinct flows.
6. **Live Form Check Scope**:
   - Live Form Check is a **future CV feature**, NOT implemented in the current Workout redesign checkpoint.
   - **`Reps observed`** (e.g., `4 reps observed`) is a transient CV metric, NOT an auto-logged set.
   - Ending or closing Form Check returns to the caller without silently logging a set or saving a workout.
7. **Speaker / Audio Icon Policy**:
   - The top-right speaker icon indicates spoken voice coaching cues.
   - Implement only if audio feedback is formally approved in product scope; otherwise omit.