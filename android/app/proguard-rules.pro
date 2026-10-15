# ML Kit Face Detection — keep reflective classes used by the native bridge.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keepclassmembers class * {
    @com.google.mlkit.** <methods>;
}
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# Keep Flutter plugin registration.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }

# Keep Camera plugin classes.
-keep class io.flutter.plugins.camera.** { *; }