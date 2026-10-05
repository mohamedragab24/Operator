# إشعارات التطبيق

- FCM token is stored under `users/{uid}/fcmTokens`.
- Foreground messages are also shown as Android local notifications.
- All received notifications are saved to `users/{uid}/notifications`.
- Admin campaign images are uploaded to Firebase Storage by the platform.
- Cloud Functions send Push notifications and create the Inbox record.

Android 13+ requires notification permission; the app requests it on startup.
