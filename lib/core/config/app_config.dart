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

  /// Default name of the Google Drive storage root that holds every server (Minecraft Servers/<Name>/...).
  /// The user can keep this name or choose another folder during Server Storage setup.
  static const String driveRootFolder = 'Minecraft Servers';
  static const String workflowFileName = 'voxelops-server.yml';
  static const String runnerRepoPath = '.voxelops/runner.py';
  static const String runnerAssetPath = 'assets/runtime/voxelops_runner.py';
  static const String defaultTailscaleTag = 'tag:minecraft';
  static const String tailscaleHostPrefix = 'voxel';

  static bool get hasGitHubOAuth => githubClientId.trim().isNotEmpty;

  /// A usable Google client ID ends with .apps.googleusercontent.com. Anything else is a build mistake.
  static bool get hasGoogleOAuth => googleClientId.trim().endsWith(googleClientSuffix);

  static const String googleClientSuffix = '.apps.googleusercontent.com';

  /// Android OAuth clients use the reversed client ID as a custom URI scheme.
  /// Must match android/app/build.gradle.kts exactly (same client ID, same algorithm, no lowercasing).
  static String get googleRedirectScheme {
    final id = googleClientId.trim();
    if (!id.endsWith(googleClientSuffix)) {
      return 'com.voxelops.oauth.unconfigured';
    }
    return 'com.googleusercontent.apps.${id.substring(0, id.length - googleClientSuffix.length)}';
  }

  static String get googleRedirectUri => '$googleRedirectScheme:/oauth2redirect';
}
