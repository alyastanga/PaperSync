/// The signed-in account. The email stays out of this type so it is not logged.
class SignedInAccount {
  const SignedInAccount({required this.id});

  final String id;
}

/// Email one-time-code sign-in. The session itself lives in secure storage.
abstract class PaperSyncAuth {
  SignedInAccount? get current;

  Stream<SignedInAccount?> watchAccount();

  Future<void> sendEmailCode(String email);

  Future<void> verifyEmailCode({required String email, required String code});

  /// One refresh. False means the session is gone and the user must sign in.
  Future<bool> refreshSession();

  Future<void> signOut();
}

class DisabledAuth implements PaperSyncAuth {
  const DisabledAuth();

  @override
  SignedInAccount? get current => null;

  @override
  Stream<SignedInAccount?> watchAccount() =>
      const Stream<SignedInAccount?>.empty();

  @override
  Future<void> sendEmailCode(String email) async {}

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {}

  @override
  Future<bool> refreshSession() async => false;

  @override
  Future<void> signOut() async {}
}

final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isEmailAddress(String value) => _email.hasMatch(value.trim());
