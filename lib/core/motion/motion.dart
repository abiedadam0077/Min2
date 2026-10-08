import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Route page with a fade + rise transition, used for every pushed screen.
CustomTransitionPage<T> fadeRisePage<T>({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: AppMotion.page,
    reverseTransitionDuration: AppMotion.base,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.enter, reverseCurve: AppMotion.exit);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Tab switch inside the shell: a short cross-fade with a slight scale, no slide.
CustomTransitionPage<T> fadeThroughPage<T>({required LocalKey key, required Widget child}) {
  return CustomTransitionPage<T>(
    key: key,
    child: child,
    transitionDuration: AppMotion.base,
    reverseTransitionDuration: AppMotion.base,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.standard);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: 0.985, end: 1).animate(curved), child: child),
      );
    },
  );
}
