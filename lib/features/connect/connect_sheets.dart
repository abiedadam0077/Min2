import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_exception.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/feedback.dart';
import '../../core/storage/secure_store.dart';
import '../../domain/integration_models.dart';
import '../../state/auth_providers.dart';
import '../../state/core_providers.dart';

/// Shared modal chrome for every connection sheet.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, inset + AppSpace.xl),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// GitHub sign-in. Uses the OAuth device flow when a client ID is configured; otherwise a
/// personal access token is accepted so the app is usable without any developer setup.
Future<void> showGitHubSignIn(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => AppConfig.hasGitHubOAuth ? const _GitHubDeviceSheet() : const _GitHubTokenSheet(),
  );
}

class _GitHubDeviceSheet extends ConsumerStatefulWidget {
  const _GitHubDeviceSheet();

  @override
  ConsumerState<_GitHubDeviceSheet> createState() => _GitHubDeviceSheetState();
}

class _GitHubDeviceSheetState extends ConsumerState<_GitHubDeviceSheet> {
  DeviceCodeChallenge? _challenge;
  String? _error;
  bool _cancelled = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _working = true;
    });
    try {
      final flow = ref.read(githubDeviceFlowProvider);
      final challenge = await flow.start();
      if (!mounted) {
        return;
      }
      setState(() => _challenge = challenge);
      final token = await flow.pollForToken(challenge, isCancelled: () => _cancelled);
      if (!mounted || _cancelled) {
        return;
      }
      await ref.read(githubAccountsProvider.notifier).addAccountWithToken(token);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on AppException catch (error) {
      if (mounted && !_cancelled) {
        setState(() => _error = describeError(context, error));
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final challenge = _challenge;
    return _SheetFrame(
      title: context.tr('github.signin.title'),
      children: [
        Text(context.tr('github.signin.deviceBody'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpace.xl),
        if (challenge == null && _error == null)
          const Center(child: CircularProgressIndicator())
        else if (challenge != null) ...[
          Center(
            child: SelectableText(
              challenge.userCode,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(letterSpacing: 4, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          PrimaryButton(
            label: context.tr('github.signin.openGitHub'),
            icon: Icons.open_in_new_rounded,
            onPressed: () => launchUrl(Uri.parse(challenge.verificationUri), mode: LaunchMode.externalApplication),
          ),
          const SizedBox(height: AppSpace.sm),
          SecondaryButton(
            label: context.tr('github.signin.copyCode'),
            icon: Icons.copy_rounded,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: challenge.userCode));
              if (context.mounted) {
                showAppSnack(context, context.tr('common.copied'));
              }
            },
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(context.tr('github.signin.waiting'), style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        ],
        if (_error != null) ...[
          Text(_error!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.danger)),
          const SizedBox(height: AppSpace.md),
          PrimaryButton(label: context.tr('action.retry'), icon: Icons.refresh_rounded, onPressed: _working ? null : _start),
        ],
        const SizedBox(height: AppSpace.md),
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.of(context).pop();
          },
          child: Text(context.tr('action.cancel')),
        ),
      ],
    );
  }
}

class _GitHubTokenSheet extends ConsumerStatefulWidget {
  const _GitHubTokenSheet();

  @override
  ConsumerState<_GitHubTokenSheet> createState() => _GitHubTokenSheetState();
}

class _GitHubTokenSheetState extends ConsumerState<_GitHubTokenSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(githubAccountsProvider.notifier).addAccountWithToken(_controller.text);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on AppException catch (error) {
      if (mounted) {
        setState(() => _error = describeError(context, error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: context.tr('github.token.title'),
      children: [
        Text(context.tr('github.token.body'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpace.md),
        SecondaryButton(
          label: context.tr('github.token.create'),
          icon: Icons.key_rounded,
          onPressed: () => launchUrl(
            Uri.parse('https://github.com/settings/tokens/new?scopes=repo,workflow,read:user&description=VoxelOps'),
            mode: LaunchMode.externalApplication,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _controller,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: context.tr('github.token.field')),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpace.lg),
        PrimaryButton(label: context.tr('action.connect'), icon: Icons.link_rounded, busy: _busy, onPressed: _busy ? null : _submit),
      ],
    );
  }
}

Future<void> showTailscaleSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (_) => const _TailscaleSheet(),
  );
}

class _TailscaleSheet extends ConsumerStatefulWidget {
  const _TailscaleSheet();

  @override
  ConsumerState<_TailscaleSheet> createState() => _TailscaleSheetState();
}

class _TailscaleSheetState extends ConsumerState<_TailscaleSheet> {
  final _id = TextEditingController();
  final _secret = TextEditingController();
  final _tailnet = TextEditingController(text: '-');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    _tailnet.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(tailscaleConnectionProvider.notifier).connect(
            clientId: _id.text,
            clientSecret: _secret.text,
            tailnet: _tailnet.text,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on AppException catch (error) {
      if (mounted) {
        setState(() => _error = describeError(context, error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: context.tr('tailscale.connect.title'),
      children: [
        Text(context.tr('tailscale.connect.body'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpace.md),
        SecondaryButton(
          label: context.tr('tailscale.connect.open'),
          icon: Icons.open_in_new_rounded,
          onPressed: () => launchUrl(Uri.parse('https://login.tailscale.com/admin/settings/oauth'), mode: LaunchMode.externalApplication),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(controller: _id, decoration: InputDecoration(labelText: context.tr('tailscale.connect.clientId'))),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _secret,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: context.tr('tailscale.connect.secret')),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(controller: _tailnet, decoration: InputDecoration(labelText: context.tr('tailscale.connect.tailnet'))),
        if (_error != null) ...[
          const SizedBox(height: AppSpace.sm),
          Text(_error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger)),
        ],
        const SizedBox(height: AppSpace.lg),
        PrimaryButton(label: context.tr('action.verifyConnect'), icon: Icons.verified_outlined, busy: _busy, onPressed: _busy ? null : _connect),
      ],
    );
  }
}

Future<void> showCurseForgeSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) => _CurseForgeSheet(onSaved: () => ref.invalidate(curseForgeKeyPresentProvider)),
    ),
  );
}

class _CurseForgeSheet extends ConsumerStatefulWidget {
  const _CurseForgeSheet({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_CurseForgeSheet> createState() => _CurseForgeSheetState();
}

class _CurseForgeSheetState extends ConsumerState<_CurseForgeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: context.tr('curseforge.title'),
      children: [
        Text(context.tr('curseforge.body'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AppSpace.md),
        SecondaryButton(
          label: context.tr('curseforge.open'),
          icon: Icons.open_in_new_rounded,
          onPressed: () => launchUrl(Uri.parse('https://console.curseforge.com/'), mode: LaunchMode.externalApplication),
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _controller,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: context.tr('curseforge.field')),
        ),
        const SizedBox(height: AppSpace.lg),
        PrimaryButton(
          label: context.tr('action.save'),
          icon: Icons.save_rounded,
          onPressed: () async {
            await ref.read(secureStoreProvider).write(SecureKeys.curseForgeKey, _controller.text.trim());
            widget.onSaved();
            if (context.mounted) {
              Navigator.of(context).pop();
              showAppSnack(context, context.tr('common.saved'));
            }
          },
        ),
      ],
    );
  }
}
