import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exception.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../domain/server_models.dart';
import '../../state/app_providers.dart';
import '../../state/server_providers.dart';

/// Runs a user action with uniform feedback: success snackbar, or a localized error that is also
/// recorded in the notification center.
Future<bool> guardedAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  String? successKey,
}) async {
  try {
    await action();
    if (context.mounted && successKey != null) {
      showAppSnack(context, context.tr(successKey));
    }
    return true;
  } on AppException catch (error) {
    final message = describeError(context, error);
    if (context.mounted) {
      showAppSnack(context, message, isError: true);
    }
    ref.read(notificationsProvider.notifier).push(context.tr('error.title'), '$message ${error.message}'.trim(), isError: true);
    return false;
  } catch (error) {
    if (context.mounted) {
      showAppSnack(context, context.tr('error.unknown'), isError: true);
    }
    ref.read(notificationsProvider.notifier).push(context.tr('error.title'), context.tr('error.unknown'), isError: true);
    return false;
  }
}

/// Compact summary of a server used in lists and cards.
class ServerSummaryCard extends StatelessWidget {
  const ServerSummaryCard({super.key, required this.record, required this.status, this.onTap, this.highlighted = false});

  final ServerRecord record;
  final ServerStatus? status;
  final VoidCallback? onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      highlighted: highlighted,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(gradient: AppColors.brand, borderRadius: AppRadius.all(AppRadius.md)),
                child: const Icon(Icons.view_in_ar_rounded, color: AppColors.ink),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      '${record.software.label} ${record.minecraftVersion}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              ServerStateChip(state: status?.state ?? ServerState.unknown),
            ],
          ),
          if (status != null && status!.state == ServerState.running) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              context.tr('home.playersOnline', args: {'n': status!.players, 'max': status!.maxPlayers}),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens the server dashboard after making it the active server.
void openServer(BuildContext context, WidgetRef ref, ServerRecord record) {
  ref.read(activeServerIdProvider.notifier).select(record.id);
  context.push('/server/${record.id}');
}
