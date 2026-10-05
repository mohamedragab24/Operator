# Firebase startup fix V29

## What changed
- Firebase Core now initializes with the explicit `DefaultFirebaseOptions.currentPlatform` configuration instead of relying only on native auto-discovery.
- `waitUntilReady()` registers its readiness listener before starting the retry loop, removing the race that could miss a fast initialization.
- Android `MainActivity` initializes the native `FirebaseApp` as early as possible after the Flutter activity is created.
- The existing UI, routing, authentication flow, R2, meetings, and course features were left intact.

## Important
Build this V29 project as a fresh GitHub Actions run. Do not copy only individual Dart files into an older Android project; the Android Firebase setup must be deployed together.
