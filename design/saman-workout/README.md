# Saman Workout — Approved Design Handoff

## Source of Truth Priority

1. **Packaged Screenshots in Screen Folders** (`screen.png`)
   - Final visual reference for layout, hierarchy, spacing, density, and typography.
   - Use for exact visual alignment.
2. **Stitch Design Specifications & PRD** (`briefs/`, screen `DESIGN.md`)
   - Structured layout information, typography scale, component design system, and rationale.
3. **Existing Flutter Code**
   - Source of truth for functionality, state management (Riverpod), navigation routes, models, and business logic.
4. **HTML Prototypes** (`code.html`)
   - Visual/layout reference only.
   - **Do NOT** copy-paste or treat generated Tailwind HTML as production code.

---

## Screen Directory Structure

```
design/saman-workout/
├── 01-workout-home/       # Workout Tab / Main Operational Hub
│   ├── screen.png
│   ├── code.html
│   ├── saman_fitness_master_prd_design_specification_v2.6.md
│   └── DESIGN.md
├── 02-exercise-library/   # Exercise Discovery & Filtering Subpage
│   ├── screen.png
│   ├── code.html
│   ├── saman_fitness_master_prd_design_specification_v2.7.txt
│   └── DESIGN.md
├── 03-exercise-detail/    # Exercise Guidance (Dumbbell Bench Press)
│   ├── screen.png
│   ├── code.html
│   ├── saman_fitness_master_prd_design_specification_v2.8.md
│   └── DESIGN.md
├── 04-active-workout/     # In-Session Active Workout (BLOCKED / Missing)
│   └── README.md
├── 05-live-form-check/    # Future CV Tracking (Wide Grip Pull-up)
│   ├── screen.png
│   ├── code.html
│   ├── saman_fitness_master_prd_design_specification_v3.2.txt
│   ├── saman_fitness_master_prd_design_specification_v3.1.txt
│   └── DESIGN.md
├── briefs/                # PRD Specification Archive (v2.6 - v3.2)
│   ├── INDEX.md
│   └── ...
├── FORM-CHECK-NOTES.md    # Reviewed screens and implementation handoff boundaries
├── MANIFEST.md            # Inventory, versioning basis, and operational rules
└── README.md              # This document
```

---

## Non-Negotiable Operational Rules

1. **Active Workout**:
   - Editing kg/reps does NOT complete a set.
   - `Log Set [N]` is the sole completion action.
   - `Finish` opens Review & Save; only explicit confirmation commits to History.
2. **Mockup Data**:
   - Values in mockups are illustrative. Planned targets are distinct from recorded results.
3. **Guidance vs. Tracking**:
   - `Video Guide` = pre-recorded instructional demonstration.
   - `Live Form Check` = real-time camera tracking.
4. **Live Form Check**:
   - Future CV design pass; not implemented in current redesign checkpoint.
   - `Reps observed` is an optical metric, not an auto-logged set.
   - Real-time notification states (correction, positive, reminder, tracking interrupted) are deferred.
