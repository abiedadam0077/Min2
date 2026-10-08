import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core_providers.dart';

/// The Drive folder that stores every server. Persisted locally; the folder itself lives in Drive.
class DriveStorage {
  const DriveStorage({required this.id, required this.name});

  final String id;
  final String name;
}

class DriveStorageNotifier extends Notifier<DriveStorage?> {
  @override
  DriveStorage? build() {
    final prefs = ref.watch(prefsProvider);
    final id = prefs.driveRootId;
    if (id == null || id.isEmpty) {
      return null;
    }
    return DriveStorage(id: id, name: prefs.driveRootName ?? 'Minecraft Servers');
  }

  Future<void> select(String id, String name) async {
    await ref.read(prefsProvider).setDriveRoot(id, name);
    state = DriveStorage(id: id, name: name);
  }

  Future<void> clear() async {
    await ref.read(prefsProvider).setDriveRoot(null, null);
    state = null;
  }
}

final driveStorageProvider = NotifierProvider<DriveStorageNotifier, DriveStorage?>(DriveStorageNotifier.new);
