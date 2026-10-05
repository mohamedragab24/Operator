import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'api_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import '../models/lesson.dart';
import '../models/user_profile.dart';
import 'r2_worker_service.dart';

class FirestoreService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // ==================== COURSES ====================

  Stream<List<Course>> watchCourses({String? category}) {
    Query<Map<String, dynamic>> query = _db
        .collection('courses')
        .where('status', isEqualTo: 'published');

    if (category != null && category != 'الكل') {
      query = query.where('category', isEqualTo: category);
    }

    return query.snapshots().map(
          (snapshot) {
            final courses = snapshot.docs
                .map(
                  (doc) => Course.fromMap(
                    doc.id,
                    doc.data(),
                  ),
                )
                .toList();

            // Keep the app catalog deterministic and aligned with the
            // platform's course list.
            courses.sort(
              (a, b) => a.title.toLowerCase().compareTo(
                    b.title.toLowerCase(),
                  ),
            );
            return courses;
          },
        );
  }

  Future<List<Course>> getPublishedCoursesOnce({String? category}) async {
    Query<Map<String, dynamic>> query = _db.collection('courses').where('status', isEqualTo: 'published');
    if (category != null && category != 'الكل') {
      query = query.where('category', isEqualTo: category);
    }
    final snapshot = await query.get();
    final courses = snapshot.docs.map((doc) => Course.fromMap(doc.id, doc.data())).toList();
    courses.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return courses;
  }

  /// Firebase first -> Cloudflare R2 manifest -> last local copy.
  /// Never fails just because the domain/deployment changed.
  Future<Course?> getCourse(String courseId) async {
    Map<String, dynamic>? raw;
    try {
      final doc = await _db.collection('courses').doc(courseId).get().timeout(const Duration(seconds: 8));
      if (doc.exists && doc.data() != null) raw = Map<String, dynamic>.from(doc.data()!);
    } catch (_) {}
    raw ??= await R2WorkerService.getJson('courses/$courseId/manifest.json');
    if (raw != null) {
      final course = Course.fromMap(courseId, raw);
      _cacheCourse(courseId, raw);
      return course;
    }
    final cached = await _readCachedCourse(courseId);
    return cached == null ? null : Course.fromMap(courseId, cached);
  }

  Future<void> _cacheCourse(String id, Map<String, dynamic> raw) async {
    try {
      final safe = jsonDecode(jsonEncode(raw, toEncodable: (o) => o.toString())) as Map<String, dynamic>;
      safe.remove('lessons');
      (await SharedPreferences.getInstance()).setString('course_cache_$id', jsonEncode(safe));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> _readCachedCourse(String id) async {
    try {
      final s = (await SharedPreferences.getInstance()).getString('course_cache_$id');
      return s == null ? null : Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) { return null; }
  }

  Future<List<Course>> getCoursesByIds(List<String> ids) async {
    final clean = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (clean.isEmpty) return [];
    // Firebase -> R2 manifest -> local copy, per course, in parallel.
    final results = await Future.wait(clean.map((id) => getCourse(id)));
    return results.whereType<Course>().toList();
  }

  Future<List<Lesson>> getLessons(String courseId) async {
    try {
      final snap = await _db.collection('courses').doc(courseId).collection('lessons').orderBy('order').get();
      if (snap.docs.isNotEmpty) return snap.docs.map((d) => Lesson.fromMap(d.id, courseId, d.data())).toList();
    } catch (_) {}
    final fallback = await R2WorkerService.getJson('courses/$courseId/manifest.json');
    final raw = fallback?['lessons'];
    if (raw is List) {
      return raw.whereType<Map>().map((m) => Lesson.fromMap((m['id'] ?? m['lessonId'] ?? '').toString(), courseId, Map<String, dynamic>.from(m))).where((l) => l.id.isNotEmpty).toList()..sort((a,b) => a.order.compareTo(b.order));
    }
    return [];
  }

  Stream<List<Lesson>> watchLessons(String courseId) {
    return _db.collection('courses').doc(courseId).collection('lessons').orderBy('order').snapshots().asyncMap((snapshot) async {
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => Lesson.fromMap(doc.id, courseId, doc.data())).toList();
      }
      return getLessons(courseId);
    }).handleError((_) async {
      return await getLessons(courseId);
    });
  }

  // ==================== USERS ====================

  Future<UserProfile?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();

    if (!doc.exists || doc.data() == null) {
      return null;
    }

    return UserProfile.fromMap(
      doc.id,
      doc.data()!,
    );
  }

  Stream<UserProfile?> watchUserProfile(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map(
          (doc) => doc.exists && doc.data() != null
              ? UserProfile.fromMap(
                  doc.id,
                  doc.data()!,
                )
              : null,
        );
  }

  Future<void> ensureUserProfile({
    required String uid,
    String? name,
    String? email,
    String? phone,
  }) async {
    final ref = _db.collection('users').doc(uid);
    final existing = await ref.get();

    await ref.set(
      {
        if (name != null && name.isNotEmpty) 'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (!existing.exists) ...{
          'joinedAt': FieldValue.serverTimestamp(),
          'mode': 'mostafhem',
        },
        'lastLoginAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updateUserProfile({
    required String uid,
    String? name,
    String? photoUrl,
    String? mode,
  }) async {
    final data = <String, dynamic>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (mode != null && (mode == 'mofahhem' || mode == 'mostafhem')) 'mode': mode,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  Future<String> createPendingCourse({
    required String uid,
    required String instructorName,
    required String title,
    required String description,
    required String category,
    required double price,
    String thumbnailUrl = '',
  }) async {
    final ref = await _db.collection('courses').add({
      'title': title.trim(),
      'description': description.trim(),
      'instructorName': instructorName.trim(),
      'instructorUid': uid,
      'ownerUid': uid,
      'createdBy': uid,
      'category': category,
      'price': price,
      'rating': 0,
      'studentsCount': 0,
      'lessonsCount': 0,
      'durationLabel': '',
      'features': <String>[],
      'thumbnailUrl': thumbnailUrl.trim(),
      'status': 'pending',
      'isPublished': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMyCourses(String uid) {
    return _db.collection('courses').where('ownerUid', isEqualTo: uid).snapshots();
  }

  // ==================== PURCHASES ====================

  Future<bool> hasPurchased(
    String uid,
    String courseId,
  ) async {
    try {
      final doc = await _db.collection('purchases').doc('${uid}_$courseId').get().timeout(const Duration(seconds: 8));
      if (doc.exists && doc.data() != null && doc.data()!['status'] == 'completed') { _cachePurchase(uid, courseId, true); return true; }

      final legacy = await _db.collection('users').doc(uid).collection('purchases').doc(courseId).get();
      if (legacy.exists && legacy.data() != null && legacy.data()!['status'] != 'cancelled' && legacy.data()!['status'] != 'refunded') { _cachePurchase(uid, courseId, true); return true; }
      _cachePurchase(uid, courseId, false);
      return false;
    } catch (_) {
      // Firebase-first. If Firestore is temporarily unavailable, ask the
      // server to perform the R2 disaster-recovery entitlement check.
      try {
        final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('checkCourseAccess')
            .call<Map<String, dynamic>>({'courseId': courseId});
        final ok = result.data['purchased'] == true;
        _cachePurchase(uid, courseId, ok);
        return ok;
      } catch (_) {
        // Both Firebase and the R2 recovery were unreachable: use last known state.
        try { return (await SharedPreferences.getInstance()).getBool('purchase_${uid}_$courseId') ?? false; } catch (_) { return false; }
      }
    }
  }
  Future<void> _cachePurchase(String uid, String courseId, bool v) async {
    try { (await SharedPreferences.getInstance()).setBool('purchase_${uid}_$courseId', v); } catch (_) {}
  }

  Future<List<String>> _cachedMyIds(String uid) async {
    try { return (await SharedPreferences.getInstance()).getStringList('my_courses_$uid') ?? <String>[]; } catch (_) { return <String>[]; }
  }

  Future<void> _cacheMyIds(String uid, List<String> ids) async {
    try { (await SharedPreferences.getInstance()).setStringList('my_courses_$uid', ids); } catch (_) {}
  }

  Future<List<String>> _myIdsFromFunction(String uid) async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('getMyPurchasedCourseIds').call<Map<String, dynamic>>();
      return (result.data['courseIds'] as List? ?? const []).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return <String>[];
    }
  }

  /// Purchased course ids: Firebase (live) -> Cloud Function (Firebase, then R2 entitlements)
  /// -> last known list on the device. Purchases made on the website appear automatically.
  Stream<List<String>> watchMyCourseIds(String uid) async* {
    final cached = await _cachedMyIds(uid);
    if (cached.isNotEmpty) yield cached;
    try {
      await for (final snapshot in _db.collection('purchases').where('uid', isEqualTo: uid).where('status', isEqualTo: 'completed').snapshots()) {
        final ids = snapshot.docs.map((doc) => (doc.data()['courseId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();
        try {
          final legacy = await _db.collection('users').doc(uid).collection('purchases').get();
          for (final doc in legacy.docs) {
            final data = doc.data();
            if (data['status'] != 'cancelled' && data['status'] != 'refunded') ids.add((data['courseId'] ?? doc.id).toString());
          }
        } catch (_) {}
        var out = ids.where((id) => id.isNotEmpty).toList();
        if (out.isEmpty) {
          out = await _myIdsFromFunction(uid);
          if (out.isEmpty && cached.isNotEmpty) out = cached;
        }
        _cacheMyIds(uid, out);
        yield out;
      }
    } catch (_) {
      final out = await _myIdsFromFunction(uid);
      yield out.isNotEmpty ? out : cached;
    }
  }

  // ==================== FAVORITES ====================

  Stream<List<String>> watchFavoriteIds(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => doc.id)
              .toList(),
        );
  }

  Future<void> setFavorite(
    String uid,
    String courseId,
    bool isFavorite,
  ) async {
    final ref = _db
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(courseId);

    if (isFavorite) {
      await ref.set({
        'courseId': courseId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  // ==================== NOTIFICATIONS ====================

  Stream<QuerySnapshot<Map<String, dynamic>>> watchNotifications(
    String uid,
  ) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy(
          'createdAt',
          descending: true,
        )
        .snapshots();
  }

  Future<void> markNotificationRead(
    String uid,
    String notificationId,
  ) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({
      'read': true,
    });
  }

  Future<Map<String, dynamic>> getRemoteSettings() async {
    final doc = await _db.collection('settings').doc('app').get();
    return doc.data() ?? {};
  }

  // ==================== PROGRESS ====================

  String _progressId(
    String uid,
    String courseId,
    String lessonId,
  ) {
    return '${uid}_${courseId}_$lessonId';
  }

  Future<int> getLessonProgressSeconds(
    String uid,
    String courseId,
    String lessonId,
  ) async {
    final doc = await _db
        .collection('progress')
        .doc(
          _progressId(
            uid,
            courseId,
            lessonId,
          ),
        )
        .get();

    if (!doc.exists || doc.data() == null) {
      return 0;
    }

    final value = doc.data()!['positionSeconds'];

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  Future<void> saveLessonProgress({
    required String uid,
    required String courseId,
    required String lessonId,
    required int positionSeconds,
    required int durationSeconds,
    required bool completed,
  }) async {
    final percent = durationSeconds <= 0
        ? 0
        : ((positionSeconds / durationSeconds) * 100)
            .clamp(0, 100)
            .round();

    await _db
        .collection('progress')
        .doc(
          _progressId(
            uid,
            courseId,
            lessonId,
          ),
        )
        .set(
      {
        'uid': uid,
        'courseId': courseId,
        'lessonId': lessonId,
        'positionSeconds': positionSeconds,
        'percent': percent,
        'completed': completed,
        'lastWatchedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
