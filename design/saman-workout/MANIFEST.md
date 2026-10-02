# Saman Workout — Design Handoff Manifest

## 1. Screen Inventory & Classification Mapping

| Target Screen | Local Source Path (Downloads) | Destination Folder (Repo) | Selected Version & Basis | File Status | Implementation Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **01. Workout Home / Workout tab** | `stitch_saman_workout-home_design` | [`design/saman-workout/01-workout-home/`](file:///c:/SamanDev/saman-app/design/saman-workout/01-workout-home/) | HTML + `screen.png` + PRD v2.6. Exact match on title, hero card, focus categories, and 5-tab bar. | **Complete** (`screen.png`, `code.html`, `saman_fitness_master_prd_design_specification_v2.6.md`, `DESIGN.md`) | Design Reference |
| **02. Exercise Library** | `stitch_saman_workout_EL_design` | [`design/saman-workout/02-exercise-library/`](file:///c:/SamanDev/saman-app/design/saman-workout/02-exercise-library/) | HTML + `screen.png` + PRD v2.7. Exact match on search bar, category tabs, filter chips, movement rows. | **Complete** (`screen.png`, `code.html`, `saman_fitness_master_prd_design_specification_v2.7.txt`, `DESIGN.md`) | Design Reference |
| **03. Exercise Detail** | `stitch_saman_workout_Active-Workout_design` | [`design/saman-workout/03-exercise-detail/`](file:///c:/SamanDev/saman-app/design/saman-workout/03-exercise-detail/) | HTML + `screen.png` + PRD v2.8. Source folder was named `Active-Workout_design` but actual HTML & screenshot are 100% Exercise Detail (Dumbbell Bench Press: video preview, 3 phases, form cues, "Start exercise" CTA). | **Complete** (`screen.png`, `code.html`, `saman_fitness_master_prd_design_specification_v2.8.md`, `DESIGN.md`) | Design Reference |
| **04. Active Workout** | *None* (Missing from local download batch) | [`design/saman-workout/04-active-workout/`](file:///c:/SamanDev/saman-app/design/saman-workout/04-active-workout/) | **BLOCKED**: No export files found. The source named `Active-Workout_design` contained Screen 03 (Exercise Detail). No fake files created. | **Missing** (HTML and screenshot missing from local Downloads) | **BLOCKED** |
| **05. Live Form Check — Wide Grip Pull-up** | `stitch_saman_workout_livet_design` & `stitch_saman_workout_tab_design` | [`design/saman-workout/05-live-form-check/`](file:///c:/SamanDev/saman-app/design/saman-workout/05-live-form-check/) | Both sources contain identical HTML & `screen.png`. Selected `v3.2.txt` from `livet_design` as latest version increment; retained `v3.1.txt` as candidate record. | **Complete** (`screen.png`, `code.html`, `saman_fitness_master_prd_design_specification_v3.2.txt`, `saman_fitness_master_prd_design_specification_v3.1.txt`, `DESIGN.md`) | Design Reference (Future CV Flow) |

---

## 2. Deferred Design Elements — Feedback States (Now Packaged)

**Real-Time Form Check Feedback State Variants** — Four state variants of the Live Form Check screen.

> **DEFERRED from active redesign checkpoint** — packaged as design reference only; not a current implementation requirement.

| State | Source Folder | Destination | Screenshot | HTML | PRD | Status |
| :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| **State A — Form Correction** | `stitch_saman_workout-1_design` | [`05-live-form-check/future-feedback-states/state-a-form-correction/`](file:///c:/SamanDev/saman-app/design/saman-workout/05-live-form-check/future-feedback-states/state-a-form-correction/) | ✅ (706×1600) | ✅ (8,173 B) | v3.3 ✅ | Packaged |
| **State B — Positive Confirmation** | `stitch_saman_workout-2_design` | [`05-live-form-check/future-feedback-states/state-b-positive-confirmation/`](file:///c:/SamanDev/saman-app/design/saman-workout/05-live-form-check/future-feedback-states/state-b-positive-confirmation/) | ✅ (706×1600) | ✅ (7,884 B) | v3.4 ✅ | Packaged |
| **State C — Between Reps** | `stitch_saman_workout-3_design` | [`05-live-form-check/future-feedback-states/state-c-between-reps/`](file:///c:/SamanDev/saman-app/design/saman-workout/05-live-form-check/future-feedback-states/state-c-between-reps/) | ✅ (706×1600) | ✅ (7,886 B) | v3.5 ✅ | Packaged |
| **State D — Tracking Interrupted** | `stitch_saman_workout-4_design` | [`05-live-form-check/future-feedback-states/state-d-tracking-interrupted/`](file:///c:/SamanDev/saman-app/design/saman-workout/05-live-form-check/future-feedback-states/state-d-tracking-interrupted/) | ✅ (706×1600) | ✅ (8,494 B) | v3.6 ✅ | Packaged |

**Duplicates found**: None. All 4 sources have unique HTML and PNG hashes.

---


## 3. Product Rules & Design Contracts Enforced

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
   - Planned targets (e.g., `Target: 26 kg × 8`) must remain visibly distinct from recorded results.
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
