import 'dart:async';
import 'dart:typed_data';

import 'package:child_voice_call/controllers/call_controller.dart';
import 'package:child_voice_call/controllers/call_state.dart';
import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/protocol/voice_event.dart';
import 'package:child_voice_call/websocket/voice_socket.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVoiceSocket implements VoiceSocketClient {
  final eventController = StreamController<VoiceEvent>.broadcast();
  final audioController = StreamController<Uint8List>.broadcast();
  final sentEvents = <Map<String, Object>>[];
  final sentAudio = <Uint8List>[];

  @override
  Stream<Uint8List> get audioChunks => audioController.stream;
  @override
  Stream<VoiceEvent> get events => eventController.stream;
  @override
  Future<void> connect(Uri uri) async {}
  @override
  void sendAudio(Uint8List data) => sentAudio.add(data);
  @override
  void sendEvent(Map<String, Object> event) => sentEvents.add(event);
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
  test('microphone is disabled while assistant speaks', () {
    final controller = CallController(character: character, socket: FakeVoiceSocket());

    controller.onEvent(const AssistantAudioStart(turnId: 'greeting'));

    expect(controller.state.phase, CallPhase.assistantSpeaking);
    expect(controller.state.microphoneEnabled, isFalse);
    controller.dispose();
  });

  test('audio end enables listening', () {
    final controller = CallController(character: character, socket: FakeVoiceSocket());
    controller.onEvent(const AssistantAudioStart(turnId: 'greeting'));

    controller.onEvent(const AssistantAudioEnd(turnId: 'greeting'));

    expect(controller.state.phase, CallPhase.listening);
    expect(controller.state.microphoneEnabled, isTrue);
    controller.dispose();
  });

  test('user turn sends start audio and commit in order', () {
    final socket = FakeVoiceSocket();
    final controller = CallController(character: character, socket: socket);
    controller.onEvent(const AssistantAudioStart(turnId: 'greeting'));
    controller.onEvent(const AssistantAudioEnd(turnId: 'greeting'));

    controller.startUserTurn('turn_1');
    controller.sendUserAudio(Uint8List.fromList([0, 0]));
    controller.commitUserTurn();

    expect(socket.sentEvents.map((event) => event['type']), [
      'input.audio.start',
      'input.audio.commit',
    ]);
    expect(socket.sentAudio, hasLength(1));
    expect(controller.state.phase, CallPhase.processing);
    controller.dispose();
  });
}

