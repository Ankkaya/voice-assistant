import 'dart:convert';

import 'package:child_voice_call/services/character_suggestion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('posts the target field and current form context', () async {
    late Uri requestedUri;
    late Map<String, dynamic> requestedBody;
    final service = CharacterSuggestionService(
      serverUri: Uri.parse('ws://example.test:8000/ws/voice'),
      client: MockClient((request) async {
        requestedUri = request.url;
        requestedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes(
          utf8.encode(jsonEncode({'suggestion': '爱探索太空的勇敢伙伴'})),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final suggestion = await service.suggest(
      field: CharacterSuggestionField.subtitle,
      formContext: const {
        'name': '星星船长',
        'traits': ['勇敢'],
      },
    );

    expect(requestedUri.scheme, 'http');
    expect(requestedUri.path, '/api/character-suggestions');
    expect(requestedBody['targetField'], 'subtitle');
    expect((requestedBody['formContext'] as Map)['name'], '星星船长');
    expect(suggestion, '爱探索太空的勇敢伙伴');
  });

  test('throws a stable exception when generation is unavailable', () async {
    final service = CharacterSuggestionService(
      serverUri: Uri.parse('ws://example.test/ws/voice'),
      client: MockClient((_) async => http.Response('', 503)),
    );

    expect(
      service.suggest(
        field: CharacterSuggestionField.name,
        formContext: const {},
      ),
      throwsA(
        isA<CharacterSuggestionException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });
}
