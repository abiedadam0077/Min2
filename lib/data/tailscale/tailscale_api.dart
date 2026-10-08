import '../../core/errors/app_exception.dart';
import '../../core/net/api_client.dart';
import '../../domain/integration_models.dart';

/// Tailscale control-plane API using an OAuth client (client credentials grant).
/// The OAuth client needs the devices read scope to show addresses and the auth_keys
/// scope so the GitHub Actions runner can join the tailnet with the official action.
class TailscaleApi {
  TailscaleApi(this._api);

  static const String _base = 'https://api.tailscale.com/api/v2';
  static const String _provider = 'Tailscale';

  final ApiClient _api;

  Future<String> _token(String clientId, String clientSecret) async {
    final response = await _api.send(
      'POST',
      Uri.parse('$_base/oauth/token'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: Uri(queryParameters: {'client_id': clientId, 'client_secret': clientSecret}).query,
      maxRetries: 1,
    );
    if (response.statusCode == 400 || response.statusCode == 401) {
      throw const AppException(AppErrorKind.unauthorized, 'Tailscale rejected the OAuth client ID or secret.');
    }
    ApiClient.ensureSuccess(response, provider: _provider);
    final token = ApiClient.decodeObject(response, provider: _provider)['access_token'];
    if (token is! String || token.isEmpty) {
      throw const AppException(AppErrorKind.unauthorized, 'Tailscale did not return an access token.');
    }
    return token;
  }

  /// Verifies the credentials by listing devices of [tailnet] ("-" means the token's tailnet).
  Future<List<TailscaleDevice>> devices({
    required String clientId,
    required String clientSecret,
    String tailnet = '-',
  }) async {
    final token = await _token(clientId, clientSecret);
    final response = await _api.send(
      'GET',
      Uri.parse('$_base/tailnet/${Uri.encodeComponent(tailnet)}/devices').replace(queryParameters: {'fields': 'default'}),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 403) {
      throw const AppException(
        AppErrorKind.forbidden,
        'The Tailscale OAuth client is missing the devices read scope.',
        statusCode: 403,
      );
    }
    ApiClient.ensureSuccess(response, provider: _provider);
    final json = ApiClient.decodeObject(response, provider: _provider);
    final items = json['devices'];
    if (items is! List<dynamic>) {
      return const <TailscaleDevice>[];
    }
    return items.whereType<Map<String, dynamic>>().map(TailscaleDevice.fromJson).toList();
  }

  /// Finds the online node whose hostname starts with [hostnamePrefix] (duplicates get suffixes).
  Future<TailscaleDevice?> findDevice({
    required String clientId,
    required String clientSecret,
    required String hostnamePrefix,
  }) async {
    final all = await devices(clientId: clientId, clientSecret: clientSecret);
    final matches = all.where((d) => d.hostname.startsWith(hostnamePrefix)).toList()
      ..sort((a, b) => (b.online ? 1 : 0).compareTo(a.online ? 1 : 0));
    return matches.isEmpty ? null : matches.first;
  }
}
