import 'dart:convert';

import '../../core/errors/app_exception.dart';
import '../../core/net/api_client.dart';
import '../../domain/integration_models.dart';
import '../../domain/server_models.dart';

enum ContentSource { all, modrinth, curseforge }

enum ContentSort { relevance, downloads, updated, newest }

/// Immutable search request. Equality is value based so Riverpod can cache results.
class ContentQuery {
  const ContentQuery({
    required this.kind,
    required this.text,
    required this.source,
    required this.sort,
    this.category,
  });

  final ContentKind kind;
  final String text;
  final ContentSource source;
  final ContentSort sort;
  final String? category;

  @override
  bool operator ==(Object other) =>
      other is ContentQuery &&
      other.kind == kind &&
      other.text == text &&
      other.source == source &&
      other.sort == sort &&
      other.category == category;

  @override
  int get hashCode => Object.hash(kind, text, source, sort, category);
}

/// Searches Modrinth and CurseForge and checks each file against the server's Minecraft
/// version and loader. Compatibility is "compatible", "unknown" (cannot be proven) or excluded.
class ContentCatalog {
  ContentCatalog({required this.api, required this.curseForge, required this.curseForgeKeyReader});

  final ApiClient api;
  final CurseForgeApi curseForge;
  final Future<String?> Function() curseForgeKeyReader;

  static const String _modrinthBase = 'https://api.modrinth.com/v2';

  Future<List<ContentProject>> search(ContentQuery query, {required ServerSoftware software, required String minecraftVersion}) async {
    final wantsModrinth = query.source != ContentSource.curseforge && query.kind != ContentKind.none && _modrinthType(query.kind) != null;
    final key = await curseForgeKeyReader();
    final results = <ContentProject>[];
    if (wantsModrinth) {
      results.addAll(await _modrinthSearch(query, software: software, minecraftVersion: minecraftVersion));
    }
    if (key != null && key.isNotEmpty && query.source != ContentSource.modrinth) {
      results.addAll(await curseForge.search(
        apiKey: key,
        query: query,
        software: software,
        minecraftVersion: minecraftVersion,
      ));
    }
    return results;
  }

  Future<List<ContentFile>> filesFor(
    ContentProject project, {
    required ContentKind kind,
    required ServerSoftware software,
    required String minecraftVersion,
  }) async {
    if (project.source == 'modrinth') {
      return _modrinthFiles(project.id, kind: kind, software: software, minecraftVersion: minecraftVersion);
    }
    final key = await curseForgeKeyReader();
    if (key == null || key.isEmpty) {
      throw const AppException(AppErrorKind.notConfigured, 'Add a CurseForge API key in Settings to use CurseForge.');
    }
    return curseForge.files(apiKey: key, modId: project.id, kind: kind, software: software, minecraftVersion: minecraftVersion);
  }

  static String? _modrinthType(ContentKind kind) => switch (kind) {
        ContentKind.mods => 'mod',
        ContentKind.plugins => 'plugin',
        ContentKind.none || ContentKind.worlds => null,
      };

  Future<List<ContentProject>> _modrinthSearch(
    ContentQuery query, {
    required ServerSoftware software,
    required String minecraftVersion,
  }) async {
    final facets = <List<String>>[
      <String>['project_type:${_modrinthType(query.kind)!}'],
      if (software.supportsContent) software.compatibleLoaderTags.map((t) => 'categories:$t').toList(),
      <String>['versions:$minecraftVersion'],
      if (query.category != null && query.category!.isNotEmpty) <String>['categories:${query.category!}'],
    ];
    final index = switch (query.sort) {
      ContentSort.relevance => 'relevance',
      ContentSort.downloads => 'downloads',
      ContentSort.updated => 'updated',
      ContentSort.newest => 'newest',
    };
    final response = await api.send(
      'GET',
      Uri.parse('$_modrinthBase/search').replace(queryParameters: {
        'query': query.text,
        'facets': jsonEncode(facets),
        'index': index,
        'limit': '20',
      }),
    );
    ApiClient.ensureSuccess(response, provider: 'Modrinth');
    final json = ApiClient.decodeObject(response, provider: 'Modrinth');
    final hits = json['hits'];
    if (hits is! List<dynamic>) {
      return const <ContentProject>[];
    }
    return hits.whereType<Map<String, dynamic>>().map((hit) {
      final id = jsonString(hit['project_id']) ?? '';
      final slug = jsonString(hit['slug']) ?? id;
      final categories = hit['categories'];
      return ContentProject(
        source: 'modrinth',
        id: id,
        slug: slug,
        title: jsonString(hit['title']) ?? slug,
        author: jsonString(hit['author']) ?? '',
        summary: jsonString(hit['description']) ?? '',
        iconUrl: jsonString(hit['icon_url']),
        downloads: jsonInt(hit['downloads']) ?? 0,
        categories: categories is List<dynamic> ? categories.whereType<String>().toList() : const <String>[],
        webUrl: 'https://modrinth.com/${_modrinthType(query.kind)}/$slug',
        serverSupported: jsonString(hit['server_side']) != 'unsupported',
      );
    }).where((p) => p.id.isNotEmpty).toList();
  }

  Future<List<ContentFile>> _modrinthFiles(
    String projectId, {
    required ContentKind kind,
    required ServerSoftware software,
    required String minecraftVersion,
  }) async {
    final loaders = software.supportsContent && kind != ContentKind.worlds ? software.compatibleLoaderTags.toList() : const <String>[];
    final response = await api.send(
      'GET',
      Uri.parse('$_modrinthBase/project/$projectId/version').replace(queryParameters: {
        if (loaders.isNotEmpty) 'loaders': jsonEncode(loaders),
        'game_versions': jsonEncode(<String>[minecraftVersion]),
      }),
    );
    ApiClient.ensureSuccess(response, provider: 'Modrinth');
    final list = ApiClient.decodeList(response, provider: 'Modrinth');
    final files = <ContentFile>[];
    for (final item in list.whereType<Map<String, dynamic>>()) {
      final versionLoaders = _strings(item['loaders']);
      final versionGames = _strings(item['game_versions']);
      final fileList = item['files'];
      if (fileList is! List<dynamic> || fileList.isEmpty) {
        continue;
      }
      final candidates = fileList.whereType<Map<String, dynamic>>().toList();
      if (candidates.isEmpty) {
        continue;
      }
      final file = candidates.firstWhere((f) => f['primary'] == true, orElse: () => candidates.first);
      final hashes = file['hashes'];
      final dependencies = item['dependencies'];
      final requiredDeps = dependencies is List<dynamic>
          ? dependencies
              .whereType<Map<String, dynamic>>()
              .where((d) => d['dependency_type'] == 'required' && jsonString(d['project_id']) != null)
              .map((d) => d['project_id'] as String)
              .toList()
          : const <String>[];
      final loaderMatch = kind == ContentKind.worlds || !software.supportsContent || versionLoaders.any(software.compatibleLoaderTags.contains);
      final gameMatch = versionGames.contains(minecraftVersion);
      final compatibility = (loaderMatch && gameMatch) ? 'compatible' : 'unknown';
      files.add(ContentFile(
        source: 'modrinth',
        projectId: projectId,
        fileId: jsonString(item['id']) ?? '',
        displayName: jsonString(item['name']) ?? jsonString(item['version_number']) ?? 'Version',
        fileName: jsonString(file['filename']) ?? 'file.jar',
        downloadUrl: jsonString(file['url']),
        sizeBytes: jsonInt(file['size']),
        sha1: hashes is Map<String, dynamic> ? jsonString(hashes['sha1']) : null,
        releaseType: jsonString(item['version_type']) ?? 'release',
        gameVersions: versionGames,
        loaders: versionLoaders,
        publishedAt: jsonDate(item['date_published']),
        compatibility: compatibility,
        compatibilityNote: compatibility == 'compatible'
            ? 'Matches Minecraft $minecraftVersion${software.supportsContent ? ' and ${software.label}' : ''}.'
            : 'Modrinth did not confirm this exact loader or version.',
        requiredDependencies: requiredDeps,
      ));
    }
    return files;
  }

  static List<String> _strings(Object? value) => value is List<dynamic> ? value.whereType<String>().toList() : const <String>[];
}

/// CurseForge for Studios API v1 (https://docs.curseforge.com). Requires a user-provided key.
class CurseForgeApi {
  CurseForgeApi(this._api);

  final ApiClient _api;

  static const String _base = 'https://api.curseforge.com/v1';
  static const int _gameMinecraft = 432;

  static int classIdFor(ContentKind kind) => switch (kind) {
        ContentKind.mods => 6,
        ContentKind.plugins => 5,
        ContentKind.worlds => 17,
        ContentKind.none => 6,
      };

  Future<List<ContentProject>> search({
    required String apiKey,
    required ContentQuery query,
    required ServerSoftware software,
    required String minecraftVersion,
  }) async {
    final sortField = switch (query.sort) {
      ContentSort.relevance => null,
      ContentSort.downloads => '6',
      ContentSort.updated => '3',
      ContentSort.newest => '11',
    };
    final loaderType = query.kind == ContentKind.mods ? software.curseForgeLoaderType : null;
    final response = await _api.send(
      'GET',
      Uri.parse('$_base/mods/search').replace(queryParameters: {
        'gameId': '$_gameMinecraft',
        'classId': '${classIdFor(query.kind)}',
        if (query.text.isNotEmpty) 'searchFilter': query.text,
        'gameVersion': minecraftVersion,
        if (loaderType != null) 'modLoaderType': '$loaderType',
        if (sortField != null) 'sortField': sortField,
        if (sortField != null) 'sortOrder': 'desc',
        'pageSize': '20',
      }),
      headers: {'x-api-key': apiKey},
    );
    ApiClient.ensureSuccess(response, provider: 'CurseForge');
    final data = ApiClient.decodeObject(response, provider: 'CurseForge')['data'];
    if (data is! List<dynamic>) {
      return const <ContentProject>[];
    }
    return data.whereType<Map<String, dynamic>>().map((mod) {
      final id = '${mod['id'] ?? ''}';
      final logo = mod['logo'];
      final authors = mod['authors'];
      final categories = mod['categories'];
      final links = mod['links'];
      return ContentProject(
        source: 'curseforge',
        id: id,
        slug: jsonString(mod['slug']) ?? id,
        title: jsonString(mod['name']) ?? 'Project $id',
        author: authors is List<dynamic> && authors.isNotEmpty && authors.first is Map<String, dynamic>
            ? jsonString((authors.first as Map<String, dynamic>)['name']) ?? ''
            : '',
        summary: jsonString(mod['summary']) ?? '',
        iconUrl: logo is Map<String, dynamic> ? jsonString(logo['thumbnailUrl']) ?? jsonString(logo['url']) : null,
        downloads: jsonInt(mod['downloadCount']) ?? 0,
        categories: categories is List<dynamic>
            ? categories.whereType<Map<String, dynamic>>().map((c) => jsonString(c['name']) ?? '').where((c) => c.isNotEmpty).toList()
            : const <String>[],
        webUrl: links is Map<String, dynamic> ? jsonString(links['websiteUrl']) ?? 'https://www.curseforge.com/minecraft' : 'https://www.curseforge.com/minecraft',
        serverSupported: true,
      );
    }).where((p) => p.id.isNotEmpty).toList();
  }

  Future<List<ContentFile>> files({
    required String apiKey,
    required String modId,
    required ContentKind kind,
    required ServerSoftware software,
    required String minecraftVersion,
  }) async {
    final loaderType = kind == ContentKind.mods ? software.curseForgeLoaderType : null;
    final response = await _api.send(
      'GET',
      Uri.parse('$_base/mods/$modId/files').replace(queryParameters: {
        'gameVersion': minecraftVersion,
        if (loaderType != null) 'modLoaderType': '$loaderType',
        'pageSize': '30',
      }),
      headers: {'x-api-key': apiKey},
    );
    ApiClient.ensureSuccess(response, provider: 'CurseForge');
    final data = ApiClient.decodeObject(response, provider: 'CurseForge')['data'];
    if (data is! List<dynamic>) {
      return const <ContentFile>[];
    }
    final loaderTags = software.compatibleLoaderTags;
    return data.whereType<Map<String, dynamic>>().map((file) {
      final games = _strings(file['gameVersions']).map((g) => g.toLowerCase()).toList();
      final gameMatch = games.contains(minecraftVersion.toLowerCase());
      final loaderMatch = kind != ContentKind.mods && kind != ContentKind.plugins
          ? true
          : (!software.supportsContent || games.any(loaderTags.contains));
      final hashes = file['hashes'];
      String? sha1;
      if (hashes is List<dynamic>) {
        for (final h in hashes.whereType<Map<String, dynamic>>()) {
          if (h['algo'] == 1) {
            sha1 = jsonString(h['value']);
          }
        }
      }
      final deps = file['dependencies'];
      final requiredDeps = deps is List<dynamic>
          ? deps
              .whereType<Map<String, dynamic>>()
              .where((d) => d['relationType'] == 3)
              .map((d) => '${d['modId'] ?? ''}')
              .where((id) => id.isNotEmpty)
              .toList()
          : const <String>[];
      final compatible = gameMatch && loaderMatch;
      final releaseType = switch (file['releaseType']) {
        2 => 'beta',
        3 => 'alpha',
        _ => 'release',
      };
      return ContentFile(
        source: 'curseforge',
        projectId: modId,
        fileId: '${file['id'] ?? ''}',
        displayName: jsonString(file['displayName']) ?? jsonString(file['fileName']) ?? 'File',
        fileName: jsonString(file['fileName']) ?? 'file.jar',
        downloadUrl: jsonString(file['downloadUrl']),
        sizeBytes: jsonInt(file['fileLength']),
        sha1: sha1,
        releaseType: releaseType,
        gameVersions: _strings(file['gameVersions']),
        loaders: _strings(file['gameVersions']).where((g) => loaderTags.contains(g.toLowerCase())).toList(),
        publishedAt: jsonDate(file['fileDate']),
        compatibility: compatible ? 'compatible' : 'unknown',
        compatibilityNote: compatible
            ? 'CurseForge lists ${software.label} support for Minecraft $minecraftVersion.'
            : 'CurseForge does not list this loader or version explicitly. Verify before installing.',
        requiredDependencies: requiredDeps,
      );
    }).where((f) => f.fileId.isNotEmpty && f.fileId != 'null').toList();
  }

  static List<String> _strings(Object? value) => value is List<dynamic> ? value.whereType<String>().toList() : const <String>[];
}
