import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/groups_service.dart';
import '../services/api_functions.dart' show FirebaseFunctionsException;

/// حل اختبار المجموعة داخل التطبيق (الاختياري يُصحَّح تلقائيًا، والمقالي يراجعه المُفهم).
class GroupQuizScreen extends StatefulWidget {
  final String groupId;
  final String quizId;
  const GroupQuizScreen({super.key, required this.groupId, required this.quizId});

  @override
  State<GroupQuizScreen> createState() => _GroupQuizScreenState();
}

class _GroupQuizScreenState extends State<GroupQuizScreen> {
  Map<String, dynamic>? _quiz;
  String? _error;
  List<dynamic> _answers = [];
  final List<TextEditingController> _ctrls = [];
  bool _busy = false;
  Map<String, dynamic>? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await FirebaseFirestore.instance.collection('groups').doc(widget.groupId).collection('quizzes').doc(widget.quizId).get();
      final q = s.data();
      if (q == null) throw Exception('missing');
      final qs = (q['questions'] as List?) ?? const [];
      _answers = List<dynamic>.filled(qs.length, null);
      for (var i = 0; i < qs.length; i++) { _ctrls.add(TextEditingController()); }
      if (mounted) setState(() => _quiz = q);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحميل الاختبار');
    }
  }

  Future<void> _submit() async {
    final qs = (_quiz!['questions'] as List);
    final out = <dynamic>[];
    for (var i = 0; i < qs.length; i++) {
      final type = (qs[i] as Map)['type'];
      if (type == 'essay') { out.add(_ctrls[i].text.trim()); } else {
        if (_answers[i] == null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('أجب عن السؤال ${i + 1}')));
          return;
        }
        out.add(_answers[i]);
      }
    }
    setState(() => _busy = true);
    try {
      final r = await GroupsService().submitQuiz(groupId: widget.groupId, quizId: widget.quizId, answers: out);
      if (mounted) setState(() => _result = r);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'تعذر إرسال الاختبار')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر إرسال الاختبار')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quiz;
    return Scaffold(
      appBar: AppBar(title: Text((q?['title'] ?? 'اختبار').toString())),
      body: _error != null
          ? Center(child: Text(_error!))
          : q == null
              ? const Center(child: CircularProgressIndicator())
              : _result != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.check_circle, size: 72, color: Colors.green),
                          const SizedBox(height: 12),
                          Text('تم إرسال الاختبار', style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text('درجة الأسئلة الاختيارية: ${_result!['autoScore']} / ${_result!['autoMax']}'),
                          if (_result!['pendingReview'] == true) const Text('الأسئلة المقالية بانتظار مراجعة المُفهم'),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('رجوع')),
                        ]),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        for (var i = 0; i < (q['questions'] as List).length; i++) _question(i, (q['questions'] as List)[i] as Map),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('إرسال الاختبار')),
                      ],
                    ),
    );
  }

  Widget _question(int i, Map q) {
    final options = (q['options'] as List?) ?? const [];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${i + 1}. ${q['text']}  (${q['points']} درجة)', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (q['type'] == 'essay')
              TextField(controller: _ctrls[i], maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'اكتب إجابتك'))
            else
              for (var o = 0; o < options.length; o++)
                RadioListTile<int>(
                  dense: true,
                  value: o,
                  groupValue: _answers[i] as int?,
                  title: Text(options[o].toString()),
                  onChanged: (v) => setState(() => _answers[i] = v),
                ),
          ],
        ),
      ),
    );
  }
}
