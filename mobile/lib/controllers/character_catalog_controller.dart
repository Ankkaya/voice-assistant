import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/character.dart';
import '../models/character_options.dart';
import '../repositories/bundled_character_repository.dart';
import '../repositories/character_options_repository.dart';
import '../repositories/custom_character_repository.dart';
import '../services/character_asset_store.dart';
import 'call_controller.dart';

class CharacterCatalogDependencies {
  const CharacterCatalogDependencies({
    required this.bundled,
    required this.custom,
    required this.options,
  });

  final BundledCharacterRepository bundled;
  final CustomCharacterRepository custom;
  final CharacterOptionsRepository options;
}

@immutable
class CharacterCatalogState {
  const CharacterCatalogState({
    required this.characters,
    required this.options,
    required this.warnings,
  });

  final List<Character> characters;
  final CharacterOptions options;
  final Set<CharacterLoadWarning> warnings;

  CharacterCatalogState copyWith({
    List<Character>? characters,
    CharacterOptions? options,
    Set<CharacterLoadWarning>? warnings,
  }) => CharacterCatalogState(
    characters: characters ?? this.characters,
    options: options ?? this.options,
    warnings: warnings ?? this.warnings,
  );
}

final characterCatalogDependenciesProvider =
    FutureProvider<CharacterCatalogDependencies>((ref) async {
      final root = await getApplicationSupportDirectory();
      final client = http.Client();
      ref.onDispose(client.close);
      final assets = FileCharacterAssetStore(root: root);
      return CharacterCatalogDependencies(
        bundled: BundledCharacterRepository(),
        custom: CustomCharacterRepository(root: root, assets: assets),
        options: CharacterOptionsRepository(
          bundle: rootBundle,
          cacheFile: File('${root.path}/character_options_cache.json'),
          client: client,
          serverUri: Uri.parse(defaultVoiceServerUrl),
        ),
      );
    });

class CharacterCatalogController extends AsyncNotifier<CharacterCatalogState> {
  late CharacterCatalogDependencies _dependencies;

  @override
  Future<CharacterCatalogState> build() async {
    _dependencies = await ref.watch(
      characterCatalogDependenciesProvider.future,
    );
    final bundled = await _dependencies.bundled.load();
    final custom = await _dependencies.custom.loadWithWarnings();
    final options = await _dependencies.options.load();
    unawaited(Future<void>.delayed(Duration.zero, refreshOptions));
    return CharacterCatalogState(
      characters: [...bundled, ...custom.characters],
      options: options,
      warnings: custom.warnings,
    );
  }

  Future<Character> create(CustomCharacterDraft draft) async {
    final created = await _dependencies.custom.create(draft);
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(characters: [...current.characters, created]),
    );
    return created;
  }

  Future<Character> updateCharacter(
    String id,
    CustomCharacterDraft draft,
  ) async {
    final current = state.requireValue;
    final existing = _find(current, id);
    if (!existing.isCustom) {
      throw StateError('Bundled characters cannot be edited');
    }
    final updated = await _dependencies.custom.update(id, draft);
    final latest = state.requireValue;
    state = AsyncData(
      latest.copyWith(
        characters: [
          for (final character in latest.characters)
            if (character.id == id) updated else character,
        ],
      ),
    );
    return updated;
  }

  Future<void> delete(String id) async {
    final current = state.requireValue;
    final existing = _find(current, id);
    if (!existing.isCustom) {
      throw StateError('Bundled characters cannot be deleted');
    }
    await _dependencies.custom.delete(id);
    final latest = state.requireValue;
    state = AsyncData(
      latest.copyWith(
        characters: latest.characters
            .where((character) => character.id != id)
            .toList(growable: false),
      ),
    );
  }

  Future<void> refreshOptions() async {
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final options = await _dependencies.options.refresh();
      final latest = state.valueOrNull;
      if (latest != null) state = AsyncData(latest.copyWith(options: options));
    } on Object {
      // Bundled/cached options remain usable when the server is unavailable.
    }
  }

  static Character _find(CharacterCatalogState state, String id) {
    for (final character in state.characters) {
      if (character.id == id) return character;
    }
    throw StateError('Character not found');
  }
}

final charactersProvider =
    AsyncNotifierProvider<CharacterCatalogController, CharacterCatalogState>(
      CharacterCatalogController.new,
    );
