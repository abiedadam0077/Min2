import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../domain/integration_models.dart';
import '../../domain/server_models.dart';
import '../../state/core_providers.dart';
import '../../state/server_providers.dart';
import '../shared/server_ui.dart';

const Set<String> _textExtensions = <String>{'properties', 'json', 'yml', 'yaml', 'txt', 'cfg', 'conf', 'toml', 'md', 'log', 'ini', 'xml', 'csv'};

class FileManagerPage extends ConsumerWidget {
  const FileManagerPage({super.key, required this.serverId, this.folderId});

  final String serverId;
  final String? folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = serverById(ref.watch(serverRegistryProvider), serverId);
    if (record == null) {
      return AppPage(title: context.tr('files.title'), children: [EmptyState(icon: Icons.search_off_rounded, title: context.tr('dashboard.missing'))]);
    }
    final current = folderId ?? record.driveFolderId;
    final files = ref.watch(driveFolderProvider(current));
    return AppPage(
      title: context.tr('files.title'),
      onRefresh: () async => ref.invalidate(driveFolderProvider(current)),
      actions: [
        IconButton(
          tooltip: context.tr('files.newFolder'),
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: () => _newFolder(context, ref, current),
        ),
      ],
      floatingAction: FloatingActionButton.extended(
        heroTag: 'files-upload',
        onPressed: () => _upload(context, ref, current),
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(context.tr('files.upload')),
      ),
      children: [
        if (folderId != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(context.tr('files.up')),
            ),
          ),
        AsyncBody<List<DriveFile>>(
          value: files,
          onRetry: () => ref.invalidate(driveFolderProvider(current)),
          builder: (context, list) {
            if (list.isEmpty) {
              return EmptyState(icon: Icons.folder_open_rounded, title: context.tr('files.empty'));
            }
            return Column(
              children: [
                for (var i = 0; i < list.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: _FileRow(record: record, file: list[i], parentId: current),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _newFolder(BuildContext context, WidgetRef ref, String parentId) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('files.newFolder')),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(context.tr('action.cancel'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: Text(context.tr('action.save'))),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !context.mounted) {
      return;
    }
    await guardedAction(context, ref, () async {
      await ref.read(serverActionsProvider).createFolder(parentId, name);
      ref.invalidate(driveFolderProvider(parentId));
    }, successKey: 'files.created');
  }

  Future<void> _upload(BuildContext context, WidgetRef ref, String parentId) async {
    final file = await openFile();
    if (file == null || !context.mounted) {
      return;
    }
    final bytes = await file.readAsBytes();
    if (!context.mounted) {
      return;
    }
    await guardedAction(context, ref, () async {
      await ref.read(serverActionsProvider).uploadBytes(folderId: parentId, name: file.name, bytes: bytes, mimeType: 'application/octet-stream');
      ref.invalidate(driveFolderProvider(parentId));
    }, successKey: 'files.uploaded');
  }
}

class _FileRow extends ConsumerWidget {
  const _FileRow({required this.record, required this.file, required this.parentId});

  final ServerRecord record;
  final DriveFile file;
  final String parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
    final editable = !file.isFolder && _textExtensions.contains(ext) && (file.sizeBytes ?? 0) <= 512 * 1024;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      onTap: file.isFolder
          ? () => context.push('/server/${record.id}/files?folder=${file.id}')
          : editable
              ? () => context.push('/server/${record.id}/file?file=${file.id}')
              : null,
      child: Row(
        children: [
          Icon(file.isFolder ? Icons.folder_rounded : Icons.insert_drive_file_outlined, color: file.isFolder ? AppColors.warning : AppColors.textSecondary),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, style: Theme.of(context).textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  file.isFolder ? formatRelative(context, file.modifiedAt) : '${formatBytes(file.sizeBytes)} · ${formatRelative(context, file.modifiedAt)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _onAction(context, ref, value),
            itemBuilder: (_) => [
              if (editable) PopupMenuItem(value: 'edit', child: Text(context.tr('files.edit'))),
              if (!file.isFolder) PopupMenuItem(value: 'download', child: Text(context.tr('files.download'))),
              PopupMenuItem(value: 'rename', child: Text(context.tr('files.rename'))),
              PopupMenuItem(value: 'delete', child: Text(context.tr('action.remove'))),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onAction(BuildContext context, WidgetRef ref, String action) async {
    final actions = ref.read(serverActionsProvider);
    if (action == 'edit') {
      context.push('/server/${record.id}/file?file=${file.id}');
      return;
    }
    if (action == 'download') {
      await guardedAction(context, ref, () async {
        final bytes = await actions.downloadFile(file);
        final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/VoxelOps/${record.id}');
        await dir.create(recursive: true);
        final target = File('${dir.path}/${file.name}');
        await target.writeAsBytes(bytes, flush: true);
        if (context.mounted) {
          showAppSnack(context, context.tr('files.savedTo', args: {'path': target.path}));
        }
      });
      return;
    }
    if (action == 'rename') {
      final controller = TextEditingController(text: file.name);
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('files.rename')),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(context.tr('action.cancel'))),
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: Text(context.tr('action.save'))),
          ],
        ),
      );
      controller.dispose();
      if (name != null && name.isNotEmpty && context.mounted) {
        await guardedAction(context, ref, () async {
          await actions.rename(file, name);
          ref.invalidate(driveFolderProvider(parentId));
        }, successKey: 'files.renamed');
      }
      return;
    }
    if (action == 'delete') {
      final ok = await confirmAction(
        context,
        title: context.tr('files.deleteTitle'),
        message: context.tr('files.deleteBody', args: {'name': file.name}),
        confirmLabel: context.tr('action.remove'),
        destructive: true,
      );
      if (ok && context.mounted) {
        await guardedAction(context, ref, () async {
          await actions.trash(file);
          ref.invalidate(driveFolderProvider(parentId));
        }, successKey: 'files.deleted');
      }
    }
  }
}
