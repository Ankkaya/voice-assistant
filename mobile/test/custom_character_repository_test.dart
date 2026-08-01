import 'dart:convert';
import 'dart:io';

import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/repositories/custom_character_repository.dart';
import 'package:child_voice_call/services/character_asset_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class FailingStoreWriter implements AtomicStoreWriter {
  final delegate = const FileAtomicStoreWriter();
  bool failNextWrite = false;

  @override
  Future<void> write(File destination, Map<String, Object?> document) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw FileSystemException('injected metadata failure', destination.path);
    }
    await delegate.write(destination, document);
  }
}

CustomCharacterDraft validDraft({String name = '星星船长'}) => CustomCharacterDraft(
  name: name,
  subtitle: '喜欢科学的探险伙伴',
  avatar: const CharacterAvatarRef.bundled('star'),
  themeColorValue: 0xff5b7cfa,
  profile: const CustomCharacterProfile(
    identityId: 'adventure_companion',
    traitIds: ['brave', 'patient'],
    interestIds: ['space', 'science'],
    description: '喜欢用有趣的小实验解释问题',
  ),
  greeting: '你好呀，我是星星船长！',
  defaultVoice: const VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
);

void main() {
  late Directory temporaryDirectory;
  late Directory root;
  late FileCharacterAssetStore assets;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'custom-character-repository-test-',
    );
    root = Directory('${temporaryDirectory.path}/support');
    assets = FileCharacterAssetStore(root: root);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  CustomCharacterRepository repository({AtomicStoreWriter? writer}) =>
      CustomCharacterRepository(root: root, assets: assets, writer: writer);

  test('create persists a custom character across repositories', () async {
    final created = await repository().create(validDraft());

    final reopened = CustomCharacterRepository(root: root, assets: assets);
    final loaded = (await reopened.load()).single;

    expect(loaded.id, created.id);
    expect(created.id, matches(RegExp(r'^custom_[a-f0-9]{32}$')));
    expect(loaded.defaultVoice.presetVoice, '白桦');
  });

  test(
    'failed metadata replace keeps old record and deletes new files',
    () async {
      final writer = FailingStoreWriter();
      final target = repository(writer: writer);
      final original = await target.create(validDraft());
      final source = File('${temporaryDirectory.path}/new-avatar.jpg');
      await source.writeAsBytes(
        img.encodeJpg(img.Image(width: 32, height: 24)),
      );
      writer.failNextWrite = true;
      final edited = CustomCharacterDraft(
        name: '修改后的名字',
        subtitle: validDraft().subtitle,
        avatar: CharacterAvatarRef.localFile(source.path),
        themeColorValue: validDraft().themeColorValue,
        profile: validDraft().profile,
        greeting: validDraft().greeting,
        defaultVoice: validDraft().defaultVoice,
      );

      await expectLater(
        target.update(original.id, edited),
        throwsA(isA<FileSystemException>()),
      );

      expect((await repository().load()).single.name, original.name);
      final avatarDirectory = Directory('${root.path}/avatars');
      final remaining = await avatarDirectory.exists()
          ? await avatarDirectory
                .list()
                .where((entity) => entity is File)
                .toList()
          : <FileSystemEntity>[];
      expect(remaining, isEmpty);
    },
  );

  test('one invalid record is skipped without hiding valid records', () async {
    await repository().create(validDraft());
    final store = File('${root.path}/custom_characters.json');
    final document =
        jsonDecode(await store.readAsString()) as Map<String, dynamic>;
    (document['characters'] as List).add({'id': 'invalid'});
    await store.writeAsString(jsonEncode(document));

    final result = await repository().loadWithWarnings();

    expect(result.characters, hasLength(1));
    expect(result.warnings, contains(CharacterLoadWarning.invalidRecord));
  });

  test('whole-file corruption is preserved during load', () async {
    await root.create(recursive: true);
    final store = File('${root.path}/custom_characters.json');
    await store.writeAsString('{broken');

    final result = await repository().loadWithWarnings();

    expect(result.characters, isEmpty);
    expect(result.warnings, {CharacterLoadWarning.invalidStore});
    expect(await store.readAsString(), '{broken');
  });

  test('create backs up a corrupt store before starting version one', () async {
    await root.create(recursive: true);
    final store = File('${root.path}/custom_characters.json');
    await store.writeAsString('{broken');

    final created = await repository().create(validDraft());

    expect((await repository().load()).single.id, created.id);
    final backups = await root
        .list()
        .where(
          (entity) => entity.path.contains('custom_characters.json.corrupt.'),
        )
        .toList();
    expect(backups, hasLength(1));
    expect(await File(backups.single.path).readAsString(), '{broken');
  });

  test('failed recovery write restores the corrupt source file', () async {
    await root.create(recursive: true);
    final store = File('${root.path}/custom_characters.json');
    await store.writeAsString('{broken');
    final writer = FailingStoreWriter()..failNextWrite = true;

    await expectLater(
      repository(writer: writer).create(validDraft()),
      throwsA(isA<FileSystemException>()),
    );

    expect(await store.readAsString(), '{broken');
  });

  test('voice clone paths are private and relative in metadata', () async {
    final source = File('${temporaryDirectory.path}/voice.wav');
    await source.writeAsBytes([
      ...'RIFF'.codeUnits,
      4,
      0,
      0,
      0,
      ...'WAVE'.codeUnits,
      ...'authorized'.codeUnits,
    ]);
    final base = validDraft();
    final draft = CustomCharacterDraft(
      name: base.name,
      subtitle: base.subtitle,
      avatar: base.avatar,
      themeColorValue: base.themeColorValue,
      profile: base.profile,
      greeting: base.greeting,
      defaultVoice: VoiceSelection(
        mode: VoiceMode.voiceClone,
        referencePath: source.path,
        referenceName: 'voice.wav',
        cloneAuthorized: true,
      ),
    );

    final created = await repository().create(draft);
    final document =
        jsonDecode(
              await File('${root.path}/custom_characters.json').readAsString(),
            )
            as Map<String, dynamic>;
    final record = (document['characters'] as List).single as Map;
    final storedVoice = record['defaultVoice'] as Map;

    expect(storedVoice['referencePath'], startsWith('voices/'));
    expect((storedVoice['referencePath'] as String).startsWith('/'), isFalse);
    expect(created.defaultVoice.referencePath, startsWith(root.path));
    expect(created.defaultVoice.cloneAuthorized, isTrue);
  });

  test('delete commits metadata before removing private assets', () async {
    final source = File('${temporaryDirectory.path}/avatar.jpg');
    await source.writeAsBytes(img.encodeJpg(img.Image(width: 24, height: 24)));
    final base = validDraft();
    final draft = CustomCharacterDraft(
      name: base.name,
      subtitle: base.subtitle,
      avatar: CharacterAvatarRef.localFile(source.path),
      themeColorValue: base.themeColorValue,
      profile: base.profile,
      greeting: base.greeting,
      defaultVoice: base.defaultVoice,
    );
    final target = repository();
    final created = await target.create(draft);
    final avatar = File(created.avatar.value);
    expect(await avatar.exists(), isTrue);

    await target.delete(created.id);

    expect(await avatar.exists(), isFalse);
    expect(await target.load(), isEmpty);
  });
}
