# Screen Design Reference: 01 - Workout Home / Workout Tab

## 1. Provenance & Identity
- **Screen Name**: Workout Home (Main Workout Tab Hub)
- **Local Source**: `stitch_saman_workout-home_design` (in `C:\Users\Administrator\Downloads\workout-screen` / `C:\Users\Administrator\Downloads`)
- **Stitch Export Files**:
  - Screenshot: [`screen.png`](./screen.png) (312 x 1014 px)
  - HTML Prototype: [`code.html`](./code.html) (17,346 bytes)
  - Spec Doc: [`saman_fitness_master_prd_design_specification_v2.6.md`](./saman_fitness_master_prd_design_specification_v2.6.md)
- **Role**: Primary entry point when selecting the **Workout** tab from the global 5-tab bar.

## 2. Visual Structure & Layout
- **Style**: Dark *Calm Athleticism* direction (obsidian canvas `#0C0D0E`, surface cards `#16171B`, 1px graphite hairline borders `#26282F`, off-white text `#F9FAFB`, muted text `#9CA3AF`).
- **Header**:
  - Title: `Workout` (`Space Grotesk`, Semibold)
  - Subtitle: `Train, log & explore movements` (`Inter`, muted)
  - Secondary Action: `My Plans` (pill button with bookmark icon)
- **Today's Scheduled Session (Hero Card)**:
  - Status pill: Understated green `Planned` chip (`#10B981` tint)
  - Hero image: Authentic strength training documentary photograph
  - Protocol & Title: `Upper Body Protocol` / `Upper Body Strength`
  - Metrics: `50 min • 5 exercises`
  - Primary CTA: Solid off-white (`#F9FAFB`) button `Start workout`
  - Secondary CTA: Ghost button `View plan >`
- **Quick Action Matrix**:
  - `Quick start` (`Train without a plan`)
  - `Browse library` (`Explore exercises`)
- **Train by Focus (Photo-led Category Cards)**:
  - `Upper Body` (Chest, Back, Arms)
  - `Lower Body` (Quads, Glutes, Legs)
  - *Policy*: Movement-based entry cards open to all athletes; zero gender locking.
- **Your Plan (Forward Horizon)**:
  - Minimal preview of upcoming days (e.g., `Lower Body Strength`, `Active Recovery`).
- **Last Workout & History**:
  - Most recent completed session card (e.g., `Leg Day & Posterior Chain • Yesterday • 48 min • 5 exercises`)
  - Link to `View history >`
- **Global Navigation**:
  - 5-tab bar: `Home` / `Workout (Active)` / `Saman` / `Nutrition` / `Profile`.

## 3. Important Design Contracts & Handoff Boundaries
- The scheduled session hero and "Last workout" details are **illustrative mockup values**.
- "Planned" status is not a completed workout.
- Tapping `Start workout` or `Quick start` routes to Active Workout; `Browse library` routes to Exercise Library.
