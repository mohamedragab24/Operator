import 'dart:async';
import 'dart:io' show SocketException, HandshakeException;
import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_functions.dart';

/// خطأ مفهوم للمستخدم: ماذا حدث + السبب + المطلوب للحل (+ تفاصيل تقنية للنسخ).
class AppError {
  final String id;
  final String title;
  final String? cause;
  final String? fix;
  final String technical;
  final String? where;
  final String? link;
  final DateTime at;
  AppError({required this.title, this.cause, this.fix, this.technical = '', this.where, this.link})
      : id = '${DateTime.now().microsecondsSinceEpoch}',
        at = DateTime.now();

  String toReport() => [
        'الخطأ: $title',
        if (where != null) 'المكان: $where',
        if (cause != null && cause!.isNotEmpty) 'السبب: $cause',
        if (fix != null && fix!.isNotEmpty) 'الحل: $fix',
        if (technical.isNotEmpty) 'التفاصيل: $technical',
        'الوقت: ${at.toIso8601String()}',
      ].join('\n');
}

/// مركز الأخطاء: أي خطأ في التطبيق يظهر فورًا في بطاقة حمراء أسفل الشاشة بسببه وحله.
///
/// الاستخدام:
///   try { ... } catch (e, st) { ErrorCenter.instance.report(e, where: 'شراء كورس', stack: st); }
///   أو:  await ErrorCenter.instance.guard(() => service.doSomething(), where: 'اسم العملية');
class ErrorCenter {
  ErrorCenter._();
  static final ErrorCenter instance = ErrorCenter._();

  final ValueNotifier<List<AppError>> errors = ValueNotifier<List<AppError>>(<AppError>[]);
  final Map<String, DateTime> _recent = {};

  /// يربط كل المصائد العامة: Flutter / Dart async / أخطاء الدوال / عناصر الواجهة التالفة.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails d) {
      previous?.call(d);
      final msg = d.exceptionAsString();
      // أخطاء الصور (رابط/إنترنت) لا تستحق نافذة خطأ، تُسجَّل في الـ console فقط
      if (msg.contains('NetworkImageLoadException') || msg.contains('HTTP request failed') || msg.contains('Failed host lookup') && (d.library ?? '').contains('image')) {
        return;
      }
      report(d.exception, stack: d.stack, where: d.library == null ? 'واجهة التطبيق' : 'واجهة التطبيق (${d.library})');
    };
    PlatformDispatcher.instance.onError = (Object e, StackTrace st) {
      report(e, stack: st, where: 'عملية في الخلفية');
      return true;
    };
    ErrorWidget.builder = (FlutterErrorDetails d) => _BrokenWidget(message: _short(d.exceptionAsString()));
    HttpsCallable.onTechnicalError = (e) => report(e, where: 'استدعاء ${e.functionName ?? 'دالة'}');
  }

  static String _short(String s) => s.length > 160 ? '${s.substring(0, 160)}…' : s;

  /// ينفّذ العملية ويعرض أي خطأ فورًا. يرجع null عند الفشل.
  Future<T?> guard<T>(Future<T> Function() action, {String? where}) async {
    try {
      return await action();
    } catch (e, st) {
      report(e, where: where, stack: st);
      return null;
    }
  }

  AppError report(Object error, {String? where, StackTrace? stack}) {
    final err = explain(error, where: where, stack: stack);
    final key = '${err.title}|${where ?? ''}';
    final last = _recent[key];
    if (last == null || DateTime.now().difference(last) > const Duration(seconds: 4)) {
      _recent[key] = DateTime.now();
      debugPrint('[خطأ${where != null ? ' — $where' : ''}] ${err.title}\nالسبب: ${err.cause}\nالحل: ${err.fix}\n${err.technical}');
      errors.value = [err, ...errors.value].take(3).toList();
    }
    return err;
  }

  /// أخطاء الاجتماع القادمة من مكتبة Jitsi/JaaS (تظهر عند إنهاء الاتصال بسبب خطأ).
  void reportMeetingError(Object? error, {String? where}) {
    if (error == null) return;
    final t = error.toString();
    final low = t.toLowerCase();
    AppError mk(String title, String cause, String fix) => AppError(title: title, cause: cause, fix: fix, technical: _short(t), where: where ?? 'الاجتماع');
    AppError err;
    if (low.contains('notallowed') || low.contains('not-allowed') || low.contains('not_allowed') || low.contains('jwt') || low.contains('token') || low.contains('authentication')) {
      err = mk('الاجتماع رفض الدخول (التوكن غير مقبول)',
          'JaaS لم يقبل توكن الدخول: JAAS_KEY_ID لا يطابق المفتاح الخاص JAAS_PRIVATE_KEY، أو JAAS_APP_ID خطأ، أو اسم الغرفة في التوكن مختلف عن الغرفة.',
          'JaaS Console ← API Keys: تأكد أن Key ID هو لنفس ملف .pk الذي وضعته في Vercel وأن App ID مطابق، ثم Redeploy وجرّب جلسة جديدة. يمكنك التأكد من الفحص: لوحة الأدمن ← فحص النظام.');
    } else if (low.contains('connectionerror') || low.contains('connection') || low.contains('network') || low.contains('xmpp')) {
      err = mk('انقطع الاتصال بالاجتماع', 'الإنترنت ضعيف أو الاتصال بخوادم 8x8 تعطل.', 'تأكد من الإنترنت ثم ادخل الجلسة من جديد.');
    } else if (low.contains('room') && (low.contains('not') || low.contains('exist'))) {
      err = mk('الغرفة غير متاحة', 'الجلسة انتهت أو لم تبدأ بعد.', 'اطلب من المُفهم بدء الجلسة ثم ادخل من جديد.');
    } else {
      err = mk('انتهى الاجتماع بسبب خطأ', 'لم يتم التعرّف على السبب من رد JaaS.', 'انسخ التفاصيل وأرسلها للمطوّر.');
    }
    final key = '${err.title}|${err.where}';
    final last = _recent[key];
    if (last == null || DateTime.now().difference(last) > const Duration(seconds: 4)) {
      _recent[key] = DateTime.now();
      errors.value = [err, ...errors.value].take(3).toList();
    }
  }

  void dismiss(String id) => errors.value = errors.value.where((e) => e.id != id).toList();
  void dismissAll() => errors.value = <AppError>[];

  /// يحوّل أي استثناء إلى شرح مفهوم.
  static AppError explain(Object e, {String? where, StackTrace? stack}) {
    final st = stack == null ? '' : ' @ ${stack.toString().split('\n').take(2).join(' | ')}';
    AppError mk(String title, String cause, String fix, {String? tech, String? link}) =>
        AppError(title: title, cause: cause, fix: fix, technical: _short('${tech ?? e.toString()}$st').replaceAll('\n', ' '), where: where, link: link);

    // ---- أخطاء الدوال (Vercel /api/fn) ----
    if (e is FirebaseFunctionsException) {
      if ((e.cause ?? '').isNotEmpty || (e.fix ?? '').isNotEmpty) {
        return AppError(title: e.message ?? e.code, cause: e.cause, fix: e.fix, technical: e.technical ?? e.code, where: where ?? e.functionName, link: e.link);
      }
      switch (e.code) {
        case 'permission-denied':
          return mk(e.message ?? 'ليس لديك صلاحية', 'حسابك لا يملك الدور المطلوب لهذه العملية.', 'سجّل بحساب مناسب (مفهم/أدمن)، أو اطلب من الإدارة منحك الصلاحية.');
        case 'unauthenticated':
          return mk('انتهت جلسة الدخول', 'التوكن انتهت صلاحيته.', 'سجّل الخروج ثم سجّل الدخول من جديد.');
        case 'not-found':
          return mk(e.message ?? 'غير موجود', 'العنصر محذوف أو المعرّف غير صحيح.', 'حدّث الشاشة وجرّب مرة أخرى.');
        case 'failed-precondition':
        case 'invalid-argument':
        case 'already-exists':
          return mk(e.message ?? 'طلب غير مقبول', 'البيانات المرسلة لا تحقق شروط العملية.', 'راجع البيانات المدخلة وأعد المحاولة.');
        default:
          return mk(e.message ?? 'خطأ في الخادم', 'خطأ داخلي لم يُحدَّد سببه.', 'افتح Vercel ← Logs وابحث عن هذا الوقت، أو انسخ التفاصيل وأرسلها للمطوّر.');
      }
    }

    // ---- Firebase Auth ----
    if (e is FirebaseAuthException) {
      const map = {
        'user-not-found': ['لا يوجد حساب بهذا البريد', 'البريد غير مسجّل.', 'تأكد من كتابة البريد أو أنشئ حسابًا جديدًا.'],
        'wrong-password': ['كلمة المرور غير صحيحة', 'كلمة المرور لا تطابق الحساب.', 'أعد المحاولة أو استخدم «نسيت كلمة المرور».'],
        'invalid-credential': ['بيانات الدخول غير صحيحة', 'البريد أو كلمة المرور خطأ.', 'تأكد من البيانات أو استخدم «نسيت كلمة المرور».'],
        'invalid-email': ['صيغة البريد غير صحيحة', 'البريد المكتوب ليس بريدًا صالحًا.', 'صحّح البريد الإلكتروني.'],
        'email-already-in-use': ['البريد مستخدم من قبل', 'يوجد حساب بنفس البريد.', 'سجّل الدخول به أو استخدم بريدًا آخر.'],
        'weak-password': ['كلمة المرور ضعيفة', 'أقل من 6 أحرف أو سهلة.', 'اختر كلمة مرور أقوى (6 أحرف على الأقل).'],
        'too-many-requests': ['محاولات كثيرة', 'Firebase أوقف المحاولات مؤقتًا بسبب التكرار.', 'انتظر بضع دقائق ثم أعد المحاولة.'],
        'network-request-failed': ['لا يوجد اتصال بالإنترنت', 'الجهاز غير متصل أو الشبكة ضعيفة.', 'اتصل بالإنترنت وأعد المحاولة.'],
        'user-disabled': ['الحساب موقوف', 'تم إيقاف هذا الحساب.', 'تواصل مع الدعم.'],
        'requires-recent-login': ['يلزم تسجيل الدخول من جديد', 'العملية حساسة وتحتاج جلسة حديثة.', 'سجّل الخروج ثم الدخول وأعد المحاولة.'],
        'operation-not-allowed': ['طريقة الدخول غير مفعّلة', 'مزوّد الدخول (Email/Google..) مغلق في Firebase.', 'Firebase Console ← Authentication ← Sign-in method ← فعّل الطريقة.'],
        'firebase-not-ready': ['تعذّر تشغيل Firebase', 'التطبيق لم يستطع تهيئة Firebase (ملف google-services.json لا يطابق com.Fahmani، أو بصمة SHA-1 ناقصة، أو إنترنت ضعيف وقت الفتح).', 'تأكد من google-services.json واسم الحزمة com.Fahmani، وأضف SHA-1/SHA-256 في Firebase Console، ثم flutter clean وأعد البناء. جرّب أيضًا إغلاق التطبيق وفتحه مع إنترنت قوي.'],
        'user-null': ['تعذّر قراءة بيانات المستخدم بعد الدخول', 'Firebase لم يُرجع المستخدم بعد نجاح العملية.', 'أعد المحاولة، ولو تكرر أرسل التفاصيل للمطوّر.'],
        'app-not-authorized': ['التطبيق غير مصرّح له', 'بصمة SHA-1/SHA-256 أو اسم الحزمة غير مضاف في Firebase.', 'Firebase Console ← Project settings ← أضف SHA-1 و SHA-256 لتطبيق com.Fahmani ثم نزّل google-services.json الجديد وأعد البناء.'],
      };
      final m = map[e.code];
      if (m != null) return mk(m[0], m[1], m[2], tech: '${e.code}: ${e.message}');
      return mk('خطأ في تسجيل الدخول', 'رمز الخطأ: ${e.code}.', 'انسخ التفاصيل وأرسلها للمطوّر.', tech: '${e.code}: ${e.message}');
    }

    // ---- Firestore / Firebase عام ----
    if (e is FirebaseException) {
      final msg = e.message ?? '';
      final link = RegExp(r'https://console\.firebase\.google\.com\S+').firstMatch(msg)?.group(0);
      switch (e.code) {
        case 'permission-denied':
          return mk('Firestore رفض العملية (permission-denied)', 'القواعد المنشورة لا تسمح لهذا الحساب بهذه القراءة/الكتابة.', 'انشر ملف firestore.rules (Firebase Console ← Firestore ← Rules ← Publish) وتأكد أنك مسجّل الدخول.', tech: '${e.plugin}/${e.code}: $msg');
        case 'failed-precondition':
          if (msg.contains('index')) {
            return mk('الاستعلام يحتاج فهرسًا (Index)', 'Firestore يطلب فهرسًا مركبًا لم يُنشأ بعد.', link != null ? 'افتح الرابط المرفق واضغط Create Index وانتظر دقيقة ثم أعد المحاولة.' : 'Firebase Console ← Firestore ← Indexes وأنشئ الفهرس المطلوب.', tech: msg, link: link);
          }
          break;
        case 'unavailable':
          return mk('تعذّر الوصول لقاعدة البيانات', 'لا يوجد إنترنت أو الخدمة متوقفة مؤقتًا.', 'تأكد من الإنترنت وأعد المحاولة.', tech: '${e.plugin}/${e.code}');
        case 'not-found':
          return mk('المستند غير موجود', 'تم حذفه أو المسار خطأ.', 'حدّث الشاشة.', tech: '${e.plugin}/${e.code}: $msg');
        case 'resource-exhausted':
          return mk('تم تجاوز حصة Firebase', 'الخطة المجانية استُنفدت مؤقتًا.', 'انتظر التجديد أو رقّ الخطة.', tech: '${e.plugin}/${e.code}');
        case 'no-app':
          return mk('Firebase لم يبدأ بعد', 'التطبيق حاول استخدام Firebase قبل اكتمال التهيئة.', 'أعد فتح التطبيق، ولو تكرر راجع google-services.json (اسم الحزمة com.Fahmani).', tech: '${e.plugin}/${e.code}');
      }
      return mk('خطأ من Firebase (${e.code})', 'الخدمة: ${e.plugin}.', 'انسخ التفاصيل وأرسلها للمطوّر.', tech: '${e.plugin}/${e.code}: $msg');
    }

    // ---- شبكة ووقت ----
    if (e is TimeoutException) {
      return mk('انتهت مهلة الاتصال', 'الشبكة بطيئة أو السيرفر لا يرد.', 'تأكد من الإنترنت وأعد المحاولة.', tech: 'TimeoutException ${e.duration ?? ''}');
    }
    if (e is SocketException) {
      return mk('لا يوجد اتصال بالإنترنت', 'الجهاز لا يستطيع الوصول إلى السيرفر (${e.address?.host ?? ''}).', 'اتصل بالإنترنت وأعد المحاولة. لو متصل: تأكد أن الدومين يعمل (افتحه في المتصفح).', tech: e.toString());
    }
    if (e is HandshakeException) {
      return mk('فشل الاتصال الآمن (SSL)', 'شهادة الموقع غير صالحة أو ساعة الجهاز غير مضبوطة.', 'اضبط التاريخ والوقت على تلقائي وأعد المحاولة.', tech: e.toString());
    }

    // ---- النظام ----
    if (e is MissingPluginException) {
      return mk('ميزة غير مسجّلة في التطبيق', 'الإضافة (plugin) لم تُبنَ داخل الـ APK أو التطبيق يعمل بنسخة بناء قديمة.', 'نفّذ: flutter clean ثم flutter pub get ثم ابنِ الـ APK من جديد وثبّته.', tech: e.message);
    }
    if (e is PlatformException) {
      final c = e.code.toLowerCase();
      if (c.contains('permission')) {
        return mk('صلاحية مطلوبة من الجهاز', 'لم تمنح التطبيق صلاحية: ${e.code}.', 'افتح إعدادات الهاتف ← التطبيقات ← مسار ← الأذونات وفعّل الصلاحية.', tech: '${e.code}: ${e.message}');
      }
      return mk('خطأ من نظام الجهاز', 'رمز: ${e.code}.', 'انسخ التفاصيل وأرسلها للمطوّر.', tech: '${e.code}: ${e.message}');
    }

    // ---- أخطاء برمجية / بيانات ----
    final s = e.toString();
    if (s.contains('core/no-app') || s.contains('تعذر تهيئة Firebase')) {
      return mk('تعذّر تشغيل Firebase', 'ملف google-services.json لا يطابق اسم الحزمة com.Fahmani أو بصمة SHA-1 غير مضافة أو نسخة إضافات Firebase غير متوافقة.', 'تأكد أن google-services.json من نفس المشروع واسم الحزمة com.Fahmani، وأضف SHA-1/SHA-256 في Firebase Console، ثم flutter clean وأعد البناء.', tech: s);
    }
    if (e is FormatException) {
      return mk('بيانات غير متوقعة من الخادم', 'الرد ليس بالصيغة المتوقعة (غالبًا الخادم رد بصفحة خطأ).', 'افتح رابط الموقع في المتصفح للتأكد أنه يعمل، وراجع Vercel ← Logs.', tech: s);
    }
    if (e is TypeError || s.contains('Null check operator') || s.contains('type \'Null\'')) {
      return mk('بيانات ناقصة في هذه الشاشة', 'مستند في قاعدة البيانات ينقصه حقل يتوقعه التطبيق.', 'انسخ التفاصيل وأرسلها للمطوّر (توضح أي شاشة وأي حقل).', tech: s);
    }
    return mk(where != null ? 'تعذّر تنفيذ: $where' : 'حدث خطأ غير متوقع', 'لم يتم التعرّف على سبب محدد.', 'انسخ التفاصيل وأرسلها للمطوّر.', tech: s);
  }
}

/// طبقة العرض: تُوضع فوق التطبيق كله (انظر main.dart).
class ErrorOverlay extends StatelessWidget {
  const ErrorOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<AppError>>(
      valueListenable: ErrorCenter.instance.errors,
      builder: (context, list, _) {
        if (list.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final e in list) Padding(padding: const EdgeInsets.only(top: 8), child: _ErrorCard(error: e))],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorCard extends StatefulWidget {
  final AppError error;
  const _ErrorCard({required this.error});
  @override
  State<_ErrorCard> createState() => _ErrorCardState();
}

class _ErrorCardState extends State<_ErrorCard> {
  bool _tech = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.error;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFFCA5A5)), boxShadow: const [BoxShadow(blurRadius: 14, color: Colors.black26)]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: const BoxDecoration(color: Color(0xFFFEF2F2), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
              child: Row(children: [
                const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.title, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB91C1C), fontSize: 14)),
                    if (e.where != null) Text('المكان: ${e.where}', style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
                  ]),
                ),
                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close, size: 20), onPressed: () => ErrorCenter.instance.dismiss(e.id)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if ((e.cause ?? '').isNotEmpty) Text.rich(TextSpan(children: [const TextSpan(text: 'السبب: ', style: TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: e.cause)]), style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155))),
                if ((e.fix ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFA7F3D0))),
                    child: Text.rich(TextSpan(children: [const TextSpan(text: 'المطلوب: ', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF065F46))), TextSpan(text: e.fix)]), style: const TextStyle(fontSize: 12.5, color: Color(0xFF064E3B))),
                  ),
                ],
                if (e.link != null) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(e.link!, style: const TextStyle(fontSize: 11, color: Colors.blue))),
                const SizedBox(height: 4),
                Row(children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: e.toReport()));
                      if (mounted) setState(() => _copied = true);
                    },
                    icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                    label: Text(_copied ? 'تم النسخ' : 'نسخ التفاصيل'),
                  ),
                  if (e.technical.isNotEmpty) TextButton(onPressed: () => setState(() => _tech = !_tech), child: Text(_tech ? 'إخفاء التقني' : 'تفاصيل تقنية')),
                ]),
                if (_tech) Container(width: double.infinity, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)), child: SelectableText(e.technical, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 10, fontFamily: 'monospace'))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// بديل الشاشة الرمادية/الحمراء عند فشل بناء عنصر.
class _BrokenWidget extends StatelessWidget {
  final String message;
  const _BrokenWidget({required this.message});
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(10),
        color: const Color(0xFFFEF2F2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB91C1C), size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text('تعذّر عرض هذا الجزء: $message', style: const TextStyle(fontSize: 11, color: Color(0xFFB91C1C), decoration: TextDecoration.none, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}
