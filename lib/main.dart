import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_router.dart';
import 'theme/app_theme.dart';
import 'services/deep_link_service.dart';
import 'services/screen_protection_service.dart';
import 'services/app_update_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_bootstrap.dart';


Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await FirebaseBootstrap.instance.waitUntilReady(timeout: const Duration(seconds: 10));
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final n = message.notification;
  await FirebaseFirestore.instance.collection('users').doc(uid).collection('notifications').doc(message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString()).set({
    'title': n?.title ?? message.data['title'] ?? '',
    'body': n?.body ?? message.data['body'] ?? '',
    'imageUrl': message.data['imageUrl'] ?? '',
    'type': message.data['type'] ?? 'push',
    'data': message.data, 'read': false, 'createdAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // The UI must never wait for Firebase. Start the Firebase connection in
  // the background and let the app open immediately.
  runApp(const MasarApp());
  unawaited(FirebaseBootstrap.instance.start());
}

class MasarApp extends StatefulWidget {
  const MasarApp({super.key});

  @override
  State<MasarApp> createState() => _MasarAppState();
}

class _MasarAppState extends State<MasarApp> {
  late final router = buildRouter();
  final deepLinkService = DeepLinkService();
  final screenProtection = ScreenProtectionService();
  final appUpdateService = AppUpdateService();
  bool _blockContent = false;
  bool _updateDialogShown = false;

  @override
  void initState() {
    super.initState();
    // Keep startup lightweight: optional services are initialized after the
    // first frame and each failure is isolated so one plugin can never stop
    // the main application from opening.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try { deepLinkService.init(router); } catch (_) {}
      screenProtection.init().catchError((_) {});
      // Firebase Messaging must not be touched until the Firebase bootstrap
      // controller reports that native Firebase is ready.
      _initMessagingSafely();
      _checkForUpdate();
    });
    screenProtection.shouldBlockContent.listen((block) {
      if (mounted) setState(() => _blockContent = block);
    });
  }

  Future<void> _initMessagingSafely() async {
    try {
      // Wait briefly for Firebase bootstrap, but never block the UI.
      for (var i = 0; i < 20; i++) {
        if (FirebaseBootstrap.instance.ready.value) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!mounted || !FirebaseBootstrap.instance.ready.value) return;

      try {
        await NotificationService().init();
      } catch (_) {}

      try {
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          if (!mounted) return;
          final requestId = message.data['requestId']?.toString();
          if (requestId != null && requestId.isNotEmpty) {
            router.push('/meeting/$requestId');
          }
        });
      } catch (_) {}

      try {
        final message = await FirebaseMessaging.instance.getInitialMessage();
        if (!mounted) return;
        final requestId = message?.data['requestId']?.toString();
        if (requestId != null && requestId.isNotEmpty) {
          router.push('/meeting/$requestId');
        }
      } catch (_) {}
    } catch (_) {
      // Messaging is optional during startup. It must never blank the app.
    }
  }

  Future<void> _checkForUpdate() async {
    try {
      // Give Firebase/router time to finish starting before showing a dialog.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || _updateDialogShown) return;

      final update = await appUpdateService.checkForAndroidUpdate();
      if (!mounted || update == null || _updateDialogShown) return;

      _updateDialogShown = true;
      await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('تحديث جديد متاح'),
        content: Text(
          'يوجد إصدار جديد من التطبيق (${update.versionName}).\n'
          'اضغط «تحديث الآن» لتحميل أحدث نسخة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('لاحقًا'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await appUpdateService.openUpdate(update);
            },
            icon: const Icon(Icons.system_update),
            label: const Text('تحديث الآن'),
          ),
        ],
      ),
      );
    } catch (_) {
      // Optional update checking must never affect normal app usage.
    }
  }

  @override
  void dispose() {
    deepLinkService.dispose();
    screenProtection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'مسار',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
      locale: const Locale('ar'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar'), Locale('en')],
      builder: (context, child) {
        // Force RTL app-wide regardless of device locale, matching the
        // brand's primary language.
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Stack(
            children: [
              child!,
              // iOS-only in practice (Android never sets _blockContent since
              // FLAG_SECURE already blocks capture at the OS level). Covers
              // every screen — not just the player — the instant a
              // recording starts or a screenshot is taken.
              if (_blockContent)
                Container(
                  color: AppColors.ink,
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, color: AppColors.gold, size: 34),
                      SizedBox(height: 12),
                      Text('تم إخفاء المحتوى لحمايته',
                          style: TextStyle(color: AppColors.paper, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
