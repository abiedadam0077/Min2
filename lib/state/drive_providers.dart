import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/google/drive_api.dart';
import '../data/provisioning/drive_layout.dart';
import '../data/provisioning/server_provisioner.dart';
import '../domain/integration_models.dart';
import 'core_providers.dart';
import 'server_providers.dart';

/// Folders this app can see in Google Drive (created by VoxelOps under drive.file).
/// Feeds the "Choose existing folder" option of the Server Storage screen.
final driveFoldersProvider = FutureProvider.autoDispose<List<DriveFile>>((ref) {
  return ref.read(driveApiProvider).listFolders();
});

/// What one server occupies in Drive, read directly from its folder.
class DriveUsage {
  const DriveUsage({required this.worlds, required this.files, required this.mods, required this.backups});

  final int worlds;
  final int files;
  final int mods;
  final int backups;
}

final driveUsageProvider = FutureProvider.autoDispose.family<DriveUsage, String>((ref, serverId) async {
  final record = findServer(ref.watch(serverRegistryProvider), serverId);
  if (record == null || record.driveFolderId.isEmpty) {
    return const DriveUsage(worlds: 0, files: 0, mods: 0, backups: 0);
  }
  final drive = ref.read(driveApiProvider);
  final rootChildren = await drive.listChildren(record.driveFolderId);
  final worlds = rootChildren.where((f) => f.isFolder && DriveLayout.worldFolders.contains(f.name)).length;
  final files = rootChildren.where((f) => !f.isFolder).length;
  final mods = await _countFiles(drive, record.driveFolderId, DriveLayout.mods);
  final backups = (await ref.read(serverActionsProvider).listBackups(record)).length;
  return DriveUsage(worlds: worlds, files: files, mods: mods, backups: backups);
});

Future<int> _countFiles(DriveApi drive, String parentId, String name) async {
  final folder = await drive.findChild(parentId, name, mimeType: DriveApi.folderMime);
  if (folder == null) {
    return 0;
  }
  final children = await drive.listChildren(folder.id);
  return children.where((f) => !f.isFolder).length;
}
