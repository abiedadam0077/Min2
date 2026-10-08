import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../state/app_providers.dart';
import '../../state/core_providers.dart';

class WelcomePage extends ConsumerWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final features = <(IconData, String, String)>[
      (Icons.rocket_launch_outlined, context.tr('welcome.f1.title'), context.tr('welcome.f1.body')),
      (Icons.cloud_sync_outlined, context.tr('welcome.f2.title'), context.tr('welcome.f2.body')),
      (Icons.shield_outlined, context.tr('welcome.f3.title'), context.tr('welcome.f3.body')),
    ];
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.background3d),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = AppBreakpoints.horizontalInset(constraints.maxWidth);
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: inset, vertical: AppSpace.lg),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - AppSpace.lg * 2),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: SegmentedButton<String>(
                            segments: <ButtonSegment<String>>[
                              ButtonSegment(value: 'en', label: Text(context.tr('lang.en'))),
                              ButtonSegment(value: 'ar', label: Text(context.tr('lang.ar'))),
                            ],
                            selected: <String>{context.isArabic ? 'ar' : 'en'},
                            onSelectionChanged: (value) => ref.read(localeProvider.notifier).set(value.first),
                          ),
                        ),
                        const Spacer(),
                        const VoxelLogo(size: 128),
                        const SizedBox(height: AppSpace.xl),
                        Text(context.tr('welcome.title'), style: theme.textTheme.displaySmall, textAlign: TextAlign.center),
                        const SizedBox(height: AppSpace.md),
                        Text(context.tr('welcome.subtitle'), style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
                        const SizedBox(height: AppSpace.xl),
                        for (var i = 0; i < features.length; i++)
                          FadeSlideIn(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: AppSpace.md),
                              child: GlassCard(
                                child: Row(
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(gradient: AppColors.brand, borderRadius: AppRadius.all(AppRadius.md)),
                                      child: Icon(features[i].$1, color: AppColors.ink),
                                    ),
                                    const SizedBox(width: AppSpace.lg),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(features[i].$2, style: theme.textTheme.titleSmall),
                                          const SizedBox(height: 2),
                                          Text(features[i].$3, style: theme.textTheme.bodySmall),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const Spacer(),
                        const SizedBox(height: AppSpace.lg),
                        PrimaryButton(
                          label: context.tr('welcome.start'),
                          icon: Icons.arrow_forward_rounded,
                          onPressed: () async {
                            await ref.read(prefsProvider).setOnboarded(true);
                            if (context.mounted) {
                              context.go('/connect');
                            }
                          },
                        ),
                        const SizedBox(height: AppSpace.md),
                        Text('${AppConfig.appName} ${AppConfig.version}', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
