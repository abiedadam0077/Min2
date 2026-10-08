import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../domain/integration_models.dart';
import '../../features/shared/server_ui.dart';
import '../../state/core_providers.dart';
import '../../state/drive_providers.dart';
import '../../state/drive_storage_providers.dart';

/// Server Storage: the Drive folder that holds every server (Minecraft Servers/<Name>/...).
/// Offered right after the first Google Drive connection; the user either creates the folder
/// or picks one that VoxelOps can already see.
class DriveStoragePage extends ConsumerStatefulWidget {
  const DriveStoragePage({super.key});

  @override
  ConsumerState<DriveStoragePage> createState() => _DriveStoragePageState();
}

class _DriveStoragePageState extends ConsumerState<DriveStoragePage> {
  final TextEditingController _name = TextEditingController(text: AppConfig.driveRootFolder);
  bool _creating = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/connect');
    }
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showAppSnack(context, context.tr('drive.nameRequired'), isError: true);
      return;
    }
    setState(() => _creating = true);
    final ok = await guardedAction(context, ref, () async {
      final folder = await ref.read(serverProvisionerProvider).createStorageRoot(name);
      await ref.read(driveStorageProvider.notifier).select(folder.id, folder.name);
    }, successKey: 'drive.storageReady');
    if (!mounted) {
      return;
    }
    setState(() => _creating = false);
    if (ok) {
      _close();
    }
  }

  Future<void> _choose(DriveFile folder) async {
    final ok = await guardedAction(context, ref, () async {
      await ref.read(serverProvisionerProvider).chooseStorageRoot(folder);
      await ref.read(driveStorageProvider.notifier).select(folder.id, folder.name);
    }, successKey: 'drive.storageReady');
    if (ok && mounted) {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final folders = ref.watch(driveFoldersProvider);
    final theme = Theme.of(context);
    return AppPage(
      title: context.tr('drive.storagePage.title'),
      onRefresh: () async => ref.invalidate(driveFoldersProvider),
      children: [
        GlassCard(child: Text(context.tr('drive.storagePage.body'), style: theme.textTheme.bodyMedium)),
        const SizedBox(height: AppSpace.lg),
        SectionTitle(title: context.tr('drive.create.title')),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: context.tr('drive.create.name')),
              ),
              const SizedBox(height: AppSpace.md),
              PrimaryButton(
                label: context.tr('drive.create.button'),
                icon: Icons.create_new_folder_outlined,
                busy: _creating,
                onPressed: _creating ? null : _create,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        SectionTitle(title: context.tr('drive.choose.title')),
        GlassCard(child: Text(context.tr('drive.choose.body'), style: theme.textTheme.bodySmall)),
        const SizedBox(height: AppSpace.md),
        AsyncBody<List<DriveFile>>(
          value: folders,
          onRetry: () => ref.invalidate(driveFoldersProvider),
          builder: (context, items) {
            if (items.isEmpty) {
              return EmptyState(
                icon: Icons.folder_off_outlined,
                title: context.tr('drive.choose.empty'),
                message: context.tr('drive.choose.hint'),
              );
            }
            return Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: GlassCard(
                        onTap: () => _choose(items[i]),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_rounded),
                            const SizedBox(width: AppSpace.md),
                            Expanded(child: Text(items[i].name, style: theme.textTheme.titleSmall)),
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
}
