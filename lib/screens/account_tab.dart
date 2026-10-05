import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import 'edit_profile_screen.dart';
import 'instructor_dashboard_screen.dart';

class _InfoPage extends StatelessWidget {
  final String title;
  final String body;
  const _InfoPage({required this.title, required this.body});
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(title)), body: RefreshIndicator(onRefresh: () async {}, child: ListView(padding: const EdgeInsets.all(20), children: [Text(body, style: const TextStyle(height: 1.8, fontSize: 14))])));
}

class AccountTab extends StatelessWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return SafeArea(
      child: StreamBuilder<UserProfile?>(
        stream: FirestoreService().watchUserProfile(user.uid),
        builder: (context, snap) {
          final profile = snap.data;
          final name = profile?.name.isNotEmpty == true
              ? profile!.name
              : (user.displayName?.isNotEmpty == true ? user.displayName! : 'طالب مسار');
          final email = profile?.email.isNotEmpty == true ? profile!.email : (user.email ?? '');
          final photoUrl = profile?.photoUrl ?? '';
          final isMofahhem = profile?.isMofahhem ?? false;

          return ListView(
            children: [
              Container(
                color: AppColors.ink,
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 22),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                      backgroundColor: AppColors.gold,
                      child: photoUrl.isEmpty
                          ? Text(name.isNotEmpty ? name[0] : 'م',
                              style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800, fontSize: 25))
                          : null,
                    ),
                    const SizedBox(height: 10),
                    Text(name, style: const TextStyle(color: AppColors.paper, fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(email, style: const TextStyle(color: Color(0xFFA9BAC0), fontSize: 12.5)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.paper,
                        side: const BorderSide(color: AppColors.paperDim),
                      ),
                      onPressed: profile == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: profile))),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('تعديل الملف الشخصي'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: Text('الحساب والأمان', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (isMofahhem)
                ListTile(
                  leading: const Icon(Icons.dashboard_outlined),
                  title: const Text('لوحة التحكم'),
                  subtitle: const Text('إنشاء ونشر كورساتك ومتابعة حالتها'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: profile == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => InstructorDashboardScreen(profile: profile))),
                ),
              if (profile?.isAdmin == true)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined, color: AppColors.gold),
                  title: const Text('لوحة التحكم الكاملة'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => context.push('/admin-control'),
                ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('أمان الحساب والأجهزة'),
                subtitle: Text(user.email ?? 'إدارة الأمان والأجهزة'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => context.push('/account-security'),
              ),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.menu_book_outlined), title: const Text('كورساتي والمفضلة'), trailing: const Icon(Icons.chevron_left), onTap: () => DefaultTabController.of(context)?.animateTo(0)),
              ListTile(leading: const Icon(Icons.info_outline), title: const Text('من نحن'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _InfoPage(title: 'من نحن', body: 'Fahimt منصة تعليمية لعرض الكورسات والمحاضرات ومتابعة التعلم من خلال التطبيق والمنصة.')))),
              ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('سياسة الخصوصية'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _InfoPage(title: 'سياسة الخصوصية', body: 'نستخدم بيانات الحساب والشراء والتقدم فقط لتقديم الخدمة وحماية المحتوى وتحسين تجربة المستخدم، وفق سياسة الخصوصية المعتمدة على المنصة.')))),
              ListTile(leading: const Icon(Icons.assignment_return_outlined), title: const Text('سياسة الاسترجاع'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const _InfoPage(title: 'سياسة الاسترجاع', body: 'تخضع طلبات الاسترجاع لشروط سياسة الاسترجاع المنشورة على المنصة، ويتم التعامل معها من خلال الدعم وإدارة المدفوعات.')))),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('تغيير كلمة المرور'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => context.push('/change-password'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.coral),
                title: const Text('تسجيل الخروج', style: TextStyle(color: AppColors.coral)),
                onTap: () async {
                  await AuthService().signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
