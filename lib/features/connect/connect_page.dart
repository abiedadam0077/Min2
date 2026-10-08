import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../state/auth_providers.dart';
import 'connect_sheets.dart';

/// Connection hub: GitHub and Google Drive are required; Tailscale is optional.
class ConnectPage extends ConsumerWidget {
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final github = ref.watch(githubAccountsProvider);
    final google = ref.watch(googleAccountProvider);
    final tailscale = ref.watch(tailscaleConnectionProvider);
    final ready = github.isConnected && google.value != null;
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
                    child: _ServiceCard(
                      icon: Icons.code_rounded,
                      title: context.tr('connect.github.title'),
                      body: github.isConnected
                          ? context.tr('connect.connectedAs', args: {'name': github.active!.login})
                          : context.tr('connect.github.body'),
                      isRequired: true,
                      connected: github.isConnected,
                      actionLabel: github.isConnected ? context.tr('action.manage') : context.tr('action.connect'),
                      onAction: () => github.isConnected ? context.push('/accounts') : showGitHubSignIn(context),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  FadeSlideIn(
                    index: 1,
                    child: _ServiceCard(
                      icon: Icons.cloud_done_outlined,
                      title: context.tr('connect.drive.title'),
                      body: google.isLoading
                          ? context.tr('common.loading')
                          : google.value != null
                              ? context.tr('connect.connectedAs', args: {'name': google.value!.email})
                              : context.tr('connect.drive.body'),
                      isRequired: true,
                      connected: google.value != null,
                      busy: google.isLoading,
                      actionLabel: google.value != null ? context.tr('action.manage') : context.tr('action.connect'),
                      onAction: () async {
                        if (google.value != null) {
                          context.push('/accounts');
                          return;
                        }
                        await ref.read(googleAccountProvider.notifier).connect();
                        final error = ref.read(googleAccountProvider).error;
                        if (error != null && context.mounted) {
                          showAppSnack(context, describeError(context, error), isError: true);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  FadeSlideIn(
                    index: 2,
                    child: _ServiceCard(
                      icon: Icons.hub_outlined,
                      title: context.tr('connect.tailscale.title'),
                      body: tailscale.value != null ? context.tr('connect.tailscale.connected') : context.tr('connect.tailscale.body'),
                      isRequired: false,
                      connected: tailscale.value != null,
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

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.isRequired,
    required this.connected,
    required this.actionLabel,
    required this.onAction,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool isRequired;
  final bool connected;
  final bool busy;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Text(
                isRequired ? context.tr('connect.required') : context.tr('connect.optional'),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                : SecondaryButton(
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
