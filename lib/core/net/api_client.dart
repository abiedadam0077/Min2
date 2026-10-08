import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../errors/app_exception.dart';

/// Thin HTTP layer shared by every API client.
///
/// - One place for timeouts, retries (GET/HEAD/PUT/DELETE and explicitly idempotent calls),
///   Retry-After handling and error mapping.
/// - Never logs headers or bodies, so tokens cannot leak into logs.
class ApiClient {
  ApiClient(this._client, {Duration? timeout}) : _timeout = timeout ?? const Duration(seconds: 25);

  final http.Client _client;
  final Duration _timeout;

  Future<http.Response> send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int maxRetries = 2,
    bool retryUnsafe = false,
  }) async {
    final bool canRetry = retryUnsafe || method == 'GET' || method == 'HEAD' || method == 'PUT' || method == 'DELETE';
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final request = http.Request(method, uri);
        request.headers['User-Agent'] = AppConfig.userAgent;
        request.headers['Accept'] = 'application/json';
        if (headers != null) {
          request.headers.addAll(headers);
        }
        if (body is Map<String, Object?> || body is List<Object?>) {
          request.headers['Content-Type'] = 'application/json; charset=utf-8';
          request.bodyBytes = utf8.encode(jsonEncode(body));
        } else if (body is String) {
          request.bodyBytes = utf8.encode(body);
        } else if (body is List<int>) {
          request.bodyBytes = body;
        }
        final streamed = await _client.send(request).timeout(timeout ?? _timeout);
        final response = await http.Response.fromStream(streamed).timeout(timeout ?? _timeout);
        final retriable = response.statusCode == 429 || response.statusCode >= 500;
        if (retriable && canRetry && attempt <= maxRetries) {
          await Future<void>.delayed(_backoff(attempt, response.headers['retry-after']));
          continue;
        }
        return response;
      } on TimeoutException {
        if (canRetry && attempt <= maxRetries) {
          await Future<void>.delayed(_backoff(attempt, null));
          continue;
        }
        throw const AppException(AppErrorKind.timeout, 'The request timed out.');
      } on SocketException {
        if (canRetry && attempt <= maxRetries) {
          await Future<void>.delayed(_backoff(attempt, null));
          continue;
        }
        throw const AppException(AppErrorKind.network, 'No network connection.');
      } on http.ClientException {
        throw const AppException(AppErrorKind.network, 'The connection was interrupted.');
      }
    }
  }

  Duration _backoff(int attempt, String? retryAfter) {
    final seconds = int.tryParse(retryAfter ?? '');
    if (seconds != null && seconds > 0 && seconds <= 60) {
      return Duration(seconds: seconds);
    }
    return Duration(milliseconds: 600 * (1 << (attempt - 1)));
  }

  /// Maps HTTP failures to [AppException]. [provider] is a safe label such as "GitHub".
  static void ensureSuccess(http.Response response, {required String provider, Set<int> accept = const {}}) {
    final code = response.statusCode;
    if ((code >= 200 && code < 300) || accept.contains(code)) {
      return;
    }
    final detail = _extractMessage(response);
    final remaining = response.headers['x-ratelimit-remaining'];
    final suffix = detail == null ? '' : ' $detail';
    if (code == 401) {
      throw AppException(AppErrorKind.unauthorized, '$provider rejected the credentials.$suffix', statusCode: code);
    }
    if (code == 403 && remaining == '0') {
      throw AppException(AppErrorKind.rateLimited, '$provider rate limit reached.$suffix', statusCode: code);
    }
    if (code == 403) {
      throw AppException(AppErrorKind.forbidden, '$provider denied access.$suffix', statusCode: code);
    }
    if (code == 404) {
      throw AppException(AppErrorKind.notFound, '$provider resource was not found.$suffix', statusCode: code);
    }
    if (code == 409) {
      throw AppException(AppErrorKind.conflict, '$provider reported a conflict.$suffix', statusCode: code);
    }
    if (code == 422) {
      throw AppException(AppErrorKind.validation, '$provider rejected the request.$suffix', statusCode: code);
    }
    if (code == 429) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '');
      throw AppException(
        AppErrorKind.rateLimited,
        '$provider asked to slow down.',
        statusCode: code,
        retryAfter: seconds == null ? null : Duration(seconds: seconds),
      );
    }
    if (code >= 500) {
      throw AppException(AppErrorKind.server, '$provider is unavailable (HTTP $code).', statusCode: code);
    }
    throw AppException(AppErrorKind.unknown, '$provider returned HTTP $code.$suffix', statusCode: code);
  }

  static String? _extractMessage(http.Response response) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'] ?? decoded['error_description'] ?? decoded['error'];
        if (message is String && message.length <= 240) {
          return message;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static Map<String, dynamic> decodeObject(http.Response response, {required String provider}) {
    final Object? decoded = _decodeJson(response, provider);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw AppException(AppErrorKind.server, '$provider returned an unexpected payload.');
  }

  static List<dynamic> decodeList(http.Response response, {required String provider}) {
    final Object? decoded = _decodeJson(response, provider);
    if (decoded is List<dynamic>) {
      return decoded;
    }
    throw AppException(AppErrorKind.server, '$provider returned an unexpected payload.');
  }

  static Object? _decodeJson(http.Response response, String provider) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw AppException(AppErrorKind.server, '$provider returned invalid JSON.');
    }
  }

  void close() => _client.close();
}
