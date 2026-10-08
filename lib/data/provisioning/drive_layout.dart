/// Google Drive layout for one server (stable, documented, recoverable):
///
/// Minecraft Servers/                      <- storage root chosen by the user
///   NovaCraft/                            <- one folder per server
///     metadata.json                       name, software, Minecraft version, repository, timestamps
///     server.properties                   Minecraft settings (edited by the app)
///     eula.txt                            accepted when the server was created
///     server-icon.png                     optional 64x64 icon
///     README.txt                          what each folder is for
///     server/                             server software cache (for example the server jar)
///     world/  world_nether/  world_the_end/
///     mods/  plugins/  config/
///     backups/                            zip backups (automatic, manual, pre-restore, imported)
///     _voxelops/                          system folder used by the app and the runner
///       control/status.json, runtime.json, live.log
///       control/commands/                 one JSON file per command from the app
///       logs/                             one log file per run
///       imports/                          world archives waiting to be applied
abstract final class DriveLayout {
  static const String server = 'server';
  static const String world = 'world';
  static const String worldNether = 'world_nether';
  static const String worldEnd = 'world_the_end';
  static const String mods = 'mods';
  static const String plugins = 'plugins';
  static const String config = 'config';
  static const String backups = 'backups';

  static const String system = '_voxelops';
  static const String control = 'control';
  static const String commands = 'commands';
  static const String logs = 'logs';
  static const String imports = 'imports';

  static const String metadataFile = 'metadata.json';
  static const String propertiesFile = 'server.properties';
  static const String eulaFile = 'eula.txt';
  static const String iconFile = 'server-icon.png';
  static const String readmeFile = 'README.txt';
  static const String runtimeFile = 'runtime.json';
  static const String statusFile = 'status.json';
  static const String liveLogFile = 'live.log';

  static const List<String> worldFolders = <String>[world, worldNether, worldEnd];

  /// Folders created at the top level of every server folder.
  static const List<String> topFolders = <String>[server, world, worldNether, worldEnd, mods, plugins, config, backups];
}
