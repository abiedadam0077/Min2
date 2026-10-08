import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/errors/app_exception.dart';
import '../../core/net/api_client.dart';
import '../../domain/integration_models.dart';
import '../../domain/server_models.dart';
import '../github/github_api.dart';
import '../google/drive_api.dart';
import '../minecraft/server_properties.dart';
import 'drive_layout.dart';

/// Everything the app does with a running or stopped server. Control actions are written as
/// command files that the runner consumes; reads (status, console, files) go straight to Drive.
class ServerActions {
  ServerActions({required this.github, required this.drive, required this.api});

  final GitHubApi github;
  final DriveApi drive;
  final ApiClient api;

  final Map<String, String> _folderIds = <String, String>{};
  final Map<String, String> _fileIds = <String, String>{};
  final Random _random = Random.secure();

  Future<String> _folder(String parentId, String name) async {
    final key = '$parentId/$name';
    final cached = _folderIds[key];
    if (cached != null) {
      return cached;
    }
    final folder = await drive.ensureFolder(parentId, name);
    _folderIds[key] = folder.id;
    return folder.id;
  }

  /// <server>/_voxelops : system folder (control queue, status, logs, imports).
  Future<String> systemFolder(ServerRecord record) => _folder(record.driveFolderId, DriveLayout.system);

  Future<String> controlFolder(ServerRecord record) async => _folder(await systemFolder(record), DriveLayout.control);

  Future<String?> _cachedFileId(String parentId, String name) async {
    final key = 'file:$parentId/$name';
    final cached = _fileIds[key];
    if (cached != null) {
      return cached;
    }
    final file = await drive.findChild(parentId, name);
    if (file != null) {
      _fileIds[key] = file.id;
    }
    return file?.id;
  }

  Future<String?> _readOptionalText(String parentId, String name) async {
    final id = await _cachedFileId(parentId, name);
    if (id == null) {
      return null;
    }
    try {
      return await drive.downloadText(id);
    } on AppException catch (error) {
      if (error.kind == AppErrorKind.notFound) {
        _fileIds.remove('file:$parentId/$name');
        return null;
      }
      rethrow;
    }
  }

  /// Latest status written by the runner. Returns an offline status when nothing was written yet.
  Future<ServerStatus> readStatus(ServerRecord record) async {
    final control = await controlFolder(record);
    final text = await _readOptionalText(control, DriveLayout.statusFile);
    if (text == null) {
      return ServerStatus.offline();
    }
    try {
      return ServerStatus.fromJson(_decode(text));
    } on FormatException {
      return ServerStatus.offline();
    }
  }

  /// Tail of the console written by the runner (most recent lines last).
  Future<List<String>> readConsole(ServerRecord record, {int maxLines = 400}) async {
    final control = await controlFolder(record);
    final text = await _readOptionalText(control, DriveLayout.liveLogFile);
    if (text == null || text.isEmpty) {
      return const <String>[];
    }
    final lines = const LineSplitter().convert(text);
    return lines.length <= maxLines ? lines : lines.sublist(lines.length - maxLines);
  }

  /// Queues a command for the runner. Commands are processed in order by file name.
  Future<void> sendCommand(ServerRecord record, String type, {Map<String, Object?> payload = const <String, Object?>{}}) async {
    final control = await controlFolder(record);
    final commands = await _folder(control, DriveLayout.commands);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final suffix = List<int>.generate(4, (_) => _random.nextInt(36)).map((v) => v.toRadixString(36)).join();
    final name = '$stamp-$suffix.json';
    final body = <String, Object?>{
      'type': type,
      'requestedAt': DateTime.now().toUtc().toIso8601String(),
      'payload': payload,
    };
    await drive.createFile(
      parentId: commands,
      name: name,
      bytes: utf8.encode(jsonEncode(body)),
      mimeType: 'application/json',
    );
  }

  Future<void> startServer(ServerRecord record) async {
    final repo = await github.getRepository(record.repoOwner, record.repoName);
    await github.dispatchServerWorkflow(owner: record.repoOwner, repo: record.repoName, ref: repo.defaultBranch);
  }

  Future<List<GitHubRun>> recentRuns(ServerRecord record) => github.listRuns(record.repoOwner, record.repoName);

  /// Last resort when the runner does not respond to "kill": cancel the active GitHub run.
  Future<bool> forceCancelActiveRun(ServerRecord record) async {
    final runs = await github.listRuns(record.repoOwner, record.repoName, perPage: 5);
    final active = runs.where((r) => r.isActive).toList();
    if (active.isEmpty) {
      return false;
    }
    await github.cancelRun(record.repoOwner, record.repoName, active.first.id, force: true);
    return true;
  }

  Future<ServerSettings> readSettings(ServerRecord record) async {
    final text = await _readOptionalText(record.driveFolderId, DriveLayout.propertiesFile);
    return text == null ? const ServerSettings() : ServerPropertiesFile.parse(text).toSettings();
  }

  /// Writes settings into server.properties while preserving every other key.
  Future<void> writeSettings(ServerRecord record, ServerSettings settings) async {
    final text = await _readOptionalText(record.driveFolderId, DriveLayout.propertiesFile);
    final properties = text == null ? ServerPropertiesFile.withDefaults() : ServerPropertiesFile.parse(text);
    properties.applySettings(settings);
    await drive.upsertBytes(
      parentId: record.driveFolderId,
      name: DriveLayout.propertiesFile,
      bytes: utf8.encode(properties.toText()),
      mimeType: 'text/plain',
    );
  }

  Future<RuntimeSettings> readRuntime(ServerRecord record) async {
    final control = await controlFolder(record);
    final text = await _readOptionalText(control, DriveLayout.runtimeFile);
    if (text == null) {
      return const RuntimeSettings();
    }
    try {
      return RuntimeSettings.fromJson(_decode(text));
    } on FormatException {
      return const RuntimeSettings();
    }
  }

  Future<void> writeRuntime(ServerRecord record, RuntimeSettings runtime) async {
    final control = await controlFolder(record);
    await drive.upsertBytes(
      parentId: control,
      name: DriveLayout.runtimeFile,
      bytes: utf8.encode(jsonEncode(runtime.toJson())),
      mimeType: 'application/json',
    );
  }

  Future<List<BackupEntry>> listBackups(ServerRecord record) async {
    final folder = await _folder(record.driveFolderId, DriveLayout.backups);
    final files = await drive.listChildren(folder);
    final entries = files.where((f) => !f.isFolder && f.name.endsWith('.zip')).map((f) {
      final kind = f.name.startsWith('manual-')
          ? 'manual'
          : f.name.startsWith('prerestore-')
              ? 'prerestore'
              : f.name.startsWith('import-')
                  ? 'import'
                  : 'auto';
      return BackupEntry(
        fileId: f.id,
        name: f.name,
        kind: kind,
        createdAt: f.modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        sizeBytes: f.sizeBytes ?? 0,
      );
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return entries;
  }

  Future<void> deleteBackup(BackupEntry backup) => drive.trash(backup.fileId);

  Future<void> restoreBackup(ServerRecord record, BackupEntry backup) =>
      sendCommand(record, 'restore', payload: {'fileId': backup.fileId, 'name': backup.name});

  /// Uploads a world archive to imports/ and asks the runner to apply it.
  Future<void> importWorld(ServerRecord record, {required String fileName, required List<int> bytes}) async {
    final folder = await _folder(await systemFolder(record), DriveLayout.imports);
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    final stored = await drive.createFile(
      parentId: folder,
      name: 'import-${DateTime.now().toUtc().millisecondsSinceEpoch}-$safeName',
      bytes: bytes,
      mimeType: 'application/zip',
    );
    await sendCommand(record, 'import', payload: {'fileId': stored.id, 'name': safeName});
  }

  Future<void> createBackup(ServerRecord record) => sendCommand(record, 'backup');

  Future<void> installContent({
    required ServerRecord record,
    required ContentFile file,
    required ContentKind kind,
  }) async {
    if (!file.canDownload) {
      throw const AppException(
        AppErrorKind.forbidden,
        'The publisher does not allow direct downloads. Open the project page to download the file.',
      );
    }
    final bytes = await download(file.downloadUrl!);
    final expectedSha1 = file.sha1;
    if (expectedSha1 != null && expectedSha1.isNotEmpty) {
      final actual = sha1.convert(bytes).toString();
      if (actual != expectedSha1.toLowerCase()) {
        throw const AppException(AppErrorKind.validation, 'The download did not match the published checksum. It was not installed.');
      }
    }
    final folder = await _folder(record.driveFolderId, kind == ContentKind.plugins ? DriveLayout.plugins : DriveLayout.mods);
    await drive.upsertBytes(
      parentId: folder,
      name: file.fileName,
      bytes: bytes,
      mimeType: 'application/java-archive',
    );
  }

  Future<Uint8List> download(String url) async {
    final response = await api.send(
      'GET',
      Uri.parse(url),
      headers: const {'Accept': '*/*'},
      timeout: const Duration(minutes: 3),
    );
    ApiClient.ensureSuccess(response, provider: 'Download');
    return response.bodyBytes;
  }

  Future<List<DriveFile>> listFolder(String folderId) async {
    final files = await drive.listChildren(folderId);
    files.sort((a, b) {
      if (a.isFolder != b.isFolder) {
        return a.isFolder ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return files;
  }

  Future<String> folderFor(ServerRecord record, String name) => _folder(record.driveFolderId, name);

  Future<void> trash(DriveFile file) => drive.trash(file.id);

  Future<void> rename(DriveFile file, String name) => drive.rename(file.id, name);

  Future<Uint8List> downloadFile(DriveFile file) => drive.download(file.id);

  Future<String> readText(DriveFile file) => drive.downloadText(file.id);

  Future<void> saveText(DriveFile file, String text) async {
    await drive.updateContent(file.id, utf8.encode(text), mimeType: file.mimeType);
  }

  Future<DriveFile> uploadBytes({
    required String folderId,
    required String name,
    required List<int> bytes,
    required String mimeType,
  }) =>
      drive.upsertBytes(parentId: folderId, name: name, bytes: bytes, mimeType: mimeType);

  Future<DriveFile> createFolder(String parentId, String name) => drive.createFolder(parentId, name);

  static Map<String, dynamic> _decode(String text) {
    final Object? decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('Expected a JSON object');
  }
}
