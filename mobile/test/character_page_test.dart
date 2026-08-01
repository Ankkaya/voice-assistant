import 'dart:io';

import 'package:child_voice_call/app.dart';
import 'package:child_voice_call/controllers/character_catalog_controller.dart';
import 'package:child_voice_call/models/character_options.dart';
import 'package:child_voice_call/repositories/bundled_character_repository.dart';
import 'package:child_voice_call/repositories/character_options_repository.dart';
import 'package:child_voice_call/repositories/custom_character_repository.dart';
import 'package:child_voice_call/services/character_asset_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testOptions = CharacterOptions(
  optionsVersion: 1,
  identities: [CharacterOption(id: 'adventure_companion', label: '探险伙伴')],
  traits: [CharacterOption(id: 'brave', label: '勇敢')],
  interests: [CharacterOption(id: 'space', label: '太空')],
  presetVoices: [PresetVoiceOption(id: '白桦', label: '白桦')],
);

class EmptyCustomRepository extends CustomCharacterRepository {
  EmptyCustomRepository()
    : super(
        root: Directory('/unused'),
        assets: FileCharacterAssetStore(root: Directory('/unused')),
      );

  @override
  Future<CharacterLoadResult> loadWithWarnings() async =>
      const CharacterLoadResult(characters: [], warnings: {});
}

class OfflineOptionsRepository extends CharacterOptionsRepository {
  OfflineOptionsRepository()
    : super(
        bundle: rootBundle,
        cacheFile: File('/unused/options.json'),
        client: MockClient((_) async => http.Response('', 500)),
        serverUri: Uri.parse('ws://localhost/ws/voice'),
      );

  @override
  Future<CharacterOptions> load() async => testOptions;

  @override
  Future<CharacterOptions> refresh() async =>
      throw http.ClientException('offline');
}

void main() {
  testWidgets('shows both configured characters', (tester) async {
    final dependencies = CharacterCatalogDependencies(
      bundled: BundledCharacterRepository(bundle: rootBundle),
      custom: EmptyCustomRepository(),
      options: OfflineOptionsRepository(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          characterCatalogDependenciesProvider.overrideWith(
            (ref) => dependencies,
          ),
        ],
        child: const VoiceCallApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('拉布拉多队长'), findsOneWidget);
    expect(find.text('莱德'), findsOneWidget);
  });
}
