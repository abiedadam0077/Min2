import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/brand.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        context.go('/home');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.background3d),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VoxelLogo(size: 132),
              const SizedBox(height: AppSpace.xl),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: AppMotion.slow,
                curve: AppMotion.enter,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
                ),
                child: Column(
                  children: [
                    Text(AppConfig.appName, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: AppSpace.xs),
                    Text(context.tr('splash.tagline'), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.xxl),
              const SizedBox(
                width: 120,
                child: LinearProgressIndicator(minHeight: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
