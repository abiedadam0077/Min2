import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../domain/server_models.dart';
import '../../state/core_providers.dart';
import '../../state/server_providers.dart';
import '../create/repo_picker_page.dart';
import '../shared/server_ui.dart';

class ServerSettingsPage extends ConsumerStatefulWidget {
  const ServerSettingsPage({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ServerSettingsPage> createState() => _ServerSettingsPageState();
}

class _ServerSettingsPageState extends ConsumerState<ServerSettingsPage> {
  final _motd = TextEditingController();
  final _seed = TextEditingController();
  ServerSettings? _settings;
  RuntimeSettings? _runtime;
  bool _saving = false;

  @override
  void dispose() {
    _motd.dispose();
    _seed.dispose();
    super.dispose();
  }

  void _syncFrom(ServerSettings value) {
    if (_settings != null) {
      return;
    }
    _settings = value;
    _motd.text = value.motd;
    _seed.text = value.levelSeed;
  }

  Future<void> _saveServer(ServerRecord record) async {
    final current = (_settings ?? const ServerSettings()).copyWith(
      motd: _motd.text.trim().isEmpty ? 'A VoxelOps server' : _motd.text.trim(),
      levelSeed: _seed.text.trim(),
    );
    setState(() => _saving = true);
    await guardedAction(context, ref, () => ref.read(serverActionsProvider).writeSettings(record, current), successKey: 'settings.saved');
    if (mounted) {
      setState(() {
        _saving = false;
        _settings = current;
      });
    }
  }

  Future<void> _saveRuntime(ServerRecord record) async {
    final runtime = _runtime;
    if (runtime == null) {
      return;
    }
    await guardedAction(context, ref, () => ref.read(serverActionsProvider).writeRuntime(record, runtime), successKey: 'settings.saved');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = serverById(ref.watch(serverRegistryProvider), widget.serverId);
    if (record == null) {
      return AppPage(title: context.tr('dashboard.missing'), children: const []);
    }
    final settingsAsync = ref.watch(serverSettingsProvider(record.id));
    final runtimeAsync = ref.watch(runtimeSettingsProvider(record.id));
    final theme = Theme.of(context);
    return AppPage(
      title: context.tr('settings.title'),
      children: [
        SectionTitle(title: context.tr('settings.serverSection'), subtitle: context.tr('settings.appliedOnRestart')),
        AsyncBody<ServerSettings>(
          value: settingsAsync,
          builder: (context, value) {
            _syncFrom(value);
            final s = _settings!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: _motd, decoration: InputDecoration(labelText: context.tr('settings.motd'))),
                const SizedBox(height: AppSpace.md),
                InfoLine(label: context.tr('settings.maxPlayers'), value: '${s.maxPlayers}'),
                ValueStepper(value: s.maxPlayers, min: 1, max: 500, step: 5, onChanged: (v) => setState(() => _settings = s.copyWith(maxPlayers: v))),
                const SizedBox(height: AppSpace.md),
                Text(context.tr('settings.gamemode'), style: theme.textTheme.labelMedium),
                const SizedBox(height: AppSpace.sm),
                OptionChips<String>(
                  options: const <String>['survival', 'creative', 'adventure', 'spectator'],
                  selected: s.gamemode,
                  label: (v) => context.tr('gamemode.$v'),
                  onSelected: (v) => setState(() => _settings = s.copyWith(gamemode: v)),
                ),
                const SizedBox(height: AppSpace.md),
                Text(context.tr('settings.difficulty'), style: theme.textTheme.labelMedium),
                const SizedBox(height: AppSpace.sm),
                OptionChips<String>(
                  options: const <String>['peaceful', 'easy', 'normal', 'hard'],
                  selected: s.difficulty,
                  label: (v) => context.tr('difficulty.$v'),
                  onSelected: (v) => setState(() => _settings = s.copyWith(difficulty: v)),
                ),
                SettingSwitch(
                  title: context.tr('settings.onlineMode'),
                  subtitle: context.tr('settings.onlineModeHint'),
                  value: s.onlineMode,
                  onChanged: (v) => setState(() => _settings = s.copyWith(onlineMode: v)),
                ),
                SettingSwitch(title: context.tr('settings.pvp'), value: s.pvp, onChanged: (v) => setState(() => _settings = s.copyWith(pvp: v))),
                SettingSwitch(title: context.tr('settings.whitelist'), value: s.whitelist, onChanged: (v) => setState(() => _settings = s.copyWith(whitelist: v))),
                SettingSwitch(title: context.tr('settings.nether'), value: s.allowNether, onChanged: (v) => setState(() => _settings = s.copyWith(allowNether: v))),
                SettingSwitch(title: context.tr('settings.commandBlocks'), value: s.commandBlocks, onChanged: (v) => setState(() => _settings = s.copyWith(commandBlocks: v))),
                const SizedBox(height: AppSpace.sm),
                TextField(controller: _seed, decoration: InputDecoration(labelText: context.tr('settings.seed'), helperText: context.tr('settings.seedHint'))),
                const SizedBox(height: AppSpace.md),
                PrimaryButton(label: context.tr('action.save'), icon: Icons.save_rounded, busy: _saving, onPressed: _saving ? null : () => _saveServer(record)),
              ],
            );
          },
        ),
        SectionTitle(title: context.tr('settings.runtimeSection'), subtitle: context.tr('settings.runtimeHint')),
        AsyncBody<RuntimeSettings>(
          value: runtimeAsync,
          builder: (context, value) {
            final r = _runtime ?? value;
            _runtime ??= value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoLine(label: context.tr('runtime.memory'), value: '${r.memoryMb} MB'),
                ValueStepper(value: r.memoryMb, min: 1024, max: 8192, step: 512, onChanged: (v) => setState(() => _runtime = r.copyWith(memoryMb: v))),
                const SizedBox(height: AppSpace.md),
                Text(context.tr('runtime.syncInterval'), style: theme.textTheme.labelMedium),
                const SizedBox(height: AppSpace.sm),
                OptionChips<int>(
                  options: const <int>[5, 10, 15, 30],
                  selected: r.syncIntervalMinutes,
                  label: (v) => context.tr('runtime.everyMinutes', args: {'n': v}),
                  onSelected: (v) => setState(() => _runtime = r.copyWith(syncIntervalMinutes: v)),
                ),
                const SizedBox(height: AppSpace.md),
                Text(context.tr('runtime.backupInterval'), style: theme.textTheme.labelMedium),
                const SizedBox(height: AppSpace.sm),
                OptionChips<int>(
                  options: const <int>[60, 180, 360],
                  selected: r.backupIntervalMinutes,
                  label: (v) => context.tr('runtime.everyMinutes', args: {'n': v}),
                  onSelected: (v) => setState(() => _runtime = r.copyWith(backupIntervalMinutes: v)),
                ),
                InfoLine(label: context.tr('runtime.retention'), value: '${r.backupRetention}'),
                ValueStepper(value: r.backupRetention, min: 1, max: 30, step: 1, onChanged: (v) => setState(() => _runtime = r.copyWith(backupRetention: v))),
                SettingSwitch(
                  title: context.tr('runtime.autoContinue'),
                  subtitle: context.tr('runtime.autoContinueHint'),
                  value: r.autoContinue,
                  onChanged: (v) => setState(() => _runtime = r.copyWith(autoContinue: v)),
                ),
                const SizedBox(height: AppSpace.sm),
                PrimaryButton(label: context.tr('settings.saveRuntime'), icon: Icons.save_rounded, onPressed: () => _saveRuntime(record)),
              ],
            );
          },
        ),
        SectionTitle(title: context.tr('settings.repoSection')),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoLine(label: context.tr('settings.repo'), value: record.repoFullName, icon: Icons.code_rounded),
              InfoLine(label: context.tr('settings.workflow'), value: '.github/workflows/voxelops-server.yml', icon: Icons.account_tree_outlined),
              const SizedBox(height: AppSpace.md),
              SecondaryButton(
                label: context.tr('settings.refreshRepo'),
                icon: Icons.sync_rounded,
                onPressed: () => guardedAction(context, ref, () => ref.read(serverProvisionerProvider).refreshRepository(record), successKey: 'settings.refreshed'),
              ),
              const SizedBox(height: AppSpace.sm),
              SecondaryButton(
                label: context.tr('settings.attachRepo'),
                icon: Icons.swap_horiz_rounded,
                onPressed: () async {
                  final selection = await context.push<RepoSelection>('/repos?mode=attach');
                  if (selection == null || selection.create || !context.mounted) {
                    return;
                  }
                  await guardedAction(context, ref, () async {
                    final updated = await ref.read(serverProvisionerProvider).attachToRepository(
                          driveFolderId: record.driveFolderId,
                          repoOwner: selection.owner,
                          repoName: selection.name,
                        );
                    await ref.read(serverRegistryProvider.notifier).upsert(updated);
                  }, successKey: 'settings.attached');
                },
              ),
              const SizedBox(height: AppSpace.sm),
              Text(context.tr('settings.tailscaleNote'), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        if (settingsAsync.hasError || runtimeAsync.hasError)
          GlassCard(
            accent: AppColors.danger,
            child: Text(
              describeError(context, settingsAsync.error ?? runtimeAsync.error ?? const AppException(AppErrorKind.unknown, 'settings')),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
