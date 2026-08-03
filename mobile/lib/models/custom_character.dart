import 'dart:io';

import 'package:flutter/foundation.dart';

import 'voice_selection.dart';

enum CharacterSource { builtIn, custom }

enum AvatarKind { asset, bundled, localFile }

@immutable
class CharacterAvatarRef {
  const CharacterAvatarRef({required this.kind, required this.value});
  const CharacterAvatarRef.asset(String value)
    : this(kind: AvatarKind.asset, value: value);
  const CharacterAvatarRef.bundled(String value)
    : this(kind: AvatarKind.bundled, value: value);
  const CharacterAvatarRef.localFile(String value)
    : this(kind: AvatarKind.localFile, value: value);

  final AvatarKind kind;
  final String value;

  static CharacterAvatarRef fromJson(
    Map<String, Object?> json, {
    Directory? root,
  }) {
    final kind = switch (json['kind']) {
      'asset' => AvatarKind.asset,
      'bundled' => AvatarKind.bundled,
      'local_file' => AvatarKind.localFile,
      final value => throw FormatException('Unknown avatar kind: $value'),
    };
    final value = json['value'];
    if (value is! String || value.isEmpty) {
      throw const FormatException('Avatar value must be a non-empty string');
    }
    if (kind != AvatarKind.localFile) {
      return CharacterAvatarRef(kind: kind, value: value);
    }
    if (root == null) {
      throw const FormatException('A root is required for local avatars');
    }
    return CharacterAvatarRef.localFile(_resolveRelativePath(value, root));
  }

  Map<String, Object> toStorageJson({required Directory root}) {
    final storedValue = kind == AvatarKind.localFile
        ? _relativePath(value, root)
        : value;
    return {'kind': _kindName(kind), 'value': storedValue};
  }

  static String _kindName(AvatarKind kind) => switch (kind) {
    AvatarKind.asset => 'asset',
    AvatarKind.bundled => 'bundled',
    AvatarKind.localFile => 'local_file',
  };
}

@immutable
class CustomCharacterProfile {
  const CustomCharacterProfile({
    required this.identityId,
    required this.traitIds,
    required this.interestIds,
    required this.description,
  });

  final String identityId;
  final List<String> traitIds;
  final List<String> interestIds;
  final String description;

  factory CustomCharacterProfile.fromJson(Map<String, Object?> json) {
    List<String> strings(String key) {
      final value = json[key];
      if (value is! List) throw FormatException('$key must be a list');
      return value
          .map((item) {
            if (item is! String || item.isEmpty) {
              throw FormatException('$key must contain strings');
            }
            return item;
          })
          .toList(growable: false);
    }

    final identity = json['identityId'];
    final description = json['description'];
    if (identity is! String || identity.isEmpty || description is! String) {
      throw const FormatException('Invalid custom character profile');
    }
    return CustomCharacterProfile(
      identityId: identity,
      traitIds: strings('traitIds'),
      interestIds: strings('interestIds'),
      description: description,
    );
  }

  Map<String, Object> toJson() => {
    'identityId': identityId,
    'traitIds': List<String>.from(traitIds),
    'interestIds': List<String>.from(interestIds),
    'description': description,
  };
}

@immutable
class CharacterFieldError {
  const CharacterFieldError(this.field, this.message);
  final String field;
  final String message;
}

@immutable
class CustomCharacterDraft {
  const CustomCharacterDraft({
    required this.name,
    required this.subtitle,
    required this.avatar,
    required this.themeColorValue,
    required this.profile,
    required this.greeting,
    required this.defaultVoice,
    this.promptProfile = '',
  });

  final String name;
  final String subtitle;
  final CharacterAvatarRef avatar;
  final int themeColorValue;
  final CustomCharacterProfile profile;
  final String greeting;
  final VoiceSelection defaultVoice;
  final String promptProfile;

  List<CharacterFieldError> validate() {
    final errors = <CharacterFieldError>[];
    final name = this.name.trim();
    final subtitle = this.subtitle.trim();
    final greeting = this.greeting.trim();
    final description = profile.description.trim();
    int characterCount(String value) => value.runes.length;
    void limit(String field, String label, String value, int max) {
      if (characterCount(value) > max) {
        errors.add(CharacterFieldError(field, '$label不能超过 $max 个字'));
      }
    }

    if (name.isEmpty) errors.add(const CharacterFieldError('name', '请输入角色名称'));
    limit('name', '角色名称', name, 20);
    limit('subtitle', '一句话介绍', subtitle, 30);
    if (greeting.isEmpty) {
      errors.add(const CharacterFieldError('greeting', '请输入开场白'));
    }
    limit('greeting', '开场白', greeting, 120);
    limit('description', '补充描述', description, 200);
    limit('promptProfile', '角色内置提示词', promptProfile.trim(), 2000);
    if (profile.identityId.trim().isEmpty) {
      errors.add(const CharacterFieldError('identityId', '请选择角色身份'));
    }
    if (profile.traitIds.isEmpty) {
      errors.add(const CharacterFieldError('traitIds', '至少选择一个性格'));
    }
    if (profile.traitIds.length > 3) {
      errors.add(const CharacterFieldError('traitIds', '最多选择三个性格'));
    }
    if (profile.interestIds.length > 3) {
      errors.add(const CharacterFieldError('interestIds', '最多选择三个兴趣'));
    }
    if (_hasDuplicates(profile.traitIds)) {
      errors.add(const CharacterFieldError('traitIds', '性格不能重复'));
    }
    if (_hasDuplicates(profile.interestIds)) {
      errors.add(const CharacterFieldError('interestIds', '兴趣不能重复'));
    }
    switch (defaultVoice.mode) {
      case VoiceMode.preset:
        if ((defaultVoice.presetVoice ?? '').trim().isEmpty) {
          errors.add(const CharacterFieldError('voice', '请选择预置音色'));
        }
      case VoiceMode.voiceDesign:
        final description = defaultVoice.voiceDescription?.trim() ?? '';
        if (characterCount(description) < 8 ||
            characterCount(description) > 500) {
          errors.add(const CharacterFieldError('voice', '音色描述需为 8～500 个字'));
        }
      case VoiceMode.voiceClone:
        if ((defaultVoice.referencePath ?? '').trim().isEmpty) {
          errors.add(const CharacterFieldError('voice', '请选择参考音频'));
        }
        if (!defaultVoice.cloneAuthorized) {
          errors.add(const CharacterFieldError('voice', '请确认已获得声音使用授权'));
        }
    }
    return errors;
  }

  static bool _hasDuplicates(List<String> values) =>
      values.length != values.toSet().length;
}

String _resolveRelativePath(String value, Directory root) {
  if (value.startsWith('/') || value.split('/').contains('..')) {
    throw const FormatException('Path must be relative to app support storage');
  }
  return _joinPath(root.path, value);
}

String _relativePath(String value, Directory root) {
  final rootPath = _canonicalPath(root.path);
  final filePath = _canonicalPath(value);
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

String _canonicalPath(String value) =>
    File(value).absolute.path.replaceAll('\\', '/');

String _joinPath(String root, String relative) {
  final normalizedRoot = _canonicalPath(root);
  return '$normalizedRoot/${relative.replaceAll('\\', '/')}';
}
