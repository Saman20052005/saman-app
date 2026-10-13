# Screen Design Reference: 03 - Exercise Detail

## 1. Provenance & Identity
- **Screen Name**: Exercise Detail (Guidance: Dumbbell Bench Press)
- **Local Source**: `stitch_saman_workout_Active-Workout_design` (in `C:\Users\Administrator\Downloads\workout-screen` / `C:\Users\Administrator\Downloads`)
  - *Note on Source Folder Naming*: The local source folder was named `stitch_saman_workout_Active-Workout_design`, but comprehensive inspection of `code.html` (Title: *"Dumbbell Bench Press - Exercise Detail | Saman"*) and `screen.png` confirms that this asset bundle contains **Exercise Detail**, NOT Active Workout execution.
- **Stitch Export Files**:
  - Screenshot: [`screen.png`](./screen.png) (390 x 1283 px)
  - HTML Prototype: [`code.html`](./code.html) (16,419 bytes)
  - Spec Doc: [`saman_fitness_master_prd_design_specification_v2.8.md`](./saman_fitness_master_prd_design_specification_v2.8.md)
- **Role**: Movement instructional guide and preparation screen before starting or logging an exercise.

## 2. Visual Structure & Layout
- **Style**: Dark *Calm Athleticism* direction.
- **Header**:
  - Left: Back button (`<`) with text `Exercise Library`
  - Right: Category label in micro-caps `CHEST / PUSH`
- **Instructional Video Preview**:
  - 16:9 athletic photography asset of athlete performing dumbbell bench press on flat bench
  - Glass-obsidian circular play control
  - Top-left status pill badge: `• VIDEO GUIDE`
- **Movement Title & Taxonomy**:
  - Headline: `Dumbbell Bench Press`
  - Subtitle: `A chest exercise using dumbbells and a flat bench.`
  - Taxonomy Card:
    - `PRIMARY`: **Chest** (understated emerald highlight)
    - `SECONDARY`: **Triceps, Shoulders**
    - `EQUIPMENT`: **Dumbbells, Flat bench**
- **How to Perform (3 Phases)**:
  - Phase 1 `Setup`: *"Sit on the bench with a dumbbell in each hand. Lie back and place your feet firmly on the floor."*
  - Phase 2 `Lower`: *"Lower the dumbbells slowly to either side of your chest."*
  - Phase 3 `Press`: *"Push them up with control until your arms are extended."*
- **Form Cues**:
  - Emerald checkmark indicators:
    - *Keep your feet planted*
    - *Keep your wrists straight*
    - *Move slowly and stay in control*
- **Bottom Action**:
  - Floating CTA button: `Start exercise ->` (solid off-white `#F9FAFB`)
- **Global Navigation**:
  - 5-tab bar visible outside active session.

## 3. Important Design Contracts & Handoff Boundaries
- **Video Guide vs. Form Check**: The Video Guide demonstrates correct movement technique via instructional asset. Form Check observes the user's movement via camera. They are completely separate flows.
- **Start Exercise Action**: Exact entry behavior must be resolved before implementation: does tapping `Start exercise` start a new session, or add/select the movement in an already active workout?
- **Form Check Entry Boundary**: In the PRD, future `Check my form` belongs only on movements verified and supported by CV (first proposed: Wide Grip Pull-up). Do **not** expose CV Form Check on Dumbbell Bench Press simply because this visual guide screen uses Dumbbell Bench Press as an example.
