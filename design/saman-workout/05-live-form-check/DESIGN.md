# Screen Design Reference: 05 - Live Form Check â€” Wide Grip Pull-up

## 1. Provenance & Identity
- **Screen Name**: Live Form Check (Wide Grip Pull-up)
- **Local Sources**:
  - Primary source: `stitch_saman_workout_livet_design` (in `C:\Users\Administrator\Downloads\workout-screen` / `C:\Users\Administrator\Downloads`)
  - Duplicate source: `stitch_saman_workout_tab_design`
  - *Verification*: Both sources contain bit-for-bit identical `code.html` (MD5: `626C75F4B6C9710A6DF54C546C6400F1`) and `screen.png` (MD5: `82909AF63BC779ABD330CB14E3A22D26`, 706 x 1600 px).
- **Stitch Export Files**:
  - Screenshot: [`screen.png`](./screen.png) (706 x 1600 px)
  - HTML Prototype: [`code.html`](./code.html) (8,647 bytes)
  - Spec Doc Selected: [`saman_fitness_master_prd_design_specification_v3.2.txt`](./saman_fitness_master_prd_design_specification_v3.2.txt) (latest version increment)
  - Alternate Candidate Spec: [`saman_fitness_master_prd_design_specification_v3.1.txt`](./saman_fitness_master_prd_design_specification_v3.1.txt) (retained for traceability)
- **Role**: Future Computer Vision optical tracking interface for real-time rep counting and single actionable posture cues during technical compound movements.

## 2. Visual Structure & Layout
- **Style**: Dark *Calm Athleticism* direction, edge-to-edge full-bleed camera UI.
- **Top Header**:
  - Left: Close button (`close` / `X`)
  - Center: Status pill `• FORM CHECK` + Title `Wide Grip Pull-up`
  - Right: Speaker / Audio toggle icon (`volume_up`)
- **Guidance & Framing**:
  - Framing instruction: `Keep your full body and the bar in view`
  - Tracking status badge: `• Full body in frame`
  - Camera view: Athlete in full body frame (hands to feet) on pull-up bar.
- **HUD Telemetry**:
  - Metric counter: `4 REPS OBSERVED` (tabular typography)
  - Actionable feedback card: Downward arrow icon + `Keep shoulders down as you pull`
- **Bottom Actions**:
  - Primary CTA: `End form check` (solid off-white `#F9FAFB`)
  - Secondary CTA: `|| Pause camera`
- **Global Navigation**:
  - Suppressed during camera session.

## 3. Important Design Contracts & Handoff Boundaries
1. **Future Feature Notice**: Live Form Check is a **future CV design pass**, NOT implemented in the current Workout redesign checkpoint.
2. **"Reps Observed" Contract**:
   - `4 reps observed` is a transient visual metric detected by CV.
   - It is **NEVER automatically recorded as a completed workout set**.
   - Ending or closing Form Check returns to Exercise Detail or Active Workout; the athlete explicitly confirms any logged volume.
3. **Speaker / Audio Icon Policy**:
   - The top-right speaker icon represents spoken form cues.
   - Keep and implement it **only if audio feedback is approved** in product scope. If audio is not in scope, remove the icon to avoid promising unavailable capabilities.
4. **Deferred Real-Time Notification Feedback States**:
   - The PRD specification describes 4 real-time notification states:
     - State A: Form Correction (`ADJUST FORM`)
     - State B: Positive Confirmation (`REP COMPLETE`)
     - State C: Between Reps Reminder (`BETWEEN REPS`)
     - State D: Tracking Interrupted (`CAMERA VIEW BLOCKED`)
   - **Status**: These 4 real-time state variants are **DEFERRED** from the active design package. Packaged as design references under [uture-feedback-states/](./future-feedback-states/) (States A, B, C, D).
