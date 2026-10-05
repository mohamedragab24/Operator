import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _auth = AuthService();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await _auth.sendPasswordReset(_emailCtrl.text.trim());
      setState(() => _sent = true);
    } catch (_) {
      // Keep the message generic so we don't reveal whether an email exists.
      setState(() => _sent = true);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('نسيت كلمة المرور؟', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text('اكتب بريدك الإلكتروني وهنبعتلك رابط إعادة التعيين', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 22),
              if (!_sent) ...[
                TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'البريد الإلكتروني')),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink))
                      : const Text('إرسال رابط إعادة التعيين'),
                ),
              ] else
                const Text('تم إرسال الرابط — راجع بريدك الإلكتروني', style: TextStyle(color: AppColors.emeraldDark, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
