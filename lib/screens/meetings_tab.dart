import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/meeting.dart';
import '../services/meeting_service.dart';
import '../services/firestore_service.dart';

class MeetingsTab extends StatefulWidget { const MeetingsTab({super.key}); @override State<MeetingsTab> createState()=>_MeetingsTabState(); }
class _MeetingsTabState extends State<MeetingsTab> {
  final _service=MeetingService();
  List<Meeting> _items=[];
  StreamSubscription<QuerySnapshot<Map<String,dynamic>>>? _a,_b;
  @override void initState(){super.initState(); final uid=FirebaseAuth.instance.currentUser?.uid; if(uid!=null){_a=_service.watchStudent(uid).listen((_)=>_reload(uid)); _b=_service.watchTeacher(uid).listen((_)=>_reload(uid)); _reload(uid);}}
  Future<void> _reload(String uid) async { final results=await Future.wait([_service.watchStudent(uid).first,_service.watchTeacher(uid).first]); final map=<String,Meeting>{}; for(final s in results){for(final d in s.docs){map[d.id]=Meeting.fromMap(d.id,d.data());}} final list=map.values.toList()..sort((a,b)=>(a.meetingTime??DateTime(2100)).compareTo(b.meetingTime??DateTime(2100))); if(mounted)setState(()=>_items=list); }
  @override void dispose(){_a?.cancel();_b?.cancel();super.dispose();}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المحاضرات'),
        centerTitle: true,
      ),
      body: _items.isEmpty
          ? const Center(child: Text('لا توجد محاضرات مجدولة حالياً'))
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final m = _items[i];
                final t = m.meetingTime;
                final can = t != null &&
                    DateTime.now().isAfter(
                        t.subtract(const Duration(minutes: 5))) &&
                    DateTime.now().isBefore(
                        t.add(const Duration(hours: 6)));
                final subtitle = t == null
                    ? 'الموعد غير محدد'
                    : '${t.toLocal()}\\n${m.mufhemName.isNotEmpty ? "المُفهّم: ${m.mufhemName}" : ""}';

                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.video_camera_front),
                    ),
                    title: Text(
                      m.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(subtitle),
                    isThreeLine: true,
                    trailing: FilledButton(
                      onPressed: can
                          ? () async {
                              final user =
                                  FirebaseAuth.instance.currentUser;
                              if (user == null) return;
                              final p = await FirestoreService()
                                  .getUserProfile(user.uid);
                              if (p == null) return;
                              await _service.join(
                                m,
                                displayName:
                                    p.name.isEmpty ? 'مستخدم' : p.name,
                                email: p.email,
                                avatar: p.photoUrl,
                                moderator: p.isAdmin || p.isMofahhem,
                              );
                            }
                          : null,
                      child: Text(can ? 'دخول' : 'لم يبدأ'),
                    ),
                  ),
                );
              },
            ),
    );
  }

}
