import 'dart:async';
import 'dart:io';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/character_asset_store.dart';

const voiceCloneMinimumDuration = Duration(seconds: 5);
const voiceCloneRecommendedDuration = Duration(seconds: 30);
const voiceCloneMaximumDuration = Duration(seconds: 60);

class VoiceCloneRecording {
  const VoiceCloneRecording({
    required this.path,
    required this.name,
    required this.size,
    required this.duration,
  });

  final String path;
  final String name;
  final int size;
  final Duration duration;
}

/// Small abstraction around the platform recorder so the recording flow can
/// be tested without a microphone or a platform channel.
abstract interface class VoiceCloneRecorder {
  Stream<double> get levels;

  Future<bool> requestPermission();

  Future<void> start();

  Future<VoiceCloneRecording> stop();

  Future<void> cancel();

  Future<void> dispose();
}

final class RecordVoiceCloneRecorder implements VoiceCloneRecorder {
  RecordVoiceCloneRecorder({AudioRecorder? recorder, this.temporaryRoot})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final Directory? temporaryRoot;
  Stream<double>? _levels;
  String? _path;
  DateTime? _startedAt;
  bool _recording = false;

  @override
  Stream<double> get levels => _levels ??= _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 100))
      .map((amplitude) {
        // Amplitudes are dBFS (normally between -60 and 0). Keep the UI
        // independent of the platform-specific amplitude scale.
        final value = (amplitude.current + 60) / 60;
        return value.clamp(0.0, 1.0).toDouble();
      });

  @override
  Future<bool> requestPermission() => _recorder.hasPermission(request: true);

  @override
  Future<void> start() async {
    if (_recording) throw StateError('Voice clone recording is running');
    final root =
        temporaryRoot ??
        Directory('${(await getTemporaryDirectory()).path}/voice_clone');
    await root.create(recursive: true);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final file = File('${root.path}/voice_$timestamp.wav');
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 24000,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: file.path,
      );
      _path = file.path;
      _startedAt = DateTime.now();
      _recording = true;
    } on Object {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  @override
  Future<VoiceCloneRecording> stop() async {
    if (!_recording || _path == null || _startedAt == null) {
      throw StateError('Voice clone recording is not running');
    }
    final path = _path!;
    final startedAt = _startedAt!;
    try {
      await _recorder.stop();
      final file = File(path);
      if (!await file.exists()) {
        throw const FormatException('录音文件没有生成，请重试');
      }
      final size = await file.length();
      if (size <= 44) {
        throw const FormatException('录音内容为空，请重试');
      }
      if (size > maxVoiceReferenceBytes) {
        throw const FormatException('录音文件过大，请缩短录音后重试');
      }
      final elapsed = DateTime.now().difference(startedAt);
      return VoiceCloneRecording(
        path: path,
        name: '我的录音.wav',
        size: size,
        duration: elapsed,
      );
    } finally {
      _recording = false;
      _startedAt = null;
    }
  }

  @override
  Future<void> cancel() async {
    final path = _path;
    if (_recording) {
      try {
        await _recorder.cancel();
      } finally {
        _recording = false;
        _startedAt = null;
      }
    }
    _path = null;
    if (path != null) await _delete(path);
  }

  @override
  Future<void> dispose() async {
    if (_recording) await cancel();
    await _recorder.dispose();
  }

  static Future<void> _delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on Object {
      // Temporary cleanup must never hide the user's recording result.
    }
  }
}

abstract interface class VoiceClonePreviewPlayer {
  Future<void> play(String path, {required void Function() onFinished});

  Future<void> stop();

  Future<void> dispose();
}

/// Uses the already bundled flutter_sound dependency for WAV preview.
final class FlutterSoundVoiceClonePreviewPlayer
    implements VoiceClonePreviewPlayer {
  FlutterSoundVoiceClonePreviewPlayer({FlutterSoundPlayer? player})
    : _player = player ?? FlutterSoundPlayer();

  final FlutterSoundPlayer _player;
  bool _opened = false;

  @override
  Future<void> play(String path, {required void Function() onFinished}) async {
    if (!_opened) {
      await _player.openPlayer();
      _opened = true;
    }
    await _player.stopPlayer();
    await _player.startPlayer(
      fromURI: path,
      codec: Codec.pcm16WAV,
      whenFinished: onFinished,
    );
  }

  @override
  Future<void> stop() async {
    if (_opened) await _player.stopPlayer();
  }

  @override
  Future<void> dispose() async {
    if (_opened) await _player.closePlayer();
    _opened = false;
  }
}
