import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/character_options.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/pages/character_editor_page.dart';
import 'package:child_voice_call/widgets/character_avatar_picker.dart';
import 'package:child_voice_call/widgets/voice_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const editorOptions = CharacterOptions(
  optionsVersion: 1,
  identities: [
    CharacterOption(id: 'adventure_companion', label: '探险伙伴'),
    CharacterOption(id: 'story_partner', label: '故事伙伴'),
  ],
  traits: [
    CharacterOption(id: 'brave', label: '勇敢'),
    CharacterOption(id: 'patient', label: '耐心'),
  ],
  interests: [CharacterOption(id: 'space', label: '太空')],
  presetVoices: [
    PresetVoiceOption(id: '白桦', label: '白桦'),
    PresetVoiceOption(id: '苏打', label: '苏打'),
  ],
);

const editorOptionsWithoutVoices = CharacterOptions(
  optionsVersion: 1,
  identities: [CharacterOption(id: 'adventure_companion', label: '探险伙伴')],
  traits: [CharacterOption(id: 'brave', label: '勇敢')],
  interests: [],
  presetVoices: [],
);

const savedCharacter = Character(
  id: 'custom_20a8d1b51412447a99abc336e306f25f',
  name: '星星船长',
  subtitle: '',
  avatar: CharacterAvatarRef.bundled('star'),
  defaultVoiceDescription: '',
  defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
  themeColor: Color(0xfff4b942),
  source: CharacterSource.custom,
  profile: CustomCharacterProfile(
    identityId: 'adventure_companion',
    traitIds: ['brave'],
    interestIds: [],
    description: '',
  ),
  greeting: '你好呀，我是星星船长！很高兴接到你的电话。',
);

class FakeAvatarPicker implements AvatarPicker {
  FakeAvatarPicker(this.path);
  final String? path;
  @override
  Future<String?> pickImagePath() async => path;
}

Widget editorApp({
  Future<Character> Function(CustomCharacterDraft)? onSave,
  AvatarPicker? avatarPicker,
}) => ProviderScope(
  child: MaterialApp(
    home: CharacterEditorPage(
      options: editorOptions,
      onSave: onSave ?? (_) async => savedCharacter,
      avatarPicker: avatarPicker,
    ),
  ),
);

Future<void> fillValidCharacterForm(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('character_name')), '星星船长');
  await tester.ensureVisible(
    find.byKey(const Key('identity_adventure_companion')),
  );
  await tester.tap(find.byKey(const Key('identity_adventure_companion')));
  await tester.tap(find.byKey(const Key('trait_brave')));
  await tester.pump();
}

Future<void> tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('save_character')));
  await tester.tap(find.byKey(const Key('save_character')));
  await tester.pump();
}

void main() {
  testWidgets('edits profile without exposing voice settings', (tester) async {
    await tester.pumpWidget(editorApp());

    expect(find.text('默认音色'), findsNothing);
    expect(find.byType(VoiceSelector), findsNothing);
  });

  testWidgets('shows an options error when no preset voice is available', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: CharacterEditorPage(
            options: editorOptionsWithoutVoices,
            onSave: (_) async => savedCharacter,
          ),
        ),
      ),
    );

    expect(find.text('角色选项加载失败'), findsOneWidget);
    expect(find.textContaining('没有可用的预置音色'), findsOneWidget);
  });

  testWidgets('existing character remains editable without preset options', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: CharacterEditorPage(
            character: savedCharacter,
            options: editorOptionsWithoutVoices,
          ),
        ),
      ),
    );

    expect(find.text('角色选项加载失败'), findsNothing);
    expect(find.byKey(const Key('character_name')), findsOneWidget);
    expect(find.byKey(const Key('save_character')), findsOneWidget);
  });

  testWidgets('requires name identity and trait before save', (tester) async {
    await tester.pumpWidget(editorApp());

    await tapSave(tester);

    expect(find.text('请输入角色名称'), findsOneWidget);
    expect(find.text('请选择角色身份'), findsOneWidget);
    expect(find.text('至少选择一个性格'), findsOneWidget);
  });

  testWidgets('name generates greeting until greeting is edited', (
    tester,
  ) async {
    await tester.pumpWidget(editorApp());

    await tester.enterText(find.byKey(const Key('character_name')), '星星船长');
    await tester.pump();
    var greeting = tester.widget<TextFormField>(
      find.byKey(const Key('character_greeting')),
    );
    expect(greeting.controller!.text, '你好呀，我是星星船长！很高兴接到你的电话。');

    await tester.enterText(
      find.byKey(const Key('character_greeting')),
      '自定义开场白',
    );
    await tester.enterText(find.byKey(const Key('character_name')), '新名字');
    await tester.pump();
    greeting = tester.widget<TextFormField>(
      find.byKey(const Key('character_greeting')),
    );
    expect(greeting.controller!.text, '自定义开场白');
  });

  testWidgets('saving valid form calls save once and pops result', (
    tester,
  ) async {
    final drafts = <CustomCharacterDraft>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              key: const Key('open_editor'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CharacterEditorPage(
                    options: editorOptions,
                    onSave: (draft) async {
                      drafts.add(draft);
                      return savedCharacter;
                    },
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_editor')));
    await tester.pumpAndSettle();
    await fillValidCharacterForm(tester);

    await tapSave(tester);
    await tester.pumpAndSettle();

    expect(drafts, hasLength(1));
    expect(drafts.single.defaultVoice.mode, VoiceMode.preset);
    expect(drafts.single.defaultVoice.presetVoice, '白桦');
    expect(find.byType(CharacterEditorPage), findsNothing);
  });

  testWidgets('gallery selection is included in the saved draft', (
    tester,
  ) async {
    final drafts = <CustomCharacterDraft>[];
    await tester.pumpWidget(
      editorApp(
        avatarPicker: FakeAvatarPicker('/gallery/photo.jpg'),
        onSave: (draft) async {
          drafts.add(draft);
          return savedCharacter;
        },
      ),
    );
    await fillValidCharacterForm(tester);
    await tester.ensureVisible(find.byKey(const Key('avatar_gallery')));
    await tester.tap(find.byKey(const Key('avatar_gallery')));
    await tester.pump();

    await tapSave(tester);
    await tester.pump();

    expect(drafts.single.avatar.kind, AvatarKind.localFile);
    expect(drafts.single.avatar.value, '/gallery/photo.jpg');
  });

  testWidgets('editing starts from saved values and returns an updated draft', (
    tester,
  ) async {
    final drafts = <CustomCharacterDraft>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: CharacterEditorPage(
            character: savedCharacter,
            options: editorOptions,
            onSave: (draft) async {
              drafts.add(draft);
              return savedCharacter;
            },
          ),
        ),
      ),
    );
    final name = tester.widget<TextFormField>(
      find.byKey(const Key('character_name')),
    );
    expect(name.controller!.text, '星星船长');

    await tester.enterText(find.byKey(const Key('character_name')), '星际船长');
    await tapSave(tester);

    expect(drafts.single.name, '星际船长');
    expect(drafts.single.greeting, savedCharacter.greeting);
    expect(drafts.single.defaultVoice, savedCharacter.defaultVoice);
  });

  testWidgets('save failure keeps editor open and shows recovery message', (
    tester,
  ) async {
    await tester.pumpWidget(
      editorApp(onSave: (_) async => throw StateError('disk full')),
    );
    await fillValidCharacterForm(tester);

    await tapSave(tester);
    await tester.pump();

    expect(find.byType(CharacterEditorPage), findsOneWidget);
    expect(find.text('角色保存失败，请检查存储空间后重试'), findsOneWidget);
  });
}
