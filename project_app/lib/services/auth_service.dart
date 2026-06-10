import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn(String emailOrPhone, String password) async {
    final String authEmail = emailOrPhone.contains('@') ? emailOrPhone : '$emailOrPhone@phone.local';
    return await _auth.signInWithEmailAndPassword(email: authEmail, password: password);
  }

  Future<UserCredential> register(String emailOrPhone, String password) async {
    final String authEmail = emailOrPhone.contains('@') ? emailOrPhone : '$emailOrPhone@phone.local';
    try {
      return await _auth.createUserWithEmailAndPassword(email: authEmail, password: password);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        return await _auth.signInWithEmailAndPassword(email: authEmail, password: password);
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

final authService = AuthService();
