import 'package:flutter/material.dart';

import '../models/character.dart';
import 'character_avatar_image.dart';

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

  @override
  Widget build(BuildContext context) {
    final themeColor = character.themeColor;
    const actionColor = Color(0xFF3D4660);
    return Semantics(
      button: true,
      enabled: !busy && onInvite != null,
      label: '邀请${character.name}给你打电话',
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shadowColor: themeColor.withValues(alpha: 0.13),
        color: Color.alphaBlend(
          themeColor.withValues(alpha: 0.055),
          Colors.white,
        ),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: themeColor.withValues(alpha: 0.20)),
        ),
        child: InkWell(
          key: Key('character_${character.id}'),
          onTap: busy ? null : onInvite,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: CharacterAvatarImage(
                      avatar: character.avatar,
                      fallbackColor: themeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        character.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: const Color(0xFF252A3A),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        character.displaySubtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF606575),
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (busy)
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: actionColor,
                              ),
                            )
                          else
                            Icon(
                              Icons.phone_in_talk_rounded,
                              size: 19,
                              color: actionColor,
                            ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              busy ? '正在邀请…' : '邀请来电',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: actionColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (!busy) ...[
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: actionColor,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
