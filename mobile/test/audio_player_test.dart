import 'dart:async';
import 'dart:typed_data';

import 'package:child_voice_call/audio/audio_player.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakePcmAudioOutput implements PcmAudioOutput {
  final events = <String>[];
  final fedBytes = BytesBuilder(copy: false);

  @override
  Future<void> open() async => events.add('open');

  @override
  Future<void> startStream(int sampleRate) async {
    events.add('start:$sampleRate');
  }

  @override
  Future<void> feed(Uint8List bytes) async {
    events.add('feed:${bytes.lengthInBytes}');
    fedBytes.add(bytes);
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

      expect(delays, [const Duration(milliseconds: 4400)]);
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

      expect(delays, [const Duration(milliseconds: 280)]);
    },
  );

  test('prebuffers enough PCM to absorb a multi-second stream gap', () async {
    final output = FakePcmAudioOutput();
    var now = DateTime(2026);
    final player = PcmAudioPlayer(output: output, clock: () => now);

    await player.start(24000);
    for (var index = 0; index < 24; index++) {
      await player.feed(Uint8List(4800));
      now = now.add(const Duration(milliseconds: 100));
    }
    expect(output.events, ['open']);

    await player.feed(Uint8List(4800));
    expect(output.events.first, 'open');
    expect(output.events[1], 'start:24000');
    expect(output.events.where((event) => event == 'feed:4800'), hasLength(25));

    now = now.add(const Duration(seconds: 2));
    await player.feed(Uint8List(4800));
    expect(output.events.last, 'feed:4800');
  });

  test('splits oversized PCM chunks to respect native backpressure', () async {
    final output = FakePcmAudioOutput();
    final player = PcmAudioPlayer(output: output);
    final pcm = Uint8List.fromList(
      List<int>.generate(120000, (index) => index & 0xff),
    );

    await player.start(24000);
    await player.feed(pcm);

    expect(output.events, [
      'open',
      'start:24000',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:5312',
    ]);
    expect(output.fedBytes.takeBytes(), pcm);
  });

  test('start stops a previous stream and resets its drain tracking', () async {
    final output = FakePcmAudioOutput();
    final player = PcmAudioPlayer(output: output);

    await player.start(24000);
    await player.feed(Uint8List(120000));
    await player.start(16000);
    await player.dispose();

    expect(output.events, [
      'open',
      'start:24000',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:16384',
      'feed:5312',
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
