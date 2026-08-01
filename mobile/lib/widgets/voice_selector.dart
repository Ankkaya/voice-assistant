import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/character_options.dart';
import '../models/voice_selection.dart';
import '../services/character_asset_store.dart';

class PickedVoiceReference {
  const PickedVoiceReference({
    required this.path,
    required this.name,
    required this.size,
  });

  final String path;
  final String name;
  final int size;
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
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.path == null) {
      throw const FormatException('无法读取这个音频文件，请换一个文件重试');
    }
    return PickedVoiceReference(
      path: file.path!,
      name: file.name,
      size: file.size,
    );
  }
}

class VoiceSelector extends StatefulWidget {
  const VoiceSelector({
    required this.options,
    required this.initialValue,
    required this.onChanged,
    this.picker = const FilePickerVoiceReferencePicker(),
    this.enabled = true,
    this.keyPrefix,
    super.key,
  });

  final List<PresetVoiceOption> options;
  final VoiceSelection initialValue;
  final ValueChanged<VoiceSelection> onChanged;
  final VoiceReferencePicker picker;
  final bool enabled;
  final String? keyPrefix;

  @override
  State<VoiceSelector> createState() => VoiceSelectorState();
}

class VoiceSelectorState extends State<VoiceSelector> {
  late VoiceMode _mode;
  late String? _presetVoice;
  late TextEditingController _descriptionController;
  String? _referencePath;
  String? _referenceName;
  bool _cloneAuthorized = false;
  String? _errorText;

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
    _cloneAuthorized = widget.initialValue.cloneAuthorized;
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_emit);
    _descriptionController.dispose();
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
      final lowerName = picked.name.toLowerCase();
      if (!lowerName.endsWith('.wav') && !lowerName.endsWith('.mp3')) {
        setState(() => _errorText = '请选择 WAV 或 MP3 参考音频');
        return;
      }
      if (picked.size <= 0) {
        setState(() => _errorText = '参考音频不能为空');
        return;
      }
      if (picked.size > maxVoiceReferenceBytes) {
        setState(() => _errorText = '参考音频不能超过 10 MB');
        return;
      }
      setState(() {
        _referencePath = picked.path;
        _referenceName = picked.name;
        _cloneAuthorized = false;
        _errorText = null;
      });
      _emit();
    } on FormatException catch (error) {
      if (mounted) setState(() => _errorText = error.message.toString());
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

  Key _key(String value) => ValueKey(
    widget.keyPrefix == null ? value : '${value}_${widget.keyPrefix}',
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '选择音色模式',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: 10),
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
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            key: _key('preset_voice'),
            initialValue: widget.options.any((item) => item.id == _presetVoice)
                ? _presetVoice
                : null,
            decoration: const InputDecoration(
              labelText: '预置音色',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final option in widget.options)
                DropdownMenuItem(value: option.id, child: Text(option.label)),
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
        ],
        if (_mode == VoiceMode.voiceDesign) ...[
          const SizedBox(height: 14),
          TextField(
            key: _key('voice_description'),
            controller: _descriptionController,
            enabled: widget.enabled,
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: '描述希望生成的声音',
              hintText: '例如：温暖、明亮的少年声音，语速适中……',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
        if (_mode == VoiceMode.voiceClone) ...[
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: _key('pick_reference'),
            onPressed: widget.enabled ? _pickReference : null,
            icon: const Icon(Icons.library_music_rounded),
            label: Text(_referenceName ?? '选择 WAV / MP3 参考音频'),
          ),
          CheckboxListTile(
            key: _key('clone_authorized'),
            value: _cloneAuthorized,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('我确认本人拥有或已获得该声音的使用授权'),
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
            '参考音频仅保存在本机，文件不超过 10 MB。',
            style: TextStyle(color: Color(0xFF777C8D), fontSize: 12),
          ),
        ],
        if (_errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
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
