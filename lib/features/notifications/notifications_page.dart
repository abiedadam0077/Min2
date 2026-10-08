import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/shell.dart';
import '../../state/app_providers.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider);
    return AppPage(
      title: context.tr('notifications.title'),
      actions: [
        if (items.isNotEmpty)
          IconButton(
            tooltip: context.tr('action.clear'),
            icon: const Icon(Icons.done_all_rounded),
            onPressed: () => ref.read(notificationsProvider.notifier).clear(),
          ),
      ],
      children: items.isEmpty
          ? [EmptyState(icon: Icons.notifications_none_rounded, title: context.tr('notifications.empty'))]
          : [
              for (var i = 0; i < items.length; i++)
                FadeSlideIn(
                  index: i,
                  child: GlassCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(items[i].isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
                            color: items[i].isError ? AppColors.danger : AppColors.info),
                        const SizedBox(width: AppSpace.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(items[i].title, style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 2),
                              Text(items[i].body, style: Theme.of(context).textTheme.bodyMedium),
                              const SizedBox(height: AppSpace.xs),
                              Text(formatRelative(context, items[i].createdAt), style: Theme.of(context).textTheme.labelSmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
    );
  }
}
