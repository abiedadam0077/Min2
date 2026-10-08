import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/shell.dart';
import '../../domain/server_models.dart';
import '../../state/core_providers.dart';
import '../../state/server_providers.dart';
import '../servers/servers_page.dart';
import '../shared/server_ui.dart';

enum _LogFilter { all, warnings, errors }

class ConsolePage extends ConsumerStatefulWidget {
  const ConsolePage({super.key});

  @override
  ConsumerState<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends ConsumerState<ConsolePage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  _LogFilter _filter = _LogFilter.all;
  int _lastCount = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll(int count) {
    if (count == _lastCount) {
      return;
    }
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send(String serverId) async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      return;
    }
    final record = serverById(ref.read(serverRegistryProvider), serverId);
    if (record == null) {
      return;
    }
    final ok = await guardedAction(
      context,
      ref,
      () => ref.read(serverActionsProvider).sendCommand(record, 'console', payload: {'text': text}),
      successKey: 'console.sent',
    );
    if (ok) {
      _input.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeServerProvider);
    if (active == null) {
      return AppPage(title: context.tr('console.title'), inShell: true, children: const [NoActiveServer()]);
    }
    final lines = ref.watch(consoleProvider(active.id));
    final status = ref.watch(serverStatusProvider(active.id)).value;
    final visible = (lines.value ?? const <String>[]).where((line) {
      final upper = line.toUpperCase();
      return switch (_filter) {
        _LogFilter.all => true,
        _LogFilter.warnings => upper.contains('WARN') || upper.contains('ERROR'),
        _LogFilter.errors => upper.contains('ERROR') || upper.contains('EXCEPTION'),
      };
    }).toList();
    _autoScroll(visible.length);
    final height = (MediaQuery.sizeOf(context).height * 0.5).clamp(260.0, 520.0).toDouble();
    final theme = Theme.of(context);
    return AppPage(
      title: context.tr('console.title'),
      inShell: true,
      children: [
        Row(
          children: [
            Expanded(child: Text(active.name, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
            ServerStateChip(state: status?.state ?? ServerState.unknown),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        OptionChips<_LogFilter>(
          options: _LogFilter.values,
          selected: _filter,
          label: (f) => context.tr('console.filter.${f.name}'),
          onSelected: (f) => setState(() => _filter = f),
        ),
        const SizedBox(height: AppSpace.md),
        Container(
          height: height,
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: AppRadius.all(AppRadius.lg),
            border: Border.all(color: AppColors.outline),
          ),
          child: visible.isEmpty
              ? Center(child: Text(context.tr('console.empty'), style: theme.textTheme.bodySmall, textAlign: TextAlign.center))
              : ListView.builder(
                  controller: _scroll,
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final line = visible[index];
                    return SelectableText(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.45,
                        color: _lineColor(line),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: AppSpace.md),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final command in const <String>['list', 'save-all flush', 'whitelist list', 'time query daytime'])
              ActionChip(label: Text(command), onPressed: () => _input.text = command),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(active.id),
                decoration: InputDecoration(hintText: context.tr('console.inputHint')),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            IconButton.filled(
              tooltip: context.tr('console.send'),
              onPressed: () => _send(active.id),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Text(context.tr('console.latency'), style: theme.textTheme.labelSmall),
      ],
    );
  }

  Color _lineColor(String line) {
    final upper = line.toUpperCase();
    if (upper.contains('ERROR') || upper.contains('EXCEPTION')) {
      return AppColors.danger;
    }
    if (upper.contains('WARN')) {
      return AppColors.warning;
    }
    if (line.contains('Done (')) {
      return AppColors.success;
    }
    return AppColors.textSecondary;
  }
}
