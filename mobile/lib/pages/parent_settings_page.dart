import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/character_catalog_controller.dart';
import '../models/character.dart';
import '../models/voice_selection.dart';
import '../widgets/character_avatar_image.dart';
import '../widgets/voice_selector.dart';
import 'character_editor_page.dart';

class ParentSettingsPage extends ConsumerStatefulWidget {
  const ParentSettingsPage({this.initialCharacterId, super.key});

  final String? initialCharacterId;

  @override
  ConsumerState<ParentSettingsPage> createState() => _ParentSettingsPageState();
}

class _ParentSettingsPageState extends ConsumerState<ParentSettingsPage> {
  String? _selectedCharacterId;
  String? _voiceKeyCharacterId;
  GlobalKey<VoiceSelectorState> _voiceKey = GlobalKey<VoiceSelectorState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedCharacterId = widget.initialCharacterId;
  }

  Character? _selectedCharacter(List<Character> characters) {
    if (characters.isEmpty) return null;
    final requestedId = _selectedCharacterId;
    for (final character in characters) {
      if (character.id == requestedId) return character;
    }
    _selectedCharacterId = characters.first.id;
    return characters.first;
  }

  void _selectCharacter(String id) {
    if (_saving || id == _selectedCharacterId) return;
    setState(() {
      _selectedCharacterId = id;
      _voiceKeyCharacterId = null;
      _voiceKey = GlobalKey<VoiceSelectorState>();
    });
  }

  void _ensureVoiceKey(String characterId) {
    if (_voiceKeyCharacterId == characterId) return;
    _voiceKeyCharacterId = characterId;
    _voiceKey = GlobalKey<VoiceSelectorState>();
  }

  Future<void> _saveVoice(Character character) async {
    final selector = _voiceKey.currentState;
    if (selector == null || !selector.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(charactersProvider.notifier)
          .saveVoice(character.id, selector.value);
      if (!mounted) return;
      setState(() {
        _voiceKeyCharacterId = null;
        _voiceKey = GlobalKey<VoiceSelectorState>();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('音色设置已保存')));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('音色设置保存失败，请重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openEditor([Character? character]) async {
    final saved = await Navigator.of(context).push<Character>(
      MaterialPageRoute<Character>(
        builder: (_) => CharacterEditorPage(character: character),
      ),
    );
    if (saved == null || !mounted) return;
    setState(() {
      _selectedCharacterId = saved.id;
      _voiceKeyCharacterId = null;
      _voiceKey = GlobalKey<VoiceSelectorState>();
    });
  }

  Future<void> _confirmDelete(
    Character character,
    List<Character> characters,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${character.name}”？'),
        content: const Text('角色和保存在本机的头像、参考音频将一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm_delete_character'),
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(charactersProvider.notifier).delete(character.id);
      if (!mounted) return;
      final remaining = characters
          .where((item) => item.id != character.id)
          .toList(growable: false);
      setState(() {
        _selectedCharacterId = remaining.isEmpty ? null : remaining.first.id;
        _voiceKeyCharacterId = null;
        _voiceKey = GlobalKey<VoiceSelectorState>();
      });
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('角色删除失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(charactersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('家长设置')),
      body: SafeArea(
        child: catalog.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _SettingsFailure(
            onRetry: () => ref.invalidate(charactersProvider),
          ),
          data: (state) => _buildContent(state),
        ),
      ),
    );
  }

  Widget _buildContent(CharacterCatalogState catalog) {
    final selected = _selectedCharacter(catalog.characters);
    if (selected != null) _ensureVoiceKey(selected.id);
    final hasCatalogWarning =
        catalog.warnings.isNotEmpty || catalog.voiceWarnings.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (hasCatalogWarning) ...[
          const _SettingsWarning(text: '部分本地角色数据无法读取'),
          const SizedBox(height: 20),
        ],
        Text(
          '选择角色',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        if (catalog.characters.isEmpty)
          const _NoCharacters()
        else
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: catalog.characters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final character = catalog.characters[index];
                return ChoiceChip(
                  key: Key('settings_character_${character.id}'),
                  selected: character.id == selected?.id,
                  onSelected: _saving
                      ? null
                      : (_) => _selectCharacter(character.id),
                  avatar: ClipOval(
                    child: SizedBox.square(
                      dimension: 28,
                      child: CharacterAvatarImage(
                        avatar: character.avatar,
                        fallbackColor: character.themeColor,
                      ),
                    ),
                  ),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 132),
                    child: Text(
                      character.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 24),
        if (selected != null) ...[
          _voiceSettings(catalog, selected),
          const SizedBox(height: 24),
        ],
        _characterManagement(catalog, selected),
      ],
    );
  }

  Widget _voiceSettings(CharacterCatalogState catalog, Character character) {
    final voice = catalog.voiceFor(character);
    final referenceMissing = catalog.invalidVoiceCharacterIds.contains(
      character.id,
    );
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFD8DAE2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  key: const Key('current_character_avatar'),
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: character.themeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: CharacterAvatarImage(
                      avatar: character.avatar,
                      fallbackColor: character.themeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${character.name}的音色',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _voiceSummary(voice),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF777C8D)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (referenceMissing) ...[
              const SizedBox(height: 16),
              const _SettingsWarning(text: '参考音频需要重新选择'),
            ],
            const SizedBox(height: 20),
            VoiceSelector(
              key: _voiceKey,
              keyPrefix: 'settings_${character.id}',
              options: catalog.options.presetVoices,
              initialValue: voice,
              enabled: !_saving,
              onChanged: (_) {},
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('save_voice_settings'),
              onPressed: _saving ? null : () => _saveVoice(character),
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? '正在保存…' : '保存音色设置'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _characterManagement(
    CharacterCatalogState catalog,
    Character? selected,
  ) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFD8DAE2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '角色管理',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('create_character'),
              onPressed: _saving ? null : _openEditor,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('新建角色'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            if (selected?.isCustom == true) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('edit_character'),
                onPressed: _saving ? null : () => _openEditor(selected),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('编辑角色'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('delete_character'),
                onPressed: _saving
                    ? null
                    : () => _confirmDelete(selected!, catalog.characters),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('删除角色'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _voiceSummary(VoiceSelection voice) => switch (voice.mode) {
    VoiceMode.preset => '预置音色 · ${voice.presetVoice}',
    VoiceMode.voiceDesign => '音色设计 · ${voice.voiceDescription}',
    VoiceMode.voiceClone => '音色克隆 · ${voice.referenceName ?? '参考音频'}',
  };
}

class _SettingsWarning extends StatelessWidget {
  const _SettingsWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFF4D6),
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

class _NoCharacters extends StatelessWidget {
  const _NoCharacters();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 20),
    child: Text('还没有角色，请先新建一个角色。'),
  );
}

class _SettingsFailure extends StatelessWidget {
  const _SettingsFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.settings_backup_restore_rounded, size: 48),
          const SizedBox(height: 12),
          const Text('设置暂时无法加载'),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    ),
  );
}
