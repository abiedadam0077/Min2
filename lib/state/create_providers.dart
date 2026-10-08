import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/app_exception.dart';
import '../domain/server_draft.dart';
import '../domain/server_models.dart';
import 'core_providers.dart';
import 'server_providers.dart';

class ServerDraftNotifier extends Notifier<ServerDraft> {
  @override
  ServerDraft build() => const ServerDraft();

  void update(ServerDraft Function(ServerDraft current) change) {
    state = change(state);
  }

  void reset() {
    state = const ServerDraft();
  }
}

final serverDraftProvider = NotifierProvider<ServerDraftNotifier, ServerDraft>(ServerDraftNotifier.new);

class CreationJob {
  const CreationJob({
    this.running = false,
    this.step = '',
    this.progress = 0,
    this.error,
    this.record,
  });

  final bool running;
  final String step;
  final double progress;
  final String? error;
  final ServerRecord? record;

  bool get finished => record != null || error != null;
}

/// Runs the provisioner and reports progress. Errors are kept in state so the progress screen can show them.
class CreationJobNotifier extends Notifier<CreationJob> {
  @override
  CreationJob build() => const CreationJob();

  Future<void> run(ServerDraft draft) async {
    state = const CreationJob(running: true, step: 'resolve', progress: 0.02);
    try {
      final record = await ref.read(serverProvisionerProvider).create(
        draft,
        onProgress: (step, fraction) {
          state = CreationJob(running: true, step: step, progress: fraction);
        },
      );
      ref.read(serverRegistryProvider.notifier).reload();
      await ref.read(activeServerIdProvider.notifier).select(record.id);
      state = CreationJob(running: false, step: 'done', progress: 1, record: record);
    } on AppException catch (error) {
      state = CreationJob(running: false, step: 'failed', progress: state.progress, error: error.message);
    } catch (error) {
      state = CreationJob(running: false, step: 'failed', progress: state.progress, error: 'Unexpected error: $error');
    }
  }

  void reset() => state = const CreationJob();
}

final creationJobProvider = NotifierProvider<CreationJobNotifier, CreationJob>(CreationJobNotifier.new);
