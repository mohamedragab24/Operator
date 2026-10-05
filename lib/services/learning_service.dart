import 'package:cloud_firestore/cloud_firestore.dart';

class LearningService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchProgress(String uid, String courseId) =>
      _db.collection('progress').where('uid', isEqualTo: uid).where('courseId', isEqualTo: courseId).snapshots();

  Future<void> saveBookmark({required String uid, required String courseId, required String lessonId, required int seconds, String? label}) async {
    final id = '${uid}_${courseId}_${lessonId}_$seconds';
    await _db.collection('bookmarks').doc(id).set({
      'uid': uid, 'courseId': courseId, 'lessonId': lessonId, 'seconds': seconds,
      'label': (label ?? '').trim(), 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchBookmarks(String uid, String courseId, String lessonId) =>
      _db.collection('bookmarks').where('uid', isEqualTo: uid).where('courseId', isEqualTo: courseId).where('lessonId', isEqualTo: lessonId).orderBy('seconds').snapshots();

  Future<void> deleteBookmark(String id) => _db.collection('bookmarks').doc(id).delete();

  Future<void> saveNote({required String uid, required String courseId, required String lessonId, required int seconds, required String text}) async {
    final ref = _db.collection('notes').doc();
    await ref.set({
      'uid': uid, 'courseId': courseId, 'lessonId': lessonId, 'seconds': seconds,
      'text': text.trim(), 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchNotes(String uid, String courseId, String lessonId) =>
      _db.collection('notes').where('uid', isEqualTo: uid).where('courseId', isEqualTo: courseId).where('lessonId', isEqualTo: lessonId).orderBy('seconds').snapshots();

  Future<void> deleteNote(String id) => _db.collection('notes').doc(id).delete();

  Future<void> reportContent({required String uid, required String courseId, String? lessonId, required String reason, String? details}) async {
    await _db.collection('contentReports').add({
      'uid': uid, 'courseId': courseId, if (lessonId != null) 'lessonId': lessonId,
      'reason': reason, 'details': details ?? '', 'status': 'open', 'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
