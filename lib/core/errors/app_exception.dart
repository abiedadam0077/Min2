/// Typed failure used across services. Messages are technical (English) and must never
/// contain tokens, secrets or personal data. The UI maps [kind] to localized copy.
enum AppErrorKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  rateLimited,
  notConfigured,
  server,
  cancelled,
  unknown,
}

class AppException implements Exception {
  const AppException(
    this.kind,
    this.message, {
    this.statusCode,
    this.retryAfter,
  });

  final AppErrorKind kind;
  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  bool get isOffline => kind == AppErrorKind.network || kind == AppErrorKind.timeout;

  @override
  String toString() => 'AppException(${kind.name}, status: $statusCode): $message';
}
