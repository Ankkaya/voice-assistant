import 'dart:async';

import 'package:child_voice_call/controllers/call_controller.dart';
import 'package:child_voice_call/controllers/call_state.dart';
import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/pages/call_page.dart';
import 'package:child_voice_call/protocol/voice_event.dart';
import 'package:child_voice_call/websocket/voice_socket.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class PageTestSocket implements VoiceSocketClient {
  final eventController = StreamController<VoiceEvent>.broadcast();
  final audioController = StreamController<Uint8List>.broadcast();
  @override
  Stream<Uint8List> get audioChunks => audioController.stream;
  @override
  Stream<VoiceEvent> get events => eventController.stream;
  @override
  Future<void> connect(Uri uri) async {}
  @override
  void sendAudio(Uint8List data) {}
  @override
  void sendEvent(Map<String, Object> event) {}
  @override
  Future<void> close() async {}
}

const character = Character(
  id: 'ryder',
  name: '莱德',
  subtitle: '救援队长',
  avatar: CharacterAvatarRef.asset('assets/characters/ryder.png'),
  defaultVoiceDescription: '明亮友好的少年声音',
  defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '苏打'),
  themeColor: Colors.red,
);

const customCharacter = Character(
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

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          null,
        );
  });

  testWidgets('only exposes hangup during a call', (tester) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    controller.onEvent(const AssistantAudioStart(turnId: 'greeting'));
    controller.onEvent(const AssistantAudioEnd(turnId: 'greeting'));

    await tester.pumpWidget(
      MaterialApp(
        home: CallPage(
          character: character,
          controller: controller,
          autoConnect: false,
          incomingCall: false,
        ),
      ),
    );

    expect(find.text('你可以说话啦'), findsOneWidget);
    expect(find.byKey(const Key('hangup_button')), findsOneWidget);
    expect(find.text('按住说话'), findsNothing);
    controller.dispose();
  });

  testWidgets('incoming call shows decline and animated accept actions', (
    tester,
  ) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CallPage(
          character: character,
          controller: controller,
          autoConnect: false,
        ),
      ),
    );

    expect(find.byKey(const Key('decline_call_button')), findsOneWidget);
    expect(find.byKey(const Key('accept_call_button')), findsOneWidget);
    expect(find.byKey(const Key('hangup_button')), findsNothing);
    expect(find.text('AI 角色来电'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('temporary inactive lifecycle does not end the call', (
    tester,
  ) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CallPage(
          character: character,
          controller: controller,
          autoConnect: false,
        ),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(find.byType(CallPage), findsOneWidget);
    expect(controller.state.phase, isNot(CallPhase.ended));
    controller.dispose();
  });

  testWidgets('custom configuration error offers edit action', (tester) async {
    final controller = CallController(
      character: customCharacter,
      socket: PageTestSocket(),
    );
    controller.onEvent(
      const TurnErrorEvent(
        stage: 'session',
        code: 'UNSAFE_CHARACTER_CONFIG',
        recoverable: false,
        message: '角色设定需要修改后才能通话。',
      ),
    );
    final result = Completer<CallPageResult?>();
    var audioCleanedUp = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            key: const Key('open_call'),
            onPressed: () async {
              result.complete(
                await Navigator.of(context).push<CallPageResult>(
                  MaterialPageRoute<CallPageResult>(
                    builder: (_) => CallPage(
                      character: customCharacter,
                      controller: controller,
                      autoConnect: false,
                      incomingCall: false,
                      audioCleanupOverride: () {
                        audioCleanedUp = true;
                        return SynchronousFuture<void>(null);
                      },
                    ),
                  ),
                ),
              );
            },
            child: const Text('打开通话'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_call')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final editButton = tester.widget<FilledButton>(
      find.byKey(const Key('edit_character_after_error')),
    );
    await tester.runAsync(() async {
      final endFuture = (editButton.onPressed as dynamic)() as Future<void>;
      await endFuture;
    });
    await tester.pump(const Duration(milliseconds: 300));
    expect(audioCleanedUp, isTrue);
    expect(result.isCompleted, isTrue);
    expect(await result.future, CallPageResult.editCharacter);
    controller.dispose();
  });
}
