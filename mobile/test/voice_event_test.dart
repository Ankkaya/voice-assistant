import 'package:child_voice_call/protocol/voice_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses assistant audio metadata', () {
    final event = VoiceEvent.fromJson({
      'type': 'assistant.audio.start',
      'turnId': 'turn_1',
      'encoding': 'pcm16le',
      'sampleRate': 24000,
      'channels': 1,
    });

    expect(event, isA<AssistantAudioStart>());
    final audio = event as AssistantAudioStart;
    expect(audio.turnId, 'turn_1');
    expect(audio.sampleRate, 24000);
  });

  test('rejects unknown event', () {
    expect(
      () => VoiceEvent.fromJson({'type': 'unknown'}),
      throwsA(isA<FormatException>()),
    );
  });
}

