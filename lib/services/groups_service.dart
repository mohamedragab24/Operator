import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'api_functions.dart';

/// رابط مشاهدة مؤقت + بيانات العلامة المائية (من الخادم بعد التحقق من العضوية).
class GroupMedia {
  final String url;
  final String name;
  final String publicId;
  GroupMedia({required this.url, required this.name, required this.publicId});

  String get watermarkText => [name, publicId].where((e) => e.isNotEmpty).join(' • ');
}

/// المجموعات: القراءة من Firestore (قواعد الأمان تسمح للأعضاء فقط)، وكل رابط محتوى/اجتماع يمرّ عبر الخادم.
class GroupsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String? get uid => FirebaseAuth.instance.currentUser?.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>> watchOwned(String uid) =>
      _db.collection('groups').where('ownerUid', isEqualTo: uid).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchMemberships(String uid) =>
      _db.collection('users').doc(uid).collection('groupMemberships').snapshots();

  Future<DocumentSnapshot<Map<String, dynamic>>> getGroup(String id) => _db.collection('groups').doc(id).get();

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchGroup(String id) => _db.collection('groups').doc(id).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchContent(String groupId, String kind) =>
      _db.collection('groups').doc(groupId).collection(kind).orderBy('order', descending: true).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> watchLiveSessions(String groupId) =>
      _db.collection('groups').doc(groupId).collection('sessions').where('status', isEqualTo: 'live').snapshots();

  Future<GroupMedia> getMedia({required String groupId, required String kind, required String id}) async {
    final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('getGroupMediaUrl')
        .call<Map<String, dynamic>>({'groupId': groupId, 'kind': kind, 'id': id});
    final d = res.data;
    final wm = (d['watermark'] is Map) ? Map<String, dynamic>.from(d['watermark'] as Map) : <String, dynamic>{};
    return GroupMedia(url: (d['url'] ?? '').toString(), name: (wm['name'] ?? '').toString(), publicId: (wm['publicId'] ?? '').toString());
  }

  /// مشاهدة تسجيل من لوحة الأدمن (يتحقق الخادم أن المستخدم أدمن).
  Future<GroupMedia> getAdminRecordingMedia(String id) async {
    final res = await FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('getLectureRecordingUrl').call<Map<String, dynamic>>({'id': id});
    final d = res.data;
    final wm = (d['watermark'] is Map) ? Map<String, dynamic>.from(d['watermark'] as Map) : <String, dynamic>{};
    return GroupMedia(url: (d['url'] ?? '').toString(), name: (wm['name'] ?? '').toString(), publicId: (wm['publicId'] ?? '').toString());
  }

  Future<Map<String, dynamic>> submitQuiz({required String groupId, required String quizId, required List<dynamic> answers}) async {
    final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('submitGroupQuiz')
        .call<Map<String, dynamic>>({'groupId': groupId, 'quizId': quizId, 'answers': answers});
    return res.data;
  }

  /// دخول جلسة مباشرة داخل التطبيق (JaaS). المُفهم صاحب المجموعة moderator ويملك صلاحية التسجيل لو الجلسة مسجلة.
  /// يرجع true لو كان المستخدم moderator والجلسة مسجلة (ليُنبَّه لضغط زر التسجيل).
  Future<bool> joinSession({required String groupId, required String sessionId, required String displayName, String? email, String? avatar}) async {
    final res = await FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable('getGroupMeetingToken')
        .call<Map<String, dynamic>>({'groupId': groupId, 'sessionId': sessionId});
    final d = res.data;
    final moderator = d['moderator'] == true;
    final record = d['record'] == true;
    final options = JitsiMeetConferenceOptions(
      room: (d['room'] ?? '').toString(),
      token: (d['token'] ?? '').toString(),
      serverURL: 'https://8x8.vc',
      configOverrides: {
        'prejoinPageEnabled': false,
        'disableInviteFunctions': true,
        'startWithAudioMuted': !moderator,
        'startWithVideoMuted': !moderator,
      },
      featureFlags: {
        FeatureFlags.recordingEnabled: moderator && record,
        FeatureFlags.androidScreenSharingEnabled: moderator,
        FeatureFlags.iosScreenSharingEnabled: moderator,
      },
      userInfo: JitsiMeetUserInfo(displayName: displayName, email: email, avatar: avatar),
    );
    await JitsiMeet().join(options);
    return moderator && record;
  }
}
