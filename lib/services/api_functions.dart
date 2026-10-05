import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  // الدومين الحالي يُقرأ من Firestore (settings/app.apiBaseUrl) فلا يلزم إعادة بناء التطبيق عند تغيير الدومين.
  static String? _remoteBase;

  static Future<String> _resolveBase({bool force = false}) async {
    if (force || _remoteBase == null) {
      try {
        final snap = await FirebaseFirestore.instance.collection('settings').doc('app').get().timeout(const Duration(seconds: 5));
        final u = (snap.data()?['apiBaseUrl'] ?? '').toString().trim();
        if (u.startsWith('http')) _remoteBase = u.replaceFirst(RegExp(r'/+$'), '');
      } catch (_) {}
    }
    return _remoteBase ?? baseUrl;
  }

  Future<http.Response> _post(String base, String? token, dynamic parameters) {
    return http
        .post(
          Uri.parse('$base/api/fn/${Uri.encodeComponent(name)}'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'data': parameters ?? <String, dynamic>{}}),
        )
        .timeout(const Duration(seconds: 60));
  }

  Future<HttpsCallableResult<T>> call<T>([dynamic parameters]) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = user == null ? null : await user.getIdToken();
    http.Response response;
    try {
      final base = await _resolveBase();
      try {
        response = await _post(base, token, parameters);
        // دومين قديم/متوقف: لا يرجع JSON صالح من الدوال → نحدّث الدومين من Firestore ونعيد مرة واحدة
        if (response.statusCode == 404 || response.statusCode >= 502) {
          final fresh = await _resolveBase(force: true);
          if (fresh != base) response = await _post(fresh, token, parameters);
        }
      } on TimeoutException {
        rethrow;
      } catch (_) {
        final fresh = await _resolveBase(force: true);
        if (fresh == base) rethrow;
        response = await _post(fresh, token, parameters);
      }
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
