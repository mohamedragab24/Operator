import 'api_functions.dart';

class AnalyticsService {
  final _functions = FirebaseFunctions.instance;
  Future<void> log(String event, {Map<String, dynamic> data = const {}}) async {
    final name = event.trim();
    if (name.isEmpty) return;
    await _functions.httpsCallable('logAnalyticsEvent').call({'event': name, 'data': data});
  }
}
