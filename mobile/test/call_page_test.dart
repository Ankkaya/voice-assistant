import 'dart:async';

import 'package:child_voice_call/audio/audio_player.dart';
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
  PageTestSocket({this.lifecycleEvents, this.closeError, this.closeWait});

  final List<String>? lifecycleEvents;
  final Object? closeError;
  final Future<void>? closeWait;
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
  Future<void> close() async {
    lifecycleEvents?.add('controller hangup');
    if (closeError case final error?) throw error;
    await closeWait;
  }
}

class PageTestPcmOutput implements PcmAudioOutput {
  final events = <String>[];

  @override
  Future<void> open() async => events.add('open');

  @override
  Future<void> startStream(int sampleRate) async {
    events.add('start:$sampleRate');
  }

  @override
  Future<void> feed(Uint8List bytes) async {
    events.add('feed:${bytes.lengthInBytes}');
  }

  @override
  Future<void> stop() async => events.add('stop');

  @override
  Future<void> close() async => events.add('close');
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

Future<Completer<CallPageResult?>> openCallRoute(
  WidgetTester tester, {
  required CallController controller,
  required bool incomingCall,
  required Future<void> Function() cleanup,
  required Future<void> Function() playHangupTone,
  bool autoConnect = false,
  Character callCharacter = character,
  List<String>? routeEvents,
  PcmAudioPlayer? audioPlayer,
}) async {
  final result = Completer<CallPageResult?>();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => FilledButton(
          key: const Key('open_call'),
          onPressed: () async {
            final routeResult = await Navigator.of(context)
                .push<CallPageResult>(
                  MaterialPageRoute<CallPageResult>(
                    builder: (_) => CallPage(
                      character: callCharacter,
                      controller: controller,
                      autoConnect: autoConnect,
                      incomingCall: incomingCall,
                      audioPlayer: audioPlayer,
                      audioCleanupOverride: cleanup,
                      hangupTonePlaybackOverride: playHangupTone,
                    ),
                  ),
                );
            routeEvents?.add('pop');
            result.complete(routeResult);
          },
          child: const Text('打开通话'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open_call')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  return result;
}

Future<void> allowEndCallWork(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump();
}

Future<void> finishCallRoutePop(WidgetTester tester) async {
  await allowEndCallWork(tester);
  await tester.pump(const Duration(milliseconds: 350));
}

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

  testWidgets('socket interruption cleans up and closes the call page', (
    tester,
  ) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    var cleanedUp = false;
    var hangupTonePlays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async => cleanedUp = true,
      playHangupTone: () async => hangupTonePlays++,
    );

    controller.onSocketError(const VoiceSocketClosed());
    await finishCallRoutePop(tester);

    expect(controller.state.connectionLost, isTrue);
    expect(cleanedUp, isTrue);
    expect(hangupTonePlays, 0);
    expect(await result.future, CallPageResult.ended);
    controller.dispose();
  });

  testWidgets('hangup before connection starts tone, then returns', (
    tester,
  ) async {
    final events = <String>[];
    final controller = CallController(
      character: character,
      socket: PageTestSocket(lifecycleEvents: events),
    );
    addTearDown(controller.dispose);
    var plays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async => events.add('cleanup'),
      playHangupTone: () async {
        plays++;
        events.add('tone');
      },
      routeEvents: events,
    );

    await tester.tap(find.byKey(const Key('hangup_button')));
    await finishCallRoutePop(tester);

    expect(
      events,
      containsAll(['controller hangup', 'cleanup', 'tone', 'pop']),
    );
    expect(plays, 1);
    expect(await result.future, CallPageResult.ended);
  });

  testWidgets('hangup after connection starts tone, then returns', (
    tester,
  ) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);
    controller.onEvent(const AssistantAudioEnd(turnId: 'greeting'));
    expect(controller.state.phase, CallPhase.listening);
    var plays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async {},
      playHangupTone: () async => plays++,
    );

    await tester.tap(find.byKey(const Key('hangup_button')));
    await finishCallRoutePop(tester);

    expect(plays, 1);
    expect(await result.future, CallPageResult.ended);
  });

  testWidgets('active hangup returns without waiting for background cleanup', (
    tester,
  ) async {
    final socketClose = Completer<void>();
    final controller = CallController(
      character: character,
      socket: PageTestSocket(closeWait: socketClose.future),
    );
    addTearDown(controller.dispose);
    final cleanup = Completer<void>();
    final playback = Completer<void>();
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () => cleanup.future,
      playHangupTone: () => playback.future,
    );

    await tester.tap(find.byKey(const Key('hangup_button')));
    await finishCallRoutePop(tester);

    expect(result.isCompleted, isTrue);
    expect(await result.future, CallPageResult.ended);
    socketClose.complete();
    cleanup.complete();
    playback.complete();
  });

  testWidgets('active hangup stops assistant audio before returning', (
    tester,
  ) async {
    final output = PageTestPcmOutput();
    final player = PcmAudioPlayer(output: output);
    await player.start(24000);
    await player.feed(Uint8List(4800));
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);

    await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async {},
      playHangupTone: () async {},
      audioPlayer: player,
    );

    await tester.tap(find.byKey(const Key('hangup_button')));
    await tester.pump();

    expect(output.events, contains('stop'));
  });

  testWidgets('repeated active hangup taps play only one tone', (tester) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);
    final playback = Completer<void>();
    var plays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async {},
      playHangupTone: () {
        plays++;
        return playback.future;
      },
    );

    await tester.tap(find.byKey(const Key('hangup_button')));
    await tester.tap(find.byKey(const Key('hangup_button')));
    await finishCallRoutePop(tester);
    expect(plays, 1);
    expect(result.isCompleted, isTrue);

    playback.complete();
    expect(await result.future, CallPageResult.ended);
  });

  testWidgets('tone failure still returns from the call', (tester) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async {},
      playHangupTone: () => Future<void>.error(StateError('audio unavailable')),
    );

    await tester.tap(find.byKey(const Key('hangup_button')));
    await finishCallRoutePop(tester);

    expect(await result.future, CallPageResult.ended);
  });

  testWidgets('cleanup failure still plays tone and returns', (tester) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);
    var plays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () => Future<void>.error(StateError('cleanup failed')),
      playHangupTone: () async => plays++,
    );

    await tester.tap(find.byKey(const Key('hangup_button')));
    await finishCallRoutePop(tester);

    expect(plays, 1);
    expect(await result.future, CallPageResult.ended);
  });

  testWidgets('controller hangup failure still cleans up, plays, and returns', (
    tester,
  ) async {
    final events = <String>[];
    final controller = CallController(
      character: character,
      socket: PageTestSocket(
        lifecycleEvents: events,
        closeError: StateError('socket close failed'),
      ),
    );
    addTearDown(controller.dispose);
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async => events.add('cleanup'),
      playHangupTone: () async => events.add('tone'),
      routeEvents: events,
    );

    await tester.tap(find.byKey(const Key('hangup_button')));
    await finishCallRoutePop(tester);

    expect(
      events,
      containsAll(['controller hangup', 'cleanup', 'tone', 'pop']),
    );
    expect(await result.future, CallPageResult.ended);
  });

  testWidgets('declining an incoming call does not play hangup tone', (
    tester,
  ) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);
    var plays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: true,
      cleanup: () async {},
      playHangupTone: () async => plays++,
    );

    await tester.tap(find.byKey(const Key('decline_call_button')));
    await finishCallRoutePop(tester);

    expect(plays, 0);
    expect(await result.future, CallPageResult.ended);
  });

  testWidgets('system back from an active call stays silent', (tester) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);
    var plays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async {},
      playHangupTone: () async => plays++,
    );

    await tester.binding.handlePopRoute();
    await finishCallRoutePop(tester);

    expect(plays, 0);
    expect(await result.future, CallPageResult.ended);
  });

  testWidgets('paused lifecycle termination stays silent', (tester) async {
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);
    var plays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async {},
      playHangupTone: () async => plays++,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await finishCallRoutePop(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(plays, 0);
    expect(await result.future, CallPageResult.ended);
  });

  testWidgets('microphone denial closes without hangup tone', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (call) async => call.method == 'hasPermission' ? false : null,
        );
    final controller = CallController(
      character: character,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);
    var plays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      autoConnect: true,
      cleanup: () async {},
      playHangupTone: () async => plays++,
    );

    await finishCallRoutePop(tester);

    expect(plays, 0);
    expect(await result.future, CallPageResult.ended);
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
    var hangupTonePlays = 0;
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
                      hangupTonePlaybackOverride: () async {
                        hangupTonePlays++;
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
    expect(hangupTonePlays, 0);
    expect(result.isCompleted, isTrue);
    expect(await result.future, CallPageResult.editCharacter);
    controller.dispose();
  });

  testWidgets('configuration-error back action stays silent', (tester) async {
    final controller = CallController(
      character: customCharacter,
      socket: PageTestSocket(),
    );
    addTearDown(controller.dispose);
    controller.onEvent(
      const TurnErrorEvent(
        stage: 'session',
        code: 'UNSAFE_CHARACTER_CONFIG',
        recoverable: false,
        message: '角色设定需要修改后才能通话。',
      ),
    );
    var plays = 0;
    final result = await openCallRoute(
      tester,
      controller: controller,
      incomingCall: false,
      cleanup: () async {},
      playHangupTone: () async => plays++,
      callCharacter: customCharacter,
    );

    await tester.tap(find.byKey(const Key('back_to_characters_after_error')));
    await finishCallRoutePop(tester);

    expect(plays, 0);
    expect(await result.future, CallPageResult.ended);
  });
}
