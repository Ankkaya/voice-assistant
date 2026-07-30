import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/character.dart';
import '../widgets/character_card.dart';
import 'call_page.dart';

class CharacterPage extends ConsumerWidget {
  const CharacterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                '选择一个 AI 卡通角色',
                style: TextStyle(color: Color(0xFF777C8D), fontSize: 16),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: characters.when(
                  data: (items) => ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final character = items[index];
                      return CharacterCard(
                        character: character,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => CallPage(character: character),
                          ),
                        ),
                      );
                    },
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
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

