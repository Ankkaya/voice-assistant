import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/character.dart';
import '../models/voice_selection.dart';
import '../services/character_asset_store.dart';

enum CharacterLoadWarning { invalidRecord, invalidStore }

class CharacterLoadResult {
  const CharacterLoadResult({required this.characters, required this.warnings});

  final List<Character> characters;
  final Set<CharacterLoadWarning> warnings;
}

class CharacterDraftValidationException implements Exception {
  const CharacterDraftValidationException(this.errors);
  final List<CharacterFieldError> errors;
}

abstract interface class AtomicStoreWriter {
  Future<void> write(File destination, Map<String, Object?> document);
}

final class FileAtomicStoreWriter implements AtomicStoreWriter {
  const FileAtomicStoreWriter();

  @override
  Future<void> write(File destination, Map<String, Object?> document) async {
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(document), flush: true);
      await temporary.rename(destination.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}

class CustomCharacterRepository {
  CustomCharacterRepository({
    required this.root,
    required this.assets,
    Uuid? uuid,
    AtomicStoreWriter? writer,
  }) : uuid = uuid ?? const Uuid(),
       writer = writer ?? const FileAtomicStoreWriter();

  final Directory root;
  final CharacterAssetStore assets;
  final Uuid uuid;
  final AtomicStoreWriter writer;

  File get storeFile => File('${root.path}/custom_characters.json');

  Future<List<Character>> load() async => (await loadWithWarnings()).characters;

  Future<CharacterLoadResult> loadWithWarnings() async {
    if (!await storeFile.exists()) {
      await _purgeBestEffort(const {});
      return const CharacterLoadResult(characters: [], warnings: {});
    }
    late Map<String, Object?> document;
    try {
      document = await _readDocument();
    } on Object {
      return const CharacterLoadResult(
        characters: [],
        warnings: {CharacterLoadWarning.invalidStore},
      );
    }

    final characters = <Character>[];
    final warnings = <CharacterLoadWarning>{};
    final references = <String>{};
    final seenIds = <String>{};
    for (final value in document['characters']! as List<Object?>) {
      try {
        if (value is! Map) throw const FormatException('Invalid character');
        final record = value.cast<String, Object?>();
        final character = Character.fromCustomJson(record, root: root);
        _validateStoredCharacter(character);
        if (!seenIds.add(character.id)) {
          throw const FormatException('Duplicate custom character ID');
        }
        characters.add(character);
        references.addAll(_recordAssets(record));
      } on Object {
        warnings.add(CharacterLoadWarning.invalidRecord);
      }
    }
    await _purgeBestEffort(references);
    return CharacterLoadResult(characters: characters, warnings: warnings);
  }

  Future<Character> create(CustomCharacterDraft draft) async {
    _validateDraft(draft);
    final id = 'custom_${uuid.v4().replaceAll('-', '').toLowerCase()}';
    final now = DateTime.now().toUtc().toIso8601String();
    final prepared = await _prepareRecord(
      draft,
      id: id,
      createdAt: now,
      updatedAt: now,
    );
    File? corruptBackup;
    try {
      Map<String, Object?> document;
      if (!await storeFile.exists()) {
        document = _emptyDocument();
      } else {
        try {
          document = await _readDocument();
        } on Object {
          corruptBackup = File(
            '${storeFile.path}.corrupt.${DateTime.now().toUtc().millisecondsSinceEpoch}',
          );
          await storeFile.rename(corruptBackup.path);
          document = _emptyDocument();
        }
      }
      final records = List<Object?>.from(document['characters']! as List);
      records.add(prepared.record);
      final updated = <String, Object?>{
        'schemaVersion': 1,
        'characters': records,
      };
      await writer.write(storeFile, updated);
      await _purgeBestEffort(_documentAssets(updated));
      return Character.fromCustomJson(prepared.record, root: root);
    } on Object {
      await _deleteBestEffort(prepared.newAssets);
      if (corruptBackup != null && await corruptBackup.exists()) {
        if (await storeFile.exists()) await storeFile.delete();
        await corruptBackup.rename(storeFile.path);
      }
      rethrow;
    }
  }

  Future<Character> update(String id, CustomCharacterDraft draft) async {
    _validateDraft(draft);
    final document = await _readDocument();
    final records = List<Object?>.from(document['characters']! as List);
    final index = records.indexWhere(
      (value) => value is Map && value['id'] == id,
    );
    if (index < 0) throw StateError('Custom character not found');
    final oldRecord = (records[index] as Map).cast<String, Object?>();
    final createdAt = oldRecord['createdAt'] is String
        ? oldRecord['createdAt']! as String
        : DateTime.now().toUtc().toIso8601String();
    final prepared = await _prepareRecord(
      draft,
      id: id,
      createdAt: createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    try {
      records[index] = prepared.record;
      final updated = <String, Object?>{
        'schemaVersion': 1,
        'characters': records,
      };
      await writer.write(storeFile, updated);
      await _deleteBestEffort(_recordAssets(oldRecord));
      await _purgeBestEffort(_documentAssets(updated));
      return Character.fromCustomJson(prepared.record, root: root);
    } on Object {
      await _deleteBestEffort(prepared.newAssets);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final document = await _readDocument();
    final records = List<Object?>.from(document['characters']! as List);
    final index = records.indexWhere(
      (value) => value is Map && value['id'] == id,
    );
    if (index < 0) throw StateError('Custom character not found');
    final removed = (records.removeAt(index) as Map).cast<String, Object?>();
    final updated = <String, Object?>{
      'schemaVersion': 1,
      'characters': records,
    };
    await writer.write(storeFile, updated);
    await _deleteBestEffort(_recordAssets(removed));
    await _purgeBestEffort(_documentAssets(updated));
  }

  Future<_PreparedRecord> _prepareRecord(
    CustomCharacterDraft draft, {
    required String id,
    required String createdAt,
    required String updatedAt,
  }) async {
    final imported = <String>[];
    try {
      late Map<String, Object> avatar;
      switch (draft.avatar.kind) {
        case AvatarKind.bundled:
          avatar = {'kind': 'bundled', 'value': draft.avatar.value};
        case AvatarKind.localFile:
          final relative = await assets.importAvatar(draft.avatar.value, id);
          imported.add(relative);
          avatar = {'kind': 'local_file', 'value': relative};
        case AvatarKind.asset:
          throw const FormatException('Custom avatar cannot use an asset path');
      }

      late Map<String, Object> voice;
      switch (draft.defaultVoice.mode) {
        case VoiceMode.preset:
          voice = {
            'mode': 'preset',
            'voice': draft.defaultVoice.presetVoice!.trim(),
          };
        case VoiceMode.voiceDesign:
          voice = {
            'mode': 'voice_design',
            'voiceDescription': draft.defaultVoice.voiceDescription!.trim(),
          };
        case VoiceMode.voiceClone:
          final relative = await assets.importVoiceReference(
            draft.defaultVoice.referencePath!,
            id,
          );
          imported.add(relative);
          voice = {
            'mode': 'voice_clone',
            'referencePath': relative,
            if (draft.defaultVoice.referenceName != null)
              'referenceName': draft.defaultVoice.referenceName!,
            'cloneAuthorized': true,
          };
      }

      final color = (draft.themeColorValue & 0xffffff)
          .toRadixString(16)
          .padLeft(6, '0')
          .toUpperCase();
      return _PreparedRecord(
        record: {
          'id': id,
          'name': draft.name.trim(),
          'subtitle': draft.subtitle.trim(),
          'avatar': avatar,
          'themeColor': '#$color',
          'profile': {
            'identityId': draft.profile.identityId,
            'traitIds': List<String>.from(draft.profile.traitIds),
            'interestIds': List<String>.from(draft.profile.interestIds),
            'description': draft.profile.description.trim(),
          },
          'greeting': draft.greeting.trim(),
          'defaultVoice': voice,
          'createdAt': createdAt,
          'updatedAt': updatedAt,
        },
        newAssets: imported,
      );
    } on Object {
      await _deleteBestEffort(imported);
      rethrow;
    }
  }

  Future<Map<String, Object?>> _readDocument() async {
    final decoded = jsonDecode(await storeFile.readAsString());
    if (decoded is! Map) throw const FormatException('Store must be an object');
    final document = decoded.cast<String, Object?>();
    if (document['schemaVersion'] != 1 || document['characters'] is! List) {
      throw const FormatException('Unsupported custom character store');
    }
    return document;
  }

  static Map<String, Object?> _emptyDocument() => {
    'schemaVersion': 1,
    'characters': <Object?>[],
  };

  static void _validateDraft(CustomCharacterDraft draft) {
    final errors = draft.validate();
    if (errors.isNotEmpty) throw CharacterDraftValidationException(errors);
  }

  static void _validateStoredCharacter(Character character) {
    if (!RegExp(r'^custom_[a-f0-9]{32}$').hasMatch(character.id)) {
      throw const FormatException('Invalid custom character ID');
    }
    final draft = CustomCharacterDraft(
      name: character.name,
      subtitle: character.subtitle,
      avatar: character.avatar,
      themeColorValue: character.themeColor.toARGB32(),
      profile: character.profile!,
      greeting: character.greeting!,
      defaultVoice: character.defaultVoice,
    );
    if (draft.validate().isNotEmpty) {
      throw const FormatException('Stored custom character is invalid');
    }
  }

  static Set<String> _recordAssets(Map<String, Object?> record) {
    final result = <String>{};
    final avatar = record['avatar'];
    if (avatar is Map &&
        avatar['kind'] == 'local_file' &&
        avatar['value'] is String) {
      result.add(avatar['value']! as String);
    }
    final voice = record['defaultVoice'];
    if (voice is Map &&
        voice['mode'] == 'voice_clone' &&
        voice['referencePath'] is String) {
      result.add(voice['referencePath']! as String);
    }
    return result;
  }

  static Set<String> _documentAssets(Map<String, Object?> document) {
    final result = <String>{};
    for (final value in document['characters']! as List) {
      if (value is Map) {
        result.addAll(_recordAssets(value.cast<String, Object?>()));
      }
    }
    return result;
  }

  Future<void> _deleteBestEffort(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        await assets.deleteRelative(path);
      } on Object {
        // Metadata is authoritative; orphan cleanup retries on the next load.
      }
    }
  }

  Future<void> _purgeBestEffort(Set<String> references) async {
    try {
      await assets.purgeOrphans(references);
    } on Object {
      // Asset cleanup must not make otherwise valid local data unavailable.
    }
  }
}

class _PreparedRecord {
  const _PreparedRecord({required this.record, required this.newAssets});
  final Map<String, Object?> record;
  final List<String> newAssets;
}
