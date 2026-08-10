import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';

abstract interface class HangupToneOutput {
  Future<void> play(Uint8List mp3Bytes);

  Future<void> dispose();
}

final class Mp3HangupToneOutput implements HangupToneOutput {
  Mp3HangupToneOutput({FlutterSoundPlayer? player})
    : _player = player ?? FlutterSoundPlayer();

  final FlutterSoundPlayer _player;
  bool _opened = false;

  @override
  Future<void> play(Uint8List mp3Bytes) async {
    if (!_opened) {
      await _player.openPlayer();
      _opened = true;
    }

    final finished = Completer<void>();
    await _player.startPlayer(
      codec: Codec.mp3,
      fromDataBuffer: mp3Bytes,
      whenFinished: () {
        if (!finished.isCompleted) finished.complete();
      },
    );
    await finished.future;
  }

  @override
  Future<void> dispose() async {
    if (!_opened) return;
    await _player.stopPlayer();
    await _player.closePlayer();
    _opened = false;
  }
}

final class HangupTonePlayer {
  HangupTonePlayer({
    HangupToneOutput? output,
    Future<ByteData> Function(String key)? assetLoader,
  }) : _output = output ?? Mp3HangupToneOutput(),
       _assetLoader = assetLoader ?? rootBundle.load;

  static const assetPath = 'assets/audio/hangup.mp3';

  final HangupToneOutput _output;
  final Future<ByteData> Function(String key) _assetLoader;
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
      final asset = await _assetLoader(assetPath);
      final mp3Bytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      await _output.play(mp3Bytes);
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
