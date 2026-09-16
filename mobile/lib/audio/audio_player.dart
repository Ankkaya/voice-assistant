import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';

abstract interface class PcmAudioOutput {
  Future<void> open();

  Future<void> startStream(int sampleRate);

  Future<void> feed(Uint8List bytes);

  Future<void> stop();

  Future<void> close();
}

final class FlutterSoundPcmAudioOutput implements PcmAudioOutput {
  FlutterSoundPcmAudioOutput({FlutterSoundPlayer? player})
    : _player = player ?? FlutterSoundPlayer();

  final FlutterSoundPlayer _player;

  @override
  Future<void> open() async {
    await _player.openPlayer();
  }

  @override
  Future<void> startStream(int sampleRate) {
    return _player.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: sampleRate,
      interleaved: true,
      bufferSize: 16384,
    );
  }

  @override
  Future<void> feed(Uint8List bytes) async {
    await _player.feedUint8FromStream(bytes);
  }

  @override
  Future<void> stop() => _player.stopPlayer();

  @override
  Future<void> close() => _player.closePlayer();
}

class PcmAudioPlayer {
  PcmAudioPlayer({
    PcmAudioOutput? output,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting Future<void> Function(Duration)? delay,
  }) : _output = output ?? FlutterSoundPcmAudioOutput(),
       _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  // MiMo's streaming response can arrive in multi-second bursts on Android.
  // Keep enough decoded PCM queued before starting AudioTrack so those gaps do
  // not drain the native buffer and force an audible underrun/restart.
  static const _prebufferDuration = Duration(milliseconds: 2500);
  static const _playbackTail = Duration(milliseconds: 80);
  static const _feedBufferBytes = 16384;

  final PcmAudioOutput _output;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  final List<Uint8List> _pending = [];
  bool _opened = false;
  bool _streamStarted = false;
  int _sampleRate = 24000;
  int _pendingBytes = 0;
  DateTime? _expectedPlaybackEnd;
  int _generation = 0;

  Future<void> start(int sampleRate) async {
    final generation = ++_generation;
    if (!_opened) {
      await _output.open();
      _opened = true;
      if (generation != _generation) return;
    }
    if (_streamStarted) {
      await _output.stop();
      if (generation != _generation) return;
    }
    _sampleRate = sampleRate;
    _pending.clear();
    _pendingBytes = 0;
    _streamStarted = false;
    _expectedPlaybackEnd = null;
  }

  Future<void> feed(Uint8List bytes) async {
    if (!_opened) {
      throw StateError('PCM player must be started before feeding audio');
    }
    if (!_streamStarted) {
      final generation = _generation;
      _pending.add(Uint8List.fromList(bytes));
      _pendingBytes += bytes.lengthInBytes;
      final prebufferBytes =
          _sampleRate * 2 * _prebufferDuration.inMilliseconds ~/ 1000;
      if (_pendingBytes < prebufferBytes) return;
      await _startStream(generation);
      return;
    }
    await _feedToOutput(bytes, _generation);
  }

  Future<void> finish() async {
    final generation = _generation;
    if (_opened && !_streamStarted && _pending.isNotEmpty) {
      await _startStream(generation);
    }
    if (generation != _generation || !_streamStarted) return;

    final expectedEnd = _expectedPlaybackEnd;
    if (expectedEnd != null) {
      final remaining = expectedEnd.difference(_clock()) + _playbackTail;
      if (remaining > Duration.zero) await _delay(remaining);
    }
    if (generation != _generation) return;
    await _output.stop();
    _streamStarted = false;
    _expectedPlaybackEnd = null;
  }

  Future<void> _startStream(int generation) async {
    if (generation != _generation) return;
    await _output.startStream(_sampleRate);
    _streamStarted = true;
    if (generation != _generation) {
      await _output.stop();
      _streamStarted = false;
      return;
    }
    final pending = List<Uint8List>.of(_pending);
    _pending.clear();
    _pendingBytes = 0;
    for (final chunk in pending) {
      if (generation != _generation) break;
      await _feedToOutput(chunk, generation);
    }
  }

  Future<void> _feedToOutput(Uint8List bytes, int generation) async {
    var offset = 0;
    while (offset < bytes.lengthInBytes) {
      if (generation != _generation) return;
      final end = (offset + _feedBufferBytes).clamp(0, bytes.lengthInBytes);
      final buffer = Uint8List.sublistView(bytes, offset, end);
      await _output.feed(buffer);
      if (generation != _generation) return;
      // flutter_sound's Android callback returns a completion signal (always
      // 1), not the number of accepted bytes. The blocking AudioTrack write
      // has completed for the whole buffer at this point.
      offset = end;
    }
    final now = _clock();
    final previousEnd = _expectedPlaybackEnd;
    final startsAt = previousEnd != null && previousEnd.isAfter(now)
        ? previousEnd
        : now;
    final microseconds =
        bytes.lengthInBytes *
        Duration.microsecondsPerSecond ~/
        (_sampleRate * 2);
    _expectedPlaybackEnd = startsAt.add(Duration(microseconds: microseconds));
  }

  Future<void> stop() async {
    _generation++;
    _pending.clear();
    _pendingBytes = 0;
    _expectedPlaybackEnd = null;
    if (_opened && _streamStarted) {
      await _output.stop();
    }
    _streamStarted = false;
  }

  Future<void> dispose() async {
    await stop();
    if (_opened) {
      await _output.close();
      _opened = false;
    }
  }
}
