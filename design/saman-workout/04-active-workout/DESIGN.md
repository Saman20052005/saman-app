# Screen Design Reference: 04 - Active Workout Session

## 1. Provenance & Identity
- **Screen Name**: Active Workout Session (In-Session Workout Tracker)
- **Local Source**: `stitch_saman_workout_active_in_design` (in `D:\design\screen-workout\stitch_saman_workout_active_in_design`)
- **Stitch Export Files**:
  - Screenshot: [`screen.png`](./screen.png) (598 x 1600 px)
  - HTML Prototype: [`code.html`](./code.html) (17,473 bytes)
  - Spec Doc: [`saman_fitness_master_prd_design_specification_v4.3.txt`](./saman_fitness_master_prd_design_specification_v4.3.txt) (25,596 bytes)
  - Historical Reconstructed Stub: [`code.reconstructed.html`](./code.reconstructed.html) (retained as reference)
- **Role**: Dedicated full-screen active logging environment when an athlete starts a scheduled or ad-hoc workout.

## 2. Visual Structure & Layout
- **Style**: Dark *Calm Athleticism* direction (obsidian canvas `#0C0D0E`, card `#16171B`, elevated `#1F2126`, active card `#1E2026`, border `#26282F`, emerald accent `#10B981`).
- **Global Chrome Suppression**: The global 5-tab bottom navigation bar is completely hidden. Full immersion.
- **Top Bar (Sticky In-Session Chrome)**:
  - Left: Minimize chevron (`expand_more` icon) to pause/background session safely.
  - Center: Session Title (`Upper Body Strength`) + Live Elapsed Chronometer (`18:42` with emerald pulsing dot).
  - Right: `Finish` button pill (`#16171B` bg, `#F9FAFB` text).
- **Horizon Progress Bar**:
  - Subheaders: `Exercise 1 of 5` (left), `2 of 4 sets completed` (emerald, right).
  - 5-segment horizon bar (1st segment half emerald filled, remaining 4 muted).
- **Current Exercise Anchor**:
  - Image card (athlete documentary photograph, 176px height) with bottom gradient overlay.
  - Floating `Video Guide` button (play icon, blurred translucent background).
  - Exercise Title: `Dumbbell Bench Press` (20px Space Grotesk semibold).
  - Equipment & Setup: `Dumbbells • Flat bench` (12px zinc muted).
- **Compact Rest Strip**:
  - Elevated card with emerald circular timer glyph (`18px stroke`).
  - Rest label & countdown: `REST 01:14`.
  - Secondary Quick Adjust: `+30s` button.
  - Skip CTA: `Skip` pill button (emerald tint).
- **Scannable Set List Table**:
  - Header columns: `SET` (col-2), `KG` (col-4), `REPS` (col-3), `STATUS` (col-3).
  - Completed Set rows (Sets 1 & 2): 24 kg x 10, 26 kg x 8 with checkmark circle.
  - Active Target Set (Set 3): Elevated container (`#1E2026`), pulsating dot, `SET 3 (ACTIVE)`, `TARGET: 26 KG x 8`, interactive stepper inputs (`- 26 kg +`, `- 8 reps +`).
  - Upcoming Set (Set 4): Muted row (`26 kg x 8 -`), 50% opacity.
  - `Add set` trigger: dashed border button.
- **Up Next Queue**:
  - `Up Next` header with `View all 5 exercises >`.
  - Next exercise card: `Lat Pulldown (Wide Grip)` | `4 sets • Cable Machine`.
- **In-Session Footer Dock**:
  - Primary Action: Solid off-white CTA `Log Set 3` (check icon, 48px height, full-width).
  - Sub-action: Text button `Pause workout` with pause icon.

## 3. Product & Interaction Contracts
1. **Set Logging Contract**: Adjusting steppers modifies values in memory; tapping **`Log Set [N]`** is the SOLE action that completes the active set.
2. **Finish Contract**: Tapping `Finish` triggers navigation to **Workout Review & Save**; it NEVER commits directly to history without review.
3. **No Global Tab Bar**: Navigation rail / tab bar is suppressed to prevent accidental exits.