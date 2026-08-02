import 'package:flutter/material.dart';

import 'pages/character_page.dart';
import 'pages/parent_settings_page.dart';

class VoiceCallApp extends StatelessWidget {
  const VoiceCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4E72E6),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'AI 角色电话',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        textTheme: const TextTheme(
          headlineMedium: TextStyle(height: 1.22),
          titleLarge: TextStyle(height: 1.28),
          bodyLarge: TextStyle(fontSize: 16, height: 1.5),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: CharacterPage(
        parentSettingsBuilder: (_, initialCharacterId) =>
            ParentSettingsPage(initialCharacterId: initialCharacterId),
      ),
    );
  }
}
