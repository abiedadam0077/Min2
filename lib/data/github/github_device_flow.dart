import 'dart:async';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/net/api_client.dart';
import '../../domain/integration_models.dart';

/// GitHub OAuth device authorization grant (RFC 8628). No client secret and no redirect URI
/// are needed, which keeps the Android app free of embedded secrets.
class GitHubDeviceFlow {
  GitHubDeviceFlow(this._api);

  final ApiClient _api;

  static const String _provider = 'GitHub';

  Future<DeviceCodeChallenge> start() async {
    if (!AppConfig.hasGitHubOAuth) {
      throw const AppException(AppErrorKind.notConfigured, 'GitHub OAuth client ID is not configured for this build.');
    }
    final response = await _api.send(
      'POST',
      Uri.parse('https://github.com/login/device/code'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'},
      body: Uri(queryParameters: {
        'client_id': AppConfig.githubClientId,
        'scope': AppConfig.githubScopes,
      }).query,
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    final json = ApiClient.decodeObject(response, provider: _provider);
    return DeviceCodeChallenge(
      deviceCode: json['device_code'] as String? ?? '',
      userCode: json['user_code'] as String? ?? '',
      verificationUri: json['verification_uri'] as String? ?? 'https://github.com/login/device',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 900,
      interval: (json['interval'] as num?)?.toInt() ?? 5,
    );
  }

  /// Polls until the user approves, denies or the code expires. Honors slow_down.
  Future<String> pollForToken(DeviceCodeChallenge challenge, {bool Function()? isCancelled}) async {
    var interval = challenge.interval;
    final deadline = DateTime.now().add(Duration(seconds: challenge.expiresIn));
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() ?? false) {
        throw const AppException(AppErrorKind.cancelled, 'Sign-in was cancelled.');
      }
      await Future<void>.delayed(Duration(seconds: interval));
      final response = await _api.send(
        'POST',
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'},
        body: Uri(queryParameters: {
          'client_id': AppConfig.githubClientId,
          'device_code': challenge.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        }).query,
        maxRetries: 1,
      );
      ApiClient.ensureSuccess(response, provider: _provider);
      final json = ApiClient.decodeObject(response, provider: _provider);
      final token = json['access_token'];
      if (token is String && token.isNotEmpty) {
        return token;
      }
      switch (json['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += 5;
          continue;
        case 'expired_token':
          throw const AppException(AppErrorKind.timeout, 'The GitHub code expired. Start the sign-in again.');
        case 'access_denied':
          throw const AppException(AppErrorKind.forbidden, 'GitHub sign-in was denied.');
        default:
          throw AppException(AppErrorKind.unknown, 'GitHub sign-in failed: ${json['error'] ?? 'unknown error'}.');
      }
    }
    throw const AppException(AppErrorKind.timeout, 'The GitHub code expired. Start the sign-in again.');
  }
}
