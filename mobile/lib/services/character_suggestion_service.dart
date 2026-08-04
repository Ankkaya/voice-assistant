import 'dart:convert';

import 'package:http/http.dart' as http;

import '../controllers/call_controller.dart';

enum CharacterSuggestionField {
  name('name'),
  subtitle('subtitle'),
  description('description'),
  greeting('greeting'),
  promptProfile('promptProfile'),
  voiceDescription('voiceDescription');

  const CharacterSuggestionField(this.wireName);
  final String wireName;
}

class CharacterSuggestionService {
  CharacterSuggestionService({http.Client? client, Uri? serverUri})
    : _client = client ?? http.Client(),
      _serverUri = serverUri ?? Uri.parse(defaultVoiceServerUrl);

  final http.Client _client;
  final Uri _serverUri;

  Future<String> suggest({
    required CharacterSuggestionField field,
    required Map<String, Object> formContext,
  }) async {
    final endpoint = _serverUri.replace(
      scheme: _serverUri.scheme == 'wss' ? 'https' : 'http',
      path: '/api/character-suggestions',
      query: null,
      fragment: null,
    );
    final response = await _client
        .post(
          endpoint,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'targetField': field.wireName,
            'formContext': formContext,
          }),
        )
        .timeout(const Duration(seconds: 40));
    if (response.statusCode != 200) {
      throw CharacterSuggestionException(response.statusCode);
    }
    final body = jsonDecode(response.body);
    if (body is! Map || body['suggestion'] is! String) {
      throw const FormatException('Character suggestion response is invalid');
    }
    final suggestion = (body['suggestion'] as String).trim();
    if (suggestion.isEmpty) {
      throw const FormatException('Character suggestion is empty');
    }
    return suggestion;
  }

  void close() => _client.close();
}

class CharacterSuggestionException implements Exception {
  const CharacterSuggestionException(this.statusCode);

  final int statusCode;
}
