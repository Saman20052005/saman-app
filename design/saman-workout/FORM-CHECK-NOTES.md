# Saman Workout — Live Form Check design notes

Status: design reference for a future Workout CV feature. The Stitch mockup is a visual proposal; this note does not claim the feature is implemented.

## Entry and screen context

- The first supported movement proposed for Form Check is Wide Grip Pull-up.
- The entry point belongs to the relevant Exercise Detail screen; an Active Workout may offer the same action for that movement.
- Form Check is a dedicated camera screen without the global tab bar. Closing it returns to the originating screen without completing or saving a workout set.
- Video Guide is separate: it demonstrates the movement, while Form Check observes the user's movement.

## Audio control

The speaker icon in the upper-right of the current Live Form Check mockup means **turn spoken form cues on or off**. Keep and label that control only if spoken feedback is included in the feature scope. If spoken feedback is not planned, remove the speaker icon from the implementation/design handoff so the interface does not promise an unavailable feature.

## Observed reps versus workout records

The mockup's **“4 reps observed”** is an illustrative live camera observation for the current Form Check session. It is **not a logged set**, a verified saved workout result, or a replacement for the user's confirmed set/rep/weight entry.

Ending or closing Form Check must not silently complete a set or save a workout session. A future review/confirmation step can offer observed reps to the user, who decides whether and how to record the set in Active Workout. Only a saved workout session should appear as completed activity in History and become eligible as real workout data for Chat AI.

## Visual reference and remaining decisions

The reviewed portrait Stitch screen from 2026-10-01 shows a dominant full-body camera view, a live rep counter, one short form cue, “End form check,” and “Pause camera.” Its appearance is approved as a design direction, not as proof that the CV detection or audio feedback exists.

Before implementation, decide whether spoken feedback is in scope and how a user confirms or edits camera-observed reps. Avoid presenting illustrative tracking values as personal workout history.
