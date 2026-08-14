import 'dart:async';
import 'dart:io';

import 'package:child_voice_call/controllers/character_catalog_controller.dart';
import 'package:child_voice_call/models/character.dart';
import 'package:child_voice_call/models/character_options.dart';
import 'package:child_voice_call/models/voice_selection.dart';
import 'package:child_voice_call/pages/call_page.dart';
import 'package:child_voice_call/pages/character_editor_page.dart';
import 'package:child_voice_call/pages/character_page.dart';
import 'package:child_voice_call/repositories/bundled_character_repository.dart';
import 'package:child_voice_call/repositories/character_options_repository.dart';
import 'package:child_voice_call/repositories/character_voice_preferences_repository.dart';
import 'package:child_voice_call/repositories/custom_character_repository.dart';
import 'package:child_voice_call/services/character_asset_store.dart';
import 'package:child_voice_call/services/app_update_service.dart';
import 'package:child_voice_call/services/voice_reference_uploader.dart';
import 'package:child_voice_call/widgets/character_card.dart';
import 'package:child_voice_call/widgets/voice_selector.dart';
import 'package:flutter/material.dart';
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

const starCaptain = Character(
  id: 'custom_20a8d1b51412447a99abc336e306f25f',
  name: '星星船长',
  subtitle: '',
  avatar: CharacterAvatarRef.bundled('star'),
  defaultVoiceDescription: '',
  defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
  themeColor: Color(0xff5b7cfa),
  source: CharacterSource.custom,
  profile: CustomCharacterProfile(
    identityId: 'adventure_companion',
    traitIds: ['brave'],
    interestIds: ['space'],
    description: '',
  ),
  greeting: '你好呀，我是星星船长！',
);

const legacyCloneCharacter = Character(
  id: 'custom_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  name: '旧角色',
  subtitle: '需要安全回退的伙伴',
  avatar: CharacterAvatarRef.bundled('star'),
  defaultVoiceDescription: '',
  defaultVoice: VoiceSelection(
    mode: VoiceMode.voiceClone,
    referencePath: '/definitely/missing/legacy.wav',
    referenceName: 'legacy.wav',
    cloneAuthorized: true,
  ),
  themeColor: Color(0xff5b7cfa),
  source: CharacterSource.custom,
  profile: CustomCharacterProfile(
    identityId: 'adventure_companion',
    traitIds: ['brave'],
    interestIds: ['space'],
    description: '',
  ),
  greeting: '你好呀！',
);

const bundledCharacters = [
  Character(
    id: 'labrador_captain',
    name: '拉布拉多队长',
    subtitle: '安全救援伙伴',
    avatar: CharacterAvatarRef.bundled('paw'),
    defaultVoiceDescription: '',
    defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
    themeColor: Color(0xfff97316),
  ),
  Character(
    id: 'ryder',
    name: '莱德',
    subtitle: '救援队长',
    avatar: CharacterAvatarRef.bundled('compass'),
    defaultVoiceDescription: '',
    defaultVoice: VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
    themeColor: Color(0xff14b8a6),
  ),
];

class FakeBundledRepository extends BundledCharacterRepository {
  FakeBundledRepository({
    this.characters = bundledCharacters,
    this.failFirstLoad = false,
    this.firstLoadCompleter,
  }) : super(bundle: rootBundle);

  final List<Character> characters;
  final bool failFirstLoad;
  final Completer<List<Character>>? firstLoadCompleter;
  int loadCount = 0;

  @override
  Future<List<Character>> load() async {
    loadCount += 1;
    if (loadCount == 1 && firstLoadCompleter != null) {
      return firstLoadCompleter!.future;
    }
    if (loadCount == 1 && failFirstLoad) {
      throw StateError('injected catalog failure');
    }
    return characters;
  }
}

class FakeCustomRepository extends CustomCharacterRepository {
  FakeCustomRepository({
    List<Character> characters = const [],
    this.warnings = const {},
  }) : characters = List<Character>.from(characters),
       super(
         root: Directory('/unused'),
         assets: FileCharacterAssetStore(root: Directory('/unused')),
       );

  final List<Character> characters;
  final Set<CharacterLoadWarning> warnings;

  @override
  Future<CharacterLoadResult> loadWithWarnings() async => CharacterLoadResult(
    characters: List<Character>.from(characters),
    warnings: warnings,
  );
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

class FakeVoicePreferencesRepository
    extends CharacterVoicePreferencesRepository {
  FakeVoicePreferencesRepository({this.preferences = const {}})
    : super(root: Directory('/unused'));

  final Map<String, VoiceSelection> preferences;
  final List<(String, VoiceSelection)> saved = [];

  @override
  Future<VoicePreferencesLoadResult> load() async => VoicePreferencesLoadResult(
    preferences: preferences,
    warnings: const {},
    invalidCharacterIds: const {},
  );

  @override
  Future<VoiceSelection> save(
    String characterId,
    VoiceSelection selection,
  ) async {
    saved.add((characterId, selection));
    return selection;
  }

  @override
  Future<void> prune(Set<String> validCharacterIds) async {}
}

class DelayedVoiceReferenceUploader extends VoiceReferenceUploader {
  DelayedVoiceReferenceUploader(this.result)
    : super(client: MockClient((_) async => http.Response('', 500)));

  final Completer<String> result;
  final Completer<void> started = Completer<void>();

  @override
  Future<String> upload(String path) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

GitHubRelease fakeRelease({String versionName = '0.1.0'}) {
  final tag = 'v$versionName';
  return GitHubRelease(
    tagName: tag,
    versionName: versionName,
    publishedAt: DateTime.utc(2026, 8, 4),
    releaseNotes: '- 增加版本更新\n- 修复通话问题',
    apkSizeBytes: 48 * 1024 * 1024,
    apkDownloadUrl: Uri.parse(
      'https://github.com/Ankkaya/voice-assistant/releases/download/'
      '$tag/child-voice-$tag.apk',
    ),
    releasePageUrl: Uri.parse(
      'https://github.com/Ankkaya/voice-assistant/releases/tag/$tag',
    ),
  );
}

AppUpdateResult fakeUpdateResult({String versionName = '0.1.0'}) =>
    AppUpdateResult(
      currentVersion: const AppVersion(versionName: '0.1.0', versionCode: 1),
      release: fakeRelease(versionName: versionName),
    );

class FakeAppUpdateService implements AppUpdateService {
  FakeAppUpdateService({
    AppUpdateResult? result,
    this.error,
    this.checkCompleter,
    this.launchResult = true,
  }) : result = result ?? fakeUpdateResult();

  final AppUpdateResult result;
  final Object? error;
  final Completer<AppUpdateResult>? checkCompleter;
  final bool launchResult;
  int checkCount = 0;
  int launchCount = 0;
  GitHubRelease? launchedRelease;

  @override
  Future<AppVersion> currentVersion() async => result.currentVersion;

  @override
  Future<AppUpdateResult> check() async {
    checkCount += 1;
    final injectedError = error;
    if (injectedError != null) throw injectedError;
    return checkCompleter?.future ?? result;
  }

  @override
  Future<bool> openDownload(GitHubRelease release) async {
    launchCount += 1;
    launchedRelease = release;
    return launchResult;
  }

  @override
  void close() {}
}

Widget _settingsPage(BuildContext context, Character character) =>
    Scaffold(body: Center(child: Text('角色页面:${character.id}')));

Future<ProviderContainer> pumpPage(
  WidgetTester tester, {
  FakeBundledRepository? bundled,
  FakeCustomRepository? custom,
  FakeVoicePreferencesRepository? voices,
  VoiceReferenceUploader? uploader,
  Future<bool> Function(String path)? referenceExists,
  bool waitForCatalog = true,
  double textScale = 1,
  Widget Function(BuildContext, Character)? characterSettingsBuilder,
  AppUpdateService? appUpdateService,
}) async {
  final dependencies = CharacterCatalogDependencies(
    bundled: bundled ?? FakeBundledRepository(),
    custom: custom ?? FakeCustomRepository(),
    options: OfflineOptionsRepository(),
    voices: voices ?? FakeVoicePreferencesRepository(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        characterCatalogDependenciesProvider.overrideWith(
          (ref) async => dependencies,
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: CharacterPage(
          characterSettingsBuilder: characterSettingsBuilder ?? _settingsPage,
          voiceReferenceUploader: uploader,
          referenceExists: referenceExists,
          appUpdateService: appUpdateService ?? FakeAppUpdateService(),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(CharacterPage)),
  );
  if (waitForCatalog) {
    await container.read(charactersProvider.future);
    await tester.pump(const Duration(milliseconds: 1));
  }
  return container;
}

void main() {
  testWidgets('shows the app version and checks once after startup', (
    tester,
  ) async {
    final updates = FakeAppUpdateService();
    final semantics = tester.ensureSemantics();

    await pumpPage(tester, appUpdateService: updates);
    await tester.pumpAndSettle();

    expect(updates.checkCount, 1);
    expect(find.text('版本 0.1.0 (1)'), findsOneWidget);
    expect(find.bySemanticsLabel('当前版本 0.1.0，点击检查更新'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('startup check shows a dialog only when an update exists', (
    tester,
  ) async {
    final updates = FakeAppUpdateService(
      result: fakeUpdateResult(versionName: '0.2.0'),
    );

    await pumpPage(tester, appUpdateService: updates);
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('版本 0.2.0'), findsOneWidget);
    expect(find.text('0.1.0 → 0.2.0'), findsOneWidget);
    expect(find.text('48.0 MB'), findsOneWidget);
    expect(find.text('立即更新'), findsOneWidget);
    expect(find.byKey(const Key('cancel_app_update')), findsNothing);
    expect(find.byKey(const Key('close_app_update')), findsOneWidget);
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).actions,
      hasLength(1),
    );
    expect(find.byKey(const Key('download_app_update')), findsOneWidget);
  });

  testWidgets('manual check reports that the app is up to date', (
    tester,
  ) async {
    final updates = FakeAppUpdateService();
    await pumpPage(tester, appUpdateService: updates);
    await tester.pumpAndSettle();

    final versionButton = find.byKey(const Key('app_version_button'));
    await tester.ensureVisible(versionButton);
    await tester.tap(versionButton);
    await tester.pumpAndSettle();

    expect(updates.checkCount, 2);
    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('automatic failures stay silent and manual failures are shown', (
    tester,
  ) async {
    final updates = FakeAppUpdateService(
      error: const AppUpdateException(AppUpdateFailure.rateLimited),
    );
    await pumpPage(tester, appUpdateService: updates);
    await tester.pumpAndSettle();

    expect(find.text('GitHub 请求频繁，请稍后重试'), findsNothing);

    final versionButton = find.byKey(const Key('app_version_button'));
    await tester.ensureVisible(versionButton);
    await tester.tap(versionButton);
    await tester.pumpAndSettle();

    expect(updates.checkCount, 2);
    expect(find.text('GitHub 请求频繁，请稍后重试'), findsOneWidget);
  });

  testWidgets('download action opens the release APK and closes the dialog', (
    tester,
  ) async {
    final updates = FakeAppUpdateService(
      result: fakeUpdateResult(versionName: '0.2.0'),
    );
    await pumpPage(tester, appUpdateService: updates);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('download_app_update')));
    await tester.pumpAndSettle();

    expect(updates.launchCount, 1);
    expect(updates.launchedRelease?.versionName, '0.2.0');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('startup check and repeated taps do not overlap', (tester) async {
    final blocker = Completer<AppUpdateResult>();
    final updates = FakeAppUpdateService(checkCompleter: blocker);
    await pumpPage(tester, appUpdateService: updates);
    await tester.pump();

    expect(updates.checkCount, 1);
    expect(find.text('正在检查更新…'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app_version_button')));
    await tester.pump();
    expect(updates.checkCount, 1);

    blocker.complete(fakeUpdateResult());
    await tester.pumpAndSettle();
    expect(find.text('版本 0.1.0 (1)'), findsOneWidget);
  });

  testWidgets('shows the child invitation contract for every character', (
    tester,
  ) async {
    await pumpPage(
      tester,
      custom: FakeCustomRepository(characters: const [starCaptain]),
    );

    expect(find.text('今天想邀请谁给你打电话？'), findsOneWidget);
    expect(find.text('选一位伙伴，稍后他会打给你'), findsOneWidget);
    expect(find.text('家长设置'), findsNothing);
    expect(find.text('邀请来电'), findsNWidgets(bundledCharacters.length + 1));
    expect(find.text('拉布拉多队长'), findsOneWidget);
    expect(find.text('莱德'), findsOneWidget);
    expect(find.text('星星船长'), findsOneWidget);
    expect(find.text('选择音色模式'), findsNothing);
    expect(find.text('新建角色'), findsOneWidget);
    expect(find.text('系统内置'), findsNWidgets(bundledCharacters.length));
    expect(find.text('我的角色'), findsOneWidget);
    expect(
      find.byKey(const Key('character_settings_labrador_captain')),
      findsOneWidget,
    );
    expect(find.byType(VoiceSelector), findsNothing);
  });

  testWidgets('the whole invitation card opens the incoming call page', (
    tester,
  ) async {
    await pumpPage(
      tester,
      voices: FakeVoicePreferencesRepository(
        preferences: const {
          'labrador_captain': VoiceSelection(
            mode: VoiceMode.preset,
            presetVoice: '苏打',
          ),
        },
      ),
    );

    await tester.tap(find.byKey(const Key('character_labrador_captain')));
    await tester.pump(const Duration(milliseconds: 100));

    final callPageFinder = find.byType(CallPage, skipOffstage: false);
    expect(callPageFinder, findsOneWidget);
    final callPage = tester.widget<CallPage>(callPageFinder);
    expect(callPage.character.id, 'labrador_captain');
    expect(callPage.voiceSelection.presetVoice, '苏打');
  });

  testWidgets('busy invitation card blocks repeated taps', (tester) async {
    var inviteCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CharacterCard(
            character: bundledCharacters.first,
            busy: true,
            onInvite: () => inviteCount += 1,
            onEdit: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('character_labrador_captain')));
    await tester.pump();

    expect(inviteCount, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('missing legacy clone falls back to an available preset', (
    tester,
  ) async {
    await pumpPage(
      tester,
      bundled: FakeBundledRepository(characters: const []),
      custom: FakeCustomRepository(characters: const [legacyCloneCharacter]),
      referenceExists: (_) async => false,
    );

    final invitation = find.byKey(
      const Key('character_custom_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
    );
    await tester.ensureVisible(invitation);
    await tester.pump();
    expect(invitation.hitTestable(), findsOneWidget);
    await tester.tap(invitation);
    final callPageFinder = find.byType(CallPage, skipOffstage: false);
    for (
      var attempt = 0;
      attempt < 10 && callPageFinder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final callPage = tester.widget<CallPage>(callPageFinder);
    expect(callPage.voiceSelection.mode, VoiceMode.preset);
    expect(callPage.voiceSelection.presetVoice, '白桦');
  });

  testWidgets('voice preparation disables character editing navigation', (
    tester,
  ) async {
    final upload = Completer<String>();
    final uploader = DelayedVoiceReferenceUploader(upload);
    await pumpPage(
      tester,
      uploader: uploader,
      referenceExists: (_) async => true,
      voices: FakeVoicePreferencesRepository(
        preferences: {
          'labrador_captain': VoiceSelection(
            mode: VoiceMode.voiceClone,
            referencePath: '/private/existing.wav',
            referenceName: 'voice.wav',
            cloneAuthorized: true,
          ),
        },
      ),
    );

    await tester.tap(find.byKey(const Key('character_labrador_captain')));
    await tester.pump();

    final settingsButton = tester.widget<IconButton>(
      find.byKey(const Key('character_settings_labrador_captain')),
    );
    expect(settingsButton.onPressed, isNull);

    expect(uploader.started.isCompleted, isTrue);
    upload.complete('reference-1');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CallPage, skipOffstage: false), findsOneWidget);
  });

  testWidgets('invitation cards expose a descriptive button semantic', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpPage(tester);

    expect(find.bySemanticsLabel('邀请拉布拉多队长给你打电话'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('gear button opens the injected character settings page', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(
      find.byKey(const Key('character_settings_labrador_captain')),
    );
    await tester.pumpAndSettle();

    expect(find.text('角色页面:labrador_captain'), findsOneWidget);
  });

  testWidgets('gear opens only the selected built-in character voice form', (
    tester,
  ) async {
    final voices = FakeVoicePreferencesRepository();
    await pumpPage(
      tester,
      voices: voices,
      characterSettingsBuilder: (_, character) =>
          CharacterEditorPage(character: character),
    );

    await tester.tap(find.byKey(const Key('character_settings_ryder')));
    await tester.pumpAndSettle();

    expect(find.byType(CharacterEditorPage), findsOneWidget);
    expect(find.text('莱德设置'), findsOneWidget);
    expect(find.text('系统角色'), findsOneWidget);
    expect(find.byType(VoiceSelector), findsOneWidget);
    expect(find.byKey(const Key('character_name')), findsNothing);
    expect(find.byKey(const Key('character_greeting')), findsNothing);

    await tester.tap(find.byKey(const Key('save_character')));
    await tester.pumpAndSettle();

    expect(voices.saved, hasLength(1));
    expect(voices.saved.single.$1, 'ryder');
  });

  testWidgets('storage warnings stay hidden from the child screen', (
    tester,
  ) async {
    await pumpPage(
      tester,
      custom: FakeCustomRepository(
        warnings: const {CharacterLoadWarning.invalidStore},
      ),
    );

    expect(find.text('部分本地角色数据无法读取'), findsNothing);
    expect(find.text('莱德'), findsOneWidget);
  });

  testWidgets('shows two stable placeholders while the catalog loads', (
    tester,
  ) async {
    final blocker = Completer<List<Character>>();
    await pumpPage(
      tester,
      bundled: FakeBundledRepository(firstLoadCompleter: blocker),
      waitForCatalog: false,
    );
    await tester.pump();

    expect(find.byKey(const Key('loading_character_placeholder_0')), findsOne);
    expect(find.byKey(const Key('loading_character_placeholder_1')), findsOne);

    blocker.complete(bundledCharacters);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('catalog error offers a working retry', (tester) async {
    final bundled = FakeBundledRepository(failFirstLoad: true);
    await pumpPage(tester, bundled: bundled, waitForCatalog: false);
    await tester.pumpAndSettle();

    expect(find.text('伙伴们暂时没有出现'), findsOneWidget);
    expect(find.byKey(const Key('retry_characters_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('retry_characters_button')));
    await tester.pumpAndSettle();

    expect(bundled.loadCount, 2);
    expect(find.text('拉布拉多队长'), findsOneWidget);
  });

  testWidgets('empty catalog opens the new character editor', (tester) async {
    await pumpPage(
      tester,
      bundled: FakeBundledRepository(characters: const []),
    );

    expect(find.text('还没有可以邀请的伙伴'), findsOneWidget);
    final addButton = find.byKey(const Key('empty_create_character_button'));
    expect(addButton, findsOneWidget);

    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(find.byType(CharacterEditorPage), findsOneWidget);
  });

  testWidgets('fits a 360 by 640 child screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 640);
    addTearDown(tester.view.reset);

    await pumpPage(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets('supports 1.3 text scaling without overflow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await pumpPage(tester, textScale: 1.3);

    expect(tester.takeException(), isNull);
    expect(find.text('今天想邀请谁给你打电话？'), findsOneWidget);
  });
}
