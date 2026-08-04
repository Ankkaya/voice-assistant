import 'package:child_voice_call/models/character_options.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/widgets/voice_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const selectorOptions = [
  PresetVoiceOption(id: '白桦', label: '白桦'),
  PresetVoiceOption(id: '苏打', label: '苏打'),
];

class FakeVoicePicker implements VoiceReferencePicker {
  PickedVoiceReference? result;
  @override
  Future<PickedVoiceReference?> pick() async => result;
}

Widget voiceSelectorApp(
  FakeVoicePicker picker,
  GlobalKey<VoiceSelectorState> selectorKey, {
  Future<String?> Function()? onSuggestVoiceDescription,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: VoiceSelector(
        key: selectorKey,
        options: selectorOptions,
        initialValue: const VoiceSelection(
          mode: VoiceMode.preset,
          presetVoice: '白桦',
        ),
        picker: picker,
        onSuggestVoiceDescription: onSuggestVoiceDescription,
        onChanged: (_) {},
      ),
    ),
  ),
);

Future<void> selectMode(WidgetTester tester, VoiceMode mode) async {
  final finder = find.byKey(Key('voice_mode_${mode.name}'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('clone mode requires file and explicit authorization', (
    tester,
  ) async {
    final picker = FakeVoicePicker();
    final selectorKey = GlobalKey<VoiceSelectorState>();
    await tester.pumpWidget(voiceSelectorApp(picker, selectorKey));
    await selectMode(tester, VoiceMode.voiceClone);

    expect(selectorKey.currentState?.validate(), isFalse);
    await tester.pump();
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
    expect(selectorKey.currentState?.validate(), isFalse);
    await tester.pump();
    expect(find.text('请确认你拥有该声音的使用授权'), findsOneWidget);
  });

  testWidgets('voice design enforces 8 to 500 characters', (tester) async {
    final picker = FakeVoicePicker();
    final selectorKey = GlobalKey<VoiceSelectorState>();
    await tester.pumpWidget(voiceSelectorApp(picker, selectorKey));
    await selectMode(tester, VoiceMode.voiceDesign);
    final description = find.byKey(const Key('voice_description'));
    await tester.enterText(description, '太短');

    expect(selectorKey.currentState?.validate(), isFalse);
    await tester.pump();

    expect(find.text('请至少用 8 个字描述希望生成的音色'), findsOneWidget);
  });

  testWidgets('voice design can fill an AI-generated suggestion', (
    tester,
  ) async {
    final picker = FakeVoicePicker();
    final selectorKey = GlobalKey<VoiceSelectorState>();
    await tester.pumpWidget(
      voiceSelectorApp(
        picker,
        selectorKey,
        onSuggestVoiceDescription: () async => '温暖明亮、活泼自然的少年伙伴声音',
      ),
    );
    await selectMode(tester, VoiceMode.voiceDesign);

    final button = find.byKey(const Key('suggest_voice_description'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.text('温暖明亮、活泼自然的少年伙伴声音'), findsOneWidget);
    expect(
      selectorKey.currentState!.value.voiceDescription,
      '温暖明亮、活泼自然的少年伙伴声音',
    );
  });
}
