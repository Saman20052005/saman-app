-dontwarn javax.lang.model.**
-dontwarn javax.annotation.**
-dontwarn javax.tools.**
-keep class autovalue.shaded.** { *; }
-keep class com.google.auto.value.** { *; }

# MediaPipe Tasks Vision: JNI/reflection resolves these by name; R8 renames/strips them in release (TaskRunner -> a)
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.proto.**
-dontwarn com.google.protobuf.**
