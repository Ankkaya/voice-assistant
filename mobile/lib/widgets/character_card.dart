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
    super.key,
  });

  final Character character;
  final CharacterOptions options;
  final Future<void> Function(VoiceSelection selection) onCall;

  @override
  State<CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<CharacterCard> {
  final _voiceKey = GlobalKey<VoiceSelectorState>();
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
                    ],
                  ),
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
