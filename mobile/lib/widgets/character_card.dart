import 'package:flutter/material.dart';

import '../models/character.dart';
import '../models/character_options.dart';
import '../models/voice_selection.dart';
import 'character_avatar_image.dart';
import 'voice_selector.dart';

class CharacterCard extends StatefulWidget {
  const CharacterCard({
    required this.character,
    required this.options,
    required this.onCall,
    this.onEdit,
    this.onDelete,
    super.key,
  });

  final Character character;
  final CharacterOptions options;
  final Future<void> Function(VoiceSelection selection) onCall;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  State<CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<CharacterCard> {
  var _voiceKey = GlobalKey<VoiceSelectorState>();
  late VoiceSelection _selection;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selection = widget.character.defaultVoice;
  }

  Future<void> _call() async {
    if (!(_voiceKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await widget.onCall(_voiceKey.currentState?.value ?? _selection);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _selection = widget.character.defaultVoice;
          _voiceKey = GlobalKey<VoiceSelectorState>();
        });
      }
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
                    child: CharacterAvatarImage(
                      avatar: character.avatar,
                      fallbackColor: character.themeColor,
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
                        character.displaySubtitle,
                        style: const TextStyle(color: Color(0xFF606575)),
                      ),
                      if (character.isCustom) ...[
                        const SizedBox(height: 7),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: character.themeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            child: Text(
                              '我的角色',
                              style: TextStyle(
                                color: character.themeColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (character.isCustom)
                  PopupMenuButton<String>(
                    key: Key('character_menu_${character.id}'),
                    onSelected: (value) {
                      if (value == 'edit') widget.onEdit?.call();
                      if (value == 'delete') widget.onDelete?.call();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('编辑')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            VoiceSelector(
              key: _voiceKey,
              keyPrefix: character.id,
              options: widget.options.presetVoices,
              initialValue: character.defaultVoice,
              enabled: !_busy,
              onChanged: (value) => _selection = value,
            ),
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
}
