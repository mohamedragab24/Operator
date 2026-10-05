import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _auth = AuthService();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    if (name.isEmpty) {
      setState(() => _error = 'اكتب الاسم الكامل');
      return;
    }
    if (email.isEmpty) {
      setState(() => _error = 'اكتب البريد الإلكتروني');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      // Firebase initializes in the background after the app opens, so
      // signup must wait for it the same way login does — otherwise this
      // fails with "No Firebase App '[DEFAULT]' has been created" if the
      // user submits before native init finishes.
      final firebaseReady = await FirebaseBootstrap.instance.waitUntilReady(
        timeout: const Duration(seconds: 30),
      );
      if (!firebaseReady) {
        final details = FirebaseBootstrap.instance.lastError;
        throw FirebaseAuthException(
          code: 'firebase-not-ready',
          message: details.isEmpty
              ? 'لم تكتمل تهيئة خدمات Firebase بعد.'
              : 'لم تكتمل تهيئة Firebase: $details',
        );
      }

      final cred = await _auth.signUp(name, email, password);
      final user = cred.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-null',
          message: 'تعذر الحصول على بيانات المستخدم بعد إنشاء الحساب',
        );
      }

      try {
        await _auth.sendEmailVerification();
      } catch (_) {
        // Verification email is secondary; do not turn a successful signup
        // into a failure. The verify screen can retry it.
      }

      try {
        await FirestoreService().ensureUserProfile(
          uid: user.uid,
          name: name,
          email: email,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        // Auth succeeded. Do not block the user because profile persistence
        // is a separate Firestore operation.
      }

      if (!mounted) return;
      context.go('/verify-email');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'هذا البريد الإلكتروني مستخدم بالفعل';
          break;
        case 'invalid-email':
          message = 'البريد الإلكتروني غير صحيح';
          break;
        case 'weak-password':
          message = 'كلمة المرور ضعيفة جدًا';
          break;
        case 'network-request-failed':
          message = 'تحقق من اتصال الإنترنت وحاول مرة أخرى';
          break;
        case 'firebase-not-ready':
          message = e.message?.isNotEmpty == true
              ? e.message!
              : 'لم تكتمل تهيئة Firebase بعد. حاول مرة أخرى.';
          break;
        case 'operation-not-allowed':
          message = 'إنشاء الحساب بالبريد الإلكتروني غير مفعّل في Firebase';
          break;
        default:
          message = 'تعذر إنشاء الحساب. رمز الخطأ: ${e.code}';
      }

      setState(() => _error = message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذر إكمال إنشاء الحساب. تفاصيل الخطأ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('إنشاء حساب جديد', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text('خطوة وحدة وتبدأ رحلة التعلّم', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 22),
              TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
              const SizedBox(height: 14),
              TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'البريد الإلكتروني أو رقم الهاتف')),
              const SizedBox(height: 14),
              TextField(controller: _passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
              if (_error != null) ...[
                const SizedBox(height: 10),
                SelectableText(_error!, style: const TextStyle(color: AppColors.coral, fontSize: 12.5)),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _error!));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ الخطأ')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('نسخ الخطأ'),
                ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                    : const Text('إنشاء الحساب'),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
