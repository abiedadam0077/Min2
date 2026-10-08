import 'package:flutter/material.dart';
import '../../state/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/shell.dart';
import '../../domain/integration_models.dart';
import '../../state/core_providers.dart';

/// Result of the repository picker: an existing repository or a request to create one.
class RepoSelection {
  const RepoSelection({required this.owner, required this.name, required this.create, required this.isPrivate});

  final String owner;
  final String name;
  final bool create;
  final bool isPrivate;
}

final _reposProvider = FutureProvider.autoDispose<List<GitHubRepo>>((ref) => ref.read(githubApiProvider).listRepositories());

class RepoPickerPage extends ConsumerStatefulWidget {
  const RepoPickerPage({super.key, required this.mode});

  /// "create" for a new server, "attach" to reuse an existing repository.
  final String mode;

  @override
  ConsumerState<RepoPickerPage> createState() => _RepoPickerPageState();
}

class _RepoPickerPageState extends ConsumerState<RepoPickerPage> {
  final _search = TextEditingController();
  final _newName = TextEditingController(text: 'voxelops-server');
  bool _private = true;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _newName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repos = ref.watch(_reposProvider);
    final allowCreate = widget.mode == 'create';
    return AppPage(
      title: context.tr(allowCreate ? 'repo.title.create' : 'repo.title.attach'),
      onRefresh: () async => ref.invalidate(_reposProvider),
      children: [
        if (allowCreate)
          GlassCard(
            highlighted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('repo.createTitle'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpace.sm),
                TextField(
                  controller: _newName,
                  decoration: InputDecoration(labelText: context.tr('repo.nameField')),
                ),
                SettingSwitchCompact(
                  label: context.tr('repo.privateField'),
                  value: _private,
                  onChanged: (v) => setState(() => _private = v),
                ),
                const SizedBox(height: AppSpace.sm),
                PrimaryButton(
                  label: context.tr('repo.createAction'),
                  icon: Icons.add_rounded,
                  onPressed: () {
                    final name = _newName.text.trim();
                    if (name.isEmpty) {
                      return;
                    }
                    final login = ref.read(githubAccountsProvider).active?.login ?? '';
                    context.pop(RepoSelection(owner: login, name: name, create: true, isPrivate: _private));
                  },
                ),
              ],
            ),
          ),
        AppSearchField(
          controller: _search,
          hint: context.tr('repo.search'),
          onSubmitted: (value) => setState(() => _query = value.trim().toLowerCase()),
        ),
        AsyncBody<List<GitHubRepo>>(
          value: repos,
          onRetry: () => ref.invalidate(_reposProvider),
          builder: (context, items) {
            final filtered = items.where((r) => _query.isEmpty || r.fullName.toLowerCase().contains(_query)).toList();
            if (filtered.isEmpty) {
              return EmptyState(icon: Icons.inbox_outlined, title: context.tr('repo.empty'));
            }
            return Column(
              children: [
                for (var i = 0; i < filtered.length; i++)
                  FadeSlideIn(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                        onTap: filtered[i].canPush
                            ? () => context.pop(
                                  RepoSelection(owner: filtered[i].owner, name: filtered[i].name, create: false, isPrivate: filtered[i].isPrivate),
                                )
                            : null,
                        child: Row(
                          children: [
                            Icon(filtered[i].isPrivate ? Icons.lock_outline_rounded : Icons.public_rounded, size: 20),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(filtered[i].fullName, style: Theme.of(context).textTheme.titleSmall),
                                  Text(
                                    filtered[i].canPush ? (filtered[i].description ?? '') : context.tr('repo.readOnly'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded, color: filtered[i].canPush ? null : Colors.transparent),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Compact switch row for dense forms.
class SettingSwitchCompact extends StatelessWidget {
  const SettingSwitchCompact({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
    );
  }
}
