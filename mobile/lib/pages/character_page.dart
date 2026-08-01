import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/character_catalog_controller.dart';
import '../models/character.dart';
import '../models/voice_selection.dart';
import '../services/voice_reference_uploader.dart';
import '../widgets/character_card.dart';
import 'call_page.dart';

class CharacterPage extends ConsumerStatefulWidget {
  const CharacterPage({super.key});

  @override
  ConsumerState<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends ConsumerState<CharacterPage> {
  late final VoiceReferenceUploader _uploader;

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
        final referenceId = await _uploader.upload(selection.referencePath!);
        resolved = selection.withReferenceId(referenceId);
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CallPage(character: character, voiceSelection: resolved),
        ),
      );
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
              const SizedBox(height: 24),
              Expanded(
                child: characters.when(
                  data: (catalog) => ListView.separated(
                    itemCount: catalog.characters.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final character = catalog.characters[index];
                      return CharacterCard(
                        character: character,
                        onCall: (selection) => _startCall(character, selection),
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
