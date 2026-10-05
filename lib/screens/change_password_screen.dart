import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newPass = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _newPass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_newPass.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة المرور يجب أن تكون 6 أحرف على الأقل')));
      return;
    }
    if (_newPass.text != _confirm.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمتا المرور غير متطابقتين')));
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService().updatePassword(_newPass.text);
      if (mounted) {
        _newPass.clear();
        _confirm.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة المرور بنجاح')));
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      final msg = e.code == 'requires-recent-login'
          ? 'لأسباب أمنية، سجّل الدخول مرة أخرى ثم جرّب تغيير كلمة المرور.'
          : (e.message ?? 'تعذر تغيير كلمة المرور');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تغيير كلمة المرور: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تغيير كلمة المرور')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('اكتب كلمة مرور جديدة لحسابك.', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        TextField(controller: _newPass, obscureText: _obscure, decoration: InputDecoration(labelText: 'كلمة المرور الجديدة', suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off)))),
        const SizedBox(height: 14),
        TextField(controller: _confirm, obscureText: _obscure, decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: _loading ? null : _save, child: _loading ? const CircularProgressIndicator(strokeWidth: 2) : const Text('تغيير كلمة المرور')),
      ],
    ),
  );
}
