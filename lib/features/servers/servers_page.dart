import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/shell.dart';
import '../../domain/server_models.dart';
import '../../state/server_providers.dart';
import '../shared/server_ui.dart';

class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverRegistryProvider);
    final active = ref.watch(activeServerIdProvider);
    return AppPage(
      title: context.tr('servers.title'),
      inShell: true,
      floatingAction: FloatingActionButton.extended(
        heroTag: 'servers-new',
        onPressed: () => context.push('/wizard'),
        icon: const Icon(Icons.add_rounded),
        label: Text(context.tr('servers.new')),
      ),
      actions: [
        IconButton(
          tooltip: context.tr('servers.import'),
          onPressed: () => context.push('/import'),
          icon: const Icon(Icons.cloud_download_outlined),
        ),
      ],
      children: servers.isEmpty
          ? [
              EmptyState(
                icon: Icons.dns_outlined,
                title: context.tr('servers.empty.title'),
                message: context.tr('servers.empty.body'),
              ),
            ]
          : [
              for (var i = 0; i < servers.length; i++)
                FadeSlideIn(
                  index: i,
                  child: _ServerTile(record: servers[i], highlighted: servers[i].id == active),
                ),
            ],
    );
  }
}

class _ServerTile extends ConsumerWidget {
  const _ServerTile({required this.record, required this.highlighted});

  final ServerRecord record;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(serverStatusProvider(record.id)).value;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: ServerSummaryCard(
        record: record,
        status: status,
        highlighted: highlighted,
        onTap: () => openServer(context, ref, record),
      ),
    );
  }
}

/// Used by the content and console tabs when no server is active yet.
class NoActiveServer extends StatelessWidget {
  const NoActiveServer({super.key});

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.dns_outlined,
      title: context.tr('servers.noActive.title'),
      message: context.tr('servers.noActive.body'),
      action: PrimaryButton(
        label: context.tr('servers.new'),
        icon: Icons.add_rounded,
        onPressed: () => context.push('/wizard'),
      ),
    );
  }
}
