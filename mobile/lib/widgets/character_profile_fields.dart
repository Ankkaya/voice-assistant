import 'package:flutter/material.dart';

import '../models/character_options.dart';

class CharacterProfileFields extends StatelessWidget {
  const CharacterProfileFields({
    required this.options,
    required this.identityId,
    required this.traitIds,
    required this.interestIds,
    required this.onIdentityChanged,
    required this.onTraitsChanged,
    required this.onInterestsChanged,
    this.identityError,
    this.traitsError,
    this.enabled = true,
    super.key,
  });

  final CharacterOptions options;
  final String? identityId;
  final Set<String> traitIds;
  final Set<String> interestIds;
  final ValueChanged<String> onIdentityChanged;
  final ValueChanged<Set<String>> onTraitsChanged;
  final ValueChanged<Set<String>> onInterestsChanged;
  final String? identityError;
  final String? traitsError;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final errorStyle = TextStyle(color: Theme.of(context).colorScheme.error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('角色身份', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options.identities)
              ChoiceChip(
                key: ValueKey('identity_${option.id}'),
                label: Text(option.label),
                selected: identityId == option.id,
                onSelected: enabled
                    ? (_) => onIdentityChanged(option.id)
                    : null,
              ),
          ],
        ),
        if (identityError != null) ...[
          const SizedBox(height: 6),
          Text(identityError!, style: errorStyle),
        ],
        const SizedBox(height: 18),
        const Text(
          '性格（选择 1～3 个）',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options.traits)
              FilterChip(
                key: ValueKey('trait_${option.id}'),
                label: Text(option.label),
                selected: traitIds.contains(option.id),
                onSelected: enabled
                    ? (selected) => _toggle(
                        current: traitIds,
                        id: option.id,
                        selected: selected,
                        max: 3,
                        onChanged: onTraitsChanged,
                      )
                    : null,
              ),
          ],
        ),
        if (traitsError != null) ...[
          const SizedBox(height: 6),
          Text(traitsError!, style: errorStyle),
        ],
        const SizedBox(height: 18),
        const Text('兴趣（最多 3 个）', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options.interests)
              FilterChip(
                key: ValueKey('interest_${option.id}'),
                label: Text(option.label),
                selected: interestIds.contains(option.id),
                onSelected: enabled
                    ? (selected) => _toggle(
                        current: interestIds,
                        id: option.id,
                        selected: selected,
                        max: 3,
                        onChanged: onInterestsChanged,
                      )
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  static void _toggle({
    required Set<String> current,
    required String id,
    required bool selected,
    required int max,
    required ValueChanged<Set<String>> onChanged,
  }) {
    final updated = Set<String>.from(current);
    if (selected) {
      if (updated.length >= max) return;
      updated.add(id);
    } else {
      updated.remove(id);
    }
    onChanged(updated);
  }
}
