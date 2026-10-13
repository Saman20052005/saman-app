# Design Reference: State C — Between Reps

## Provenance
- **Source Folder**: `stitch_saman_workout-3_design`  
  (`C:\Users\Administrator\Downloads\stitch_saman_workout-3_design`)
- **Files**:
  - [`screen.png`](screen.png) — 706 × 1600 px, MD5: `6BD24BEC24D642788AEDC44DBC8FE8C5`
  - [`code.html`](code.html) — 7,886 bytes, MD5: `FFA3E16E3AC7B1F317B3279E3F1AB052`
  - [`saman_fitness_master_prd_design_specification_v3.5.txt`](saman_fitness_master_prd_design_specification_v3.5.txt)

## State Identity
| Element | Value |
| :--- | :--- |
| Header badge | `● TRACKING` (emerald) |
| Rep counter | `4 REPS OBSERVED` — `LIVE OBSERVATION` *(held, not incremented)* |
| Feedback card label | `BETWEEN REPS` |
| Feedback card icon | Clock / schedule icon (neutral surface) |
| Feedback card cue | *"Lower with control before your next pull."* |
| Primary CTA | `End form check` |
| Secondary CTA | `Pause camera` |

## Design Contracts
- **Deferred feature**: Part of future Live Form Check CV implementation.
- This state fires during the eccentric (lowering) phase between detected reps.
- Rep counter is held steady at `4`; no increment occurs during the lowering/eccentric phase.
- The neutral dark card communicates a coaching cue for the downward movement — calm, not alarming.
- This is a rest-phase coaching state between reps, distinct from State A (active correction mid-rep) and State B (rep completion confirmation).
- No audio feedback assumed from this mockup alone.
