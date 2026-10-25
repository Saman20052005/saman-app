# Workout CV Model Specification

## Model Overview
- **Name:** MediaPipe Pose Landmarker (Lite - float16)
- **Format:** Google AI Edge Task Bundle (`.task`)
- **Asset Path:** `frontend/android/app/src/main/assets/pose_landmarker_lite.task`
- **Official Source URL:** https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
- **Model Version:** MediaPipe Pose Landmarker v2 (Lite Float16 Latest)
- **File Size:** 5,777,746 bytes (~5.51 MB)
- **SHA256:** `59929E1D1EE95287735DDD833B19CF4AC46D29BC7AFDDBBF6753C459690D574A`

## Runtime Configuration
- **Delegate:** CPU Delegate (`Delegate.CPU`) for deterministic stability across diverse Android chipsets; GPU delegate fallback planned for future optimizations.
- **Running Mode:** `RunningMode.LIVE_STREAM` (real-time camera feed asynchronous inference).
- **Target Landmarks:** 33 body landmarks (x, y, z normalized, presence, visibility).
- **Detection Targets:**
  - Configured `numPoses = 2` to detect multiple people and trigger `multiplePeople` gating state.
  - Tracking single primary target when exactly one person is present in frame.
- **Key Joint Gating:**
  - Essential joints for Pull-up and Lat Pulldown:
    - Shoulders (Landmarks 11, 12)
    - Elbows (Landmarks 13, 14)
    - Wrists (Landmarks 15, 16)
    - Hips (Landmarks 23, 24)
  - Minimum visibility threshold: 0.5 for core upper-body joints.
