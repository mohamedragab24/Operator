# Firebase fix V36

## Root cause addressed
The Android app was reaching FlutterFire plugins while the native Firebase default app did not exist. This produced errors such as:

- `No Firebase App '[DEFAULT]' has been created`
- `call Firebase.initializeApp(Context) first`
- FlutterFire `channel-error`

## Fix
Firebase is now initialized in a custom Android `Application` (`MasarApplication`) before Flutter starts and before FlutterFire plugins can access Auth/Firestore/Messaging.

The native initialization uses the project's explicit FirebaseOptions, so it does not depend on FlutterFire Core's Dart initialization channel on Android.

`MainActivity` only verifies that the default native app exists.

Dart keeps the Android path free of `Firebase.initializeApp()`. iOS continues to use normal FlutterFire initialization.
