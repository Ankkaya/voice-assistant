import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/character_catalog_controller.dart';
import '../models/character.dart';
import '../models/character_options.dart';
import '../models/voice_selection.dart';
import '../widgets/character_avatar_picker.dart';
import '../widgets/character_profile_fields.dart';
import '../widgets/voice_selector.dart';

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
  final _voiceKey = GlobalKey<VoiceSelectorState>();
  late final TextEditingController _nameController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _greetingController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _promptController;
  late CharacterAvatarRef _avatar;
  late int _themeColorValue;
  late String? _identityId;
  late Set<String> _traitIds;
  late Set<String> _interestIds;
  late VoiceSelection _voiceSelection;
  bool _voiceInitialized = false;
  bool _greetingEdited = false;
  bool _settingGreeting = false;
  bool _saving = false;
  int _selectedTab = 0;
  String? _identityError;
  String? _traitsError;

  bool get _isEditing => widget.character != null;

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
    _promptController = TextEditingController(
      text: character == null
          ? ''
          : character.promptProfile.trim().isNotEmpty
          ? character.promptProfile
          : _defaultPrompt(character),
    );
    _avatar = character?.avatar ?? const CharacterAvatarRef.bundled('star');
    _themeColorValue =
        character?.themeColor.toARGB32() ?? bundledAvatarColors['star']!;
    _identityId = character?.profile?.identityId;
    _traitIds = {...?character?.profile?.traitIds};
    _interestIds = {...?character?.profile?.interestIds};
    _voiceSelection =
        character?.defaultVoice ?? const VoiceSelection(mode: VoiceMode.preset);
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
    _promptController.dispose();
    super.dispose();
  }

  static String _defaultPrompt(Character character) {
    final description = character.profile?.description.trim() ?? '';
    final detail = description.isEmpty
        ? character.displaySubtitle
        : description;
    return '你是${character.name}，$detail。与 6–9 岁儿童对话时使用简短、积极、易懂的中文，保持温暖、耐心，并鼓励孩子提问。';
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
    final voiceValid =
        !_isEditing || (_voiceKey.currentState?.validate() ?? false);
    setState(() {
      _identityError = identityValid ? null : '请选择角色身份';
      _traitsError = traitsValid ? null : '至少选择一个性格';
    });
    if (!formValid || !identityValid || !traitsValid || !voiceValid) return;

    final selectedVoice = _isEditing
        ? _voiceKey.currentState!.value
        : VoiceSelection(
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
      defaultVoice: selectedVoice,
      promptProfile: _isEditing ? _promptController.text.trim() : '',
    );
    setState(() => _saving = true);
    try {
      final Character saved;
      if (widget.onSave != null) {
        saved = await widget.onSave!(draft);
      } else if (!_isEditing) {
        saved = await ref.read(charactersProvider.notifier).create(draft);
      } else {
        saved = await ref
            .read(charactersProvider.notifier)
            .updateCharacter(widget.character!.id, draft);
        await ref
            .read(charactersProvider.notifier)
            .saveVoice(widget.character!.id, selectedVoice);
      }
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
    final catalogState = catalog?.valueOrNull;
    final options = suppliedOptions ?? catalogState?.options;
    if (options == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEditing ? '角色编辑' : '新建角色')),
        body: catalog?.hasError == true
            ? const Center(child: Text('角色选项加载失败'))
            : const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_voiceInitialized) {
      _voiceSelection = widget.character == null
          ? VoiceSelection(
              mode: VoiceMode.preset,
              presetVoice: options.presetVoices.isEmpty
                  ? null
                  : options.presetVoices.first.id,
            )
          : catalogState?.voiceFor(widget.character!) ??
                widget.character!.defaultVoice;
      _voiceInitialized = true;
    }
    if (!_isEditing && options.presetVoices.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('新建角色')),
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
      appBar: AppBar(title: Text(_isEditing ? '角色编辑' : '新建角色')),
      bottomNavigationBar: _isEditing
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: _saveButton(options, editMode: true),
            )
          : null,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, _isEditing ? 28 : 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _isEditing
                  ? _editFields(options)
                  : _createFields(options),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _editFields(CharacterOptions options) => [
    _sectionTitle('角色基础信息'),
    Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE7E9F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _MyCharacterBadge(),
                const Spacer(),
                Text(
                  '${_nameController.text.runes.length}/20',
                  style: const TextStyle(
                    color: Color(0xFF777C8D),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 18),
            _nameField(),
            const SizedBox(height: 12),
            _subtitleField(label: '角色简介'),
            const SizedBox(height: 18),
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
            _descriptionField(),
          ],
        ),
      ),
    ),
    const SizedBox(height: 24),
    _settingsTabs(),
    const SizedBox(height: 18),
    IndexedStack(
      index: _selectedTab,
      children: [_voiceSettings(options), _promptSettings()],
    ),
  ];

  List<Widget> _createFields(CharacterOptions options) => [
    _sectionTitle('基本信息'),
    _nameField(),
    const SizedBox(height: 12),
    _subtitleField(label: '一句话介绍（可选）'),
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
      onInterestsChanged: (value) => setState(() => _interestIds = value),
    ),
    const SizedBox(height: 16),
    _descriptionField(),
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
    _saveButton(options, editMode: false),
  ];

  Widget _settingsTabs() => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFD8DAE2))),
    ),
    child: Row(
      children: [
        _tabButton(0, '音色设置', const Key('voice_settings_tab')),
        _tabButton(1, '内置提示词', const Key('prompt_settings_tab')),
      ],
    ),
  );

  Widget _tabButton(int index, String label, Key key) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: key,
          onPressed: _saving
              ? null
              : () => setState(() => _selectedTab = index),
          style: TextButton.styleFrom(
            foregroundColor: _selectedTab == index
                ? const Color(0xFF4E72E6)
                : const Color(0xFF777C8D),
            padding: const EdgeInsets.symmetric(vertical: 16),
            minimumSize: const Size.fromHeight(48),
            shape: const RoundedRectangleBorder(),
          ),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 3,
          color: _selectedTab == index
              ? const Color(0xFF4E72E6)
              : Colors.transparent,
        ),
      ],
    ),
  );

  Widget _voiceSettings(CharacterOptions options) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '当前音色：${_voiceSummary(_voiceSelection)}',
            style: const TextStyle(color: Color(0xFF777C8D)),
          ),
          const SizedBox(height: 16),
          VoiceSelector(
            key: _voiceKey,
            keyPrefix: 'editor_${widget.character!.id}',
            options: options.presetVoices,
            initialValue: _voiceSelection,
            enabled: !_saving,
            onChanged: (value) => setState(() => _voiceSelection = value),
          ),
        ],
      ),
    ),
  );

  Widget _promptSettings() => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const Key('character_prompt_profile'),
            controller: _promptController,
            enabled: !_saving,
            minLines: 7,
            maxLines: 12,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: '角色内置提示词',
              hintText: '描述角色的身份、语气和回复方式',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value ?? '').trim().runes.length > 2000
                ? '角色内置提示词不能超过 2000 个字'
                : null,
          ),
          const SizedBox(height: 8),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Color(0xFF9A6A00),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '请勿加入个人隐私、危险指令或不适合儿童的内容。',
                  style: TextStyle(color: Color(0xFF775500), height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('restore_default_prompt'),
            onPressed: _saving
                ? null
                : () => setState(
                    () => _promptController.text = _defaultPrompt(
                      widget.character!,
                    ),
                  ),
            icon: const Icon(Icons.restore_rounded),
            label: const Text('恢复默认'),
          ),
        ],
      ),
    ),
  );

  Widget _nameField() => TextFormField(
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
  );

  Widget _subtitleField({required String label}) => TextFormField(
    key: const Key('character_subtitle'),
    controller: _subtitleController,
    enabled: !_saving,
    maxLength: 30,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    validator: (value) =>
        (value ?? '').trim().runes.length > 30 ? '一句话介绍不能超过 30 个字' : null,
  );

  Widget _descriptionField() => TextFormField(
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
    validator: (value) =>
        (value ?? '').trim().runes.length > 200 ? '补充描述不能超过 200 个字' : null,
  );

  Widget _saveButton(CharacterOptions options, {required bool editMode}) =>
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
        label: Text(
          _saving
              ? '正在保存…'
              : editMode
              ? '保存角色设置'
              : '保存角色',
        ),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      );

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    ),
  );

  static String _voiceSummary(VoiceSelection voice) => switch (voice.mode) {
    VoiceMode.preset => '预置音色 · ${voice.presetVoice}',
    VoiceMode.voiceDesign => '音色设计',
    VoiceMode.voiceClone => '音色克隆 · ${voice.referenceName ?? '参考音频'}',
  };
}

class _MyCharacterBadge extends StatelessWidget {
  const _MyCharacterBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFF5B7CFA).withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Text(
      '我的角色',
      style: TextStyle(
        color: Color(0xFF4E72E6),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
