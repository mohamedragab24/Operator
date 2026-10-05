import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class InstructorDashboardScreen extends StatelessWidget {
  final UserProfile profile;
  const InstructorDashboardScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('لوحة التحكم')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.add)),
            title: const Text('نشر كورس جديد', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('الكورس يذهب للمراجعة قبل نشره للطلاب'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCourseScreen())),
          ),
        ),
        const SizedBox(height: 16),
        const Text('كورساتي', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirestoreService().watchMyCourses(FirebaseAuth.instance.currentUser!.uid),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
            final docs = snap.data!.docs;
            if (docs.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Text('لم تنشر أي كورسات بعد.', textAlign: TextAlign.center));
            return Column(
              children: docs.map((d) {
                final data = d.data();
                final status = (data['status'] ?? 'pending').toString();
                final label = status == 'published' ? 'منشور' : status == 'rejected' ? 'مرفوض' : 'قيد المراجعة';
                return Card(
                  child: ListTile(
                    title: Text((data['title'] ?? 'بدون عنوان').toString()),
                    subtitle: Text(label),
                    trailing: Icon(status == 'published' ? Icons.check_circle : status == 'rejected' ? Icons.cancel : Icons.hourglass_top),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    ),
  );
}

class CreateCourseScreen extends StatefulWidget {
  const CreateCourseScreen({super.key});
  @override
  State<CreateCourseScreen> createState() => _CreateCourseScreenState();
}

class _CreateCourseScreenState extends State<CreateCourseScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _thumbnail = TextEditingController();
  String _category = 'برمجة';
  bool _loading = false;
  final _categories = const ['برمجة', 'تصميم', 'تسويق', 'بيانات'];

  @override
  void dispose() {
    _title.dispose(); _description.dispose(); _price.dispose(); _thumbnail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final description = _description.text.trim();
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (title.isEmpty || description.isEmpty || price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أكمل العنوان والوصف والسعر بشكل صحيح')));
      return;
    }
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final profile = await FirestoreService().getUserProfile(user.uid);
      final name = profile?.name.isNotEmpty == true ? profile!.name : (user.displayName ?? 'المُفهّم');
      await FirestoreService().createPendingCourse(
        uid: user.uid,
        instructorName: name,
        title: title,
        description: description,
        category: _category,
        price: price,
        thumbnailUrl: _thumbnail.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال الكورس للمراجعة')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الكورس: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('نشر كورس جديد')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'عنوان الكورس')),
        const SizedBox(height: 12),
        TextField(controller: _description, maxLines: 5, decoration: const InputDecoration(labelText: 'وصف الكورس')),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: const InputDecoration(labelText: 'التصنيف'),
          items: _categories.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 12),
        TextField(controller: _price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر')),
        const SizedBox(height: 12),
        TextField(controller: _thumbnail, decoration: const InputDecoration(labelText: 'رابط صورة الكورس (اختياري)')),
        const SizedBox(height: 22),
        ElevatedButton(onPressed: _loading ? null : _submit, child: _loading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('إرسال للمراجعة')),
      ],
    ),
  );
}
