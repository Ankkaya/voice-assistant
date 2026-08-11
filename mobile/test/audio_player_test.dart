import 'dart:async';

import 'package:child_voice_call/audio/audio_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakePcmAudioOutput implements PcmAudioOutput {
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

void main() {
  test('finish drains a short buffered clip before stopping output', () async {
    final output = FakePcmAudioOutput();
    var now = DateTime(2026);
    final delays = <Duration>[];
    final player = PcmAudioPlayer(
      output: output,
      clock: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );

    await player.start(24000);
    await player.feed(Uint8List(2400));
    expect(output.events, ['open']);

    await player.finish();
    await player.dispose();

    expect(delays, [const Duration(milliseconds: 130)]);
    expect(output.events, [
      'open',
      'start:24000',
      'feed:2400',
      'stop',
      'close',
    ]);
  });

  test(
    'finish waits for fast streamed greeting to leave the audio queue',
    () async {
      final output = FakePcmAudioOutput();
      var now = DateTime(2026);
      final delays = <Duration>[];
      final player = PcmAudioPlayer(
        output: output,
        clock: () => now,
        delay: (duration) async {
          delays.add(duration);
          now = now.add(duration);
        },
      );

      await player.start(24000);
      for (var index = 0; index < 16; index++) {
        await player.feed(Uint8List(15360));
        if (index < 15) now = now.add(const Duration(milliseconds: 100));
      }

      await player.finish();

      expect(delays, [const Duration(milliseconds: 3700)]);
      expect(output.events.first, 'open');
      expect(output.events[1], 'start:24000');
      expect(
        output.events.where((event) => event == 'feed:15360'),
        hasLength(16),
      );
      expect(output.events.last, 'stop');
    },
  );

  test(
    'a delayed chunk extends playback from its actual arrival time',
    () async {
      final output = FakePcmAudioOutput();
      var now = DateTime(2026);
      final delays = <Duration>[];
      final player = PcmAudioPlayer(
        output: output,
        clock: () => now,
        delay: (duration) async => delays.add(duration),
      );

      await player.start(24000);
      await player.feed(Uint8List(4800));
      now = now.add(const Duration(seconds: 1));
      await player.feed(Uint8List(4800));
      await player.finish();

      expect(delays, [const Duration(milliseconds: 180)]);
    },
  );

  test('start stops a previous stream and resets its drain tracking', () async {
    final output = FakePcmAudioOutput();
    final player = PcmAudioPlayer(output: output);

    await player.start(24000);
    await player.feed(Uint8List(4800));
    await player.start(16000);
    await player.dispose();

    expect(output.events, [
      'open',
      'start:24000',
      'feed:4800',
      'stop',
      'close',
    ]);
  });

  test('stop interrupts finish drain immediately', () async {
    final output = FakePcmAudioOutput();
    final drainStarted = Completer<void>();
    final releaseDrain = Completer<void>();
    final player = PcmAudioPlayer(
      output: output,
      delay: (_) {
        drainStarted.complete();
        return releaseDrain.future;
      },
    );

    await player.start(24000);
    await player.feed(Uint8List(4800));
    final finish = player.finish();
    await drainStarted.future;

    await player.stop();
    expect(output.events.last, 'stop');

    releaseDrain.complete();
    await finish;
    expect(output.events.where((event) => event == 'stop'), hasLength(1));

    await player.dispose();
  });
}
