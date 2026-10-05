import 'api_functions.dart';

class RoleService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<String> switchLearningRole(String targetRole) async {
    if (targetRole != 'student' && targetRole != 'instructor') {
      throw ArgumentError('الدور غير مسموح');
    }

    final result = await _functions
        .httpsCallable('switchLearningRole')
        .call({'targetRole': targetRole});

    return (result.data?['role'] ?? targetRole).toString();
  }
}
