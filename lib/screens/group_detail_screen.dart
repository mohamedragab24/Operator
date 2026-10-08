import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/groups_service.dart';
import '../services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/api_functions.dart';
import '../services/error_center.dart';

/// داخل المجموعة: الفيديوهات، ملفات PDF، الاختبارات، الجلسات المباشرة والمسجلة. كل شيء يُفتح داخل التطبيق.
class GroupDetailScreen extends StatelessWidget {
  final String groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final service = GroupsService();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: service.watchGroup(groupId),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('لا يمكنك الوصول لهذه المجموعة')));
        }
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final g = snap.data!.data();
        if (g == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('المجموعة غير موجودة')));
        if ((g['status'] ?? 'active') != 'active') {
          return Scaffold(appBar: AppBar(title: Text((g['name'] ?? '').toString())), body: const Center(child: Text('المجموعة متوقفة مؤقتًا')));
        }
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text((g['name'] ?? 'مجموعة').toString()),
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(icon: Icon(Icons.play_circle_outline), text: 'الفيديوهات'),
                  Tab(icon: Icon(Icons.picture_as_pdf_outlined), text: 'ملفات PDF'),
                  Tab(icon: Icon(Icons.quiz_outlined), text: 'الاختبارات'),
                  Tab(icon: Icon(Icons.video_camera_front_outlined), text: 'الجلسات'),
                ],
              ),
            ),
            body: Column(
              children: [
                _LiveBanner(groupId: groupId, service: service),
                Expanded(
                  child: TabBarView(
                    children: [
                      _ContentList(groupId: groupId, kind: 'videos', icon: Icons.play_circle_fill, empty: 'لا توجد فيديوهات بعد', onOpen: (id, title) => context.push('/group/$groupId/video/$id?title=${Uri.encodeComponent(title)}&kind=videos')),
                      _ContentList(groupId: groupId, kind: 'files', icon: Icons.picture_as_pdf, empty: 'لا توجد ملفات بعد', onOpen: (id, title) => context.push('/group/$groupId/pdf/$id?title=${Uri.encodeComponent(title)}')),
                      _ContentList(groupId: groupId, kind: 'quizzes', icon: Icons.quiz, empty: 'لا توجد اختبارات بعد', subtitle: (d) => '${d['questionCount'] ?? 0} سؤال', onOpen: (id, title) => context.push('/group/$groupId/quiz/$id')),
                      _ContentList(groupId: groupId, kind: 'recordings', icon: Icons.slow_motion_video, empty: 'لا توجد جلسات مسجلة بعد', ready: (d) => d['status'] == 'ready', subtitle: (d) => d['status'] == 'ready' ? _dur(d['durationSec']) : 'جارٍ المعالجة', onOpen: (id, title) => context.push('/group/$groupId/video/$id?title=${Uri.encodeComponent(title)}&kind=recordings')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _dur(dynamic s) {
    final n = (s is num) ? s.toInt() : 0;
    if (n <= 0) return 'تسجيل جلسة';
    final h = n ~/ 3600, m = (n % 3600) ~/ 60;
    return h > 0 ? '$hس $mد' : '$mد';
  }
}

class _LiveBanner extends StatelessWidget {
  final String groupId;
  final GroupsService service;
  const _LiveBanner({required this.groupId, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: service.watchLiveSessions(groupId),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          children: docs.map((d) {
            return Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.green.shade200)),
              child: Row(
                children: [
                  const Icon(Icons.sensors, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text('جلسة مباشرة الآن: ${d.data()['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold))),
                  FilledButton(onPressed: () => context.push('/group/$groupId/session/${d.id}'), child: const Text('دخول الاجتماع')),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ContentList extends StatelessWidget {
  final String groupId;
  final String kind;
  final IconData icon;
  final String empty;
  final void Function(String id, String title) onOpen;
  final String Function(Map<String, dynamic>)? subtitle;
  final bool Function(Map<String, dynamic>)? ready;
  const _ContentList({required this.groupId, required this.kind, required this.icon, required this.empty, required this.onOpen, this.subtitle, this.ready});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: GroupsService().watchContent(groupId, kind),
      builder: (context, snap) {
        if (snap.hasError) return const Center(child: Text('تعذر تحميل المحتوى'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return Center(child: Text(empty));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final title = (d['title'] ?? 'بدون عنوان').toString();
            final ok = ready == null ? true : ready!(d);
            return Card(
              child: ListTile(
                leading: Icon(icon, size: 30),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: subtitle == null ? null : Text(subtitle!(d)),
                trailing: ok ? const Icon(Icons.chevron_left) : const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                onTap: ok ? () => onOpen(docs[i].id, title) : null,
              ),
            );
          },
        );
      },
    );
  }
}

/// شاشة دخول الاجتماع: تفتح الاجتماع داخل التطبيق مباشرة (من زر المجموعة أو من رابط المنصة fahmny://group/..).
class GroupSessionScreen extends StatefulWidget {
  final String groupId;
  final String sessionId;
  const GroupSessionScreen({super.key, required this.groupId, required this.sessionId});

  @override
  State<GroupSessionScreen> createState() => _GroupSessionScreenState();
}

class _GroupSessionScreenState extends State<GroupSessionScreen> {
  bool _joining = false;
  String? _error;
  bool _recordHint = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _join());
  }

  Future<void> _join() async {
    if (_joining) return;
    setState(() { _joining = true; _error = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('سجّل الدخول أولًا');
      final profile = await FirestoreService().getUserProfile(user.uid);
      final hint = await GroupsService().joinSession(
        groupId: widget.groupId,
        sessionId: widget.sessionId,
        displayName: (profile == null || profile.name.isEmpty) ? 'مستخدم' : profile.name,
        email: profile?.email,
        avatar: profile?.photoUrl,
      );
      if (mounted) setState(() => _recordHint = hint);
    } catch (e, st) {
      if (e is! FirebaseFunctionsException) ErrorCenter.instance.report(e, where: 'دخول الجلسة المباشرة', stack: st);
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الجلسة المباشرة')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.video_call, size: 80),
              const SizedBox(height: 12),
              if (_joining) const CircularProgressIndicator(),
              if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
              if (_recordHint) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('هذه الجلسة مسجلة: اضغط زر التسجيل داخل الاجتماع لبدء التسجيل.', textAlign: TextAlign.center)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _joining ? null : _join, icon: const Icon(Icons.play_arrow), label: const Text('دخول الاجتماع')),
              TextButton(onPressed: () => context.canPop() ? context.pop() : context.go('/home'), child: const Text('رجوع')),
            ],
          ),
        ),
      ),
    );
  }
}
