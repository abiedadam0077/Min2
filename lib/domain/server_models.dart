/// Server domain model: software catalogue, persisted server record, live status and
/// the Drive-hosted metadata that makes a server recoverable without this phone.
library;

enum ContentKind { none, mods, plugins, worlds }

enum ServerSoftware {
  vanilla('Vanilla', ContentKind.none, '', 'vanilla'),
  fabric('Fabric', ContentKind.mods, 'fabric', 'fabric'),
  forge('Forge', ContentKind.mods, 'forge', 'forge'),
  neoforge('NeoForge', ContentKind.mods, 'neoforge', 'neoforge'),
  paper('Paper', ContentKind.plugins, 'paper', 'paper'),
  purpur('Purpur', ContentKind.plugins, 'purpur', 'purpur'),
  spigot('Spigot', ContentKind.plugins, 'spigot', 'spigot');

  const ServerSoftware(this.label, this.contentKind, this.loaderTag, this.runnerId);

  final String label;
  final ContentKind contentKind;

  /// Loader tag used by Modrinth ("" for vanilla).
  final String loaderTag;

  /// Stable identifier written to metadata.json and read by the runner.
  final String runnerId;

  bool get supportsContent => contentKind != ContentKind.none;

  String get contentFolder => contentKind == ContentKind.plugins ? 'plugins' : 'mods';

  /// Loader tags a content project may declare and still be installed on this server.
  Set<String> get compatibleLoaderTags => switch (this) {
        ServerSoftware.vanilla => const <String>{},
        ServerSoftware.fabric => const <String>{'fabric'},
        ServerSoftware.forge => const <String>{'forge'},
        ServerSoftware.neoforge => const <String>{'neoforge'},
        ServerSoftware.paper => const <String>{'paper', 'spigot', 'bukkit'},
        ServerSoftware.purpur => const <String>{'purpur', 'paper', 'spigot', 'bukkit'},
        ServerSoftware.spigot => const <String>{'spigot', 'bukkit'},
      };

  /// CurseForge modLoaderType enum (1 Forge, 4 Fabric, 6 NeoForge); null when not applicable.
  int? get curseForgeLoaderType => switch (this) {
        ServerSoftware.fabric => 4,
        ServerSoftware.forge => 1,
        ServerSoftware.neoforge => 6,
        _ => null,
      };

  static ServerSoftware fromRunnerId(String id) {
    for (final value in values) {
      if (value.runnerId == id) {
        return value;
      }
    }
    throw ArgumentError.value(id, 'id', 'Unknown server software');
  }
}

/// A concrete, pinned download for one software + Minecraft version pair.
class ResolvedBuild {
  const ResolvedBuild({
    required this.minecraftVersion,
    required this.loaderVersion,
    required this.javaMajor,
    this.downloadUrl,
    this.sha256,
    this.note,
  });

  final String minecraftVersion;

  /// Loader/build identifier stored in ServerRecord.loaderVersion and used by the runner.
  final String loaderVersion;
  final int javaMajor;
  final String? downloadUrl;
  final String? sha256;
  final String? note;
}

class McVersion {
  const McVersion({required this.id, required this.channel, this.releasedAt});

  final String id;

  /// release | snapshot | stable | beta | experimental | dev
  final String channel;
  final DateTime? releasedAt;

  bool get isStable => channel == 'release' || channel == 'stable';

  @override
  bool operator ==(Object other) => other is McVersion && other.id == id && other.channel == channel;

  @override
  int get hashCode => Object.hash(id, channel);
}

/// Subset of server.properties exposed in the wizard and settings screens.
/// Unknown keys are preserved when the file is rewritten (see ServerPropertiesFile).
class ServerSettings {
  const ServerSettings({
    this.motd = 'A VoxelOps server',
    this.maxPlayers = 20,
    this.gamemode = 'survival',
    this.difficulty = 'easy',
    this.onlineMode = true,
    this.pvp = true,
    this.viewDistance = 10,
    this.simulationDistance = 8,
    this.whitelist = false,
    this.spawnProtection = 16,
    this.allowNether = true,
    this.commandBlocks = false,
    this.hardcore = false,
    this.levelSeed = '',
  });

  final String motd;
  final int maxPlayers;
  final String gamemode;
  final String difficulty;
  final bool onlineMode;
  final bool pvp;
  final int viewDistance;
  final int simulationDistance;
  final bool whitelist;
  final int spawnProtection;
  final bool allowNether;
  final bool commandBlocks;
  final bool hardcore;
  final String levelSeed;

  ServerSettings copyWith({
    String? motd,
    int? maxPlayers,
    String? gamemode,
    String? difficulty,
    bool? onlineMode,
    bool? pvp,
    int? viewDistance,
    int? simulationDistance,
    bool? whitelist,
    int? spawnProtection,
    bool? allowNether,
    bool? commandBlocks,
    bool? hardcore,
    String? levelSeed,
  }) {
    return ServerSettings(
      motd: motd ?? this.motd,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      gamemode: gamemode ?? this.gamemode,
      difficulty: difficulty ?? this.difficulty,
      onlineMode: onlineMode ?? this.onlineMode,
      pvp: pvp ?? this.pvp,
      viewDistance: viewDistance ?? this.viewDistance,
      simulationDistance: simulationDistance ?? this.simulationDistance,
      whitelist: whitelist ?? this.whitelist,
      spawnProtection: spawnProtection ?? this.spawnProtection,
      allowNether: allowNether ?? this.allowNether,
      commandBlocks: commandBlocks ?? this.commandBlocks,
      hardcore: hardcore ?? this.hardcore,
      levelSeed: levelSeed ?? this.levelSeed,
    );
  }
}

/// Runtime knobs read by the runner from control/runtime.json. Changing them from the app
/// takes effect on the next sync tick (or the next start).
class RuntimeSettings {
  const RuntimeSettings({
    this.memoryMb = 3072,
    this.syncIntervalMinutes = 10,
    this.backupIntervalMinutes = 180,
    this.backupRetention = 7,
    this.autoContinue = true,
  });

  final int memoryMb;
  final int syncIntervalMinutes;
  final int backupIntervalMinutes;
  final int backupRetention;
  final bool autoContinue;

  RuntimeSettings copyWith({
    int? memoryMb,
    int? syncIntervalMinutes,
    int? backupIntervalMinutes,
    int? backupRetention,
    bool? autoContinue,
  }) {
    return RuntimeSettings(
      memoryMb: memoryMb ?? this.memoryMb,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      backupIntervalMinutes: backupIntervalMinutes ?? this.backupIntervalMinutes,
      backupRetention: backupRetention ?? this.backupRetention,
      autoContinue: autoContinue ?? this.autoContinue,
    );
  }

  Map<String, Object> toJson() => {
        'memoryMb': memoryMb,
        'syncIntervalMinutes': syncIntervalMinutes,
        'backupIntervalMinutes': backupIntervalMinutes,
        'backupRetention': backupRetention,
        'autoContinue': autoContinue,
      };

  static RuntimeSettings fromJson(Map<String, dynamic> json) {
    return RuntimeSettings(
      memoryMb: _int(json['memoryMb'], 3072),
      syncIntervalMinutes: _int(json['syncIntervalMinutes'], 10),
      backupIntervalMinutes: _int(json['backupIntervalMinutes'], 180),
      backupRetention: _int(json['backupRetention'], 7),
      autoContinue: json['autoContinue'] is bool ? json['autoContinue'] as bool : true,
    );
  }
}

/// Persisted in the app (SharedPreferences) and mirrored to Drive metadata.json.
class ServerRecord {
  const ServerRecord({
    required this.id,
    required this.name,
    required this.description,
    required this.software,
    required this.minecraftVersion,
    required this.loaderVersion,
    required this.javaMajor,
    required this.driveFolderId,
    required this.repoOwner,
    required this.repoName,
    required this.createdAt,
    this.tailscaleHostname,
    this.githubAccountLogin,
    this.lastBackupAt,
    this.lastSyncAt,
  });

  final String id;
  final String name;
  final String description;
  final ServerSoftware software;
  final String minecraftVersion;
  final String loaderVersion;
  final int javaMajor;
  final String driveFolderId;
  final String repoOwner;
  final String repoName;
  final DateTime createdAt;
  final String? tailscaleHostname;
  final String? githubAccountLogin;
  final DateTime? lastBackupAt;
  final DateTime? lastSyncAt;

  String get repoFullName => '$repoOwner/$repoName';

  ServerRecord copyWith({
    String? name,
    String? description,
    String? loaderVersion,
    String? tailscaleHostname,
    String? githubAccountLogin,
    DateTime? lastBackupAt,
    DateTime? lastSyncAt,
    String? repoOwner,
    String? repoName,
    String? driveFolderId,
  }) {
    return ServerRecord(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      software: software,
      minecraftVersion: minecraftVersion,
      loaderVersion: loaderVersion ?? this.loaderVersion,
      javaMajor: javaMajor,
      driveFolderId: driveFolderId ?? this.driveFolderId,
      repoOwner: repoOwner ?? this.repoOwner,
      repoName: repoName ?? this.repoName,
      createdAt: createdAt,
      tailscaleHostname: tailscaleHostname ?? this.tailscaleHostname,
      githubAccountLogin: githubAccountLogin ?? this.githubAccountLogin,
      lastBackupAt: lastBackupAt ?? this.lastBackupAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'software': software.runnerId,
        'minecraftVersion': minecraftVersion,
        'loaderVersion': loaderVersion,
        'javaMajor': javaMajor,
        'driveFolderId': driveFolderId,
        'repoOwner': repoOwner,
        'repoName': repoName,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'tailscaleHostname': tailscaleHostname,
        'githubAccountLogin': githubAccountLogin,
        'lastBackupAt': lastBackupAt?.toUtc().toIso8601String(),
        'lastSyncAt': lastSyncAt?.toUtc().toIso8601String(),
      };

  static ServerRecord fromJson(Map<String, dynamic> json) {
    return ServerRecord(
      id: _str(json['id']) ?? '',
      name: _str(json['name']) ?? 'Server',
      description: _str(json['description']) ?? '',
      software: ServerSoftware.fromRunnerId(_str(json['software']) ?? 'vanilla'),
      minecraftVersion: _str(json['minecraftVersion']) ?? '',
      loaderVersion: _str(json['loaderVersion']) ?? '',
      javaMajor: _int(json['javaMajor'], 21),
      driveFolderId: _str(json['driveFolderId']) ?? '',
      repoOwner: _str(json['repoOwner']) ?? '',
      repoName: _str(json['repoName']) ?? '',
      createdAt: DateTime.tryParse(_str(json['createdAt']) ?? '')?.toLocal() ?? DateTime.now(),
      tailscaleHostname: _str(json['tailscaleHostname']),
      githubAccountLogin: _str(json['githubAccountLogin']),
      lastBackupAt: DateTime.tryParse(_str(json['lastBackupAt']) ?? '')?.toLocal(),
      lastSyncAt: DateTime.tryParse(_str(json['lastSyncAt']) ?? '')?.toLocal(),
    );
  }

  /// Metadata written to Drive at Minecraft Servers/<Name>/metadata.json.
  Map<String, Object?> toDriveMetadata() => {
        'schema': 1,
        'id': id,
        'name': name,
        'description': description,
        'software': software.runnerId,
        'minecraftVersion': minecraftVersion,
        'loaderVersion': loaderVersion,
        'javaMajor': javaMajor,
        'githubRepo': repoFullName,
        'workflow': 'voxelops-server.yml',
        'tailscaleHostname': tailscaleHostname,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'lastBackupAt': lastBackupAt?.toUtc().toIso8601String(),
        'lastSyncAt': lastSyncAt?.toUtc().toIso8601String(),
      };

  static ServerRecord fromDriveMetadata(
    Map<String, dynamic> json, {
    required String driveFolderId,
    required String repoOwner,
    required String repoName,
    String? githubAccountLogin,
  }) {
    return ServerRecord(
      id: _str(json['id']) ?? 'srv_${DateTime.now().microsecondsSinceEpoch}',
      name: _str(json['name']) ?? 'Imported server',
      description: _str(json['description']) ?? '',
      software: ServerSoftware.fromRunnerId(_str(json['software']) ?? 'vanilla'),
      minecraftVersion: _str(json['minecraftVersion']) ?? '',
      loaderVersion: _str(json['loaderVersion']) ?? '',
      javaMajor: _int(json['javaMajor'], 21),
      driveFolderId: driveFolderId,
      repoOwner: repoOwner,
      repoName: repoName,
      createdAt: DateTime.tryParse(_str(json['createdAt']) ?? '')?.toLocal() ?? DateTime.now(),
      tailscaleHostname: _str(json['tailscaleHostname']),
      githubAccountLogin: githubAccountLogin,
      lastBackupAt: DateTime.tryParse(_str(json['lastBackupAt']) ?? '')?.toLocal(),
      lastSyncAt: DateTime.tryParse(_str(json['lastSyncAt']) ?? '')?.toLocal(),
    );
  }
}

enum ServerState { offline, starting, running, stopping, restarting, saving, error, unknown }

/// Written by the runner to control/status.json roughly every 15 seconds.
class ServerStatus {
  const ServerStatus({
    required this.state,
    required this.updatedAt,
    this.players = 0,
    this.maxPlayers = 0,
    this.minecraftVersion,
    this.cpuPercent,
    this.ramUsedMb,
    this.ramTotalMb,
    this.uptimeSeconds,
    this.tailscaleIp,
    this.syncState = 'idle',
    this.lastError,
    this.runId,
    this.lastBackupAt,
    this.lastSyncAt,
  });

  final ServerState state;
  final DateTime updatedAt;
  final int players;
  final int maxPlayers;
  final String? minecraftVersion;
  final double? cpuPercent;
  final int? ramUsedMb;
  final int? ramTotalMb;
  final int? uptimeSeconds;
  final String? tailscaleIp;
  final String syncState;
  final String? lastError;
  final String? runId;
  final DateTime? lastBackupAt;
  final DateTime? lastSyncAt;

  bool get isStale => DateTime.now().toUtc().difference(updatedAt.toUtc()) > const Duration(seconds: 120);

  static ServerStatus offline() => ServerStatus(state: ServerState.offline, updatedAt: DateTime.now());

  /// Used when the status file cannot be read (offline device, Drive error).
  static ServerStatus unreachable(String message) =>
      ServerStatus(state: ServerState.unknown, updatedAt: DateTime.now(), lastError: message);

  static ServerStatus fromJson(Map<String, dynamic> json) {
    return ServerStatus(
      state: _state(_str(json['state'])),
      updatedAt: DateTime.tryParse(_str(json['updatedAt']) ?? '')?.toLocal() ?? DateTime.now(),
      players: _int(json['players'], 0),
      maxPlayers: _int(json['maxPlayers'], 0),
      minecraftVersion: _str(json['minecraftVersion']),
      cpuPercent: _double(json['cpuPercent']),
      ramUsedMb: _nullableInt(json['ramUsedMb']),
      ramTotalMb: _nullableInt(json['ramTotalMb']),
      uptimeSeconds: _nullableInt(json['uptimeSeconds']),
      tailscaleIp: _str(json['tailscaleIp']),
      syncState: _str(json['syncState']) ?? 'idle',
      lastError: _str(json['lastError']),
      runId: _str(json['runId']),
      lastBackupAt: DateTime.tryParse(_str(json['lastBackupAt']) ?? '')?.toLocal(),
      lastSyncAt: DateTime.tryParse(_str(json['lastSyncAt']) ?? '')?.toLocal(),
    );
  }

  static ServerState _state(String? value) {
    for (final candidate in ServerState.values) {
      if (candidate.name == value) {
        return candidate;
      }
    }
    return ServerState.unknown;
  }
}

class BackupEntry {
  const BackupEntry({
    required this.fileId,
    required this.name,
    required this.kind,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String fileId;
  final String name;

  /// auto | manual | prerestore | import
  final String kind;
  final DateTime createdAt;
  final int sizeBytes;
}

String? _str(Object? value) => value is String && value.isNotEmpty ? value : null;

int _int(Object? value, int fallback) => value is num ? value.toInt() : fallback;

int? _nullableInt(Object? value) => value is num ? value.toInt() : null;

double? _double(Object? value) => value is num ? value.toDouble() : null;
