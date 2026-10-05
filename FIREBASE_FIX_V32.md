# Firebase Fix V32

Fixed the V31 compile error caused by stale references to `firebaseBootstrap`.

Changed those references to the actual singleton `FirebaseBootstrap.instance` in:
- `lib/main.dart`
- `lib/screens/splash_screen.dart`

No Firebase startup strategy was changed from V31.
