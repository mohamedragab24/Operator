// Firebase configuration for the Fahmani/Masar app.
// These values match the project's google-services.json and
// GoogleService-Info.plist. Keeping them explicit avoids relying solely on
// platform auto-configuration during startup.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase web configuration is not included in this mobile app.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Firebase is not configured for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBVzHAgc-gLC8uVIylT7gpV1HWgaCvINrs',
    appId: '1:60922959373:android:b28cad44b8b2dded0fa744',
    messagingSenderId: '60922959373',
    projectId: 'studio-7708799057-99672',
    storageBucket: 'studio-7708799057-99672.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBabWBTY3QnDSVEB1FqSxrEkBR6zXWxsic',
    appId: '1:60922959373:ios:c4c18fbb504521520fa744',
    messagingSenderId: '60922959373',
    projectId: 'studio-7708799057-99672',
    storageBucket: 'studio-7708799057-99672.firebasestorage.app',
    iosBundleId: 'com.Fahmani',
  );
}
