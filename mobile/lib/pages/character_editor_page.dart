import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/character_catalog_controller.dart';
import '../models/character.dart';
import '../models/character_options.dart';
import '../models/voice_selection.dart';
import '../widgets/character_avatar_picker.dart';
import '../widgets/character_profile_fields.dart';

class CharacterEditorPage extends ConsumerStatefulWidget {
  const CharacterEditorPage({
    this.character,
    this.avatarPicker,
    this.options,
    this.onSave,
    super.key,
  });

  final Character? character;
  final AvatarPicker? avatarPicker;
  final CharacterOptions? options;
  final Future<Character> Function(CustomCharacterDraft draft)? onSave;

  @override
  ConsumerState<CharacterEditorPage> createState() =>
      _CharacterEditorPageState();
}

class _CharacterEditorPageState extends ConsumerState<CharacterEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _greetingController;
  late final TextEditingController _descriptionController;
  late CharacterAvatarRef _avatar;
  late int _themeColorValue;
  late String? _identityId;
  late Set<String> _traitIds;
  late Set<String> _interestIds;
  bool _greetingEdited = false;
  bool _settingGreeting = false;
  bool _saving = false;
  String? _identityError;
  String? _traitsError;

  @override
  void initState() {
    super.initState();
    final character = widget.character;
    _nameController = TextEditingController(text: character?.name ?? '')
      ..addListener(_updateDefaultGreeting);
    _subtitleController = TextEditingController(
      text: character?.subtitle ?? '',
    );
    _greetingController = TextEditingController(text: character?.greeting ?? '')
      ..addListener(_markGreetingEdited);
    _descriptionController = TextEditingController(
      text: character?.profile?.description ?? '',
    );
    _avatar = character?.avatar ?? const CharacterAvatarRef.bundled('star');
    _themeColorValue =
        character?.themeColor.toARGB32() ?? bundledAvatarColors['star']!;
    _identityId = character?.profile?.identityId;
    _traitIds = {...?character?.profile?.traitIds};
    _interestIds = {...?character?.profile?.interestIds};
    _greetingEdited = character != null;
  }

  @override
  void dispose() {
    _nameController.removeListener(_updateDefaultGreeting);
    _greetingController.removeListener(_markGreetingEdited);
    _nameController.dispose();
    _subtitleController.dispose();
    _greetingController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _updateDefaultGreeting() {
    if (_greetingEdited) return;
    final name = _nameController.text.trim();
    final greeting = name.isEmpty ? '' : '你好呀，我是$name！很高兴接到你的电话。';
    if (_greetingController.text == greeting) return;
    _settingGreeting = true;
    _greetingController.value = TextEditingValue(
      text: greeting,
      selection: TextSelection.collapsed(offset: greeting.length),
    );
    _settingGreeting = false;
  }

  void _markGreetingEdited() {
    if (!_settingGreeting) _greetingEdited = true;
  }

  Future<void> _save(CharacterOptions options) async {
    FocusScope.of(context).unfocus();
    final formValid = _formKey.currentState?.validate() ?? false;
    final identityValid = (_identityId ?? '').isNotEmpty;
    final traitsValid = _traitIds.isNotEmpty;
    setState(() {
      _identityError = identityValid ? null : '请选择角色身份';
      _traitsError = traitsValid ? null : '至少选择一个性格';
    });
    if (!formValid || !identityValid || !traitsValid) return;

    final defaultVoice =
        widget.character?.defaultVoice ??
        VoiceSelection(
          mode: VoiceMode.preset,
          presetVoice: options.presetVoices.first.id,
        );
    final draft = CustomCharacterDraft(
      name: _nameController.text.trim(),
      subtitle: _subtitleController.text.trim(),
      avatar: _avatar,
      themeColorValue: _themeColorValue,
      profile: CustomCharacterProfile(
        identityId: _identityId!,
        traitIds: _traitIds.toList(growable: false),
        interestIds: _interestIds.toList(growable: false),
        description: _descriptionController.text.trim(),
      ),
      greeting: _greetingController.text.trim(),
      defaultVoice: defaultVoice,
    );
    setState(() => _saving = true);
    try {
      final saved = widget.onSave != null
          ? await widget.onSave!(draft)
          : widget.character == null
          ? await ref.read(charactersProvider.notifier).create(draft)
          : await ref
                .read(charactersProvider.notifier)
                .updateCharacter(widget.character!.id, draft);
      if (mounted) Navigator.of(context).pop(saved);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('角色保存失败，请检查存储空间后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliedOptions = widget.options;
    final catalog = suppliedOptions == null
        ? ref.watch(charactersProvider)
        : null;
    final options = suppliedOptions ?? catalog?.valueOrNull?.options;
    if (options == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.character == null ? '新建角色' : '编辑角色')),
        body: catalog?.hasError == true
            ? const Center(child: Text('角色选项加载失败'))
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.character == null && options.presetVoices.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.character == null ? '新建角色' : '编辑角色')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('角色选项加载失败'),
                SizedBox(height: 8),
                Text('没有可用的预置音色，请检查角色选项配置'),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.character == null ? '新建角色' : '编辑角色')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle('基本信息'),
                TextFormField(
                  key: const Key('character_name'),
                  controller: _nameController,
                  enabled: !_saving,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: '角色名称',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return '请输入角色名称';
                    if (text.runes.length > 20) return '角色名称不能超过 20 个字';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('character_subtitle'),
                  controller: _subtitleController,
                  enabled: !_saving,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    labelText: '一句话介绍（可选）',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().runes.length > 30
                      ? '一句话介绍不能超过 30 个字'
                      : null,
                ),
                const SizedBox(height: 8),
                CharacterAvatarPicker(
                  initialAvatar: _avatar,
                  initialColorValue: _themeColorValue,
                  picker: widget.avatarPicker,
                  enabled: !_saving,
                  onChanged: (avatar, colorValue) {
                    _avatar = avatar;
                    _themeColorValue = colorValue;
                  },
                ),
                const SizedBox(height: 28),
                _sectionTitle('角色设定'),
                CharacterProfileFields(
                  options: options,
                  identityId: _identityId,
                  traitIds: _traitIds,
                  interestIds: _interestIds,
                  identityError: _identityError,
                  traitsError: _traitsError,
                  enabled: !_saving,
                  onIdentityChanged: (value) => setState(() {
                    _identityId = value;
                    _identityError = null;
                  }),
                  onTraitsChanged: (value) => setState(() {
                    _traitIds = value;
                    _traitsError = null;
                  }),
                  onInterestsChanged: (value) =>
                      setState(() => _interestIds = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('character_description'),
                  controller: _descriptionController,
                  enabled: !_saving,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: '补充描述（可选）',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => (value ?? '').trim().runes.length > 200
                      ? '补充描述不能超过 200 个字'
                      : null,
                ),
                const SizedBox(height: 28),
                _sectionTitle('开场白'),
                TextFormField(
                  key: const Key('character_greeting'),
                  controller: _greetingController,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: '接通电话时说的话',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return '请输入开场白';
                    if (text.runes.length > 120) return '开场白不能超过 120 个字';
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  key: const Key('save_character'),
                  onPressed: _saving ? null : () => _save(options),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? '正在保存…' : '保存角色'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}
