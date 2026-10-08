/// Compile-time configuration.
///
/// OAuth client IDs are public identifiers, not secrets. CI injects them with
/// --dart-define from repository variables. No client secret is ever compiled into the app.
abstract final class AppConfig {
  static const String appName = 'VoxelOps';
  static const String version = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  static const String build = String.fromEnvironment('APP_BUILD', defaultValue: '1');

  static const String githubClientId = String.fromEnvironment('GITHUB_OAUTH_CLIENT_ID');
  static const String googleClientId = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');

  static const String userAgent = 'VoxelOps-Android/1.0 (+https://github.com/abiedadam0077/Min2)';
  static const String githubScopes = 'repo workflow read:user';
  static const String googleScopes = 'openid email profile https://www.googleapis.com/auth/drive.file';

  /// Root folder in Google Drive that holds every server (MinecraftServers/<Name>/...).
  static const String driveRootFolder = 'MinecraftServers';
  static const String workflowFileName = 'voxelops-server.yml';
  static const String runnerRepoPath = '.voxelops/runner.py';
  static const String runnerAssetPath = 'assets/runtime/voxelops_runner.py';
  static const String defaultTailscaleTag = 'tag:minecraft';
  static const String tailscaleHostPrefix = 'voxel';

  static bool get hasGitHubOAuth => githubClientId.trim().isNotEmpty;
  static bool get hasGoogleOAuth => googleClientId.trim().isNotEmpty;

  /// Android OAuth clients use the reversed client ID as a custom URI scheme.
  static String get googleRedirectScheme {
    final prefix = googleClientId.trim().replaceFirst('.apps.googleusercontent.com', '');
    return 'com.googleusercontent.apps.${prefix.toLowerCase()}';
  }

  static String get googleRedirectUri => '$googleRedirectScheme:/oauth2redirect';
}
