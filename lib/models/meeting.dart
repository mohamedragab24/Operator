import 'package:cloud_firestore/cloud_firestore.dart';

class Meeting {
  final String id;
  final String title;
  final String status;
  final String mustafhemId;
  final String mufhemId;
  final String mustafhemName;
  final String mufhemName;
  final DateTime? meetingTime;
  final num amount;

  Meeting({required this.id, required this.title, required this.status, required this.mustafhemId, required this.mufhemId, required this.mustafhemName, required this.mufhemName, required this.meetingTime, required this.amount});

  factory Meeting.fromMap(String id, Map<String,dynamic> d) {
    final raw = d['meetingTime'];
    DateTime? time;
    if (raw is Timestamp) time = raw.toDate();
    else if (raw is DateTime) time = raw;
    else if (raw is String) time = DateTime.tryParse(raw);
    return Meeting(
      id: id,
      title: (d['title'] ?? 'محاضرة').toString(),
      status: (d['status'] ?? '').toString(),
      mustafhemId: (d['mustafhemId'] ?? '').toString(),
      mufhemId: (d['mufhemId'] ?? '').toString(),
      mustafhemName: (d['mustafhemName'] ?? '').toString(),
      mufhemName: (d['mufhemName'] ?? '').toString(),
      meetingTime: time,
      amount: (d['amount'] ?? 0) as num,
    );
  }
}
