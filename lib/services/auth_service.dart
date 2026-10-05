import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  // Lazy: constructing this service must be safe before Firebase Core is ready.
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn(
    String email,
    String password,
  ) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'البريد الإلكتروني مطلوب',
      );
    }

    if (password.isEmpty) {
      throw FirebaseAuthException(
        code: 'empty-password',
        message: 'كلمة المرور مطلوبة',
      );
    }

    try {
      return await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(
      email: email.trim().toLowerCase(),
    );
  }

  Future<void> updatePassword(String newPassword) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: 'يجب تسجيل الدخول أولاً');
    }
    if (newPassword.length < 6) {
      throw FirebaseAuthException(code: 'weak-password', message: 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
    }
    await user.updatePassword(newPassword);
  }


  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user', message: 'يجب تسجيل الدخول أولاً');
    }
    if (!user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<bool> refreshEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified == true;
  }

  Future<void> signOut() {
    return _auth.signOut();
  }
}
