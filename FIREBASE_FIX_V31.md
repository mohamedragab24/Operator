# Firebase Fix V31

The release error `PlatformException(channel-error, Unable to establish connection on channel)` was caused by invoking FlutterFire Firebase Core initialization on Android during startup.

V31 changes Android startup to rely on the native Firebase SDK initialized by `google-services.json` / FirebaseInitProvider. The Dart code no longer calls `Firebase.initializeApp()` on Android and no longer reads `Firebase.apps` as a readiness gate.

iOS retains normal FlutterFire initialization.

The Android package remains `com.Fahmani` and the existing `google-services.json` is preserved.
