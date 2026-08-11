import 'dart:async';

import 'package:child_voice_call/audio/ringtone_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeRingtoneOutput implements RingtoneOutput {
  final events = <String>[];
  void Function()? onFinished;
  bool opened = false;

  @override
  Future<void> open() async {
    opened = true;
    events.add('open');
  }

  @override
  Future<void> play(Uint8List mp3Bytes, void Function() onFinished) async {
    events.add('play:${mp3Bytes.lengthInBytes}');
    this.onFinished = onFinished;
  }

  @override
  Future<void> stop() async {
    if (opened) events.add('stop');
  }

  @override
  Future<void> close() async {
    if (!opened) return;
    opened = false;
    events.add('close');
  }

  void finishPlayback() => onFinished?.call();
}

ByteData _assetData([List<int> bytes = const [1, 2, 3, 4]]) {
  return ByteData.sublistView(Uint8List.fromList(bytes));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundles the selected MP3 ringtone', () async {
    final data = await rootBundle.load(RingtonePlayer.assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    expect(RingtonePlayer.isMp3File(bytes), isTrue);
    expect(bytes, hasLength(36197));
  });

  test('starts once and loops when MP3 playback finishes', () async {
    final output = FakeRingtoneOutput();
    var loads = 0;
    final player = RingtonePlayer(
      output: output,
      assetLoader: (path) async {
        loads++;
        expect(path, RingtonePlayer.assetPath);
        return _assetData();
      },
    );

    await Future.wait([player.start(), player.start()]);
    expect(loads, 1);
    expect(output.events, ['open', 'play:4']);

    output.finishPlayback();
    await Future<void>.delayed(Duration.zero);
    expect(output.events, ['open', 'play:4', 'play:4']);

    await player.dispose();
    expect(output.events, ['open', 'play:4', 'play:4', 'stop', 'close']);
  });

  test('stop prevents a completed MP3 from starting another loop', () async {
    final output = FakeRingtoneOutput();
    final player = RingtonePlayer(
      output: output,
      assetLoader: (_) async => _assetData(),
    );

    await player.start();
    await player.stop();
    output.finishPlayback();
    await Future<void>.delayed(Duration.zero);
    await player.dispose();

    expect(output.events, ['open', 'play:4', 'stop', 'close']);
  });

  test('dispose during asset loading prevents late playback', () async {
    final output = FakeRingtoneOutput();
    final loadEntered = Completer<void>();
    final loadGate = Completer<void>();
    final player = RingtonePlayer(
      output: output,
      assetLoader: (_) async {
        loadEntered.complete();
        await loadGate.future;
        return _assetData();
      },
    );

    final start = player.start();
    await loadEntered.future;
    final dispose = player.dispose();
    loadGate.complete();
    await Future.wait([start, dispose]);

    expect(output.events, isEmpty);
  });
}
