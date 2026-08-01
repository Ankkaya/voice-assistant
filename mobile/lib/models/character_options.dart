import 'package:flutter/foundation.dart';

@immutable
class CharacterOption {
  const CharacterOption({required this.id, required this.label});

  final String id;
  final String label;

  factory CharacterOption.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const {'id', 'label'});
    final id = _requiredString(json, 'id');
    final label = _requiredString(json, 'label');
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(id)) {
      throw const FormatException('Character option ID is invalid');
    }
    if (label.runes.length > 20) {
      throw const FormatException('Character option label is too long');
    }
    return CharacterOption(id: id, label: label);
  }

  Map<String, Object> toJson() => {'id': id, 'label': label};
}

@immutable
class PresetVoiceOption {
  const PresetVoiceOption({required this.id, required this.label});

  final String id;
  final String label;

  factory PresetVoiceOption.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const {'id', 'label'});
    final id = _requiredString(json, 'id');
    final label = _requiredString(json, 'label');
    if (id.runes.length > 40 || label.runes.length > 40) {
      throw const FormatException('Preset voice option is too long');
    }
    return PresetVoiceOption(id: id, label: label);
  }

  Map<String, Object> toJson() => {'id': id, 'label': label};
}

@immutable
class CharacterOptions {
  const CharacterOptions({
    required this.optionsVersion,
    required this.identities,
    required this.traits,
    required this.interests,
    required this.presetVoices,
  });

  final int optionsVersion;
  final List<CharacterOption> identities;
  final List<CharacterOption> traits;
  final List<CharacterOption> interests;
  final List<PresetVoiceOption> presetVoices;

  factory CharacterOptions.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const {
      'optionsVersion',
      'identities',
      'traits',
      'interests',
      'presetVoices',
    });
    final version = json['optionsVersion'];
    if (version is! int || version < 1) {
      throw const FormatException('Options version must be positive');
    }

    List<CharacterOption> options(String key) {
      final records = _records(json, key);
      final result = records
          .map(CharacterOption.fromJson)
          .toList(growable: false);
      _requireUniqueIds(result.map((option) => option.id), key);
      return result;
    }

    final voiceRecords = _records(json, 'presetVoices');
    final voices = voiceRecords
        .map(PresetVoiceOption.fromJson)
        .toList(growable: false);
    _requireUniqueIds(voices.map((voice) => voice.id), 'presetVoices');
    return CharacterOptions(
      optionsVersion: version,
      identities: options('identities'),
      traits: options('traits'),
      interests: options('interests'),
      presetVoices: voices,
    );
  }

  Map<String, Object> toJson() => {
    'optionsVersion': optionsVersion,
    'identities': identities.map((option) => option.toJson()).toList(),
    'traits': traits.map((option) => option.toJson()).toList(),
    'interests': interests.map((option) => option.toJson()).toList(),
    'presetVoices': presetVoices.map((voice) => voice.toJson()).toList(),
  };

  static List<Map<String, Object?>> _records(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value is! List || value.isEmpty) {
      throw FormatException('$key must be a non-empty list');
    }
    return value
        .map((record) {
          if (record is! Map) {
            throw FormatException('$key contains invalid data');
          }
          return record.cast<String, Object?>();
        })
        .toList(growable: false);
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

void _requireExactKeys(Map<String, Object?> json, Set<String> expected) {
  if (!setEquals(json.keys.toSet(), expected)) {
    throw const FormatException('Character options contain unknown fields');
  }
}

void _requireUniqueIds(Iterable<String> ids, String key) {
  final values = ids.toList(growable: false);
  if (values.length != values.toSet().length) {
    throw FormatException('$key contains duplicate IDs');
  }
}
