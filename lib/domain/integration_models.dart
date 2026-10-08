/// Models for external services. Parsing is tolerant: unknown or missing fields degrade to
/// safe defaults instead of crashing the UI.
library;

String? jsonString(Object? value) => value is String && value.isNotEmpty ? value : null;

int? jsonInt(Object? value) => value is num ? value.toInt() : null;

bool jsonBool(Object? value, {bool fallback = false}) => value is bool ? value : fallback;

DateTime? jsonDate(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

class GitHubUser {
  const GitHubUser({required this.login, required this.name, required this.avatarUrl});

  final String login;
  final String? name;
  final String? avatarUrl;

  static GitHubUser fromJson(Map<String, dynamic> json) => GitHubUser(
        login: jsonString(json['login']) ?? 'unknown',
        name: jsonString(json['name']),
        avatarUrl: jsonString(json['avatar_url']),
      );
}

class GitHubRepo {
  const GitHubRepo({
    required this.owner,
    required this.name,
    required this.isPrivate,
    required this.defaultBranch,
    required this.description,
    required this.canPush,
    required this.updatedAt,
  });

  final String owner;
  final String name;
  final bool isPrivate;
  final String defaultBranch;
  final String? description;
  final bool canPush;
  final DateTime? updatedAt;

  String get fullName => '$owner/$name';

  static GitHubRepo fromJson(Map<String, dynamic> json) {
    final owner = json['owner'];
    final permissions = json['permissions'];
    return GitHubRepo(
      owner: owner is Map<String, dynamic> ? jsonString(owner['login']) ?? '' : '',
      name: jsonString(json['name']) ?? '',
      isPrivate: jsonBool(json['private']),
      defaultBranch: jsonString(json['default_branch']) ?? 'main',
      description: jsonString(json['description']),
      canPush: permissions is Map<String, dynamic> ? jsonBool(permissions['push']) : false,
      updatedAt: jsonDate(json['updated_at']),
    );
  }
}

class GitHubRun {
  const GitHubRun({
    required this.id,
    required this.runNumber,
    required this.status,
    required this.conclusion,
    required this.event,
    required this.createdAt,
    required this.htmlUrl,
    required this.title,
  });

  final int id;
  final int runNumber;

  /// queued | in_progress | completed | waiting | requested | pending
  final String status;

  /// success | failure | cancelled | skipped | timed_out | null while running
  final String? conclusion;
  final String event;
  final DateTime? createdAt;
  final String htmlUrl;
  final String title;

  bool get isActive => status != 'completed';

  static GitHubRun fromJson(Map<String, dynamic> json) => GitHubRun(
        id: jsonInt(json['id']) ?? 0,
        runNumber: jsonInt(json['run_number']) ?? 0,
        status: jsonString(json['status']) ?? 'unknown',
        conclusion: jsonString(json['conclusion']),
        event: jsonString(json['event']) ?? '',
        createdAt: jsonDate(json['created_at']),
        htmlUrl: jsonString(json['html_url']) ?? '',
        title: jsonString(json['display_title']) ?? jsonString(json['name']) ?? 'Workflow run',
      );
}

class DeviceCodeChallenge {
  const DeviceCodeChallenge({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final int expiresIn;
  final int interval;
}

class DriveFile {
  const DriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.md5,
    required this.parents,
  });

  final String id;
  final String name;
  final String mimeType;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? md5;
  final List<String> parents;

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';

  static DriveFile fromJson(Map<String, dynamic> json) {
    final rawParents = json['parents'];
    return DriveFile(
      id: jsonString(json['id']) ?? '',
      name: jsonString(json['name']) ?? '',
      mimeType: jsonString(json['mimeType']) ?? 'application/octet-stream',
      sizeBytes: int.tryParse(jsonString(json['size']) ?? ''),
      modifiedAt: jsonDate(json['modifiedTime']),
      md5: jsonString(json['md5Checksum']),
      parents: rawParents is List<dynamic> ? rawParents.whereType<String>().toList() : const <String>[],
    );
  }
}

class DriveQuota {
  const DriveQuota({required this.email, required this.displayName, required this.usedBytes, required this.limitBytes});

  final String? email;
  final String? displayName;
  final int usedBytes;
  final int? limitBytes;
}

class TailscaleDevice {
  const TailscaleDevice({
    required this.name,
    required this.hostname,
    required this.addresses,
    required this.online,
  });

  final String name;
  final String hostname;
  final List<String> addresses;
  final bool online;

  String? get ipv4 {
    for (final address in addresses) {
      if (!address.contains(':')) {
        return address;
      }
    }
    return null;
  }

  static TailscaleDevice fromJson(Map<String, dynamic> json) {
    final rawAddresses = json['addresses'];
    return TailscaleDevice(
      name: jsonString(json['name']) ?? '',
      hostname: jsonString(json['hostname']) ?? '',
      addresses: rawAddresses is List<dynamic> ? rawAddresses.whereType<String>().toList() : const <String>[],
      online: jsonBool(json['online']),
    );
  }
}

/// A searchable project from Modrinth or CurseForge.
class ContentProject {
  const ContentProject({
    required this.source,
    required this.id,
    required this.slug,
    required this.title,
    required this.author,
    required this.summary,
    required this.iconUrl,
    required this.downloads,
    required this.categories,
    required this.webUrl,
    required this.serverSupported,
  });

  /// "modrinth" or "curseforge"
  final String source;
  final String id;
  final String slug;
  final String title;
  final String author;
  final String summary;
  final String? iconUrl;
  final int downloads;
  final List<String> categories;
  final String webUrl;

  /// false when the project explicitly says it does not run on servers.
  final bool serverSupported;
}

/// One downloadable file of a project, annotated with compatibility for the target server.
class ContentFile {
  const ContentFile({
    required this.source,
    required this.projectId,
    required this.fileId,
    required this.displayName,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.sha1,
    required this.releaseType,
    required this.gameVersions,
    required this.loaders,
    required this.publishedAt,
    required this.compatibility,
    required this.compatibilityNote,
    required this.requiredDependencies,
  });

  final String source;
  final String projectId;
  final String fileId;
  final String displayName;
  final String fileName;
  final String? downloadUrl;
  final int? sizeBytes;
  final String? sha1;

  /// release | beta | alpha
  final String releaseType;
  final List<String> gameVersions;
  final List<String> loaders;
  final DateTime? publishedAt;

  /// compatible | unknown | incompatible
  final String compatibility;
  final String compatibilityNote;

  /// Project IDs that must be installed too (Modrinth) or CurseForge file IDs.
  final List<String> requiredDependencies;

  bool get canDownload => downloadUrl != null && downloadUrl!.isNotEmpty;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isError = false,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isError;
}
