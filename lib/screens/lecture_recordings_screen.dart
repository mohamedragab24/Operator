import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_functions.dart';
import '../services/error_center.dart';
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

  /// يرجع سبب المشكلة والحل لو التسجيل فشل أو علق (بدل ترك الحالة «فشل/جارٍ الرفع» بلا تفسير).
  static _Problem? _problem(Map<String, dynamic> m) {
    final st = (m['status'] ?? '').toString();
    if (st == 'failed') {
      final title = (m['errorTitle'] ?? '').toString();
      final cause = (m['errorCause'] ?? '').toString();
      final fix = (m['errorFix'] ?? '').toString();
      if (title.isNotEmpty || cause.isNotEmpty) {
        return _Problem(title.isEmpty ? 'فشل رفع التسجيل' : title, cause, fix, (m['error'] ?? '').toString());
      }
      final raw = (m['error'] ?? '').toString();
      return _Problem('فشل رفع التسجيل', raw == 'no_download_link' ? 'JaaS لم يرسل رابط التسجيل.' : 'السبب التقني: $raw',
          'افتح Vercel ← Logs لمسار /api/jaas/webhook وأرسل الخطأ للمطوّر.', raw);
    }
    if (st == 'uploading') {
      final started = (m['uploadStartedAtMs'] is num) ? (m['uploadStartedAtMs'] as num).toInt() : 0;
      if (started > 0 && DateTime.now().millisecondsSinceEpoch - started > 10 * 60 * 1000) {
        return _Problem('الرفع متوقف منذ أكثر من 10 دقائق',
            'غالبًا تجاوزت العملية حد وقت دالة Vercel (60 ثانية في الخطة المجانية) فانقطعت قبل الانتهاء، فبقيت الحالة «جارٍ الرفع».',
            'ارفع حد maxDuration (خطة Pro) أو قلّل حجم/مدة التسجيل، ثم أعد إرسال حدث RECORDING_UPLOADED من JaaS Console. راجع Vercel ← Logs لمسار /api/jaas/webhook.', 'uploadStartedAtMs=$started');
      }
    }
    if (st == 'processing' || st == 'recording') {
      final ts = m['createdAt'];
      if (ts is Timestamp && DateTime.now().difference(ts.toDate()).inHours >= 6) {
        return _Problem('التسجيل عالق في «${_status[st]}» منذ ساعات',
            'لم يصل حدث RECORDING_UPLOADED من JaaS (Webhook غير مضبوط أو الأحداث الثلاثة غير مفعّلة).',
            'JaaS Console ← Webhooks: تأكد من الرابط وسر JAAS_WEBHOOK_SECRET وتفعيل RECORDING_STARTED / ENDED / UPLOADED.', '');
      }
    }
    return null;
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
    } catch (e, st) {
      ErrorCenter.instance.report(e, where: 'حذف تسجيل محاضرة', stack: st);
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
                if (snap.hasError) {
                  final err = ErrorCenter.explain(snap.error!, where: 'تحميل تسجيلات المحاضرات');
                  return Center(child: Padding(padding: const EdgeInsets.all(16), child: _ProblemBox(problem: _Problem(err.title, err.cause ?? '', err.fix ?? '', err.technical))));
                }
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
                            if (_problem(m) != null) _ProblemBox(problem: _problem(m)!),
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


class _Problem {
  final String title, cause, fix, technical;
  const _Problem(this.title, this.cause, this.fix, this.technical);
}

class _ProblemBox extends StatelessWidget {
  final _Problem problem;
  const _ProblemBox({required this.problem});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCA5A5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(problem.title, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB91C1C), fontSize: 13)),
          if (problem.cause.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('السبب: ${problem.cause}', style: const TextStyle(fontSize: 12))),
          if (problem.fix.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
              child: Text('المطلوب: ${problem.fix}', style: const TextStyle(fontSize: 12, color: Color(0xFF064E3B))),
            ),
          if (problem.technical.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText(problem.technical, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, color: Colors.black54))),
        ],
      ),
    );
  }
}
