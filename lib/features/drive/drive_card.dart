import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../state/auth_providers.dart';
import '../../state/drive_providers.dart';
import '../../state/drive_storage_providers.dart';
import '../../state/server_providers.dart';

/// Compact Google Drive status card: connection, account, Server Storage, sync badge and usage.
class DriveCard extends ConsumerWidget {
  const DriveCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final google = ref.watch(googleAccountProvider);
    final storage = ref.watch(driveStorageProvider);
    final theme = Theme.of(context);
    final account = google.value;
    final connected = account != null;
    final busy = google.isLoading;
    final failed = google.hasError && !busy && !connected;
    final active = ref.watch(activeServerProvider);

    final String statusLabel;
    final Color statusColor;
    if (busy) {
      statusLabel = context.tr('drive.connecting');
      statusColor = AppColors.primary;
    } else if (connected) {
      statusLabel = context.tr('drive.connected');
      statusColor = AppColors.success;
    } else if (failed) {
      statusLabel = context.tr('drive.needsAttention');
      statusColor = AppColors.warning;
    } else {
      statusLabel = context.tr('drive.required');
      statusColor = AppColors.primary;
    }

    return GlassCard(
      highlighted: connected,
      accent: connected ? AppColors.success : AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Badge(icon: Icons.cloud_done_outlined, color: statusColor),
              const SizedBox(width: AppSpace.md),
              Expanded(child: Text(context.tr('drive.title'), style: theme.textTheme.titleMedium)),
              _Pill(label: statusLabel, color: statusColor),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (connected) ...[
            Text(account.email, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpace.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${context.tr('drive.storage')}: ${storage?.name ?? context.tr('drive.storageNotSet')}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (storage != null) _Pill(label: context.tr('drive.synced'), color: AppColors.success, icon: Icons.check_rounded),
              ],
            ),
            if (active != null) ...[
              const SizedBox(height: AppSpace.sm),
              _UsageLine(serverId: active.id),
            ],
          ] else if (failed) ...[
            Text(context.tr('drive.failedTitle'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpace.xs),
            Text(context.tr('drive.failedBody'), style: theme.textTheme.bodySmall),
          ] else
            Text(context.tr('drive.body'), style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                : connected
                    ? _footerConnected(context, storageMissing: storage == null)
                    : PrimaryButton(
                        label: failed ? context.tr('action.retry') : context.tr('action.connect'),
                        icon: Icons.link_rounded,
                        onPressed: () => connectDrive(context, ProviderScope.containerOf(context)),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _footerConnected(BuildContext context, {required bool storageMissing}) {
    if (storageMissing) {
      return SecondaryButton(
        label: context.tr('drive.chooseStorage'),
        icon: Icons.folder_open_rounded,
        onPressed: () => context.push('/drive/storage'),
      );
    }
    return SecondaryButton(
      label: context.tr('action.manage'),
      icon: Icons.tune_rounded,
      onPressed: () => showDriveManageSheet(context),
    );
  }
}

/// Starts Google sign-in. On success the Server Storage screen opens when no storage is chosen yet.
Future<void> connectDrive(BuildContext context, ProviderContainer container) async {
  await container.read(googleAccountProvider.notifier).connect();
  if (!context.mounted) {
    return;
  }
  final state = container.read(googleAccountProvider);
  if (state.hasError) {
    showAppSnack(context, describeError(context, state.error!), isError: true);
    return;
  }
  if (state.value != null && container.read(driveStorageProvider) == null) {
    context.push('/drive/storage');
  }
}

Future<void> showDriveManageSheet(BuildContext context) {
  final container = ProviderScope.containerOf(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DriveManageSheet(host: context, container: container),
  );
}

class _DriveManageSheet extends StatelessWidget {
  const _DriveManageSheet({required this.host, required this.container});

  /// Context of the page that opened the sheet. It stays mounted after the sheet closes.
  final BuildContext host;
  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    final google = container.read(googleAccountProvider);
    final storage = container.read(driveStorageProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('drive.title'), style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpace.sm),
            Text(google.value?.email ?? context.tr('drive.body'), style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpace.xs),
            Text(
              '${context.tr('drive.storage')}: ${storage?.name ?? context.tr('drive.storageNotSet')}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpace.lg),
            SecondaryButton(
              label: context.tr('drive.changeStorage'),
              icon: Icons.folder_open_rounded,
              onPressed: () {
                final router = GoRouter.of(host);
                Navigator.of(context).pop();
                router.push('/drive/storage');
              },
            ),
            const SizedBox(height: AppSpace.sm),
            SecondaryButton(
              label: context.tr('drive.checkConnection'),
              icon: Icons.sync_rounded,
              onPressed: () async {
                final messenger = ScaffoldMessenger.maybeOf(host);
                final okMessage = context.tr('drive.connectionOk');
                final failMessage = context.tr('drive.reconnectNeeded');
                try {
                  await container.read(googleAccountProvider.notifier).verify();
                  container.invalidate(driveQuotaProvider);
                  messenger?.showSnackBar(SnackBar(content: Text(okMessage)));
                } on Object {
                  messenger?.showSnackBar(SnackBar(content: Text(failMessage)));
                }
              },
            ),
            const SizedBox(height: AppSpace.sm),
            SecondaryButton(
              label: context.tr('drive.reconnect'),
              icon: Icons.link_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                connectDrive(host, container);
              },
            ),
            const SizedBox(height: AppSpace.sm),
            SecondaryButton(
              label: context.tr('drive.disconnect'),
              icon: Icons.link_off_rounded,
              danger: true,
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: context.tr('accounts.disconnectDriveTitle'),
                  message: context.tr('accounts.disconnectDriveBody'),
                  confirmLabel: context.tr('accounts.disconnect'),
                  destructive: true,
                );
                if (!ok) {
                  return;
                }
                await container.read(googleAccountProvider.notifier).disconnect();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// "Worlds • Files • Mods • Backups" for the active server, read from Drive.
class _UsageLine extends ConsumerWidget {
  const _UsageLine({required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(driveUsageProvider(serverId));
    final style = Theme.of(context).textTheme.labelMedium;
    return usage.when(
      loading: () => Text(context.tr('common.loading'), style: style),
      error: (error, _) => Text(describeError(context, error), style: style),
      data: (value) => Text(
        context.tr('drive.usage', args: {
          'worlds': value.worlds,
          'files': value.files,
          'mods': value.mods,
          'backups': value.backups,
        }),
        style: style,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: AppRadius.all(AppRadius.md)),
      child: Icon(icon, color: color),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: AppRadius.all(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: AppSpace.xs)],
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}
