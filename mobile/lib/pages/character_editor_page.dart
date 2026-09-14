import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/character_catalog_controller.dart';
import '../models/character.dart';
import '../models/character_options.dart';
import '../models/voice_selection.dart';
import '../services/character_suggestion_service.dart';
import '../theme/app_colors.dart';
import '../widgets/character_avatar_image.dart';
import '../widgets/character_avatar_picker.dart';
import '../widgets/character_profile_fields.dart';
import '../widgets/voice_selector.dart';

class CharacterEditorPage extends ConsumerStatefulWidget {
  const CharacterEditorPage({
    this.character,
    this.avatarPicker,
    this.options,
    this.onSave,
    this.onDelete,
    this.suggestionService,
    super.key,
  });

  final Character? character;
  final AvatarPicker? avatarPicker;
  final CharacterOptions? options;
  final Future<Character> Function(CustomCharacterDraft draft)? onSave;
  final Future<void> Function(Character character)? onDelete;
  final CharacterSuggestionService? suggestionService;

  @override
  ConsumerState<CharacterEditorPage> createState() =>
      _CharacterEditorPageState();
}

class _CharacterEditorPageState extends ConsumerState<CharacterEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _voiceKey = GlobalKey<VoiceSelectorState>();
  final _scrollController = ScrollController();
  final _basicSectionKey = GlobalKey();
  final _profileSectionKey = GlobalKey();
  final _otherSectionKey = GlobalKey();
  final _voiceSectionKey = GlobalKey();
  late final CharacterSuggestionService _suggestionService;
  late final bool _ownsSuggestionService;
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
  bool _deleting = false;
  CharacterSuggestionField? _suggestingField;
  String _activeSection = '基本信息';
  String? _identityError;
  String? _traitsError;

  bool get _isEditing => widget.character != null;
  bool get _isBuiltIn => widget.character?.isCustom == false;

  @override
  void initState() {
    super.initState();
    _ownsSuggestionService = widget.suggestionService == null;
    _suggestionService =
        widget.suggestionService ?? CharacterSuggestionService();
    _scrollController.addListener(_updateActiveSection);
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActiveSection());
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
    _scrollController.removeListener(_updateActiveSection);
    _scrollController.dispose();
    if (_ownsSuggestionService) _suggestionService.close();
    super.dispose();
  }

  static String _defaultPrompt(Character character) {
    final description = character.profile?.description.trim() ?? '';
    final detail = description.isEmpty
        ? character.displaySubtitle
        : description;
    return '你是${character.name}，$detail。与3到6岁儿童对话时使用简短、积极、易懂的中文，保持温暖、耐心，并鼓励孩子提问。';
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
    final voiceValid = _voiceKey.currentState?.validate() ?? false;
    if (_isBuiltIn) {
      if (!voiceValid) return;
      final selectedVoice = _voiceKey.currentState!.value;
      setState(() => _saving = true);
      try {
        await ref
            .read(charactersProvider.notifier)
            .saveVoice(widget.character!.id, selectedVoice);
        if (mounted) Navigator.of(context).pop(widget.character);
      } on Object {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('音色设置保存失败，请重试')));
      }
      return;
    }

    final formValid = _formKey.currentState?.validate() ?? false;
    final identityValid = (_identityId ?? '').isNotEmpty;
    final traitsValid = _traitIds.isNotEmpty;
    setState(() {
      _identityError = identityValid ? null : '请选择角色身份';
      _traitsError = traitsValid ? null : '至少选择一个性格';
    });
    if (!formValid || !identityValid || !traitsValid || !voiceValid) return;

    final selectedVoice = _voiceKey.currentState!.value;
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
      promptProfile: _promptController.text.trim(),
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
        appBar: AppBar(title: Text(_pageTitle)),
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
    if (options.presetVoices.isEmpty &&
        _voiceSelection.mode == VoiceMode.preset) {
      return Scaffold(
        appBar: AppBar(title: Text(_pageTitle)),
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
      backgroundColor: !_isEditing ? AppColors.background : null,
      appBar: AppBar(
        title: Text(_pageTitle),
        centerTitle: !_isEditing ? false : null,
        backgroundColor: !_isEditing ? Colors.white : null,
        foregroundColor: !_isEditing ? AppColors.textPrimary : null,
        surfaceTintColor: !_isEditing ? Colors.transparent : null,
      ),
      bottomNavigationBar: Container(
        decoration: !_isEditing
            ? const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
              )
            : null,
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isEditing)
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).maybePop(),
                        style: TextButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor: const Color(0xFFF3F4F6),
                          foregroundColor: AppColors.textSecondary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _saveButton(options)),
                  ],
                )
              else
                _saveButton(options),
              if (_isEditing && !_isBuiltIn) ...[
                const SizedBox(height: 8),
                _deleteButton(),
              ],
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _isBuiltIn
                  ? _builtInFields(options)
                  : !_isEditing
                  ? _creationFields(options)
                  : _customFields(options),
            ),
          ),
        ),
      ),
    );
  }

  String get _pageTitle {
    if (!_isEditing) return '新建角色';
    if (!_isBuiltIn) return _activeSection;
    return '${widget.character!.name}设置';
  }

  void _updateActiveSection() {
    if (!mounted || _isBuiltIn || !_isEditing) return;
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 1) {
      if (_activeSection != '音色设置') {
        setState(() => _activeSection = '音色设置');
      }
      return;
    }
    final threshold = MediaQuery.sizeOf(context).height * 0.36;
    var nextSection = '基本信息';
    final sections = <(String, GlobalKey)>[
      ('基本信息', _basicSectionKey),
      ('角色设定', _profileSectionKey),
      ('其他信息', _otherSectionKey),
      ('音色设置', _voiceSectionKey),
    ];
    for (final (label, key) in sections) {
      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      if (renderObject.localToGlobal(Offset.zero).dy <= threshold) {
        nextSection = label;
      }
    }
    if (nextSection != _activeSection) {
      setState(() => _activeSection = nextSection);
    }
  }

  List<Widget> _builtInFields(CharacterOptions options) => [
    _sectionCard([
      Row(
        children: [
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: widget.character!.themeColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: CharacterAvatarImage(
                avatar: widget.character!.avatar,
                fallbackColor: widget.character!.themeColor,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.character!.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.character!.displaySubtitle,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const _SystemCharacterBadge(),
        ],
      ),
      const SizedBox(height: 16),
      const _EditorHint(
        icon: Icons.lock_outline_rounded,
        text: '系统角色的形象与对话设定由应用统一维护，这里只调整当前角色的音色。',
      ),
    ]),
    const SizedBox(height: 24),
    _sectionTitle('音色设置'),
    _voiceSettings(options),
  ];

  List<Widget> _creationFields(CharacterOptions options) => [
    _creationCard('基本信息', [
      CharacterAvatarPicker(
        initialAvatar: _avatar,
        initialColorValue: _themeColorValue,
        picker: widget.avatarPicker,
        enabled: !_saving,
        centered: true,
        onChanged: (avatar, color) {
          _avatar = avatar;
          _themeColorValue = color;
        },
      ),
      const SizedBox(height: 24),
      _creationField(
        options,
        CharacterSuggestionField.name,
        _nameController,
        '角色名称',
        '给伙伴起个名字',
        20,
        required: true,
      ),
      const SizedBox(height: 20),
      _creationField(
        options,
        CharacterSuggestionField.subtitle,
        _subtitleController,
        '一句话介绍',
        '例如：一位充满好奇心的探险伙伴',
        30,
      ),
    ], badge: true),
    const SizedBox(height: 24),
    _creationCard('角色设定', [
      const Text(
        '为伙伴选择合适的身份和性格特征。',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      const SizedBox(height: 20),
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
      const SizedBox(height: 24),
      _creationField(
        options,
        CharacterSuggestionField.description,
        _descriptionController,
        '补充描述',
        '描述角色的外貌、习惯、背景故事等…',
        200,
        lines: 3,
      ),
    ]),
    const SizedBox(height: 24),
    _creationCard('对话与表达', [
      _creationField(
        options,
        CharacterSuggestionField.greeting,
        _greetingController,
        '开场白',
        '你好呀，我是星星船长！今天想聊什么呢？',
        120,
        lines: 3,
        required: true,
      ),
      const SizedBox(height: 20),
      _creationField(
        options,
        CharacterSuggestionField.promptProfile,
        _promptController,
        '补充对话设定',
        '例如：喜欢用太空冒险做比喻，遇到困难时先鼓励孩子再一起想办法。',
        2000,
        lines: 4,
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFAEF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF9E650D), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '请勿加入个人隐私、危险指令或不适合儿童的内容；儿童安全规则始终优先。',
                style: TextStyle(
                  color: Color(0xFF9E650D),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    ]),
    const SizedBox(height: 24),
    _creationCard('音色设置', [
      VoiceSelector(
        key: _voiceKey,
        keyPrefix: 'editor_new',
        options: options.presetVoices,
        initialValue: _voiceSelection,
        enabled: !_saving,
        segmented: true,
        onSuggestVoiceDescription: () =>
            _loadSuggestion(CharacterSuggestionField.voiceDescription, options),
        onChanged: (value) => setState(() => _voiceSelection = value),
      ),
    ]),
  ];

  Widget _creationCard(
    String title,
    List<Widget> children, {
    bool badge = false,
  }) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F6B5BD2),
          blurRadius: 12,
          offset: Offset(0, 2),
        ),
      ],
    ),
    child: Theme(
      data: Theme.of(context).copyWith(
        chipTheme: Theme.of(context).chipTheme.copyWith(
          backgroundColor: Colors.white,
          selectedColor: AppColors.surfaceTint,
          side: const BorderSide(color: AppColors.outline),
          shape: const StadiumBorder(),
          labelStyle: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          secondaryLabelStyle: const TextStyle(
            color: AppColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (badge) const _NewCharacterBadge(),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );

  Widget _creationField(
    CharacterOptions options,
    CharacterSuggestionField field,
    TextEditingController controller,
    String label,
    String hint,
    int limit, {
    int lines = 1,
    bool required = false,
  }) {
    final fieldKey = switch (field) {
      CharacterSuggestionField.name => 'character_name',
      CharacterSuggestionField.subtitle => 'character_subtitle',
      CharacterSuggestionField.description => 'character_description',
      CharacterSuggestionField.greeting => 'character_greeting',
      _ => 'character_prompt_profile',
    };
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.outline),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (required)
                    const TextSpan(
                      text: ' *',
                      style: TextStyle(color: Color(0xFFE84545)),
                    ),
                ],
              ),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            _suggestionButton(
              field: field,
              controller: controller,
              options: options,
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: Key(fieldKey),
          controller: controller,
          enabled: !_saving,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          maxLength: limit,
          style: const TextStyle(fontSize: 16, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            hintStyle: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
            contentPadding: const EdgeInsets.all(14),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            semanticCounterText: '最多 $limit 个字',
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (required && text.isEmpty) return '请输入$label';
            if (text.runes.length > limit) return '$label不能超过 $limit 个字';
            return null;
          },
        ),
      ],
    );
  }

  List<Widget> _customFields(CharacterOptions options) => [
    _sectionTitle('基本信息', key: _basicSectionKey),
    _sectionCard([
      Row(
        children: [
          _isEditing ? const _MyCharacterBadge() : const _NewCharacterBadge(),
          const Spacer(),
          Text(
            '${_nameController.text.runes.length}/20',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
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
      if (!_isEditing) ...[
        const SizedBox(height: 8),
        _suggestionButton(
          field: CharacterSuggestionField.name,
          controller: _nameController,
          options: options,
        ),
      ],
      const SizedBox(height: 12),
      _subtitleField(label: '一句话介绍（可选）'),
      if (!_isEditing) ...[
        const SizedBox(height: 8),
        _suggestionButton(
          field: CharacterSuggestionField.subtitle,
          controller: _subtitleController,
          options: options,
        ),
      ],
    ]),
    const SizedBox(height: 24),
    _sectionTitle('角色设定', key: _profileSectionKey),
    _sectionCard([
      const _EditorHint(
        icon: Icons.auto_awesome_rounded,
        text: '身份、性格、兴趣和补充描述会共同决定角色在问答中的表达方式。',
      ),
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
        onInterestsChanged: (value) => setState(() => _interestIds = value),
      ),
      const SizedBox(height: 16),
      _descriptionField(),
      if (!_isEditing) ...[
        const SizedBox(height: 8),
        _suggestionButton(
          field: CharacterSuggestionField.description,
          controller: _descriptionController,
          options: options,
        ),
      ],
    ]),
    const SizedBox(height: 24),
    _sectionTitle('其他信息', key: _otherSectionKey),
    _sectionCard([
      _greetingField(),
      if (!_isEditing) ...[
        const SizedBox(height: 8),
        _suggestionButton(
          field: CharacterSuggestionField.greeting,
          controller: _greetingController,
          options: options,
        ),
      ],
      const SizedBox(height: 18),
      _promptFields(options),
    ]),
    const SizedBox(height: 24),
    _sectionTitle('音色设置', key: _voiceSectionKey),
    _voiceSettings(options),
  ];

  Widget _sectionCard(List<Widget> children) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: AppColors.outline),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget _voiceSettings(CharacterOptions options) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: AppColors.outline),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '当前音色：${_voiceSummary(_voiceSelection)}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          VoiceSelector(
            key: _voiceKey,
            keyPrefix: 'editor_${widget.character?.id ?? 'new'}',
            options: options.presetVoices,
            initialValue: _voiceSelection,
            enabled: !_saving,
            segmented: true,
            onSuggestVoiceDescription: !_isEditing
                ? () => _loadSuggestion(
                    CharacterSuggestionField.voiceDescription,
                    options,
                  )
                : null,
            onChanged: (value) => setState(() => _voiceSelection = value),
          ),
        ],
      ),
    ),
  );

  Widget _greetingField() => TextFormField(
    key: const Key('character_greeting'),
    controller: _greetingController,
    enabled: !_saving,
    minLines: 2,
    maxLines: 4,
    maxLength: 120,
    decoration: const InputDecoration(
      labelText: '接通电话时的开场白',
      hintText: '例如：你好呀，我是星星船长！今天想聊什么呢？',
      border: OutlineInputBorder(),
      alignLabelWithHint: true,
    ),
    validator: (value) {
      final text = value?.trim() ?? '';
      if (text.isEmpty) return '请输入开场白';
      if (text.runes.length > 120) return '开场白不能超过 120 个字';
      return null;
    },
  );

  Widget _promptFields(CharacterOptions options) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        key: const Key('character_prompt_profile'),
        controller: _promptController,
        enabled: !_saving,
        minLines: 5,
        maxLines: 10,
        maxLength: 2000,
        decoration: const InputDecoration(
          labelText: '补充对话设定（可选）',
          hintText: '例如：喜欢用太空冒险做比喻，遇到困难时先鼓励孩子再一起想办法。',
          helperText: '会和身份、性格、兴趣一起用于生成角色问答提示词',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
        validator: (value) => (value ?? '').trim().runes.length > 2000
            ? '补充对话设定不能超过 2000 个字'
            : null,
      ),
      const SizedBox(height: 8),
      if (!_isEditing) ...[
        _suggestionButton(
          field: CharacterSuggestionField.promptProfile,
          controller: _promptController,
          options: options,
        ),
        const SizedBox(height: 12),
      ],
      const _EditorHint(
        icon: Icons.shield_outlined,
        text: '请勿加入个人隐私、危险指令或不适合儿童的内容；儿童安全规则始终优先。',
      ),
    ],
  );

  Widget _suggestionButton({
    required CharacterSuggestionField field,
    required TextEditingController controller,
    required CharacterOptions options,
  }) {
    final loading = _suggestingField == field;
    return OutlinedButton.icon(
      key: Key('suggest_${field.wireName}'),
      onPressed: _saving || _suggestingField != null
          ? null
          : () => _fillSuggestion(field, controller, options),
      icon: loading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome_rounded, size: 18),
      label: Text(loading ? '正在生成…' : 'AI 生成建议'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        backgroundColor: AppColors.surfaceTint,
        foregroundColor: AppColors.primary,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }

  Future<void> _fillSuggestion(
    CharacterSuggestionField field,
    TextEditingController controller,
    CharacterOptions options,
  ) async {
    final suggestion = await _loadSuggestion(field, options);
    if (suggestion == null || !mounted) return;
    controller.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
  }

  Future<String?> _loadSuggestion(
    CharacterSuggestionField field,
    CharacterOptions options,
  ) async {
    if (_suggestingField != null) return null;
    setState(() => _suggestingField = field);
    try {
      return await _suggestionService.suggest(
        field: field,
        formContext: _suggestionContext(options),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时生成不了建议，请稍后再试')));
      }
      return null;
    } finally {
      if (mounted) setState(() => _suggestingField = null);
    }
  }

  Map<String, Object> _suggestionContext(CharacterOptions options) {
    String optionLabel(List<CharacterOption> values, String? id) =>
        values
            .where((option) => option.id == id)
            .map((option) => option.label)
            .firstOrNull ??
        '';
    List<String> optionLabels(List<CharacterOption> values, Set<String> ids) =>
        values
            .where((option) => ids.contains(option.id))
            .map((option) => option.label)
            .toList(growable: false);

    return {
      'name': _nameController.text.trim(),
      'subtitle': _subtitleController.text.trim(),
      'identity': optionLabel(options.identities, _identityId),
      'traits': optionLabels(options.traits, _traitIds),
      'interests': optionLabels(options.interests, _interestIds),
      'description': _descriptionController.text.trim(),
      'greeting': _greetingController.text.trim(),
      'promptProfile': _promptController.text.trim(),
      'voiceDescription': _voiceSelection.voiceDescription?.trim() ?? '',
    };
  }

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

  Widget _saveButton(CharacterOptions options) => FilledButton.icon(
    key: const Key('save_character'),
    onPressed: _saving || _deleting ? null : () => _save(options),
    icon: _saving
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Icon(_isEditing ? Icons.save_rounded : Icons.check_circle_rounded),
    label: Text(_saving ? '正在保存…' : _saveButtonLabel),
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );

  Widget _deleteButton() => OutlinedButton.icon(
    key: const Key('delete_character_editor'),
    onPressed: _saving || _deleting ? null : _confirmDelete,
    icon: _deleting
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.delete_outline_rounded),
    label: Text(_deleting ? '正在删除…' : '删除角色'),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      foregroundColor: Theme.of(context).colorScheme.error,
      side: BorderSide(color: Theme.of(context).colorScheme.error),
    ),
  );

  Future<void> _confirmDelete() async {
    final character = widget.character;
    if (character == null || !character.isCustom || _saving || _deleting) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${character.name}”？'),
        content: const Text('角色和保存在本机的头像、参考音频将一并删除，删除后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('confirm_delete_character_editor'),
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      if (widget.onDelete != null) {
        await widget.onDelete!(character);
      } else {
        await ref.read(charactersProvider.notifier).delete(character.id);
      }
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('角色删除失败，请稍后重试')));
    }
  }

  String get _saveButtonLabel {
    if (_isBuiltIn) return '保存音色设置';
    return _isEditing ? '保存角色设置' : '创建角色';
  }

  Widget _sectionTitle(String text, {Key? key}) => Padding(
    key: key,
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
      color: AppColors.primary.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Text(
      '我的角色',
      style: TextStyle(
        color: AppColors.primaryDeep,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _NewCharacterBadge extends StatelessWidget {
  const _NewCharacterBadge();

  @override
  Widget build(BuildContext context) => const _EditorBadge(
    label: '新伙伴',
    foreground: Color(0xFF9E650D),
    background: Color(0xFFFFF1DB),
  );
}

class _SystemCharacterBadge extends StatelessWidget {
  const _SystemCharacterBadge();

  @override
  Widget build(BuildContext context) => const _EditorBadge(
    label: '系统角色',
    foreground: AppColors.textSecondary,
    background: AppColors.surfaceTint,
  );
}

class _EditorBadge extends StatelessWidget {
  const _EditorBadge({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _EditorHint extends StatelessWidget {
  const _EditorHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColors.primaryDeep),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
