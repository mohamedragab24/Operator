import 'package:cloud_firestore/cloud_firestore.dart';
import 'api_functions.dart';

import 'r2_worker_service.dart';

class SignedVideoResult {
  final String url;
  final DateTime expiresAt;
  SignedVideoResult({required this.url, required this.expiresAt});
}

class VideoService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<SignedVideoResult> getSignedVideoUrl({required String courseId, required String lessonId}) async {
    final callable = _functions.httpsCallable('getSignedVideoUrl');
    final result = await callable.call<Map<String, dynamic>>({'courseId': courseId, 'lessonId': lessonId});
    final resultData = result.data;
    return SignedVideoResult(url: resultData['url'] as String, expiresAt: DateTime.fromMillisecondsSinceEpoch(resultData['expiresAtMs'] as int));
  }
}
