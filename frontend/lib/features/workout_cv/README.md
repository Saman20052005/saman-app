# Lat pulldown — Active source integration

Status: **Đã tích hợp source; camera Android trên Active chưa xác minh.**

Active already contains the selected native CameraX/MediaPipe pipeline, platform
registration in `MainActivity`, CAMERA permission, pinned Android dependencies and
`android/app/src/main/assets/pose_landmarker_lite.task`. These are retained; the
old workspace's debug TFLite probe is not a runtime camera model.

Camera landmarks → existing upper-body quality gates → pixel-scaled motion
features → existing `LatPulldownBaseline` → phase and provisional rep count.
Camera uses native capture timestamps; Android video replay uses video PTS. Both
use one tracker. Invalid data interrupts holds; a long gap cancels the unfinished
cycle and preserves completed reps. Source/exercise changes reset CV analysis.
Results stay inside the CV provider and never complete sets or save session data.

The rep baseline is rule based, uses the model-left elbow and existing thresholds
calibrated against a replay clip. It is **not a custom-trained exercise model**;
live accuracy, framing and overlay alignment remain unverified.

Web/iOS: the Form Check entry explains the platform restriction. No real landmark
recording is packaged for browser replay, and no Android channel is called there.
The Dart replay source remains available for existing offline tests. Android slow
video replay remains opt-in with `WORKOUT_CV_REPLAY_TRIAL=true`; it needs a readable
video on the device and is not evidence that Active live camera works. Existing
replay PTS/skew/overlay limitations are not optimized in this checkpoint.

## Demo and later phone check

From the Active workspace, start a manual workout containing **Lat Pulldown / Kéo
xô**, select that exercise, then tap **Form Check**. Android opens the CV screen;
web shows the platform restriction. Closing CV preserves manual workout inputs
and completed sets. CV reps are provisional and are not saved to the workout.

When the developer is ready to attach a phone (not executed in this checkpoint):

```powershell
Set-Location 'D:/SamanDev/workspace/saman-main-verified-CP26_20261025_072840/frontend'
flutter devices
flutter run -d <device-id> --no-pub --dart-define=BACKEND_URL=http://127.0.0.1:8000
```

Use the existing SDK and backend/network configuration. The URL above matches the
current local web launch; on a phone, retain the developer's existing port
forwarding or reachable backend URL. Do not add the replay trial define for the
live camera check. No backend/MongoDB restart is required by this integration.

Only check: open camera and grant permission → landmarks appear → moving changes
landmarks → exit/re-enter without errors. Do not treat this as rep accuracy
acceptance. No APK build, emulator launch or phone operation was performed here.
