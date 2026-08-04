import 'package:flutter/material.dart';

/// Shared colors for the warm, playful child-facing visual language.
abstract final class AppColors {
  static const primary = Color(0xFF6B5BD2);
  static const primaryDeep = Color(0xFF5143B8);
  static const secondary = Color(0xFFC13E69);
  static const accent = Color(0xFFFFB84D);

  static const textPrimary = Color(0xFF3D3155);
  static const textSecondary = Color(0xFF6F6480);
  static const textMuted = Color(0xFF796D87);

  static const background = Color(0xFFFFF8F4);
  static const surfaceTint = Color(0xFFF6F1FF);
  static const outline = Color(0xFFE2D9EC);
  static const placeholder = Color(0xFFEDE6F2);

  static const addCharacterGradient = <Color>[
    Color(0xFF715BD8),
    Color(0xFFC13E69),
  ];
}
