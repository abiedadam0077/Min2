import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/shell.dart';
import '../../state/app_providers.dart';
import '../../state/auth_providers.dart';
import '../../state/server_providers.dart';
import '../connect/connect_sheets.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final code = locale?.languageCode ?? 'system';
    final theme = Theme.of(context);
    final quota = ref.watch(driveQuotaProvider);
    return AppPage(
      title: context.tr('more.title'),
      inShell: true,
      children: [
        GlassCard(
          child: Row(
            children: [
              const VoxelLogo(size: 56, animate: false),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppConfig.appName, style: theme.textTheme.titleLarge),
                    Text('${AppConfig.version} (${AppConfig.build})', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionTitle(title: context.tr('more.account')),
        _Tile(icon: Icons.manage_accounts_outlined, label: context.tr('more.accounts'), onTap: () => context.push('/accounts')),
        _Tile(icon: Icons.notifications_none_rounded, label: context.tr('notifications.title'), onTap: () => context.push('/notifications')),
        _Tile(icon: Icons.key_rounded, label: context.tr('accounts.curseforge'), onTap: () => showCurseForgeSheet(context, ref)),
        SectionTitle(title: context.tr('more.language')),
        GlassCard(
          child: OptionChips<String>(
            options: const <String>['system', 'ar', 'en'],
            selected: code,
            label: (c) => context.tr('lang.$c'),
            onSelected: (c) => ref.read(localeProvider.notifier).set(c),
          ),
        ),
        SectionTitle(title: context.tr('more.storage')),
        quota.when(
          data: (q) => MetricCard(
            icon: Icons.cloud_outlined,
            label: context.tr('home.driveUsage'),
            value: formatBytes(q.usedBytes),
            caption: q.email,
            color: AppColors.info,
          ),
          loading: () => const SkeletonList(count: 1, height: 96),
          error: (error, _) => GlassCard(child: Text(describeError(context, error), style: theme.textTheme.bodySmall)),
        ),
        SectionTitle(title: context.tr('more.about')),
        _Tile(
          icon: Icons.article_outlined,
          label: context.tr('more.licenses'),
          onTap: () => showLicensePage(context: context, applicationName: AppConfig.appName, applicationVersion: AppConfig.version),
        ),
        GlassCard(
          child: Text(context.tr('more.disclaimer'), style: theme.textTheme.bodySmall),
        ),
        if (ref.watch(serverRegistryProvider).isNotEmpty)
          GlassCard(
            child: Text(context.tr('more.servers', args: {'n': ref.watch(serverRegistryProvider).length}), style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleSmall)),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
