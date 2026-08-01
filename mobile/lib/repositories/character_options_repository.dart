import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/character_options.dart';

class CharacterOptionsRepository {
  CharacterOptionsRepository({
    required this.bundle,
    required this.cacheFile,
    required this.client,
    required this.serverUri,
  });

  final AssetBundle bundle;
  final File cacheFile;
  final http.Client client;
  final Uri serverUri;

  Future<CharacterOptions> load() async {
    final bundled = _decode(
      await bundle.loadString('assets/character_options.json'),
    );
    try {
      return _decode(await cacheFile.readAsString());
    } on Object {
      return bundled;
    }
  }

  Future<CharacterOptions> refresh() async {
    final endpoint = Uri(
      scheme: serverUri.scheme == 'wss' ? 'https' : 'http',
      userInfo: serverUri.userInfo,
      host: serverUri.host,
      port: serverUri.hasPort ? serverUri.port : null,
      path: '/api/character-options',
    );
    final response = await client
        .get(endpoint)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw http.ClientException('character options request failed', endpoint);
    }
    final options = _decode(response.body);
    await cacheFile.parent.create(recursive: true);
    final temporary = File('${cacheFile.path}.tmp');
    try {
      await temporary.writeAsString(response.body, flush: true);
      await temporary.rename(cacheFile.path);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
    return options;
  }

  static CharacterOptions _decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Character options must be an object');
    }
    return CharacterOptions.fromJson(decoded.cast<String, Object?>());
  }
}
