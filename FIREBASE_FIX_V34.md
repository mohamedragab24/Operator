# Firebase Android Fix V34

- Fixed release Gradle failure caused by `com.google.firebase:firebase-app:` having no version.
- Added Firebase Android BOM `33.5.1` and `firebase-app` with the BOM-managed version.
- Replaced reflection-based `FirebaseApp` lookup with the direct Firebase Android SDK API.
- `google-services.json` remains the Android Firebase configuration.
- Dart still avoids `Firebase.initializeApp()` on Android; FlutterFire Core is used on iOS.
- This addresses the runtime `Firebase native init ... FirebaseApp ...` failure from V33 and the release dependency resolution failure.
