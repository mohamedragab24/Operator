import 'api_functions.dart';

class PurchaseService {
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<double> purchaseCourse(String courseId) async {
    final callable = _functions.httpsCallable('purchaseCourse');
    final result = await callable.call<Map<String, dynamic>>({'courseId': courseId});
    return (result.data['amountPaid'] as num?)?.toDouble() ?? 0;
  }
}
