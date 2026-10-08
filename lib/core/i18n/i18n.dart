import 'package:flutter/widgets.dart';

import '../errors/app_exception.dart';
import 'strings_ar.dart';
import 'strings_en.dart';

/// Lookup helpers. Keys are dotted identifiers defined in strings_en.dart and strings_ar.dart.
extension AppI18n on BuildContext {
  bool get isArabic => Localizations.localeOf(this).languageCode == 'ar';

  String tr(String key, {Map<String, Object?>? args}) {
    final table = isArabic ? stringsAr : stringsEn;
    var text = table[key] ?? stringsEn[key] ?? key;
    if (args != null) {
      args.forEach((name, value) {
        text = text.replaceAll('{$name}', '$value');
      });
    }
    return text;
  }
}

/// Maps a thrown error to a localized, user-facing message. Technical details never include secrets.
String describeError(BuildContext context, Object error) {
  if (error is AppException) {
    final key = switch (error.kind) {
      AppErrorKind.network => 'error.network',
      AppErrorKind.timeout => 'error.timeout',
      AppErrorKind.unauthorized => 'error.unauthorized',
      AppErrorKind.forbidden => 'error.forbidden',
      AppErrorKind.notFound => 'error.notFound',
      AppErrorKind.conflict => 'error.conflict',
      AppErrorKind.validation => 'error.validation',
      AppErrorKind.rateLimited => 'error.rateLimited',
      AppErrorKind.notConfigured => 'error.notConfigured',
      AppErrorKind.server => 'error.server',
      AppErrorKind.cancelled => 'error.cancelled',
      AppErrorKind.unknown => 'error.unknown',
    };
    return context.tr(key);
  }
  return context.tr('error.unknown');
}
