enum VoiceMode { preset, voiceDesign, voiceClone }

class VoiceSelection {
  const VoiceSelection({
    required this.mode,
    this.presetVoice,
    this.voiceDescription,
    this.referencePath,
    this.referenceName,
    this.referenceId,
    this.cloneAuthorized = false,
  });

  final VoiceMode mode;
  final String? presetVoice;
  final String? voiceDescription;
  final String? referencePath;
  final String? referenceName;
  final String? referenceId;
  final bool cloneAuthorized;

  VoiceSelection withReferenceId(String value) => VoiceSelection(
    mode: mode,
    presetVoice: presetVoice,
    voiceDescription: voiceDescription,
    referencePath: referencePath,
    referenceName: referenceName,
    referenceId: value,
    cloneAuthorized: cloneAuthorized,
  );

  Map<String, Object>? toProtocolJson({required bool includePreset}) {
    return switch (mode) {
      VoiceMode.preset =>
        includePreset ? {'mode': 'preset', 'voice': presetVoice!} : null,
      VoiceMode.voiceDesign => {
        'mode': 'voice_design',
        'voiceDescription': voiceDescription!.trim(),
      },
      VoiceMode.voiceClone => {
        'mode': 'voice_clone',
        'referenceId': referenceId!,
      },
    };
  }

  Map<String, Object> toStorageJson() => switch (mode) {
    VoiceMode.preset => {'mode': 'preset', 'voice': presetVoice!},
    VoiceMode.voiceDesign => {
      'mode': 'voice_design',
      'voiceDescription': voiceDescription!.trim(),
    },
    VoiceMode.voiceClone => {
      'mode': 'voice_clone',
      'referencePath': referencePath!,
      if (referenceName != null) 'referenceName': referenceName!,
      'cloneAuthorized': cloneAuthorized,
    },
  };

  factory VoiceSelection.fromStorageJson(Map<String, Object?> json) {
    final mode = json['mode'];
    return switch (mode) {
      'preset' => VoiceSelection(
        mode: VoiceMode.preset,
        presetVoice: _requiredString(json, 'voice'),
      ),
      'voice_design' => VoiceSelection(
        mode: VoiceMode.voiceDesign,
        voiceDescription: _requiredString(json, 'voiceDescription'),
      ),
      'voice_clone' => _cloneFromStorage(json),
      final value => throw FormatException('Unknown voice mode: $value'),
    };
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key must be a non-empty string');
    }
    return value;
  }

  static VoiceSelection _cloneFromStorage(Map<String, Object?> json) {
    if (json['cloneAuthorized'] != true) {
      throw const FormatException('Stored voice clone is not authorized');
    }
    return VoiceSelection(
      mode: VoiceMode.voiceClone,
      referencePath: _requiredString(json, 'referencePath'),
      referenceName: json['referenceName'] as String?,
      cloneAuthorized: true,
    );
  }
}
