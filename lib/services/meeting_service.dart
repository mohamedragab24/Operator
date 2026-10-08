import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';
import 'api_functions.dart';
import '../models/meeting.dart';
import 'error_center.dart';

class MeetingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final JitsiMeet _jitsi = JitsiMeet();
  static const String _jaasRoomPrefix = 'vpaas-magic-cookie-1fbd16d85bf84be0aaba7317c17f25dd/Fahimni_';

  Stream<List<Meeting>> watchUserMeetings(String uid) {
    final a = _db.collection('istifhams').where('mustafhemId', isEqualTo: uid).where('status', whereIn: ['paid','completed']).snapshots();
    final b = _db.collection('istifhams').where('mufhemId', isEqualTo: uid).where('status', whereIn: ['paid','completed']).snapshots();
    // Merge is handled in the UI from the two streams; this method is kept for future aggregation.
    return a.map((s) => s.docs.map((d) => Meeting.fromMap(d.id, d.data())).toList());
  }

  Stream<QuerySnapshot<Map<String,dynamic>>> watchStudent(String uid) => _db.collection('istifhams').where('mustafhemId', isEqualTo: uid).where('status', whereIn: ['paid','completed']).snapshots();
  Stream<QuerySnapshot<Map<String,dynamic>>> watchTeacher(String uid) => _db.collection('istifhams').where('mufhemId', isEqualTo: uid).where('status', whereIn: ['paid','completed']).snapshots();

  Future<void> join(Meeting meeting, {required String displayName, String? email, String? avatar, bool moderator = false}) async {
    final room = '${_jaasRoomPrefix.replaceFirst(RegExp(r'/$'), '')}${meeting.id}'.split('/').last;
    String? token;
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('getJaasMeetingToken').call({'room': room});
      token = result.data['token']?.toString();
    } catch (e, st) {
      // نكمل الدخول، لكن بدون توكن لن يعمل التسجيل/الإشراف: نُظهر السبب فورًا
      ErrorCenter.instance.report(e, where: 'توكن الاجتماع (JaaS)', stack: st);
    }
    final options = JitsiMeetConferenceOptions(
      room: '$_jaasRoomPrefix${meeting.id}',
      token: token,
      serverURL: 'https://8x8.vc',
      configOverrides: {
        'prejoinPageEnabled': false,
        'disableInviteFunctions': true,
        'startWithAudioMuted': false,
        'startWithVideoMuted': false,
      },
      featureFlags: {
        FeatureFlags.recordingEnabled: moderator,
        FeatureFlags.androidScreenSharingEnabled: false,
        FeatureFlags.iosScreenSharingEnabled: false,
      },
      userInfo: JitsiMeetUserInfo(displayName: displayName, email: email, avatar: avatar),
    );
    await _jitsi.join(
      options,
      JitsiMeetEventListener(
        conferenceTerminated: (url, error) => ErrorCenter.instance.reportMeetingError(error, where: 'المحاضرة'),
      ),
    );
  }
}
