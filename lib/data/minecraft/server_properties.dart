import 'dart:convert';

import '../../domain/server_models.dart';

/// Round-trip editor for server.properties. Comments, ordering and unknown keys are kept,
/// so edits made in the app never destroy settings the user added by hand.
class ServerPropertiesFile {
  ServerPropertiesFile._(this._lines);

  final List<String> _lines;

  factory ServerPropertiesFile.parse(String text) {
    final lines = const LineSplitter().convert(text);
    return ServerPropertiesFile._(lines.isEmpty ? <String>[] : lines);
  }

  factory ServerPropertiesFile.withDefaults({String levelName = 'world'}) {
    return ServerPropertiesFile.parse([
      '#Minecraft server properties (managed by VoxelOps)',
      'level-name=$levelName',
      'server-port=25565',
      'enable-status=true',
      'enable-rcon=false',
      'enable-query=false',
      'sync-chunk-writes=true',
    ].join('\n'));
  }

  String? get(String key) {
    for (final line in _lines) {
      if (_isComment(line) || !line.contains('=')) {
        continue;
      }
      final index = line.indexOf('=');
      if (line.substring(0, index).trim() == key) {
        return line.substring(index + 1);
      }
    }
    return null;
  }

  void set(String key, String value) {
    for (var i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (_isComment(line) || !line.contains('=')) {
        continue;
      }
      final index = line.indexOf('=');
      if (line.substring(0, index).trim() == key) {
        _lines[i] = '$key=$value';
        return;
      }
    }
    _lines.add('$key=$value');
  }

  /// Applies the wizard/settings values without touching unrelated keys.
  void applySettings(ServerSettings settings) {
    set('motd', settings.motd.replaceAll('\n', ' '));
    set('max-players', '${settings.maxPlayers}');
    set('gamemode', settings.gamemode);
    set('difficulty', settings.difficulty);
    set('online-mode', '${settings.onlineMode}');
    set('pvp', '${settings.pvp}');
    set('view-distance', '${settings.viewDistance}');
    set('simulation-distance', '${settings.simulationDistance}');
    set('white-list', '${settings.whitelist}');
    set('spawn-protection', '${settings.spawnProtection}');
    set('allow-nether', '${settings.allowNether}');
    set('enable-command-block', '${settings.commandBlocks}');
    set('hardcore', '${settings.hardcore}');
    if (settings.levelSeed.isNotEmpty) {
      set('level-seed', settings.levelSeed);
    }
  }

  ServerSettings toSettings() {
    bool boolean(String key, bool fallback) => switch (get(key)?.trim().toLowerCase()) {
          'true' => true,
          'false' => false,
          _ => fallback,
        };
    int integer(String key, int fallback) => int.tryParse(get(key)?.trim() ?? '') ?? fallback;
    return ServerSettings(
      motd: get('motd') ?? 'A VoxelOps server',
      maxPlayers: integer('max-players', 20),
      gamemode: get('gamemode') ?? 'survival',
      difficulty: get('difficulty') ?? 'easy',
      onlineMode: boolean('online-mode', true),
      pvp: boolean('pvp', true),
      viewDistance: integer('view-distance', 10),
      simulationDistance: integer('simulation-distance', 8),
      whitelist: boolean('white-list', false),
      spawnProtection: integer('spawn-protection', 16),
      allowNether: boolean('allow-nether', true),
      commandBlocks: boolean('enable-command-block', false),
      hardcore: boolean('hardcore', false),
      levelSeed: get('level-seed') ?? '',
    );
  }

  String toText() => '${_lines.join('\n')}\n';

  static bool _isComment(String line) {
    final trimmed = line.trimLeft();
    return trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('!');
  }
}
