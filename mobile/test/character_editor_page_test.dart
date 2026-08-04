import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/character_options.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/pages/character_editor_page.dart';
import 'package:child_voice_call/services/character_suggestion_service.dart';
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
  promptProfile: '用温暖、有趣的方式陪伴孩子探索太空。',
);

const builtInCharacter = Character(
  id: 'ryder',
  name: '莱德',
  subtitle: '乐于助人的救援队长',
  avatar: CharacterAvatarRef.bundled('compass'),
  defaultVoiceDescription: '',
  defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '苏打'),
  themeColor: Color(0xffe64b4b),
);

class FakeAvatarPicker implements AvatarPicker {
  FakeAvatarPicker(this.path);
  final String? path;
  @override
  Future<String?> pickImagePath() async => path;
}

class FakeCharacterSuggestionService extends CharacterSuggestionService {
  FakeCharacterSuggestionService(this.responses);

  final Map<CharacterSuggestionField, String> responses;
  final List<(CharacterSuggestionField, Map<String, Object>)> requests = [];

  @override
  Future<String> suggest({
    required CharacterSuggestionField field,
    required Map<String, Object> formContext,
  }) async {
    requests.add((field, formContext));
    return responses[field] ?? '可爱的角色建议';
  }

  @override
  void close() {}
}

Widget editorApp({
  Future<Character> Function(CustomCharacterDraft)? onSave,
  AvatarPicker? avatarPicker,
  CharacterSuggestionService? suggestionService,
}) => ProviderScope(
  child: MaterialApp(
    home: CharacterEditorPage(
      options: editorOptions,
      onSave: onSave ?? (_) async => savedCharacter,
      avatarPicker: avatarPicker,
      suggestionService: suggestionService,
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
  testWidgets('new character exposes the same complete configuration form', (
    tester,
  ) async {
    await tester.pumpWidget(editorApp());

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('基本信息')),
      findsOneWidget,
    );
    expect(find.text('基本信息'), findsNWidgets(2));
    expect(find.text('角色设定'), findsOneWidget);
    expect(find.text('其他信息'), findsOneWidget);
    expect(find.text('音色设置'), findsOneWidget);
    expect(find.byKey(const Key('character_greeting')), findsOneWidget);
    expect(find.byKey(const Key('character_prompt_profile')), findsOneWidget);
    expect(find.byType(VoiceSelector), findsOneWidget);
    expect(find.byKey(const Key('suggest_name')), findsOneWidget);
    expect(find.byKey(const Key('suggest_subtitle')), findsOneWidget);
    expect(find.byKey(const Key('suggest_description')), findsOneWidget);
    expect(find.byKey(const Key('suggest_greeting')), findsOneWidget);
    expect(find.byKey(const Key('suggest_promptProfile')), findsOneWidget);
  });

  testWidgets('new character title follows the visible form section', (
    tester,
  ) async {
    await tester.pumpWidget(editorApp());

    for (final section in ['角色设定', '其他信息', '音色设置']) {
      await Scrollable.ensureVisible(
        tester.element(find.text(section)),
        alignment: 0.12,
      );
      await tester.pump();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text(section)),
        findsOneWidget,
      );
    }
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

  testWidgets('preset voice requires at least one available voice option', (
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

    expect(find.text('角色选项加载失败'), findsOneWidget);
    expect(find.textContaining('没有可用的预置音色'), findsOneWidget);
  });

  testWidgets('built-in character only exposes its current voice settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: CharacterEditorPage(
            character: builtInCharacter,
            options: editorOptions,
          ),
        ),
      ),
    );

    expect(find.text('莱德设置'), findsOneWidget);
    expect(find.text('系统角色'), findsOneWidget);
    expect(find.byType(VoiceSelector), findsOneWidget);
    expect(find.byKey(const Key('character_name')), findsNothing);
    expect(find.byKey(const Key('character_greeting')), findsNothing);
    expect(find.byKey(const Key('character_prompt_profile')), findsNothing);
    expect(find.byKey(const Key('identity_adventure_companion')), findsNothing);
    expect(find.text('保存音色设置'), findsOneWidget);
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

  testWidgets('structured role fields generate a useful conversation profile', (
    tester,
  ) async {
    final suggestions = FakeCharacterSuggestionService({
      CharacterSuggestionField.promptProfile: '保持勇敢和耐心，多用太空小实验帮助孩子思考。',
    });
    await tester.pumpWidget(editorApp(suggestionService: suggestions));
    await fillValidCharacterForm(tester);
    await tester.ensureVisible(find.byKey(const Key('interest_space')));
    await tester.tap(find.byKey(const Key('interest_space')));
    await tester.enterText(
      find.byKey(const Key('character_description')),
      '喜欢用小实验解释问题',
    );
    await tester.ensureVisible(find.byKey(const Key('suggest_promptProfile')));
    await tester.tap(find.byKey(const Key('suggest_promptProfile')));
    await tester.pump();

    final prompt = tester.widget<TextFormField>(
      find.byKey(const Key('character_prompt_profile')),
    );
    expect(prompt.controller!.text, '保持勇敢和耐心，多用太空小实验帮助孩子思考。');
    expect(suggestions.requests, hasLength(1));
    final context = suggestions.requests.single.$2;
    expect(context['name'], '星星船长');
    expect(context['identity'], '探险伙伴');
    expect(context['traits'], ['勇敢']);
    expect(context['interests'], ['太空']);
    expect(context['description'], '喜欢用小实验解释问题');
  });

  testWidgets('every new-character text input can use an AI suggestion', (
    tester,
  ) async {
    final suggestions = FakeCharacterSuggestionService({
      CharacterSuggestionField.name: '月亮船长',
      CharacterSuggestionField.subtitle: '爱探索星空的温暖伙伴',
      CharacterSuggestionField.description: '喜欢用有趣的小实验陪孩子认识宇宙。',
      CharacterSuggestionField.greeting: '你好呀，我是月亮船长！今天想探索哪颗星星？',
      CharacterSuggestionField.promptProfile: '语气温暖活泼，回答前先鼓励孩子大胆猜想。',
      CharacterSuggestionField.voiceDescription: '温暖明亮、活泼自然的少年伙伴声音',
    });
    await tester.pumpWidget(editorApp(suggestionService: suggestions));

    Future<void> useSuggestion(String key) async {
      final button = find.byKey(Key(key));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
    }

    await useSuggestion('suggest_name');
    await useSuggestion('suggest_subtitle');
    await useSuggestion('suggest_description');
    await useSuggestion('suggest_greeting');
    await useSuggestion('suggest_promptProfile');

    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('character_name')))
          .controller!
          .text,
      '月亮船长',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('character_subtitle')))
          .controller!
          .text,
      '爱探索星空的温暖伙伴',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('character_description')))
          .controller!
          .text,
      '喜欢用有趣的小实验陪孩子认识宇宙。',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('character_greeting')))
          .controller!
          .text,
      '你好呀，我是月亮船长！今天想探索哪颗星星？',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('character_prompt_profile')),
          )
          .controller!
          .text,
      '语气温暖活泼，回答前先鼓励孩子大胆猜想。',
    );

    final voiceMode = find.byKey(
      const Key('voice_mode_voiceDesign_editor_new'),
    );
    await tester.ensureVisible(voiceMode);
    await tester.tap(voiceMode);
    await tester.pump();
    await useSuggestion('suggest_voice_description_editor_new');

    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('voice_description_editor_new')),
          )
          .controller!
          .text,
      '温暖明亮、活泼自然的少年伙伴声音',
    );
    expect(
      suggestions.requests.map((request) => request.$1).toSet(),
      CharacterSuggestionField.values.toSet(),
    );
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
    expect(find.byType(VoiceSelector), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('基本信息')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const Key('character_prompt_profile')),
    );
    final prompt = tester.widget<TextFormField>(
      find.byKey(const Key('character_prompt_profile')),
    );
    expect(prompt.controller!.text, savedCharacter.promptProfile);
    await tester.enterText(
      find.byKey(const Key('character_prompt_profile')),
      '保持耐心，多用太空冒险的比喻。',
    );

    await tester.enterText(find.byKey(const Key('character_name')), '星际船长');
    await tapSave(tester);

    expect(drafts.single.name, '星际船长');
    expect(drafts.single.greeting, savedCharacter.greeting);
    expect(drafts.single.defaultVoice.mode, savedCharacter.defaultVoice.mode);
    expect(
      drafts.single.defaultVoice.presetVoice,
      savedCharacter.defaultVoice.presetVoice,
    );
    expect(drafts.single.promptProfile, '保持耐心，多用太空冒险的比喻。');
  });

  testWidgets('custom character editor title follows each visible section', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: CharacterEditorPage(
            character: savedCharacter,
            options: editorOptions,
          ),
        ),
      ),
    );

    for (final section in ['角色设定', '其他信息', '音色设置']) {
      await Scrollable.ensureVisible(
        tester.element(find.text(section)),
        alignment: 0.12,
      );
      await tester.pump();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text(section)),
        findsOneWidget,
      );
    }
  });

  testWidgets('custom character delete requires confirmation', (tester) async {
    final deleted = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              key: const Key('open_editor_for_delete'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CharacterEditorPage(
                    character: savedCharacter,
                    options: editorOptions,
                    onDelete: (character) async => deleted.add(character.id),
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_editor_for_delete')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('delete_character_editor')));
    await tester.pumpAndSettle();
    expect(find.text('删除“星星船长”？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(find.byType(CharacterEditorPage), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete_character_editor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_delete_character_editor')));
    await tester.pumpAndSettle();

    expect(deleted, [savedCharacter.id]);
    expect(find.byType(CharacterEditorPage), findsNothing);
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

  testWidgets('complete form remains scrollable on a small scaled screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: CharacterEditorPage(
            options: editorOptions,
            onSave: (_) async => savedCharacter,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
    await tester.ensureVisible(find.byKey(const Key('save_character')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
