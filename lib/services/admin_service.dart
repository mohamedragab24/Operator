import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'api_functions.dart';

class AdminService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchPendingCourses() {
    return _db
        .collection('courses')
        .where('status', isEqualTo: 'pending')
        .orderBy('submittedAt', descending: true)
        .snapshots();
  }

  Future<void> reviewCourse({
    required String courseId,
    required String decision,
    String? rejectionReason,
  }) async {
    if (decision != 'approved' && decision != 'rejected') {
      throw ArgumentError('قرار المراجعة غير صحيح');
    }
    if (decision == 'rejected' && (rejectionReason == null || rejectionReason.trim().isEmpty)) {
      throw ArgumentError('سبب الرفض مطلوب');
    }

    final courseRef = _db.collection('courses').doc(courseId);
    final courseSnap = await courseRef.get();
    if (!courseSnap.exists) throw Exception('الكورس غير موجود');
    final data = courseSnap.data() ?? <String, dynamic>{};
    if ((data['status'] ?? 'pending').toString() != 'pending') {
      throw Exception('الكورس ليس قيد المراجعة حاليًا');
    }

    final user = await _db.collection('users').doc(
      // The signed-in UID is supplied by Firebase Auth through the current profile lookup.
      // This avoids depending on a custom-claims admin role.
      (await _currentUid()),
    ).get();
    final reviewerName = (user.data()?['name'] ?? user.data()?['email'] ?? 'الأدمن').toString();
    final uid = await _currentUid();
    final batch = _db.batch();

    batch.update(courseRef, {
      'status': decision == 'approved' ? 'published' : 'rejected',
      'isPublished': decision == 'approved',
      'reviewedBy': uid,
      'reviewerName': reviewerName,
      'reviewedAt': FieldValue.serverTimestamp(),
      'rejectionReason': decision == 'rejected' ? rejectionReason!.trim() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final reviewRef = courseRef.collection('reviews').doc();
    batch.set(reviewRef, {
      'reviewerId': uid,
      'reviewerName': reviewerName,
      'reviewedAt': FieldValue.serverTimestamp(),
      'decision': decision,
      if (decision == 'rejected') 'rejectionReason': rejectionReason!.trim(),
    });

    final notificationRef = _db.collection('notifications').doc();
    batch.set(notificationRef, {
      'userId': data['instructorId'],
      'title': decision == 'approved' ? 'تم اعتماد الكورس' : 'تم رفض الكورس',
      'message': decision == 'approved'
          ? 'تم اعتماد الكورس وأصبح منشورًا للطلاب.'
          : 'تم رفض الكورس. السبب: ${rejectionReason!.trim()}',
      'type': decision == 'approved' ? 'course_approval' : 'course_rejection',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<String> _currentUid() async {
    final auth = FirebaseAuth.instance;
    final uid = auth.currentUser?.uid;
    if (uid == null) throw Exception('يجب تسجيل الدخول أولاً');
    return uid;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchReviewHistory(String courseId) {
    return _db
        .collection('courses')
        .doc(courseId)
        .collection('reviews')
        .orderBy('reviewedAt', descending: true)
        .snapshots();
  }
}
