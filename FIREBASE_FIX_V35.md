# Firebase Fix V35

The V34 build still failed because `com.google.firebase:firebase-app` is not a valid Firebase Android Maven artifact.

V35 changes the native Android dependency to `com.google.firebase:firebase-common`, managed by Firebase BOM 33.5.1. `FirebaseApp` is provided by firebase-common.

No Dart Firebase initialization is added back on Android; the app continues to use the native Firebase default app through the MethodChannel.
