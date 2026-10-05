# V27 Firebase startup fix

- Android/iOS Firebase initialization now uses the native Firebase configuration (`google-services.json` / `GoogleService-Info.plist`) via `Firebase.initializeApp()` without manually supplied options.
- Firebase startup retries indefinitely every 3 seconds after a transient failure.
- A timeout in `waitUntilReady` no longer means "internet problem" and does not stop the background retry loop.
- Login waits up to 30 seconds for Firebase and reports the actual Firebase initialization error if it is still unavailable.
- `network-request-failed` is only reported for an actual Firebase Auth network error.
- Firestore profile sync remains non-blocking after successful Auth login.
