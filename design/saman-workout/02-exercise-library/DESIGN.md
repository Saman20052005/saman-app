# Screen Design Reference: 02 - Exercise Library

## 1. Provenance & Identity
- **Screen Name**: Exercise Library
- **Local Source**: `stitch_saman_workout_EL_design` (in `C:\Users\Administrator\Downloads\workout-screen` / `C:\Users\Administrator\Downloads`)
- **Stitch Export Files**:
  - Screenshot: [`screen.png`](file:///c:/SamanDev/saman-app/design/saman-workout/02-exercise-library/screen.png) (312 × 733 px)
  - HTML Prototype: [`code.html`](file:///c:/SamanDev/saman-app/design/saman-workout/02-exercise-library/code.html) (16,404 bytes)
  - Spec Doc: [`saman_fitness_master_prd_design_specification_v2.7.txt`](file:///c:/SamanDev/saman-app/design/saman-workout/02-exercise-library/saman_fitness_master_prd_design_specification_v2.7.txt)
- **Role**: Workout subpage for discovering, searching, and filtering exercises.

## 2. Visual Structure & Layout
- **Style**: Dark *Calm Athleticism* direction.
- **Header**:
  - Left: Back button (`chevron_left`) returning to Workout tab
  - Center/Left: `Exercise Library`
  - Right: Bookmark icon (`bookmarks`)
- **Search & Filters**:
  - Search bar: `Search exercises` with tune/filter icon
  - Primary category tabs: `All` | `Upper Body` (active chip with emerald indicator) | `Lower Body` | `Core`
  - Secondary muscle/equipment filter chips: `Chest` | `Back` | `Shoulders` | `Arms` | `Equipment v`
- **Movement List Rows (`MOVEMENTS`)**:
  - Photo thumbnail showing movement form and visible equipment
  - Title (e.g., `Dumbbell Bench Press`, `Lat Pulldown`, `Seated Cable Row`, `Dumbbell Shoulder Press`, `Push-Up`)
  - Metadata subtitle (e.g., `Chest • Dumbbell`, `Back • Cable Machine`)
  - Video guidance affordance: `Video guide` (`play_circle` icon)
  - Right-aligned chevron affordance
- **Global Navigation**:
  - Persistent 5-tab bar anchored with `Workout` tab active.

## 3. Important Design Contracts & Handoff Boundaries
- The screenshot illustrates an **Upper Body** entry state. Filter selections must agree with visible results.
- Selecting any movement row navigates to its **Exercise Detail** screen.
- Bookmark control behavior requires product confirmation (saved exercise action vs visual mockup affordance).
- "Video guide" pill indicates instructional demonstration availability, distinct from live camera Form Check.
