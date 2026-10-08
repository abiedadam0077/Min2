import 'package:flutter/material.dart';
import '../../state/core_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../domain/integration_models.dart';
import '../../domain/server_models.dart';
import '../../state/server_providers.dart';
import '../shared/server_ui.dart';

class ServerDashboardPage extends ConsumerWidget {
  const ServerDashboardPage({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = serverById(ref.watch(serverRegistryProvider), serverId);
    if (record == null) {
      return AppPage(title: context.tr('dashboard.missing'), children: [EmptyState(icon: Icons.search_off_rounded, title: context.tr('dashboard.missing'))]);
    }
    final statusAsync = ref.watch(serverStatusProvider(record.id));
    final status = statusAsync.value ?? ServerStatus.offline();
    final running = status.state == ServerState.running;
    final busy = status.state == ServerState.starting || status.state == ServerState.stopping || status.state == ServerState.restarting;
    final tailscale = ref.watch(tailscaleDeviceProvider(record.id));
    final runs = ref.watch(workflowRunsProvider(record.id));
    final ip = status.tailscaleIp ?? tailscale.value?.ipv4;
    final theme = Theme.of(context);
    return AppPage(
      title: record.name,
      actions: [
        IconButton(tooltip: context.tr('dashboard.files'), icon: const Icon(Icons.folder_open_rounded), onPressed: () => context.push('/server/${record.id}/files')),
        IconButton(tooltip: context.tr('dashboard.settings'), icon: const Icon(Icons.tune_rounded), onPressed: () => context.push('/server/${record.id}/settings')),
      ],
      onRefresh: () async {
        ref.invalidate(serverStatusProvider(record.id));
        ref.invalidate(workflowRunsProvider(record.id));
      },
      children: [
        GlassCard(
          highlighted: running,
          accent: AppColors.success,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(context.tr('dashboard.status'), style: theme.textTheme.titleSmall)),
                  ServerStateChip(state: status.state),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              InfoLine(label: context.tr('dashboard.players'), value: '${status.players}/${status.maxPlayers}'),
              InfoLine(label: context.tr('dashboard.uptime'), value: status.uptimeSeconds == null ? '-' : formatDuration(Duration(seconds: status.uptimeSeconds!))),
              InfoLine(label: context.tr('dashboard.version'), value: '${record.software.label} ${record.minecraftVersion}'),
              InfoLine(label: context.tr('dashboard.lastSync'), value: formatRelative(context, status.lastSyncAt ?? record.lastSyncAt)),
              if (status.isStale && running)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.sm),
                  child: Text(context.tr('dashboard.stale'), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
                ),
              if (status.lastError != null && status.lastError!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.sm),
                  child: Text(status.lastError!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger)),
                ),
            ],
          ),
        ),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('dashboard.connect'), style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpace.sm),
              InfoLine(label: context.tr('dashboard.tailscaleIp'), value: ip ?? context.tr('dashboard.notReported'), icon: Icons.hub_outlined),
              InfoLine(label: context.tr('dashboard.hostname'), value: record.tailscaleHostname ?? '-', icon: Icons.label_outline_rounded),
              if (ip != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: ip));
                      if (context.mounted) {
                        showAppSnack(context, context.tr('common.copied'));
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(context.tr('dashboard.copyAddress')),
                  ),
                ),
            ],
          ),
        ),
        _ActionsCard(record: record, state: status.state, runs: runs),
        _Controls(record: record, running: running, busy: busy, status: status),
        SectionTitle(title: context.tr('dashboard.actions')),
        Row(
          children: [
            Expanded(child: SecondaryButton(label: context.tr('dashboard.console'), icon: Icons.terminal_rounded, onPressed: () => context.go('/console'))),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: SecondaryButton(label: context.tr('dashboard.backups'), icon: Icons.history_rounded, onPressed: () => context.push('/server/${record.id}/backups'))),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Row(
          children: [
            Expanded(child: SecondaryButton(label: context.tr('dashboard.mods'), icon: Icons.extension_rounded, onPressed: () => context.go('/content'))),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: SecondaryButton(
                label: context.tr('dashboard.openDrive'),
                icon: Icons.cloud_outlined,
                onPressed: () => launchUrl(Uri.parse('https://drive.google.com/drive/folders/${record.driveFolderId}'), mode: LaunchMode.externalApplication),
              ),
            ),
          ],
        ),
        SectionTitle(title: context.tr('dashboard.workflow')),
        runs.when(
          data: (items) => items.isEmpty
              ? GlassCard(child: Text(context.tr('dashboard.noRuns'), style: theme.textTheme.bodyMedium))
              : Column(
                  children: [
                    for (final run in items.take(6))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpace.sm),
                        child: GlassCard(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                          onTap: run.htmlUrl.isEmpty ? null : () => launchUrl(Uri.parse(run.htmlUrl), mode: LaunchMode.externalApplication),
                          child: Row(
                            children: [
                              Icon(_runIcon(run), color: _runColor(run)),
                              const SizedBox(width: AppSpace.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('#${run.runNumber} · ${run.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                                    Text(
                                      '${run.conclusion ?? run.status} · ${formatRelative(context, run.createdAt)}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.open_in_new_rounded, size: 18),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
          loading: () => const SkeletonList(count: 2, height: 64),
          error: (error, _) => GlassCard(child: Text(describeError(context, error), style: theme.textTheme.bodySmall)),
        ),
        const SizedBox(height: AppSpace.lg),
        SecondaryButton(
          label: context.tr('dashboard.forgetLocal'),
          icon: Icons.phonelink_erase_rounded,
          danger: true,
          onPressed: () async {
            final ok = await confirmAction(
              context,
              title: context.tr('dashboard.forgetTitle'),
              message: context.tr('dashboard.forgetBody'),
              confirmLabel: context.tr('dashboard.forgetAction'),
              destructive: true,
            );
            if (ok) {
              await ref.read(serverRegistryProvider.notifier).forgetLocally(record.id);
              if (context.mounted) {
                context.go('/servers');
              }
            }
          },
        ),
      ],
    );
  }

  IconData _runIcon(GitHubRun run) => run.conclusion == 'success'
      ? Icons.check_circle_rounded
      : run.conclusion == null
          ? Icons.autorenew_rounded
          : Icons.error_outline_rounded;

  Color _runColor(GitHubRun run) => run.conclusion == 'success'
      ? AppColors.success
      : run.conclusion == null
          ? AppColors.info
          : AppColors.danger;
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.record, required this.running, required this.busy, required this.status});

  final ServerRecord record;
  final bool running;
  final bool busy;
  final ServerStatus status;

  Future<void> _confirmed(BuildContext context, WidgetRef ref, {required String command, required String title, required String body, required String label, bool destructive = false}) async {
    final ok = await confirmAction(context, title: title, message: body, confirmLabel: label, destructive: destructive);
    if (!ok || !context.mounted) {
      return;
    }
    await guardedAction(context, ref, () => ref.read(serverActionsProvider).sendCommand(record, command), successKey: 'dashboard.commandQueued');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!running && !busy) {
      return PrimaryButton(
        label: context.tr('action.start'),
        icon: Icons.play_arrow_rounded,
        onPressed: () => guardedAction(context, ref, () => ref.read(serverActionsProvider).startServer(record), successKey: 'dashboard.startQueued'),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: context.tr('action.restart'),
                icon: Icons.restart_alt_rounded,
                onPressed: () => _confirmed(
                  context,
                  ref,
                  command: 'restart',
                  title: context.tr('dashboard.restartTitle'),
                  body: context.tr('dashboard.restartBody'),
                  label: context.tr('action.restart'),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: PrimaryButton(
                label: context.tr('action.stop'),
                icon: Icons.stop_rounded,
                onPressed: () => _confirmed(
                  context,
                  ref,
                  command: 'stop',
                  title: context.tr('dashboard.stopTitle'),
                  body: context.tr('dashboard.stopBody'),
                  label: context.tr('action.stop'),
                  destructive: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        SecondaryButton(
          label: context.tr('action.kill'),
          icon: Icons.bolt_rounded,
          danger: true,
          onPressed: () async {
            final ok = await confirmAction(
              context,
              title: context.tr('dashboard.killTitle'),
              message: context.tr('dashboard.killBody'),
              confirmLabel: context.tr('action.kill'),
              destructive: true,
            );
            if (!ok || !context.mounted) {
              return;
            }
            await guardedAction(context, ref, () async {
              await ref.read(serverActionsProvider).sendCommand(record, 'kill');
              await Future<void>.delayed(const Duration(seconds: 45));
              final latest = await ref.read(serverActionsProvider).readStatus(record);
              if (latest.state != ServerState.offline) {
                await ref.read(serverActionsProvider).forceCancelActiveRun(record);
              }
            }, successKey: 'dashboard.killQueued');
          },
        ),
      ],
    );
  }
}

/// GitHub Actions status for this server: Ready, Running, Queued, Stopping or Not started,
/// with links to the workflow and to the logs of the latest run. Start, stop and restart are below.
class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.record, required this.state, required this.runs});

  final ServerRecord record;
  final ServerState state;
  final AsyncValue<List<GitHubRun>> runs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = runs.value ?? const <GitHubRun>[];
    final latest = items.isEmpty ? null : items.first;
    final repoBase = 'https://github.com/${record.repoOwner}/${record.repoName}';
    final workflowUrl = Uri.parse('$repoBase/actions/workflows/${AppConfig.workflowFileName}');
    final logsUrl = (latest != null && latest.htmlUrl.isNotEmpty) ? Uri.parse(latest.htmlUrl) : Uri.parse('$repoBase/actions');

    final String label;
    final Color color;
    if (state == ServerState.stopping) {
      label = context.tr('actions.stopping');
      color = AppColors.warning;
    } else if (latest == null) {
      label = context.tr('actions.notStarted');
      color = AppColors.textMuted;
    } else if (latest.isActive) {
      final queued = latest.status == 'queued' || latest.status == 'waiting' || latest.status == 'pending' || latest.status == 'requested';
      label = queued ? context.tr('actions.queued') : context.tr('actions.running');
      color = queued ? AppColors.warning : AppColors.success;
    } else {
      label = context.tr('actions.ready');
      color = AppColors.primary;
    }

    return GlassCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.play_circle_outline_rounded, color: color),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(context.tr('actions.title'), style: theme.textTheme.titleSmall)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: AppRadius.all(AppRadius.pill)),
                child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(context.tr('actions.runner'), style: theme.textTheme.bodySmall),
          if (latest != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text('#${latest.runNumber} · ${latest.title}', style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: context.tr('actions.viewWorkflow'),
                  icon: Icons.account_tree_outlined,
                  onPressed: () => launchUrl(workflowUrl, mode: LaunchMode.externalApplication),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: SecondaryButton(
                  label: context.tr('actions.viewLogs'),
                  icon: Icons.receipt_long_outlined,
                  onPressed: () => launchUrl(logsUrl, mode: LaunchMode.externalApplication),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
