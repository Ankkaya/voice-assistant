import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/voice_selection.dart';
import '../services/character_asset_store.dart';

enum VoicePreferenceWarning { invalidStore, invalidRecord, missingReference }

class VoicePreferencesLoadResult {
  const VoicePreferencesLoadResult({
    required this.preferences,
    required this.warnings,
    required this.invalidCharacterIds,
  });

  final Map<String, VoiceSelection> preferences;
  final Set<VoicePreferenceWarning> warnings;
  final Set<String> invalidCharacterIds;
}

abstract interface class VoicePreferencesWriter {
  Future<void> write(File destination, Map<String, Object?> document);
}

final class FileVoicePreferencesWriter implements VoicePreferencesWriter {
  const FileVoicePreferencesWriter();

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

class CharacterVoicePreferencesRepository {
  CharacterVoicePreferencesRepository({
    required this.root,
    this.writer = const FileVoicePreferencesWriter(),
  });

  final Directory root;
  final VoicePreferencesWriter writer;

  static final RegExp _characterIdPattern = RegExp(r'^[a-zA-Z0-9_]+$');
  static int _fileSequence = 0;
  Future<void> _mutationQueue = Future<void>.value();

  File get storeFile => File('${root.path}/character_voice_preferences.json');

  Directory get referencesDirectory =>
      Directory('${root.path}/voice_preferences');

  Future<VoicePreferencesLoadResult> load() async {
    if (!await storeFile.exists()) {
      return const VoicePreferencesLoadResult(
        preferences: {},
        warnings: {},
        invalidCharacterIds: {},
      );
    }

    late Map<String, Object?> document;
    try {
      document = await _readDocument();
    } on Object {
      return const VoicePreferencesLoadResult(
        preferences: {},
        warnings: {VoicePreferenceWarning.invalidStore},
        invalidCharacterIds: {},
      );
    }

    final preferences = <String, VoiceSelection>{};
    final warnings = <VoicePreferenceWarning>{};
    final invalidCharacterIds = <String>{};
    final records = document['preferences']! as Map<String, Object?>;
    for (final entry in records.entries) {
      final characterId = entry.key;
      try {
        _validateCharacterId(characterId);
        final value = entry.value;
        if (value is! Map) {
          throw const FormatException('Voice preference must be an object');
        }
        var selection = VoiceSelection.fromStorageJson(
          value.cast<String, Object?>(),
        );
        if (selection.mode == VoiceMode.voiceClone) {
          final relativePath = selection.referencePath!;
          final reference = _privateReferenceFile(relativePath);
          if (!await reference.exists()) {
            warnings.add(VoicePreferenceWarning.missingReference);
            invalidCharacterIds.add(characterId);
            continue;
          }
          selection = VoiceSelection(
            mode: VoiceMode.voiceClone,
            referencePath: reference.absolute.path,
            referenceName: selection.referenceName,
            cloneAuthorized: true,
          );
        }
        preferences[characterId] = selection;
      } on Object {
        warnings.add(VoicePreferenceWarning.invalidRecord);
        invalidCharacterIds.add(characterId);
      }
    }

    return VoicePreferencesLoadResult(
      preferences: Map.unmodifiable(preferences),
      warnings: Set.unmodifiable(warnings),
      invalidCharacterIds: Set.unmodifiable(invalidCharacterIds),
    );
  }

  Future<VoiceSelection> save(String characterId, VoiceSelection selection) =>
      _serializeMutation(() => _save(characterId, selection));

  Future<VoiceSelection> _save(
    String characterId,
    VoiceSelection selection,
  ) async {
    _validateCharacterId(characterId);
    final document = await _documentForMutation();
    final records = Map<String, Object?>.from(
      document['preferences']! as Map<String, Object?>,
    );
    final oldReference = _cloneReferenceFromRecord(records[characterId]);

    File? importedReference;
    late VoiceSelection normalized;
    try {
      if (selection.mode == VoiceMode.voiceClone) {
        importedReference = await _importClone(selection, characterId);
        normalized = VoiceSelection(
          mode: VoiceMode.voiceClone,
          referencePath: importedReference.absolute.path,
          referenceName: selection.referenceName,
          cloneAuthorized: true,
        );
        records[characterId] = {
          ...normalized.toStorageJson(),
          'referencePath': _relativeReferencePath(importedReference),
        };
      } else {
        normalized = VoiceSelection.fromStorageJson(selection.toStorageJson());
        records[characterId] = normalized.toStorageJson();
      }

      await writer.write(storeFile, {
        'schemaVersion': 1,
        'preferences': records,
      });
    } on Object {
      if (importedReference != null) {
        await _deleteBestEffort(importedReference);
      }
      rethrow;
    }

    if (oldReference != null && oldReference.path != importedReference?.path) {
      await _deleteBestEffort(oldReference);
    }
    return normalized;
  }

  Future<void> delete(String characterId) =>
      _serializeMutation(() => _delete(characterId));

  Future<void> _delete(String characterId) async {
    _validateCharacterId(characterId);
    if (!await storeFile.exists()) return;
    final document = await _readDocument();
    final records = Map<String, Object?>.from(
      document['preferences']! as Map<String, Object?>,
    );
    final removed = records.remove(characterId);
    if (removed == null) return;
    final oldReference = _cloneReferenceFromRecord(removed);

    await writer.write(storeFile, {'schemaVersion': 1, 'preferences': records});
    if (oldReference != null) await _deleteBestEffort(oldReference);
  }

  Future<void> prune(Set<String> validCharacterIds) =>
      _serializeMutation(() => _prune(validCharacterIds));

  Future<void> _prune(Set<String> validCharacterIds) async {
    try {
      if (!await storeFile.exists()) return;
      final document = await _readDocument();
      final records = Map<String, Object?>.from(
        document['preferences']! as Map<String, Object?>,
      );
      final removedReferences = <File>[];
      var changed = false;
      for (final characterId in records.keys.toList()) {
        if (validCharacterIds.contains(characterId)) continue;
        final removed = records.remove(characterId);
        final reference = _cloneReferenceFromRecord(removed);
        if (reference != null) removedReferences.add(reference);
        changed = true;
      }
      if (!changed) return;

      await writer.write(storeFile, {
        'schemaVersion': 1,
        'preferences': records,
      });
      for (final reference in removedReferences) {
        await _deleteBestEffort(reference);
      }
    } on Object {
      // Pruning is background maintenance and must not hide a usable catalog.
    }
  }

  Future<Map<String, Object?>> _documentForMutation() async {
    if (!await storeFile.exists()) return _emptyDocument();
    return _readDocument();
  }

  Future<T> _serializeMutation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _mutationQueue = _mutationQueue.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<Map<String, Object?>> _readDocument() async {
    final decoded = jsonDecode(await storeFile.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Voice preference store must be an object');
    }
    final document = decoded.cast<String, Object?>();
    final preferences = document['preferences'];
    if (document['schemaVersion'] != 1 || preferences is! Map) {
      throw const FormatException('Unsupported voice preference store');
    }
    return {
      'schemaVersion': 1,
      'preferences': preferences.cast<String, Object?>(),
    };
  }

  Future<File> _importClone(
    VoiceSelection selection,
    String characterId,
  ) async {
    if (!selection.cloneAuthorized) {
      throw const FormatException('Voice clone is not authorized');
    }
    final sourcePath = selection.referencePath;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      throw const FormatException('Voice clone reference path is required');
    }
    final source = File(sourcePath);
    final length = await source.length();
    if (length == 0) {
      throw const FormatException('Reference audio is empty');
    }
    if (length > maxVoiceReferenceBytes) {
      throw RangeError('Reference audio exceeds 7.5 MB');
    }
    final lowerPath = source.path.toLowerCase();
    final extension = lowerPath.endsWith('.wav')
        ? '.wav'
        : lowerPath.endsWith('.mp3')
        ? '.mp3'
        : null;
    if (extension == null) {
      throw const FormatException('Reference audio must be WAV or MP3');
    }

    final bytes = await source.readAsBytes();
    final validWav =
        extension == '.wav' &&
        bytes.length >= 12 &&
        _ascii(bytes, 0, 4) == 'RIFF' &&
        _ascii(bytes, 8, 12) == 'WAVE';
    final validMp3 =
        extension == '.mp3' &&
        (_startsWith(bytes, const [0x49, 0x44, 0x33]) ||
            (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0));
    if (!validWav && !validMp3) {
      throw const FormatException('Reference audio content is invalid');
    }

    await referencesDirectory.create(recursive: true);
    final sequence = _fileSequence++;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final destination = File(
      '${referencesDirectory.path}/${characterId}_${timestamp}_$sequence$extension',
    );
    final temporary = File('${destination.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(destination.path);
      return destination;
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  File? _cloneReferenceFromRecord(Object? value) {
    if (value is! Map || value['mode'] != 'voice_clone') return null;
    final path = value['referencePath'];
    if (path is! String) return null;
    try {
      return _privateReferenceFile(path);
    } on FormatException {
      return null;
    }
  }

  File _privateReferenceFile(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final segments = normalized.split('/');
    if (normalized.startsWith('/') ||
        segments.length != 2 ||
        segments.first != 'voice_preferences' ||
        segments.last.isEmpty ||
        segments.contains('..')) {
      throw const FormatException('Voice reference path is not private');
    }
    return File('${root.path}/$normalized');
  }

  String _relativeReferencePath(File file) {
    return 'voice_preferences/${file.uri.pathSegments.last}';
  }

  Future<void> _deleteBestEffort(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // Metadata is authoritative; an orphan can be removed on later cleanup.
    }
  }

  static Map<String, Object?> _emptyDocument() => {
    'schemaVersion': 1,
    'preferences': <String, Object?>{},
  };

  static void _validateCharacterId(String characterId) {
    if (!_characterIdPattern.hasMatch(characterId)) {
      throw const FormatException('Character ID is invalid');
    }
  }

  static String _ascii(List<int> bytes, int start, int end) =>
      String.fromCharCodes(bytes.sublist(start, end));

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }
}
