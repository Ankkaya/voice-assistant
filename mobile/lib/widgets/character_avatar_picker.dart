import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/custom_character.dart';
import 'character_avatar_image.dart';

abstract interface class AvatarPicker {
  Future<String?> pickImagePath();
}

class GalleryAvatarPicker implements AvatarPicker {
  GalleryAvatarPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<String?> pickImagePath() async =>
      (await _picker.pickImage(source: ImageSource.gallery))?.path;
}

const bundledAvatarColors = <String, int>{
  'star': 0xfff4b942,
  'rocket': 0xff5b7cfa,
  'book': 0xff8b5cf6,
  'compass': 0xff14b8a6,
  'paw': 0xfff97316,
  'robot': 0xff64748b,
};

const galleryAvatarColor = 0xff5b7cfa;

class CharacterAvatarPicker extends StatefulWidget {
  const CharacterAvatarPicker({
    required this.initialAvatar,
    required this.initialColorValue,
    required this.onChanged,
    this.picker,
    this.enabled = true,
    super.key,
  });

  final CharacterAvatarRef initialAvatar;
  final int initialColorValue;
  final void Function(CharacterAvatarRef avatar, int colorValue) onChanged;
  final AvatarPicker? picker;
  final bool enabled;

  @override
  State<CharacterAvatarPicker> createState() => _CharacterAvatarPickerState();
}

class _CharacterAvatarPickerState extends State<CharacterAvatarPicker> {
  late CharacterAvatarRef _avatar;
  late int _colorValue;

  @override
  void initState() {
    super.initState();
    _avatar = widget.initialAvatar;
    _colorValue = widget.initialColorValue;
  }

  Future<void> _pickGallery() async {
    final path = await (widget.picker ?? GalleryAvatarPicker()).pickImagePath();
    if (!mounted || path == null) return;
    _update(CharacterAvatarRef.localFile(path), galleryAvatarColor);
  }

  void _update(CharacterAvatarRef avatar, int colorValue) {
    setState(() {
      _avatar = avatar;
      _colorValue = colorValue;
    });
    widget.onChanged(avatar, colorValue);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('角色头像', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 72,
                height: 72,
                child: CharacterAvatarImage(
                  avatar: _avatar,
                  fallbackColor: Color(_colorValue),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in bundledAvatarColors.entries)
                    ChoiceChip(
                      key: ValueKey('avatar_${entry.key}'),
                      selected:
                          _avatar.kind == AvatarKind.bundled &&
                          _avatar.value == entry.key,
                      avatar: Icon(
                        _icon(entry.key),
                        color: Color(entry.value),
                        size: 18,
                      ),
                      label: Text(_label(entry.key)),
                      onSelected: widget.enabled
                          ? (_) => _update(
                              CharacterAvatarRef.bundled(entry.key),
                              entry.value,
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('avatar_gallery'),
          onPressed: widget.enabled ? _pickGallery : null,
          icon: const Icon(Icons.photo_library_rounded),
          label: const Text('从相册选择'),
        ),
      ],
    );
  }

  static IconData _icon(String id) => switch (id) {
    'star' => Icons.star_rounded,
    'rocket' => Icons.rocket_launch_rounded,
    'book' => Icons.menu_book_rounded,
    'compass' => Icons.explore_rounded,
    'paw' => Icons.pets_rounded,
    'robot' => Icons.smart_toy_rounded,
    _ => Icons.person_rounded,
  };

  static String _label(String id) => switch (id) {
    'star' => '星星',
    'rocket' => '火箭',
    'book' => '书本',
    'compass' => '指南针',
    'paw' => '爪印',
    'robot' => '机器人',
    _ => id,
  };
}
