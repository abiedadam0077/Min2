import 'package:flutter/material.dart';

/// Spacing scale (4 pt base grid).
abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii for cards, sheets and controls.
abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;

  static BorderRadius all(double value) => BorderRadius.circular(value);
}

/// Motion tokens. Durations stay short so interactions feel instant; curves are physical.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 480);
  static const Duration page = Duration(milliseconds: 340);

  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasized = Curves.easeOutBack;
  static const Curve standard = Curves.fastOutSlowIn;
}

/// Responsive breakpoints (logical pixels).
abstract final class AppBreakpoints {
  static const double compact = 600;
  static const double medium = 840;
  static const double expanded = 1200;
  static const double contentMaxWidth = 760;
  static const double navClearance = 112;

  static bool isCompact(double width) => width < compact;
  static bool isExpanded(double width) => width >= medium;

  /// Horizontal page inset that centers content up to [contentMaxWidth].
  static double horizontalInset(double width) {
    final extra = (width - contentMaxWidth) / 2;
    return extra > AppSpace.lg ? extra : AppSpace.lg;
  }
}
