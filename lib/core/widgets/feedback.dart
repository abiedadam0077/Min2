import 'package:flutter/material.dart';

import '../i18n/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Themed confirmation dialog. Returns true only when the user explicitly confirms.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.tr('action.cancel'),
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: AppMotion.base,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final theme = Theme.of(dialogContext);
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Material(
                color: AppColors.surface,
                borderRadius: AppRadius.all(AppRadius.xl),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
                          color: destructive ? AppColors.warning : AppColors.primary, size: 32),
                      const SizedBox(height: AppSpace.md),
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: AppSpace.sm),
                      Text(message, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: AppSpace.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            child: Text(context.tr('action.cancel')),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          FilledButton(
                            style: destructive
                                ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.ink)
                                : null,
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            child: Text(confirmLabel),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.emphasized, reverseCurve: AppMotion.exit);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween<double>(begin: 0.92, end: 1).animate(curved), child: child),
      );
    },
  );
  return result ?? false;
}

void showAppSnack(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xl),
        backgroundColor: isError ? AppColors.danger.withValues(alpha: 0.2) : AppColors.surfaceHigh,
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: isError ? AppColors.danger : AppColors.success, size: 20),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

