import 'dart:async';
import 'dart:io';

import 'package:child_voice_call/controllers/character_catalog_controller.dart';
import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/character_options.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/repositories/bundled_character_repository.dart';
import 'package:child_voice_call/repositories/character_options_repository.dart';
import 'package:child_voice_call/repositories/character_voice_preferences_repository.dart';
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
  final List<String> deletedIds = [];

  @override
  Future<CharacterLoadResult> loadWithWarnings() async => CharacterLoadResult(
    characters: List<Character>.from(characters),
    warnings: const {},
  );

  @override
  Future<void> delete(String id) async => deletedIds.add(id);
}

class FakeVoicePreferencesRepository
    extends CharacterVoicePreferencesRepository {
  FakeVoicePreferencesRepository({
    Map<String, VoiceSelection> preferences = const {},
    Set<VoicePreferenceWarning> warnings = const {},
    Set<String> invalidCharacterIds = const {},
  }) : _preferences = Map<String, VoiceSelection>.from(preferences),
       _warnings = Set<VoicePreferenceWarning>.from(warnings),
       _invalidCharacterIds = Set<String>.from(invalidCharacterIds),
       super(root: Directory('/unused'));

  final Map<String, VoiceSelection> _preferences;
  final Set<VoicePreferenceWarning> _warnings;
  final Set<String> _invalidCharacterIds;
  final List<String> deletedIds = [];
  final List<Set<String>> prunedIds = [];
  bool failSave = false;
  Completer<void>? saveGate;

  @override
  Future<VoicePreferencesLoadResult> load() async => VoicePreferencesLoadResult(
    preferences: Map<String, VoiceSelection>.from(_preferences),
    warnings: Set<VoicePreferenceWarning>.from(_warnings),
    invalidCharacterIds: Set<String>.from(_invalidCharacterIds),
  );

  @override
  Future<VoiceSelection> save(
    String characterId,
    VoiceSelection selection,
  ) async {
    if (failSave) throw const FileSystemException('injected save failure');
    await saveGate?.future;
    _preferences[characterId] = selection;
    return selection;
  }

  @override
  Future<void> delete(String characterId) async {
    deletedIds.add(characterId);
    _preferences.remove(characterId);
  }

  @override
  Future<void> prune(Set<String> validCharacterIds) async {
    prunedIds.add(Set<String>.from(validCharacterIds));
    _preferences.removeWhere((id, _) => !validCharacterIds.contains(id));
  }
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
  FakeVoicePreferencesRepository? voiceRepository,
}) {
  final dependencies = CharacterCatalogDependencies(
    bundled: FakeBundledRepository(bundled),
    custom: FakeCustomRepository(custom),
    options: optionsRepository,
    voices: voiceRepository ?? FakeVoicePreferencesRepository(),
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

  test(
    'voiceFor returns a saved preference and otherwise the default',
    () async {
      final voiceRepository = FakeVoicePreferencesRepository(
        preferences: const {
          'ryder': VoiceSelection(
            mode: VoiceMode.voiceDesign,
            voiceDescription: '温暖明亮的少年队长声音',
          ),
        },
      );
      final container = makeContainer(
        bundled: const [ryder],
        custom: const [starCaptain],
        optionsRepository: FakeOptionsRepository(options(1)),
        voiceRepository: voiceRepository,
      );
      addTearDown(container.dispose);

      final state = await container.read(charactersProvider.future);

      expect(state.voiceFor(ryder).voiceDescription, '温暖明亮的少年队长声音');
      expect(state.voiceFor(starCaptain).presetVoice, '白桦');
    },
  );

  test('saveVoice persists before publishing updated state', () async {
    final voiceRepository = FakeVoicePreferencesRepository();
    final container = makeContainer(
      bundled: const [ryder],
      custom: const [],
      optionsRepository: FakeOptionsRepository(options(1)),
      voiceRepository: voiceRepository,
    );
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);

    await container
        .read(charactersProvider.notifier)
        .saveVoice(
          'ryder',
          const VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
        );

    expect(
      container
          .read(charactersProvider)
          .requireValue
          .voiceFor(ryder)
          .presetVoice,
      '白桦',
    );
  });

  test('failed voice save leaves the effective voice unchanged', () async {
    final voiceRepository = FakeVoicePreferencesRepository()..failSave = true;
    final container = makeContainer(
      bundled: const [ryder],
      custom: const [],
      optionsRepository: FakeOptionsRepository(options(1)),
      voiceRepository: voiceRepository,
    );
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);

    await expectLater(
      container
          .read(charactersProvider.notifier)
          .saveVoice(
            'ryder',
            const VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
          ),
      throwsA(isA<FileSystemException>()),
    );

    expect(
      container
          .read(charactersProvider)
          .requireValue
          .voiceFor(ryder)
          .presetVoice,
      '苏打',
    );
  });

  test('deleting a custom character removes its voice preference', () async {
    final voiceRepository = FakeVoicePreferencesRepository(
      preferences: {starCaptain.id: starCaptain.defaultVoice},
    );
    final customRepository = FakeCustomRepository(const [starCaptain]);
    final dependencies = CharacterCatalogDependencies(
      bundled: FakeBundledRepository(const [ryder]),
      custom: customRepository,
      options: FakeOptionsRepository(options(1)),
      voices: voiceRepository,
    );
    final container = ProviderContainer(
      overrides: [
        characterCatalogDependenciesProvider.overrideWith(
          (ref) => dependencies,
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(charactersProvider.future);

    await container.read(charactersProvider.notifier).delete(starCaptain.id);

    expect(customRepository.deletedIds, [starCaptain.id]);
    expect(voiceRepository.deletedIds, [starCaptain.id]);
    expect(
      container.read(charactersProvider).requireValue.characters,
      isNot(contains(starCaptain)),
    );
    expect(
      container.read(charactersProvider).requireValue.voicePreferences,
      isNot(contains(starCaptain.id)),
    );
  });

  test(
    'a delayed save cannot restore a deleted character preference',
    () async {
      final gate = Completer<void>();
      final voiceRepository = FakeVoicePreferencesRepository()..saveGate = gate;
      final customRepository = FakeCustomRepository(const [starCaptain]);
      final dependencies = CharacterCatalogDependencies(
        bundled: FakeBundledRepository(const [ryder]),
        custom: customRepository,
        options: FakeOptionsRepository(options(1)),
        voices: voiceRepository,
      );
      final container = ProviderContainer(
        overrides: [
          characterCatalogDependenciesProvider.overrideWith(
            (ref) => dependencies,
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(charactersProvider.future);

      final save = container
          .read(charactersProvider.notifier)
          .saveVoice(
            starCaptain.id,
            const VoiceSelection(mode: VoiceMode.preset, presetVoice: '苏打'),
          );
      await Future<void>.delayed(Duration.zero);
      await container.read(charactersProvider.notifier).delete(starCaptain.id);
      gate.complete();

      await expectLater(save, throwsA(isA<StateError>()));
      final state = container.read(charactersProvider).requireValue;
      expect(state.characters.map((item) => item.id), ['ryder']);
      expect(state.voicePreferences, isNot(contains(starCaptain.id)));
      expect(voiceRepository.deletedIds, [starCaptain.id, starCaptain.id]);
    },
  );

  test('saving a repaired preference clears its resolved warning', () async {
    final voiceRepository = FakeVoicePreferencesRepository(
      warnings: const {VoicePreferenceWarning.missingReference},
      invalidCharacterIds: const {'ryder'},
    );
    final container = makeContainer(
      bundled: const [ryder],
      custom: const [],
      optionsRepository: FakeOptionsRepository(options(1)),
      voiceRepository: voiceRepository,
    );
    addTearDown(container.dispose);
    final initial = await container.read(charactersProvider.future);
    expect(initial.voiceWarnings, {VoicePreferenceWarning.missingReference});

    await container
        .read(charactersProvider.notifier)
        .saveVoice(
          'ryder',
          const VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
        );

    final repaired = container.read(charactersProvider).requireValue;
    expect(repaired.invalidVoiceCharacterIds, isEmpty);
    expect(repaired.voiceWarnings, isEmpty);
  });

  test('build filters and prunes preferences for unknown characters', () async {
    final voiceRepository = FakeVoicePreferencesRepository(
      preferences: const {
        'retired': VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
      },
    );
    final container = makeContainer(
      bundled: const [ryder],
      custom: const [],
      optionsRepository: FakeOptionsRepository(options(1)),
      voiceRepository: voiceRepository,
    );
    addTearDown(container.dispose);

    final state = await container.read(charactersProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(state.voicePreferences, isEmpty);
    expect(voiceRepository.prunedIds, [
      <String>{'ryder'},
    ]);
  });
}
