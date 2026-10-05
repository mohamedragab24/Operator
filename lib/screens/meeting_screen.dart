import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/meeting.dart';
import '../services/meeting_service.dart';
import '../services/firestore_service.dart';

class MeetingScreen extends StatelessWidget {
  final String requestId;
  const MeetingScreen({super.key, required this.requestId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('istifhams').doc(requestId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final data = snap.data!.data();
        if (data == null) return const Scaffold(body: Center(child: Text('المحاضرة غير موجودة')));
        final meeting = Meeting.fromMap(requestId, data);
        final time = meeting.meetingTime;
        final now = DateTime.now();
        final canJoin = time != null && now.isAfter(time.subtract(const Duration(minutes: 5))) && now.isBefore(time.add(const Duration(hours: 6)));
        return Scaffold(
          appBar: AppBar(title: const Text('المحاضرة المباشرة')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.video_call, size: 80),
                  const SizedBox(height: 16),
                  Text(meeting.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(time == null ? 'لم يتم تحديد الموعد' : time.toLocal().toString(), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: canJoin ? () async {
                      final uid = FirebaseAuth.instance.currentUser?.uid;
                      if (uid == null) return;
                      final profile = await FirestoreService().getUserProfile(uid);
                      if (profile == null) return;
                      await MeetingService().join(meeting, displayName: profile.name.isEmpty ? 'مستخدم' : profile.name, email: profile.email, avatar: profile.photoUrl, moderator: profile.isAdmin || profile.isMofahhem);
                    } : null,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(canJoin ? 'دخول المحاضرة' : 'لم يبدأ الموعد بعد'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
