import 'package:child_voice_call/audio/voice_clone_recorder.dart';
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

class FakeVoiceRecorder implements VoiceCloneRecorder {
  bool permissionGranted = true;
  Duration duration = const Duration(seconds: 12);
  int startCount = 0;
  int stopCount = 0;
  int cancelCount = 0;

  @override
  Stream<double> get levels => const Stream<double>.empty();

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> start() async => startCount++;

  @override
  Future<VoiceCloneRecording> stop() async {
    stopCount++;
    return VoiceCloneRecording(
      path: '/cache/voice_clone.wav',
      name: '我的录音.wav',
      size: 2048,
      duration: duration,
    );
  }

  @override
  Future<void> cancel() async => cancelCount++;

  @override
  Future<void> dispose() async {}
}

class FakeVoicePreviewPlayer implements VoiceClonePreviewPlayer {
  @override
  Future<void> play(String path, {required void Function() onFinished}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Widget voiceSelectorApp(
  FakeVoicePicker picker,
  GlobalKey<VoiceSelectorState> selectorKey, {
  Future<String?> Function()? onSuggestVoiceDescription,
  VoiceCloneRecorder? voiceRecorder,
  VoiceClonePreviewPlayer? previewPlayer,
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
        voiceRecorder: voiceRecorder,
        previewPlayer: previewPlayer,
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

  testWidgets('microphone recording becomes the clone reference', (
    tester,
  ) async {
    final picker = FakeVoicePicker();
    final recorder = FakeVoiceRecorder();
    final selectorKey = GlobalKey<VoiceSelectorState>();
    await tester.pumpWidget(
      voiceSelectorApp(
        picker,
        selectorKey,
        voiceRecorder: recorder,
        previewPlayer: FakeVoicePreviewPlayer(),
      ),
    );
    await selectMode(tester, VoiceMode.voiceClone);

    await tester.tap(find.byKey(const Key('record_reference')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start_voice_recording')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump();
    expect(recorder.startCount, 1);

    final stopButton = find.byKey(const Key('stop_voice_recording'));
    await tester.ensureVisible(stopButton);
    tester.widget<FilledButton>(stopButton).onPressed!();
    await tester.pumpAndSettle();
    expect(recorder.stopCount, 1);
    expect(find.text('录音时长 00:12'), findsOneWidget);

    final useButton = find.byKey(const Key('use_voice_recording'));
    await tester.ensureVisible(useButton);
    tester.widget<FilledButton>(useButton).onPressed!();
    await tester.pumpAndSettle();

    expect(
      selectorKey.currentState!.value.referencePath,
      '/cache/voice_clone.wav',
    );
    expect(selectorKey.currentState!.value.referenceName, '我的录音.wav');
    expect(selectorKey.currentState!.value.cloneAuthorized, isFalse);
    expect(find.text('录音时长 00:12'), findsOneWidget);
  });

  testWidgets('recording permission denial keeps the recording sheet open', (
    tester,
  ) async {
    final picker = FakeVoicePicker();
    final recorder = FakeVoiceRecorder()..permissionGranted = false;
    final selectorKey = GlobalKey<VoiceSelectorState>();
    await tester.pumpWidget(
      voiceSelectorApp(
        picker,
        selectorKey,
        voiceRecorder: recorder,
        previewPlayer: FakeVoicePreviewPlayer(),
      ),
    );
    await selectMode(tester, VoiceMode.voiceClone);

    await tester.tap(find.byKey(const Key('record_reference')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start_voice_recording')));
    await tester.pumpAndSettle();

    expect(find.text('需要麦克风权限才能录制声音'), findsOneWidget);
    expect(find.byKey(const Key('open_microphone_settings')), findsOneWidget);
    expect(recorder.startCount, 0);
  });

  testWidgets('recording shorter than five seconds is rejected', (
    tester,
  ) async {
    final picker = FakeVoicePicker();
    final recorder = FakeVoiceRecorder()..duration = const Duration(seconds: 3);
    final selectorKey = GlobalKey<VoiceSelectorState>();
    await tester.pumpWidget(
      voiceSelectorApp(
        picker,
        selectorKey,
        voiceRecorder: recorder,
        previewPlayer: FakeVoicePreviewPlayer(),
      ),
    );
    await selectMode(tester, VoiceMode.voiceClone);

    await tester.tap(find.byKey(const Key('record_reference')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start_voice_recording')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    await tester.pump();
    final stopButton = find.byKey(const Key('stop_voice_recording'));
    await tester.ensureVisible(stopButton);
    tester.widget<FilledButton>(stopButton).onPressed!();
    await tester.pumpAndSettle();

    expect(find.text('录音太短，请至少录制 5 秒'), findsOneWidget);
    expect(find.byKey(const Key('use_voice_recording')), findsNothing);
    expect(recorder.cancelCount, 1);
  });
}
