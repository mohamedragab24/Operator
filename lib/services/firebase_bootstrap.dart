import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'build_versions.dart';

/// Coordinates Firebase startup.
///
/// IMPORTANT: FlutterFire keeps its own Dart-side registry of Firebase apps.
/// Even when the native Android FirebaseApp already exists (created by
/// google-services / MasarApplication), `FirebaseAuth.instance` and the other
/// plugins throw `[core/no-app] No Firebase App '[DEFAULT]' has been created`
/// until `Firebase.initializeApp()` has been called once from Dart. So Dart
/// initialization must run on Android as well.
class FirebaseBootstrap {
  FirebaseBootstrap._();
  static final FirebaseBootstrap instance = FirebaseBootstrap._();

  static const MethodChannel _nativeChannel =
      MethodChannel('masar_app/firebase');

  static const Duration _stepTimeout = Duration(seconds: 10);

  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);
  Future<void>? _running;

  Future<void> start() {
    if (ready.value) return Future<void>.value();
    return _running ??= _start().whenComplete(() {
      // Allow a later attempt (e.g. from the login button) to retry.
      if (!ready.value) _running = null;
    });
  }

  Future<void> _start() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _confirmNativeApp();
      }
      await _initializeFlutterFire();
      error.value = null;
      ready.value = true;
    } catch (e) {
      error.value = e.toString();
      ready.value = false;
    }
  }

  /// Best effort: checks that the native Android default app exists.
  /// Never fatal — if it is missing, the Dart initialization below creates it
  /// from DefaultFirebaseOptions.
  Future<void> _confirmNativeApp() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final result = await _nativeChannel
            .invokeMethod<bool>('ensureInitialized')
            .timeout(const Duration(seconds: 3));
        if (result == true) return;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Registers the default app in FlutterFire's Dart registry, retrying on
  /// transient platform-channel failures.
  Future<void> _initializeFlutterFire() async {
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await _initializeOnce();
        return;
      } catch (e) {
        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    var diagnostics = '';
    try {
      diagnostics = await _nativeChannel
              .invokeMethod<String>('diagnostics')
              .timeout(const Duration(seconds: 3)) ??
          '';
    } catch (e) {
      diagnostics = 'diagnostics-unavailable: $e';
    }
    final probe = await _probeCoreChannel();
    throw StateError('تعذر تهيئة Firebase: $lastError | native: $diagnostics'
        ' | probe: $probe | versions: $kFirebaseVersions');
  }

  /// Sends a raw message to the firebase_core Pigeon channel.
  /// null reply  -> the native side has no working handler for this channel.
  /// decode error / value -> a handler exists (Dart/native version mismatch).
  Future<String> _probeCoreChannel() async {
    const name =
        'dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.initializeCore';
    try {
      final reply = await const BasicMessageChannel<Object?>(
        name,
        StandardMessageCodec(),
      ).send(null).timeout(const Duration(seconds: 5));
      return reply == null
          ? 'handler-missing(null-reply)'
          : 'handler-present(${reply.runtimeType})';
    } catch (e) {
      return 'handler-present(${e.toString().split('\n').first})';
    }
  }

  Future<void> _initializeOnce() async {
    try {
      // Uses the native default app (google-services.json / plist).
      await Firebase.initializeApp().timeout(_stepTimeout);
    } catch (_) {
      // No native default app yet: create it from explicit options.
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(_stepTimeout);
      } on FirebaseException catch (e) {
        if (e.code != 'duplicate-app') rethrow;
      }
    }
    // Throws core/no-app if the Dart registry still has no default app.
    Firebase.app();
  }

  Future<bool> waitUntilReady({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (ready.value) return true;

    final deadline = DateTime.now().add(timeout);
    while (!ready.value) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      try {
        await start().timeout(remaining);
      } catch (_) {}
      if (ready.value) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return ready.value;
  }

  String get lastError => error.value ?? '';

  void dispose() {
    ready.dispose();
    error.dispose();
  }
}
