import 'dart:async';
import 'dart:typed_data';

import 'package:child_voice_call/controllers/call_controller.dart';
import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/pages/call_page.dart';
import 'package:child_voice_call/protocol/voice_event.dart';
import 'package:child_voice_call/websocket/voice_socket.dart';
import 'package:flutter/material.dart';
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
  avatar: 'assets/characters/ryder.svg',
  themeColor: Colors.red,
);

void main() {
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
        ),
      ),
    );

    expect(find.text('你可以说话啦'), findsOneWidget);
    expect(find.byKey(const Key('hangup_button')), findsOneWidget);
    expect(find.text('按住说话'), findsNothing);
    controller.dispose();
  });
}
