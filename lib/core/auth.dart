/// The signed-in user.
class Account {
  const Account({required this.uid, this.email, this.name});

  final String uid;
  final String? email;
  final String? name;
}

/// A sign-in problem, with a message ready to show.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
}

/// Thrown when the user backs out of signing in; nothing needs saying.
class AuthCancelled implements Exception {
  const AuthCancelled();
}

/// Accounts, kept behind an interface so the flows can be tested without a
/// server. Every method throws [AuthFailure] when it does not succeed.
abstract class Auth {
  Account? get current;

  /// The account after each sign-in, null after each sign-out.
  Stream<Account?> get changes;

  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);

  /// Throws [AuthCancelled] if the user closes the account picker.
  Future<void> signInWithGoogle();
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}
