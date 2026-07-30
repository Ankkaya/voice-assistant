import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

class AudioCapture {
  AudioCapture({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  static const sampleRate = 16000;
  static const channels = 1;
  static const frameBytes = 640; // 20ms of PCM16LE at 16kHz mono.

  final AudioRecorder _recorder;
  bool _running = false;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<Stream<Uint8List>> start() async {
    if (_running) {
      throw StateError('Audio capture is already running');
    }
    final raw = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
    _running = true;
    return _frameStream(raw);
  }

  Stream<Uint8List> _frameStream(Stream<Uint8List> raw) async* {
    final pending = <int>[];
    await for (final chunk in raw) {
      pending.addAll(chunk);
      while (pending.length >= frameBytes) {
        yield Uint8List.fromList(pending.sublist(0, frameBytes));
        pending.removeRange(0, frameBytes);
      }
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
