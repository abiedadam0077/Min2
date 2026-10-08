import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/shell.dart';
import '../../data/provisioning/server_provisioner.dart';
import '../../state/core_providers.dart';
import '../../state/server_providers.dart';
import '../create/repo_picker_page.dart';
import '../shared/server_ui.dart';

final _discoverProvider = FutureProvider.autoDispose<List<DiscoveredServer>>((ref) => ref.read(serverProvisionerProvider).discover());

/// Recovery path: finds VoxelOps servers in Google Drive and reconnects them to a repository.
class ImportServerPage extends ConsumerWidget {
  const ImportServerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final found = ref.watch(_discoverProvider);
    final known = ref.watch(serverRegistryProvider).map((s) => s.id).toSet();
    return AppPage(
      title: context.tr('import.title'),
      onRefresh: () async => ref.invalidate(_discoverProvider),
      children: [
        GlassCard(child: Text(context.tr('import.body'), style: Theme.of(context).textTheme.bodyMedium)),
        AsyncBody<List<DiscoveredServer>>(
          value: found,
          onRetry: () => ref.invalidate(_discoverProvider),
          builder: (context, items) {
            if (items.isEmpty) {
              return EmptyState(icon: Icons.cloud_off_outlined, title: context.tr('import.empty'), message: context.tr('import.emptyHint'));
            }
            return Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: GlassCard(
                        onTap: () => _attach(context, ref, items[i]),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(gradient: AppColors.brand, borderRadius: AppRadius.all(AppRadius.md)),
                              child: const Icon(Icons.cloud_done_outlined, color: AppColors.ink),
                            ),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(items[i].record.name, style: Theme.of(context).textTheme.titleSmall),
                                  Text(
                                    '${items[i].record.software.label} ${items[i].record.minecraftVersion}'
                                    '${known.contains(items[i].record.id) ? ' · ${context.tr('import.known')}' : ''}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _attach(BuildContext context, WidgetRef ref, DiscoveredServer server) async {
    final selection = await context.push<RepoSelection>('/repos?mode=attach');
    if (selection == null || selection.create || !context.mounted) {
      return;
    }
    final ok = await guardedAction(context, ref, () async {
      final record = await ref.read(serverProvisionerProvider).attachToRepository(
            driveFolderId: server.folderId,
            repoOwner: selection.owner,
            repoName: selection.name,
          );
      ref.read(serverRegistryProvider.notifier).reload();
      await ref.read(activeServerIdProvider.notifier).select(record.id);
    }, successKey: 'import.done');
    if (ok && context.mounted) {
      context.go('/home');
    }
  }
}
