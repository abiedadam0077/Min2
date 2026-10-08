import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Android Keystore-backed storage for every credential (GitHub tokens, Google refresh
/// tokens, Tailscale OAuth secrets). Nothing secret is written to SharedPreferences or logs.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
      return;
    }
    await _storage.write(key: key, value: value);
  }

  Future<void> delete(String key) => _storage.delete(key: key);
}

abstract final class SecureKeys {
  static const String googleRefreshToken = 'google.refresh_token.v1';
  static const String tailscaleClientId = 'tailscale.client_id.v1';
  static const String tailscaleClientSecret = 'tailscale.client_secret.v1';
  static const String curseForgeKey = 'curseforge.api_key.v1';

  /// One secure entry per GitHub account. [login] is GitHub's case-insensitive login.
  static String githubToken(String login) => 'github.token.v1.${login.toLowerCase()}';
}
