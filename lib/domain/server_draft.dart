import 'dart:typed_data';

import 'server_models.dart';

/// Everything the creation wizard collects. Immutable; the wizard updates it with copyWith.
class ServerDraft {
  const ServerDraft({
    this.name = '',
    this.description = '',
    this.software = ServerSoftware.paper,
    this.minecraftVersion = '',
    this.build,
    this.settings = const ServerSettings(),
    this.runtime = const RuntimeSettings(),
    this.iconBytes,
    this.eulaAccepted = false,
    this.githubRiskAccepted = false,
    this.startAfterCreate = false,
    this.repoOwner = '',
    this.repoName = '',
    this.createRepository = true,
    this.repoPrivate = true,
    this.runnerLabel = 'ubuntu-latest',
  });

  final String name;
  final String description;
  final ServerSoftware software;
  final String minecraftVersion;
  final ResolvedBuild? build;
  final ServerSettings settings;
  final RuntimeSettings runtime;
  final Uint8List? iconBytes;
  final bool eulaAccepted;
  final bool githubRiskAccepted;
  final bool startAfterCreate;
  final String repoOwner;
  final String repoName;
  final bool createRepository;
  final bool repoPrivate;
  final String runnerLabel;

  String get repoFullName => repoOwner.isEmpty || repoName.isEmpty ? '' : '$repoOwner/$repoName';

  ServerDraft copyWith({
    String? name,
    String? description,
    ServerSoftware? software,
    String? minecraftVersion,
    ResolvedBuild? build,
    ServerSettings? settings,
    RuntimeSettings? runtime,
    Uint8List? iconBytes,
    bool clearIcon = false,
    bool? eulaAccepted,
    bool? githubRiskAccepted,
    bool? startAfterCreate,
    String? repoOwner,
    String? repoName,
    bool? createRepository,
    bool? repoPrivate,
    String? runnerLabel,
  }) {
    return ServerDraft(
      name: name ?? this.name,
      description: description ?? this.description,
      software: software ?? this.software,
      minecraftVersion: minecraftVersion ?? this.minecraftVersion,
      build: build ?? this.build,
      settings: settings ?? this.settings,
      runtime: runtime ?? this.runtime,
      iconBytes: clearIcon ? null : (iconBytes ?? this.iconBytes),
      eulaAccepted: eulaAccepted ?? this.eulaAccepted,
      githubRiskAccepted: githubRiskAccepted ?? this.githubRiskAccepted,
      startAfterCreate: startAfterCreate ?? this.startAfterCreate,
      repoOwner: repoOwner ?? this.repoOwner,
      repoName: repoName ?? this.repoName,
      createRepository: createRepository ?? this.createRepository,
      repoPrivate: repoPrivate ?? this.repoPrivate,
      runnerLabel: runnerLabel ?? this.runnerLabel,
    );
  }
}
