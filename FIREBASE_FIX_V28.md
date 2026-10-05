# Firebase startup/login fix V28

Fixed a deadlock in `FirebaseBootstrap.waitUntilReady()`.

The previous implementation awaited `start()`, while `start()` returned the long-lived retry loop. When Firebase was not immediately ready, LoginScreen could remain on "جاري التحميل" forever.

V28 starts the retry loop in the background with `unawaited(start())` and waits only on the readiness notifier with the caller timeout. Firebase initialization continues independently.

This does not change the Firebase project configuration.
