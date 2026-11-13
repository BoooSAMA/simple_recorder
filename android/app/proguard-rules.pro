# FFmpegKit registers its native methods from JNI_OnLoad using hard-coded class
# and method names. R8 renaming/shrinking them makes System.loadLibrary fail with
# "Bad JNI version returned from JNI_OnLoad ... 0", which aborts
# GeneratedPluginRegistrant and leaves every plugin (JNI, path_provider,
# background_service, ...) unregistered in release builds.
-keep class com.antonkarpenko.ffmpegkit.** { *; }

# Dart JNI bridge (used by path_provider_android 2.x through jni_flutter).
-keep class com.github.dart_lang.jni.** { *; }
-keep class com.github.dart_lang.jni_flutter.** { *; }

# Keep class/member names of any class declaring native methods.
-keepclasseswithmembernames class * {
    native <methods>;
}
