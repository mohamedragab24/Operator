import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  StreamSubscription<User?>? _authSub;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: true);
    const localSettings = InitializationSettings(android: android, iOS: ios);
    await _local.initialize(localSettings);
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(const AndroidNotificationChannel('fahimt_general', 'إشعارات فهمت', description: 'إشعارات المنصة والكورسات', importance: Importance.high));
    await _messaging.setAutoInitEnabled(true);
    final messagingSettings = await _messaging.requestPermission(alert: true, badge: true, sound: true, provisional: false);
    if (messagingSettings.authorizationStatus == AuthorizationStatus.denied) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) await _saveToken(user.uid);
    await _authSub?.cancel();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null) {
        try { await _saveToken(user.uid); } catch (_) {}
      }
    });
    await _messageSub?.cancel();
    _messageSub = FirebaseMessaging.onMessage.listen((message) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final n = message.notification;
      final title = n?.title ?? message.data['title'] ?? '';
      final body = n?.body ?? message.data['body'] ?? '';
      await _local.show(
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647),
        title.toString(),
        body.toString(),
        const NotificationDetails(android: AndroidNotificationDetails('fahimt_general', 'إشعارات فهمت', channelDescription: 'إشعارات المنصة والكورسات', importance: Importance.high, priority: Priority.high, icon: '@mipmap/ic_launcher')),
      );
      await _db.collection('users').doc(uid).collection('notifications').doc(message.messageId ?? DateTime.now().microsecondsSinceEpoch.toString()).set({
        'title': title,
        'body': body,
        'imageUrl': n?.android?.imageUrl ?? message.data['imageUrl'] ?? '',
        'type': message.data['type'] ?? 'push',
        'data': message.data,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    _tokenSub = _messaging.onTokenRefresh.listen((token) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || token.isEmpty) return;
      await _saveToken(uid, token);
    });
  }

  Future<void> _saveToken(String uid, [String? suppliedToken]) async {
    final token = suppliedToken ?? await _messaging.getToken();
    if (token == null || token.isEmpty) return;
    await _db.collection('users').doc(uid).collection('fcmTokens').doc(token).set({
      'token': token, 'platform': 'flutter', 'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _db.collection('devices').doc(token).set({
      'uid': uid, 'token': token, 'platform': 'flutter', 'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> dispose() async {
    await _tokenSub?.cancel();
    await _messageSub?.cancel();
    await _authSub?.cancel();
  }
}
