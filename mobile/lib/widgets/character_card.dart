import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/voice_selection.dart';

class CharacterCard extends StatefulWidget {
  const CharacterCard({
    required this.character,
    required this.onCall,
    super.key,
  });

  final Character character;
  final Future<void> Function(VoiceSelection selection) onCall;

  @override
  State<CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<CharacterCard> {
  late final TextEditingController _descriptionController;
  VoiceMode _mode = VoiceMode.preset;
  String? _referencePath;
  String? _referenceName;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.character.defaultVoiceDescription,
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickReference() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3'],
      allowMultiple: false,
    );
    if (!mounted || result == null) return;
    final file = result.files.single;
    if (file.path == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法读取这个音频文件，请换一个文件重试')));
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('参考音频不能超过 10 MB')));
      return;
    }
    setState(() {
      _referencePath = file.path;
      _referenceName = file.name;
    });
  }

  Future<void> _call() async {
    final description = _descriptionController.text.trim();
    if (_mode == VoiceMode.voiceDesign && description.length < 8) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少用 8 个字描述希望生成的音色')));
      return;
    }
    if (_mode == VoiceMode.voiceClone && _referencePath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择已获授权的 WAV 或 MP3 参考音频')));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onCall(
        VoiceSelection(
          mode: _mode,
          presetVoice: _mode == VoiceMode.preset
              ? widget.character.defaultVoice.presetVoice
              : null,
          voiceDescription: description,
          referencePath: _referencePath,
          referenceName: _referenceName,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final character = widget.character;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: character.themeColor.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 82,
                  height: 82,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: character.themeColor.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      character.avatar.value,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        character.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        character.subtitle,
                        style: const TextStyle(color: Color(0xFF606575)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '选择音色模式',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _modeChip(VoiceMode.preset, '预置音色', Icons.graphic_eq_rounded),
                _modeChip(
                  VoiceMode.voiceDesign,
                  '音色设计',
                  Icons.auto_awesome_rounded,
                ),
                _modeChip(
                  VoiceMode.voiceClone,
                  '音色克隆',
                  Icons.audio_file_rounded,
                ),
              ],
            ),
            if (_mode == VoiceMode.voiceDesign) ...[
              const SizedBox(height: 14),
              TextField(
                key: Key('voice_description_${character.id}'),
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: '描述希望生成的声音',
                  hintText: '例如：温暖、明亮的少年声音，语速适中……',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_mode == VoiceMode.voiceClone) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                key: Key('pick_reference_${character.id}'),
                onPressed: _busy ? null : _pickReference,
                icon: const Icon(Icons.library_music_rounded),
                label: Text(_referenceName ?? '选择 WAV / MP3 参考音频'),
              ),
              const SizedBox(height: 7),
              const Text(
                '仅使用本人或已明确授权的声音，文件不超过 10 MB。',
                style: TextStyle(color: Color(0xFF777C8D), fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: Key('character_${character.id}'),
              onPressed: _busy ? null : _call,
              style: FilledButton.styleFrom(
                backgroundColor: character.themeColor,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.call_rounded),
              label: Text(_busy ? '正在准备音色…' : '给${character.name}打电话'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(VoiceMode mode, String label, IconData icon) {
    return ChoiceChip(
      key: Key('voice_mode_${widget.character.id}_${mode.name}'),
      selected: _mode == mode,
      onSelected: _busy ? null : (_) => setState(() => _mode = mode),
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selectedColor: widget.character.themeColor.withValues(alpha: 0.18),
      side: BorderSide(
        color: _mode == mode
            ? widget.character.themeColor
            : const Color(0xFFD8DAE2),
      ),
    );
  }
}
