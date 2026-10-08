import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/server_models.dart';

/// Non-secret app state. Tokens never live here; they are in SecureStore.
class AppPrefs {
  AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const String _kLocale = 'pref.locale';
  static const String _kOnboarded = 'pref.onboarded';
  static const String _kActiveServer = 'pref.active_server';
  static const String _kServers = 'pref.servers.v1';
  static const String _kGitHubAccounts = 'pref.github.accounts.v1';
  static const String _kGitHubActive = 'pref.github.active';
  static const String _kGoogleAccount = 'pref.google.account.v1';
  static const String _kTailscaleTailnet = 'pref.tailscale.tailnet';
  static const String _kTailscaleConnected = 'pref.tailscale.connected';
  static const String _kDriveRootId = 'pref.drive.root_id';
  static const String _kDriveRootName = 'pref.drive.root_name';

  String get locale => _prefs.getString(_kLocale) ?? 'system';

  Future<void> setLocale(String value) => _prefs.setString(_kLocale, value);

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;

  Future<void> setOnboarded(bool value) => _prefs.setBool(_kOnboarded, value);

  String? get activeServerId => _prefs.getString(_kActiveServer);

  Future<void> setActiveServerId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kActiveServer);
    } else {
      await _prefs.setString(_kActiveServer, id);
    }
  }

  List<ServerRecord> servers() {
    final raw = _prefs.getString(_kServers);
    if (raw == null || raw.isEmpty) {
      return <ServerRecord>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return <ServerRecord>[];
    }
    final result = <ServerRecord>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        try {
          result.add(ServerRecord.fromJson(item));
        } on ArgumentError {
          // Skip records written by a newer or unknown software type.
        }
      }
    }
    return result;
  }

  Future<void> saveServers(List<ServerRecord> servers) {
    return _prefs.setString(_kServers, jsonEncode(servers.map((s) => s.toJson()).toList()));
  }

  /// Public GitHub profile data per account (no tokens).
  List<Map<String, dynamic>> githubAccounts() => _readList(_kGitHubAccounts);

  Future<void> saveGitHubAccounts(List<Map<String, dynamic>> accounts) =>
      _prefs.setString(_kGitHubAccounts, jsonEncode(accounts));

  String? get githubActiveLogin => _prefs.getString(_kGitHubActive);

  Future<void> setGitHubActiveLogin(String? login) async {
    if (login == null) {
      await _prefs.remove(_kGitHubActive);
    } else {
      await _prefs.setString(_kGitHubActive, login);
    }
  }

  Map<String, dynamic>? get googleAccount {
    final raw = _prefs.getString(_kGoogleAccount);
    if (raw == null) {
      return null;
    }
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<void> setGoogleAccount(Map<String, dynamic>? value) async {
    if (value == null) {
      await _prefs.remove(_kGoogleAccount);
    } else {
      await _prefs.setString(_kGoogleAccount, jsonEncode(value));
    }
  }

  String get tailscaleTailnet => _prefs.getString(_kTailscaleTailnet) ?? '-';

  Future<void> setTailscaleTailnet(String value) => _prefs.setString(_kTailscaleTailnet, value.trim().isEmpty ? '-' : value.trim());

  bool get tailscaleConnected => _prefs.getBool(_kTailscaleConnected) ?? false;

  Future<void> setTailscaleConnected(bool value) => _prefs.setBool(_kTailscaleConnected, value);

  /// Drive folder that holds every server (chosen during Server Storage setup).
  String? get driveRootId => _prefs.getString(_kDriveRootId);

  String? get driveRootName => _prefs.getString(_kDriveRootName);

  Future<void> setDriveRoot(String? id, String? name) async {
    if (id == null || id.isEmpty) {
      await _prefs.remove(_kDriveRootId);
      await _prefs.remove(_kDriveRootName);
      return;
    }
    await _prefs.setString(_kDriveRootId, id);
    await _prefs.setString(_kDriveRootName, name ?? 'Minecraft Servers');
  }

  List<Map<String, dynamic>> _readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) {
      return <Map<String, dynamic>>[];
    }
    return decoded.whereType<Map<String, dynamic>>().toList();
  }
}
