import 'dart:convert';
import 'dart:io';

import 'package:child_voice_call/repositories/character_options_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class StringAssetBundle extends CachingAssetBundle {
  StringAssetBundle(this.source);
  final String source;

  @override
  Future<ByteData> load(String key) async {
    if (key != 'assets/character_options.json') {
      throw StateError('Unknown asset: $key');
    }
    final bytes = Uint8List.fromList(utf8.encode(source));
    return ByteData.view(bytes.buffer);
  }
}

String optionsJson({required int version}) => jsonEncode({
  'optionsVersion': version,
  'identities': [
    {'id': 'adventure_companion', 'label': '探险伙伴'},
  ],
  'traits': [
    {'id': 'brave', 'label': '勇敢'},
  ],
  'interests': [
    {'id': 'space', 'label': '太空'},
  ],
  'presetVoices': [
    {'id': '白桦', 'label': '白桦'},
    {'id': '苏打', 'label': '苏打'},
  ],
});

http.Response jsonResponse(String body, int statusCode) => http.Response.bytes(
  utf8.encode(body),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late Directory temporaryDirectory;
  late File cacheFile;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'character-options-test-',
    );
    cacheFile = File('${temporaryDirectory.path}/cache/options.json');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  CharacterOptionsRepository repository(http.Client client) =>
      CharacterOptionsRepository(
        bundle: StringAssetBundle(optionsJson(version: 1)),
        cacheFile: cacheFile,
        client: client,
        serverUri: Uri.parse('ws://localhost:8000/ws/voice?ignored=true'),
      );

  test('load prefers valid cache over bundled options', () async {
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString(optionsJson(version: 2));

    final options = await repository(
      MockClient((_) async => http.Response('', 500)),
    ).load();

    expect(options.optionsVersion, 2);
  });

  test('load falls back to bundled options when cache is corrupt', () async {
    await cacheFile.parent.create(recursive: true);
    await cacheFile.writeAsString('{broken');

    final options = await repository(
      MockClient((_) async => http.Response('', 500)),
    ).load();

    expect(options.optionsVersion, 1);
    expect(options.presetVoices.map((voice) => voice.id), ['白桦', '苏打']);
  });

  test('refresh validates response before replacing cache', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return jsonResponse(optionsJson(version: 3), 200);
    });

    final options = await repository(client).refresh();

    expect(options.optionsVersion, 3);
    expect(
      requestedUri,
      Uri.parse('http://localhost:8000/api/character-options'),
    );
    expect(jsonDecode(await cacheFile.readAsString())['optionsVersion'], 3);
  });

  test('invalid refresh leaves the previous cache untouched', () async {
    await cacheFile.parent.create(recursive: true);
    final previous = optionsJson(version: 2);
    await cacheFile.writeAsString(previous);
    final invalid = jsonDecode(optionsJson(version: 3)) as Map<String, dynamic>;
    invalid['identities'] = [
      {'id': 'duplicate', 'label': '重复'},
      {'id': 'duplicate', 'label': '重复'},
    ];
    final client = MockClient(
      (_) async => jsonResponse(jsonEncode(invalid), 200),
    );

    await expectLater(repository(client).refresh(), throwsFormatException);

    expect(await cacheFile.readAsString(), previous);
  });

  test('HTTP failure leaves the previous cache untouched', () async {
    await cacheFile.parent.create(recursive: true);
    final previous = optionsJson(version: 2);
    await cacheFile.writeAsString(previous);
    final client = MockClient((_) async => http.Response('unavailable', 503));

    await expectLater(
      repository(client).refresh(),
      throwsA(isA<http.ClientException>()),
    );

    expect(await cacheFile.readAsString(), previous);
  });
}
