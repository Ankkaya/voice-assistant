import 'dart:io';

import 'package:child_voice_call/controllers/character_catalog_controller.dart';
import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/character_options.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/repositories/bundled_character_repository.dart';
import 'package:child_voice_call/repositories/character_options_repository.dart';
import 'package:child_voice_call/repositories/custom_character_repository.dart';
import 'package:child_voice_call/services/character_asset_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const ryder = Character(
  id: 'ryder',
  name: '莱德',
  subtitle: '救援队长',
  avatar: CharacterAvatarRef.asset('assets/characters/ryder.png'),
  defaultVoiceDescription: '明亮友好的少年声音',
  defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '苏打'),
  themeColor: Color(0xffe64b4b),
);

const starCaptain = Character(
  id: 'custom_20a8d1b51412447a99abc336e306f25f',
  name: '星星船长',
  subtitle: '',
  avatar: CharacterAvatarRef.bundled('star'),
  defaultVoiceDescription: '',
  defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
  themeColor: Color(0xff5b7cfa),
  source: CharacterSource.custom,
  profile: CustomCharacterProfile(
    identityId: 'adventure_companion',
    traitIds: ['brave'],
    interestIds: ['space'],
    description: '',
  ),
  greeting: '你好呀，我是星星船长！',
);

CharacterOptions options(int version) => CharacterOptions(
  optionsVersion: version,
  identities: const [CharacterOption(id: 'adventure_companion', label: '探险伙伴')],
  traits: const [CharacterOption(id: 'brave', label: '勇敢')],
  interests: const [CharacterOption(id: 'space', label: '太空')],
  presetVoices: const [PresetVoiceOption(id: '白桦', label: '白桦')],
);

final validDraft = CustomCharacterDraft(
  name: '星星船长',
  subtitle: '',
  avatar: const CharacterAvatarRef.bundled('star'),
  themeColorValue: 0xff5b7cfa,
  profile: const CustomCharacterProfile(
    identityId: 'adventure_companion',
    traitIds: ['brave'],
    interestIds: ['space'],
    description: '',
  ),
  greeting: '你好呀，我是星星船长！',
  defaultVoice: const VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
);

class FakeBundledRepository extends BundledCharacterRepository {
  FakeBundledRepository(this.characters);
  final List<Character> characters;

  @override
  Future<List<Character>> load() async => characters;
}

class FakeAssetStore implements CharacterAssetStore {
  @override
  Future<void> deleteRelative(String? path) async {}
  @override
  Future<String> importAvatar(String sourcePath, String characterId) async =>
      'avatars/$characterId.jpg';
  @override
  Future<String> importVoiceReference(
    String sourcePath,
    String characterId,
  ) async => 'voices/$characterId.wav';
  @override
  Future<void> purgeOrphans(Set<String> referencedPaths) async {}
}

class FakeCustomRepository extends CustomCharacterRepository {
  FakeCustomRepository(this.characters)
    : super(root: Directory('/unused'), assets: FakeAssetStore());

  final List<Character> characters;

  @override
  Future<CharacterLoadResult> loadWithWarnings() async => CharacterLoadResult(
    characters: List<Character>.from(characters),
    warnings: const {},
  );
}

class FakeOptionsRepository extends CharacterOptionsRepository {
  FakeOptionsRepository(this.current)
    : super(
        bundle: rootBundle,
        cacheFile: File('/unused/options.json'),
        client: MockClient((_) async => http.Response('', 500)),
        serverUri: Uri.parse('ws://localhost/ws/voice'),
      );

  CharacterOptions current;
  bool failRefresh = false;

  @override
  Future<CharacterOptions> load() async => current;

  @override
  Future<CharacterOptions> refresh() async {
    if (failRefresh) throw http.ClientException('injected failure');
    return current;
  }
}

ProviderContainer makeContainer({
  required List<Character> bundled,
  required List<Character> custom,
  required FakeOptionsRepository optionsRepository,
}) {
  final dependencies = CharacterCatalogDependencies(
    bundled: FakeBundledRepository(bundled),
    custom: FakeCustomRepository(custom),
    options: optionsRepository,
  );
  return ProviderContainer(
    overrides: [
      characterCatalogDependenciesProvider.overrideWith((ref) => dependencies),
    ],
  );
}

void main() {
  test('catalog merges bundled first and custom second', () async {
    final container = makeContainer(
      bundled: const [ryder],
      custom: const [starCaptain],
      optionsRepository: FakeOptionsRepository(options(1)),
    );
    addTearDown(container.dispose);

    final state = await container.read(charactersProvider.future);

    expect(state.characters.map((item) => item.id), ['ryder', starCaptain.id]);
  });

  test('controller refuses to edit or delete bundled characters', () async {
    final container = makeContainer(
      bundled: const [ryder],
      custom: const [starCaptain],
      optionsRepository: FakeOptionsRepository(options(1)),
    );
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);
    final controller = container.read(charactersProvider.notifier);

    await expectLater(controller.delete('ryder'), throwsA(isA<StateError>()));
    await expectLater(
      controller.updateCharacter('ryder', validDraft),
      throwsA(isA<StateError>()),
    );
  });

  test('failed option refresh retains current options', () async {
    final optionsRepository = FakeOptionsRepository(options(1));
    final container = makeContainer(
      bundled: const [ryder],
      custom: const [],
      optionsRepository: optionsRepository,
    );
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);
    optionsRepository.failRefresh = true;

    await container.read(charactersProvider.notifier).refreshOptions();

    expect(
      container.read(charactersProvider).requireValue.options.optionsVersion,
      1,
    );
  });
}
