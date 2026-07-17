# Flutter / embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core (optional deferred components; unused but referenced by Flutter tooling)
-dontwarn com.google.android.play.core.**

# Keep native methods / JNI entry points used by plugins (e.g. SQLite, media).
-keepclasseswithmembernames class * {
    native <methods>;
}

# Gson / reflective models used by some plugins
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
