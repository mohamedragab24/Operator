import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/admin_service.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const _Denied(message: 'يجب تسجيل الدخول أولاً');

    return StreamBuilder<UserProfile?>(
      stream: FirestoreService().watchUserProfile(user.uid),
      builder: (context, profileSnap) {
        final profile = profileSnap.data;
        if (profileSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (profile == null || !profile.isAdmin) {
          return const _Denied(message: 'ليس لديك صلاحية الدخول إلى لوحة الأدمن');
        }
        return const _AdminHome();
      },
    );
  }
}

class _AdminHome extends StatelessWidget {
  const _AdminHome();

  @override
  Widget build(BuildContext context) {
    final service = AdminService();
    return Scaffold(
      appBar: AppBar(
        title: const Text('مركز الاعتماد الموحد — مراجعة الكورسات'),
        backgroundColor: AppColors.ink,
        foregroundColor: AppColors.paper,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchPendingCourses(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('حدث خطأ: ${snapshot.error}'));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_circle_outline, size: 58),
                SizedBox(height: 12),
                Text('لا توجد كورسات قيد المراجعة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ]),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _PendingCourseCard(courseId: doc.id, data: doc.data());
            },
          );
        },
      ),
    );
  }
}

class _PendingCourseCard extends StatelessWidget {
  final String courseId;
  final Map<String, dynamic> data;
  const _PendingCourseCard({required this.courseId, required this.data});

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? data['name'] ?? 'بدون اسم').toString();
    final instructor = (data['instructorName'] ?? data['instructor'] ?? 'غير محدد').toString();
    final price = (data['promotionalPrice'] ?? data['promoPrice'] ?? data['price'] ?? '').toString();
    final description = (data['description'] ?? '').toString();
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('المُفهّم: $instructor'),
          if (price.isNotEmpty) Text('السعر: $price'),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showHistory(context),
                icon: const Icon(Icons.history),
                label: const Text('السجل'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _approve(context),
                icon: const Icon(Icons.check),
                label: const Text('قبول'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
                onPressed: () => _reject(context),
                icon: const Icon(Icons.close),
                label: const Text('رفض'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _approve(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('قبول الكورس؟'),
        content: const Text('سيصبح الكورس منشورًا ويمكن للطلاب رؤيته وشراؤه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('قبول')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await AdminService().reviewCourse(courseId: courseId, decision: 'approved');
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم قبول الكورس ونشره')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر القبول: $e')));
    }
  }

  Future<void> _reject(BuildContext context) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('سبب رفض الكورس'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'اكتب سبب الرفض بوضوح'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('رفض الكورس')),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.trim().isEmpty || !context.mounted) {
      if (reason != null && reason.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سبب الرفض مطلوب')));
      }
      return;
    }
    try {
      await AdminService().reviewCourse(courseId: courseId, decision: 'rejected', rejectionReason: reason.trim());
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفض الكورس وحفظ السبب')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الرفض: $e')));
    }
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .65,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: AdminService().watchReviewHistory(courseId),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('سجل المراجعات', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  if (docs.isEmpty) const Text('لا يوجد سجل مراجعات بعد.'),
                  ...docs.map((doc) {
                    final d = doc.data();
                    final decision = (d['decision'] ?? '').toString();
                    final reviewer = (d['reviewerName'] ?? d['reviewerUid'] ?? 'الأدمن').toString();
                    final reason = (d['rejectionReason'] ?? '').toString();
                    final time = d['reviewedAt'] is Timestamp ? (d['reviewedAt'] as Timestamp).toDate().toLocal().toString() : 'غير معروف';
                    return ListTile(
                      leading: Icon(decision == 'approved' ? Icons.check_circle : Icons.cancel),
                      title: Text(decision == 'approved' ? 'قبول' : 'رفض'),
                      subtitle: Text('$reviewer\n$time${reason.isNotEmpty ? '\nالسبب: $reason' : ''}'),
                    );
                  }),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Denied extends StatelessWidget {
  final String message;
  const _Denied({required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message, textAlign: TextAlign.center))));
}
