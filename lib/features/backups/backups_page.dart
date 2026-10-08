import 'package:file_selector/file_selector.dart';
import '../../state/core_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../domain/server_models.dart';
import '../../state/server_providers.dart';
import '../shared/server_ui.dart';

class BackupsPage extends ConsumerWidget {
  const BackupsPage({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = serverById(ref.watch(serverRegistryProvider), serverId);
    final backups = ref.watch(backupsProvider(serverId));
    return AppPage(
      title: context.tr('backups.title'),
      onRefresh: () async => ref.invalidate(backupsProvider(serverId)),
      actions: [
        IconButton(
          tooltip: context.tr('backups.importWorld'),
          icon: const Icon(Icons.upload_file_rounded),
          onPressed: record == null ? null : () => _importWorld(context, ref, record),
        ),
      ],
      floatingAction: FloatingActionButton.extended(
        heroTag: 'backups-create',
        onPressed: record == null
            ? null
            : () => guardedAction(
                  context,
                  ref,
                  () => ref.read(serverActionsProvider).createBackup(record),
                  successKey: 'backups.queued',
                ),
        icon: const Icon(Icons.backup_rounded),
        label: Text(context.tr('backups.create')),
      ),
      children: [
        GlassCard(
          child: Text(context.tr('backups.info'), style: Theme.of(context).textTheme.bodySmall),
        ),
        AsyncBody<List<BackupEntry>>(
          value: backups,
          onRetry: () => ref.invalidate(backupsProvider(serverId)),
          builder: (context, items) {
            if (items.isEmpty) {
              return EmptyState(icon: Icons.history_toggle_off_rounded, title: context.tr('backups.empty'));
            }
            return Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.14), borderRadius: AppRadius.all(AppRadius.pill)),
                                  child: Text(context.tr('backups.kind.${items[i].kind}'), style: Theme.of(context).textTheme.labelSmall),
                                ),
                                const Spacer(),
                                Text(formatBytes(items[i].sizeBytes), style: Theme.of(context).textTheme.labelSmall),
                              ],
                            ),
                            const SizedBox(height: AppSpace.sm),
                            Text(items[i].name, style: Theme.of(context).textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(formatDate(items[i].createdAt), style: Theme.of(context).textTheme.labelSmall),
                            const SizedBox(height: AppSpace.md),
                            Row(
                              children: [
                                Expanded(
                                  child: SecondaryButton(
                                    label: context.tr('backups.restore'),
                                    icon: Icons.settings_backup_restore_rounded,
                                    onPressed: record == null ? null : () => _restore(context, ref, record, items[i]),
                                  ),
                                ),
                                const SizedBox(width: AppSpace.sm),
                                IconButton(
                                  tooltip: context.tr('action.remove'),
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () async {
                                    final ok = await confirmAction(
                                      context,
                                      title: context.tr('backups.deleteTitle'),
                                      message: context.tr('backups.deleteBody', args: {'name': items[i].name}),
                                      confirmLabel: context.tr('action.remove'),
                                      destructive: true,
                                    );
                                    if (!ok || !context.mounted) {
                                      return;
                                    }
                                    await guardedAction(context, ref, () => ref.read(serverActionsProvider).deleteBackup(items[i]), successKey: 'backups.deleted');
                                    ref.invalidate(backupsProvider(serverId));
                                  },
                                ),
                              ],
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
  }

  Future<void> _restore(BuildContext context, WidgetRef ref, ServerRecord record, BackupEntry backup) async {
    final ok = await confirmAction(
      context,
      title: context.tr('backups.restoreTitle'),
      message: context.tr('backups.restoreBody'),
      confirmLabel: context.tr('backups.restore'),
      destructive: true,
    );
    if (!ok || !context.mounted) {
      return;
    }
    await guardedAction(context, ref, () => ref.read(serverActionsProvider).restoreBackup(record, backup), successKey: 'backups.restoreQueued');
  }

  Future<void> _importWorld(BuildContext context, WidgetRef ref, ServerRecord record) async {
    const type = XTypeGroup(label: 'zip', extensions: <String>['zip']);
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[type]);
    if (file == null || !context.mounted) {
      return;
    }
    final ok = await confirmAction(
      context,
      title: context.tr('backups.importTitle'),
      message: context.tr('backups.importBody'),
      confirmLabel: context.tr('backups.importWorld'),
      destructive: true,
    );
    if (!ok || !context.mounted) {
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
