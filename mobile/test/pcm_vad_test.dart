import 'dart:typed_data';

import 'package:child_voice_call/audio/pcm_vad.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pcmFrame(int amplitude) {
  final data = ByteData(640);
  for (var offset = 0; offset < 640; offset += 2) {
    final sample = (offset ~/ 2).isEven ? amplitude : -amplitude;
    data.setInt16(offset, sample, Endian.little);
  }
  return data.buffer.asUint8List();
}

List<VadAction> feed(PcmVad vad, int milliseconds, int amplitude) {
  final actions = <VadAction>[];
  for (var i = 0; i < milliseconds ~/ 20; i++) {
    actions.addAll(vad.process(pcmFrame(amplitude)));
  }
  return actions;
}

void main() {
  test('includes pre-roll and commits after 800ms silence', () {
    final vad = PcmVad();
    feed(vad, 200, 0);
    final actions = <VadAction>[...feed(vad, 400, 6000), ...feed(vad, 800, 0)];

    expect(actions.whereType<SpeechStart>(), hasLength(1));
    expect(actions.whereType<SpeechCommit>(), hasLength(1));
    final milliseconds = actions.whereType<VadAudio>().length * 20;
    expect(milliseconds, greaterThanOrEqualTo(1200));
  });

  test('discards speech shorter than 300ms', () {
    final vad = PcmVad();
    final actions = <VadAction>[...feed(vad, 200, 6000), ...feed(vad, 200, 0)];

    expect(actions.whereType<SpeechStart>(), isEmpty);
    expect(actions.whereType<VadDiscard>(), hasLength(1));
  });

  test('forces commit at fifteen seconds', () {
    final vad = PcmVad();
    final actions = feed(vad, 15200, 6000);

    expect(actions.whereType<SpeechStart>(), isNotEmpty);
    expect(actions.whereType<SpeechCommit>(), isNotEmpty);
  });

  test('rejects an incomplete PCM16 sample', () {
    expect(() => PcmVad().process(Uint8List(1)), throwsA(isA<ArgumentError>()));
  });
}
