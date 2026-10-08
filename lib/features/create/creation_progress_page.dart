import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/shell.dart';
import '../../state/create_providers.dart';

const List<String> _stepOrder = <String>['resolve', 'drive', 'github', 'workflow', 'secrets', 'start', 'done'];

class CreationProgressPage extends ConsumerWidget {
  const CreationProgressPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(creationJobProvider);
    final theme = Theme.of(context);
    final currentIndex = _stepOrder.indexOf(job.step);
    return AppPage(
      title: context.tr('create.progress.title'),
      children: [
        GlassCard(
          highlighted: job.record != null,
          accent: job.error != null ? AppColors.danger : AppColors.success,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                job.error != null
                    ? context.tr('create.progress.failed')
                    : job.record != null
                        ? context.tr('create.progress.done')
                        : context.tr('create.progress.running'),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpace.md),
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: job.progress.clamp(0.0, 1.0).toDouble()),
                duration: AppMotion.slow,
                curve: AppMotion.standard,
                builder: (context, value, _) => ClipRRect(
                  borderRadius: AppRadius.all(AppRadius.pill),
                  child: LinearProgressIndicator(value: value, minHeight: 8, backgroundColor: AppColors.surfaceHigh),
                ),
              ),
            ],
          ),
        ),
        for (final key in _stepOrder.where((s) => s != 'done'))
          FadeSlideIn(
            index: _stepOrder.indexOf(key),
            child: _StepRow(
              label: context.tr('create.step.$key'),
              done: currentIndex > _stepOrder.indexOf(key) || job.record != null,
              active: job.running && job.step == key,
              failed: job.error != null && job.step == key,
            ),
          ),
        if (job.error != null) ...[
          GlassCard(
            accent: AppColors.danger,
            highlighted: true,
            child: Text(job.error!, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.danger)),
          ),
          PrimaryButton(
            label: context.tr('create.progress.retry'),
            icon: Icons.refresh_rounded,
            onPressed: () => ref.read(creationJobProvider.notifier).run(ref.read(serverDraftProvider)),
          ),
          SecondaryButton(
            label: context.tr('create.progress.backToWizard'),
            icon: Icons.arrow_back_rounded,
            onPressed: () => context.go('/wizard'),
          ),
        ],
        if (job.record != null) ...[
          PrimaryButton(
            label: context.tr('create.progress.openDashboard'),
            icon: Icons.dashboard_rounded,
            onPressed: () {
              ref.read(creationJobProvider.notifier).reset();
              ref.read(serverDraftProvider.notifier).reset();
              context.go('/server/${job.record!.id}');
            },
          ),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.done, required this.active, required this.failed});

  final String label;
  final bool done;
  final bool active;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final color = failed ? AppColors.danger : done ? AppColors.success : active ? AppColors.primary : AppColors.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: AppMotion.base,
            child: Icon(
              done ? Icons.check_circle_rounded : failed ? Icons.error_rounded : Icons.radio_button_unchecked_rounded,
              key: ValueKey<String>('$label-$done-$failed'),
              color: color,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: active || done ? AppColors.textPrimary : AppColors.textMuted))),
          if (active) SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
        ],
      ),
    );
  }
}
