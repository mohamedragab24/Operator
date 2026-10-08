import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_functions.dart';
import '../services/firestore_service.dart';
import 'group_video_screen.dart';

/// لوحة تحكم التطبيق ← تسجيلات المحاضرات (للأدمن): اسم المحاضرة، المجموعة، المدرس، التاريخ، المدة، مشاهدة، حذف.
class LectureRecordingsScreen extends StatelessWidget {
  const LectureRecordingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول')));
    return FutureBuilder(
      future: FirestoreService().getUserProfile(user.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snap.data == null || !snap.data!.isAdmin) return Scaffold(appBar: AppBar(), body: const Center(child: Text('ليس لديك صلاحية الدخول')));
        return const _Body();
      },
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  String _q = '';

  static String _date(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate().toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
    }
    return '—';
  }

  static String _dur(dynamic s) {
    final n = (s is num) ? s.toInt() : 0;
    if (n <= 0) return '—';
    final h = n ~/ 3600, m = (n % 3600) ~/ 60, sec = n % 60;
    return h > 0 ? '$hس $mد' : (m > 0 ? '$mد $secث' : '$secث');
  }

  static const _status = {'ready': 'جاهز', 'processing': 'جارٍ المعالجة', 'uploading': 'جارٍ الرفع', 'recording': 'قيد التسجيل', 'failed': 'فشل'};

  Future<void> _delete(String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف التسجيل'),
        content: Text('حذف «$title» نهائيًا من التخزين؟ لا يمكن التراجع.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف'))],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('adminDeleteLectureRecording').call<dynamic>({'id': id});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف التسجيل')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحذف: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيلات المحاضرات')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextField(onChanged: (v) => setState(() => _q = v.trim()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'بحث بالاسم أو المجموعة أو المدرس', border: OutlineInputBorder())),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('lectureRecordings').snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return const Center(child: Text('تعذر تحميل التسجيلات'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs.where((d) {
                  if (_q.isEmpty) return true;
                  final m = d.data();
                  return [m['title'], m['groupName'], m['ownerName']].any((v) => (v ?? '').toString().contains(_q));
                }).toList()
                  ..sort((a, b) => ((b.data()['order'] ?? 0) as num).compareTo((a.data()['order'] ?? 0) as num));
                if (docs.isEmpty) return const Center(child: Text('لا توجد تسجيلات'));
                return ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();
                    final ready = m['status'] == 'ready';
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text((m['title'] ?? 'محاضرة').toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 6),
                            Text('المجموعة: ${m['groupName'] ?? '—'}'),
                            Text('المدرس: ${m['ownerName'] ?? '—'}'),
                            Text('التاريخ: ${_date(m['createdAt'])}   •   المدة: ${_dur(m['durationSec'])}'),
                            Text('الحالة: ${_status[m['status']] ?? m['status'] ?? '—'}'),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                FilledButton.icon(
                                  onPressed: ready ? () => context.push('/admin/recordings/${d.id}?title=${Uri.encodeComponent((m['title'] ?? '').toString())}') : null,
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('مشاهدة'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(onPressed: () => _delete(d.id, (m['title'] ?? '').toString()), icon: const Icon(Icons.delete_outline, color: Colors.red), label: const Text('حذف', style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// مشاهدة تسجيل من لوحة الأدمن (رابط مؤقت من getLectureRecordingUrl).
class AdminRecordingPlayerScreen extends StatelessWidget {
  final String recordingId;
  final String title;
  const AdminRecordingPlayerScreen({super.key, required this.recordingId, required this.title});

  @override
  Widget build(BuildContext context) {
    return GroupVideoScreen(groupId: '', kind: 'admin', itemId: recordingId, title: title);
  }
}
