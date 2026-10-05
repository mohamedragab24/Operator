import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _loading = false;
  String? _message;

  Future<void> _refreshVerification() async {
    setState(() { _loading = true; _message = null; });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) context.go('/login');
        return;
      }
      await user.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed?.emailVerified == true) {
        if (mounted) context.go('/home');
      } else {
        if (mounted) setState(() => _message = 'لم يتم التحقق من البريد حتى الآن. افتح رسالة Firebase ثم اضغط الرابط، وبعدها اضغط تحقق مرة أخرى.');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _message = 'تعذر تحديث حالة التحقق: ${e.code}');
    } catch (_) {
      if (mounted) setState(() => _message = 'تعذر الاتصال بـ Firebase. تأكد من الإنترنت وحاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendAgain() async {
    setState(() { _loading = true; _message = null; });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) setState(() => _message = 'تم إرسال رسالة تحقق جديدة إلى بريدك الإلكتروني.');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _message = e.code == 'too-many-requests'
          ? 'تم إرسال رسائل كثيرة. انتظر قليلًا ثم حاول مرة أخرى.'
          : 'تعذر إرسال رسالة التحقق: ${e.code}');
    } catch (_) {
      if (mounted) setState(() => _message = 'تعذر الاتصال بـ Firebase لإرسال الرسالة.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('التحقق من الحساب')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 76, color: AppColors.gold),
                const SizedBox(height: 22),
                Text('تحقق من بريدك الإلكتروني', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text('أرسلنا رابط التحقق إلى\n$email', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 22),
                if (_message != null)
                  Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(_message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted))),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _refreshVerification,
                    child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('تحقق مرة أخرى'),
                  ),
                ),
                TextButton(onPressed: _loading ? null : _sendAgain, child: const Text('إعادة إرسال رسالة التحقق')),
                TextButton(onPressed: _loading ? null : () => FirebaseAuth.instance.signOut().then((_) { if (mounted) context.go('/login'); }), child: const Text('تسجيل الخروج')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
