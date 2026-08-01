import 'dart:io';

import 'package:child_voice_call/app.dart';
import 'package:child_voice_call/controllers/character_catalog_controller.dart';
import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/character_options.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/pages/character_editor_page.dart';
import 'package:child_voice_call/repositories/bundled_character_repository.dart';
import 'package:child_voice_call/repositories/character_options_repository.dart';
import 'package:child_voice_call/repositories/custom_character_repository.dart';
import 'package:child_voice_call/services/character_asset_store.dart';
import 'package:child_voice_call/widgets/character_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testOptions = CharacterOptions(
  optionsVersion: 1,
  identities: [CharacterOption(id: 'adventure_companion', label: '探险伙伴')],
  traits: [CharacterOption(id: 'brave', label: '勇敢')],
  interests: [CharacterOption(id: 'space', label: '太空')],
  presetVoices: [PresetVoiceOption(id: '白桦', label: '白桦')],
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

const bundledCharacters = [
  Character(
    id: 'labrador_captain',
    name: '拉布拉多队长',
    subtitle: '安全救援伙伴',
    avatar: CharacterAvatarRef.bundled('paw'),
    defaultVoiceDescription: '',
    defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
    themeColor: Color(0xfff97316),
  ),
  Character(
    id: 'ryder',
    name: '莱德',
    subtitle: '救援队长',
    avatar: CharacterAvatarRef.bundled('compass'),
    defaultVoiceDescription: '',
    defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
    themeColor: Color(0xff14b8a6),
  ),
];

class FakeBundledRepository extends BundledCharacterRepository {
  FakeBundledRepository() : super(bundle: rootBundle);

  @override
  Future<List<Character>> load() async => bundledCharacters;
}

class FakeCustomRepository extends CustomCharacterRepository {
  FakeCustomRepository({
    List<Character> characters = const [],
    this.warnings = const {},
  }) : characters = List<Character>.from(characters),
       super(
         root: Directory('/unused'),
         assets: FileCharacterAssetStore(root: Directory('/unused')),
       );

  final List<Character> characters;
  final Set<CharacterLoadWarning> warnings;
  final List<String> deletedIds = [];

  @override
  Future<CharacterLoadResult> loadWithWarnings() async => CharacterLoadResult(
    characters: List<Character>.from(characters),
    warnings: warnings,
  );

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    characters.removeWhere((character) => character.id == id);
  }
}

class OfflineOptionsRepository extends CharacterOptionsRepository {
  OfflineOptionsRepository()
    : super(
        bundle: rootBundle,
        cacheFile: File('/unused/options.json'),
        client: MockClient((_) async => http.Response('', 500)),
        serverUri: Uri.parse('ws://localhost/ws/voice'),
      );

  @override
  Future<CharacterOptions> load() async => testOptions;

  @override
  Future<CharacterOptions> refresh() async =>
      throw http.ClientException('offline');
}

Future<void> pumpCatalog(
  WidgetTester tester,
  FakeCustomRepository custom,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  final dependencies = CharacterCatalogDependencies(
    bundled: FakeBundledRepository(),
    custom: custom,
    options: OfflineOptionsRepository(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        characterCatalogDependenciesProvider.overrideWith(
          (ref) => dependencies,
        ),
      ],
      child: const VoiceCallApp(),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(VoiceCallApp)),
  );
  await container.read(charactersProvider.future);
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> scrollCatalogUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 12 && finder.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('shows bundled characters', (tester) async {
    await pumpCatalog(tester, FakeCustomRepository());

    expect(find.text('拉布拉多队长'), findsOneWidget);
    expect(find.text('莱德'), findsOneWidget);
  });

  testWidgets('list ends with new character card and opens editor', (
    tester,
  ) async {
    await pumpCatalog(
      tester,
      FakeCustomRepository(characters: const [starCaptain]),
    );
    await scrollCatalogUntilFound(tester, find.text('我的角色'));
    final createCard = find.byKey(const Key('create_character_card'));
    await scrollCatalogUntilFound(tester, createCard);

    await tester.tap(createCard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CharacterEditorPage), findsOneWidget);
  });

  testWidgets('storage warning leaves bundled roles usable', (tester) async {
    await pumpCatalog(
      tester,
      FakeCustomRepository(warnings: const {CharacterLoadWarning.invalidStore}),
    );

    expect(find.text('部分本地角色数据无法读取'), findsOneWidget);
    expect(find.text('莱德'), findsOneWidget);
  });

  testWidgets('custom delete requires confirmation and bundled has no menu', (
    tester,
  ) async {
    final custom = FakeCustomRepository(characters: const [starCaptain]);
    await pumpCatalog(tester, custom);
    expect(find.byKey(const Key('character_menu_ryder')), findsNothing);
    final menu = find.byKey(Key('character_menu_${starCaptain.id}'));
    await scrollCatalogUntilFound(tester, menu);

    await tester.tap(menu);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('删除“星星船长”？'), findsOneWidget);
    await tester.tap(find.text('确认删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(custom.deletedIds, [starCaptain.id]);
  });

  testWidgets('temporary call voice resets to the saved default', (
    tester,
  ) async {
    VoiceSelection? calledWith;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CharacterCard(
              character: starCaptain,
              options: testOptions,
              onCall: (selection) async => calledWith = selection,
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(Key('voice_mode_voiceDesign_${starCaptain.id}')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(Key('voice_description_${starCaptain.id}')),
      '温暖明亮又有耐心的少年声音',
    );
    await tester.tap(find.byKey(Key('character_${starCaptain.id}')));
    await tester.pump();

    expect(calledWith?.mode, VoiceMode.voiceDesign);
    expect(find.byKey(Key('preset_voice_${starCaptain.id}')), findsOneWidget);
    expect(find.text('白桦'), findsOneWidget);
  });
}
