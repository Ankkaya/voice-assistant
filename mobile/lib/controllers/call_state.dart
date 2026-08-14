import 'package:flutter/foundation.dart';

enum CallPhase {
  connecting,
  ringing,
  assistantSpeaking,
  listening,
  userSpeaking,
  processing,
  error,
  ended,
}

@immutable
class CallViewState {
  static const connectionLostErrorCode = 'CONNECTION_LOST';

  const CallViewState({
    this.phase = CallPhase.connecting,
    this.elapsed = Duration.zero,
    this.currentTurnId,
    this.errorMessage,
    this.errorCode,
  });

  final CallPhase phase;
  final Duration elapsed;
  final String? currentTurnId;
  final String? errorMessage;
  final String? errorCode;

  bool get canEditCharacter => const {
    'INVALID_CHARACTER_CONFIG',
    'UNSUPPORTED_CHARACTER_OPTION',
    'UNSAFE_CHARACTER_CONFIG',
    'UNSUPPORTED_PRESET_VOICE',
    'VOICE_REFERENCE_NOT_FOUND',
  }.contains(errorCode);

  bool get microphoneEnabled =>
      phase == CallPhase.listening || phase == CallPhase.userSpeaking;

  bool get connectionLost =>
      phase == CallPhase.error && errorCode == connectionLostErrorCode;

  CallViewState copyWith({
    CallPhase? phase,
    Duration? elapsed,
    String? currentTurnId,
    bool clearTurnId = false,
    String? errorMessage,
    String? errorCode,
    bool clearError = false,
  }) {
    return CallViewState(
      phase: phase ?? this.phase,
      elapsed: elapsed ?? this.elapsed,
      currentTurnId: clearTurnId ? null : currentTurnId ?? this.currentTurnId,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      errorCode: clearError ? null : errorCode ?? this.errorCode,
    );
  }

  String statusText(String characterName) => switch (phase) {
    CallPhase.connecting => '正在连接',
    CallPhase.ringing => '正在呼叫$characterName',
    CallPhase.assistantSpeaking => '$characterName正在说话',
    CallPhase.listening => '你可以说话啦',
    CallPhase.userSpeaking => '我在听',
    CallPhase.processing => '$characterName正在想一想',
    CallPhase.error => errorMessage ?? '通话遇到了一点问题',
    CallPhase.ended => '通话已结束',
  };
}
