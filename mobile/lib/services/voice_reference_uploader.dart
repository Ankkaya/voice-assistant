import 'dart:convert';

import 'package:http/http.dart' as http;

import '../controllers/call_controller.dart';

class VoiceReferenceUploader {
  VoiceReferenceUploader({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> upload(String path) async {
    final socketUri = Uri.parse(defaultVoiceServerUrl);
    final uploadUri = socketUri.replace(
      scheme: socketUri.scheme == 'wss' ? 'https' : 'http',
      path: '/api/voice-references',
      query: null,
      fragment: null,
    );
    final request = http.MultipartRequest('POST', uploadUri)
      ..files.add(await http.MultipartFile.fromPath('file', path));
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 201) {
      throw VoiceReferenceUploadException(response.statusCode);
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['referenceId']! as String;
  }

  void close() => _client.close();
}

class VoiceReferenceUploadException implements Exception {
  const VoiceReferenceUploadException(this.statusCode);

  final int statusCode;
}
