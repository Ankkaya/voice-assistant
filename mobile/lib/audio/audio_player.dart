import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';

class PcmAudioPlayer {
  PcmAudioPlayer({FlutterSoundPlayer? player})
    : _player = player ?? FlutterSoundPlayer();

  final FlutterSoundPlayer _player;
  final List<Uint8List> _pending = [];
  bool _opened = false;
  bool _streamStarted = false;
  int _sampleRate = 24000;
  int _pendingBytes = 0;

  Future<void> start(int sampleRate) async {
    if (!_opened) {
      await _player.openPlayer();
      _opened = true;
    }
    if (_streamStarted) {
      await _player.stopPlayer();
    }
    _sampleRate = sampleRate;
    _pending.clear();
    _pendingBytes = 0;
    _streamStarted = false;
  }

  Future<void> feed(Uint8List bytes) async {
    if (!_opened) {
      throw StateError('PCM player must be started before feeding audio');
    }
    if (!_streamStarted) {
      _pending.add(Uint8List.fromList(bytes));
      _pendingBytes += bytes.lengthInBytes;
      final prebufferBytes = (_sampleRate * 2 * 0.1).round();
      if (_pendingBytes < prebufferBytes) return;
      await _startStream();
      return;
    }
    await _player.feedUint8FromStream(bytes);
  }

  Future<void> finish() async {
    if (_opened && !_streamStarted && _pending.isNotEmpty) {
      await _startStream();
    }
  }

  Future<void> _startStream() async {
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: _sampleRate,
      interleaved: true,
      bufferSize: 4096,
    );
    _streamStarted = true;
    for (final chunk in _pending) {
      await _player.feedUint8FromStream(chunk);
    }
    _pending.clear();
    _pendingBytes = 0;
  }

  Future<void> stop() async {
    _pending.clear();
    _pendingBytes = 0;
    if (_opened && _streamStarted) {
      await _player.stopPlayer();
    }
    _streamStarted = false;
  }

  Future<void> dispose() async {
    await stop();
    if (_opened) {
      await _player.closePlayer();
      _opened = false;
    }
  }
}
