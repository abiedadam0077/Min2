import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voxelops/core/config/app_config.dart';
import 'package:voxelops/core/utils/format.dart';
import 'package:voxelops/core/errors/app_exception.dart';
import 'package:voxelops/data/google/drive_api.dart';
import 'package:voxelops/data/minecraft/server_icon.dart';
import 'package:image/image.dart' as img;

void main() {
  test('formats byte counts for humans', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
  });

  test('escapes Drive query literals', () {
    expect(DriveApi.escapeQuery("it's a\\test"), "it\\'s a\\\\test");
  });

  test('builds a Google redirect scheme from the client ID', () {
    expect(AppConfig.googleRedirectUri.endsWith(':/oauth2redirect'), isTrue);
  });

  test('exceptions are offline-aware', () {
    expect(const AppException(AppErrorKind.network, 'x').isOffline, isTrue);
    expect(const AppException(AppErrorKind.notFound, 'x').isOffline, isFalse);
  });

  test('server icons are 64x64 PNGs cropped from the centre', () {
    final source = img.Image(width: 300, height: 120);
    final bytes = Uint8List.fromList(img.encodePng(source));
    final icon = buildServerIcon(bytes);
    expect(icon, isNotNull);
    final decoded = img.decodePng(icon!);
    expect(decoded?.width, 64);
    expect(decoded?.height, 64);
  });

  test('runner asset ships with the app and exposes the command protocol', () {
    final text = File('assets/runtime/voxelops_runner.py').readAsStringSync();
    expect(text, contains('save-all flush'));
    expect(text, contains('"control"'));
    expect(text, contains('def main():'));
    expect(text, isNot(contains('GDRIVE_REFRESH_TOKEN =')));
  });
}
