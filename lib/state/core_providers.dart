import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';

import '../core/net/api_client.dart';
import '../core/storage/secure_store.dart';
import '../data/content/content_catalog.dart';
import '../data/github/github_api.dart';
import '../data/github/github_device_flow.dart';
import '../data/google/drive_api.dart';
import '../data/google/google_auth_service.dart';
import '../data/local/app_prefs.dart';
import '../data/minecraft/version_catalog.dart';
import '../data/provisioning/server_actions.dart';
import '../data/provisioning/server_provisioner.dart';
import '../data/tailscale/tailscale_api.dart';

/// Overridden in main() with the SharedPreferences instance loaded before runApp.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden at startup');
});

final prefsProvider = Provider<AppPrefs>((ref) => AppPrefs(ref.watch(sharedPreferencesProvider)));

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(httpClientProvider)));

final githubDeviceFlowProvider = Provider<GitHubDeviceFlow>((ref) => GitHubDeviceFlow(ref.watch(apiClientProvider)));

/// GitHub API bound to the active account. The token is read from secure storage per request.
final githubApiProvider = Provider<GitHubApi>((ref) {
  final store = ref.watch(secureStoreProvider);
  final prefs = ref.watch(prefsProvider);
  return GitHubApi(ref.watch(apiClientProvider), () async {
    final login = prefs.githubActiveLogin;
    if (login == null || login.isEmpty) {
      return null;
    }
    return store.read(SecureKeys.githubToken(login));
  });
});

final googleAuthProvider = Provider<GoogleAuthService>((ref) => GoogleAuthService(
      secureStore: ref.watch(secureStoreProvider),
      api: ref.watch(apiClientProvider),
    ));

final driveApiProvider = Provider<DriveApi>((ref) {
  final auth = ref.watch(googleAuthProvider);
  return DriveApi(ref.watch(apiClientProvider), auth.accessToken);
});

final tailscaleApiProvider = Provider<TailscaleApi>((ref) => TailscaleApi(ref.watch(apiClientProvider)));

final versionCatalogProvider = Provider<VersionCatalog>((ref) => VersionCatalog(ref.watch(apiClientProvider)));

final contentCatalogProvider = Provider<ContentCatalog>((ref) {
  final api = ref.watch(apiClientProvider);
  final store = ref.watch(secureStoreProvider);
  return ContentCatalog(
    api: api,
    curseForge: CurseForgeApi(api),
    curseForgeKeyReader: () => store.read(SecureKeys.curseForgeKey),
  );
});

final serverActionsProvider = Provider<ServerActions>((ref) => ServerActions(
      github: ref.watch(githubApiProvider),
      drive: ref.watch(driveApiProvider),
      api: ref.watch(apiClientProvider),
    ));

final serverProvisionerProvider = Provider<ServerProvisioner>((ref) => ServerProvisioner(
      github: ref.watch(githubApiProvider),
      drive: ref.watch(driveApiProvider),
      store: ref.watch(secureStoreProvider),
      prefs: ref.watch(prefsProvider),
      versions: ref.watch(versionCatalogProvider),
      runnerSource: () => rootBundle.loadString(AppConfig.runnerAssetPath),
    ));

