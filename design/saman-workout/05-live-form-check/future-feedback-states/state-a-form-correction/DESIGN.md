# Design Reference: State A — Form Correction

## Provenance
- **Source Folder**: `stitch_saman_workout-1_design`  
  (`C:\Users\Administrator\Downloads\stitch_saman_workout-1_design`)
- **Files**:
  - [`screen.png`](screen.png) — 706 × 1600 px, MD5: `B33765C93543438B2516178F7F622662`
  - [`code.html`](code.html) — 8,173 bytes, MD5: `10E151CC5F803CF27F2CB4E8FD79630D`
  - [`saman_fitness_master_prd_design_specification_v3.3.txt`](saman_fitness_master_prd_design_specification_v3.3.txt)

## State Identity
| Element | Value |
| :--- | :--- |
| Header badge | `● FORM CHECK` (emerald) |
| Rep counter | `4 REPS OBSERVED` — `LIVE OBSERVATION` |
| Feedback card label | `ADJUST FORM • Form adjustment` |
| Feedback card icon | Downward arrow (amber `#F59E0B`) |
| Feedback card cue | *"Keep your shoulders down on the next rep."* |
| Primary CTA | `End form check` |
| Secondary CTA | `Pause camera` |

## Design Contracts
- **Deferred feature**: Part of future Live Form Check CV implementation.
- This state fires when CV detects a form deviation in the current rep.
- The amber downward-arrow card replaces any prior positive or between-reps card; exactly one card at a time.
- The correction cue is a single, actionable sentence — no multi-sentence paragraphs, no injury claims, no blame language.
- The rep count (`4`) is NOT incremented on correction cues; a rep is only considered observed when correctly completed.
- No audio feedback assumed from this mockup alone.
