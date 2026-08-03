import 'dart:async';
import 'dart:typed_data';

import 'package:child_voice_call/audio/hangup_tone_player.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _samples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return [
    for (var offset = 0; offset < bytes.length; offset += 2)
      data.getInt16(offset, Endian.little),
  ];
}

int _zeroCrossings(List<int> samples, int start, int end) {
  var crossings = 0;
  for (var index = start + 1; index < end; index++) {
    if ((samples[index - 1] < 0 && samples[index] >= 0) ||
        (samples[index - 1] > 0 && samples[index] <= 0)) {
      crossings++;
    }
  }
  return crossings;
}

final class FakeHangupToneOutput implements HangupToneOutput {
  FakeHangupToneOutput({
    required this.events,
    this.startGate,
    this.feedGate,
    this.disposeGate,
  });

  final List<String> events;
  final Completer<void>? startGate;
  final Completer<void>? feedGate;
  final Completer<void>? disposeGate;
  final startEntered = Completer<void>();
  final feedEntered = Completer<void>();
  final disposeEntered = Completer<void>();

  @override
  Future<void> start(int sampleRate) async {
    events.add('start:$sampleRate');
    startEntered.complete();
    await startGate?.future;
  }

  @override
  Future<void> feed(Uint8List bytes) async {
    events.add('feed:${bytes.length}');
    feedEntered.complete();
    await feedGate?.future;
  }

  @override
  Future<void> finish() async => events.add('finish');

  @override
  Future<void> dispose() async {
    events.add('dispose');
    disposeEntered.complete();
    await disposeGate?.future;
  }
}

void main() {
  test('builds 500ms pcm16 with a descending two-part tone', () {
    final bytes = HangupTonePlayer.buildTone();
    final samples = _samples(bytes);
    final samplesPerMillisecond = HangupTonePlayer.sampleRate ~/ 1000;

    expect(bytes, hasLength(HangupTonePlayer.sampleRate));
    expect(samples.any((sample) => sample != 0), isTrue);
    expect(
      samples
          .sublist(185 * samplesPerMillisecond, 225 * samplesPerMillisecond)
          .every((sample) => sample == 0),
      isTrue,
    );

    final highCrossings = _zeroCrossings(
      samples,
      20 * samplesPerMillisecond,
      160 * samplesPerMillisecond,
    );
    final lowCrossings = _zeroCrossings(
      samples,
      250 * samplesPerMillisecond,
      450 * samplesPerMillisecond,
    );
    expect(highCrossings / 140, greaterThan(lowCrossings / 200));
  });

  test('concurrent play follows one ordered lifecycle', () async {
    final events = <String>[];
    final output = FakeHangupToneOutput(events: events);
    final player = HangupTonePlayer(
      output: output,
      delay: (duration) async => events.add('delay:${duration.inMilliseconds}'),
    );

    final firstPlay = player.play();
    final secondPlay = player.play();
    expect(identical(firstPlay, secondPlay), isTrue);
    await Future.wait([firstPlay, secondPlay]);
    await player.dispose();
    await player.dispose();

    expect(events, [
      'start:24000',
      'feed:24000',
      'finish',
      'delay:500',
      'dispose',
    ]);
  });

  for (final stage in ['start', 'feed', 'delay']) {
    test(
      'dispose during $stage waits for playback and releases once',
      () async {
        final events = <String>[];
        final gate = Completer<void>();
        final delayEntered = Completer<void>();
        final output = FakeHangupToneOutput(
          events: events,
          startGate: stage == 'start' ? gate : null,
          feedGate: stage == 'feed' ? gate : null,
        );
        final player = HangupTonePlayer(
          output: output,
          delay: (duration) async {
            events.add('delay:${duration.inMilliseconds}');
            delayEntered.complete();
            if (stage == 'delay') await gate.future;
          },
        );

        final play = player.play();
        await switch (stage) {
          'start' => output.startEntered.future,
          'feed' => output.feedEntered.future,
          _ => delayEntered.future,
        };

        var firstDisposeCompleted = false;
        var secondDisposeCompleted = false;
        final firstDispose = player.dispose().then(
          (_) => firstDisposeCompleted = true,
        );
        final secondDispose = player.dispose().then(
          (_) => secondDisposeCompleted = true,
        );
        await Future<void>.delayed(Duration.zero);
        final firstCompletedBeforePlayback = firstDisposeCompleted;
        final secondCompletedBeforePlayback = secondDisposeCompleted;

        gate.complete();
        await Future.wait([play, firstDispose, secondDispose]);
        await player.dispose();

        expect(firstCompletedBeforePlayback, isFalse);
        expect(secondCompletedBeforePlayback, isFalse);
        expect(events, [
          'start:24000',
          'feed:24000',
          'finish',
          'delay:500',
          'dispose',
        ]);
      },
    );
  }

  test('concurrent dispose waits for one output release', () async {
    final events = <String>[];
    final disposeGate = Completer<void>();
    final output = FakeHangupToneOutput(
      events: events,
      disposeGate: disposeGate,
    );
    final player = HangupTonePlayer(output: output);

    var firstCompleted = false;
    var secondCompleted = false;
    final firstDispose = player.dispose().then((_) => firstCompleted = true);
    await output.disposeEntered.future;
    final secondDispose = player.dispose().then((_) => secondCompleted = true);
    await Future<void>.delayed(Duration.zero);
    final firstCompletedBeforeRelease = firstCompleted;
    final secondCompletedBeforeRelease = secondCompleted;

    disposeGate.complete();
    await Future.wait([firstDispose, secondDispose]);
    await player.dispose();
    await player.play();

    expect(firstCompletedBeforeRelease, isFalse);
    expect(secondCompletedBeforeRelease, isFalse);
    expect(events, ['dispose']);
  });
}
