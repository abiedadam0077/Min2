import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/errors/app_exception.dart';
import '../../core/net/api_client.dart';
import '../../domain/integration_models.dart';

/// Returns a bearer token. With forceRefresh the stored refresh token is used even if the cached token looks valid.
typedef DriveAccessToken = Future<String> Function({bool forceRefresh});

/// Google Drive v3 client. Works on files and folders created by this app (drive.file scope).
///
/// Every request goes through [_send]: when Drive answers 401 the access token is refreshed once and the
/// request is repeated, so an expired access token never reaches the user as an error.
class DriveApi {
  DriveApi(this._api, this._accessToken);

  static const String _base = 'https://www.googleapis.com/drive/v3';
  static const String _uploadBase = 'https://www.googleapis.com/upload/drive/v3';
  static const String _provider = 'Google Drive';
  static const String folderMime = 'application/vnd.google-apps.folder';
  static const String _fileFields = 'id,name,mimeType,size,modifiedTime,md5Checksum,parents,trashed';
  static const int multipartLimit = 4 * 1024 * 1024;
  static const int chunkSize = 8 * 1024 * 1024;

  final ApiClient _api;
  final DriveAccessToken _accessToken;

  static String escapeQuery(String value) => value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
    int maxRetries = 2,
  }) async {
    Future<http.Response> attempt(String token) => _api.send(
          method,
          uri,
          headers: {...?headers, 'Authorization': 'Bearer $token'},
          body: body,
          timeout: timeout,
          maxRetries: maxRetries,
        );
    final first = await attempt(await _accessToken());
    if (first.statusCode != 401) {
      return first;
    }
    return attempt(await _accessToken(forceRefresh: true));
  }

  Future<DriveQuota> about() async {
    final response = await _send(
      'GET',
      Uri.parse('$_base/about').replace(queryParameters: {'fields': 'user(displayName,emailAddress),storageQuota(limit,usage)'}),
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    final json = ApiClient.decodeObject(response, provider: _provider);
    final user = json['user'];
    final quota = json['storageQuota'];
    final quotaMap = quota is Map<String, dynamic> ? quota : const <String, dynamic>{};
    return DriveQuota(
      email: user is Map<String, dynamic> ? user['emailAddress'] as String? : null,
      displayName: user is Map<String, dynamic> ? user['displayName'] as String? : null,
      usedBytes: int.tryParse('${quotaMap['usage'] ?? 0}') ?? 0,
      limitBytes: int.tryParse('${quotaMap['limit'] ?? ''}'),
    );
  }

  Future<List<DriveFile>> listChildren(String folderId) async {
    final files = <DriveFile>[];
    String? pageToken;
    do {
      final response = await _send(
        'GET',
        Uri.parse('$_base/files').replace(queryParameters: {
          'q': "'${escapeQuery(folderId)}' in parents and trashed = false",
          'fields': 'nextPageToken,files($_fileFields)',
          'pageSize': '1000',
          'orderBy': 'folder,name',
          if (pageToken != null) 'pageToken': pageToken,
        }),
      );
      ApiClient.ensureSuccess(response, provider: _provider);
      final json = ApiClient.decodeObject(response, provider: _provider);
      final items = json['files'];
      if (items is List<dynamic>) {
        files.addAll(items.whereType<Map<String, dynamic>>().map(DriveFile.fromJson));
      }
      pageToken = json['nextPageToken'] as String?;
    } while (pageToken != null);
    return files;
  }

  /// Folders this app can see (created by VoxelOps). Used by the Server Storage picker.
  Future<List<DriveFile>> listFolders() async {
    final response = await _send(
      'GET',
      Uri.parse('$_base/files').replace(queryParameters: {
        'q': "mimeType = '$folderMime' and trashed = false",
        'fields': 'files($_fileFields)',
        'pageSize': '100',
        'orderBy': 'name',
      }),
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    final items = ApiClient.decodeObject(response, provider: _provider)['files'];
    if (items is! List<dynamic>) {
      return const <DriveFile>[];
    }
    return items.whereType<Map<String, dynamic>>().map(DriveFile.fromJson).toList();
  }

  Future<DriveFile?> findChild(String parentId, String name, {String? mimeType}) async {
    final clauses = <String>[
      "'${escapeQuery(parentId)}' in parents",
      "name = '${escapeQuery(name)}'",
      'trashed = false',
      if (mimeType != null) "mimeType = '${escapeQuery(mimeType)}'",
    ];
    final response = await _send(
      'GET',
      Uri.parse('$_base/files').replace(queryParameters: {
        'q': clauses.join(' and '),
        'fields': 'files($_fileFields)',
        'pageSize': '10',
      }),
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    final items = ApiClient.decodeObject(response, provider: _provider)['files'];
    if (items is List<dynamic> && items.isNotEmpty && items.first is Map<String, dynamic>) {
      return DriveFile.fromJson(items.first as Map<String, dynamic>);
    }
    return null;
  }

  Future<DriveFile> getFile(String fileId) async {
    final response = await _send(
      'GET',
      Uri.parse('$_base/files/$fileId').replace(queryParameters: {'fields': _fileFields}),
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    return DriveFile.fromJson(ApiClient.decodeObject(response, provider: _provider));
  }

  Future<DriveFile> ensureFolder(String parentId, String name) async {
    final existing = await findChild(parentId, name, mimeType: folderMime);
    if (existing != null) {
      return existing;
    }
    return createFolder(parentId, name);
  }

  Future<DriveFile> createFolder(String parentId, String name) async {
    final response = await _send(
      'POST',
      Uri.parse('$_base/files').replace(queryParameters: {'fields': _fileFields}),
      body: <String, Object?>{
        'name': name,
        'mimeType': folderMime,
        'parents': <String>[parentId],
      },
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    return DriveFile.fromJson(ApiClient.decodeObject(response, provider: _provider));
  }

  Future<Uint8List> download(String fileId) async {
    final response = await _send(
      'GET',
      Uri.parse('$_base/files/$fileId').replace(queryParameters: {'alt': 'media'}),
      timeout: const Duration(minutes: 3),
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    return response.bodyBytes;
  }

  Future<String> downloadText(String fileId) async {
    final bytes = await download(fileId);
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Creates [name] inside [parentId], or replaces the content when a file with that name exists.
  Future<DriveFile> upsertBytes({
    required String parentId,
    required String name,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final existing = await findChild(parentId, name);
    if (existing != null && !existing.isFolder) {
      return updateContent(existing.id, bytes, mimeType: mimeType);
    }
    return createFile(parentId: parentId, name: name, bytes: bytes, mimeType: mimeType);
  }

  Future<DriveFile> createFile({
    required String parentId,
    required String name,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (data.length > multipartLimit) {
      return _resumable(
        method: 'POST',
        url: Uri.parse('$_uploadBase/files').replace(queryParameters: {'uploadType': 'resumable', 'fields': _fileFields}),
        metadata: {'name': name, 'parents': <String>[parentId], 'mimeType': mimeType},
        mimeType: mimeType,
        total: data.length,
        readChunk: (start, end) async => Uint8List.sublistView(data, start, end),
      );
    }
    final boundary = 'voxelops${DateTime.now().microsecondsSinceEpoch}';
    final body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n'))
      ..add(utf8.encode(jsonEncode({'name': name, 'parents': <String>[parentId], 'mimeType': mimeType})))
      ..add(utf8.encode('\r\n--$boundary\r\nContent-Type: $mimeType\r\n\r\n'))
      ..add(data)
      ..add(utf8.encode('\r\n--$boundary--'));
    final response = await _send(
      'POST',
      Uri.parse('$_uploadBase/files').replace(queryParameters: {'uploadType': 'multipart', 'fields': _fileFields}),
      headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
      body: body.takeBytes(),
      timeout: const Duration(minutes: 2),
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    return DriveFile.fromJson(ApiClient.decodeObject(response, provider: _provider));
  }

  Future<DriveFile> updateContent(String fileId, List<int> bytes, {required String mimeType}) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (data.length > multipartLimit) {
      return _resumable(
        method: 'PATCH',
        url: Uri.parse('$_uploadBase/files/$fileId').replace(queryParameters: {'uploadType': 'resumable', 'fields': _fileFields}),
        metadata: null,
        mimeType: mimeType,
        total: data.length,
        readChunk: (start, end) async => Uint8List.sublistView(data, start, end),
      );
    }
    final response = await _send(
      'PATCH',
      Uri.parse('$_uploadBase/files/$fileId').replace(queryParameters: {'uploadType': 'media', 'fields': _fileFields}),
      headers: {'Content-Type': mimeType},
      body: data,
      timeout: const Duration(minutes: 2),
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    return DriveFile.fromJson(ApiClient.decodeObject(response, provider: _provider));
  }

  /// Uploads a local file in 8 MiB chunks so large worlds never sit fully in memory.
  Future<DriveFile> uploadLocalFile({
    required String parentId,
    required String name,
    required File file,
    required String mimeType,
  }) async {
    final total = await file.length();
    final raf = await file.open();
    try {
      return await _resumable(
        method: 'POST',
        url: Uri.parse('$_uploadBase/files').replace(queryParameters: {'uploadType': 'resumable', 'fields': _fileFields}),
        metadata: {'name': name, 'parents': <String>[parentId], 'mimeType': mimeType},
        mimeType: mimeType,
        total: total,
        readChunk: (start, end) async {
          await raf.setPosition(start);
          return raf.read(end - start);
        },
      );
    } finally {
      await raf.close();
    }
  }

  /// Resumable protocol: start a session, then send Content-Range chunks. Google answers 308 until the
  /// last byte arrives. Each chunk is retried on transient failures and verified by the final response.
  Future<DriveFile> _resumable({
    required String method,
    required Uri url,
    required Map<String, Object?>? metadata,
    required String mimeType,
    required int total,
    required Future<Uint8List> Function(int start, int end) readChunk,
  }) async {
    final start = await _send(
      method,
      url,
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': mimeType,
        'X-Upload-Content-Length': '$total',
      },
      body: metadata ?? <String, Object?>{},
      timeout: const Duration(seconds: 60),
    );
    ApiClient.ensureSuccess(start, provider: _provider);
    final location = start.headers['location'];
    if (location == null || location.isEmpty) {
      throw const AppException(AppErrorKind.server, 'Google Drive did not return an upload session.');
    }
    if (total == 0) {
      final empty = await _api.send(
        'PUT',
        Uri.parse(location),
        headers: {'Content-Length': '0', 'Content-Range': 'bytes */0'},
        body: const <int>[],
        timeout: const Duration(minutes: 2),
      );
      ApiClient.ensureSuccess(empty, provider: _provider);
      return DriveFile.fromJson(ApiClient.decodeObject(empty, provider: _provider));
    }
    var offset = 0;
    while (offset < total) {
      final end = (offset + chunkSize < total) ? offset + chunkSize : total;
      final chunk = await readChunk(offset, end);
      final response = await _api.send(
        'PUT',
        Uri.parse(location),
        headers: {'Content-Range': 'bytes $offset-${end - 1}/$total', 'Content-Type': mimeType},
        body: chunk,
        timeout: const Duration(minutes: 3),
        maxRetries: 3,
      );
      if (response.statusCode == 308) {
        final received = response.headers['range'];
        offset = received == null ? end : (int.tryParse(received.split('-').last) ?? (end - 1)) + 1;
        continue;
      }
      ApiClient.ensureSuccess(response, provider: _provider);
      return DriveFile.fromJson(ApiClient.decodeObject(response, provider: _provider));
    }
    throw const AppException(AppErrorKind.server, 'The upload finished without a file response.');
  }

  Future<void> rename(String fileId, String newName) async {
    final response = await _send(
      'PATCH',
      Uri.parse('$_base/files/$fileId').replace(queryParameters: {'fields': _fileFields}),
      body: <String, Object?>{'name': newName},
    );
    ApiClient.ensureSuccess(response, provider: _provider);
  }

  /// Moves a file to Drive trash, where it stays recoverable for 30 days.
  Future<void> trash(String fileId) async {
    final response = await _send(
      'PATCH',
      Uri.parse('$_base/files/$fileId').replace(queryParameters: {'fields': 'id'}),
      body: <String, Object?>{'trashed': true},
    );
    ApiClient.ensureSuccess(response, provider: _provider);
  }
}
