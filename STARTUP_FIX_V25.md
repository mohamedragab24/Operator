# V25 startup fix

Root cause found in V24: `LoginScreen`, `SignupScreen`, and `ForgotPasswordScreen` construct `AuthService` while Firebase Core can still be uninitialized. `AuthService` previously created `FirebaseAuth.instance` as a field initializer, which can throw `core/no-app` before the login screen renders and appear as a blank white page in release builds.

Fixes:
- FirebaseAuth is now lazy inside AuthService.
- FirestoreService is lazy as an additional startup safety guard.
- NotificationService Firebase dependencies are lazy as well.
- Firebase bootstrap remains non-blocking.
