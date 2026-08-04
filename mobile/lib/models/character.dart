import 'dart:io';

import 'package:flutter/widgets.dart';

import 'custom_character.dart';
import 'voice_selection.dart';

export 'custom_character.dart';

@immutable
class Character {
  const Character({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.avatar,
    required this.defaultVoiceDescription,
    required this.defaultVoice,
    required this.themeColor,
    this.source = CharacterSource.builtIn,
    this.profile,
    this.greeting,
    this.promptProfile = '',
  });

  final String id;
  final String name;
  final String subtitle;
  final CharacterAvatarRef avatar;
  final String defaultVoiceDescription;
  final Color themeColor;
  final CharacterSource source;
  final CustomCharacterProfile? profile;
  final String? greeting;
  final String promptProfile;
  final VoiceSelection defaultVoice;

  bool get isCustom => source == CharacterSource.custom;

  String get displaySubtitle =>
      isCustom && subtitle.trim().isEmpty ? '我的 AI 伙伴' : subtitle;

  Map<String, Object>? get customCharacterProtocolJson {
    if (!isCustom) return null;
    final profile = this.profile;
    final greeting = this.greeting;
    if (profile == null || greeting == null) {
      throw StateError('Custom character is missing its profile or greeting');
    }
    return {
      'displayName': name,
      'greeting': greeting,
      'identityId': profile.identityId,
      'traitIds': List<String>.from(profile.traitIds),
      'interestIds': List<String>.from(profile.interestIds),
      if (profile.description.trim().isNotEmpty)
        'description': profile.description,
      if (promptProfile.trim().isNotEmpty)
        'promptProfile': promptProfile.trim(),
    };
  }

  factory Character.fromBundledJson(Map<String, Object?> json) {
    final defaultVoiceDescription = _requiredString(
      json,
      'defaultVoiceDescription',
    );
    final profileJson = json['profile'];
    if (profileJson is! Map) {
      throw const FormatException('Bundled character profile is invalid');
    }
    final presetVoice = (json['defaultPresetVoice'] as String?) ?? '';
    return Character(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      subtitle: _requiredString(json, 'subtitle'),
      avatar: CharacterAvatarRef.asset(_requiredString(json, 'avatar')),
      defaultVoiceDescription: defaultVoiceDescription,
      themeColor: _color(json['themeColor']),
      profile: CustomCharacterProfile.fromJson(
        profileJson.cast<String, Object?>(),
      ),
      greeting: _requiredString(json, 'greeting'),
      promptProfile: _requiredString(json, 'promptProfile'),
      defaultVoice: VoiceSelection(
        mode: VoiceMode.preset,
        presetVoice: presetVoice,
      ),
    );
  }

  // Kept as a source-compatible alias for callers loading bundled records.
  factory Character.fromJson(Map<String, Object?> json) =>
      Character.fromBundledJson(json);

  factory Character.fromCustomJson(
    Map<String, Object?> json, {
    required Directory root,
  }) {
    final profileJson = json['profile'];
    final voiceJson = json['defaultVoice'];
    final avatarJson = json['avatar'];
    if (profileJson is! Map || voiceJson is! Map || avatarJson is! Map) {
      throw const FormatException('Custom character has invalid nested data');
    }
    final profile = CustomCharacterProfile.fromJson(
      profileJson.cast<String, Object?>(),
    );
    final greeting = _requiredString(json, 'greeting');
    final promptProfile = (json['promptProfile'] as String?)?.trim() ?? '';
    final defaultVoice = VoiceSelection.fromStorageJson(
      voiceJson.cast<String, Object?>(),
    );
    final runtimeVoice = _resolveVoicePath(defaultVoice, root);
    return Character(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      subtitle: (json['subtitle'] as String?) ?? '',
      avatar: CharacterAvatarRef.fromJson(
        avatarJson.cast<String, Object?>(),
        root: root,
      ),
      defaultVoiceDescription: runtimeVoice.voiceDescription ?? '',
      themeColor: _color(json['themeColor']),
      source: CharacterSource.custom,
      profile: profile,
      greeting: greeting,
      promptProfile: promptProfile,
      defaultVoice: runtimeVoice,
    );
  }

  Map<String, Object> toStorageJson({required Directory root}) {
    if (!isCustom) {
      throw StateError('Only custom characters can be stored');
    }
    final profile = this.profile;
    final greeting = this.greeting;
    if (profile == null || greeting == null) {
      throw StateError('Custom character is missing its profile or greeting');
    }
    final voice = _storageVoice(defaultVoice, root);
    return {
      'id': id,
      'name': name,
      'subtitle': subtitle,
      'avatar': avatar.toStorageJson(root: root),
      'themeColor': _colorHex(themeColor),
      'profile': profile.toJson(),
      'greeting': greeting,
      if (promptProfile.trim().isNotEmpty)
        'promptProfile': promptProfile.trim(),
      'defaultVoice': voice,
    };
  }

  static VoiceSelection _resolveVoicePath(
    VoiceSelection voice,
    Directory root,
  ) {
    if (voice.mode != VoiceMode.voiceClone || voice.referencePath == null) {
      return voice;
    }
    final path = _resolveLocalPath(voice.referencePath!, root);
    return VoiceSelection(
      mode: voice.mode,
      presetVoice: voice.presetVoice,
      voiceDescription: voice.voiceDescription,
      referencePath: path,
      referenceName: voice.referenceName,
      referenceId: voice.referenceId,
      cloneAuthorized: voice.cloneAuthorized,
    );
  }

  static Map<String, Object> _storageVoice(
    VoiceSelection voice,
    Directory root,
  ) {
    final json = voice.toStorageJson();
    if (voice.mode == VoiceMode.voiceClone) {
      json['referencePath'] = _relativeLocalPath(voice.referencePath!, root);
    }
    return json;
  }

  static String _resolveLocalPath(String path, Directory root) {
    if (path.startsWith('/') || path.split('/').contains('..')) {
      throw const FormatException(
        'Path must be relative to app support storage',
      );
    }
    return '${File(root.path).absolute.path}/${path.replaceAll('\\', '/')}';
  }

  static String _relativeLocalPath(String path, Directory root) {
    final rootPath = File(root.path).absolute.path.replaceAll('\\', '/');
    final filePath = File(path).absolute.path.replaceAll('\\', '/');
    final prefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
    if (filePath == rootPath || !filePath.startsWith(prefix)) {
      throw const FormatException(
        'Local asset must be inside app support storage',
      );
    }
    final relative = filePath.substring(prefix.length);
    if (relative.isEmpty || relative.split('/').contains('..')) {
      throw const FormatException('Local asset path is invalid');
    }
    return relative;
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  static Color _color(Object? value) {
    if (value is! String) throw const FormatException('Invalid theme color');
    final hex = value.replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) {
      throw const FormatException('Theme color must be a six-digit hex value');
    }
    return Color(int.parse('FF$hex', radix: 16));
  }

  static String _colorHex(Color color) =>
      '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
}
