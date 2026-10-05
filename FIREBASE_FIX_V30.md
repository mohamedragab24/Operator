# Firebase / Android build fix V30

The V29 APK build failed at Kotlin compilation because MainActivity.kt imported `com.google.firebase.FirebaseApp` directly, while the app module does not expose that Firebase Android SDK class as a direct dependency.

V30 removes that direct native FirebaseApp import/initialization. Firebase is initialized through the FlutterFire `firebase_core` plugin, which is the dependency already used by the Flutter project. The V28/V29 Dart-side startup fix remains in place so Firebase initialization is bounded and does not leave login stuck on "جاري التحميل".

The warnings about tree-shaken icons, Giphy/AndroidX migration, Media3/support-library migration, and deprecated APIs are warnings, not the build-stopping error shown in the supplied log.
