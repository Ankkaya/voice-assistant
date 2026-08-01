import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/pages/character_editor_page.dart';
import 'package:child_voice_call/widgets/voice_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'character_editor_page_test.dart'
    show editorOptions, fillValidCharacterForm, savedCharacter;

class FakeVoicePicker implements VoiceReferencePicker {
  PickedVoiceReference? result;
  @override
  Future<PickedVoiceReference?> pick() async => result;
}

Widget voiceEditorApp(FakeVoicePicker picker) => ProviderScope(
  child: MaterialApp(
    home: CharacterEditorPage(
      options: editorOptions,
      voiceReferencePicker: picker,
      onSave: (_) async => savedCharacter,
    ),
  ),
);

Future<void> selectMode(WidgetTester tester, VoiceMode mode) async {
  final finder = find.byKey(Key('voice_mode_${mode.name}'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> save(WidgetTester tester) async {
  final finder = find.byKey(const Key('save_character'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('clone mode requires file and explicit authorization', (
    tester,
  ) async {
    final picker = FakeVoicePicker();
    await tester.pumpWidget(voiceEditorApp(picker));
    await fillValidCharacterForm(tester);
    await selectMode(tester, VoiceMode.voiceClone);

    await save(tester);
    expect(find.text('请选择 WAV 或 MP3 参考音频'), findsOneWidget);

    picker.result = const PickedVoiceReference(
      path: '/private/authorized.wav',
      name: 'authorized.wav',
      size: 1024,
    );
    final pickButton = find.byKey(const Key('pick_reference'));
    await tester.ensureVisible(pickButton);
    await tester.tap(pickButton);
    await tester.pump();
    await save(tester);
    expect(find.text('请确认你拥有该声音的使用授权'), findsOneWidget);
  });

  testWidgets('voice design enforces 8 to 500 characters', (tester) async {
    final picker = FakeVoicePicker();
    await tester.pumpWidget(voiceEditorApp(picker));
    await fillValidCharacterForm(tester);
    await selectMode(tester, VoiceMode.voiceDesign);
    final description = find.byKey(const Key('voice_description'));
    await tester.enterText(description, '太短');

    await save(tester);

    expect(find.text('请至少用 8 个字描述希望生成的音色'), findsOneWidget);
  });
}
