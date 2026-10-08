import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../state/auth_providers.dart';
import '../../state/drive_storage_providers.dart';
import '../drive/drive_card.dart';
import 'connect_sheets.dart';

/// Connect Services: GitHub and Google Drive are required, Tailscale is optional.
class ConnectPage extends ConsumerWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final github = ref.watch(githubAccountsProvider);
    final google = ref.watch(googleAccountProvider);
    final storage = ref.watch(driveStorageProvider);
    final tailscale = ref.watch(tailscaleConnectionProvider);
    final ready = github.isConnected && google.value != null && storage != null;
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.background3d),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = AppBreakpoints.horizontalInset(constraints.maxWidth);
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, AppSpace.lg, inset, AppSpace.xxl),
                children: [
                  Text(context.tr('connect.title'), style: theme.textTheme.headlineMedium),
                  const SizedBox(height: AppSpace.sm),
                  Text(context.tr('connect.subtitle'), style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpace.xl),
                  FadeSlideIn(
                    index: 0,
                    child: _ServiceTile(
                      icon: Icons.code_rounded,
                      title: context.tr('connect.github.title'),
                      connected: github.isConnected,
                      statusText: github.isConnected
                          ? '@${github.active!.login}'
                          : context.tr('connect.notConnected'),
                      requirement: context.tr('connect.required'),
                      actionLabel: github.isConnected ? context.tr('action.manage') : context.tr('action.connect'),
                      onAction: () => github.isConnected ? context.push('/accounts') : showGitHubSignIn(context),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  FadeSlideIn(index: 1, child: const DriveCard()),
                  const SizedBox(height: AppSpace.md),
                  FadeSlideIn(
                    index: 2,
                    child: _ServiceTile(
                      icon: Icons.hub_outlined,
                      title: context.tr('connect.tailscale.title'),
                      connected: tailscale.value != null,
                      statusText: tailscale.value != null
                          ? context.tr('connect.tailscale.connected')
                          : context.tr('connect.optionalStatus'),
                      requirement: context.tr('connect.optional'),
                      actionLabel: tailscale.value != null ? context.tr('action.manage') : context.tr('action.connect'),
                      onAction: () => tailscale.value != null ? context.push('/accounts') : showTailscaleSheet(context),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  PrimaryButton(
                    label: context.tr('connect.continue'),
                    icon: Icons.arrow_forward_rounded,
                    onPressed: ready ? () => context.go('/home') : null,
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(context.tr('connect.privacy'), style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.icon,
    required this.title,
    required this.connected,
    required this.statusText,
    required this.requirement,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final bool connected;
  final String statusText;
  final String requirement;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = connected ? AppColors.success : AppColors.textMuted;
    return GlassCard(
      highlighted: connected,
      accent: AppColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (connected ? AppColors.success : AppColors.primary).withValues(alpha: 0.16),
                  borderRadius: AppRadius.all(AppRadius.md),
                ),
                child: Icon(icon, color: connected ? AppColors.success : AppColors.primary),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              Text(requirement, style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(statusText, style: theme.textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SecondaryButton(
              label: actionLabel,
              icon: connected ? Icons.tune_rounded : Icons.link_rounded,
              onPressed: onAction,
            ),
          ),
        ],
      ),
    );
  }
}
