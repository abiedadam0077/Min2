import 'package:flutter/foundation.dart';
import '../data/google/google_auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/motion/motion.dart';
import '../features/accounts/accounts_page.dart';
import '../features/backups/backups_page.dart';
import '../features/connect/connect_page.dart';
import '../features/console/console_page.dart';
import '../features/content/content_page.dart';
import '../features/create/create_server_page.dart';
import '../features/create/creation_progress_page.dart';
import '../features/create/repo_picker_page.dart';
import '../features/drive/drive_storage_page.dart';
import '../features/dashboard/server_dashboard_page.dart';
import '../features/files/file_editor_page.dart';
import '../features/files/file_manager_page.dart';
import '../features/home/home_page.dart';
import '../features/import/import_server_page.dart';
import '../features/more/more_page.dart';
import '../features/notifications/notifications_page.dart';
import '../features/onboarding/welcome_page.dart';
import '../features/servers/servers_page.dart';
import '../features/settings/server_settings_page.dart';
import '../features/splash/splash_page.dart';
import '../state/auth_providers.dart';
import '../state/core_providers.dart';
import 'app_shell.dart';

/// Recomputes redirects whenever sign-in state changes.
class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.onDispose(refresh.dispose);
  ref.listen<GitHubAccountsState>(githubAccountsProvider, (_, __) => refresh.refresh());
  ref.listen<AsyncValue<GoogleAccount?>>(googleAccountProvider, (_, __) => refresh.refresh());

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(ref, state.uri.path),
    routes: [
      GoRoute(path: '/splash', pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: const SplashPage())),
      GoRoute(path: '/welcome', pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: const WelcomePage())),
      GoRoute(path: '/connect', pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: const ConnectPage())),
      GoRoute(
        path: '/repos',
        pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: RepoPickerPage(mode: s.uri.queryParameters['mode'] ?? 'create')),
      ),
      GoRoute(path: '/wizard', pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: const CreateServerPage())),
      GoRoute(path: '/creating', pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: const CreationProgressPage())),
      GoRoute(path: '/import', pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: const ImportServerPage())),
      GoRoute(path: '/accounts', pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: const AccountsPage())),
      GoRoute(path: '/drive/storage', pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: const DriveStoragePage())),
      GoRoute(path: '/notifications', pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: const NotificationsPage())),
      GoRoute(
        path: '/server/:id',
        pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: ServerDashboardPage(serverId: s.pathParameters['id'] ?? '')),
      ),
      GoRoute(
        path: '/server/:id/files',
        pageBuilder: (c, s) => fadeRisePage(
          key: s.pageKey,
          child: FileManagerPage(serverId: s.pathParameters['id'] ?? '', folderId: s.uri.queryParameters['folder']),
        ),
      ),
      GoRoute(
        path: '/server/:id/file',
        pageBuilder: (c, s) => fadeRisePage(
          key: s.pageKey,
          child: FileEditorPage(serverId: s.pathParameters['id'] ?? '', fileId: s.uri.queryParameters['file'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/server/:id/backups',
        pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: BackupsPage(serverId: s.pathParameters['id'] ?? '')),
      ),
      GoRoute(
        path: '/server/:id/settings',
        pageBuilder: (c, s) => fadeRisePage(key: s.pageKey, child: ServerSettingsPage(serverId: s.pathParameters['id'] ?? '')),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/home', pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: const HomePage())),
          GoRoute(path: '/servers', pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: const ServersPage())),
          GoRoute(path: '/content', pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: const ContentPage())),
          GoRoute(path: '/console', pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: const ConsolePage())),
          GoRoute(path: '/more', pageBuilder: (c, s) => fadeThroughPage(key: s.pageKey, child: const MorePage())),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text(state.error?.toString() ?? 'Not found')),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});

/// Setup gate: onboarding first, then GitHub and Google Drive. Tailscale is optional.
String? _redirect(Ref ref, String path) {
  if (path == '/splash') {
    return null;
  }
  final prefs = ref.read(prefsProvider);
  if (!prefs.onboarded) {
    return path == '/welcome' ? null : '/welcome';
  }
  final github = ref.read(githubAccountsProvider).isConnected;
  final google = ref.read(googleAccountProvider);
  if (google.isLoading) {
    return null;
  }
  final driveConnected = google.value != null;
  const setupRoutes = <String>{'/welcome', '/connect', '/accounts', '/drive/storage'};
  if ((!github || !driveConnected) && !setupRoutes.contains(path)) {
    return '/connect';
  }
  if (path == '/welcome' && github && driveConnected) {
    return '/home';
  }
  return null;
}
