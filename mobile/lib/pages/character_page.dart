import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/character_catalog_controller.dart';
import '../models/character.dart';
import '../models/voice_selection.dart';
import '../services/app_update_service.dart';
import '../services/voice_reference_uploader.dart';
import '../theme/app_colors.dart';
import '../widgets/character_card.dart';
import 'call_page.dart';
import 'character_editor_page.dart';

class CharacterPage extends ConsumerStatefulWidget {
  const CharacterPage({
    this.characterSettingsBuilder,
    this.voiceReferenceUploader,
    this.referenceExists,
    this.appUpdateService,
    super.key,
  });

  final Widget Function(BuildContext, Character)? characterSettingsBuilder;
  final VoiceReferenceUploader? voiceReferenceUploader;
  final Future<bool> Function(String path)? referenceExists;
  final AppUpdateService? appUpdateService;

  @override
  ConsumerState<CharacterPage> createState() => _CharacterPageState();
}

class _CharacterPageState extends ConsumerState<CharacterPage> {
  late final VoiceReferenceUploader _uploader;
  late final bool _ownsUploader;
  late final AppUpdateService _appUpdateService;
  late final bool _ownsAppUpdateService;
  String? _busyCharacterId;
  AppVersion? _appVersion;
  bool _checkingUpdate = false;
  bool _updateDialogVisible = false;

  @override
  void initState() {
    super.initState();
    _ownsUploader = widget.voiceReferenceUploader == null;
    _uploader = widget.voiceReferenceUploader ?? VoiceReferenceUploader();
    _ownsAppUpdateService = widget.appUpdateService == null;
    _appUpdateService = widget.appUpdateService ?? GitHubAppUpdateService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkForUpdate(manual: false);
    });
  }

  @override
  void dispose() {
    if (_ownsUploader) _uploader.close();
    if (_ownsAppUpdateService) _appUpdateService.close();
    super.dispose();
  }

  Future<void> _checkForUpdate({required bool manual}) async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);

    AppUpdateResult? availableUpdate;
    String? feedback;
    try {
      final currentVersion = await _appUpdateService.currentVersion();
      if (mounted) setState(() => _appVersion = currentVersion);

      final result = await _appUpdateService.check();
      if (!mounted) return;
      _appVersion = result.currentVersion;
      if (result.updateAvailable) {
        availableUpdate = result;
      } else if (manual) {
        feedback = '当前已是最新版本';
      }
    } on AppUpdateException catch (error) {
      if (manual) feedback = _updateFailureMessage(error.failure);
    } on Object {
      if (manual) feedback = '检查更新失败，请稍后重试';
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }

    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (availableUpdate != null) {
      await _showUpdateDialog(availableUpdate);
    } else if (feedback != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(feedback)));
    }
  }

  String _updateFailureMessage(AppUpdateFailure failure) => switch (failure) {
    AppUpdateFailure.rateLimited => 'GitHub 请求频繁，请稍后重试',
    AppUpdateFailure.notFound => '暂未找到可用版本',
    AppUpdateFailure.invalidResponse => '版本信息配置有误',
    AppUpdateFailure.network => '检查更新失败，请稍后重试',
  };

  Future<void> _showUpdateDialog(AppUpdateResult result) async {
    if (_updateDialogVisible) return;
    _updateDialogVisible = true;
    var openingDownload = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('发现新版本 ${result.release.versionName}'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前版本：${result.currentVersion.displayName}'),
                    const SizedBox(height: 6),
                    Text('最新版本：${result.release.versionName}'),
                    const SizedBox(height: 6),
                    Text('发布日期：${_formatDate(result.release.publishedAt)}'),
                    const SizedBox(height: 6),
                    Text('安装包：${_formatFileSize(result.release.apkSizeBytes)}'),
                    if (result.release.releaseNotes.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        '更新内容',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(result.release.releaseNotes),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                key: const Key('cancel_app_update'),
                onPressed: openingDownload
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('download_app_update'),
                onPressed: openingDownload
                    ? null
                    : () async {
                        setDialogState(() => openingDownload = true);
                        final launched = await _appUpdateService.openDownload(
                          result.release,
                        );
                        if (!dialogContext.mounted) return;
                        if (launched) {
                          Navigator.of(dialogContext).pop();
                          return;
                        }
                        setDialogState(() => openingDownload = false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('无法打开 GitHub，请稍后重试')),
                        );
                      },
                child: openingDownload
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('从 GitHub 下载'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _updateDialogVisible = false;
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  String _formatFileSize(int bytes) {
    final megabytes = bytes / (1024 * 1024);
    if (megabytes >= 1) return '${megabytes.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).ceil()} KB';
  }

  Future<void> _openCharacterSettings(Character character) async {
    final settingsBuilder = widget.characterSettingsBuilder;
    if (settingsBuilder == null) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => settingsBuilder(routeContext, character),
      ),
    );
  }

  Future<void> _openNewCharacter() async {
    if (_busyCharacterId != null) return;
    await Navigator.of(context).push<Character>(
      MaterialPageRoute<Character>(builder: (_) => const CharacterEditorPage()),
    );
  }

  Future<void> _startCall(Character character) async {
    if (_busyCharacterId != null) return;
    setState(() => _busyCharacterId = character.id);
    try {
      final catalog = ref.read(charactersProvider).requireValue;
      var selection = catalog.voiceFor(character);
      if (selection.mode == VoiceMode.voiceClone) {
        final path = selection.referencePath;
        final exists =
            path != null &&
            await (widget.referenceExists?.call(path) ?? File(path).exists());
        if (!exists) {
          selection = _safePresetVoice(catalog, character);
        } else {
          selection = selection.withReferenceId(await _uploader.upload(path));
        }
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final result = await Navigator.of(context).push<CallPageResult>(
        MaterialPageRoute<CallPageResult>(
          builder: (_) =>
              CallPage(character: character, voiceSelection: selection),
        ),
      );
      if (result == CallPageResult.editCharacter && mounted) {
        await _openCharacterSettings(character);
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('现在还邀请不了，请稍后再试')));
    } finally {
      if (mounted) setState(() => _busyCharacterId = null);
    }
  }

  VoiceSelection _safePresetVoice(
    CharacterCatalogState catalog,
    Character character,
  ) {
    final defaultVoice = character.defaultVoice;
    if (defaultVoice.mode == VoiceMode.preset &&
        (defaultVoice.presetVoice ?? '').isNotEmpty) {
      return defaultVoice;
    }
    if (catalog.options.presetVoices.isEmpty) {
      throw StateError('No preset voice is available for safe fallback');
    }
    return VoiceSelection(
      mode: VoiceMode.preset,
      presetVoice: catalog.options.presetVoices.first.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(charactersProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          children: [
            Text(
              '今天想邀请谁给你打电话？',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.textPrimary,
                fontSize: 28,
                height: 1.22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '选一位伙伴，稍后他会打给你',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            characters.when(
              data: (catalog) {
                if (catalog.characters.isEmpty) {
                  return _EmptyCharacters(onCreateCharacter: _openNewCharacter);
                }
                return Column(
                  children: [
                    for (
                      var index = 0;
                      index < catalog.characters.length;
                      index++
                    ) ...[
                      if (index > 0) const SizedBox(height: 16),
                      CharacterCard(
                        character: catalog.characters[index],
                        busy: _busyCharacterId == catalog.characters[index].id,
                        onInvite: _busyCharacterId == null
                            ? () => _startCall(catalog.characters[index])
                            : null,
                        onEdit: _busyCharacterId == null
                            ? () => _openCharacterSettings(
                                catalog.characters[index],
                              )
                            : null,
                      ),
                    ],
                    const SizedBox(height: 18),
                    _CreateCharacterCard(onPressed: _openNewCharacter),
                  ],
                );
              },
              loading: () => const Column(
                children: [
                  _LoadingCharacterCard(index: 0),
                  SizedBox(height: 16),
                  _LoadingCharacterCard(index: 1),
                ],
              ),
              error: (_, __) => _CatalogFailure(
                onRetry: () => ref.invalidate(charactersProvider),
              ),
            ),
            const SizedBox(height: 28),
            _buildVersionFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildVersionFooter() {
    final version = _appVersion;
    final label = _checkingUpdate
        ? '正在检查更新…'
        : version == null
        ? '版本信息加载中…'
        : '版本 ${version.displayName}';
    final semanticsLabel = version == null
        ? label
        : '当前版本 ${version.versionName}，点击检查更新';

    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Center(
        child: TextButton.icon(
          key: const Key('app_version_button'),
          onPressed: _checkingUpdate
              ? null
              : () => _checkForUpdate(manual: true),
          icon: _checkingUpdate
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.info_outline_rounded, size: 16),
          label: Text(label),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textMuted,
            minimumSize: const Size(48, 48),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _LoadingCharacterCard extends StatelessWidget {
  const _LoadingCharacterCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    const placeholder = AppColors.placeholder;
    return Card(
      key: Key('loading_character_placeholder_$index'),
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: placeholder,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(dimension: 92),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PlaceholderLine(widthFactor: 0.58, height: 20),
                  SizedBox(height: 10),
                  _PlaceholderLine(widthFactor: 0.88, height: 14),
                  SizedBox(height: 15),
                  _PlaceholderLine(widthFactor: 0.50, height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderLine extends StatelessWidget {
  const _PlaceholderLine({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: widthFactor,
    alignment: Alignment.centerLeft,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.placeholder,
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(height: height),
    ),
  );
}

class _CatalogFailure extends StatelessWidget {
  const _CatalogFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _CatalogMessage(
    icon: Icons.cloud_off_rounded,
    title: '伙伴们暂时没有出现',
    message: '休息一下，再请他们出来吧',
    action: FilledButton.icon(
      key: const Key('retry_characters_button'),
      onPressed: onRetry,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('重新加载'),
    ),
  );
}

class _EmptyCharacters extends StatelessWidget {
  const _EmptyCharacters({required this.onCreateCharacter});

  final VoidCallback onCreateCharacter;

  @override
  Widget build(BuildContext context) => _CatalogMessage(
    icon: Icons.sentiment_satisfied_alt_rounded,
    title: '还没有可以邀请的伙伴',
    message: '请家长先添加一位伙伴',
    action: FilledButton.icon(
      key: const Key('empty_create_character_button'),
      onPressed: onCreateCharacter,
      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
      icon: const Icon(Icons.add_rounded),
      label: const Text('新建角色'),
    ),
  );
}

class _CreateCharacterCard extends StatelessWidget {
  const _CreateCharacterCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '新建角色，创造一个专属电话伙伴',
    child: Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.addCharacterGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('create_character_card'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(24),
          child: const SizedBox(
            height: 94,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x33FFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 52,
                      child: Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '新建角色',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '创造一个专属电话伙伴',
                          style: TextStyle(
                            color: Color(0xE6FFFFFF),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFE29A)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 54, color: AppColors.textMuted),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
        ),
        const SizedBox(height: 20),
        action,
      ],
    ),
  );
}
