import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/character.dart';
import '../models/character_options.dart';
import '../models/voice_selection.dart';
import '../repositories/bundled_character_repository.dart';
import '../repositories/character_options_repository.dart';
import '../repositories/character_voice_preferences_repository.dart';
import '../repositories/custom_character_repository.dart';
import '../services/character_asset_store.dart';
import 'call_controller.dart';

class CharacterCatalogDependencies {
  const CharacterCatalogDependencies({
    required this.bundled,
    required this.custom,
    required this.options,
    required this.voices,
  });

  final BundledCharacterRepository bundled;
  final CustomCharacterRepository custom;
  final CharacterOptionsRepository options;
  final CharacterVoicePreferencesRepository voices;
}

@immutable
class CharacterCatalogState {
  const CharacterCatalogState({
    required this.characters,
    required this.options,
    required this.warnings,
    required this.voicePreferences,
    required this.voiceWarnings,
    required this.invalidVoiceCharacterIds,
  });

  final List<Character> characters;
  final CharacterOptions options;
  final Set<CharacterLoadWarning> warnings;
  final Map<String, VoiceSelection> voicePreferences;
  final Set<VoicePreferenceWarning> voiceWarnings;
  final Set<String> invalidVoiceCharacterIds;

  VoiceSelection voiceFor(Character character) =>
      voicePreferences[character.id] ?? character.defaultVoice;

  CharacterCatalogState copyWith({
    List<Character>? characters,
    CharacterOptions? options,
    Set<CharacterLoadWarning>? warnings,
    Map<String, VoiceSelection>? voicePreferences,
    Set<VoicePreferenceWarning>? voiceWarnings,
    Set<String>? invalidVoiceCharacterIds,
  }) => CharacterCatalogState(
    characters: characters ?? this.characters,
    options: options ?? this.options,
    warnings: warnings ?? this.warnings,
    voicePreferences: voicePreferences ?? this.voicePreferences,
    voiceWarnings: voiceWarnings ?? this.voiceWarnings,
    invalidVoiceCharacterIds:
        invalidVoiceCharacterIds ?? this.invalidVoiceCharacterIds,
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
        voices: CharacterVoicePreferencesRepository(root: root),
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
    final loadedVoices = await _dependencies.voices.load();
    final characters = [...bundled, ...custom.characters];
    final validIds = characters.map((character) => character.id).toSet();
    final voicePreferences = <String, VoiceSelection>{
      for (final entry in loadedVoices.preferences.entries)
        if (validIds.contains(entry.key)) entry.key: entry.value,
    };
    final invalidVoiceCharacterIds = loadedVoices.invalidCharacterIds
        .where(validIds.contains)
        .toSet();
    final voiceWarnings = <VoicePreferenceWarning>{
      if (loadedVoices.warnings.contains(VoicePreferenceWarning.invalidStore))
        VoicePreferenceWarning.invalidStore,
      if (invalidVoiceCharacterIds.isNotEmpty)
        ...loadedVoices.warnings.where(
          (warning) => warning != VoicePreferenceWarning.invalidStore,
        ),
    };
    unawaited(_dependencies.voices.prune(validIds));
    unawaited(Future<void>.delayed(Duration.zero, refreshOptions));
    return CharacterCatalogState(
      characters: characters,
      options: options,
      warnings: custom.warnings,
      voicePreferences: voicePreferences,
      voiceWarnings: voiceWarnings,
      invalidVoiceCharacterIds: invalidVoiceCharacterIds,
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
    try {
      await _dependencies.voices.delete(id);
    } on Object {
      // The removed character stays removed. A later catalog prune retries
      // cleanup for any stale preference or private reference file.
    }
    final latest = state.requireValue;
    final voicePreferences = Map<String, VoiceSelection>.from(
      latest.voicePreferences,
    )..remove(id);
    state = AsyncData(
      latest.copyWith(
        characters: latest.characters
            .where((character) => character.id != id)
            .toList(growable: false),
        voicePreferences: voicePreferences,
        invalidVoiceCharacterIds: latest.invalidVoiceCharacterIds
            .where((characterId) => characterId != id)
            .toSet(),
        voiceWarnings: _resolvedVoiceWarnings(
          latest.voiceWarnings,
          latest.invalidVoiceCharacterIds
              .where((characterId) => characterId != id)
              .toSet(),
        ),
      ),
    );
  }

  Future<void> saveVoice(String characterId, VoiceSelection selection) async {
    final current = state.requireValue;
    _find(current, characterId);
    final saved = await _dependencies.voices.save(characterId, selection);
    final latest = state.requireValue;
    if (!latest.characters.any((character) => character.id == characterId)) {
      try {
        await _dependencies.voices.delete(characterId);
      } on Object {
        // A later catalog prune retries cleanup.
      }
      throw StateError('Character was deleted while saving its voice');
    }
    final invalidVoiceCharacterIds = latest.invalidVoiceCharacterIds
        .where((id) => id != characterId)
        .toSet();
    state = AsyncData(
      latest.copyWith(
        voicePreferences: {...latest.voicePreferences, characterId: saved},
        invalidVoiceCharacterIds: invalidVoiceCharacterIds,
        voiceWarnings: _resolvedVoiceWarnings(
          latest.voiceWarnings,
          invalidVoiceCharacterIds,
        ),
      ),
    );
  }

  static Set<VoicePreferenceWarning> _resolvedVoiceWarnings(
    Set<VoicePreferenceWarning> current,
    Set<String> invalidCharacterIds,
  ) => {
    if (current.contains(VoicePreferenceWarning.invalidStore))
      VoicePreferenceWarning.invalidStore,
    if (invalidCharacterIds.isNotEmpty)
      ...current.where(
        (warning) => warning != VoicePreferenceWarning.invalidStore,
      ),
  };

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
