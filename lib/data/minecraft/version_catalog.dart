import 'dart:convert';


import '../../core/errors/app_exception.dart';
import '../../core/net/api_client.dart';
import '../../domain/server_models.dart';

/// Pulls version lists and builds from the official sources of each server software.
/// Nothing here is hard-coded: every list is fetched live when the wizard opens.
class VersionCatalog {
  VersionCatalog(this._api);

  final ApiClient _api;
  final Map<ServerSoftware, List<McVersion>> _cache = <ServerSoftware, List<McVersion>>{};
  final Map<String, int> _javaCache = <String, int>{};

  static const String _mojangManifest = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json';
  static const String _fabricGame = 'https://meta.fabricmc.net/v2/versions/game';
  static const String _fabricLoader = 'https://meta.fabricmc.net/v2/versions/loader';
  static const String _fabricInstaller = 'https://meta.fabricmc.net/v2/versions/installer';
  static const String _forgeMaven = 'https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml';
  static const String _neoForgeMaven = 'https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml';
  static const String _paperProject = 'https://fill.papermc.io/v3/projects/paper';
  static const String _purpur = 'https://api.purpurmc.org/v2/purpur';
  static const String _spigotHub = 'https://hub.spigotmc.org/versions/';

  Future<List<McVersion>> versionsFor(ServerSoftware software, {bool refresh = false}) async {
    if (!refresh && _cache.containsKey(software)) {
      return _cache[software]!;
    }
    final list = switch (software) {
      ServerSoftware.vanilla => await _vanilla(),
      ServerSoftware.fabric => await _fabric(),
      ServerSoftware.forge => await _forge(),
      ServerSoftware.neoforge => await _neoForge(),
      ServerSoftware.paper => await _paper(),
      ServerSoftware.purpur => await _purpurVersions(),
      ServerSoftware.spigot => await _spigot(),
    };
    _cache[software] = list;
    return list;
  }

  /// Resolves the newest build for [mcVersion]. Throws when the software has no build for it.
  Future<ResolvedBuild> resolve(ServerSoftware software, String mcVersion) async {
    final javaMajor = await javaMajorFor(mcVersion);
    switch (software) {
      case ServerSoftware.vanilla:
        final server = await _mojangServer(mcVersion);
        return ResolvedBuild(
          minecraftVersion: mcVersion,
          loaderVersion: '',
          javaMajor: javaMajor,
          downloadUrl: server.url,
          sha256: null,
        );
      case ServerSoftware.fabric:
        final loader = await _firstStable(_fabricLoader);
        final installer = await _firstStable(_fabricInstaller);
        return ResolvedBuild(
          minecraftVersion: mcVersion,
          loaderVersion: '$loader|$installer',
          javaMajor: javaMajor,
          downloadUrl: 'https://meta.fabricmc.net/v2/versions/loader/$mcVersion/$loader/$installer/server/jar',
        );
      case ServerSoftware.forge:
        final versions = await _mavenVersions(_forgeMaven);
        final match = versions.lastWhere(
          (v) => v.startsWith('$mcVersion-'),
          orElse: () => throw AppException(AppErrorKind.notFound, 'No Forge build exists for $mcVersion.'),
        );
        return ResolvedBuild(
          minecraftVersion: mcVersion,
          loaderVersion: match,
          javaMajor: javaMajor,
          downloadUrl: 'https://maven.minecraftforge.net/net/minecraftforge/forge/$match/forge-$match-installer.jar',
        );
      case ServerSoftware.neoforge:
        final versions = await _mavenVersions(_neoForgeMaven);
        final match = versions.lastWhere(
          (v) => _neoForgeMinecraft(v) == mcVersion,
          orElse: () => throw AppException(AppErrorKind.notFound, 'No NeoForge build exists for $mcVersion.'),
        );
        return ResolvedBuild(
          minecraftVersion: mcVersion,
          loaderVersion: match,
          javaMajor: javaMajor,
          downloadUrl: 'https://maven.neoforged.net/releases/net/neoforged/neoforge/$match/neoforge-$match-installer.jar',
        );
      case ServerSoftware.paper:
        final builds = await _getJson('$_paperProject/versions/$mcVersion/builds');
        if (builds is! List<dynamic> || builds.isEmpty) {
          throw AppException(AppErrorKind.notFound, 'Paper has no build for $mcVersion.');
        }
        final maps = builds.whereType<Map<String, dynamic>>().toList();
        final stable = maps.firstWhere(
          (b) => b['channel'] == 'STABLE',
          orElse: () => maps.first,
        );
        final id = stable['id'];
        final downloads = stable['downloads'];
        final server = downloads is Map<String, dynamic> ? downloads['server:default'] : null;
        final url = server is Map<String, dynamic> ? server['url'] as String? : null;
        final checksums = server is Map<String, dynamic> ? server['checksums'] : null;
        final sha = checksums is Map<String, dynamic> ? checksums['sha256'] as String? : null;
        return ResolvedBuild(
          minecraftVersion: mcVersion,
          loaderVersion: '$id',
          javaMajor: javaMajor,
          downloadUrl: url,
          sha256: sha,
          note: stable['channel'] == 'STABLE' ? null : 'Only experimental builds are available.',
        );
      case ServerSoftware.purpur:
        final info = await _getJson('$_purpur/$mcVersion');
        final builds = info is Map<String, dynamic> ? info['builds'] : null;
        final latest = builds is Map<String, dynamic> ? builds['latest'] : null;
        if (latest == null) {
          throw AppException(AppErrorKind.notFound, 'Purpur has no build for $mcVersion.');
        }
        final build = '$latest';
        return ResolvedBuild(
          minecraftVersion: mcVersion,
          loaderVersion: build,
          javaMajor: javaMajor,
          downloadUrl: '$_purpur/$mcVersion/$build/download',
        );
      case ServerSoftware.spigot:
        return ResolvedBuild(
          minecraftVersion: mcVersion,
          loaderVersion: 'buildtools',
          javaMajor: javaMajor,
          note: 'Spigot is compiled from source with BuildTools on the runner (takes several minutes).',
        );
    }
  }

  /// Java major version required by a Minecraft release (from Mojang's version JSON).
  Future<int> javaMajorFor(String mcVersion) async {
    final cached = _javaCache[mcVersion];
    if (cached != null) {
      return cached;
    }
    final details = await _mojangDetails(mcVersion);
    final java = details['javaVersion'];
    final major = java is Map<String, dynamic> && java['majorVersion'] is num ? (java['majorVersion'] as num).toInt() : 8;
    _javaCache[mcVersion] = major;
    return major;
  }

  Future<List<McVersion>> _vanilla() async {
    final manifest = await _getJson(_mojangManifest);
    final versions = manifest is Map<String, dynamic> ? manifest['versions'] : null;
    if (versions is! List<dynamic>) {
      throw const AppException(AppErrorKind.server, 'Mojang returned an unexpected version manifest.');
    }
    return versions.whereType<Map<String, dynamic>>().where((v) => v['type'] == 'release' || v['type'] == 'snapshot').map((v) {
      final isRelease = v['type'] == 'release';
      return McVersion(
        id: v['id'] as String? ?? '',
        channel: isRelease ? 'release' : 'snapshot',
        releasedAt: DateTime.tryParse(v['releaseTime'] as String? ?? '')?.toLocal(),
      );
    }).where((v) => v.id.isNotEmpty).toList();
  }

  Future<List<McVersion>> _fabric() async {
    final list = await _getJson(_fabricGame);
    if (list is! List<dynamic>) {
      return const <McVersion>[];
    }
    return list
        .whereType<Map<String, dynamic>>()
        .map((v) => McVersion(id: v['version'] as String? ?? '', channel: v['stable'] == true ? 'release' : 'snapshot'))
        .where((v) => v.id.isNotEmpty)
        .toList();
  }

  Future<List<McVersion>> _forge() async {
    final versions = await _mavenVersions(_forgeMaven);
    final seen = <String>{};
    final result = <McVersion>[];
    for (final v in versions.reversed) {
      final mc = v.split('-').first;
      if (seen.add(mc)) {
        result.add(McVersion(id: mc, channel: _isPreRelease(mc) ? 'snapshot' : 'release'));
      }
    }
    return result;
  }

  Future<List<McVersion>> _neoForge() async {
    final versions = await _mavenVersions(_neoForgeMaven);
    final seen = <String>{};
    final result = <McVersion>[];
    for (final v in versions.reversed) {
      final mc = _neoForgeMinecraft(v);
      if (mc != null && seen.add(mc)) {
        result.add(McVersion(id: mc, channel: _isPreRelease(mc) ? 'snapshot' : 'release'));
      }
    }
    return result;
  }

  Future<List<McVersion>> _paper() async {
    final project = await _getJson(_paperProject);
    final versions = project is Map<String, dynamic> ? project['versions'] : null;
    if (versions is! Map<String, dynamic>) {
      return const <McVersion>[];
    }
    final result = <McVersion>[];
    for (final group in versions.values) {
      if (group is List<dynamic>) {
        for (final v in group.whereType<String>()) {
          result.add(McVersion(id: v, channel: _isPreRelease(v) ? 'snapshot' : 'release'));
        }
      }
    }
    return result;
  }

  Future<List<McVersion>> _purpurVersions() async {
    final project = await _getJson(_purpur);
    final versions = project is Map<String, dynamic> ? project['versions'] : null;
    if (versions is! List<dynamic>) {
      return const <McVersion>[];
    }
    final list = versions.whereType<String>().toList()..sort(compareMinecraftVersions);
    return list.reversed.map((v) => McVersion(id: v, channel: _isPreRelease(v) ? 'snapshot' : 'release')).toList();
  }

  Future<List<McVersion>> _spigot() async {
    final response = await _api.send('GET', Uri.parse(_spigotHub), maxRetries: 1);
    ApiClient.ensureSuccess(response, provider: 'Spigot');
    final html = utf8.decode(response.bodyBytes);
    final matches = RegExp(r'href="(\d+(?:\.\d+)+)\.json"').allMatches(html).map((m) => m.group(1)!).toSet().toList()
      ..sort(compareMinecraftVersions);
    return matches.reversed.map((v) => McVersion(id: v, channel: 'release')).toList();
  }

  Future<({String url, String sha1})> _mojangServer(String mcVersion) async {
    final details = await _mojangDetails(mcVersion);
    final downloads = details['downloads'];
    final server = downloads is Map<String, dynamic> ? downloads['server'] : null;
    if (server is! Map<String, dynamic> || server['url'] is! String) {
      throw AppException(AppErrorKind.notFound, 'Mojang does not publish a server jar for $mcVersion.');
    }
    return (url: server['url'] as String, sha1: server['sha1'] as String? ?? '');
  }

  Future<Map<String, dynamic>> _mojangDetails(String mcVersion) async {
    final manifest = await _getJson(_mojangManifest);
    final versions = manifest is Map<String, dynamic> ? manifest['versions'] : null;
    String? url;
    if (versions is List<dynamic>) {
      for (final entry in versions.whereType<Map<String, dynamic>>()) {
        if (entry['id'] == mcVersion) {
          url = entry['url'] as String?;
          break;
        }
      }
    }
    if (url == null) {
      throw AppException(AppErrorKind.notFound, 'Minecraft $mcVersion is not in the Mojang manifest.');
    }
    final details = await _getJson(url);
    if (details is! Map<String, dynamic>) {
      throw const AppException(AppErrorKind.server, 'Mojang returned an unexpected version payload.');
    }
    return details;
  }

  Future<String> _firstStable(String url) async {
    final list = await _getJson(url);
    if (list is List<dynamic>) {
      for (final item in list.whereType<Map<String, dynamic>>()) {
        if (item['stable'] == true && item['version'] is String) {
          return item['version'] as String;
        }
      }
    }
    throw AppException(AppErrorKind.notFound, 'No stable build found at $url.');
  }

  Future<List<String>> _mavenVersions(String url) async {
    final response = await _api.send('GET', Uri.parse(url), maxRetries: 1);
    ApiClient.ensureSuccess(response, provider: 'Maven');
    final xml = utf8.decode(response.bodyBytes);
    return RegExp(r'<version>([^<]+)</version>').allMatches(xml).map((m) => m.group(1)!).toList();
  }

  Future<Object?> _getJson(String url) async {
    final response = await _api.send('GET', Uri.parse(url), maxRetries: 2);
    ApiClient.ensureSuccess(response, provider: 'Version source');
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const AppException(AppErrorKind.server, 'A version source returned invalid JSON.');
    }
  }

  static bool _isPreRelease(String version) => RegExp(r'(pre|rc|snapshot|-|w\d)', caseSensitive: false).hasMatch(version);

  /// NeoForge versions look like 21.1.100 (MC 1.21.1) or 26.1.0.2 (new scheme); 1.20.1 builds use "1.20.1-47.1.x".
  static String? _neoForgeMinecraft(String version) {
    if (version.contains('-')) {
      return version.split('-').first;
    }
    final parts = version.split('.');
    if (parts.length < 2) {
      return null;
    }
    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    if (major == null || minor == null) {
      return null;
    }
    if (major >= 26) {
      final patch = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
      return patch > 0 ? '$major.$minor.$patch' : '$major.$minor';
    }
    return minor == 0 ? '1.$major' : '1.$major.$minor';
  }

  /// Orders dotted Minecraft versions numerically (1.9 < 1.10).
  static int compareMinecraftVersions(String a, String b) {
    final pa = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final pb = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) {
        return x.compareTo(y);
      }
    }
    return 0;
  }
}

/// Exposed for unit tests of the NeoForge version mapping.
String? neoForgeMinecraftForTest(String version) => VersionCatalog._neoForgeMinecraft(version);
