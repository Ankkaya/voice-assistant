enum VoiceMode { preset, voiceDesign, voiceClone }

class VoiceSelection {
  const VoiceSelection({
    required this.mode,
    this.voiceDescription,
    this.referencePath,
    this.referenceName,
    this.referenceId,
  });

  final VoiceMode mode;
  final String? voiceDescription;
  final String? referencePath;
  final String? referenceName;
  final String? referenceId;

  VoiceSelection withReferenceId(String value) => VoiceSelection(
    mode: mode,
    voiceDescription: voiceDescription,
    referencePath: referencePath,
    referenceName: referenceName,
    referenceId: value,
  );

  Map<String, Object>? toProtocolJson() {
    return switch (mode) {
      VoiceMode.preset => null,
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
}
