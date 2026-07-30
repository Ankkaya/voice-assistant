import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class Character {
  const Character({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.avatar,
    required this.themeColor,
  });

  final String id;
  final String name;
  final String subtitle;
  final String avatar;
  final Color themeColor;

  factory Character.fromJson(Map<String, Object?> json) {
    final color = (json['themeColor']! as String).replaceFirst('#', '');
    return Character(
      id: json['id']! as String,
      name: json['name']! as String,
      subtitle: json['subtitle']! as String,
      avatar: json['avatar']! as String,
      themeColor: Color(int.parse('FF$color', radix: 16)),
    );
  }
}

class CharacterRepository {
  const CharacterRepository();

  Future<List<Character>> load() async {
    final source = await rootBundle.loadString('assets/characters.json');
    final records = jsonDecode(source) as List<dynamic>;
    return records
        .cast<Map<String, dynamic>>()
        .map((record) => Character.fromJson(record))
        .toList(growable: false);
  }
}

final charactersProvider = FutureProvider<List<Character>>((ref) {
  return const CharacterRepository().load();
});
