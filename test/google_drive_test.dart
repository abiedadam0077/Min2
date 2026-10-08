import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:voxelops/core/config/app_config.dart';
import 'package:voxelops/core/errors/app_exception.dart';
import 'package:voxelops/core/net/api_client.dart';
import 'package:voxelops/data/google/drive_api.dart';
import 'package:voxelops/data/google/google_auth_service.dart';
import 'package:voxelops/data/provisioning/drive_layout.dart';

void main() {
  group('Google sign-in errors', () {
    test('a denied consent is reported as forbidden, not as a scope error', () {
      final error = classifyGoogleAuthError('access_denied');
      expect(error.kind, AppErrorKind.forbidden);
    });

    test('a revoked grant means the session expired', () {
      expect(classifyGoogleAuthError('invalid_grant').kind, AppErrorKind.sessionExpired);
    });

    test('client misconfiguration is reported as not configured', () {
      for (final code in <String>['invalid_client', 'unauthorized_client', 'redirect_uri_mismatch']) {
        expect(classifyGoogleAuthError(code).kind, AppErrorKind.notConfigured, reason: code);
      }
    });

    test('unknown failures become a generic sign-in failure', () {
      expect(classifyGoogleAuthError(null).kind, AppErrorKind.signInFailed);
      expect(classifyGoogleAuthError('something_else').kind, AppErrorKind.signInFailed);
    });
  });

  group('Google Drive client', () {
    test('escapeQuery escapes quotes and backslashes for Drive queries', () {
      expect(DriveApi.escapeQuery("it's \\ here"), "it\\'s \\\\ here");
    });

    test('a 401 refreshes the access token exactly once and retries the request', () async {
      var refreshes = 0;
      final mock = MockClient((request) async {
        if (request.headers['Authorization'] == 'Bearer stale') {
          return http.Response('{"error":{"code":401}}', 401, headers: {'content-type': 'application/json'});
        }
        return http.Response(
          '{"files":[{"id":"f1","name":"world","mimeType":"application/vnd.google-apps.folder"}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final api = DriveApi(ApiClient(mock), ({bool forceRefresh = false}) async {
        if (forceRefresh) {
          refreshes++;
          return 'fresh';
        }
        return 'stale';
      });

      final files = await api.listChildren('parent');

      expect(refreshes, 1);
      expect(files.single.name, 'world');
      expect(files.single.isFolder, isTrue);
    });

    test('a missing file on lookup returns null instead of throwing', () async {
      final mock = MockClient((request) async {
        return http.Response('{"files":[]}', 200, headers: {'content-type': 'application/json'});
      });
      final api = DriveApi(ApiClient(mock), ({bool forceRefresh = false}) async => 'token');
      expect(await api.findChild('parent', 'server.properties'), isNull);
    });
  });

  group('Configuration and layout', () {
    test('without a Google client ID the redirect scheme is a non-matching placeholder', () {
      expect(AppConfig.hasGoogleOAuth, isFalse);
      expect(AppConfig.googleRedirectScheme, 'com.voxelops.oauth.unconfigured');
    });

    test('the default storage root is Minecraft Servers', () {
      expect(AppConfig.driveRootFolder, 'Minecraft Servers');
    });

    test('every server folder of the documented layout is present', () {
      expect(
        DriveLayout.topFolders,
        containsAll(<String>['server', 'world', 'world_nether', 'world_the_end', 'mods', 'plugins', 'config', 'backups']),
      );
      expect(DriveLayout.metadataFile, 'metadata.json');
      expect(DriveLayout.propertiesFile, 'server.properties');
      expect(DriveLayout.system, '_voxelops');
    });
  });
}
