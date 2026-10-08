import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_appauth/flutter_appauth.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/net/api_client.dart';
import '../../core/storage/secure_store.dart';

class GoogleAccount {
  const GoogleAccount({required this.email, required this.name, required this.pictureUrl});

  final String email;
  final String? name;
  final String? pictureUrl;
}

/// Google sign-in through the system browser (AppAuth, PKCE, no client secret).
/// Only the drive.file scope is requested: the app sees only files it creates.
class GoogleAuthService {
  GoogleAuthService({required SecureStore secureStore, required ApiClient api, FlutterAppAuth? appAuth})
      : _store = secureStore,
        _api = api,
        _appAuth = appAuth ?? const FlutterAppAuth();

  static const String _authorizationEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String _userInfoEndpoint = 'https://openidconnect.googleapis.com/v1/userinfo';
  static const String _revokeEndpoint = 'https://oauth2.googleapis.com/revoke';

  final SecureStore _store;
  final ApiClient _api;
  final FlutterAppAuth _appAuth;

  String? _accessToken;
  DateTime? _accessTokenExpiry;

  static const AuthorizationServiceConfiguration _configuration = AuthorizationServiceConfiguration(
    authorizationEndpoint: _authorizationEndpoint,
    tokenEndpoint: _tokenEndpoint,
  );

  Future<bool> hasRefreshToken() async => (await _store.read(SecureKeys.googleRefreshToken))?.isNotEmpty ?? false;

  Future<GoogleAccount> signIn() async {
    _requireConfigured();
    final AuthorizationTokenResponse response;
    try {
      response = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          AppConfig.googleClientId,
          AppConfig.googleRedirectUri,
          serviceConfiguration: _configuration,
          scopes: AppConfig.googleScopes.split(' '),
          promptValues: const <String>['consent'],
          additionalParameters: const <String, String>{'access_type': 'offline'},
        ),
      );
    } on FlutterAppAuthUserCancelledException {
      throw const AppException(AppErrorKind.cancelled, 'Google sign-in was cancelled.');
    } on PlatformException catch (error) {
      throw AppException(AppErrorKind.unauthorized, 'Google sign-in failed. ${error.message ?? ''}'.trim());
    }
    final refreshToken = response.refreshToken;
    final accessToken = response.accessToken;
    if (refreshToken == null || refreshToken.isEmpty || accessToken == null || accessToken.isEmpty) {
      throw const AppException(
        AppErrorKind.unauthorized,
        'Google did not return offline access. Remove the app from your Google account permissions and try again.',
      );
    }
    await _store.write(SecureKeys.googleRefreshToken, refreshToken);
    _accessToken = accessToken;
    _accessTokenExpiry = response.accessTokenExpirationDateTime;
    return _fetchAccount(accessToken);
  }

  /// Returns a valid access token, refreshing it with the stored refresh token when needed.
  Future<String> accessToken() async {
    final cached = _accessToken;
    final expiry = _accessTokenExpiry;
    if (cached != null && expiry != null && expiry.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return cached;
    }
    final refreshToken = await _store.read(SecureKeys.googleRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AppException(AppErrorKind.unauthorized, 'Google Drive is not connected.');
    }
    _requireConfigured();
    try {
      final response = await _appAuth.token(
        TokenRequest(
          AppConfig.googleClientId,
          AppConfig.googleRedirectUri,
          refreshToken: refreshToken,
          grantType: GrantType.refreshToken,
          serviceConfiguration: _configuration,
          scopes: AppConfig.googleScopes.split(' '),
        ),
      );
      final token = response.accessToken;
      if (token == null || token.isEmpty) {
        throw const AppException(AppErrorKind.unauthorized, 'Google Drive session expired. Reconnect Google Drive.');
      }
      final rotated = response.refreshToken;
      if (rotated != null && rotated.isNotEmpty && rotated != refreshToken) {
        await _store.write(SecureKeys.googleRefreshToken, rotated);
      }
      _accessToken = token;
      _accessTokenExpiry = response.accessTokenExpirationDateTime ?? DateTime.now().add(const Duration(minutes: 50));
      return token;
    } on FlutterAppAuthPlatformException catch (error) {
      throw AppException(
        AppErrorKind.unauthorized,
        'Google Drive session expired. Reconnect Google Drive. (${error.message ?? 'auth error'})',
      );
    }
  }

  Future<GoogleAccount> _fetchAccount(String accessToken) async {
    final response = await _api.send(
      'GET',
      Uri.parse(_userInfoEndpoint),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    ApiClient.ensureSuccess(response, provider: 'Google');
    final json = ApiClient.decodeObject(response, provider: 'Google');
    return GoogleAccount(
      email: json['email'] as String? ?? 'Google account',
      name: json['name'] as String?,
      pictureUrl: json['picture'] as String?,
    );
  }

  /// Revokes the grant when possible and forgets every local credential.
  Future<void> signOut() async {
    final refreshToken = await _store.read(SecureKeys.googleRefreshToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _api.send(
          'POST',
          Uri.parse(_revokeEndpoint),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'token=${Uri.encodeQueryComponent(refreshToken)}',
          maxRetries: 0,
        );
      } on AppException {
        // Revocation is best effort; local credentials are removed regardless.
      }
    }
    await _store.delete(SecureKeys.googleRefreshToken);
    _accessToken = null;
    _accessTokenExpiry = null;
  }

  void _requireConfigured() {
    if (!AppConfig.hasGoogleOAuth) {
      throw const AppException(AppErrorKind.notConfigured, 'Google OAuth client ID is not configured for this build.');
    }
  }

}
