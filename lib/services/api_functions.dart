import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// بديل متوافق مع cloud_functions: بدل استدعاء Firebase Cloud Functions (تحتاج خطة Blaze)
/// نستدعي مسار المنصة على Vercel: POST {API_BASE_URL}/api/fn/<name> مع Firebase ID token.
/// لتغيير الدومين وقت البناء:  --dart-define=API_BASE_URL=https://your-domain.vercel.app
class FirebaseFunctionsException implements Exception {
  final String code;
  final String? message;
  FirebaseFunctionsException({required this.code, this.message});

  @override
  String toString() => message ?? code;
}

class HttpsCallableResult<T> {
  final T data;
  HttpsCallableResult(this.data);
}

class HttpsCallable {
  final String name;
  HttpsCallable(this.name);

  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    final url = configured.trim().isEmpty ? 'https://fahemny86.vercel.app' : configured.trim();
    return url.replaceFirst(RegExp(r'/+$'), '');
  }

  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = user == null ? null : await user.getIdToken();
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/fn/${Uri.encodeComponent(name)}'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'data': parameters ?? <String, dynamic>{}}),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw FirebaseFunctionsException(code: 'deadline-exceeded', message: 'انتهت مهلة الاتصال بالخادم');
    } catch (_) {
      throw FirebaseFunctionsException(code: 'unavailable', message: 'تعذر الاتصال بالخادم');
    }

    Map<String, dynamic> body = <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}

    final error = body['error'];
    if (response.statusCode != 200 || error != null) {
      final map = error is Map ? error : const {};
      throw FirebaseFunctionsException(
        code: (map['code'] ?? 'internal').toString(),
        message: (map['message'] ?? 'internal').toString(),
      );
    }

    Object? raw = body['data'];
    if (raw == null && null is! T) raw = <String, dynamic>{};
    return HttpsCallableResult<T>(raw as T);
  }
}

class FirebaseFunctions {
  FirebaseFunctions._();
  static final FirebaseFunctions instance = FirebaseFunctions._();
  static FirebaseFunctions instanceFor({String? region, dynamic app}) => instance;
  HttpsCallable httpsCallable(String name) => HttpsCallable(name);
}
