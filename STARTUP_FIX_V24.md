# V24 startup fix

- Fixed a release-startup hazard where Firebase Messaging was accessed before Firebase Core was initialized.
- `FirebaseMessaging.onMessageOpenedApp` and `getInitialMessage()` now run only after `Firebase.apps.isNotEmpty` and are fully isolated with try/catch.
- The app UI remains independent of Firebase startup.
- No Firebase error page is shown.
