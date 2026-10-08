import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../data/minecraft/server_icon.dart';
import '../../domain/server_draft.dart';
import '../../domain/server_models.dart';
import '../../state/core_providers.dart';
import '../../state/create_providers.dart';
import '../../state/server_providers.dart';
import '../../state/auth_providers.dart';
import 'repo_picker_page.dart';

/// Resolves the exact loader build for the review step (cached per software + version).
final buildPreviewProvider = FutureProvider.autoDispose.family<ResolvedBuild, ({ServerSoftware software, String version})>((ref, args) {
  return ref.read(versionCatalogProvider).resolve(args.software, args.version);
});

class CreateServerPage extends ConsumerStatefulWidget {
  const CreateServerPage({super.key});

  @override
  ConsumerState<CreateServerPage> createState() => _CreateServerPageState();
}

class _CreateServerPageState extends ConsumerState<CreateServerPage> {
  static const List<String> _steps = <String>['software', 'version', 'details', 'settings', 'repository', 'review'];

  int _step = 0;
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _motd = TextEditingController();
  final _seed = TextEditingController();
  final _versionSearch = TextEditingController();
  String _channel = 'release';
  String? _error;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(serverDraftProvider);
    _name.text = draft.name;
    _description.text = draft.description;
    _motd.text = draft.settings.motd;
    _seed.text = draft.settings.levelSeed;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _motd.dispose();
    _seed.dispose();
    _versionSearch.dispose();
    super.dispose();
  }

  ServerDraft get _draft => ref.read(serverDraftProvider);

  void _update(ServerDraft Function(ServerDraft) change) {
    ref.read(serverDraftProvider.notifier).update(change);
    setState(() => _error = null);
  }

  String? _validate(ServerDraft draft) {
    switch (_steps[_step]) {
      case 'version':
        return draft.minecraftVersion.isEmpty ? context.tr('create.validation.version') : null;
      case 'details':
        final name = _name.text.trim();
        if (name.length < 3 || name.length > 40) {
          return context.tr('create.validation.name');
        }
        return null;
      case 'settings':
        return draft.settings.maxPlayers < 1 ? context.tr('create.validation.players') : null;
      case 'repository':
        if (draft.repoFullName.isEmpty) {
          return context.tr('create.validation.repo');
        }
        if (!draft.eulaAccepted || !draft.githubRiskAccepted) {
          return context.tr('create.validation.consent');
        }
        return null;
      default:
        return null;
    }
  }

  void _next() {
    _commitText();
    final message = _validate(_draft);
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    if (_step < _steps.length - 1) {
      setState(() {
        _step++;
        _error = null;
      });
    }
  }

  void _back() {
    if (_step == 0) {
      context.pop();
      return;
    }
    setState(() {
      _step--;
      _error = null;
    });
  }

  void _commitText() {
    _update((d) => d.copyWith(
          name: _name.text.trim(),
          description: _description.text.trim(),
          settings: d.settings.copyWith(motd: _motd.text.trim().isEmpty ? 'A VoxelOps server' : _motd.text.trim(), levelSeed: _seed.text.trim()),
        ));
  }

  Future<void> _pickIcon() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 90);
      if (picked == null) {
        return;
      }
      final icon = buildServerIcon(await picked.readAsBytes());
      if (icon == null) {
        if (mounted) {
          showAppSnack(context, context.tr('create.icon.invalid'), isError: true);
        }
        return;
      }
      _update((d) => d.copyWith(iconBytes: icon));
    } on Exception {
      if (mounted) {
        showAppSnack(context, context.tr('create.icon.invalid'), isError: true);
      }
    }
  }

  Future<void> _pickRepository() async {
    _commitText();
    final selection = await context.push<RepoSelection>('/repos?mode=create');
    if (selection == null || !mounted) {
      return;
    }
    _update((d) => d.copyWith(
          repoOwner: selection.create ? (ref.read(githubAccountsProvider).active?.login ?? '') : selection.owner,
          repoName: selection.name,
          createRepository: selection.create,
          repoPrivate: selection.isPrivate,
        ));
  }

  Future<void> _create() async {
    _commitText();
    final draft = _draft;
    if (draft.repoFullName.isEmpty) {
      setState(() => _error = context.tr('create.validation.repo'));
      return;
    }
    final job = ref.read(creationJobProvider.notifier);
    context.go('/creating');
    await job.run(draft);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(serverDraftProvider);
    final isLast = _step == _steps.length - 1;
    return Scaffold(
      body: Stack(
        children: [
          AppPage(
            title: context.tr('create.title'),
            leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => context.pop()),
            children: [
              _ProgressHeader(step: _step, total: _steps.length),
              AnimatedSwitcher(
                duration: AppMotion.base,
                switchInCurve: AppMotion.enter,
                switchOutCurve: AppMotion.exit,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey<int>(_step), child: _buildStep(context, draft)),
              ),
              if (_error != null)
                GlassCard(
                  accent: AppColors.danger,
                  highlighted: true,
                  child: Text(_error!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.danger)),
                ),
              Row(
                children: [
                  Expanded(child: SecondaryButton(label: _step == 0 ? context.tr('action.cancel') : context.tr('action.back'), icon: Icons.arrow_back_rounded, onPressed: _back)),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: PrimaryButton(
                      label: isLast ? context.tr('create.createAction') : context.tr('action.next'),
                      icon: isLast ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
                      onPressed: isLast ? _create : _next,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context, ServerDraft draft) {
    switch (_steps[_step]) {
      case 'software':
        return _softwareStep(context, draft);
      case 'version':
        return _versionStep(context, draft);
      case 'details':
        return _detailsStep(context, draft);
      case 'settings':
        return _settingsStep(context, draft);
      case 'repository':
        return _repositoryStep(context, draft);
      default:
        return _reviewStep(context, draft);
    }
  }

  Widget _softwareStep(BuildContext context, ServerDraft draft) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('create.software.title'), style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpace.sm),
        Text(context.tr('create.software.body'), style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpace.md),
        for (var i = 0; i < ServerSoftware.values.length; i++)
          FadeSlideIn(
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: GlassCard(
                highlighted: draft.software == ServerSoftware.values[i],
                accent: AppColors.primary,
                onTap: () => _update((d) => d.copyWith(software: ServerSoftware.values[i], minecraftVersion: '', build: null)),
                child: Row(
                  children: [
                    Icon(_softwareIcon(ServerSoftware.values[i]), color: AppColors.primary),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ServerSoftware.values[i].label, style: theme.textTheme.titleSmall),
                          Text(context.tr('software.${ServerSoftware.values[i].runnerId}'), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (draft.software == ServerSoftware.values[i]) const Icon(Icons.check_circle_rounded, color: AppColors.success),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  IconData _softwareIcon(ServerSoftware software) => switch (software) {
        ServerSoftware.vanilla => Icons.grass_rounded,
        ServerSoftware.fabric => Icons.auto_fix_high_rounded,
        ServerSoftware.forge => Icons.hardware_rounded,
        ServerSoftware.neoforge => Icons.bolt_rounded,
        ServerSoftware.paper => Icons.description_outlined,
        ServerSoftware.purpur => Icons.auto_awesome_rounded,
        ServerSoftware.spigot => Icons.extension_outlined,
      };

  Widget _versionStep(BuildContext context, ServerDraft draft) {
    final versions = ref.watch(minecraftVersionsProvider(draft.software));
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('create.version.title'), style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpace.sm),
        Text(context.tr('create.version.body', args: {'software': draft.software.label}), style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpace.md),
        OptionChips<String>(
          options: const <String>['release', 'snapshot'],
          selected: _channel,
          label: (v) => context.tr('create.version.channel.$v'),
          onSelected: (v) => setState(() => _channel = v),
        ),
        const SizedBox(height: AppSpace.md),
        AppSearchField(controller: _versionSearch, hint: context.tr('create.version.search'), onSubmitted: (_) => setState(() {})),
        const SizedBox(height: AppSpace.md),
        AsyncBody<List<McVersion>>(
          value: versions,
          onRetry: () => ref.invalidate(minecraftVersionsProvider(draft.software)),
          builder: (context, list) {
            final query = _versionSearch.text.trim();
            final filtered = list
                .where((v) => (_channel == 'release' ? v.isStable : !v.isStable))
                .where((v) => query.isEmpty || v.id.contains(query))
                .take(120)
                .toList();
            if (filtered.isEmpty) {
              return EmptyState(icon: Icons.search_off_rounded, title: context.tr('create.version.none'));
            }
            return OptionChips<String>(
              options: filtered.map((v) => v.id).toList(),
              selected: draft.minecraftVersion.isEmpty ? null : draft.minecraftVersion,
              label: (v) => v,
              onSelected: (v) => _update((d) => d.copyWith(minecraftVersion: v, build: null)),
            );
          },
        ),
      ],
    );
  }

  Widget _detailsStep(BuildContext context, ServerDraft draft) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('create.details.title'), style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            GestureDetector(
              onTap: _pickIcon,
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppRadius.all(AppRadius.lg),
                  border: Border.all(color: AppColors.outline),
                  image: draft.iconBytes == null ? null : DecorationImage(image: MemoryImage(draft.iconBytes!), fit: BoxFit.cover),
                ),
                child: draft.iconBytes == null ? const Icon(Icons.add_photo_alternate_outlined, size: 32) : null,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('create.details.icon'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpace.xs),
                  Text(context.tr('create.details.iconHint'), style: theme.textTheme.bodySmall),
                  if (draft.iconBytes != null)
                    TextButton(
                      onPressed: () => _update((d) => d.copyWith(clearIcon: true)),
                      child: Text(context.tr('action.remove')),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        TextField(controller: _name, decoration: InputDecoration(labelText: context.tr('create.details.name'))),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _description,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: context.tr('create.details.description')),
        ),
      ],
    );
  }

  Widget _settingsStep(BuildContext context, ServerDraft draft) {
    final s = draft.settings;
    final r = draft.runtime;
    void setSettings(ServerSettings value) => _update((d) => d.copyWith(settings: value));
    void setRuntime(RuntimeSettings value) => _update((d) => d.copyWith(runtime: value));
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('create.settings.title'), style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpace.md),
        TextField(controller: _motd, decoration: InputDecoration(labelText: context.tr('settings.motd'))),
        const SizedBox(height: AppSpace.md),
        InfoLine(label: context.tr('settings.maxPlayers'), value: '${s.maxPlayers}'),
        ValueStepper(value: s.maxPlayers, min: 1, max: 500, step: 5, onChanged: (v) => setSettings(s.copyWith(maxPlayers: v))),
        const SizedBox(height: AppSpace.md),
        Text(context.tr('settings.gamemode'), style: theme.textTheme.labelMedium),
        const SizedBox(height: AppSpace.sm),
        OptionChips<String>(
          options: const <String>['survival', 'creative', 'adventure'],
          selected: s.gamemode,
          label: (v) => context.tr('gamemode.$v'),
          onSelected: (v) => setSettings(s.copyWith(gamemode: v)),
        ),
        const SizedBox(height: AppSpace.md),
        Text(context.tr('settings.difficulty'), style: theme.textTheme.labelMedium),
        const SizedBox(height: AppSpace.sm),
        OptionChips<String>(
          options: const <String>['peaceful', 'easy', 'normal', 'hard'],
          selected: s.difficulty,
          label: (v) => context.tr('difficulty.$v'),
          onSelected: (v) => setSettings(s.copyWith(difficulty: v)),
        ),
        SettingSwitch(
          title: context.tr('settings.onlineMode'),
          subtitle: context.tr('settings.onlineModeHint'),
          value: s.onlineMode,
          onChanged: (v) => setSettings(s.copyWith(onlineMode: v)),
        ),
        SettingSwitch(title: context.tr('settings.pvp'), value: s.pvp, onChanged: (v) => setSettings(s.copyWith(pvp: v))),
        SettingSwitch(title: context.tr('settings.whitelist'), value: s.whitelist, onChanged: (v) => setSettings(s.copyWith(whitelist: v))),
        SettingSwitch(title: context.tr('settings.nether'), value: s.allowNether, onChanged: (v) => setSettings(s.copyWith(allowNether: v))),
        TextField(controller: _seed, decoration: InputDecoration(labelText: context.tr('settings.seed'))),
        const SizedBox(height: AppSpace.xl),
        SectionTitle(title: context.tr('create.runtime.title'), subtitle: context.tr('create.runtime.body')),
        InfoLine(label: context.tr('runtime.memory'), value: '${r.memoryMb} MB'),
        ValueStepper(value: r.memoryMb, min: 1024, max: 8192, step: 512, onChanged: (v) => setRuntime(r.copyWith(memoryMb: v))),
        const SizedBox(height: AppSpace.md),
        Text(context.tr('runtime.backupInterval'), style: theme.textTheme.labelMedium),
        const SizedBox(height: AppSpace.sm),
        OptionChips<int>(
          options: const <int>[60, 180, 360],
          selected: r.backupIntervalMinutes,
          label: (v) => context.tr('runtime.everyMinutes', args: {'n': v}),
          onSelected: (v) => setRuntime(r.copyWith(backupIntervalMinutes: v)),
        ),
        SettingSwitch(
          title: context.tr('runtime.autoContinue'),
          subtitle: context.tr('runtime.autoContinueHint'),
          value: r.autoContinue,
          onChanged: (v) => setRuntime(r.copyWith(autoContinue: v)),
        ),
      ],
    );
  }

  Widget _repositoryStep(BuildContext context, ServerDraft draft) {
    final theme = Theme.of(context);
    final tailscale = ref.watch(tailscaleConnectionProvider).value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('create.repo.title'), style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpace.sm),
        Text(context.tr('create.repo.body'), style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpace.md),
        GlassCard(
          highlighted: draft.repoFullName.isNotEmpty,
          onTap: _pickRepository,
          child: Row(
            children: [
              const Icon(Icons.folder_special_outlined),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Text(
                  draft.repoFullName.isEmpty
                      ? context.tr('create.repo.choose')
                      : '${draft.repoFullName}${draft.createRepository ? ' (${context.tr('create.repo.new')})' : ''}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(tailscale ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      color: tailscale ? AppColors.success : AppColors.warning),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      tailscale ? context.tr('create.repo.tailscaleOn') : context.tr('create.repo.tailscaleOff'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        SettingSwitch(
          title: context.tr('create.repo.eula'),
          subtitle: context.tr('create.repo.eulaHint'),
          value: draft.eulaAccepted,
          onChanged: (v) => _update((d) => d.copyWith(eulaAccepted: v)),
        ),
        TextButton(
          onPressed: () => launchUrl(Uri.parse('https://www.minecraft.net/en-us/eula'), mode: LaunchMode.externalApplication),
          child: Text(context.tr('create.repo.eulaLink')),
        ),
        SettingSwitch(
          title: context.tr('create.repo.risk'),
          subtitle: context.tr('create.repo.riskHint'),
          value: draft.githubRiskAccepted,
          onChanged: (v) => _update((d) => d.copyWith(githubRiskAccepted: v)),
        ),
        SettingSwitch(
          title: context.tr('create.repo.startNow'),
          value: draft.startAfterCreate,
          onChanged: (v) => _update((d) => d.copyWith(startAfterCreate: v)),
        ),
      ],
    );
  }

  Widget _reviewStep(BuildContext context, ServerDraft draft) {
    final theme = Theme.of(context);
    final preview = draft.minecraftVersion.isEmpty
        ? null
        : ref.watch(buildPreviewProvider((software: draft.software, version: draft.minecraftVersion)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('create.review.title'), style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpace.md),
        GlassCard(
          highlighted: true,
          child: Column(
            children: [
              InfoLine(label: context.tr('create.review.name'), value: _name.text.trim()),
              InfoLine(label: context.tr('create.review.software'), value: draft.software.label),
              InfoLine(label: context.tr('create.review.version'), value: draft.minecraftVersion),
              InfoLine(
                label: context.tr('create.review.loader'),
                value: preview == null
                    ? '-'
                    : preview.when(
                        data: (b) => b.loaderVersion.isEmpty ? '-' : b.loaderVersion,
                        loading: () => context.tr('common.loading'),
                        error: (e, _) => describeError(context, e),
                      ),
              ),
              InfoLine(
                label: context.tr('create.review.java'),
                value: preview == null
                    ? '-'
                    : preview.when(
                        data: (b) => 'Java ${b.javaMajor}',
                        loading: () => context.tr('common.loading'),
                        error: (e, _) => '-',
                      ),
              ),
              InfoLine(label: context.tr('create.review.repo'), value: draft.repoFullName),
              InfoLine(label: context.tr('create.review.runner'), value: context.tr('actions.runner')),
              InfoLine(label: context.tr('create.review.players'), value: '${draft.settings.maxPlayers}'),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(context.tr('create.review.note'), style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpace.sm),
        Text(context.tr('create.review.driveNote'), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('create.stepOf', args: {'n': step + 1, 'total': total}), style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: AppSpace.sm),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: (step + 1) / total),
            duration: AppMotion.base,
            curve: AppMotion.standard,
            builder: (context, value, _) => ClipRRect(
              borderRadius: AppRadius.all(AppRadius.pill),
              child: LinearProgressIndicator(value: value, minHeight: 6, backgroundColor: AppColors.surfaceHigh),
            ),
          ),
        ],
      ),
    );
  }
}
