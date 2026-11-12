import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth.dart';

const _messages = {
  'invalid-email': 'E-posta adresi geçerli görünmüyor.',
  'invalid-credential': 'E-posta veya şifre yanlış.',
  'wrong-password': 'E-posta veya şifre yanlış.',
  'user-not-found': 'E-posta veya şifre yanlış.',
  'user-disabled': 'Bu hesap kapatılmış.',
  'email-already-in-use': 'Bu e-postayla zaten bir hesap var. Giriş yapmayı dene.',
  'weak-password': 'Şifre çok kısa, en az 6 karakter olmalı.',
  'too-many-requests': 'Çok fazla deneme yapıldı. Biraz bekleyip tekrar dene.',
  'network-request-failed': 'İnternet bağlantısı yok. Giriş için bir kez bağlanman gerekiyor.',
  'account-exists-with-different-credential':
      'Bu e-posta başka bir giriş yöntemiyle kayıtlı. O yöntemle giriş yap.',
  'operation-not-allowed': 'Bu giriş yöntemi şu an kapalı.',
};

class FirebaseAuthService implements Auth {
  /// [serverClientId] is the project's web client id, which Google needs to
  /// issue a token Firebase accepts.
  FirebaseAuthService({required this.serverClientId, FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final String serverClientId;
  final FirebaseAuth _auth;
  Future<void>? _googleReady;

  static Account? _account(User? user) => user == null
      ? null
      : Account(uid: user.uid, email: user.email, name: user.displayName);

  @override
  Account? get current => _account(_auth.currentUser);

  @override
  Stream<Account?> get changes => _auth.authStateChanges().map(_account);

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_messages[error.code] ?? 'Giriş yapılamadı. Tekrar dene.');
    }
  }

  @override
  Future<void> signIn(String email, String password) => _run(
        () => _auth.signInWithEmailAndPassword(email: email, password: password),
      );

  @override
  Future<void> signUp(String email, String password) => _run(
        () => _auth.createUserWithEmailAndPassword(email: email, password: password),
      );

  @override
  Future<void> sendPasswordReset(String email) =>
      _run(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signInWithGoogle() => _run(() async {
        final google = GoogleSignIn.instance;
        final GoogleSignInAccount account;
        try {
          await (_googleReady ??= google.initialize(serverClientId: serverClientId));
          account = await google.authenticate();
        } on GoogleSignInException catch (error) {
          if (error.code == GoogleSignInExceptionCode.canceled) {
            throw const AuthCancelled();
          }
          throw const AuthFailure('Google ile giriş yapılamadı. Tekrar dene.');
        }
        await _auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: account.authentication.idToken),
        );
      });

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    // Otherwise the next Google sign-in silently reuses the same account.
    if (_googleReady != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } on GoogleSignInException {
        // Already signed out of Firebase, which is what matters.
      }
    }
  }
}
