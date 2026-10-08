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

/// Maps OAuth error codes to outcomes the user can act on. Kept pure so it can be unit tested.
AppException classifyGoogleAuthError(String? oauthError) {
  switch (oauthError) {
    case 'access_denied':
      return const AppException(AppErrorKind.forbidden, 'Google denied the requested permissions.');
    case 'invalid_grant':
      return const AppException(AppErrorKind.sessionExpired, 'The Google grant is no longer valid.');
    case 'invalid_client':
    case 'unauthorized_client':
    case 'redirect_uri_mismatch':
    case 'invalid_request':
      return const AppException(AppErrorKind.notConfigured, 'The Google OAuth client is not configured for this build.');
    default:
      return const AppException(AppErrorKind.signInFailed, 'Google sign-in did not complete.');
  }
}

/// Google sign-in through the system browser (AppAuth with PKCE, no client secret).
///
/// Scopes: openid, email, profile and drive.file. drive.file only grants access to files and folders
/// that this app creates, which is exactly what the server storage needs.
class GoogleAuthService {
  GoogleAuthService({required SecureStore secureStore, required ApiClient api, FlutterAppAuth? appAuth})
      : _store = secureStore,
        _api = api,
        _appAuth = appAuth ?? const FlutterAppAuth();

  static const String _authorizationEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String _userInfoEndpoint = 'https://openidconnect.googleapis.com/v1/userinfo';
  static const String _revokeEndpoint = 'https://oauth2.googleapis.com/revoke';

  static const AuthorizationServiceConfiguration _configuration = AuthorizationServiceConfiguration(
    authorizationEndpoint: _authorizationEndpoint,
    tokenEndpoint: _tokenEndpoint,
  );

  final SecureStore _store;
  final ApiClient _api;
  final FlutterAppAuth _appAuth;

  String? _accessToken;
  DateTime? _accessTokenExpiry;

  Future<bool> hasRefreshToken() async => (await _store.read(SecureKeys.googleRefreshToken))?.isNotEmpty ?? false;

  /// Opens the Google consent screen and stores the refresh token in secure storage.
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
          // "consent" makes Google return a refresh token even if the user approved before.
          promptValues: const <String>['consent'],
          additionalParameters: const <String, String>{'access_type': 'offline'},
        ),
      );
    } on FlutterAppAuthUserCancelledException {
      throw const AppException(AppErrorKind.cancelled, 'Google sign-in was cancelled.');
    } on FlutterAppAuthPlatformException catch (error) {
      throw classifyGoogleAuthError(error.platformErrorDetails.error);
    } on PlatformException {
      throw const AppException(AppErrorKind.signInFailed, 'Google sign-in did not complete.');
    }
    final refreshToken = response.refreshToken;
    final accessToken = response.accessToken;
    if (refreshToken == null || refreshToken.isEmpty || accessToken == null || accessToken.isEmpty) {
      throw const AppException(AppErrorKind.signInFailed, 'Google did not grant offline access.');
    }
    await _store.write(SecureKeys.googleRefreshToken, refreshToken);
    _accessToken = accessToken;
    _accessTokenExpiry = response.accessTokenExpirationDateTime ?? DateTime.now().add(const Duration(minutes: 50));
    return _fetchAccount(accessToken);
  }

  /// Returns a valid access token. Refreshes with the stored refresh token when it is near expiry
  /// or when [forceRefresh] is true (after the Drive API answered 401).
  Future<String> accessToken({bool forceRefresh = false}) async {
    final cached = _accessToken;
    final expiry = _accessTokenExpiry;
    if (!forceRefresh && cached != null && expiry != null && expiry.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return cached;
    }
    final refreshToken = await _store.read(SecureKeys.googleRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const AppException(AppErrorKind.sessionExpired, 'Google Drive is not connected.');
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
        ),
      );
      final token = response.accessToken;
      if (token == null || token.isEmpty) {
        throw const AppException(AppErrorKind.sessionExpired, 'Google did not return an access token.');
      }
      final rotated = response.refreshToken;
      if (rotated != null && rotated.isNotEmpty && rotated != refreshToken) {
        await _store.write(SecureKeys.googleRefreshToken, rotated);
      }
      _accessToken = token;
      _accessTokenExpiry = response.accessTokenExpirationDateTime ?? DateTime.now().add(const Duration(minutes: 50));
      return token;
    } on FlutterAppAuthPlatformException catch (error) {
      final mapped = classifyGoogleAuthError(error.platformErrorDetails.error);
      if (mapped.kind == AppErrorKind.sessionExpired) {
        // The grant was revoked or expired: forget it so the UI asks the user to connect again.
        await _store.delete(SecureKeys.googleRefreshToken);
        _accessToken = null;
        _accessTokenExpiry = null;
      }
      throw mapped;
    } on PlatformException {
      throw const AppException(AppErrorKind.network, 'Could not refresh the Google session.');
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

  /// Revokes the grant when possible and removes every local credential.
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
