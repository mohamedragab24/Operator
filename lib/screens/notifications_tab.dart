import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class NotificationsTab extends StatelessWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Text('يجب تسجيل الدخول أولاً'),
        ),
      );
    }

    final service = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchNotifications(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text('حدث خطأ أثناء تحميل الإشعارات'),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const _EmptyNotifications();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              final title =
                  data['title']?.toString() ?? 'إشعار جديد';

              final body =
                  data['body']?.toString() ?? '';

              final read = data['read'] == true;

              return Card(
                color: read
                    ? null
                    : AppColors.emeraldLight,
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      read
                          ? Icons.notifications_none
                          : Icons.notifications,
                    ),
                  ),
                  title: Text(
                    title,
                    style: TextStyle(
                      fontWeight: read
                          ? FontWeight.normal
                          : FontWeight.bold,
                    ),
                  ),
                  subtitle: body.isEmpty
                      ? null
                      : Padding(
                          padding:
                              const EdgeInsets.only(top: 4),
                          child: Text(body),
                        ),
                  onTap: () async {
                    if (!read) {
                      await service.markNotificationRead(
                        user.uid,
                        doc.id,
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none,
            size: 72,
            color: AppColors.muted,
          ),
          const SizedBox(height: 16),
          const Text(
            'لا توجد إشعارات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
