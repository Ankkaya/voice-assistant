import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/character_catalog_controller.dart';
import '../models/character.dart';
import '../models/voice_selection.dart';
import '../services/voice_reference_uploader.dart';
import '../widgets/character_card.dart';
import 'call_page.dart';
import 'character_editor_page.dart';

class CharacterPage extends ConsumerStatefulWidget {
  const CharacterPage({
    this.characterSettingsBuilder,
    this.voiceReferenceUploader,
    this.referenceExists,
    super.key,
  });

  final Widget Function(BuildContext, String)? characterSettingsBuilder;
  final VoiceReferenceUploader? voiceReferenceUploader;
  final Future<bool> Function(String path)? referenceExists;

  @override
  ConsumerState<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends ConsumerState<CharacterPage> {
  late final VoiceReferenceUploader _uploader;
  late final bool _ownsUploader;
  String? _busyCharacterId;

  @override
  void initState() {
    super.initState();
    _ownsUploader = widget.voiceReferenceUploader == null;
    _uploader = widget.voiceReferenceUploader ?? VoiceReferenceUploader();
  }

  @override
  void dispose() {
    if (_ownsUploader) _uploader.close();
    super.dispose();
  }

  Future<void> _openCharacterSettings(String characterId) async {
    final settingsBuilder = widget.characterSettingsBuilder;
    if (settingsBuilder == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => settingsBuilder(routeContext, characterId),
      ),
    );
  }

  Future<void> _openNewCharacter() async {
    if (_busyCharacterId != null) return;
    await Navigator.of(context).push<Character>(
      MaterialPageRoute<Character>(builder: (_) => const CharacterEditorPage()),
    );
  }

  Future<void> _startCall(Character character) async {
    if (_busyCharacterId != null) return;
    setState(() => _busyCharacterId = character.id);
    try {
      final catalog = ref.read(charactersProvider).requireValue;
      var selection = catalog.voiceFor(character);
      if (selection.mode == VoiceMode.voiceClone) {
        final path = selection.referencePath;
        final exists =
            path != null &&
            await (widget.referenceExists?.call(path) ?? File(path).exists());
        if (!exists) {
          selection = _safePresetVoice(catalog, character);
        } else {
          selection = selection.withReferenceId(await _uploader.upload(path));
        }
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final result = await Navigator.of(context).push<CallPageResult>(
        MaterialPageRoute<CallPageResult>(
          builder: (_) =>
              CallPage(character: character, voiceSelection: selection),
        ),
      );
      if (result == CallPageResult.editCharacter && mounted) {
        await _openCharacterSettings(character.id);
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('现在还邀请不了，请稍后再试')));
    } finally {
      if (mounted) setState(() => _busyCharacterId = null);
    }
  }

  VoiceSelection _safePresetVoice(
    CharacterCatalogState catalog,
    Character character,
  ) {
    final defaultVoice = character.defaultVoice;
    if (defaultVoice.mode == VoiceMode.preset &&
        (defaultVoice.presetVoice ?? '').isNotEmpty) {
      return defaultVoice;
    }
    if (catalog.options.presetVoices.isEmpty) {
      throw StateError('No preset voice is available for safe fallback');
    }
    return VoiceSelection(
      mode: VoiceMode.preset,
      presetVoice: catalog.options.presetVoices.first.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(charactersProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            Text(
              '今天想邀请谁给你打电话？',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: const Color(0xFF252A3A),
                fontSize: 28,
                height: 1.22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '选一位伙伴，稍后他会打给你',
              style: TextStyle(
                color: Color(0xFF606575),
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            characters.when(
              data: (catalog) {
                if (catalog.characters.isEmpty) {
                  return _EmptyCharacters(onCreateCharacter: _openNewCharacter);
                }
                return Column(
                  children: [
                    for (
                      var index = 0;
                      index < catalog.characters.length;
                      index++
                    ) ...[
                      if (index > 0) const SizedBox(height: 16),
                      CharacterCard(
                        character: catalog.characters[index],
                        busy: _busyCharacterId == catalog.characters[index].id,
                        onInvite: _busyCharacterId == null
                            ? () => _startCall(catalog.characters[index])
                            : null,
                        onEdit: _busyCharacterId == null
                            ? () => _openCharacterSettings(
                                catalog.characters[index].id,
                              )
                            : null,
                      ),
                    ],
                    const SizedBox(height: 18),
                    _CreateCharacterCard(onPressed: _openNewCharacter),
                  ],
                );
              },
              loading: () => const Column(
                children: [
                  _LoadingCharacterCard(index: 0),
                  SizedBox(height: 16),
                  _LoadingCharacterCard(index: 1),
                ],
              ),
              error: (_, __) => _CatalogFailure(
                onRetry: () => ref.invalidate(charactersProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCharacterCard extends StatelessWidget {
  const _LoadingCharacterCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    const placeholder = Color(0xFFE8EAF1);
    return Card(
      key: Key('loading_character_placeholder_$index'),
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE7E9F0)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: placeholder,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(dimension: 92),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PlaceholderLine(widthFactor: 0.58, height: 20),
                  SizedBox(height: 10),
                  _PlaceholderLine(widthFactor: 0.88, height: 14),
                  SizedBox(height: 15),
                  _PlaceholderLine(widthFactor: 0.50, height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderLine extends StatelessWidget {
  const _PlaceholderLine({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: Alignment.centerLeft,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE8EAF1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(height: height),
    ),
  );
}

class _CatalogFailure extends StatelessWidget {
  const _CatalogFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _CatalogMessage(
    icon: Icons.cloud_off_rounded,
    title: '伙伴们暂时没有出现',
    message: '休息一下，再请他们出来吧',
    action: FilledButton.icon(
      key: const Key('retry_characters_button'),
      onPressed: onRetry,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('重新加载'),
    ),
  );
}

class _EmptyCharacters extends StatelessWidget {
  const _EmptyCharacters({required this.onCreateCharacter});

  final VoidCallback onCreateCharacter;

  @override
  Widget build(BuildContext context) => _CatalogMessage(
    icon: Icons.sentiment_satisfied_alt_rounded,
    title: '还没有可以邀请的伙伴',
    message: '请家长先添加一位伙伴',
    action: FilledButton.icon(
      key: const Key('empty_create_character_button'),
      onPressed: onCreateCharacter,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      icon: const Icon(Icons.add_rounded),
      label: const Text('新建角色'),
    ),
  );
}

class _CreateCharacterCard extends StatelessWidget {
  const _CreateCharacterCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xFFD8DAE2)),
    ),
    child: InkWell(
      key: const Key('create_character_card'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(24),
      child: const SizedBox(
        height: 96,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline_rounded, color: Color(0xFF4E72E6)),
            SizedBox(height: 8),
            Text(
              '新建角色',
              style: TextStyle(
                color: Color(0xFF4E72E6),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 54, color: const Color(0xFF7A849E)),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF252A3A),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF606575), fontSize: 15),
        ),
        const SizedBox(height: 20),
        action,
      ],
    ),
  );
}
