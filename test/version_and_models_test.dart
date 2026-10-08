import 'package:flutter_test/flutter_test.dart';
import 'package:voxelops/data/minecraft/version_catalog.dart';
import 'package:voxelops/domain/server_models.dart';
import 'package:voxelops/data/content/content_catalog.dart';

void main() {
  test('maps NeoForge version numbers to Minecraft versions', () {
    expect(neoForgeMinecraftForTest('21.1.100'), '1.21.1');
    expect(neoForgeMinecraftForTest('21.0.45'), '1.21');
    expect(neoForgeMinecraftForTest('20.4.237'), '1.20.4');
    expect(neoForgeMinecraftForTest('1.20.1-47.1.82'), '1.20.1');
    expect(neoForgeMinecraftForTest('26.1.0.2'), '26.1');
  });

  test('orders Minecraft versions numerically', () {
    final list = ['1.10', '1.9', '1.21.4', '1.8.9'];
    list.sort(VersionCatalog.compareMinecraftVersions);
    expect(list, ['1.8.9', '1.9', '1.10', '1.21.4']);
  });

  test('loader compatibility follows the server software', () {
    expect(ServerSoftware.paper.compatibleLoaderTags.contains('spigot'), isTrue);
    expect(ServerSoftware.fabric.compatibleLoaderTags.contains('forge'), isFalse);
    expect(ServerSoftware.vanilla.supportsContent, isFalse);
    expect(ServerSoftware.neoforge.curseForgeLoaderType, 6);
  });

  test('server record survives a JSON round trip', () {
    final record = ServerRecord(
      id: 'srv-1',
      name: 'Test',
      description: 'desc',
      software: ServerSoftware.forge,
      minecraftVersion: '1.20.1',
      loaderVersion: '1.20.1-47.2.0',
      javaMajor: 17,
      driveFolderId: 'folder',
      repoOwner: 'me',
      repoName: 'repo',
      createdAt: DateTime.utc(2026, 2, 3, 4, 5, 6),
    );
    final restored = ServerRecord.fromJson(record.toJson());
    expect(restored.software, ServerSoftware.forge);
    expect(restored.repoFullName, 'me/repo');
    expect(restored.loaderVersion, '1.20.1-47.2.0');
    expect(restored.javaMajor, 17);
  });

  test('server status parses known states and falls back to unknown', () {
    final running = ServerStatus.fromJson({'state': 'running', 'players': 3, 'maxPlayers': 20, 'updatedAt': DateTime.now().toUtc().toIso8601String()});
    expect(running.state, ServerState.running);
    expect(running.players, 3);
    final odd = ServerStatus.fromJson({'state': 'martian'});
    expect(odd.state, ServerState.unknown);
  });

  test('runtime settings default safely when fields are missing', () {
    final runtime = RuntimeSettings.fromJson({'memoryMb': 4096});
    expect(runtime.memoryMb, 4096);
    expect(runtime.backupRetention, 7);
    expect(runtime.autoContinue, isTrue);
  });

  test('content queries compare by value for provider caching', () {
    const a = ContentQuery(kind: ContentKind.mods, text: 'jei', source: ContentSource.all, sort: ContentSort.relevance);
    const b = ContentQuery(kind: ContentKind.mods, text: 'jei', source: ContentSource.all, sort: ContentSort.relevance);
    expect(a == b, isTrue);
    expect(a.hashCode, b.hashCode);
  });
}
