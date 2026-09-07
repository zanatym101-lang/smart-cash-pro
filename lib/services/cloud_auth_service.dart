import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CloudAuthService {
  static FirebaseAuth? get _auth {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  static User? get currentUser => _auth?.currentUser;
  static String? get currentWorkspaceId => currentUser?.uid;

  static Stream<User?> get authStateChanges =>
      _auth?.authStateChanges() ?? const Stream.empty();

  static Future<UserCredential?> signIn(String email, String password) async {
    final auth = _auth;
    if (auth == null) return null;
    return await auth.signInWithEmailAndPassword(email: email, password: password);
  }

  static Future<UserCredential?> signUp(String email, String password) async {
    final auth = _auth;
    if (auth == null) return null;
    return await auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    final auth = _auth;
    if (auth == null) {
      throw FirebaseAuthException(
        code: 'app-not-initialized',
        message: 'خدمة المصادقة غير متاحة حالياً',
      );
    }
    await auth.sendPasswordResetEmail(email: email.trim());
  }

  static Future<void> signOut() async {
    await _auth?.signOut();
  }
}
