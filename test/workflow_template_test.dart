import 'package:flutter_test/flutter_test.dart';
import 'package:voxelops/data/minecraft/workflow_template.dart';
import 'package:voxelops/domain/server_models.dart';

ServerRecord _record({String name = 'Nova Craft! 2026', String id = 'srv-abc-12345678'}) => ServerRecord(
      id: id,
      name: name,
      description: '',
      software: ServerSoftware.paper,
      minecraftVersion: '1.21.4',
      loaderVersion: '123',
      javaMajor: 21,
      driveFolderId: 'drive-folder',
      repoOwner: 'octo',
      repoName: 'voxelops-nova',
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  test('renders dispatchable workflow with secrets referenced by name only', () {
    final yaml = WorkflowTemplate.render(record: _record(), runtime: const RuntimeSettings(), tailscaleEnabled: true);
    expect(yaml, contains('workflow_dispatch:'));
    expect(yaml, contains('actions: write'));
    expect(yaml, contains(r'${{ secrets.GDRIVE_REFRESH_TOKEN }}'));
    expect(yaml, contains(r'${{ secrets.TS_OAUTH_SECRET }}'));
    expect(yaml, contains('python3 .voxelops/runner.py'));
    expect(yaml, contains('java-version: "21"'));
    expect(yaml, isNot(contains('refresh_token=')));
  });

  test('omits Tailscale steps when Tailscale is not connected', () {
    final yaml = WorkflowTemplate.render(record: _record(), runtime: const RuntimeSettings(), tailscaleEnabled: false);
    expect(yaml, isNot(contains('tailscale/github-action')));
    expect(yaml, contains('VOXEL_TAILSCALE_ENABLED: "false"'));
  });

  test('tailscale hostname is a valid DNS label of at most 63 characters', () {
    final host = WorkflowTemplate.hostname(_record(name: 'Ａ very long server name that keeps going and going forever and ever'));
    expect(host.length, lessThanOrEqualTo(63));
    expect(RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$').hasMatch(host), isTrue);
    expect(host.startsWith('voxel-'), isTrue);
  });
}
