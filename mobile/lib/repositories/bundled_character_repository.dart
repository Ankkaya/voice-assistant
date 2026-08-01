import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/character.dart';

class BundledCharacterRepository {
  BundledCharacterRepository({AssetBundle? bundle})
    : bundle = bundle ?? rootBundle;

  final AssetBundle bundle;

  Future<List<Character>> load() async {
    final source = await bundle.loadString('assets/characters.json');
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Bundled characters must be a list');
    }
    return decoded
        .map((record) {
          if (record is! Map) {
            throw const FormatException('Bundled character is invalid');
          }
          return Character.fromBundledJson(record.cast<String, Object?>());
        })
        .toList(growable: false);
  }
}

final charactersProvider = FutureProvider<List<Character>>((ref) {
  return BundledCharacterRepository().load();
});
