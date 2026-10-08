import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../state/auth_providers.dart';
import '../connect/connect_sheets.dart';

/// Account switching and service management: GitHub accounts, Google Drive, Tailscale, CurseForge.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final github = ref.watch(githubAccountsProvider);
    final google = ref.watch(googleAccountProvider);
    final tailscale = ref.watch(tailscaleConnectionProvider);
    final curseForge = ref.watch(curseForgeKeyPresentProvider);
    return AppPage(
      title: context.tr('accounts.title'),
      children: [
        SectionTitle(title: context.tr('accounts.github')),
        if (github.accounts.isEmpty)
          GlassCard(child: Text(context.tr('accounts.githubEmpty'), style: Theme.of(context).textTheme.bodyMedium))
        else
          for (final account in github.accounts)
            FadeSlideIn(
              child: GlassCard(
                highlighted: account.login == github.activeLogin,
                accent: AppColors.primary,
                onTap: () => ref.read(githubAccountsProvider.notifier).switchTo(account.login),
                child: Row(
                  children: [
                    AvatarImage(url: account.avatarUrl, fallback: account.login, size: 44),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(account.name?.isNotEmpty == true ? account.name! : account.login, style: Theme.of(context).textTheme.titleSmall),
                          Text('@${account.login}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (account.login == github.activeLogin)
                      Chip(label: Text(context.tr('accounts.active'))),
                    IconButton(
                      tooltip: context.tr('action.remove'),
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        final ok = await confirmAction(
                          context,
                          title: context.tr('accounts.removeTitle'),
                          message: context.tr('accounts.removeBody', args: {'name': account.login}),
                          confirmLabel: context.tr('action.remove'),
                          destructive: true,
                        );
                        if (ok) {
                          await ref.read(githubAccountsProvider.notifier).removeAccount(account.login);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        Row(
          children: [
            Expanded(child: SecondaryButton(label: context.tr('accounts.addGitHub'), icon: Icons.add_rounded, onPressed: () => showGitHubSignIn(context))),
          ],
        ),
        SectionTitle(title: context.tr('accounts.drive')),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                google.value?.email ?? context.tr('connect.drive.body'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: google.value == null
                        ? PrimaryButton(
                            label: context.tr('action.connect'),
                            busy: google.isLoading,
                            onPressed: () async {
                              await ref.read(googleAccountProvider.notifier).connect();
                              final error = ref.read(googleAccountProvider).error;
                              if (error != null && context.mounted) {
                                showAppSnack(context, describeError(context, error), isError: true);
                              }
                            },
                          )
                        : SecondaryButton(
                            label: context.tr('accounts.disconnect'),
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
                              if (ok) {
                                await ref.read(googleAccountProvider.notifier).disconnect();
                              }
                            },
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionTitle(title: context.tr('accounts.tailscale')),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tailscale.value != null ? context.tr('connect.tailscale.connected') : context.tr('connect.tailscale.body'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: tailscale.value != null ? context.tr('accounts.tailscaleUpdate') : context.tr('action.connect'),
                      icon: Icons.hub_outlined,
                      onPressed: () => showTailscaleSheet(context),
                    ),
                  ),
                  if (tailscale.value != null) ...[
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: SecondaryButton(
                        label: context.tr('accounts.disconnect'),
                        icon: Icons.link_off_rounded,
                        danger: true,
                        onPressed: () => ref.read(tailscaleConnectionProvider.notifier).disconnect(),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        SectionTitle(title: context.tr('accounts.curseforge')),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                curseForge.value == true ? context.tr('accounts.curseForgeSet') : context.tr('accounts.curseForgeMissing'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpace.md),
              SecondaryButton(
                label: context.tr('accounts.curseForgeAction'),
                icon: Icons.key_rounded,
                onPressed: () => showCurseForgeSheet(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
