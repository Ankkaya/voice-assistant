import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/character.dart';

class CharacterCard extends StatelessWidget {
  const CharacterCard({
    required this.character,
    required this.onTap,
    super.key,
  });

  final Character character;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '给${character.name}打电话',
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: character.themeColor.withValues(alpha: 0.18)),
        ),
        child: InkWell(
          key: Key('character_${character.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: character.themeColor.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: SvgPicture.asset(character.avatar),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        character.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        character.subtitle,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF606575),
                            ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.call_rounded, color: character.themeColor),
                          const SizedBox(width: 6),
                          Text(
                            '打电话',
                            style: TextStyle(
                              color: character.themeColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: character.themeColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

