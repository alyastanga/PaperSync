import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/auth.dart';

class SupabasePaperSyncAuth implements PaperSyncAuth {
  SupabasePaperSyncAuth(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 20);

  @override
  SignedInAccount? get current {
    final id = _client.auth.currentUser?.id;
    if (id == null) return null;
    return SignedInAccount(id: id);
  }

  @override
  Stream<SignedInAccount?> watchAccount() {
    return _client.auth.onAuthStateChange.map((event) {
      final id = event.session?.user.id;
      if (id == null) return null;
      return SignedInAccount(id: id);
    });
  }

  @override
  Future<void> sendEmailCode(String email) async {
    final address = email.trim();
    if (!isEmailAddress(address)) {
      throw const FormatException('email');
    }
    await _client.auth.signInWithOtp(email: address).timeout(_timeout);
  }

  @override
  Future<void> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    await _client.auth
        .verifyOTP(email: email.trim(), token: code.trim(), type: OtpType.email)
        .timeout(_timeout);
  }

  @override
  Future<bool> refreshSession() async {
    try {
      final response = await _client.auth.refreshSession().timeout(_timeout);
      return response.session != null;
    } on AuthException {
      return false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> signOut() {
    return _client.auth.signOut().timeout(_timeout);
  }
}
