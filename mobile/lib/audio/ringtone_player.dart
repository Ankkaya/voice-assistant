import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_player.dart';

class RingtonePlayer {
  RingtonePlayer({PcmAudioPlayer? player})
    : _player = player ?? PcmAudioPlayer();

  static const _sampleRate = 24000;
  static const _cycle = Duration(milliseconds: 2400);

  final PcmAudioPlayer _player;
  Timer? _timer;
  Future<void> _work = Future<void>.value();
  bool _playing = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_playing || _disposed) return;
    _playing = true;
    final pattern = _buildPattern();
    await _player.start(_sampleRate);
    await _player.feed(pattern);
    _timer = Timer.periodic(_cycle, (_) {
      if (!_playing) return;
      _work = _work.then((_) => _player.feed(pattern));
    });
  }

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    _timer?.cancel();
    _timer = null;
    try {
      await _work;
    } on Object {
      // A ringtone failure must never block answering or declining a call.
    }
    await _player.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _player.dispose();
  }

  static Uint8List _buildPattern() {
    final sampleCount = (_sampleRate * _cycle.inMilliseconds / 1000).round();
    final data = ByteData(sampleCount * 2);
    for (var i = 0; i < sampleCount; i++) {
      final seconds = i / _sampleRate;
      final position = seconds % 2.4;
      final ringing = position < 0.42 || (position >= 0.62 && position < 1.04);
      final envelope = ringing ? _edgeEnvelope(position) : 0.0;
      final wave =
          math.sin(2 * math.pi * 440 * seconds) +
          math.sin(2 * math.pi * 520 * seconds);
      final sample = (wave * envelope * 4200).round().clamp(-32768, 32767);
      data.setInt16(i * 2, sample, Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static double _edgeEnvelope(double position) {
    final withinBurst = position < 0.42 ? position : position - 0.62;
    const fade = 0.025;
    if (withinBurst < fade) return withinBurst / fade;
    if (withinBurst > 0.42 - fade) return (0.42 - withinBurst) / fade;
    return 1;
  }
}
