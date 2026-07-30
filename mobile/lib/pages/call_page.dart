import 'package:flutter/material.dart';

import '../models/character.dart';

class CallPage extends StatelessWidget {
  const CallPage({required this.character, super.key});

  final Character character;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(character.name)),
      body: const Center(child: Text('正在准备通话…')),
    );
  }
}

