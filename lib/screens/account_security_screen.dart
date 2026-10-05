import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class AccountSecurityScreen extends StatelessWidget {
  const AccountSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول')));
    final devices = FirebaseFirestore.instance.collection('devices').where('uid', isEqualTo: user.uid).orderBy('lastSeenAt', descending: true);
    return Scaffold(
      appBar: AppBar(title: const Text('أمان الحساب والأجهزة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: ListTile(leading: const Icon(Icons.email_outlined), title: const Text('البريد الإلكتروني'), subtitle: Text(user.email ?? ''))),
          const SizedBox(height: 12),
          const Text('الأجهزة المسجلة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
            stream: devices.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return const ListTile(title: Text('تعذر تحميل الأجهزة'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (snap.data!.docs.isEmpty) return const ListTile(title: Text('لا توجد أجهزة مسجلة بعد.'));
              return Column(children: snap.data!.docs.map((d) { final x=d.data(); return Card(margin: const EdgeInsets.only(bottom:8), child: ListTile(leading: const Icon(Icons.phone_android), title: Text(x['platform']?.toString() ?? 'جهاز'), subtitle: Text('آخر ظهور: ${_date(x['lastSeenAt'])}'), trailing: const Icon(Icons.check_circle_outline))); }).toList());
            },
          ),
          const SizedBox(height: 12),
          ListTile(leading: const Icon(Icons.lock_outline), title: const Text('تغيير كلمة المرور'), trailing: const Icon(Icons.chevron_left), onTap: () => context.push('/change-password')),
          const Padding(padding: EdgeInsets.all(12), child: Text('إدارة الجلسات تعتمد على رموز تسجيل الدخول المسجلة؛ يمكن إنهاء الجلسات من إعدادات الحساب عند توفر إدارة الجلسات على الخادم.', style: TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  static String _date(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal().toString().split('.').first;
    return 'غير معروف';
  }
}
