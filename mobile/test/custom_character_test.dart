import 'dart:io';

import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/protocol/voice_event.dart';
import 'package:child_voice_call/repositories/bundled_character_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final customRecord = <String, Object?>{
  'id': 'custom_20a8d1b51412447a99abc336e306f25f',
  'name': '星星船长',
  'subtitle': '喜欢科学的探险伙伴',
  'avatar': {
    'kind': 'local_file',
    'value': 'avatars/custom_20a8d1b51412447a99abc336e306f25f.jpg',
  },
  'themeColor': '#5B7CFA',
  'profile': {
    'identityId': 'adventure_companion',
    'traitIds': ['brave', 'patient'],
    'interestIds': ['space', 'science'],
    'description': '喜欢用有趣的小实验解释问题',
  },
  'greeting': '你好呀，我是星星船长！',
  'promptProfile': '用有趣的科学实验启发孩子。',
  'defaultVoice': {'mode': 'preset', 'voice': '白桦'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = Directory('${Directory.current.path}/test-app-support');

  test('custom character round trips relative storage and runtime paths', () {
    final character = Character.fromCustomJson(customRecord, root: root);
    final storage = character.toStorageJson(root: root);

    expect((storage['avatar']! as Map)['value'], startsWith('avatars/'));
    final restored = Character.fromCustomJson(storage, root: root);
    expect(restored.source, CharacterSource.custom);
    expect(restored.profile!.traitIds, ['brave', 'patient']);
    expect(restored.defaultVoice.presetVoice, '白桦');
    expect(restored.avatar.kind, AvatarKind.localFile);
    expect(
      restored.avatar.value.replaceAll('\\', '/'),
      startsWith(root.path.replaceAll('\\', '/')),
    );
    expect(restored.displaySubtitle, '喜欢科学的探险伙伴');
    expect(restored.promptProfile, '用有趣的科学实验启发孩子。');
  });

  test('custom session start includes a safe structured snapshot', () {
    final character = Character.fromCustomJson(customRecord, root: root);
    final event = VoiceClientEvent.sessionStart(
      character.id,
      customCharacter: character.customCharacterProtocolJson,
      voiceConfig: character.defaultVoice.toProtocolJson(includePreset: true),
    );

    expect(
      event['customCharacter'],
      containsPair('identityId', 'adventure_companion'),
    );
    expect(event['voiceConfig'], {'mode': 'preset', 'voice': '白桦'});
    expect((event['customCharacter'] as Map).containsKey('avatar'), isFalse);
    expect((event['customCharacter'] as Map).containsKey('subtitle'), isFalse);
    expect(
      event['customCharacter'],
      containsPair('promptProfile', '用有趣的科学实验启发孩子。'),
    );
  });

  test('bundled session remains backward compatible', () {
    expect(VoiceClientEvent.sessionStart('ryder'), {
      'type': 'session.start',
      'characterId': 'ryder',
    });
  });

  test(
    'bundled characters expose complete prompt-relevant configuration',
    () async {
      final characters = await BundledCharacterRepository().load();

      for (final character in characters) {
        expect(character.profile, isNotNull);
        expect(character.profile!.identityId, isNotEmpty);
        expect(character.profile!.traitIds, isNotEmpty);
        expect(character.greeting, isNotEmpty);
        expect(character.promptProfile, isNotEmpty);
      }
    },
  );

  test('rejects local paths outside app support storage', () {
    final record = Map<String, Object?>.from(customRecord);
    record['avatar'] = {'kind': 'local_file', 'value': '../private.jpg'};
    expect(
      () => Character.fromCustomJson(record, root: root),
      throwsA(isA<FormatException>()),
    );
  });

  test('draft validates global field limits and clone authorization', () {
    final draft = CustomCharacterDraft(
      name: '',
      subtitle: 'a' * 31,
      avatar: const CharacterAvatarRef.bundled('star'),
      themeColorValue: 0xff5b7cfa,
      profile: const CustomCharacterProfile(
        identityId: '',
        traitIds: [],
        interestIds: ['space', 'space', 'science', 'art'],
        description: '',
      ),
      greeting: '',
      defaultVoice: const VoiceSelection(
        mode: VoiceMode.voiceClone,
        referencePath: '/tmp/reference.wav',
      ),
    );
    final fields = draft.validate().map((error) => error.field).toSet();
    expect(fields, containsAll(['name', 'subtitle', 'greeting', 'identityId']));
    expect(fields, containsAll(['traitIds', 'interestIds', 'voice']));
  });

  test('stored clone must include explicit authorization', () {
    expect(
      () => VoiceSelection.fromStorageJson({
        'mode': 'voice_clone',
        'referencePath': 'voices/sample.wav',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
