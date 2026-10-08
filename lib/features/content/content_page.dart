import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../data/content/content_catalog.dart';
import '../../data/provisioning/drive_layout.dart';
import '../../domain/integration_models.dart';
import '../../domain/server_models.dart';
import '../../state/core_providers.dart';
import '../../state/server_providers.dart';
import '../servers/servers_page.dart';
import '../shared/server_ui.dart';

/// Folder id for the active server's mods/plugins folder (created on demand).
final contentFolderProvider = FutureProvider.autoDispose.family<String, ({String serverId, String name})>((ref, args) async {
  final record = serverById(ref.read(serverRegistryProvider), args.serverId);
  if (record == null) {
    throw StateError('Server not found');
  }
  return ref.read(serverActionsProvider).folderFor(record, args.name);
});

class ContentPage extends ConsumerStatefulWidget {
  const ContentPage({super.key});

  @override
  ConsumerState<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends ConsumerState<ContentPage> {
  final _search = TextEditingController();
  ContentKind? _kind;
  ContentSource _source = ContentSource.all;
  ContentSort _sort = ContentSort.relevance;
  String _query = '';
  int _tab = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeServerProvider);
    if (active == null) {
      return AppPage(title: context.tr('content.title'), inShell: true, children: const [NoActiveServer()]);
    }
    final software = active.software;
    final kind = _kind ?? (software.contentKind == ContentKind.plugins ? ContentKind.plugins : ContentKind.mods);
    final folderName = kind == ContentKind.worlds ? DriveLayout.world : (kind == ContentKind.plugins ? DriveLayout.plugins : DriveLayout.mods);
    return AppPage(
      title: context.tr('content.title'),
      inShell: true,
      children: [
        Text(
          context.tr('content.subtitle', args: {'server': active.name, 'version': active.minecraftVersion}),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpace.md),
        OptionChips<int>(
          options: const <int>[0, 1],
          selected: _tab,
          label: (t) => context.tr(t == 0 ? 'content.tab.browse' : 'content.tab.installed'),
          onSelected: (t) => setState(() => _tab = t),
        ),
        const SizedBox(height: AppSpace.md),
        OptionChips<ContentKind>(
          options: <ContentKind>[if (software.supportsContent) ContentKind.mods, if (software.supportsContent) ContentKind.plugins, ContentKind.worlds],
          selected: kind,
          label: (k) => context.tr('content.kind.${k.name}'),
          onSelected: (k) => setState(() {
            _kind = k;
            _query = '';
            _search.clear();
          }),
        ),
        const SizedBox(height: AppSpace.md),
        if (_tab == 0) ...[
          if (kind == ContentKind.worlds)
            GlassCard(
              child: Text(context.tr('content.worldsNote'), style: Theme.of(context).textTheme.bodySmall),
            ),
          AppSearchField(
            controller: _search,
            hint: context.tr('content.search'),
            onSubmitted: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: AppSpace.sm),
          OptionChips<ContentSource>(
            options: ContentSource.values,
            selected: _source,
            label: (s) => context.tr('content.source.${s.name}'),
            onSelected: (s) => setState(() => _source = s),
          ),
          const SizedBox(height: AppSpace.sm),
          OptionChips<ContentSort>(
            options: ContentSort.values,
            selected: _sort,
            label: (s) => context.tr('content.sort.${s.name}'),
            onSelected: (s) => setState(() => _sort = s),
          ),
          const SizedBox(height: AppSpace.md),
          if (_query.isEmpty)
            EmptyState(icon: Icons.travel_explore_rounded, title: context.tr('content.startSearch'))
          else
            _SearchResults(
              query: ContentQuery(kind: kind, text: _query, source: _source, sort: _sort),
              software: software,
              minecraftVersion: active.minecraftVersion,
              kind: kind,
              serverId: active.id,
            ),
        ] else
          _InstalledList(serverId: active.id, folderName: folderName, kind: kind),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.query,
    required this.software,
    required this.minecraftVersion,
    required this.kind,
    required this.serverId,
  });

  final ContentQuery query;
  final ServerSoftware software;
  final String minecraftVersion;
  final ContentKind kind;
  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(contentSearchProvider((query: query, software: software, minecraftVersion: minecraftVersion)));
    return AsyncBody<List<ContentProject>>(
      value: results,
      onRetry: () => ref.invalidate(contentSearchProvider((query: query, software: software, minecraftVersion: minecraftVersion))),
      builder: (context, items) {
        if (items.isEmpty) {
          return EmptyState(icon: Icons.search_off_rounded, title: context.tr('content.noResults'));
        }
        return Column(
          children: [
            for (var i = 0; i < items.length; i++)
              FadeSlideIn(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: GlassCard(
                    onTap: () => _openProject(context, items[i]),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AvatarImage(url: items[i].iconUrl, fallback: items[i].title, size: 48),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(items[i].title, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(
                                '${items[i].author} · ${context.tr('content.downloads', args: {'n': formatCount(items[i].downloads)})} · ${items[i].source}',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: AppSpace.xs),
                              Text(items[i].summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openProject(BuildContext context, ContentProject project) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _ProjectSheet(
        project: project,
        kind: kind,
        software: software,
        minecraftVersion: minecraftVersion,
        serverId: serverId,
      ),
    );
  }
}

String formatCount(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}K';
  }
  return '$value';
}

class _ProjectSheet extends ConsumerWidget {
  const _ProjectSheet({
    required this.project,
    required this.kind,
    required this.software,
    required this.minecraftVersion,
    required this.serverId,
  });

  final ContentProject project;
  final ContentKind kind;
  final ServerSoftware software;
  final String minecraftVersion;
  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = (project: project, kind: kind, software: software, minecraftVersion: minecraftVersion);
    final files = ref.watch(contentFilesProvider(args));
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(project.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpace.xs),
            Text(project.summary, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpace.md),
            SecondaryButton(
              label: context.tr('content.openPage'),
              icon: Icons.open_in_new_rounded,
              onPressed: () => launchUrl(Uri.parse(project.webUrl), mode: LaunchMode.externalApplication),
            ),
            const SizedBox(height: AppSpace.lg),
            AsyncBody<List<ContentFile>>(
              value: files,
              onRetry: () => ref.invalidate(contentFilesProvider(args)),
              builder: (context, list) {
                if (list.isEmpty) {
                  return EmptyState(icon: Icons.inventory_2_outlined, title: context.tr('content.noFiles'), message: context.tr('content.noFilesHint'));
                }
                return Column(
                  children: [
                    for (final file in list.take(15))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: _FileTile(file: file, kind: kind, serverId: serverId),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FileTile extends ConsumerWidget {
  const _FileTile({required this.file, required this.kind, required this.serverId});

  final ContentFile file;
  final ContentKind kind;
  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compatible = file.compatibility == 'compatible';
    final color = compatible ? AppColors.success : AppColors.warning;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(file.displayName, style: Theme.of(context).textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: AppRadius.all(AppRadius.pill)),
                child: Text(context.tr(compatible ? 'content.compat.ok' : 'content.compat.unknown'), style: TextStyle(color: color, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            '${file.releaseType} · ${formatBytes(file.sizeBytes)} · ${file.gameVersions.take(4).join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(file.compatibilityNote, style: Theme.of(context).textTheme.labelSmall),
          if (file.requiredDependencies.isNotEmpty)
            Text(context.tr('content.deps', args: {'n': file.requiredDependencies.length}), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.warning)),
          const SizedBox(height: AppSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: file.canDownload
                ? PrimaryButton(
                    label: context.tr('content.install'),
                    icon: Icons.download_rounded,
                    onPressed: () async {
                      final record = serverById(ref.read(serverRegistryProvider), serverId);
                      if (record == null) {
                        return;
                      }
                      await guardedAction(
                        context,
                        ref,
                        () => ref.read(serverActionsProvider).installContent(record: record, file: file, kind: kind),
                        successKey: 'content.installed',
                      );
                    },
                  )
                : SecondaryButton(
                    label: context.tr('content.openPage'),
                    icon: Icons.open_in_new_rounded,
                    onPressed: () => launchUrl(Uri.parse('https://www.curseforge.com/minecraft'), mode: LaunchMode.externalApplication),
                  ),
          ),
        ],
      ),
    );
  }
}

class _InstalledList extends ConsumerWidget {
  const _InstalledList({required this.serverId, required this.folderName, required this.kind});

  final String serverId;
  final String folderName;
  final ContentKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(contentFolderProvider((serverId: serverId, name: folderName)));
    return AsyncBody<String>(
      value: folder,
      builder: (context, folderId) {
        final files = ref.watch(driveFolderProvider(folderId));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: SecondaryButton(label: context.tr('content.restartHint'), icon: Icons.info_outline_rounded, onPressed: null)),
                if (kind == ContentKind.worlds) ...[
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: PrimaryButton(
                      label: context.tr('content.uploadWorld'),
                      icon: Icons.upload_file_rounded,
                      onPressed: () => _uploadWorld(context, ref),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpace.md),
            AsyncBody<List<DriveFile>>(
              value: files,
              onRetry: () => ref.invalidate(driveFolderProvider(folderId)),
              builder: (context, list) {
                final items = list.where((f) => !f.isFolder).toList();
                if (items.isEmpty) {
                  return EmptyState(icon: Icons.folder_open_rounded, title: context.tr('content.installedEmpty'));
                }
                return Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      FadeSlideIn(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.sm),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                            child: Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined, size: 20),
                                const SizedBox(width: AppSpace.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(items[i].name, style: Theme.of(context).textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text(formatBytes(items[i].sizeBytes), style: Theme.of(context).textTheme.labelSmall),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.tr('action.remove'),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () async {
                                    final ok = await confirmAction(
                                      context,
                                      title: context.tr('content.removeTitle'),
                                      message: context.tr('content.removeBody', args: {'name': items[i].name}),
                                      confirmLabel: context.tr('action.remove'),
                                      destructive: true,
                                    );
                                    if (!ok || !context.mounted) {
                                      return;
                                    }
                                    await guardedAction(context, ref, () => ref.read(serverActionsProvider).trash(items[i]), successKey: 'content.removed');
                                    ref.invalidate(driveFolderProvider(folderId));
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _uploadWorld(BuildContext context, WidgetRef ref) async {
    const type = XTypeGroup(label: 'zip', extensions: <String>['zip']);
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[type]);
    if (file == null || !context.mounted) {
      return;
    }
    final record = serverById(ref.read(serverRegistryProvider), serverId);
    if (record == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (!context.mounted) {
      return;
    }
    await guardedAction(
      context,
      ref,
      () => ref.read(serverActionsProvider).importWorld(record, fileName: file.name, bytes: bytes),
      successKey: 'content.worldQueued',
    );
  }
}
