import 'dart:convert';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/storage/secure_store.dart';
import '../../domain/integration_models.dart';
import '../../domain/server_draft.dart';
import '../../domain/server_models.dart';
import '../github/github_api.dart';
import '../github/sealed_box.dart';
import '../google/drive_api.dart';
import '../local/app_prefs.dart';
import '../minecraft/server_properties.dart';
import '../minecraft/version_catalog.dart';
import '../minecraft/workflow_template.dart';
import 'drive_layout.dart';

typedef ProvisionProgress = void Function(String step, double fraction);

/// A server folder under the storage root that contains a VoxelOps metadata.json.
class DiscoveredServer {
  const DiscoveredServer({required this.folderId, required this.folderName, required this.record});

  final String folderId;
  final String folderName;
  final ServerRecord record;
}

/// Creates, rebinds and imports servers. Google Drive is the source of truth: everything needed
/// to recover a server (metadata, properties, worlds, mods, backups) lives in its Drive folder.
class ServerProvisioner {
  ServerProvisioner({
    required this.github,
    required this.drive,
    required this.store,
    required this.prefs,
    required this.versions,
    required this.runnerSource,
  });

  final GitHubApi github;
  final DriveApi drive;
  final SecureStore store;
  final AppPrefs prefs;
  final VersionCatalog versions;
  final Future<String> Function() runnerSource;

  static final RegExp _repoNamePattern = RegExp(r'^[A-Za-z0-9._-]{1,100}$');

  /// Lowercase slug that is valid as a GitHub repository name.
  static String suggestRepoName(String serverName) {
    final slug = serverName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final base = slug.isEmpty ? 'minecraft' : slug;
    return 'voxelops-${base.length > 60 ? base.substring(0, 60) : base}';
  }

  /// Returns the storage root ("Minecraft Servers" by default). With [create] false it never creates anything.
  Future<String?> storageRootId({bool create = true}) async {
    final saved = prefs.driveRootId;
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    final name = prefs.driveRootName ?? AppConfig.driveRootFolder;
    final existing = await drive.findChild('root', name, mimeType: DriveApi.folderMime);
    if (existing != null) {
      await prefs.setDriveRoot(existing.id, existing.name);
      return existing.id;
    }
    if (!create) {
      return null;
    }
    final created = await drive.createFolder('root', name);
    await prefs.setDriveRoot(created.id, created.name);
    return created.id;
  }

  /// Creates a new storage root (or reuses a folder with the same name that VoxelOps already owns).
  Future<DriveFile> createStorageRoot(String name) async {
    final cleaned = name.trim().isEmpty ? AppConfig.driveRootFolder : name.trim();
    final folder = await drive.ensureFolder('root', cleaned);
    await prefs.setDriveRoot(folder.id, folder.name);
    return folder;
  }

  /// Uses a folder that the app can already see (created by VoxelOps) as the storage root.
  Future<void> chooseStorageRoot(DriveFile folder) async {
    if (!folder.isFolder) {
      throw const AppException(AppErrorKind.validation, 'Choose a folder, not a file.');
    }
    await prefs.setDriveRoot(folder.id, folder.name);
  }

  Future<ServerRecord> create(ServerDraft draft, {required ProvisionProgress onProgress}) async {
    _validateDraft(draft);
    onProgress('resolve', 0.05);
    final build = draft.build ?? await versions.resolve(draft.software, draft.minecraftVersion);
    final user = await github.currentUser();
    final refresh = await store.read(SecureKeys.googleRefreshToken);
    if (refresh == null || refresh.isEmpty) {
      throw const AppException(AppErrorKind.notConfigured, 'Connect Google Drive before creating a server.');
    }

    onProgress('drive', 0.15);
    final rootId = await storageRootId() ?? (throw const AppException(AppErrorKind.server, 'Server storage is not ready.'));
    final folderName = await _uniqueFolderName(rootId, draft.name.trim());
    final serverFolder = await drive.createFolder(rootId, folderName);
    final tree = await _createServerTree(serverFolder.id);

    final id = _newId();
    final now = DateTime.now();
    var record = ServerRecord(
      id: id,
      name: draft.name.trim(),
      description: draft.description.trim(),
      software: draft.software,
      minecraftVersion: build.minecraftVersion,
      loaderVersion: build.loaderVersion,
      javaMajor: build.javaMajor,
      driveFolderId: serverFolder.id,
      repoOwner: '',
      repoName: '',
      createdAt: now,
      tailscaleHostname: null,
      githubAccountLogin: user.login,
    );

    final properties = ServerPropertiesFile.withDefaults(levelName: DriveLayout.world)..applySettings(draft.settings);
    await drive.upsertBytes(
      parentId: serverFolder.id,
      name: DriveLayout.propertiesFile,
      bytes: utf8.encode(properties.toText()),
      mimeType: 'text/plain',
    );
    await drive.upsertBytes(
      parentId: serverFolder.id,
      name: DriveLayout.eulaFile,
      bytes: utf8.encode('# Accepted in VoxelOps on ${now.toUtc().toIso8601String()}\neula=true\n'),
      mimeType: 'text/plain',
    );
    if (draft.iconBytes != null) {
      await drive.upsertBytes(parentId: serverFolder.id, name: DriveLayout.iconFile, bytes: draft.iconBytes!, mimeType: 'image/png');
    }
    await drive.upsertBytes(
      parentId: serverFolder.id,
      name: DriveLayout.readmeFile,
      bytes: utf8.encode(_driveReadme(record.name)),
      mimeType: 'text/plain',
    );
    await drive.upsertBytes(
      parentId: tree.control,
      name: DriveLayout.runtimeFile,
      bytes: utf8.encode(JsonEncoder.withIndent('  ').convert(draft.runtime.toJson())),
      mimeType: 'application/json',
    );
    await drive.upsertBytes(
      parentId: tree.control,
      name: DriveLayout.statusFile,
      bytes: utf8.encode(jsonEncode(_offlineStatus())),
      mimeType: 'application/json',
    );
    // Written before GitHub is touched, so the server can be recovered even if a later step fails.
    await _writeMetadata(record);

    onProgress('github', 0.4);
    final repoName = draft.repoName.trim();
    if (!_repoNamePattern.hasMatch(repoName)) {
      throw const AppException(AppErrorKind.validation, 'Repository name may contain only letters, digits, dots, dashes and underscores.');
    }
    final GitHubRepo repo;
    if (draft.createRepository) {
      repo = await github.createRepository(
        name: repoName,
        isPrivate: draft.repoPrivate,
        description: 'VoxelOps Minecraft server: ${record.name}',
      );
    } else {
      repo = await github.getRepository(draft.repoOwner, repoName);
    }
    record = record.copyWith(repoOwner: repo.owner, repoName: repo.name);

    onProgress('workflow', 0.6);
    final tailscaleEnabled = prefs.tailscaleConnected;
    await _writeRepositoryFiles(record, runtime: draft.runtime, branch: repo.defaultBranch, tailscaleEnabled: tailscaleEnabled);

    onProgress('secrets', 0.8);
    await _writeSecrets(record, tailscaleEnabled: tailscaleEnabled);
    await _writeMetadata(record);

    final existing = prefs.servers().where((s) => s.id != record.id).toList();
    await prefs.saveServers([...existing, record]);
    await prefs.setActiveServerId(record.id);

    if (draft.startAfterCreate) {
      onProgress('start', 0.95);
      await github.dispatchServerWorkflow(owner: repo.owner, repo: repo.name, ref: repo.defaultBranch);
    }
    onProgress('done', 1);
    return record;
  }

  /// Lists every server folder under the storage root that carries VoxelOps metadata.
  Future<List<DiscoveredServer>> discover() async {
    final rootId = await storageRootId(create: false);
    if (rootId == null) {
      return const <DiscoveredServer>[];
    }
    final folders = (await drive.listChildren(rootId)).where((f) => f.isFolder).toList();
    final result = <DiscoveredServer>[];
    for (final folder in folders) {
      final metadataFile = await drive.findChild(folder.id, DriveLayout.metadataFile);
      if (metadataFile == null) {
        continue;
      }
      try {
        final json = _decodeObject(await drive.downloadText(metadataFile.id));
        final repoFull = json['githubRepo'] as String? ?? '';
        final parts = repoFull.split('/');
        final record = ServerRecord.fromDriveMetadata(
          json,
          driveFolderId: folder.id,
          repoOwner: parts.isNotEmpty ? parts.first : '',
          repoName: parts.length > 1 ? parts[1] : '',
        );
        result.add(DiscoveredServer(folderId: folder.id, folderName: folder.name, record: record));
      } on AppException {
        continue;
      } on FormatException {
        continue;
      }
    }
    return result;
  }

  /// Attaches a Drive server to a repository: a new account, a new repository, or a repaired workflow.
  /// When [createRepository] is true the repository is created when it does not exist yet.
  Future<ServerRecord> attachToRepository({
    required String driveFolderId,
    required String repoOwner,
    required String repoName,
    bool createRepository = false,
    bool repoPrivate = true,
  }) async {
    final metadataFile = await drive.findChild(driveFolderId, DriveLayout.metadataFile);
    if (metadataFile == null) {
      throw const AppException(AppErrorKind.notFound, 'This Drive folder does not contain VoxelOps metadata.');
    }
    final json = _decodeObject(await drive.downloadText(metadataFile.id));
    final user = await github.currentUser();
    // Never reuses an existing repository silently: writing a workflow into the wrong repo is destructive.
    final GitHubRepo repo = createRepository
        ? await github.createRepository(
            name: repoName,
            isPrivate: repoPrivate,
            description: 'VoxelOps Minecraft server: ${json['name'] ?? ''}',
          )
        : await github.getRepository(repoOwner, repoName);
    var record = ServerRecord.fromDriveMetadata(
      json,
      driveFolderId: driveFolderId,
      repoOwner: repo.owner,
      repoName: repo.name,
      githubAccountLogin: user.login,
    );
    final runtime = await _readRuntime(driveFolderId);
    await _writeRepositoryFiles(record, runtime: runtime, branch: repo.defaultBranch, tailscaleEnabled: prefs.tailscaleConnected);
    await _writeSecrets(record, tailscaleEnabled: prefs.tailscaleConnected);
    await _writeMetadata(record);
    final others = prefs.servers().where((s) => s.id != record.id).toList();
    await prefs.saveServers([...others, record]);
    return record;
  }

  /// Re-renders the workflow and refreshes secrets after a settings change (for example, Tailscale).
  Future<void> refreshRepository(ServerRecord record) async {
    final repo = await github.getRepository(record.repoOwner, record.repoName);
    final runtime = await _readRuntime(record.driveFolderId);
    await _writeRepositoryFiles(record, runtime: runtime, branch: repo.defaultBranch, tailscaleEnabled: prefs.tailscaleConnected);
    await _writeSecrets(record, tailscaleEnabled: prefs.tailscaleConnected);
  }

  /// Creates the per-server folder tree. Returns the ids the rest of the provisioning needs.
  Future<_ServerTree> _createServerTree(String serverFolderId) async {
    final ids = <String, String>{};
    for (final name in DriveLayout.topFolders) {
      ids[name] = (await drive.createFolder(serverFolderId, name)).id;
    }
    final system = await drive.createFolder(serverFolderId, DriveLayout.system);
    final control = await drive.createFolder(system.id, DriveLayout.control);
    final commands = await drive.createFolder(control.id, DriveLayout.commands);
    final logs = await drive.createFolder(system.id, DriveLayout.logs);
    final imports = await drive.createFolder(system.id, DriveLayout.imports);
    return _ServerTree(
      topFolders: ids,
      system: system.id,
      control: control.id,
      commands: commands.id,
      logs: logs.id,
      imports: imports.id,
    );
  }

  Future<RuntimeSettings> _readRuntime(String driveFolderId) async {
    final control = await _controlFolderId(driveFolderId);
    if (control == null) {
      return const RuntimeSettings();
    }
    final file = await drive.findChild(control, DriveLayout.runtimeFile);
    if (file == null) {
      return const RuntimeSettings();
    }
    try {
      return RuntimeSettings.fromJson(_decodeObject(await drive.downloadText(file.id)));
    } on AppException {
      return const RuntimeSettings();
    } on FormatException {
      return const RuntimeSettings();
    }
  }

  Future<String?> _controlFolderId(String driveFolderId) async {
    final system = await drive.findChild(driveFolderId, DriveLayout.system, mimeType: DriveApi.folderMime);
    if (system == null) {
      return null;
    }
    final control = await drive.findChild(system.id, DriveLayout.control, mimeType: DriveApi.folderMime);
    return control?.id;
  }

  Future<void> _writeRepositoryFiles(
    ServerRecord record, {
    required RuntimeSettings runtime,
    required String branch,
    required bool tailscaleEnabled,
  }) async {
    final workflow = WorkflowTemplate.render(record: record, runtime: runtime, tailscaleEnabled: tailscaleEnabled);
    final runner = await runnerSource();
    await _upsert(record, '.github/workflows/${AppConfig.workflowFileName}', workflow, branch, 'VoxelOps: update server workflow');
    await _upsert(record, AppConfig.runnerRepoPath, runner, branch, 'VoxelOps: update runner');
    await _upsert(record, '.voxelops/README.md', _repoReadme(record), branch, 'VoxelOps: document server repository');
  }

  Future<void> _upsert(ServerRecord record, String path, String content, String branch, String message) async {
    final existing = await github.readTextFile(record.repoOwner, record.repoName, path, ref: branch);
    if (existing != null && existing.text == content) {
      return;
    }
    await github.writeFile(
      owner: record.repoOwner,
      repo: record.repoName,
      path: path,
      bytes: utf8.encode(content),
      message: message,
      branch: branch,
      sha: existing?.sha,
    );
  }

  Future<void> _writeSecrets(ServerRecord record, {required bool tailscaleEnabled}) async {
    final refresh = await store.read(SecureKeys.googleRefreshToken);
    if (refresh == null || refresh.isEmpty) {
      throw const AppException(AppErrorKind.notConfigured, 'Google Drive is not connected.');
    }
    final key = await github.actionsPublicKey(record.repoOwner, record.repoName);
    Future<void> put(String name, String value) async {
      await github.putActionsSecret(
        owner: record.repoOwner,
        repo: record.repoName,
        name: name,
        keyId: key.keyId,
        encryptedValue: encryptForGitHubSecret(base64PublicKey: key.key, plaintext: value),
      );
    }

    await put('VOXEL_DRIVE_FOLDER_ID', record.driveFolderId);
    await put('GDRIVE_CLIENT_ID', AppConfig.googleClientId);
    await put('GDRIVE_REFRESH_TOKEN', refresh);
    if (tailscaleEnabled) {
      final clientId = await store.read(SecureKeys.tailscaleClientId);
      final secret = await store.read(SecureKeys.tailscaleClientSecret);
      if (clientId != null && secret != null) {
        await put('TS_OAUTH_CLIENT_ID', clientId);
        await put('TS_OAUTH_SECRET', secret);
      }
    }
  }

  Future<void> _writeMetadata(ServerRecord record) async {
    final bytes = utf8.encode(JsonEncoder.withIndent('  ').convert(record.toDriveMetadata()));
    await drive.upsertBytes(
      parentId: record.driveFolderId,
      name: DriveLayout.metadataFile,
      bytes: bytes,
      mimeType: 'application/json',
    );
  }

  Future<String> _uniqueFolderName(String rootId, String base) async {
    var candidate = base;
    var counter = 2;
    while (await drive.findChild(rootId, candidate, mimeType: DriveApi.folderMime) != null) {
      candidate = '$base ($counter)';
      counter++;
    }
    return candidate;
  }

  static void _validateDraft(ServerDraft draft) {
    final name = draft.name.trim();
    if (name.length < 3 || name.length > 40) {
      throw const AppException(AppErrorKind.validation, 'Server name must be between 3 and 40 characters.');
    }
    if (draft.minecraftVersion.isEmpty && draft.build == null) {
      throw const AppException(AppErrorKind.validation, 'Choose a Minecraft version.');
    }
    if (!draft.eulaAccepted) {
      throw const AppException(AppErrorKind.validation, 'You must accept the Minecraft EULA to continue.');
    }
    if (!draft.githubRiskAccepted) {
      throw const AppException(AppErrorKind.validation, 'Acknowledge the GitHub Actions usage terms to continue.');
    }
    if (draft.settings.maxPlayers < 1 || draft.settings.maxPlayers > 500) {
      throw const AppException(AppErrorKind.validation, 'Max players must be between 1 and 500.');
    }
  }

  static Map<String, dynamic> _decodeObject(String text) {
    final Object? decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const AppException(AppErrorKind.server, 'Drive metadata is not a JSON object.');
  }

  static Map<String, Object?> _offlineStatus() => {
        'state': 'offline',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'players': 0,
        'maxPlayers': 0,
        'syncState': 'idle',
      };

  static String _newId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(36);
    final rnd = (DateTime.now().microsecond * 7919 + now.length).toRadixString(36);
    return 'srv-$now-$rnd';
  }

  static String _driveReadme(String name) => '''
VoxelOps server: $name

This folder is managed by the VoxelOps app and the GitHub Actions runner.
- server.properties, mods/, plugins/ and config/ take effect on the next start.
- world/, world_nether/ and world_the_end/ are saved by the runner during a run and before every stop.
- backups/ contains zip archives. They can be restored from the app.
- _voxelops/ is the system folder: control/ (commands and status), logs/ and imports/.
  Do not delete it while the server is in use.

Recovery: install VoxelOps, sign in with the same Google account, and choose
"Import existing server" to reconnect this folder to a GitHub repository.
''';

  static String _repoReadme(ServerRecord record) => '''
# ${record.name}

This repository runs a Minecraft server with VoxelOps on GitHub-hosted runners.

- Workflow: .github/workflows/${AppConfig.workflowFileName}
- Runner: ${AppConfig.runnerRepoPath}
- World, configuration and backups are stored in Google Drive (${AppConfig.driveRootFolder}/${record.name}).
- Secrets (Drive folder ID, Drive refresh token, optional Tailscale OAuth) are stored as Actions secrets.
- Minecraft version: ${record.minecraftVersion} (${record.software.label}).

Do not commit world data to this repository.
''';
}

class _ServerTree {
  const _ServerTree({
    required this.topFolders,
    required this.system,
    required this.control,
    required this.commands,
    required this.logs,
    required this.imports,
  });

  final Map<String, String> topFolders;
  final String system;
  final String control;
  final String commands;
  final String logs;
  final String imports;
}

ServerRecord? findServer(List<ServerRecord> servers, String id) {
  for (final server in servers) {
    if (server.id == id) {
      return server;
    }
  }
  return null;
}
