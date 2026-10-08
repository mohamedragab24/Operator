import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/groups_service.dart';
import '../theme/app_theme.dart';

/// تبويب «المجموعات»: المجموعات التي أنشأها المُفهم + المجموعات التي انضم لها الطالب (تظهر تلقائيًا من منصة فهمت).
class GroupsTab extends StatefulWidget {
  const GroupsTab({super.key});

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> {
  final _service = GroupsService();
  StreamSubscription? _a, _b;
  List<Map<String, dynamic>> _owned = [];
  List<Map<String, dynamic>> _joined = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _loading = false;
      return;
    }
    _a = _service.watchOwned(uid).listen((snap) {
      _owned = snap.docs.map((d) => {'id': d.id, ...d.data(), 'owner': true}).toList();
      if (mounted) setState(() => _loading = false);
    }, onError: (e) {
      if (mounted) setState(() { _error = 'تعذر تحميل المجموعات'; _loading = false; });
    });
    _b = _service.watchMemberships(uid).listen((snap) async {
      final groups = <Map<String, dynamic>>[];
      for (final m in snap.docs) {
        try {
          final g = await _service.getGroup(m.id);
          if (g.exists) groups.add({'id': g.id, ...?g.data(), 'owner': false});
        } catch (_) {/* مجموعة محذوفة أو متوقفة */}
      }
      _joined = groups;
      if (mounted) setState(() => _loading = false);
    }, onError: (e) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _a?.cancel();
    _b?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = <String, Map<String, dynamic>>{};
    for (final g in [..._joined, ..._owned]) {
      all[g['id'] as String] = g;
    }
    final list = all.values.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('المجموعات'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : list.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('لا توجد مجموعات بعد.\nعند دعوتك لمجموعة من منصة فهمت وقبولها ستظهر هنا تلقائيًا.', textAlign: TextAlign.center),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final g = list[i];
                        final frozen = (g['status'] ?? 'active') != 'active';
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: frozen ? Colors.grey.shade300 : AppColors.primaryLight,
                              child: Icon(frozen ? Icons.ac_unit : Icons.groups, color: AppColors.primaryDark),
                            ),
                            title: Text((g['name'] ?? 'مجموعة').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(frozen
                                ? 'المجموعة متوقفة مؤقتًا'
                                : '${g['owner'] == true ? 'أنت المُفهم' : 'المُفهم: ${g['ownerName'] ?? ''}'} • ${g['memberCount'] ?? 0} طالب'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: frozen ? null : () => context.push('/group/${g['id']}'),
                          ),
                        );
                      },
                    ),
    );
  }
}
