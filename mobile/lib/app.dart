import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controllers/character_catalog_controller.dart';
import 'pages/character_editor_page.dart';
import 'pages/character_page.dart';
import 'pages/app_startup_page.dart';
import 'theme/app_colors.dart';

class VoiceCallApp extends StatelessWidget {
  const VoiceCallApp({super.key});

  static const _appSystemUiOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: AppColors.background,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarDividerColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          secondary: AppColors.secondary,
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecondary,
          outline: AppColors.outline,
        );
    final baseTextTheme = ThemeData.light().textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );
    return MaterialApp(
      title: '嗨呀',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        textTheme: baseTextTheme.copyWith(
          headlineMedium: baseTextTheme.headlineMedium?.copyWith(
            height: 1.22,
            color: AppColors.textPrimary,
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            height: 1.28,
            color: AppColors.textPrimary,
          ),
          bodyLarge: baseTextTheme.bodyLarge?.copyWith(
            color: AppColors.textPrimary,
            fontSize: 16,
            height: 1.5,
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
          bodySmall: baseTextTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          floatingLabelStyle: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
          hintStyle: const TextStyle(color: AppColors.textMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryDeep,
            side: const BorderSide(color: AppColors.outline),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryDeep,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: _appSystemUiOverlayStyle,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _AppHome(),
    );
  }
}

class _AppHome extends ConsumerStatefulWidget {
  const _AppHome();

  @override
  ConsumerState<_AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends ConsumerState<_AppHome> {
  static const _minimumStartupDuration = Duration(milliseconds: 400);
  Timer? _startupTimer;
  bool _startupDurationElapsed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startupTimer = Timer(_minimumStartupDuration, () {
        if (mounted) setState(() => _startupDurationElapsed = true);
      });
    });
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Let the first Flutter frame paint the startup surface before kicking
    // off the local catalog initialization.
    if (!_startupDurationElapsed) return const AppStartupPage();
    final catalog = ref.watch(charactersProvider);
    if (catalog.isLoading && !catalog.hasValue) {
      return const AppStartupPage();
    }
    return CharacterPage(
      characterSettingsBuilder: (_, character) =>
          CharacterEditorPage(character: character),
    );
  }
}
