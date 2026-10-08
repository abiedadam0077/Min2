import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/net/api_client.dart';
import '../../domain/integration_models.dart';

/// GitHub REST API v3 for repositories, the Contents API, Actions secrets, workflow runs and
/// dispatches. Every call uses the active account's token, read from secure storage on demand.
class GitHubApi {
  GitHubApi(this._api, this._tokenReader);

  static const String _base = 'https://api.github.com';
  static const String _provider = 'GitHub';

  final ApiClient _api;
  final Future<String?> Function() _tokenReader;

  Future<Map<String, String>> _headers() async {
    final token = await _tokenReader();
    if (token == null || token.isEmpty) {
      throw const AppException(AppErrorKind.unauthorized, 'GitHub is not connected.');
    }
    return {
      'Authorization': 'Bearer $token',
      'X-GitHub-Api-Version': '2022-11-28',
      'Accept': 'application/vnd.github+json',
    };
  }

  Future<http.Response> _get(String path, {Map<String, String>? query}) async {
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    return _api.send('GET', uri, headers: await _headers());
  }

  Future<GitHubUser> currentUser() async {
    final response = await _get('/user');
    ApiClient.ensureSuccess(response, provider: _provider);
    return GitHubUser.fromJson(ApiClient.decodeObject(response, provider: _provider));
  }

  /// Repositories the user can access. Capped at 500 to keep the picker responsive.
  Future<List<GitHubRepo>> listRepositories() async {
    final repos = <GitHubRepo>[];
    for (var page = 1; page <= 5; page++) {
      final response = await _get('/user/repos', query: {
        'per_page': '100',
        'page': '$page',
        'sort': 'pushed',
        'affiliation': 'owner,collaborator,organization_member',
      });
      ApiClient.ensureSuccess(response, provider: _provider);
      final items = ApiClient.decodeList(response, provider: _provider);
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          repos.add(GitHubRepo.fromJson(item));
        }
      }
      if (items.length < 100) {
        break;
      }
    }
    return repos;
  }

  Future<GitHubRepo> getRepository(String owner, String repo) async {
    final response = await _get('/repos/$owner/$repo');
    ApiClient.ensureSuccess(response, provider: _provider);
    return GitHubRepo.fromJson(ApiClient.decodeObject(response, provider: _provider));
  }

  /// Creates a private or public repository with an initial commit so the Contents API works.
  Future<GitHubRepo> createRepository({required String name, required bool isPrivate, String? description}) async {
    final response = await _api.send(
      'POST',
      Uri.parse('$_base/user/repos'),
      headers: await _headers(),
      body: <String, Object?>{
        'name': name,
        'private': isPrivate,
        'description': description ?? 'VoxelOps Minecraft server',
        'auto_init': true,
        'has_issues': false,
        'has_wiki': false,
        'has_projects': false,
      },
    );
    ApiClient.ensureSuccess(response, provider: _provider);
    return GitHubRepo.fromJson(ApiClient.decodeObject(response, provider: _provider));
  }

  /// Returns (sha, decoded text) or null when the file does not exist.
  Future<({String sha, String text})?> readTextFile(String owner, String repo, String path, {String? ref}) async {
    final response = await _get('/repos/$owner/$repo/contents/${_encodePath(path)}', query: ref == null ? null : {'ref': ref});
    if (response.statusCode == 404) {
      return null;
    }
    ApiClient.ensureSuccess(response, provider: _provider);
    final json = ApiClient.decodeObject(response, provider: _provider);
    final content = (json['content'] as String? ?? '').replaceAll('\n', '');
    final sha = json['sha'] as String? ?? '';
    return (sha: sha, text: utf8.decode(base64Decode(content)));
  }

  /// Creates or updates a file on [branch]. Pass [sha] when updating an existing file.
  Future<void> writeFile({
    required String owner,
    required String repo,
    required String path,
    required List<int> bytes,
    required String message,
    required String branch,
    String? sha,
  }) async {
    final response = await _api.send(
      'PUT',
      Uri.parse('$_base/repos/$owner/$repo/contents/${_encodePath(path)}'),
      headers: await _headers(),
      body: <String, Object?>{
        'message': message,
        'content': base64Encode(bytes),
        'branch': branch,
        if (sha != null) 'sha': sha,
      },
    );
    ApiClient.ensureSuccess(response, provider: _provider);
  }

  Future<({String keyId, String key})> actionsPublicKey(String owner, String repo) async {
    final response = await _get('/repos/$owner/$repo/actions/secrets/public-key');
    ApiClient.ensureSuccess(response, provider: _provider);
    final json = ApiClient.decodeObject(response, provider: _provider);
    return (keyId: json['key_id'] as String? ?? '', key: json['key'] as String? ?? '');
  }

  Future<void> putActionsSecret({
    required String owner,
    required String repo,
    required String name,
    required String encryptedValue,
    required String keyId,
  }) async {
    final response = await _api.send(
      'PUT',
      Uri.parse('$_base/repos/$owner/$repo/actions/secrets/$name'),
      headers: await _headers(),
      body: <String, Object?>{'encrypted_value': encryptedValue, 'key_id': keyId},
    );
    ApiClient.ensureSuccess(response, provider: _provider, accept: const {201, 204});
  }

  Future<List<GitHubRun>> listRuns(String owner, String repo, {int perPage = 10}) async {
    final response = await _get(
      '/repos/$owner/$repo/actions/workflows/${AppConfig.workflowFileName}/runs',
      query: {'per_page': '$perPage'},
    );
    if (response.statusCode == 404) {
      return const <GitHubRun>[];
    }
    ApiClient.ensureSuccess(response, provider: _provider);
    final json = ApiClient.decodeObject(response, provider: _provider);
    final runs = json['workflow_runs'];
    if (runs is! List<dynamic>) {
      return const <GitHubRun>[];
    }
    return runs.whereType<Map<String, dynamic>>().map(GitHubRun.fromJson).toList();
  }

  /// Starts the server workflow on [ref]. Returns once GitHub accepted the dispatch (HTTP 204).
  Future<void> dispatchServerWorkflow({
    required String owner,
    required String repo,
    required String ref,
    Map<String, String> inputs = const <String, String>{},
  }) async {
    final response = await _api.send(
      'POST',
      Uri.parse('$_base/repos/$owner/$repo/actions/workflows/${AppConfig.workflowFileName}/dispatches'),
      headers: await _headers(),
      body: <String, Object?>{'ref': ref, if (inputs.isNotEmpty) 'inputs': inputs},
    );
    if (response.statusCode == 404) {
      throw const AppException(
        AppErrorKind.notFound,
        'Workflow not found. Make sure Actions are enabled for this repository and the workflow file exists on the branch.',
        statusCode: 404,
      );
    }
    ApiClient.ensureSuccess(response, provider: _provider, accept: const {204});
  }

  Future<void> cancelRun(String owner, String repo, int runId, {bool force = false}) async {
    final response = await _api.send(
      'POST',
      Uri.parse('$_base/repos/$owner/$repo/actions/runs/$runId/${force ? 'force-cancel' : 'cancel'}'),
      headers: await _headers(),
    );
    ApiClient.ensureSuccess(response, provider: _provider, accept: const {202});
  }

  static String _encodePath(String path) => path.split('/').map(Uri.encodeComponent).join('/');
}
