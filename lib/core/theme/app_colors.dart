import 'package:flutter/material.dart';

/// Dark-first palette: deep navy surfaces, electric blue primary, violet and cyan accents.
abstract final class AppColors {
  static const Color ink = Color(0xFF050914);
  static const Color background = Color(0xFF0A1022);
  static const Color surface = Color(0xFF111A35);
  static const Color surfaceHigh = Color(0xFF18234A);
  static const Color surfaceLow = Color(0xFF0E1630);

  static const Color outline = Color(0x26FFFFFF);
  static const Color outlineSoft = Color(0x14FFFFFF);
  static const Color glassFill = Color(0x14FFFFFF);

  static const Color primary = Color(0xFF4C8DFF);
  static const Color primaryDeep = Color(0xFF3566E8);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color cyan = Color(0xFF22D3EE);

  static const Color success = Color(0xFF34D399);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFF87171);
  static const Color info = Color(0xFF60A5FA);

  static const Color textPrimary = Color(0xFFEEF3FF);
  static const Color textSecondary = Color(0xFFA7B3D6);
  static const Color textMuted = Color(0xFF6E7BA3);

  static const LinearGradient brand = LinearGradient(
    colors: [primary, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [Color(0x1FFFFFFF), Color(0x0AFFFFFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient background3d = LinearGradient(
    colors: [Color(0xFF0B1638), background, ink],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
