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
  const CharacterPage({super.key});

  @override
  ConsumerState<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends ConsumerState<CharacterPage> {
  late final VoiceReferenceUploader _uploader;
  bool _warningDismissed = false;

  @override
  void initState() {
    super.initState();
    _uploader = VoiceReferenceUploader();
  }

  @override
  void dispose() {
    _uploader.close();
    super.dispose();
  }

  Future<void> _startCall(Character character, VoiceSelection selection) async {
    try {
      var resolved = selection;
      if (selection.mode == VoiceMode.voiceClone) {
        final path = selection.referencePath;
        if (path == null || !await File(path).exists()) {
          if (!mounted) return;
          final edit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('参考音频已不存在'),
              content: const Text('参考音频已不存在，请编辑角色后重新选择'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('编辑角色'),
                ),
              ],
            ),
          );
          if (edit == true && mounted) await _openEditor(character);
          return;
        }
        final referenceId = await _uploader.upload(selection.referencePath!);
        resolved = selection.withReferenceId(referenceId);
      }
      if (!mounted) return;
      final result = await Navigator.of(context).push<CallPageResult>(
        MaterialPageRoute<CallPageResult>(
          builder: (_) =>
              CallPage(character: character, voiceSelection: resolved),
        ),
      );
      if (result == CallPageResult.editCharacter && mounted) {
        await _openEditor(character);
      }
    } on VoiceReferenceUploadException catch (error) {
      if (!mounted) return;
      final message = error.statusCode == 413
          ? '参考音频不能超过 10 MB'
          : '参考音频上传失败，请稍后重试';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('音色准备失败，请检查网络和文件后重试')));
    }
  }

  Future<void> _openEditor([Character? character]) async {
    await Navigator.of(context).push<Character>(
      MaterialPageRoute<Character>(
        builder: (_) => CharacterEditorPage(character: character),
      ),
    );
  }

  Future<void> _confirmDelete(Character character) async {
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
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(charactersProvider.notifier).delete(character.id);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('角色删除失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(charactersProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '想给谁打电话？',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF252A3A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '选择角色和音色后发起通话',
                style: TextStyle(color: Color(0xFF777C8D), fontSize: 16),
              ),
              if (!_warningDismissed &&
                  characters.valueOrNull?.warnings.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Material(
                  color: const Color(0xFFFFF4D6),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                    child: Row(
                      children: [
                        const Expanded(child: Text('部分本地角色数据无法读取')),
                        IconButton(
                          key: const Key('dismiss_character_warning'),
                          onPressed: () =>
                              setState(() => _warningDismissed = true),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Expanded(
                child: characters.when(
                  data: (catalog) => ListView.separated(
                    itemCount: catalog.characters.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      if (index == catalog.characters.length) {
                        return Card(
                          key: const Key('create_character_card'),
                          elevation: 0,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _openEditor,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_circle_outline_rounded),
                                  SizedBox(width: 8),
                                  Text(
                                    '新建角色',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      final character = catalog.characters[index];
                      return CharacterCard(
                        character: character,
                        options: catalog.options,
                        onCall: (selection) => _startCall(character, selection),
                        onEdit: character.isCustom
                            ? () => _openEditor(character)
                            : null,
                        onDelete: character.isCustom
                            ? () => _confirmDelete(character)
                            : null,
                      );
                    },
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const Center(child: Text('角色加载失败')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
