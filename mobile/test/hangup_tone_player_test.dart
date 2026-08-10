import 'dart:async';

import 'package:child_voice_call/audio/hangup_tone_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeHangupToneOutput implements HangupToneOutput {
  FakeHangupToneOutput({required this.events, this.playGate, this.disposeGate});

  final List<String> events;
  final Completer<void>? playGate;
  final Completer<void>? disposeGate;
  final playEntered = Completer<void>();
  final disposeEntered = Completer<void>();

  @override
  Future<void> play(Uint8List mp3Bytes) async {
    events.add('play:${mp3Bytes.length}');
    playEntered.complete();
    await playGate?.future;
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
    disposeEntered.complete();
    await disposeGate?.future;
  }
}

ByteData _assetData([List<int> bytes = const [1, 2, 3, 4]]) {
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles the selected MP3 hangup sound', () async {
    final data = await rootBundle.load(HangupTonePlayer.assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    expect(HangupTonePlayer.isMp3File(bytes), isTrue);
    expect(bytes, hasLength(22477));
  });

  test(
    'concurrent play loads the MP3 once and follows one lifecycle',
    () async {
      final events = <String>[];
      var loads = 0;
      final output = FakeHangupToneOutput(events: events);
      final player = HangupTonePlayer(
        output: output,
        assetLoader: (path) async {
          loads++;
          expect(path, HangupTonePlayer.assetPath);
          return _assetData();
        },
      );

      final firstPlay = player.play();
      final secondPlay = player.play();
      expect(identical(firstPlay, secondPlay), isTrue);
      await Future.wait([firstPlay, secondPlay]);
      await player.dispose();
      await player.dispose();

      expect(loads, 1);
      expect(events, ['play:4', 'dispose']);
    },
  );

  test(
    'dispose during asset loading waits for playback and releases once',
    () async {
      final events = <String>[];
      final loadEntered = Completer<void>();
      final loadGate = Completer<void>();
      final output = FakeHangupToneOutput(events: events);
      final player = HangupTonePlayer(
        output: output,
        assetLoader: (path) async {
          loadEntered.complete();
          await loadGate.future;
          return _assetData();
        },
      );

      final play = player.play();
      await loadEntered.future;
      var disposeCompleted = false;
      final dispose = player.dispose().then((_) => disposeCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposeCompleted, isFalse);

      loadGate.complete();
      await Future.wait([play, dispose]);
      expect(events, ['play:4', 'dispose']);
    },
  );

  test(
    'dispose during playback waits for playback and releases once',
    () async {
      final events = <String>[];
      final playGate = Completer<void>();
      final output = FakeHangupToneOutput(events: events, playGate: playGate);
      final player = HangupTonePlayer(
        output: output,
        assetLoader: (_) async => _assetData(),
      );

      final play = player.play();
      await output.playEntered.future;
      var firstDisposeCompleted = false;
      var secondDisposeCompleted = false;
      final firstDispose = player.dispose().then(
        (_) => firstDisposeCompleted = true,
      );
      final secondDispose = player.dispose().then(
        (_) => secondDisposeCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(firstDisposeCompleted, isFalse);
      expect(secondDisposeCompleted, isFalse);

      playGate.complete();
      await Future.wait([play, firstDispose, secondDispose]);
      await player.dispose();
      expect(events, ['play:4', 'dispose']);
    },
  );

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
    expect(firstCompleted, isFalse);
    expect(secondCompleted, isFalse);

    disposeGate.complete();
    await Future.wait([firstDispose, secondDispose]);
    await player.dispose();
    await player.play();

    expect(events, ['dispose']);
  });
}
