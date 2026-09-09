import 'dart:convert';
import 'dart:io';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../controllers/call_controller.dart';

abstract interface class PresetVoicePreviewPlayer {
  Future<void> play(String voice, {required void Function() onFinished});

  Future<void> stop();

  Future<void> dispose();
}

/// Requests a short WAV sample from the voice service and plays it locally.
final class HttpPresetVoicePreviewPlayer implements PresetVoicePreviewPlayer {
  HttpPresetVoicePreviewPlayer({http.Client? client, Uri? serverUri})
    : _client = client ?? http.Client(),
      _serverUri = serverUri ?? Uri.parse(defaultVoiceServerUrl),
      _player = FlutterSoundPlayer();

  final http.Client _client;
  final Uri _serverUri;
  final FlutterSoundPlayer _player;
  bool _opened = false;
  File? _sampleFile;

  @override
  Future<void> play(String voice, {required void Function() onFinished}) async {
    final endpoint = _serverUri.replace(
      scheme: _serverUri.scheme == 'wss' ? 'https' : 'http',
      path: '/api/voice-preview',
      query: null,
      fragment: null,
    );
    final response = await _client
        .post(
          endpoint,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'voice': voice}),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode != 200 || response.bodyBytes.length <= 44) {
      throw HttpException('voice preview request failed');
    }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/preset_voice_preview.wav');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    _sampleFile = file;
    if (!_opened) {
      await _player.openPlayer();
      _opened = true;
    }
    await _player.stopPlayer();
    await _player.startPlayer(
      fromURI: file.path,
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
    _client.close();
    final file = _sampleFile;
    _sampleFile = null;
    if (file != null) {
      try {
        if (await file.exists()) await file.delete();
      } on Object {
        // Best effort cleanup of the short-lived preview sample.
      }
    }
  }
}
