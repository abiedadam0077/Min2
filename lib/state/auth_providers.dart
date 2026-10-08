import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../core/storage/secure_store.dart';
import '../data/github/github_api.dart';
import '../data/google/google_auth_service.dart';
import '../domain/integration_models.dart';
import 'core_providers.dart';

class GitHubAccount {
  const GitHubAccount({required this.login, required this.name, required this.avatarUrl});

  final String login;
  final String? name;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {'login': login, 'name': name, 'avatarUrl': avatarUrl};

  static GitHubAccount fromJson(Map<String, dynamic> json) => GitHubAccount(
        login: json['login'] as String? ?? '',
        name: json['name'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
      );
}

class GitHubAccountsState {
  const GitHubAccountsState({this.accounts = const <GitHubAccount>[], this.activeLogin});

  final List<GitHubAccount> accounts;
  final String? activeLogin;

  GitHubAccount? get active {
    for (final account in accounts) {
      if (account.login == activeLogin) {
        return account;
      }
    }
    return null;
  }

  bool get isConnected => active != null;
}

/// Multiple GitHub accounts on one device. Each token lives under its own secure key.
class GitHubAccountsNotifier extends Notifier<GitHubAccountsState> {
  @override
  GitHubAccountsState build() {
    final prefs = ref.watch(prefsProvider);
    final accounts = prefs.githubAccounts().map(GitHubAccount.fromJson).where((a) => a.login.isNotEmpty).toList();
    final active = prefs.githubActiveLogin;
    return GitHubAccountsState(accounts: accounts, activeLogin: active);
  }

  /// Validates [token] against GitHub, stores it securely and makes the account active.
  Future<GitHubUser> addAccountWithToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw const AppException(AppErrorKind.validation, 'Enter a GitHub token.');
    }
    final api = GitHubApi(ref.read(apiClientProvider), () async => trimmed);
    final user = await api.currentUser();
    await _store(user, trimmed);
    return user;
  }

  Future<void> _store(GitHubUser user, String token) async {
    final store = ref.read(secureStoreProvider);
    final prefs = ref.read(prefsProvider);
    await store.write(SecureKeys.githubToken(user.login), token);
    final account = GitHubAccount(login: user.login, name: user.name, avatarUrl: user.avatarUrl);
    final others = state.accounts.where((a) => a.login.toLowerCase() != user.login.toLowerCase()).toList();
    final accounts = [...others, account];
    await prefs.saveGitHubAccounts(accounts.map((a) => a.toJson()).toList());
    await prefs.setGitHubActiveLogin(user.login);
    state = GitHubAccountsState(accounts: accounts, activeLogin: user.login);
  }

  Future<void> switchTo(String login) async {
    if (!state.accounts.any((a) => a.login == login)) {
      return;
    }
    await ref.read(prefsProvider).setGitHubActiveLogin(login);
    state = GitHubAccountsState(accounts: state.accounts, activeLogin: login);
  }

  Future<void> removeAccount(String login) async {
    await ref.read(secureStoreProvider).delete(SecureKeys.githubToken(login));
    final accounts = state.accounts.where((a) => a.login != login).toList();
    final prefs = ref.read(prefsProvider);
    await prefs.saveGitHubAccounts(accounts.map((a) => a.toJson()).toList());
    final nextActive = state.activeLogin == login ? (accounts.isEmpty ? null : accounts.first.login) : state.activeLogin;
    await prefs.setGitHubActiveLogin(nextActive);
    state = GitHubAccountsState(accounts: accounts, activeLogin: nextActive);
  }
}

final githubAccountsProvider = NotifierProvider<GitHubAccountsNotifier, GitHubAccountsState>(GitHubAccountsNotifier.new);

/// Google account shown in the UI. Credentials stay in secure storage.
class GoogleAccountNotifier extends AsyncNotifier<GoogleAccount?> {
  @override
  Future<GoogleAccount?> build() async {
    final stored = ref.watch(prefsProvider).googleAccount;
    final hasToken = await ref.watch(googleAuthProvider).hasRefreshToken();
    if (stored == null || !hasToken) {
      return null;
    }
    return GoogleAccount(
      email: stored['email'] as String? ?? 'Google account',
      name: stored['name'] as String?,
      pictureUrl: stored['picture'] as String?,
    );
  }

  /// Runs the Google sign-in flow. Any failure except a user cancellation is reported as a single
  /// friendly "could not connect Google Drive" error; the technical reason stays out of the UI.
  Future<void> connect() async {
    state = AsyncLoading<GoogleAccount?>();
    state = await AsyncValue.guard(() async {
      try {
        final account = await ref.read(googleAuthProvider).signIn();
        await ref.read(prefsProvider).setGoogleAccount({
          'email': account.email,
          'name': account.name,
          'picture': account.pictureUrl,
        });
        return account;
      } on AppException catch (error) {
        if (error.kind == AppErrorKind.cancelled) {
          rethrow;
        }
        throw AppException(AppErrorKind.signInFailed, error.message, statusCode: error.statusCode);
      }
    });
  }

  /// Confirms that the stored grant still works by refreshing the access token.
  /// A revoked or expired grant clears the local connection so the card asks the user to connect again.
  Future<void> verify() async {
    try {
      await ref.read(googleAuthProvider).accessToken(forceRefresh: true);
    } on AppException catch (error) {
      if (error.kind == AppErrorKind.sessionExpired) {
        await ref.read(prefsProvider).setGoogleAccount(null);
        state = const AsyncData<GoogleAccount?>(null);
      }
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await ref.read(googleAuthProvider).signOut();
    await ref.read(prefsProvider).setGoogleAccount(null);
    state = const AsyncData<GoogleAccount?>(null);
  }
}

final googleAccountProvider = AsyncNotifierProvider<GoogleAccountNotifier, GoogleAccount?>(GoogleAccountNotifier.new);

class TailscaleConnection {
  const TailscaleConnection({required this.tailnet});

  final String tailnet;
}

/// Tailscale OAuth client used to read device addresses and to let runners join the tailnet.
class TailscaleConnectionNotifier extends AsyncNotifier<TailscaleConnection?> {
  @override
  Future<TailscaleConnection?> build() async {
    final prefs = ref.watch(prefsProvider);
    if (!prefs.tailscaleConnected) {
      return null;
    }
    return TailscaleConnection(tailnet: prefs.tailscaleTailnet);
  }

  Future<void> connect({required String clientId, required String clientSecret, required String tailnet}) async {
    final cleanId = clientId.trim();
    final cleanSecret = clientSecret.trim();
    final cleanTailnet = tailnet.trim().isEmpty ? '-' : tailnet.trim();
    if (cleanId.isEmpty || cleanSecret.isEmpty) {
      throw const AppException(AppErrorKind.validation, 'Enter both the OAuth client ID and secret.');
    }
    await ref.read(tailscaleApiProvider).devices(clientId: cleanId, clientSecret: cleanSecret, tailnet: cleanTailnet);
    final store = ref.read(secureStoreProvider);
    await store.write(SecureKeys.tailscaleClientId, cleanId);
    await store.write(SecureKeys.tailscaleClientSecret, cleanSecret);
    final prefs = ref.read(prefsProvider);
    await prefs.setTailscaleTailnet(cleanTailnet);
    await prefs.setTailscaleConnected(true);
    state = AsyncData(TailscaleConnection(tailnet: cleanTailnet));
  }

  Future<void> disconnect() async {
    final store = ref.read(secureStoreProvider);
    await store.delete(SecureKeys.tailscaleClientId);
    await store.delete(SecureKeys.tailscaleClientSecret);
    await ref.read(prefsProvider).setTailscaleConnected(false);
    state = const AsyncData<TailscaleConnection?>(null);
  }
}

final tailscaleConnectionProvider = AsyncNotifierProvider<TailscaleConnectionNotifier, TailscaleConnection?>(TailscaleConnectionNotifier.new);

/// CurseForge API key (the user's own key from console.curseforge.com). Stored only in secure storage.
final curseForgeKeyPresentProvider = FutureProvider<bool>((ref) async {
  final key = await ref.watch(secureStoreProvider).read(SecureKeys.curseForgeKey);
  return key != null && key.isNotEmpty;
});
