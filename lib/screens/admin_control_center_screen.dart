import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/api_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../services/admin_service.dart';
import '../services/r2_worker_service.dart';

class AdminControlCenterScreen extends StatefulWidget {
  const AdminControlCenterScreen({super.key});

  @override
  State<AdminControlCenterScreen> createState() => _AdminControlCenterScreenState();
}

class _AdminControlCenterScreenState extends State<AdminControlCenterScreen> {
  int tab = 0;
  final db = FirebaseFirestore.instance;
  final fn = FirebaseFunctions.instanceFor(region: 'us-central1');
  bool uploading = false;

  Future<void> _ban(String uid) async {
    final reason = TextEditingController();
    int days = 7;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حظر المستخدم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: reason, decoration: const InputDecoration(labelText: 'سبب الحظر')),
            TextField(
              decoration: const InputDecoration(labelText: 'عدد الأيام'),
              keyboardType: TextInputType.number,
              onChanged: (value) => days = int.tryParse(value) ?? 7,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حظر')),
        ],
      ),
    );
    if (ok == true && reason.text.trim().isNotEmpty) {
      await fn.httpsCallable('setUserBan').call({
        'uid': uid,
        'reason': reason.text.trim(),
        'days': days,
      });
    }
  }

  Future<String?> _pickNotificationImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
      maxWidth: 1600,
    );
    if (picked == null) return null;
    if (mounted) setState(() => uploading = true);
    try {
      final bytes = await File(picked.path).readAsBytes();
      final key =
          'notifications/${DateTime.now().millisecondsSinceEpoch}_${picked.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
      final url = R2WorkerService.keyToUrl(key);
      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'image/jpeg'},
        body: bytes,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) return url;
      throw Exception('R2 upload ${response.statusCode}');
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _notify() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final campaign = TextEditingController();
    final description = TextEditingController();
    String imageUrl = '';
    DateTime when = DateTime.now().add(const Duration(minutes: 5));

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('إشعار مجدول'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
                TextField(controller: body, decoration: const InputDecoration(labelText: 'الرسالة')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: uploading
                      ? null
                      : () async {
                          final url = await _pickNotificationImage();
                          if (url != null) {
                            imageUrl = url;
                            setLocal(() {});
                          }
                        },
                  icon: const Icon(Icons.image),
                  label: Text(imageUrl.isEmpty ? 'رفع صورة من الهاتف' : 'تم رفع الصورة ✓'),
                ),
                if (imageUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Image.network(imageUrl, height: 80, fit: BoxFit.cover),
                  ),
                TextField(controller: campaign, decoration: const InputDecoration(labelText: 'اسم الحملة')),
                TextField(controller: description, decoration: const InputDecoration(labelText: 'الوصف')),
                ListTile(
                  title: Text('وقت الإرسال: ${when.toLocal()}'),
                  trailing: const Icon(Icons.schedule),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: ctx,
                      initialDate: when,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date == null) return;
                    final time = await showTimePicker(
                      context: ctx,
                      initialTime: TimeOfDay.fromDateTime(when),
                    );
                    if (time != null) {
                      when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                      setLocal(() {});
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('جدولة')),
          ],
        ),
      ),
    );

    if (ok == true && title.text.trim().isNotEmpty && body.text.trim().isNotEmpty) {
      await fn.httpsCallable('scheduleNotification').call({
        'title': title.text.trim(),
        'body': body.text.trim(),
        'imageUrl': imageUrl,
        'campaign': campaign.text.trim(),
        'description': description.text.trim(),
        'sendAt': when.toUtc().toIso8601String(),
        'audience': 'all',
      });
    }
  }

  Future<void> _admin() async {
    final identifier = TextEditingController();
    String type = 'auto';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        title: const Text('إضافة صلاحية أدمن'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('استخدم حسابًا موجودًا في Firebase. لا يتم إنشاء حساب جديد ولا نطلب اسمًا أو كلمة مرور.'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(labelText: 'نوع المعرف'),
              items: const [DropdownMenuItem(value: 'auto', child: Text('تحديد تلقائي')), DropdownMenuItem(value: 'uid', child: Text('UID')), DropdownMenuItem(value: 'email', child: Text('البريد الإلكتروني')), DropdownMenuItem(value: 'phone', child: Text('رقم الهاتف'))],
              onChanged: (v) => setLocal(() => type = v ?? 'auto'),
            ),
            TextField(controller: identifier, decoration: const InputDecoration(labelText: 'UID أو البريد أو رقم الهاتف')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
        ],
      )),
    );
    if (ok == true && identifier.text.trim().isNotEmpty) {
      await fn.httpsCallable('grantAdmin').call({'identifier': identifier.text.trim(), 'type': type});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_meetings(), _courses(), _mufahems(), _users(), _notifications(), _admins()];
    return Scaffold(
      appBar: AppBar(title: const Text('مركز الاعتماد الموحد')),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tab('المحاضرات', 0),
                _tab('مراجعة الكورسات', 1),
                _tab('المفهّمين', 2),
                _tab('المستخدمون', 3),
                _tab('الإشعارات', 4),
                _tab('حسابات الأدمن', 5),
              ],
            ),
          ),
          Expanded(child: pages[tab]),
        ],
      ),
    );
  }

  Widget _tab(String title, int index) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: ChoiceChip(
        label: Text(title),
        selected: tab == index,
        onSelected: (_) => setState(() => tab = index),
      ),
    );
  }

  Widget _meetings() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('istifhams').where('status', whereIn: ['paid', 'completed']).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return ListView(
          children: docs.map((doc) {
            final data = doc.data();
            final recording = (data['recordingUrl'] ?? data['recordingR2Url'] ?? '').toString();
            return ListTile(
              leading: const Icon(Icons.video_call),
              title: Text((data['title'] ?? 'محاضرة').toString()),
              subtitle: Text('${data['meetingTime'] ?? 'غير محدد'}'),
              trailing: recording.isEmpty
                  ? const Text('لا يوجد تسجيل')
                  : IconButton(
                      icon: const Icon(Icons.play_circle),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('مراجعة فيديو المحاضرة'),
                          content: SelectableText(recording),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('إغلاق'),
                            ),
                          ],
                        ),
                      ),
                    ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _courses() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('courses').where('status', isEqualTo: 'pending').snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return ListView(
          children: docs.map((doc) {
            final data = doc.data();
            return ListTile(
              title: Text((data['title'] ?? 'بدون اسم').toString()),
              trailing: Wrap(
                children: [
                  IconButton(
                    icon: const Icon(Icons.check),
                    onPressed: () => AdminService().reviewCourse(
                      courseId: doc.id,
                      decision: 'approved',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      final reason = TextEditingController();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('سبب الرفض'),
                          content: TextField(controller: reason),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('إلغاء'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('رفض'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && reason.text.trim().isNotEmpty) {
                        await AdminService().reviewCourse(
                          courseId: doc.id,
                          decision: 'rejected',
                          rejectionReason: reason.text.trim(),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _mufahems() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').where('mode', isEqualTo: 'mofahhem').limit(200).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return ListView(
          children: docs.map((doc) {
            final data = doc.data();
            return ListTile(
              title: Text((data['name'] ?? data['email'] ?? doc.id).toString()),
              subtitle: Text('${data['email'] ?? ''}'),
              trailing: IconButton(icon: const Icon(Icons.block), onPressed: () => _ban(doc.id)),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _users() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').limit(200).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return ListView(
          children: docs.map((doc) {
            final data = doc.data();
            return ListTile(
              title: Text((data['name'] ?? data['email'] ?? doc.id).toString()),
              subtitle: Text('${data['email'] ?? ''}'),
              trailing: IconButton(icon: const Icon(Icons.block), onPressed: () => _ban(doc.id)),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _notifications() {
    return Center(
      child: FilledButton.icon(
        onPressed: _notify,
        icon: const Icon(Icons.notifications_active),
        label: const Text('إرسال / جدولة إشعار مع رفع صورة'),
      ),
    );
  }

  Widget _admins() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').where('isAdmin', isEqualTo: true).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            FilledButton.icon(
              onPressed: _admin,
              icon: const Icon(Icons.person_add),
              label: const Text('إضافة أدمن'),
            ),
            const SizedBox(height: 12),
            ...docs.map((doc) {
              final data = doc.data();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: Text((data['name'] ?? 'بدون اسم').toString()),
                  subtitle: Text((data['email'] ?? doc.id).toString()),
                  trailing: Text(data['role']?.toString() ?? 'admin'),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
