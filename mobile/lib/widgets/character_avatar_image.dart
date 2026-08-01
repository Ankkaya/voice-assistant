import 'dart:io';

import 'package:flutter/material.dart';

import '../models/custom_character.dart';

class CharacterAvatarImage extends StatelessWidget {
  const CharacterAvatarImage({
    required this.avatar,
    required this.fallbackColor,
    this.fit = BoxFit.cover,
    super.key,
  });

  final CharacterAvatarRef avatar;
  final Color fallbackColor;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => switch (avatar.kind) {
    AvatarKind.asset => Image.asset(
      avatar.value,
      fit: fit,
      errorBuilder: (_, _, _) => _fallback(),
    ),
    AvatarKind.bundled => _bundledAvatar(),
    AvatarKind.localFile =>
      File(avatar.value).existsSync()
          ? Image.file(
              File(avatar.value),
              fit: fit,
              errorBuilder: (_, _, _) => _fallback(),
            )
          : _fallback(),
  };

  Widget _bundledAvatar() {
    final icon = switch (avatar.value) {
      'star' => Icons.star_rounded,
      'rocket' => Icons.rocket_launch_rounded,
      'book' => Icons.menu_book_rounded,
      'compass' => Icons.explore_rounded,
      'paw' => Icons.pets_rounded,
      'robot' => Icons.smart_toy_rounded,
      _ => Icons.person_rounded,
    };
    return ColoredBox(
      color: fallbackColor.withValues(alpha: 0.16),
      child: Center(child: Icon(icon, color: fallbackColor, size: 52)),
    );
  }

  Widget _fallback() => ColoredBox(
    color: fallbackColor.withValues(alpha: 0.16),
    child: Center(
      child: Icon(Icons.person_rounded, color: fallbackColor, size: 52),
    ),
  );
}
