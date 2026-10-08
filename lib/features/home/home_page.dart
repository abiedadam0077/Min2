import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../domain/integration_models.dart';
import '../../domain/server_models.dart';
import '../../state/app_providers.dart';
import '../../state/auth_providers.dart';
import '../../state/core_providers.dart';
import '../../state/server_providers.dart';
import '../shared/server_ui.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final github = ref.watch(githubAccountsProvider).active;
    final servers = ref.watch(serverRegistryProvider);
    final active = ref.watch(activeServerProvider);
    final notifications = ref.watch(notificationsProvider).length;
    return AppPage(
      title: context.tr('home.title'),
      inShell: true,
      onRefresh: () async {
        ref.invalidate(driveQuotaProvider);
        if (active != null) {
          ref.invalidate(workflowRunsProvider(active.id));
          ref.invalidate(serverStatusProvider(active.id));
        }
      },
      actions: [
        IconButton(
          tooltip: context.tr('notifications.title'),
          onPressed: () => context.push('/notifications'),
          icon: Badge.count(
            count: notifications,
            isLabelVisible: notifications > 0,
            child: const Icon(Icons.notifications_none_rounded),
          ),
        ),
      ],
      children: [
        if (github != null)
          FadeSlideIn(
            child: GlassCard(
              child: Row(
                children: [
                  AvatarImage(url: github.avatarUrl, fallback: github.login, size: 48),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('home.greeting', args: {'name': github.name ?? github.login}), style: Theme.of(context).textTheme.titleMedium),
                        Text(context.tr('home.subtitle'), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (servers.isEmpty)
          FadeSlideIn(
            index: 1,
            child: EmptyState(
              icon: Icons.add_home_work_outlined,
              title: context.tr('home.empty.title'),
              message: context.tr('home.empty.body'),
              action: Column(
                children: [
                  PrimaryButton(label: context.tr('home.empty.create'), icon: Icons.add_rounded, onPressed: () => context.push('/wizard')),
                  const SizedBox(height: AppSpace.sm),
                  SecondaryButton(label: context.tr('home.empty.import'), icon: Icons.cloud_download_outlined, onPressed: () => context.push('/import')),
                ],
              ),
            ),
          )
        else if (active != null) ...[
          SectionTitle(title: context.tr('home.activeServer')),
          _ActiveServerPanel(record: active),
        ],
        if (servers.length > 1) ...[
          SectionTitle(title: context.tr('home.otherServers')),
          for (final record in servers.where((s) => s.id != active?.id))
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: ServerSummaryCard(record: record, status: null, onTap: () => openServer(context, ref, record)),
            ),
        ],
        SectionTitle(title: context.tr('home.drive')),
        _DriveQuotaCard(),
      ],
    );
  }
}

class _ActiveServerPanel extends ConsumerWidget {
  const _ActiveServerPanel({required this.record});

  final ServerRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider(record.id));
    final current = status.value ?? ServerStatus.offline();
    final runs = ref.watch(workflowRunsProvider(record.id));
    final running = current.state == ServerState.running || current.state == ServerState.starting;
    return Column(
      children: [
        FadeSlideIn(
          child: ServerSummaryCard(record: record, status: current, highlighted: running, onTap: () => openServer(context, ref, record)),
        ),
        const SizedBox(height: AppSpace.md),
        FadeSlideIn(
          index: 1,
          child: Row(
            children: [
              Expanded(
                child: running
                    ? SecondaryButton(
                        label: context.tr('action.stop'),
                        icon: Icons.stop_rounded,
                        danger: true,
                        onPressed: () async {
                          final ok = await confirmAction(
                            context,
                            title: context.tr('dashboard.stopTitle'),
                            message: context.tr('dashboard.stopBody'),
                            confirmLabel: context.tr('action.stop'),
                            destructive: true,
                          );
                          if (ok && context.mounted) {
                            await guardedAction(context, ref, () => ref.read(serverActionsProvider).sendCommand(record, 'stop'), successKey: 'dashboard.stopQueued');
                          }
                        },
                      )
                    : PrimaryButton(
                        label: context.tr('action.start'),
                        icon: Icons.play_arrow_rounded,
                        onPressed: () => guardedAction(context, ref, () => ref.read(serverActionsProvider).startServer(record), successKey: 'dashboard.startQueued'),
                      ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: SecondaryButton(
                  label: context.tr('action.backup'),
                  icon: Icons.backup_rounded,
                  onPressed: () => guardedAction(context, ref, () => ref.read(serverActionsProvider).createBackup(record), successKey: 'dashboard.backupQueued'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        FadeSlideIn(
          index: 2,
          child: GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width >= AppBreakpoints.medium ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpace.md,
            crossAxisSpacing: AppSpace.md,
            childAspectRatio: 1.25,
            children: [
              MetricCard(
                icon: Icons.groups_2_outlined,
                label: context.tr('dashboard.players'),
                value: '${current.players}/${current.maxPlayers}',
                progress: current.maxPlayers == 0 ? null : current.players / current.maxPlayers,
              ),
              MetricCard(
                icon: Icons.memory_rounded,
                label: context.tr('dashboard.cpu'),
                value: current.cpuPercent == null ? '-' : '${current.cpuPercent!.toStringAsFixed(0)}%',
                progress: current.cpuPercent == null ? null : current.cpuPercent! / 100,
                color: AppColors.cyan,
              ),
              MetricCard(
                icon: Icons.sd_storage_rounded,
                label: context.tr('dashboard.ram'),
                value: current.ramUsedMb == null ? '-' : '${current.ramUsedMb} MB',
                progress: (current.ramUsedMb == null || current.ramTotalMb == null || current.ramTotalMb == 0)
                    ? null
                    : current.ramUsedMb! / current.ramTotalMb!,
                color: AppColors.violet,
              ),
              MetricCard(
                icon: Icons.backup_outlined,
                label: context.tr('dashboard.lastBackup'),
                value: formatRelative(context, current.lastBackupAt ?? record.lastBackupAt),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        runs.when(
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('home.recentRuns'), style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: AppSpace.sm),
                      for (final run in items.take(3))
                        InfoLine(
                          label: '#${run.runNumber}',
                          value: '${run.conclusion ?? run.status} · ${formatRelative(context, run.createdAt)}',
                          icon: Icons.play_circle_outline_rounded,
                        ),
                    ],
                  ),
                ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _DriveQuotaCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(driveQuotaProvider);
    return quota.when(
      data: (DriveQuota q) => MetricCard(
        icon: Icons.cloud_outlined,
        label: context.tr('home.driveUsage'),
        value: formatBytes(q.usedBytes),
        progress: q.limitBytes == null || q.limitBytes == 0 ? null : q.usedBytes / q.limitBytes!,
        caption: q.email,
        color: AppColors.info,
      ),
      loading: () => const SkeletonList(count: 1, height: 96),
      error: (error, _) => GlassCard(
        child: Text(describeError(context, error), style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
