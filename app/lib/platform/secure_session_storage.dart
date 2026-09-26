import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session and PKCE verifier in the Keychain or Keystore.
class SecureGotrueStorage extends GotrueAsyncStorage {
  const SecureGotrueStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> getItem({required String key}) => _storage.read(key: key);

  @override
  Future<void> removeItem({required String key}) => _storage.delete(key: key);

  @override
  Future<void> setItem({required String key, required String value}) {
    return _storage.write(key: key, value: value);
  }
}

/// Keeps the Supabase session in the Keychain or Keystore.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'papersync.supabase.session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await accessToken()) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) {
    return _storage.write(key: _key, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
