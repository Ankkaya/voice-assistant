import 'package:flutter/material.dart';

import 'pages/character_page.dart';

class VoiceCallApp extends StatelessWidget {
  const VoiceCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 角色电话',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4E72E6),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      home: const CharacterPage(),
    );
  }
}
