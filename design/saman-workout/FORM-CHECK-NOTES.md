# Saman Workout — design handoff notes

Status: reviewed Stitch visual direction for the Workout redesign, captured on 2026-10-01. These static mockups are **not evidence of implemented functionality, verified exercise inventory, or real personal workout records**. This document records the visual/interaction decisions and open handoff items. It does not authorize code, backend, or schema changes.

## Reference screens and visual rules

| Screen | Latest reviewed Stitch screenshot | Packaged Design Folder | Role |
| --- | --- | --- | --- |
| Workout main | `Screenshot 2026-10-01 at 3.46.09 PM.png` | [01-workout-home](01-workout-home/) | Workout tab entry |
| Exercise Library | `Screenshot 2026-10-01 at 3.55.25 PM.png` | [02-exercise-library](02-exercise-library/) | Exercise discovery |
| Exercise Detail | `Screenshot 2026-10-01 at 4.05.13 PM.png` | [03-exercise-detail](03-exercise-detail/) | Dumbbell Bench Press guidance |
| Active Workout | `Screenshot 2026-10-01 at 4.19.35 PM.png` | [04-active-workout](04-active-workout/) *(Assets missing from local downloads — BLOCKED)* | In-session logging |
| Live Form Check | `Screenshot 2026-10-01 at 4.30.24 PM.png` | [05-live-form-check](05-live-form-check/) | Future CV flow for Wide Grip Pull-up |

These screenshot names identify the user-reviewed images in the design conversation; the image assets and Stitch exports are **not yet packaged in this branch** (see imported folders above for packaged Stitch exports and [MANIFEST.md](MANIFEST.md) for handoff inventory). Obtain and version the actual exports before treating a screenshot as an implementation-ready visual source. The approved Home, Chat AI, and Profile design sources remain the broader Saman style references; this note does not supersede their latest approved files.

Use the dark **Calm Athleticism** direction: near-black/charcoal surfaces, warm off-white primary actions, restrained emerald for states and completion, Space Grotesk headlines, Inter body text, and limited JetBrains Mono for aligned numeric information. Prefer clear hierarchy, readable touch targets, generous spacing, and authentic sports documentary imagery featuring male athletes in these examples. Exercise access and plans must remain open to all users regardless of gender. The light theme is a later design pass.

## 1. Workout main

- Keep the five-tab app navigation exactly **Home / Workout (active) / Saman / Nutrition / Profile**.
- The scheduled-session hero uses an authentic strength-training photograph, planned status, session name, estimated duration and exercise count, with an off-white **Start workout** action and secondary **View plan**. A planned session is not a completed workout.
- Provide **Quick start** (workout without a plan), **Browse library**, photo-led **Upper Body** and **Lower Body** entry cards, **My Plans / Your Plan**, and a **Last workout** area linking to History. The two focus categories are not gender locks.
- The shown session names, plan dates, duration/counts and “Last workout” details are illustrative until backed by actual user data. Do not imply an example History row was saved by the current user. Do not add unverified exercise-library totals.
- Primary routes: Start workout / Quick start → Active Workout; Browse library / category card → Exercise Library (with appropriate starting filter); plan actions → plan view; Last workout / View history → Workout History. Exact behavior for starting a planned versus empty session requires a later flow decision.

## 2. Exercise Library

- A Workout subpage with back to Workout and the same five-tab navigation (Workout active).
- Search, primary focus tabs **All / Upper Body / Lower Body / Core**, optional muscle/equipment filters, and photo-led movement rows with muscle/equipment metadata and a Video guide affordance.
- The screenshot illustrates an **Upper Body** entry state. Filter selections must agree with visible results; do not show a selected muscle chip that contradicts the list. Counts and bookmark behavior must not be invented.
- Selecting a movement opens its Exercise Detail. Decide whether the upper-right bookmark control is a real saved-exercise action; otherwise remove it at implementation handoff.

## 3. Exercise Detail

- The reviewed example is **Dumbbell Bench Press**. Back returns to Exercise Library; the five-tab navigation remains visible outside an active session.
- Show an actual instructional video entry with a clear play action, concise movement facts (primary/secondary muscles and equipment), three short steps, and simple form cues. A photograph or poster is a preview, not proof that a playable video asset exists.
- The off-white **Start exercise** action must have an explicit entry behavior: start a session, or add/select the exercise in an already active session. Resolve this before implementation.
- A future **Check my form** entry belongs here only for movements that are genuinely supported by CV. Do **not** place it on Dumbbell Bench Press solely because this visual example uses that movement. The first proposed CV movement is Wide Grip Pull-up.
- Video Guide demonstrates correct movement; Form Check observes the user's own movement. They are separate experiences.

## 4. Active Workout

- Dedicated in-session layout: compact title, elapsed time, progress, one current movement photo, Video Guide, compact rest timer, set list, upcoming movement and one primary off-white **Log Set 3** action. The global tab bar is hidden.
- Example screen: **Upper Body Strength**, exercise 1 of 5, Dumbbell Bench Press, two completed example sets (24 kg × 10; 26 kg × 8), editable set 3 (26 kg / 8 reps), and upcoming planned set 4. These are **illustrative mockup values**, not verified history. “Target: 26 kg × 8” is a plan/reference, not a recorded result.
- The active row edits kg/reps. **Log Set 3** is the sole completion action for that set; avoid a duplicate completion checkbox. Completed sets must be distinct from editable and planned sets. The rest timer has +30s/Skip; Add set and next-exercise navigation remain secondary.
- **Pause workout** does not finish or save. Minimize/leave must preserve or safely handle in-progress work, with exact resume/discard behavior specified before implementation.
- **Finish** opens **Workout Review & Save**; it does not silently mark completion or save. A separate screen and flow are still needed for review, confirmation, saving, failure/retry, and entry into History.
- When supported on the current movement, Active Workout can offer **Check my form** beside guidance. Opening and closing CV must not automatically log a set.

## 5. Live Form Check — future Workout CV

- Reviewed portrait direction for **Wide Grip Pull-up**: full-height live camera view with pull-up bar and entire athlete visible, compact header, simple “Full body in frame” status, large observed-rep count, one short cue at a time, off-white **End form check** and secondary **Pause camera**. Hide global tabs.
- The speaker icon in the top-right of the current mockup means **turn spoken form cues on/off**. Keep and label it only if spoken feedback is in the feature scope; otherwise remove it so the UI does not promise unavailable audio.
- **“4 reps observed”** is an illustrative live CV observation in the mockup. It is not a logged set, verified saved workout result, or replacement for confirmed set/rep/weight input.
- Closing or ending CV returns to the originating Exercise Detail or Active Workout without silently completing a set or saving a session. A later review/confirmation step may offer observed reps; the user decides whether and how to enter them into Active Workout.
- If the body/bar leaves the camera view, use plain guidance instead of presenting unreliable rep counts or form judgments. Avoid invented confidence percentages, medical claims, fixed required camera distances, and unsupported detection statuses.
- The first supported movement, camera permissions/setup, observation validation, audio scope and confirmation UI must be settled before implementation. Do not expose Form Check on movements that CV cannot assess.

## Workout data boundary for the later phase

The intended product flow is **train → confirm logged sets → review and save session → view actual session in History → Chat AI can read the saved session**. Keep planned targets, editable drafts, camera observations, and completed/saved records visibly distinct. Chat AI must not treat mockup numbers, unsaved sets, or CV observations as factual workout history.

## Outstanding screens and handoff decisions

1. Design **Workout Review & Save** and **Workout History** before describing the end-to-end journey as complete.
2. Resolve the exact behavior of Start exercise, session minimize/pause/resume/discard, set correction, and whether observed CV reps can prefill a set after explicit confirmation.
3. Confirm real exercise video assets and the supported CV exercise list; decide whether spoken feedback and Library bookmarks are in scope.
4. ~~Package the approved Stitch images/exports and latest design-system documents with provenance.~~ **Done (2026-10-02)**: Screens 01–03 and 05 packaged in `design/saman-workout/`. Screen 04 (Active Workout) still missing from local downloads — blocked. Four real-time feedback state variants (States A–D) packaged under [`05-live-form-check/future-feedback-states/`](05-live-form-check/future-feedback-states/) — deferred, not yet an implementation requirement. See [MANIFEST.md](MANIFEST.md) for full inventory.
5. Confirm audio/spoken feedback scope. The speaker icon visible in the base Live Form Check mockup and the feedback state variants is a design element only; it must not be implemented unless spoken feedback is formally approved.

No Flutter, backend, data model, or live service change is part of this design-document update.

