import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';

abstract interface class RingtoneOutput {
  Future<void> open();

  Future<void> play(Uint8List mp3Bytes, void Function() onFinished);

  Future<void> stop();

  Future<void> close();
}

final class Mp3RingtoneOutput implements RingtoneOutput {
  Mp3RingtoneOutput({FlutterSoundPlayer? player})
    : _player = player ?? FlutterSoundPlayer();

  final FlutterSoundPlayer _player;
  bool _opened = false;

  @override
  Future<void> open() async {
    if (_opened) return;
    await _player.openPlayer();
    _opened = true;
  }

  @override
  Future<void> play(Uint8List mp3Bytes, void Function() onFinished) async {
    await _player.startPlayer(
      codec: Codec.mp3,
      fromDataBuffer: mp3Bytes,
      whenFinished: onFinished,
    );
  }

  @override
  Future<void> stop() async {
    if (_opened) await _player.stopPlayer();
  }

  @override
  Future<void> close() async {
    if (!_opened) return;
    await _player.closePlayer();
    _opened = false;
  }
}

class RingtonePlayer {
  RingtonePlayer({
    RingtoneOutput? output,
    Future<ByteData> Function(String key)? assetLoader,
  }) : _output = output ?? Mp3RingtoneOutput(),
       _assetLoader = assetLoader ?? rootBundle.load;

  static const assetPath = 'assets/audio/ringtone.mp3';

  final RingtoneOutput _output;
  final Future<ByteData> Function(String key) _assetLoader;
  Future<void> _work = Future<void>.value();
  Uint8List? _mp3Bytes;
  bool _playing = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_playing || _disposed) return;
    _playing = true;
    _work = _loadAndStart();
    try {
      await _work;
    } on Object {
      _playing = false;
      rethrow;
    }
  }

  Future<void> _loadAndStart() async {
    final asset = await _assetLoader(assetPath);
    if (!_playing) return;
    _mp3Bytes = asset.buffer.asUint8List(
      asset.offsetInBytes,
      asset.lengthInBytes,
    );
    await _output.open();
    if (!_playing) return;
    await _playOnce();
  }

  Future<void> _playOnce() async {
    final bytes = _mp3Bytes;
    if (!_playing || bytes == null) return;
    await _output.play(bytes, _onPlaybackFinished);
  }

  void _onPlaybackFinished() {
    if (!_playing) return;
    _work = _work.then((_) => _playOnce()).catchError((Object _) {
      _playing = false;
    });
  }

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    try {
      await _work;
    } on Object {
      // A ringtone failure must never block answering or declining a call.
    }
    await _output.stop();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _output.close();
    _mp3Bytes = null;
  }

  @visibleForTesting
  static bool isMp3File(Uint8List bytes) {
    if (bytes.lengthInBytes < 3) return false;
    final hasId3Tag = String.fromCharCodes(bytes.sublist(0, 3)) == 'ID3';
    final hasFrameSync =
        bytes.lengthInBytes >= 2 &&
        bytes[0] == 0xff &&
        (bytes[1] & 0xe0) == 0xe0;
    return hasId3Tag || hasFrameSync;
  }
}
