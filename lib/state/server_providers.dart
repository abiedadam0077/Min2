import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../core/storage/secure_store.dart';
import '../data/content/content_catalog.dart';
import '../data/minecraft/workflow_template.dart';
import '../data/provisioning/server_actions.dart';
import '../domain/integration_models.dart';
import '../domain/server_models.dart';
import 'core_providers.dart';

ServerRecord? serverById(List<ServerRecord> servers, String? id) {
  if (id == null) {
    return null;
  }
  for (final server in servers) {
    if (server.id == id) {
      return server;
    }
  }
  return null;
}

class ServerRegistryNotifier extends Notifier<List<ServerRecord>> {
  @override
  List<ServerRecord> build() => ref.watch(prefsProvider).servers();

  void reload() {
    state = ref.read(prefsProvider).servers();
  }

  Future<void> upsert(ServerRecord record) async {
    final next = <ServerRecord>[...state.where((s) => s.id != record.id), record];
    state = next;
    await ref.read(prefsProvider).saveServers(next);
  }

  /// Forgets a server on this device only. Drive data and the GitHub repository are kept.
  Future<void> forgetLocally(String id) async {
    final next = state.where((s) => s.id != id).toList();
    state = next;
    await ref.read(prefsProvider).saveServers(next);
    final prefs = ref.read(prefsProvider);
    if (prefs.activeServerId == id) {
      await ref.read(activeServerIdProvider.notifier).select(next.isEmpty ? null : next.first.id);
    }
  }
}

final serverRegistryProvider = NotifierProvider<ServerRegistryNotifier, List<ServerRecord>>(ServerRegistryNotifier.new);

class ActiveServerNotifier extends Notifier<String?> {
  @override
  String? build() => ref.watch(prefsProvider).activeServerId;

  Future<void> select(String? id) async {
    state = id;
    await ref.read(prefsProvider).setActiveServerId(id);
  }
}

final activeServerIdProvider = NotifierProvider<ActiveServerNotifier, String?>(ActiveServerNotifier.new);

final activeServerProvider = Provider<ServerRecord?>((ref) {
  final servers = ref.watch(serverRegistryProvider);
  final id = ref.watch(activeServerIdProvider);
  return serverById(servers, id) ?? (servers.isEmpty ? null : servers.first);
});

/// Live status: polls control/status.json every 12 seconds while a widget watches it.
final serverStatusProvider = StreamProvider.autoDispose.family<ServerStatus, String>((ref, serverId) async* {
  while (true) {
    final record = serverById(ref.read(serverRegistryProvider), serverId);
    if (record == null) {
      return;
    }
    try {
      yield await ref.read(serverActionsProvider).readStatus(record);
    } on AppException catch (error) {
      yield ServerStatus.unreachable(error.message);
    }
    await Future<void>.delayed(const Duration(seconds: 12));
  }
});

/// Console tail: polls control/live.log every 6 seconds. Keeps the last good lines on errors.
final consoleProvider = StreamProvider.autoDispose.family<List<String>, String>((ref, serverId) async* {
  var lines = <String>[];
  while (true) {
    final record = serverById(ref.read(serverRegistryProvider), serverId);
    if (record == null) {
      return;
    }
    try {
      lines = await ref.read(serverActionsProvider).readConsole(record);
    } on AppException {
      // Keep showing the last good tail; the status card reports connectivity problems.
    }
    yield lines;
    await Future<void>.delayed(const Duration(seconds: 6));
  }
});

/// GitHub Actions runs for the server workflow, refreshed every 20 seconds.
final workflowRunsProvider = StreamProvider.autoDispose.family<List<GitHubRun>, String>((ref, serverId) async* {
  var runs = <GitHubRun>[];
  while (true) {
    final record = serverById(ref.read(serverRegistryProvider), serverId);
    if (record == null) {
      return;
    }
    try {
      runs = await ref.read(githubApiProvider).listRuns(record.repoOwner, record.repoName);
    } on AppException {
      // Offline or rate limited: keep the previous list.
    }
    yield runs;
    await Future<void>.delayed(const Duration(seconds: 20));
  }
});

final driveFolderProvider = FutureProvider.autoDispose.family<List<DriveFile>, String>((ref, folderId) {
  return ref.read(serverActionsProvider).listFolder(folderId);
});

final backupsProvider = FutureProvider.autoDispose.family<List<BackupEntry>, String>((ref, serverId) {
  final record = serverById(ref.read(serverRegistryProvider), serverId);
  if (record == null) {
    return Future.value(const <BackupEntry>[]);
  }
  return ref.read(serverActionsProvider).listBackups(record);
});

final runtimeSettingsProvider = FutureProvider.autoDispose.family<RuntimeSettings, String>((ref, serverId) {
  final record = serverById(ref.read(serverRegistryProvider), serverId);
  if (record == null) {
    return Future.value(const RuntimeSettings());
  }
  return ref.read(serverActionsProvider).readRuntime(record);
});

final serverSettingsProvider = FutureProvider.autoDispose.family<ServerSettings, String>((ref, serverId) {
  final record = serverById(ref.read(serverRegistryProvider), serverId);
  if (record == null) {
    return Future.value(const ServerSettings());
  }
  return ref.read(serverActionsProvider).readSettings(record);
});

/// Tailscale address from the Tailscale API. Used when the runner has not reported an IP yet.
final tailscaleDeviceProvider = FutureProvider.autoDispose.family<TailscaleDevice?, String>((ref, serverId) async {
  final record = serverById(ref.read(serverRegistryProvider), serverId);
  if (record == null) {
    return null;
  }
  final store = ref.read(secureStoreProvider);
  final clientId = await store.read(SecureKeys.tailscaleClientId);
  final secret = await store.read(SecureKeys.tailscaleClientSecret);
  if (clientId == null || secret == null) {
    return null;
  }
  return ref.read(tailscaleApiProvider).findDevice(
        clientId: clientId,
        clientSecret: secret,
        hostnamePrefix: WorkflowTemplate.hostname(record),
      );
});

final driveQuotaProvider = FutureProvider.autoDispose((ref) => ref.read(driveApiProvider).about());

final minecraftVersionsProvider = FutureProvider.family<List<McVersion>, ServerSoftware>((ref, software) {
  return ref.read(versionCatalogProvider).versionsFor(software);
});

final contentSearchProvider = FutureProvider.autoDispose.family<List<ContentProject>, ({ContentQuery query, ServerSoftware software, String minecraftVersion})>((ref, args) {
  return ref.read(contentCatalogProvider).search(
        args.query,
        software: args.software,
        minecraftVersion: args.minecraftVersion,
      );
});

final contentFilesProvider = FutureProvider.autoDispose.family<List<ContentFile>, ({ContentProject project, ContentKind kind, ServerSoftware software, String minecraftVersion})>((ref, args) {
  return ref.read(contentCatalogProvider).filesFor(
        args.project,
        kind: args.kind,
        software: args.software,
        minecraftVersion: args.minecraftVersion,
      );
});

final githubRepoInfoProvider = FutureProvider.autoDispose.family<GitHubRepo, ({String owner, String name})>((ref, args) {
  return ref.read(githubApiProvider).getRepository(args.owner, args.name);
});
