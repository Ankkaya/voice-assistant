import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../audio/voice_clone_recorder.dart';
import '../audio/voice_preview_player.dart';
import '../models/character_options.dart';
import '../models/voice_selection.dart';
import '../services/character_asset_store.dart';
import '../theme/app_colors.dart';
import 'voice_clone_recording_sheet.dart';

class PickedVoiceReference {
  const PickedVoiceReference({
    required this.path,
    required this.name,
    required this.size,
    this.format,
  });

  final String path;
  final String name;
  final int size;
  final String? format;
}

abstract interface class VoiceReferencePicker {
  Future<PickedVoiceReference?> pick();
}

class FilePickerVoiceReferencePicker implements VoiceReferencePicker {
  const FilePickerVoiceReferencePicker();

  @override
  Future<PickedVoiceReference?> pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav', 'mp3'],
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.path == null) {
      throw const FormatException('无法读取这个音频文件，请换一个文件重试');
    }
    final format = _audioFormat(file.name) ?? _audioFormatFromBytes(file.bytes);
    return PickedVoiceReference(
      path: file.path!,
      name: file.name,
      size: file.size,
      format: format,
    );
  }

  static String? _audioFormat(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .split('?')
        .first
        .split('#')
        .first;
    if (normalized.endsWith('.wav')) return 'wav';
    if (normalized.endsWith('.mp3')) return 'mp3';
    return null;
  }

  static String? _audioFormatFromBytes(Uint8List? bytes) {
    if (bytes == null || bytes.length < 4) return null;
    final isWav =
        bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45;
    if (isWav) return 'wav';
    final hasId3 =
        bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33;
    final hasFrameSync =
        bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
    return hasId3 || hasFrameSync ? 'mp3' : null;
  }
}

class VoiceSelector extends StatefulWidget {
  const VoiceSelector({
    required this.options,
    required this.initialValue,
    required this.onChanged,
    this.picker = const FilePickerVoiceReferencePicker(),
    this.enabled = true,
    this.segmented = false,
    this.keyPrefix,
    this.onSuggestVoiceDescription,
    this.voiceRecorder,
    this.previewPlayer,
    this.presetPreviewPlayer,
    this.referencePreviewPlayer,
    super.key,
  });

  final List<PresetVoiceOption> options;
  final VoiceSelection initialValue;
  final ValueChanged<VoiceSelection> onChanged;
  final VoiceReferencePicker picker;
  final bool enabled;
  final bool segmented;
  final String? keyPrefix;
  final Future<String?> Function()? onSuggestVoiceDescription;
  final VoiceCloneRecorder? voiceRecorder;
  final VoiceClonePreviewPlayer? previewPlayer;
  final PresetVoicePreviewPlayer? presetPreviewPlayer;
  final VoiceClonePreviewPlayer? referencePreviewPlayer;

  @override
  State<VoiceSelector> createState() => VoiceSelectorState();
}

class VoiceSelectorState extends State<VoiceSelector> {
  late VoiceMode _mode;
  late String? _presetVoice;
  late TextEditingController _descriptionController;
  String? _referencePath;
  String? _referenceName;
  String? _referenceFormat;
  int? _referenceSize;
  Duration? _referenceDuration;
  String? _temporaryReferencePath;
  bool _cloneAuthorized = false;
  bool _suggestingVoiceDescription = false;
  bool _previewingPreset = false;
  bool _previewingReference = false;
  bool _loadingReferencePreview = false;
  String? _errorText;
  PresetVoicePreviewPlayer? _presetPreviewPlayer;
  VoiceClonePreviewPlayer? _referencePreviewPlayer;
  File? _referencePreviewFile;

  VoiceSelection get value => VoiceSelection(
    mode: _mode,
    presetVoice: _mode == VoiceMode.preset ? _presetVoice : null,
    voiceDescription: _mode == VoiceMode.voiceDesign
        ? _descriptionController.text
        : null,
    referencePath: _mode == VoiceMode.voiceClone ? _referencePath : null,
    referenceName: _mode == VoiceMode.voiceClone ? _referenceName : null,
    cloneAuthorized: _mode == VoiceMode.voiceClone && _cloneAuthorized,
  );

  @override
  void initState() {
    super.initState();
    _mode = widget.initialValue.mode;
    _presetVoice =
        widget.initialValue.presetVoice ??
        (widget.options.isEmpty ? null : widget.options.first.id);
    _descriptionController = TextEditingController(
      text: widget.initialValue.voiceDescription ?? '',
    )..addListener(_emit);
    _referencePath = widget.initialValue.referencePath;
    _referenceName = widget.initialValue.referenceName;
    _referenceFormat = _extensionFromValue(_referenceName);
    _cloneAuthorized = widget.initialValue.cloneAuthorized;
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_emit);
    _descriptionController.dispose();
    final temporaryReferencePath = _temporaryReferencePath;
    if (temporaryReferencePath != null) {
      unawaited(_deleteTemporaryReference(temporaryReferencePath));
    }
    unawaited(_presetPreviewPlayer?.dispose());
    unawaited(_referencePreviewPlayer?.dispose());
    unawaited(_deleteReferencePreviewFile());
    super.dispose();
  }

  bool validate() {
    final error = switch (_mode) {
      VoiceMode.preset when (_presetVoice ?? '').isEmpty => '请选择预置音色',
      VoiceMode.voiceDesign
          when _descriptionController.text.trim().runes.length < 8 =>
        '请至少用 8 个字描述希望生成的音色',
      VoiceMode.voiceDesign
          when _descriptionController.text.trim().runes.length > 500 =>
        '音色描述不能超过 500 个字',
      VoiceMode.voiceClone when _referencePath == null => '请选择 WAV 或 MP3 参考音频',
      VoiceMode.voiceClone when !_cloneAuthorized => '请确认你拥有该声音的使用授权',
      _ => null,
    };
    setState(() => _errorText = error);
    return error == null;
  }

  Future<void> _pickReference() async {
    try {
      final picked = await widget.picker.pick();
      if (!mounted || picked == null) return;
      // Some Android document providers return a display name and cached path
      // without an extension. FilePickerVoiceReferencePicker supplies a
      // content-sniffed format for that case.
      final format =
          picked.format ??
          (_hasSupportedAudioExtension(picked.name)
              ? _extensionFromValue(picked.name)
              : _extensionFromValue(picked.path));
      if (format == null) {
        setState(() => _errorText = '请选择 WAV 或 MP3 参考音频');
        return;
      }
      if (picked.size <= 0) {
        setState(() => _errorText = '参考音频不能为空');
        return;
      }
      if (picked.size > maxVoiceReferenceBytes) {
        setState(() => _errorText = '参考音频不能超过 7.5 MB');
        return;
      }
      await _replaceReference(
        path: picked.path,
        name: _nameWithExtension(picked.name, format),
        format: format,
        size: picked.size,
        temporary: false,
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _errorText = error.message.toString());
    }
  }

  static bool _hasSupportedAudioExtension(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .split('?')
        .first
        .split('#')
        .first;
    return normalized.endsWith('.wav') || normalized.endsWith('.mp3');
  }

  static String? _extensionFromValue(String? value) {
    if (value == null) return null;
    final normalized = value
        .trim()
        .toLowerCase()
        .split('?')
        .first
        .split('#')
        .first;
    if (normalized.endsWith('.wav')) return 'wav';
    if (normalized.endsWith('.mp3')) return 'mp3';
    return null;
  }

  static String _nameWithExtension(String name, String format) {
    return _hasSupportedAudioExtension(name) ? name : '$name.$format';
  }

  Future<void> _recordReference() async {
    final recording = await showVoiceCloneRecordingSheet(
      context,
      recorder: widget.voiceRecorder,
      previewPlayer: widget.previewPlayer,
    );
    if (!mounted || recording == null) return;
    await _replaceReference(
      path: recording.path,
      name: recording.name,
      format: 'wav',
      size: recording.size,
      duration: recording.duration,
      temporary: true,
    );
  }

  Future<void> _replaceReference({
    required String path,
    required String name,
    required bool temporary,
    String? format,
    int? size,
    Duration? duration,
  }) async {
    final previousTemporary = _temporaryReferencePath;
    if (previousTemporary != null && previousTemporary != path) {
      await _deleteTemporaryReference(previousTemporary);
    }
    await _deleteReferencePreviewFile();
    if (!mounted) {
      if (temporary) await _deleteTemporaryReference(path);
      return;
    }
    setState(() {
      _referencePath = path;
      _referenceName = name;
      _referenceFormat = format ?? _extensionFromValue(name);
      _referenceSize = size;
      _referenceDuration = duration;
      _temporaryReferencePath = temporary ? path : null;
      _cloneAuthorized = false;
      _errorText = null;
    });
    _emit();
  }

  static Future<void> _deleteTemporaryReference(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on Object {
      // Temporary draft cleanup is best effort.
    }
  }

  void _setMode(VoiceMode mode) {
    setState(() {
      _mode = mode;
      _errorText = null;
    });
    _emit();
  }

  void _emit() {
    if (!mounted) return;
    widget.onChanged(value);
  }

  Future<void> _suggestVoiceDescription() async {
    final callback = widget.onSuggestVoiceDescription;
    if (callback == null || _suggestingVoiceDescription) return;
    setState(() => _suggestingVoiceDescription = true);
    try {
      final suggestion = await callback();
      if (!mounted || suggestion == null) return;
      _descriptionController.value = TextEditingValue(
        text: suggestion,
        selection: TextSelection.collapsed(offset: suggestion.length),
      );
      setState(() => _errorText = null);
      _emit();
    } finally {
      if (mounted) setState(() => _suggestingVoiceDescription = false);
    }
  }

  Future<void> _previewPresetVoice() async {
    final voice = _presetVoice;
    if (voice == null || _previewingPreset) return;
    final previewPlayer = _presetPreviewPlayer ??=
        widget.presetPreviewPlayer ?? HttpPresetVoicePreviewPlayer();
    setState(() => _previewingPreset = true);
    try {
      await previewPlayer.play(
        voice,
        onFinished: () {
          if (mounted) setState(() => _previewingPreset = false);
        },
      );
    } on Object catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('音色试听暂时不可用，请检查语音服务连接')));
      }
    } finally {
      if (mounted) setState(() => _previewingPreset = false);
    }
  }

  Future<void> _toggleReferencePreview() async {
    final path = _referencePath;
    if (path == null) return;
    final previewPlayer = _referencePreviewPlayer ??=
        widget.referencePreviewPlayer ?? FlutterSoundVoiceClonePreviewPlayer();
    if (_previewingReference) {
      await previewPlayer.stop();
      if (mounted) {
        setState(() {
          _previewingReference = false;
          _loadingReferencePreview = false;
        });
      }
      return;
    }
    setState(() => _previewingReference = true);
    try {
      if (mounted) setState(() => _loadingReferencePreview = true);
      final playablePath = await _prepareReferencePreviewPath(path);
      if (!mounted || !_previewingReference) return;
      await previewPlayer.play(
        playablePath,
        onFinished: () {
          if (mounted) setState(() => _previewingReference = false);
        },
      );
      if (mounted) setState(() => _loadingReferencePreview = false);
    } on Object {
      if (mounted) {
        setState(() {
          _previewingReference = false;
          _loadingReferencePreview = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法试听这段音频，请重新选择文件')));
      }
    }
  }

  Future<String> _prepareReferencePreviewPath(String path) async {
    final format = _referenceFormat;
    if (format == null || _extensionFromValue(path) != null) return path;
    final existing = _referencePreviewFile;
    if (existing != null && await existing.exists()) return existing.path;
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/voice_reference_preview_${identityHashCode(this)}.$format',
    );
    await File(path).copy(file.path);
    _referencePreviewFile = file;
    return file.path;
  }

  Future<void> _deleteReferencePreviewFile() async {
    final file = _referencePreviewFile;
    _referencePreviewFile = null;
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on Object {
      // Best effort cleanup for the temporary preview copy.
    }
  }

  Key _key(String value) => ValueKey(
    widget.keyPrefix == null ? value : '${value}_${widget.keyPrefix}',
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.segmented)
          const Text(
            '选择音色模式',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        if (!widget.segmented) const SizedBox(height: 10),
        if (widget.segmented)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                for (final mode in VoiceMode.values)
                  Expanded(
                    child: TextButton(
                      key: _key('voice_mode_${mode.name}'),
                      onPressed: widget.enabled ? () => _setMode(mode) : null,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
                        backgroundColor: _mode == mode
                            ? Colors.white
                            : Colors.transparent,
                        foregroundColor: _mode == mode
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(switch (mode) {
                        VoiceMode.preset => '预置音色',
                        VoiceMode.voiceDesign => '音色设计',
                        VoiceMode.voiceClone => '音色克隆',
                      }),
                    ),
                  ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _modeChip(VoiceMode.preset, '预置音色', Icons.graphic_eq_rounded),
              _modeChip(
                VoiceMode.voiceDesign,
                '音色设计',
                Icons.auto_awesome_rounded,
              ),
              _modeChip(VoiceMode.voiceClone, '音色克隆', Icons.audio_file_rounded),
            ],
          ),
        if (_mode == VoiceMode.preset) ...[
          SizedBox(height: widget.segmented ? 20 : 14),
          if (widget.segmented) ...[
            const Text(
              '选择音色',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
          ],
          DropdownButtonFormField<String>(
            isExpanded: true,
            isDense: !widget.segmented,
            style: widget.segmented
                ? const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  )
                : null,
            icon: Icon(
              widget.segmented
                  ? Icons.expand_more_rounded
                  : Icons.arrow_drop_down,
              color: AppColors.textSecondary,
              size: 20,
            ),
            selectedItemBuilder: widget.segmented
                ? (context) => [
                    for (final option in widget.options)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          option.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ]
                : null,
            key: _key('preset_voice'),
            initialValue: widget.options.any((item) => item.id == _presetVoice)
                ? _presetVoice
                : null,
            decoration: InputDecoration(
              labelText: widget.segmented ? null : '预置音色',
              filled: widget.segmented,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: widget.segmented
                  ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
                  : null,
              prefixIcon: widget.segmented
                  ? const Icon(
                      Icons.record_voice_over,
                      color: AppColors.primary,
                      size: 20,
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.segmented ? 12 : 4),
              ),
              enabledBorder: widget.segmented
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.outline),
                    )
                  : null,
            ),
            items: [
              for (final option in widget.options)
                DropdownMenuItem(
                  value: option.id,
                  child: Text(
                    option.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: widget.enabled
                ? (value) {
                    setState(() {
                      _presetVoice = value;
                      _errorText = null;
                    });
                    _emit();
                  }
                : null,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: _key('preview_preset_voice'),
            onPressed: widget.enabled && !_previewingPreset
                ? _previewPresetVoice
                : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            icon: _previewingPreset
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_circle_outline_rounded),
            label: Text(_previewingPreset ? '正在试听…' : '试听当前音色'),
          ),
        ],
        if (_mode == VoiceMode.voiceDesign) ...[
          SizedBox(height: widget.segmented ? 20 : 14),
          if (widget.segmented) ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Text(
                  '音色描述（1～4 句）',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (widget.onSuggestVoiceDescription != null)
                  _voiceSuggestionButton(),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: _key('voice_description'),
            controller: _descriptionController,
            enabled: widget.enabled,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            style: widget.segmented
                ? const TextStyle(
                    fontSize: 16,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  )
                : null,
            decoration: InputDecoration(
              labelText: widget.segmented ? null : '音色描述（1～4 句）',
              hintText: '例如：十岁左右的少年男声，清亮温暖、活泼自信，普通话清晰，语速适中。',
              helperText: '建议包含年龄与性别、音色质感、情绪语气、语速节奏；也可补充角色或场景。',
              helperMaxLines: 6,
              filled: widget.segmented,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: widget.segmented
                  ? const EdgeInsets.all(14)
                  : null,
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(widget.segmented ? 12 : 4),
              ),
              enabledBorder: widget.segmented
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.outline),
                    )
                  : null,
              focusedBorder: widget.segmented
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    )
                  : null,
            ),
          ),
          if (!widget.segmented &&
              widget.onSuggestVoiceDescription != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: _key('suggest_voice_description'),
                onPressed: widget.enabled && !_suggestingVoiceDescription
                    ? _suggestVoiceDescription
                    : null,
                icon: _suggestingVoiceDescription
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(_suggestingVoiceDescription ? '正在生成…' : 'AI 生成建议'),
              ),
            ),
          ],
        ],
        if (_mode == VoiceMode.voiceClone) ...[
          SizedBox(height: widget.segmented ? 20 : 14),
          if (widget.segmented) ...[
            const Text(
              '参考声音',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '录制一段声音，或从本机选择音频',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
          ],
          if (_referencePath == null)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: _key('record_reference'),
                    style: _referenceButtonStyle,
                    onPressed: widget.enabled ? _recordReference : null,
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('录制声音'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: _key('pick_reference'),
                    style: _referenceButtonStyle,
                    onPressed: widget.enabled ? _pickReference : null,
                    icon: const Icon(Icons.library_music_rounded),
                    label: const Text('选择音频'),
                  ),
                ),
              ],
            )
          else ...[
            _selectedReference(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: _key('record_reference'),
                    style: _referenceButtonStyle,
                    onPressed: widget.enabled ? _recordReference : null,
                    icon: const Icon(Icons.mic_rounded),
                    label: const Text('重新录制'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    key: _key('pick_reference'),
                    style: _referenceButtonStyle,
                    onPressed: widget.enabled ? _pickReference : null,
                    icon: const Icon(Icons.library_music_rounded),
                    label: const Text('更换文件'),
                  ),
                ),
              ],
            ),
          ],
          CheckboxListTile(
            key: _key('clone_authorized'),
            value: _cloneAuthorized,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              '我确认本人拥有或已获得该声音的使用授权',
              style: widget.segmented
                  ? const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    )
                  : null,
            ),
            onChanged: widget.enabled
                ? (value) {
                    setState(() {
                      _cloneAuthorized = value ?? false;
                      _errorText = null;
                    });
                    _emit();
                  }
                : null,
          ),
          const Text(
            '建议在安静环境中自然说话 10～30 秒；也可选择 WAV / MP3，文件不超过 7.5 MB。录音保存在本机，仅在通话时临时上传。',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.24),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _voiceSuggestionButton() => TextButton.icon(
    key: _key('suggest_voice_description'),
    onPressed: widget.enabled && !_suggestingVoiceDescription
        ? _suggestVoiceDescription
        : null,
    style: TextButton.styleFrom(
      foregroundColor: AppColors.primary,
      backgroundColor: AppColors.surfaceTint,
      minimumSize: const Size(0, 42),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    icon: _suggestingVoiceDescription
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.auto_awesome_rounded, size: 18),
    label: Text(_suggestingVoiceDescription ? '正在生成…' : 'AI 生成建议'),
  );

  static const _referenceButtonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(double.infinity, 48)),
    maximumSize: WidgetStatePropertyAll(Size(double.infinity, 48)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    ),
    iconSize: WidgetStatePropertyAll(20),
    textStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  Widget _selectedReference() => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.outline),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(
            _referenceDuration == null
                ? Icons.audio_file_rounded
                : Icons.mic_rounded,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _referenceName ?? '参考音频',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (_referenceFormat != null || _referenceSize != null)
                  Text(
                    [
                      if (_referenceFormat != null)
                        _referenceFormat!.toUpperCase(),
                      if (_referenceSize != null)
                        _formatFileSize(_referenceSize!),
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                if (_referenceDuration != null)
                  Text(
                    '录音时长 ${_formatDuration(_referenceDuration!)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: _key('preview_reference'),
            tooltip: _previewingReference ? '停止试听' : '试听参考音频',
            onPressed: widget.enabled ? _toggleReferencePreview : null,
            color: AppColors.primary,
            icon: _loadingReferencePreview
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _previewingReference
                ? const Icon(Icons.stop_rounded)
                : const Icon(Icons.play_circle_outline_rounded),
          ),
          const Icon(Icons.check_circle_rounded, color: AppColors.primary),
        ],
      ),
    ),
  );

  static String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _modeChip(VoiceMode mode, String label, IconData icon) {
    return ChoiceChip(
      key: _key('voice_mode_${mode.name}'),
      selected: _mode == mode,
      onSelected: widget.enabled ? (_) => _setMode(mode) : null,
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
