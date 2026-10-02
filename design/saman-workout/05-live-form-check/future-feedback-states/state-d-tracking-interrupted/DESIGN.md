# Design Reference: State D — Tracking Interrupted

## Provenance
- **Source Folder**: `stitch_saman_workout-4_design`  
  (`C:\Users\Administrator\Downloads\stitch_saman_workout-4_design`)
- **Files**:
  - [`screen.png`](screen.png) — 706 × 1600 px, MD5: `0BC118735235EA47BF176C77EAF073BE`
  - [`code.html`](code.html) — 8,494 bytes, MD5: `EB854D54CFA8AE04D5D9998F1CF40EBE`
  - [`saman_fitness_master_prd_design_specification_v3.6.txt`](saman_fitness_master_prd_design_specification_v3.6.txt)

## State Identity
| Element | Value |
| :--- | :--- |
| Header badge | `● TRACKING PAUSED` (amber `#F59E0B`) |
| Framing badge | `Tracking paused — subject out of view` (amber border) |
| Camera view | Dimmed/blurred overlay — athlete partially out of frame |
| Rep counter | `4 REPS HELD [FROZEN]` — `OBSERVATION PAUSED` |
| Feedback card label | `PLACEMENT GUIDANCE` |
| Feedback card icon | `person_search` icon (amber) |
| Feedback card cue | *"Tracking paused — move back until your full body and the bar are visible."* |
| Primary CTA | `End form check` |
| Secondary CTA | `Resume camera` *(replaces "Pause camera" from active states)* |

## Design Contracts
- **Deferred feature**: Part of future Live Form Check CV implementation.
- This state fires when the athlete's body or the pull-up bar exits the camera frame, making reliable pose estimation impossible.
- **Rep count is frozen**: `4 REPS HELD [FROZEN]`. No increment, no decrement. The system makes no form judgment while tracking is paused.
- **No form assessment**: No correction, positive confirmation, or between-reps coaching cues appear in this state. Only placement guidance is shown.
- Camera view uses a dim/blur overlay to visually distinguish the non-active tracking state from active observation.
- The secondary action changes from `Pause camera` → `Resume camera`, making it clear the athlete needs to reposition before tracking resumes.
- On returning to frame: CV re-establishes tracking and resumes from the held rep count.
- Plain guidance language only — no invented confidence percentages, medical claims, or exact required distances.
