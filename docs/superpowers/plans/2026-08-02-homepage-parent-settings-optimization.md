# Homepage and Parent Settings Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the mixed child/adult homepage with a child-only invitation screen and a parent settings screen that persists independent voice settings for every built-in and custom character.

**Architecture:** Keep immutable character definitions separate from mutable voice preferences. A dedicated JSON repository owns `characterId → VoiceSelection` and cloned reference files; the catalog controller merges those preferences into runtime state. `CharacterPage` consumes the effective voice without exposing configuration, while `ParentSettingsPage` owns configuration and custom-character management.

**Tech Stack:** Flutter 3 / Dart 3.12, Material 3, Riverpod `AsyncNotifier`, `dart:io` JSON persistence, Flutter widget and unit tests.

## Global Constraints

- Target Flutter Android at 360 × 640, 390 × 844, and 412 × 915.
- Support 130% text scaling without clipping critical content.
- Child-facing copy must not expose “预置音色、音色设计、音色克隆”, provider names, protocols, status codes, or file errors.
- Use “今天想邀请谁给你打电话？” and “选一位伙伴，稍后他会打给你” on the child homepage.
- Use “邀请来电” for the child action; do not use “给角色打电话”.
- Ordinary touch targets must be at least 48 × 48 logical pixels.
- Built-in and custom characters must both support independent locally persisted voice settings.
- Voice clone files must be WAV or MP3, no larger than 10 MB, and stored under the app support directory.
- Do not add PIN, authentication, accounts, cloud sync, history, bottom navigation, or server protocol changes.
- Preserve the user's untracked `.superpowers/` directory and unrelated worktree changes.

---

## File Structure

- Create `mobile/lib/repositories/character_voice_preferences_repository.dart`: atomic JSON persistence and private clone-file ownership.
- Create `mobile/test/character_voice_preferences_repository_test.dart`: repository serialization, fallback, and cleanup tests.
- Modify `mobile/lib/controllers/character_catalog_controller.dart`: load and expose effective voice preferences.
- Modify `mobile/test/character_catalog_controller_test.dart`: controller preference behavior.
- Modify `mobile/lib/widgets/character_card.dart`: stateless child-facing invitation card.
- Modify `mobile/lib/pages/character_page.dart`: child-only homepage, navigation, states, and call preparation.
- Modify `mobile/test/character_page_test.dart`: homepage behavior and visual-contract tests.
- Create `mobile/lib/pages/parent_settings_page.dart`: all-character voice configuration and custom-character management.
- Create `mobile/test/parent_settings_page_test.dart`: settings interaction tests.
- Modify `mobile/lib/pages/character_editor_page.dart`: remove duplicate voice UI while retaining safe defaults.
- Modify `mobile/test/character_editor_page_test.dart`: editor contract updates.
- Modify `mobile/lib/app.dart`: shared theme details required by both screens.

---

### Task 1: Persist Voice Preferences for Every Character

**Files:**

- Create: `mobile/lib/repositories/character_voice_preferences_repository.dart`
- Create: `mobile/test/character_voice_preferences_repository_test.dart`

**Interfaces:**

- Consumes: `VoiceSelection`, `VoiceMode`, `maxVoiceReferenceBytes`.
- Produces: `VoicePreferencesLoadResult`, `VoicePreferenceWarning`, and `CharacterVoicePreferencesRepository.load/save/delete/prune`.
- `save` returns the normalized runtime selection, including an absolute private path for voice-clone mode.

- [ ] **Step 1: Write failing repository tests**

Cover preset and voice-design round trips, clone import and absolute-path restoration, replacement cleanup, deletion cleanup, pruning unknown character IDs, missing clone fallback warning, malformed-record isolation, and atomic writer failure. Use a temporary directory and a fake writer:

```dart
final class ThrowingVoicePreferencesWriter
    implements VoicePreferencesWriter {
  @override
  Future<void> write(File destination, Map<String, Object?> document) async {
    throw const FileSystemException('injected write failure');
  }
}

test('preset preferences round trip by character id', () async {
  final root = await Directory.systemTemp.createTemp('voice_preferences_');
  addTearDown(() => root.delete(recursive: true));
  final repository = CharacterVoicePreferencesRepository(root: root);

  await repository.save(
    'ryder',
    const VoiceSelection(mode: VoiceMode.preset, presetVoice: '苏打'),
  );
  final loaded = await repository.load();

  expect(loaded.preferences['ryder']?.presetVoice, '苏打');
  expect(loaded.warnings, isEmpty);
});
```

- [ ] **Step 2: Run the repository tests and verify they fail**

Run: `cd mobile && flutter test test/character_voice_preferences_repository_test.dart`

Expected: FAIL because the repository types do not exist.

- [ ] **Step 3: Implement the repository document and validation model**

Use a versioned document and isolate invalid entries rather than failing the whole file:

```dart
enum VoicePreferenceWarning { invalidStore, invalidRecord, missingReference }

class VoicePreferencesLoadResult {
  const VoicePreferencesLoadResult({
    required this.preferences,
    required this.warnings,
    required this.invalidCharacterIds,
  });

  final Map<String, VoiceSelection> preferences;
  final Set<VoicePreferenceWarning> warnings;
  final Set<String> invalidCharacterIds;
}

abstract interface class VoicePreferencesWriter {
  Future<void> write(File destination, Map<String, Object?> document);
}

class CharacterVoicePreferencesRepository {
  CharacterVoicePreferencesRepository({
    required this.root,
    this.writer = const FileVoicePreferencesWriter(),
  });

  final Directory root;
  final VoicePreferencesWriter writer;

  File get storeFile => File('${root.path}/character_voice_preferences.json');
  Directory get referencesDirectory =>
      Directory('${root.path}/voice_preferences');

  Future<VoicePreferencesLoadResult> load();
  Future<VoiceSelection> save(String characterId, VoiceSelection selection);
  Future<void> delete(String characterId);
  Future<void> prune(Set<String> validCharacterIds);
}
```

Store this exact top-level shape:

```json
{
  "schemaVersion": 1,
  "preferences": {
    "ryder": {"mode": "preset", "voice": "苏打"}
  }
}
```

Validate character IDs with `^[a-zA-Z0-9_]+$`. Reuse `VoiceSelection.toStorageJson` and `VoiceSelection.fromStorageJson`. For clone records, convert between `voice_preferences/<filename>` in JSON and an absolute runtime path under `root`.

- [ ] **Step 4: Implement atomic clone import, replacement, and delete cleanup**

Validate extension, size, and WAV/MP3 magic bytes before copying. Write to `voice_preferences/<characterId>_<timestamp>.<ext>` through a temporary file and rename. Commit the JSON before deleting the old clone; on JSON failure, delete only the newly imported file and preserve the old document and file.

`delete(characterId)` must write the updated JSON first, then delete the removed clone file. `prune(validCharacterIds)` must remove records and clone files for IDs not present in the catalog. `load()` must skip clone records whose referenced file no longer exists and return both `missingReference` and the affected ID.

- [ ] **Step 5: Run repository tests and static analysis**

Run:

```bash
cd mobile
dart format lib/repositories/character_voice_preferences_repository.dart test/character_voice_preferences_repository_test.dart
flutter test test/character_voice_preferences_repository_test.dart
flutter analyze
```

Expected: all repository tests pass and analysis reports no issues.

- [ ] **Step 6: Commit the repository task**

```bash
git add mobile/lib/repositories/character_voice_preferences_repository.dart mobile/test/character_voice_preferences_repository_test.dart
git commit -m "feat: persist per-character voice preferences"
```

---

### Task 2: Integrate Effective Voices into the Character Catalog

**Files:**

- Modify: `mobile/lib/controllers/character_catalog_controller.dart`
- Modify: `mobile/test/character_catalog_controller_test.dart`

**Interfaces:**

- Consumes: `CharacterVoicePreferencesRepository` from Task 1.
- Produces: `CharacterCatalogState.voicePreferences`, `voiceWarnings`, `invalidVoiceCharacterIds`, and `voiceFor(Character)`; controller methods `saveVoice` and enhanced `delete`.

- [ ] **Step 1: Extend test dependency fakes and write failing controller tests**

Add an in-memory fake implementing the concrete repository through overridable methods, then verify:

```dart
test('voiceFor returns saved preference and otherwise character default', () async {
  final state = await container.read(charactersProvider.future);
  expect(state.voiceFor(ryder).voiceDescription, '温暖明亮的少年队长声音');
  expect(state.voiceFor(starCaptain).presetVoice, '白桦');
});

test('saveVoice persists before publishing updated state', () async {
  await container.read(charactersProvider.future);
  await container.read(charactersProvider.notifier).saveVoice(
    'ryder',
    const VoiceSelection(mode: VoiceMode.preset, presetVoice: '白桦'),
  );
  expect(
    container.read(charactersProvider).requireValue.voiceFor(ryder).presetVoice,
    '白桦',
  );
});
```

Also test repository save failure leaves state unchanged and custom-character deletion invokes preference cleanup.

- [ ] **Step 2: Run controller tests and verify they fail**

Run: `cd mobile && flutter test test/character_catalog_controller_test.dart`

Expected: FAIL because the dependency and state fields do not exist.

- [ ] **Step 3: Add voice repository dependency and catalog state fields**

Extend the dependency constructor and state:

```dart
class CharacterCatalogDependencies {
  const CharacterCatalogDependencies({
    required this.bundled,
    required this.custom,
    required this.options,
    required this.voices,
  });
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

  VoiceSelection voiceFor(Character character) =>
      voicePreferences[character.id] ?? character.defaultVoice;
}
```

Construct the repository with the same application-support root, load it during `build`, filter preferences to IDs present in the merged character list, and call `unawaited(_dependencies.voices.prune(validIds))` after state inputs have loaded. The prune method handles its own filesystem errors so background cleanup cannot turn a usable catalog into an error state.

- [ ] **Step 4: Implement save and delete coordination**

```dart
Future<void> saveVoice(String characterId, VoiceSelection selection) async {
  final current = state.requireValue;
  _find(current, characterId);
  final saved = await _dependencies.voices.save(characterId, selection);
  final latest = state.requireValue;
  state = AsyncData(latest.copyWith(
    voicePreferences: {...latest.voicePreferences, characterId: saved},
    invalidVoiceCharacterIds: {
      ...latest.invalidVoiceCharacterIds.where((id) => id != characterId),
    },
  ));
}
```

After successful custom-character deletion, remove the entry from state and call preference deletion. Preference cleanup is best-effort after the character record is durably removed; call `prune` during the next catalog build so an interrupted cleanup cannot leave a permanent stale record or clone file.

- [ ] **Step 5: Update every test dependency construction**

Search with `rg "CharacterCatalogDependencies\(" mobile` and supply a fake voice repository in every test fixture. Do not weaken existing assertions for bundled/custom ordering, option refresh, or delete restrictions.

- [ ] **Step 6: Run focused and full controller tests**

Run:

```bash
cd mobile
dart format lib/controllers/character_catalog_controller.dart test/character_catalog_controller_test.dart
flutter test test/character_catalog_controller_test.dart
flutter test test/custom_character_repository_test.dart test/character_options_repository_test.dart
```

Expected: all tests pass.

- [ ] **Step 7: Commit the catalog integration**

```bash
git add mobile/lib/controllers/character_catalog_controller.dart mobile/test/character_catalog_controller_test.dart mobile/test/character_page_test.dart
git commit -m "feat: expose effective character voices"
```

---

### Task 3: Replace the Homepage with the Child Invitation Experience

**Files:**

- Modify: `mobile/lib/widgets/character_card.dart`
- Modify: `mobile/lib/pages/character_page.dart`
- Modify: `mobile/test/character_page_test.dart`

**Interfaces:**

- Consumes: `CharacterCatalogState.voiceFor` and `CallPage`.
- Produces: `CharacterCard(character, busy, onInvite)`, child-only homepage states, and an injectable `Widget Function(BuildContext, String?)? parentSettingsBuilder` navigation seam that Task 4 wires to the real page.

- [ ] **Step 1: Rewrite homepage widget tests to express the child contract**

Replace tests for inline voice selection and the trailing new-character card with assertions that:

```dart
expect(find.text('今天想邀请谁给你打电话？'), findsOneWidget);
expect(find.text('选一位伙伴，稍后他会打给你'), findsOneWidget);
expect(find.text('家长设置'), findsOneWidget);
expect(find.text('邀请来电'), findsNWidgets(bundledCharacters.length));
expect(find.text('选择音色模式'), findsNothing);
expect(find.text('新建角色'), findsNothing);
expect(find.byType(VoiceSelector), findsNothing);
```

Add tests for entire-card tapping, a busy card that blocks a second tap, error retry via `ref.invalidate(charactersProvider)`, empty-state navigation through an injected fake settings builder, hidden storage warning, 360 × 640 layout, and 1.3 text scaling with `tester.takeException()` returning null.

- [ ] **Step 2: Run homepage tests and verify they fail**

Run: `cd mobile && flutter test test/character_page_test.dart`

Expected: FAIL against the existing mixed homepage.

- [ ] **Step 3: Refactor `CharacterCard` into a stateless invitation card**

Use this public contract:

```dart
class CharacterCard extends StatelessWidget {
  const CharacterCard({
    required this.character,
    required this.onInvite,
    this.busy = false,
    super.key,
  });

  final Character character;
  final VoidCallback? onInvite;
  final bool busy;
}
```

Wrap the card in `Semantics(button: true, label: '邀请${character.name}给你打电话')` and `InkWell`. Use a 92px circular avatar, `maxLines: 1` with ellipsis for the name, `maxLines: 2` for the subtitle, and a visible “邀请来电” label with an arrow or progress indicator. Keep at least 48px interactive height and a 24px radius.

- [ ] **Step 4: Rebuild `CharacterPage` as a scrolling child-only page**

Add `Widget Function(BuildContext, String?)? parentSettingsBuilder` to `CharacterPage`; the header button and empty-state action call it with `null`, while a call-page edit result passes the affected character ID. Use `ListView` or `CustomScrollView` so the header scrolls on short screens. Track only `_busyCharacterId`. The call path resolves the voice immediately before navigation:

```dart
final catalog = ref.read(charactersProvider).requireValue;
var selection = catalog.voiceFor(character);
if (selection.mode == VoiceMode.voiceClone) {
  final path = selection.referencePath;
  if (path == null || !await File(path).exists()) {
    selection = character.defaultVoice;
  } else {
    selection = selection.withReferenceId(await _uploader.upload(path));
  }
}
```

Do not show clone-file dialogs or technical Snackbars to the child. On preparation failure, show “现在还邀请不了，请稍后再试”。 Keep the existing `CallPageResult.editCharacter` path by routing it to parent settings with the affected character selected.

- [ ] **Step 5: Add loading, failure, and empty states**

- Loading: two static card-shaped placeholders matching final geometry.
- Failure: icon, “伙伴们暂时没有出现”, secondary sentence, and a keyed `重新加载` button.
- Empty: “还没有可以邀请的伙伴” and a keyed `请家长添加角色` button that opens parent settings.
- Storage warnings: omit from the child screen entirely.

- [ ] **Step 6: Run homepage tests and accessibility-sensitive layouts**

Run:

```bash
cd mobile
dart format lib/widgets/character_card.dart lib/pages/character_page.dart test/character_page_test.dart
flutter test test/character_page_test.dart
flutter test test/character_avatar_image_test.dart
```

Expected: tests pass without overflow exceptions.

- [ ] **Step 7: Commit the child homepage**

```bash
git add mobile/lib/widgets/character_card.dart mobile/lib/pages/character_page.dart mobile/test/character_page_test.dart
git commit -m "feat: simplify child character homepage"
```

---

### Task 4: Add Parent Settings for All Characters

**Files:**

- Create: `mobile/lib/pages/parent_settings_page.dart`
- Create: `mobile/test/parent_settings_page_test.dart`
- Modify: `mobile/lib/pages/character_page.dart`
- Modify: `mobile/lib/app.dart`

**Interfaces:**

- Consumes: `charactersProvider`, `VoiceSelector`, `CharacterEditorPage`, catalog `saveVoice/delete` methods, and the `CharacterPage.parentSettingsBuilder` seam from Task 3.
- Produces: `ParentSettingsPage(initialCharacterId)` and returns normally to the child homepage.

- [ ] **Step 1: Write failing parent-settings widget tests**

Test these exact behaviors:

- Every built-in and custom character is available in the role selector.
- Initial character ID selects the requested role; missing ID falls back to the first role.
- Switching characters rebuilds `VoiceSelector` with `catalog.voiceFor(character)`.
- Invalid voice design does not save.
- Valid preset, design, and clone modes call `saveVoice` and show “音色设置已保存”.
- A missing saved clone reference shows “参考音频需要重新选择”.
- “新建角色” is always present.
- “编辑角色” and “删除角色” appear only for custom characters.
- Catalog storage warnings appear here and never on the child homepage.
- Delete confirmation contains the selected character name.

- [ ] **Step 2: Run settings tests and verify they fail**

Run: `cd mobile && flutter test test/parent_settings_page_test.dart`

Expected: FAIL because `ParentSettingsPage` does not exist.

- [ ] **Step 3: Implement selection and form lifecycle**

Use this public API:

```dart
class ParentSettingsPage extends ConsumerStatefulWidget {
  const ParentSettingsPage({this.initialCharacterId, super.key});
  final String? initialCharacterId;
}
```

Maintain `_selectedCharacterId`, a replaceable `GlobalKey<VoiceSelectorState>`, and `_saving`. On character switch, replace the key so the form receives the new effective initial value. Use a horizontally scrolling set of character chips/cards with avatars and names rather than a narrow dropdown, while preserving text ellipsis.

- [ ] **Step 4: Implement voice summary, editor, and save feedback**

Map modes to summaries:

```dart
String voiceSummary(VoiceSelection voice) => switch (voice.mode) {
  VoiceMode.preset => '预置音色 · ${voice.presetVoice}',
  VoiceMode.voiceDesign => '音色设计 · ${voice.voiceDescription}',
  VoiceMode.voiceClone => '音色克隆 · ${voice.referenceName ?? '参考音频'}',
};
```

Place `VoiceSelector` inside a 24px-radius white section card. `_save` must validate first, await `saveVoice`, then show a success SnackBar. On failure, leave the selector mounted and show “音色设置保存失败，请重试”. Disable switching and saving only while the write is active.

- [ ] **Step 5: Implement role management and warning placement**

Add “新建角色” after the voice section. For custom roles, show “编辑角色” and destructive “删除角色”. Reuse the existing confirmation copy. After create, select the returned character; after edit, keep the same selection; after delete, select the first remaining character. Display catalog warnings as an adult-facing yellow banner with “部分本地角色数据无法读取”.

- [ ] **Step 6: Wire child navigation and call-page edit requests**

In `VoiceCallApp`, construct `CharacterPage(parentSettingsBuilder: (_, initialCharacterId) => ParentSettingsPage(initialCharacterId: initialCharacterId))`. The homepage button and empty state pass `null`; `CallPageResult.editCharacter` passes `character.id`. Tests inject this same signature, so there is one navigation API.

- [ ] **Step 7: Run settings and navigation tests**

Run:

```bash
cd mobile
dart format lib/pages/parent_settings_page.dart lib/pages/character_page.dart test/parent_settings_page_test.dart test/character_page_test.dart
flutter test test/parent_settings_page_test.dart test/character_page_test.dart
```

Expected: all settings and homepage navigation tests pass.

- [ ] **Step 8: Commit parent settings**

```bash
git add mobile/lib/pages/parent_settings_page.dart mobile/lib/pages/character_page.dart mobile/lib/app.dart mobile/test/parent_settings_page_test.dart mobile/test/character_page_test.dart
git commit -m "feat: add parent voice settings"
```

---

### Task 5: Remove Duplicate Voice Editing from the Character Editor

**Files:**

- Modify: `mobile/lib/pages/character_editor_page.dart`
- Modify: `mobile/test/character_editor_page_test.dart`

**Interfaces:**

- Consumes: `CharacterOptions.presetVoices` for a safe default when creating.
- Produces: character-profile-only editor; existing custom characters preserve their stored base default voice.

- [ ] **Step 1: Rewrite editor tests for the new ownership boundary**

Assert that `VoiceSelector` and “默认音色” are absent. For creation, assert the resulting draft uses the first available preset voice. For editing, assert the existing character's `defaultVoice` is preserved unchanged. Retain all current tests for name, profile, greeting, avatar, save errors, and validation.

```dart
expect(find.text('默认音色'), findsNothing);
expect(find.byType(VoiceSelector), findsNothing);
expect(drafts.single.defaultVoice.mode, VoiceMode.preset);
expect(drafts.single.defaultVoice.presetVoice, '白桦');
```

- [ ] **Step 2: Run editor tests and verify the ownership tests fail**

Run: `cd mobile && flutter test test/character_editor_page_test.dart`

Expected: FAIL because the current editor renders `VoiceSelector`.

- [ ] **Step 3: Remove selector state and preserve a safe base voice**

Remove `_voiceKey`, `_voice`, picker usage in the widget UI, and voice validation. When creating, resolve:

```dart
final defaultVoice = widget.character?.defaultVoice ??
    VoiceSelection(
      mode: VoiceMode.preset,
      presetVoice: options.presetVoices.first.id,
    );
```

Pass `defaultVoice` into `CustomCharacterDraft`. If `presetVoices` is empty, show the existing options failure state with a parent-facing explanation instead of indexing an empty list. Remove the now-unused `voiceReferencePicker` constructor parameter and update all call sites and tests.

- [ ] **Step 4: Run editor and custom repository regressions**

Run:

```bash
cd mobile
dart format lib/pages/character_editor_page.dart test/character_editor_page_test.dart
flutter test test/character_editor_page_test.dart test/custom_character_repository_test.dart test/custom_character_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit the editor boundary change**

```bash
git add mobile/lib/pages/character_editor_page.dart mobile/test/character_editor_page_test.dart
git commit -m "refactor: move voice editing to parent settings"
```

---

### Task 6: Apply Shared Visual Polish and Complete Regression Verification

**Files:**

- Modify: `mobile/lib/app.dart`

**Interfaces:**

- Consumes: all pages and widgets from previous tasks.
- Produces: consistent Material 3 theme and a fully verified optimization.

- [ ] **Step 1: Add focused shared theme values**

Keep the existing seed and background. Add a Chinese-friendly typography hierarchy, card shape, input decoration, and minimum button geometry without overriding character theme colors:

```dart
final scheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF4E72E6),
  brightness: Brightness.light,
);

theme: ThemeData(
  colorScheme: scheme,
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFFF6F7FB),
  cardTheme: const CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
  ),
);
```

Use `CardThemeData`, which is the `ThemeData.cardTheme` value type in the installed Flutter 3.44.8 SDK.

- [ ] **Step 2: Run formatter, analyzer, and the complete Flutter test suite**

Run:

```bash
cd mobile
dart format lib test
flutter analyze
flutter test
```

Expected: formatter is clean, analyzer reports no issues, and every Flutter test passes.

- [ ] **Step 3: Run server regressions because call payload behavior is shared**

Run:

```bash
cd server
python -m pytest -q
```

Expected: all server tests pass; no protocol changes should be observed.

- [ ] **Step 4: Inspect the final diff and verify scope**

Run:

```bash
git status --short
git diff --check
git diff --stat HEAD~5..HEAD
```

Confirm only homepage, parent settings, voice preference persistence, editor ownership, theme, tests, and their approved docs changed. Confirm `.superpowers/` remains untouched and uncommitted.

- [ ] **Step 5: Commit final polish if Task 6 changed files**

```bash
git add mobile/lib/app.dart
git commit -m "style: polish child and parent surfaces"
```

- [ ] **Step 6: Report delivery evidence**

Report the child/adult separation, voice persistence behavior, failure fallbacks, exact test commands and results, commit hashes, and any residual limitation. Link the implementation files and the approved design/plan.
