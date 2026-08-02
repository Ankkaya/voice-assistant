import 'dart:convert';
import 'dart:io';

import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/repositories/character_voice_preferences_repository.dart';
import 'package:child_voice_call/services/character_asset_store.dart';
import 'package:flutter_test/flutter_test.dart';

final class ThrowingVoicePreferencesWriter implements VoicePreferencesWriter {
  @override
  Future<void> write(File destination, Map<String, Object?> document) async {
    throw const FileSystemException('injected write failure');
  }
}

void main() {
  late Directory temporaryDirectory;
  late Directory root;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'voice-preferences-repository-test-',
    );
    root = Directory('${temporaryDirectory.path}/support');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  CharacterVoicePreferencesRepository repository({
    VoicePreferencesWriter? writer,
  }) => CharacterVoicePreferencesRepository(
    root: root,
    writer: writer ?? const FileVoicePreferencesWriter(),
  );

  Future<File> wavSource(String name) async {
    final source = File('${temporaryDirectory.path}/$name.wav');
    await source.writeAsBytes([
      ...'RIFF'.codeUnits,
      4,
      0,
      0,
      0,
      ...'WAVE'.codeUnits,
      ...'authorized voice'.codeUnits,
    ]);
    return source;
  }

  Future<Map<String, dynamic>> storedDocument() async =>
      jsonDecode(
            await File(
              '${root.path}/character_voice_preferences.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;

  test('preset preferences round trip by character id', () async {
    final target = repository();

    await target.save(
      'ryder',
      const VoiceSelection(mode: VoiceMode.preset, presetVoice: '苏打'),
    );
    final loaded = await target.load();

    expect(loaded.preferences['ryder']?.presetVoice, '苏打');
    expect(loaded.warnings, isEmpty);
    expect(loaded.invalidCharacterIds, isEmpty);
    expect(await storedDocument(), {
      'schemaVersion': 1,
      'preferences': {
        'ryder': {'mode': 'preset', 'voice': '苏打'},
      },
    });
  });

  test('voice design preferences round trip and trim description', () async {
    final target = repository();

    final saved = await target.save(
      'star_captain',
      const VoiceSelection(
        mode: VoiceMode.voiceDesign,
        voiceDescription: '  温暖明亮的少年队长声音  ',
      ),
    );
    final loaded = await target.load();

    expect(saved.voiceDescription, '温暖明亮的少年队长声音');
    expect(loaded.preferences['star_captain']?.voiceDescription, '温暖明亮的少年队长声音');
  });

  test('clone is imported privately and restored as absolute path', () async {
    final source = await wavSource('reference');
    final target = repository();

    final saved = await target.save(
      'ryder',
      VoiceSelection(
        mode: VoiceMode.voiceClone,
        referencePath: source.path,
        referenceName: '我的声音.wav',
        cloneAuthorized: true,
      ),
    );
    final loaded = await target.load();
    final stored = await storedDocument();
    final record = (stored['preferences'] as Map)['ryder'] as Map;

    expect(saved.referencePath, startsWith('${root.path}/voice_preferences/'));
    expect(File(saved.referencePath!).isAbsolute, isTrue);
    expect(await File(saved.referencePath!).exists(), isTrue);
    expect(record['referencePath'], startsWith('voice_preferences/'));
    expect((record['referencePath'] as String).startsWith('/'), isFalse);
    expect(loaded.preferences['ryder']?.referencePath, saved.referencePath);
    expect(loaded.preferences['ryder']?.referenceName, '我的声音.wav');
    expect(loaded.preferences['ryder']?.cloneAuthorized, isTrue);
  });

  test('replacing a clone commits new file then removes old file', () async {
    final firstSource = await wavSource('first');
    final secondSource = await wavSource('second');
    final target = repository();
    final first = await target.save(
      'ryder',
      VoiceSelection(
        mode: VoiceMode.voiceClone,
        referencePath: firstSource.path,
        cloneAuthorized: true,
      ),
    );

    final second = await target.save(
      'ryder',
      VoiceSelection(
        mode: VoiceMode.voiceClone,
        referencePath: secondSource.path,
        cloneAuthorized: true,
      ),
    );

    expect(second.referencePath, isNot(first.referencePath));
    expect(await File(first.referencePath!).exists(), isFalse);
    expect(await File(second.referencePath!).exists(), isTrue);
  });

  test('deleting a preference also deletes its clone file', () async {
    final source = await wavSource('delete-me');
    final target = repository();
    final saved = await target.save(
      'ryder',
      VoiceSelection(
        mode: VoiceMode.voiceClone,
        referencePath: source.path,
        cloneAuthorized: true,
      ),
    );

    await target.delete('ryder');

    expect((await target.load()).preferences, isEmpty);
    expect(await File(saved.referencePath!).exists(), isFalse);
  });

  test('pruning removes unknown records and their clone files', () async {
    final source = await wavSource('unknown');
    final target = repository();
    final removed = await target.save(
      'unknown_character',
      VoiceSelection(
        mode: VoiceMode.voiceClone,
        referencePath: source.path,
        cloneAuthorized: true,
      ),
    );
    await target.save(
      'ryder',
      const VoiceSelection(mode: VoiceMode.preset, presetVoice: '苏打'),
    );

    await target.prune({'ryder'});

    expect((await target.load()).preferences.keys, ['ryder']);
    expect(await File(removed.referencePath!).exists(), isFalse);
  });

  test('concurrent saves preserve preferences for both characters', () async {
    final target = repository();

    await Future.wait([
      target.save(
        'ryder',
        const VoiceSelection(mode: VoiceMode.preset, presetVoice: '苏打'),
      ),
      target.save(
        'labrador_captain',
        const VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
      ),
    ]);

    final loaded = await target.load();
    expect(loaded.preferences.keys, containsAll(['ryder', 'labrador_captain']));
  });

  test('missing clone is skipped and reported for its character', () async {
    await root.create(recursive: true);
    await File('${root.path}/character_voice_preferences.json').writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'preferences': {
          'ryder': {
            'mode': 'voice_clone',
            'referencePath': 'voice_preferences/missing.wav',
            'cloneAuthorized': true,
          },
        },
      }),
    );

    final loaded = await repository().load();

    expect(loaded.preferences, isEmpty);
    expect(loaded.warnings, contains(VoicePreferenceWarning.missingReference));
    expect(loaded.invalidCharacterIds, {'ryder'});
  });

  test('malformed records are isolated from valid preferences', () async {
    await root.create(recursive: true);
    await File('${root.path}/character_voice_preferences.json').writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'preferences': {
          'ryder': {'mode': 'preset', 'voice': '苏打'},
          'broken': {'mode': 'preset'},
          '../outside': {'mode': 'preset', 'voice': '白桦'},
        },
      }),
    );

    final loaded = await repository().load();

    expect(loaded.preferences.keys, ['ryder']);
    expect(loaded.warnings, contains(VoicePreferenceWarning.invalidRecord));
    expect(loaded.invalidCharacterIds, {'broken', '../outside'});
  });

  test('malformed store returns an invalid-store warning', () async {
    await root.create(recursive: true);
    final store = File('${root.path}/character_voice_preferences.json');
    await store.writeAsString('{broken');

    final loaded = await repository().load();

    expect(loaded.preferences, isEmpty);
    expect(loaded.warnings, {VoicePreferenceWarning.invalidStore});
    expect(await store.readAsString(), '{broken');
  });

  test('writer failure preserves old document and clone', () async {
    final firstSource = await wavSource('existing');
    final originalRepository = repository();
    final original = await originalRepository.save(
      'ryder',
      VoiceSelection(
        mode: VoiceMode.voiceClone,
        referencePath: firstSource.path,
        cloneAuthorized: true,
      ),
    );
    final originalDocument = await originalRepository.storeFile.readAsString();
    final replacementSource = await wavSource('replacement');
    final failing = repository(writer: ThrowingVoicePreferencesWriter());

    await expectLater(
      failing.save(
        'ryder',
        VoiceSelection(
          mode: VoiceMode.voiceClone,
          referencePath: replacementSource.path,
          cloneAuthorized: true,
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );

    expect(await originalRepository.storeFile.readAsString(), originalDocument);
    expect(await File(original.referencePath!).exists(), isTrue);
    final privateFiles = await originalRepository.referencesDirectory
        .list()
        .where((entity) => entity is File)
        .toList();
    expect(privateFiles.map((file) => file.path), [original.referencePath]);
  });

  group('clone validation', () {
    test('rejects unsupported extensions', () async {
      final source = File('${temporaryDirectory.path}/voice.m4a');
      await source.writeAsBytes('not audio'.codeUnits);

      await expectLater(
        repository().save(
          'ryder',
          VoiceSelection(
            mode: VoiceMode.voiceClone,
            referencePath: source.path,
            cloneAuthorized: true,
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects invalid WAV or MP3 contents', () async {
      final source = File('${temporaryDirectory.path}/voice.mp3');
      await source.writeAsBytes('not an mp3'.codeUnits);

      await expectLater(
        repository().save(
          'ryder',
          VoiceSelection(
            mode: VoiceMode.voiceClone,
            referencePath: source.path,
            cloneAuthorized: true,
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects files larger than 10 MB', () async {
      final source = File('${temporaryDirectory.path}/oversized.wav');
      final handle = await source.open(mode: FileMode.write);
      await handle.truncate(maxVoiceReferenceBytes + 1);
      await handle.close();

      await expectLater(
        repository().save(
          'ryder',
          VoiceSelection(
            mode: VoiceMode.voiceClone,
            referencePath: source.path,
            cloneAuthorized: true,
          ),
        ),
        throwsA(isA<RangeError>()),
      );
    });
  });
}
