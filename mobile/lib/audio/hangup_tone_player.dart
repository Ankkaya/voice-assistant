import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'audio_player.dart';

abstract interface class HangupToneOutput {
  Future<void> start(int sampleRate);

  Future<void> feed(Uint8List bytes);

  Future<void> finish();

  Future<void> dispose();
}

final class PcmHangupToneOutput implements HangupToneOutput {
  PcmHangupToneOutput({PcmAudioPlayer? player})
    : _player = player ?? PcmAudioPlayer();

  final PcmAudioPlayer _player;

  @override
  Future<void> start(int sampleRate) => _player.start(sampleRate);

  @override
  Future<void> feed(Uint8List bytes) => _player.feed(bytes);

  @override
  Future<void> finish() => _player.finish();

  @override
  Future<void> dispose() => _player.dispose();
}

final class HangupTonePlayer {
  HangupTonePlayer({
    HangupToneOutput? output,
    Future<void> Function(Duration)? delay,
  }) : _output = output ?? PcmHangupToneOutput(),
       _delay = delay ?? Future<void>.delayed;

  static const sampleRate = 24000;
  static const duration = Duration(milliseconds: 760);
  static const playbackTail = Duration(milliseconds: 140);

  final HangupToneOutput _output;
  final Future<void> Function(Duration) _delay;
  Future<void>? _playFuture;
  Future<void>? _disposeFuture;
  Future<void>? _outputDisposeFuture;

  Future<void> play() {
    final disposeFuture = _disposeFuture;
    if (disposeFuture != null) return disposeFuture;
    return _playFuture ??= _playOnce();
  }

  Future<void> _playOnce() async {
    try {
      await _output.start(sampleRate);
      await _output.feed(buildTone());
      await _output.finish();
      await _delay(duration + playbackTail);
    } finally {
      await _disposeOutputOnce();
    }
  }

  Future<void> dispose() => _disposeFuture ??= _disposeAfterPlay();

  Future<void> _disposeAfterPlay() async {
    final playFuture = _playFuture;
    if (playFuture != null) {
      try {
        await playFuture;
      } catch (_) {
        // Playback failures are reported to the play caller. Disposal still
        // waits for, and reports failures from, the shared output release.
      }
    }
    await _disposeOutputOnce();
  }

  Future<void> _disposeOutputOnce() {
    return _outputDisposeFuture ??= Future<void>.sync(_output.dispose);
  }

  @visibleForTesting
  static Uint8List buildTone() {
    const firstEndMs = 260.0;
    const secondStartMs = 330.0;
    const secondEndMs = 730.0;
    const fadeMs = 18.0;
    final sampleCount = sampleRate * duration.inMilliseconds ~/ 1000;
    final data = ByteData(sampleCount * 2);

    for (var index = 0; index < sampleCount; index++) {
      final milliseconds = index * 1000 / sampleRate;
      final (
        frequency,
        segmentPosition,
        segmentLength,
      ) = milliseconds < firstEndMs
          ? (620.0, milliseconds, firstEndMs)
          : milliseconds >= secondStartMs && milliseconds < secondEndMs
          ? (440.0, milliseconds - secondStartMs, secondEndMs - secondStartMs)
          : (0.0, 0.0, 0.0);
      final envelope = frequency == 0
          ? 0.0
          : math.min(
              1.0,
              math.min(
                segmentPosition / fadeMs,
                (segmentLength - segmentPosition) / fadeMs,
              ),
            );
      final seconds = index / sampleRate;
      final sample =
          (math.sin(2 * math.pi * frequency * seconds) * envelope * 18000)
              .round()
              .clamp(-32768, 32767);
      data.setInt16(index * 2, sample, Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
