import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxelops/core/i18n/strings_ar.dart';
import 'package:voxelops/core/i18n/strings_en.dart';

void main() {
  test('Arabic and English dictionaries define exactly the same keys', () {
    expect(stringsAr.keys.toSet(), stringsEn.keys.toSet());
    for (final entry in stringsAr.entries) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
    }
  });

  test('every literal translation key used in lib/ exists in the dictionaries', () {
    final pattern = RegExp(r"""tr\('([a-zA-Z0-9_.]+)'|successKey: '([a-zA-Z0-9_.]+)'""");
    final missing = <String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) {
        continue;
      }
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        final key = match.group(1) ?? match.group(2)!;
        if (!stringsEn.containsKey(key)) {
          missing.add('${file.path}: $key');
        }
      }
    }
    expect(missing, isEmpty);
  });
}
