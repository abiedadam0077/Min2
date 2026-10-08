import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/shell.dart';
import '../../domain/integration_models.dart';
import '../../domain/server_models.dart';
import '../../state/core_providers.dart';
import '../../state/server_providers.dart';
import '../shared/server_ui.dart';

/// Text editor for small configuration files stored in Drive (server.properties, JSON, YAML, ...).
class FileEditorPage extends ConsumerStatefulWidget {
  const FileEditorPage({super.key, required this.serverId, required this.fileId});

  final String serverId;
  final String fileId;

  @override
  ConsumerState<FileEditorPage> createState() => _FileEditorPageState();
}

class _FileEditorPageState extends ConsumerState<FileEditorPage> {
  final _controller = TextEditingController();
  DriveFile? _file;
  String _original = '';
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final file = await ref.read(driveApiProvider).getFile(widget.fileId);
      final text = await ref.read(serverActionsProvider).readText(file);
      if (!mounted) {
        return;
      }
      setState(() {
        _file = file;
        _original = text;
        _controller.text = text;
        _loading = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) {
      return;
    }
    setState(() => _saving = true);
    final ok = await guardedAction(context, ref, () => ref.read(serverActionsProvider).saveText(file, _controller.text), successKey: 'files.saved');
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      if (ok) {
        _original = _controller.text;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final record = serverById(ref.watch(serverRegistryProvider), widget.serverId);
    final status = ref.watch(serverStatusProvider(widget.serverId)).value;
    final dirty = _controller.text != _original;
    final isProperties = _file?.name == 'server.properties';
    final running = status?.state == ServerState.running;
    return AppPage(
      title: _file?.name ?? context.tr('files.editor'),
      actions: [
        IconButton(
          tooltip: context.tr('action.save'),
          onPressed: _saving || !dirty || _file == null ? null : _save,
          icon: _saving
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_rounded),
        ),
      ],
      children: [
        if (isProperties && running)
          GlassCard(
            accent: AppColors.warning,
            highlighted: true,
            child: Text(context.tr('files.propertiesWarning'), style: Theme.of(context).textTheme.bodySmall),
          ),
        if (_loading)
          const SkeletonList(count: 1, height: 360)
        else if (_error != null)
          ErrorState(error: _error!, onRetry: _load)
        else
          TextField(
            controller: _controller,
            minLines: 18,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: context.tr('files.editorHint'),
              alignLabelWithHint: true,
            ),
          ),
        if (record != null && dirty)
          Text(context.tr('files.unsaved'), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: AppSpace.lg),
      ],
    );
  }
}
