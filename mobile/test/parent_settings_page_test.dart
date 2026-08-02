import 'dart:io';

import 'package:child_voice_call/controllers/character_catalog_controller.dart';
import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/character_options.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/pages/character_editor_page.dart';
import 'package:child_voice_call/pages/parent_settings_page.dart';
import 'package:child_voice_call/repositories/bundled_character_repository.dart';
import 'package:child_voice_call/repositories/character_options_repository.dart';
import 'package:child_voice_call/repositories/character_voice_preferences_repository.dart';
import 'package:child_voice_call/repositories/custom_character_repository.dart';
import 'package:child_voice_call/services/character_asset_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const settingsOptions = CharacterOptions(
  optionsVersion: 1,
  identities: [CharacterOption(id: 'adventure_companion', label: '探险伙伴')],
  traits: [CharacterOption(id: 'brave', label: '勇敢')],
  interests: [CharacterOption(id: 'space', label: '太空')],
  presetVoices: [
    PresetVoiceOption(id: '白桦', label: '白桦'),
    PresetVoiceOption(id: '苏打', label: '苏打'),
  ],
);

const settingsRyder = Character(
  id: 'ryder',
  name: '莱德',
  subtitle: '乐于助人的救援队长',
  avatar: CharacterAvatarRef.bundled('compass'),
  defaultVoiceDescription: '',
  defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '苏打'),
  themeColor: Color(0xffe64b4b),
);

const settingsCustom = Character(
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

class SettingsBundledRepository extends BundledCharacterRepository {
  SettingsBundledRepository() : super(bundle: rootBundle);

  @override
  Future<List<Character>> load() async => const [settingsRyder];
}

class SettingsAssetStore implements CharacterAssetStore {
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

class SettingsCustomRepository extends CustomCharacterRepository {
  SettingsCustomRepository({this.warnings = const {}})
    : super(root: Directory('/unused'), assets: SettingsAssetStore());

  final Set<CharacterLoadWarning> warnings;
  final List<String> deletedIds = [];

  @override
  Future<CharacterLoadResult> loadWithWarnings() async => CharacterLoadResult(
    characters: const [settingsCustom],
    warnings: warnings,
  );

  @override
  Future<void> delete(String id) async => deletedIds.add(id);
}

class SettingsOptionsRepository extends CharacterOptionsRepository {
  SettingsOptionsRepository()
    : super(
        bundle: rootBundle,
        cacheFile: File('/unused/options.json'),
        client: MockClient((_) async => http.Response('', 500)),
        serverUri: Uri.parse('ws://localhost/ws/voice'),
      );

  @override
  Future<CharacterOptions> load() async => settingsOptions;

  @override
  Future<CharacterOptions> refresh() async => settingsOptions;
}

class SettingsVoiceRepository extends CharacterVoicePreferencesRepository {
  SettingsVoiceRepository({
    this.preferences = const {},
    this.warnings = const {},
    this.invalidCharacterIds = const {},
    this.failSave = false,
  }) : super(root: Directory('/unused'));

  final Map<String, VoiceSelection> preferences;
  final Set<VoicePreferenceWarning> warnings;
  final Set<String> invalidCharacterIds;
  final bool failSave;
  final List<(String, VoiceSelection)> saved = [];
  final List<String> deletedIds = [];

  @override
  Future<VoicePreferencesLoadResult> load() async => VoicePreferencesLoadResult(
    preferences: preferences,
    warnings: warnings,
    invalidCharacterIds: invalidCharacterIds,
  );

  @override
  Future<VoiceSelection> save(
    String characterId,
    VoiceSelection selection,
  ) async {
    if (failSave) throw const FileSystemException('injected save failure');
    saved.add((characterId, selection));
    if (selection.mode == VoiceMode.voiceClone) {
      return VoiceSelection(
        mode: VoiceMode.voiceClone,
        referencePath: '/private/saved_${saved.length}.wav',
        referenceName: selection.referenceName,
        cloneAuthorized: true,
      );
    }
    return selection;
  }

  @override
  Future<void> delete(String characterId) async {
    deletedIds.add(characterId);
  }

  @override
  Future<void> prune(Set<String> validCharacterIds) async {}
}

class SettingsFixture {
  const SettingsFixture({
    required this.container,
    required this.custom,
    required this.voices,
  });

  final ProviderContainer container;
  final SettingsCustomRepository custom;
  final SettingsVoiceRepository voices;
}

Future<SettingsFixture> pumpSettings(
  WidgetTester tester, {
  String? initialCharacterId,
  Map<String, VoiceSelection> preferences = const {},
  Set<VoicePreferenceWarning> voiceWarnings = const {},
  Set<String> invalidVoiceCharacterIds = const {},
  Set<CharacterLoadWarning> characterWarnings = const {},
  bool failVoiceSave = false,
  double textScale = 1,
}) async {
  final custom = SettingsCustomRepository(warnings: characterWarnings);
  final voices = SettingsVoiceRepository(
    preferences: preferences,
    warnings: voiceWarnings,
    invalidCharacterIds: invalidVoiceCharacterIds,
    failSave: failVoiceSave,
  );
  final dependencies = CharacterCatalogDependencies(
    bundled: SettingsBundledRepository(),
    custom: custom,
    options: SettingsOptionsRepository(),
    voices: voices,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        characterCatalogDependenciesProvider.overrideWith(
          (ref) async => dependencies,
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: ParentSettingsPage(initialCharacterId: initialCharacterId),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ParentSettingsPage)),
  );
  await container.read(charactersProvider.future);
  await tester.pump(const Duration(milliseconds: 1));
  return SettingsFixture(container: container, custom: custom, voices: voices);
}

Future<void> scrollUntilVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pump();
}

void main() {
  testWidgets('lists every character and limits management to custom roles', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text('莱德'), findsWidgets);
    expect(find.text('星星船长'), findsOneWidget);
    expect(find.byKey(const Key('create_character')), findsOneWidget);
    expect(find.byKey(const Key('edit_character')), findsNothing);
    expect(find.byKey(const Key('delete_character')), findsNothing);
    expect(find.byKey(const Key('current_character_avatar')), findsOneWidget);

    await tester.tap(
      find.byKey(Key('settings_character_${settingsCustom.id}')),
    );
    await tester.pump();
    await scrollUntilVisible(tester, find.byKey(const Key('edit_character')));

    expect(find.byKey(const Key('edit_character')), findsOneWidget);
    expect(find.byKey(const Key('delete_character')), findsOneWidget);
  });

  testWidgets('loads the selected effective voice and saves changes', (
    tester,
  ) async {
    final fixture = await pumpSettings(
      tester,
      initialCharacterId: settingsCustom.id,
      preferences: {
        settingsCustom.id: const VoiceSelection(
          mode: VoiceMode.voiceDesign,
          voiceDescription: '温暖明亮又有耐心的少年声音',
        ),
      },
    );

    final description = find.byKey(
      Key('voice_description_settings_${settingsCustom.id}'),
    );
    expect(description, findsOneWidget);
    expect(find.text('温暖明亮又有耐心的少年声音'), findsWidgets);
    await tester.enterText(description, '坚定温暖又活泼自然的队长声音');
    await scrollUntilVisible(
      tester,
      find.byKey(const Key('save_voice_settings')),
    );
    await tester.tap(find.byKey(const Key('save_voice_settings')));
    await tester.pump();

    expect(fixture.voices.saved, hasLength(1));
    expect(fixture.voices.saved.single.$1, settingsCustom.id);
    expect(fixture.voices.saved.single.$2.voiceDescription, '坚定温暖又活泼自然的队长声音');
    expect(find.text('音色设置已保存'), findsOneWidget);
  });

  testWidgets('invalid voice design remains unsaved', (tester) async {
    final fixture = await pumpSettings(tester);
    await tester.tap(
      find.byKey(const Key('voice_mode_voiceDesign_settings_ryder')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('voice_description_settings_ryder')),
      '太短',
    );
    await scrollUntilVisible(
      tester,
      find.byKey(const Key('save_voice_settings')),
    );
    await tester.tap(find.byKey(const Key('save_voice_settings')));
    await tester.pump();

    expect(fixture.voices.saved, isEmpty);
    expect(find.text('请至少用 8 个字描述希望生成的音色'), findsOneWidget);
  });

  testWidgets('unknown initial role falls back and switching rebuilds voice', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      initialCharacterId: 'missing_character',
      preferences: {
        settingsCustom.id: const VoiceSelection(
          mode: VoiceMode.voiceDesign,
          voiceDescription: '温暖清晰又充满耐心的伙伴声音',
        ),
      },
    );

    expect(
      find.byKey(const Key('preset_voice_settings_ryder')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(Key('settings_character_${settingsCustom.id}')),
    );
    await tester.pump();

    expect(
      find.byKey(Key('voice_description_settings_${settingsCustom.id}')),
      findsOneWidget,
    );
    expect(find.text('温暖清晰又充满耐心的伙伴声音'), findsWidgets);
  });

  testWidgets('saved clone can be saved again from its normalized path', (
    tester,
  ) async {
    final fixture = await pumpSettings(
      tester,
      initialCharacterId: settingsCustom.id,
      preferences: {
        settingsCustom.id: const VoiceSelection(
          mode: VoiceMode.voiceClone,
          referencePath: '/private/original.wav',
          referenceName: 'original.wav',
          cloneAuthorized: true,
        ),
      },
    );
    final saveButton = find.byKey(const Key('save_voice_settings'));
    await scrollUntilVisible(tester, saveButton);

    await tester.tap(saveButton);
    await tester.pump();
    await tester.tap(saveButton);
    await tester.pump();

    expect(fixture.voices.saved, hasLength(2));
    expect(
      fixture.voices.saved.first.$2.referencePath,
      '/private/original.wav',
    );
    expect(fixture.voices.saved.last.$2.referencePath, '/private/saved_1.wav');
  });

  testWidgets('failed save keeps the edited value for retry', (tester) async {
    await pumpSettings(
      tester,
      initialCharacterId: settingsCustom.id,
      preferences: {
        settingsCustom.id: const VoiceSelection(
          mode: VoiceMode.voiceDesign,
          voiceDescription: '原来温暖又耐心的角色声音',
        ),
      },
      failVoiceSave: true,
    );
    final description = find.byKey(
      Key('voice_description_settings_${settingsCustom.id}'),
    );
    await tester.enterText(description, '修改后坚定又自然的角色声音');
    await scrollUntilVisible(
      tester,
      find.byKey(const Key('save_voice_settings')),
    );
    await tester.tap(find.byKey(const Key('save_voice_settings')));
    await tester.pump();

    final field = tester.widget<TextField>(description);
    expect(field.controller?.text, '修改后坚定又自然的角色声音');
    expect(find.text('音色设置保存失败，请重试'), findsOneWidget);
  });

  testWidgets('adult surface shows catalog and missing-reference warnings', (
    tester,
  ) async {
    await pumpSettings(
      tester,
      initialCharacterId: settingsCustom.id,
      characterWarnings: const {CharacterLoadWarning.invalidStore},
      voiceWarnings: const {VoicePreferenceWarning.missingReference},
      invalidVoiceCharacterIds: {settingsCustom.id},
    );

    expect(find.text('部分本地角色数据无法读取'), findsOneWidget);
    expect(find.text('参考音频需要重新选择'), findsOneWidget);
  });

  testWidgets('custom role deletion is confirmed and cleans its preference', (
    tester,
  ) async {
    final fixture = await pumpSettings(
      tester,
      initialCharacterId: settingsCustom.id,
    );
    await scrollUntilVisible(tester, find.byKey(const Key('delete_character')));
    await tester.tap(find.byKey(const Key('delete_character')));
    await tester.pumpAndSettle();

    expect(find.text('删除“星星船长”？'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_delete_character')));
    await tester.pumpAndSettle();

    expect(fixture.custom.deletedIds, [settingsCustom.id]);
    expect(fixture.voices.deletedIds, [settingsCustom.id]);
    expect(
      fixture.container
          .read(charactersProvider)
          .requireValue
          .characters
          .map((character) => character.id),
      ['ryder'],
    );
  });

  testWidgets('new and edit actions open the character editor', (tester) async {
    await pumpSettings(tester, initialCharacterId: settingsCustom.id);
    await scrollUntilVisible(tester, find.byKey(const Key('edit_character')));

    await tester.tap(find.byKey(const Key('edit_character')));
    await tester.pumpAndSettle();
    expect(find.byType(CharacterEditorPage), findsOneWidget);
    expect(find.text('编辑角色'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await scrollUntilVisible(tester, find.byKey(const Key('create_character')));
    await tester.tap(find.byKey(const Key('create_character')));
    await tester.pumpAndSettle();

    expect(find.byType(CharacterEditorPage), findsOneWidget);
    expect(find.text('新建角色'), findsOneWidget);
  });

  testWidgets('supports a 360 by 640 screen with 1.3 text scaling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    await pumpSettings(tester, textScale: 1.3);
    await scrollUntilVisible(tester, find.byKey(const Key('create_character')));

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('create_character')), findsOneWidget);
  });
}
