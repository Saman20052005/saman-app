# health_ai_app

A new Flutter project.

## Android workout CV replay trial

`WORKOUT_CV_REPLAY_TRIAL` defaults to `false`. A normal build keeps the camera
entry and hides replay trial controls; it does not need the local test clip.
This restores the camera entry only, without claiming that camera live or the
known camera-to-replay JNI crash has passed validation.

For the experimental slow replay on the prepared test emulator:

```powershell
flutter build apk --debug --no-pub --dart-define=BACKEND_URL=http://127.0.0.1:8012 --dart-define=WORKOUT_CV_REPLAY_TRIAL=true
```

Only a native Android Lat pulldown screen uses replay when the flag is true.
Opening the screen, resuming and retrying permission use the same source policy.
Form Check opens the preset clip directly; there is no file picker. The clip
must already exist in the app sandbox at
`/data/data/com.example.health_ai_app/files/test_videos/15620300_1080_1920_50fps.mp4`;
it is not bundled in the APK or Git. Without that clip, the opt-in trial reports
an error. Do not enable the flag for an ordinary build.

The trial verifies one clip/emulator only, not accuracy, real-time or camera live.
EOF keeps completed reps and clears the skeleton; restart resets to 0; leaving
does not save history or complete a set. The camera-to-replay crash is unresolved.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
