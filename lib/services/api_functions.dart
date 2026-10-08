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
  /// السبب الأرجح والمطلوب للحل (يرسلها السيرفر أو تُحسب هنا للأخطاء الشبكية)
  final String? cause;
  final String? fix;
  final String? technical;
  final String? link;
  final String? functionName;
  FirebaseFunctionsException({required this.code, this.message, this.cause, this.fix, this.technical, this.link, this.functionName});

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

  /// يُضبط من ErrorCenter.install(): أي خطأ تقني (له سبب/حل) يظهر فورًا للمستخدم.
  static void Function(FirebaseFunctionsException e)? onTechnicalError;

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
      final e = FirebaseFunctionsException(
        code: 'deadline-exceeded',
        message: 'انتهت مهلة الاتصال بالخادم',
        cause: 'السيرفر لم يرد خلال 60 ثانية (إنترنت ضعيف، أو عملية ثقيلة تجاوزت حد Vercel).',
        fix: 'تأكد من الإنترنت وأعد المحاولة. لو تكرر افتح Vercel ← Logs لمسار /api/fn/$name.',
        technical: 'TimeoutException POST /api/fn/$name',
        functionName: name,
      );
      onTechnicalError?.call(e);
      throw e;
    } catch (err) {
      final base = _remoteBase ?? HttpsCallable.baseUrl;
      final e = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'تعذر الاتصال بالخادم',
        cause: 'الجهاز لا يصل إلى $base (لا يوجد إنترنت، أو الدومين متوقف/تغيّر).',
        fix: 'تأكد من الإنترنت وافتح $base في المتصفح للتأكد أنه يعمل. لو الدومين تغيّر: حدّث settings/app ← apiBaseUrl في Firestore (أو ابنِ التطبيق بـ --dart-define=API_BASE_URL).',
        technical: 'POST $base/api/fn/$name failed: $err',
        functionName: name,
      );
      onTechnicalError?.call(e);
      throw e;
    }

    Map<String, dynamic> body = <String, dynamic>{};
    bool parsed = false;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        body = decoded;
        parsed = true;
      }
    } catch (_) {}

    final error = body['error'];
    if (response.statusCode != 200 || error != null) {
      final map = error is Map ? error : const {};
      String message = (map['message'] ?? 'internal').toString();
      String? cause = (map['cause'] ?? '').toString().isEmpty ? null : map['cause'].toString();
      String? fix = (map['fix'] ?? '').toString().isEmpty ? null : map['fix'].toString();
      String code = (map['code'] ?? 'internal').toString();
      if (!parsed) {
        // السيرفر رد بصفحة غير JSON: نشرح الحالة حسب رمز HTTP
        final s = response.statusCode;
        final base = _remoteBase ?? HttpsCallable.baseUrl;
        message = 'السيرفر رد بخطأ $s';
        if (s == 401 || s == 403) {
          cause = 'Vercel يحمي الموقع (Deployment Protection) أو الطلب مرفوض قبل أن يصل للدالة.';
          fix = 'Vercel ← Settings ← Deployment Protection ← أوقفها للإنتاج (Production)، ثم أعد المحاولة.';
        } else if (s == 404) {
          cause = 'المسار /api/fn/$name غير منشور على $base (نسخة المنصة قديمة أو الدومين خطأ).';
          fix = 'ارفع آخر نسخة من fahmni-platform إلى Vercel وتأكد أن النشر نجح، وأن الدومين في التطبيق صحيح.';
        } else if (s == 504 || s == 408) {
          cause = 'العملية تجاوزت حد الوقت في Vercel (60 ثانية في الخطة المجانية).';
          fix = 'أعد المحاولة، ولو تكرر افتح Vercel ← Logs لمعرفة الخطوة البطيئة.';
        } else {
          cause = 'الدالة انهارت قبل أن ترد، أو آخر نشر فشل.';
          fix = 'Vercel ← Deployments (تأكد أن آخر نسخة Ready) ثم Logs لمسار /api/fn/$name.';
        }
      }
      final ex = FirebaseFunctionsException(
        code: code,
        message: message,
        cause: cause,
        fix: fix,
        technical: (map['technical'] ?? 'HTTP ${response.statusCode} /api/fn/$name').toString(),
        link: map['link']?.toString(),
        functionName: name,
      );
      // الأخطاء التقنية (لها سبب/حل) تظهر فورًا؛ أخطاء المنطق العادية يعرضها المستدعي
      if (cause != null || fix != null) onTechnicalError?.call(ex);
      throw ex;
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
