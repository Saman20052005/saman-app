# Live Form Check — Future Real-Time Feedback States

## Scope Notice

These four sub-screens are **state variants** of a **single** future Live Form Check screen (`05-live-form-check/`).

> **DEFERRED — not a requirement in the current Workout redesign checkpoint.**
> They represent the proposed visual direction for real-time optical CV feedback and must NOT be treated as approved for implementation until the broader Live Form Check feature is formally scheduled.

---

## Classification Table

| Source Folder (Downloads) | Actual State | Canonical State ID | Destination Folder | Screenshot | HTML | PRD Doc | Verdict |
| :--- | :--- | :--- | :--- | :---: | :---: | :---: | :--- |
| `stitch_saman_workout-1_design` | Form Correction cue (Amber/Adjust Form) | **State A** | [`state-a-form-correction/`](state-a-form-correction/) | ✅ | ✅ | v3.3 ✅ | **Confirmed** |
| `stitch_saman_workout-2_design` | Positive rep confirmation (Emerald/Rep Complete) | **State B** | [`state-b-positive-confirmation/`](state-b-positive-confirmation/) | ✅ | ✅ | v3.4 ✅ | **Confirmed** |
| `stitch_saman_workout-3_design` | Between-reps eccentric cue (Neutral/Between Reps) | **State C** | [`state-c-between-reps/`](state-c-between-reps/) | ✅ | ✅ | v3.5 ✅ | **Confirmed** |
| `stitch_saman_workout-4_design` | Tracking interrupted / subject out of view | **State D** | [`state-d-tracking-interrupted/`](state-d-tracking-interrupted/) | ✅ | ✅ | v3.6 ✅ | **Confirmed** |

**Duplicates found**: None. All 4 HTML and PNG files have unique MD5 hashes.

---

## Visual Evidence per State

### State A — Form Correction
- **Header status**: `● FORM CHECK` (emerald)
- **Rep counter**: `4 REPS OBSERVED • LIVE OBSERVATION`
- **Feedback card**: Amber border, downward-arrow icon, label `ADJUST FORM • Form adjustment`, cue text *"Keep your shoulders down on the next rep."*
- **Bottom actions**: `End form check` | `Pause camera`
- **HTML key text**: `arrow_downward Adjust Form Form adjustment Keep your shoulders down on the next rep.`

### State B — Positive Confirmation
- **Header status**: `● TRACKING` (emerald)
- **Rep counter**: `5 REPS OBSERVED • LIVE OBSERVATION` *(counter advanced by 1)*
- **Feedback card**: Emerald border, checkmark icon, label `REP COMPLETE`, cue text *"Good rep — chin cleared the bar."*
- **Bottom actions**: `End form check` | `Pause camera`
- **HTML key text**: `check Rep Complete Good rep — chin cleared the bar.`

### State C — Between Reps
- **Header status**: `● TRACKING` (emerald)
- **Rep counter**: `4 REPS OBSERVED • LIVE OBSERVATION` *(held, not advanced)*
- **Feedback card**: Neutral/dark border, clock icon, label `BETWEEN REPS`, cue text *"Lower with control before your next pull."*
- **Bottom actions**: `End form check` | `Pause camera`
- **HTML key text**: `schedule Between Reps Lower with control before your next pull.`

### State D — Tracking Interrupted
- **Header status**: `● TRACKING PAUSED` (amber)
- **Rep counter**: `4 REPS HELD [FROZEN] • OBSERVATION PAUSED` *(frozen, no increment)*
- **Framing badge**: `Tracking paused — subject out of view` (amber)
- **Camera view**: Visually dimmed/blurred overlay showing athlete partially out of frame
- **Feedback card**: Amber border, `person_search` icon, label `PLACEMENT GUIDANCE`, cue text *"Tracking paused — move back until your full body and the bar are visible."*
- **Bottom actions**: `End form check` | `Resume camera` *(replaces Pause camera)*
- **HTML key text**: `Tracking Paused Wide Grip Pull-up Tracking paused — subject out of view 4 reps held FROZEN`

---

## Design Contracts & Implementation Boundaries

1. **One state at a time**: Exactly one feedback card is shown at any moment. States do not stack or overlap.
2. **No auto-logging**: `Reps observed` / `Reps held` are transient CV optical observations. They are **never** automatically committed as a logged set or saved to workout history. The athlete decides explicitly.
3. **Tracking interrupted → no form judgment**: In State D, the system does not increment rep count, deliver form correction, or positive confirmation while tracking is paused.
4. **"Good rep" is mockup text**: The cue *"Good rep — chin cleared the bar"* is an illustrative design example. It does NOT confirm the underlying CV logic is implemented or validated. Real deployment requires verified signal mapping before production use.
5. **No audio assumption**: The `volume_up` speaker icon visible in the base Form Check screen is a design detail only. No spoken feedback is included in these state mocks; the speaker icon may appear in adjacent states if it was in the shared header, but its implementation is **not approved** in the current scope.
6. **Closing or resuming**: Tapping `End form check` in any state returns to the originating screen (Exercise Detail or Active Workout) without silently logging a set or saving a session. In State D, `Resume camera` restores tracking to the last held rep count and waits for a valid framing signal.
