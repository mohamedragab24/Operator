# Firebase fix V37

## Root cause
V31/V36 stopped calling `Firebase.initializeApp()` on Android. But FlutterFire keeps its own
Dart-side registry of apps, so even with a native default app, `FirebaseAuth.instance` throws
`[core/no-app] No Firebase App '[DEFAULT]' has been created - call Firebase.initializeApp()`.

## Fix
- `firebase_bootstrap.dart`: Dart `Firebase.initializeApp()` now runs on Android too (native check
  is best-effort), with retries, an options fallback, and a `Firebase.app()` verification.
  `waitUntilReady()` now retries instead of waiting passively.
- `android/app/build.gradle`: release build no longer minifies/shrinks (R8 can strip FlutterFire
  channel classes, which was the likely source of the old `channel-error`).
- `signup_screen.dart`: waits for Firebase and shows real error messages.

## V37b
- `MainActivity.kt`: explicitly (idempotently) re-runs `GeneratedPluginRegistrant` and makes sure the
  `firebase_core` plugin is attached to the engine; the result is exposed to Dart as diagnostics and
  appended to the startup error message.
- CI: `flutter build apk --release --no-shrink` in both workflows (R8 fully off).

## V37c (real root cause of channel-error)
Diagnostics showed `firebase_core` was registered natively, so the failure was a Dart/native
version mismatch: floating `^` Firebase versions pulled a broken `firebase_core_platform_interface`
(5.4.1). All Firebase packages are now pinned to one coherent release (firebase_core 3.8.0,
firebase_auth 5.3.3, cloud_firestore 5.5.0, firebase_storage 12.3.6, cloud_functions 5.1.5,
firebase_messaging 15.1.5) and `firebase_core_platform_interface` is overridden to 5.4.2.

## V37d
Same channel-error after pinning, so diagnostics were extended:
- `MainActivity.kt`: re-attaches the firebase_core plugin (a plugin is stored in the registry before
  `onAttachedToEngine` runs, so "registered" does not prove its Pigeon handlers exist), captures any
  exception, and installs the Pigeon handlers directly.
- `firebase_bootstrap.dart`: on failure also probes the raw Pigeon channel (`handler-missing` vs
  `handler-present`) and prints the resolved Firebase package versions (`kFirebaseVersions`).
- CI writes `lib/services/build_versions.dart` from `pubspec.lock` after `flutter pub get`.
