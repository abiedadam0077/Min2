/// Google Drive folder layout for one server:
///
/// MinecraftServers/<Name>/
///   metadata.json, server.properties, eula.txt, server-icon.png, README.txt
///   server/        server software cache (server jar), restored before every start
///   world/ world_nether/ world_the_end/
///   mods/ plugins/ config/
///   backups/       zip backups created by the runner or the app
///   logs/          archived console logs per run
///   imports/       uploaded world archives waiting to be applied
///   control/       runtime.json, status.json, live.log and commands/ (app -> runner queue)
abstract final class DriveLayout {
  static const String server = 'server';
  static const String world = 'world';
  static const String worldNether = 'world_nether';
  static const String worldEnd = 'world_the_end';
  static const String mods = 'mods';
  static const String plugins = 'plugins';
  static const String config = 'config';
  static const String backups = 'backups';
  static const String logs = 'logs';
  static const String imports = 'imports';
  static const String control = 'control';
  static const String commands = 'commands';

  static const String metadataFile = 'metadata.json';
  static const String propertiesFile = 'server.properties';
  static const String eulaFile = 'eula.txt';
  static const String iconFile = 'server-icon.png';
  static const String readmeFile = 'README.txt';
  static const String runtimeFile = 'runtime.json';
  static const String statusFile = 'status.json';
  static const String liveLogFile = 'live.log';

  static const List<String> worldFolders = <String>[world, worldNether, worldEnd];

  static const List<String> topFolders = <String>[
    server,
    world,
    worldNether,
    worldEnd,
    mods,
    plugins,
    config,
    backups,
    logs,
    imports,
    control,
  ];
}
