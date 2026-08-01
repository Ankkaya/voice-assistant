sealed class VoiceEvent {
  const VoiceEvent();

  factory VoiceEvent.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'session.ready' => SessionReady(
        sessionId: json['sessionId'] as String,
        maxDurationSeconds: (json['maxDurationSeconds'] as int?) ?? 600,
      ),
      'user.transcript' => UserTranscript(
        turnId: json['turnId'] as String,
        text: json['text'] as String,
      ),
      'assistant.thinking' => AssistantThinking(
        turnId: json['turnId'] as String,
      ),
      'assistant.audio.start' => AssistantAudioStart(
        turnId: json['turnId'] as String,
        encoding: json['encoding'] as String,
        sampleRate: json['sampleRate'] as int,
        channels: json['channels'] as int,
      ),
      'assistant.audio.end' => AssistantAudioEnd(
        turnId: json['turnId'] as String,
      ),
      'turn.error' => TurnErrorEvent(
        stage: json['stage'] as String,
        code: json['code'] as String,
        recoverable: json['recoverable'] as bool,
        message: json['message'] as String,
      ),
      'pong' => PongEvent(timestamp: json['timestamp'] as int),
      final type => throw FormatException('Unknown voice event: $type'),
    };
  }
}

final class SessionReady extends VoiceEvent {
  const SessionReady({
    required this.sessionId,
    required this.maxDurationSeconds,
  });
  final String sessionId;
  final int maxDurationSeconds;
}

final class UserTranscript extends VoiceEvent {
  const UserTranscript({required this.turnId, required this.text});
  final String turnId;
  final String text;
}

final class AssistantThinking extends VoiceEvent {
  const AssistantThinking({required this.turnId});
  final String turnId;
}

final class AssistantAudioStart extends VoiceEvent {
  const AssistantAudioStart({
    required this.turnId,
    this.encoding = 'pcm16le',
    this.sampleRate = 24000,
    this.channels = 1,
  });

  final String turnId;
  final String encoding;
  final int sampleRate;
  final int channels;
}

final class AssistantAudioEnd extends VoiceEvent {
  const AssistantAudioEnd({required this.turnId});
  final String turnId;
}

final class TurnErrorEvent extends VoiceEvent {
  const TurnErrorEvent({
    required this.stage,
    required this.code,
    required this.recoverable,
    required this.message,
  });

  final String stage;
  final String code;
  final bool recoverable;
  final String message;
}

final class PongEvent extends VoiceEvent {
  const PongEvent({required this.timestamp});
  final int timestamp;
}

abstract final class VoiceClientEvent {
  static Map<String, Object> sessionStart(
    String characterId, {
    Map<String, Object>? customCharacter,
    Map<String, Object>? voiceConfig,
  }) => {
    'type': 'session.start',
    'characterId': characterId,
    if (customCharacter != null) 'customCharacter': customCharacter,
    if (voiceConfig != null) 'voiceConfig': voiceConfig,
  };

  static Map<String, Object> audioStart(String turnId) => {
    'type': 'input.audio.start',
    'turnId': turnId,
  };

  static Map<String, Object> audioCommit(String turnId) => {
    'type': 'input.audio.commit',
    'turnId': turnId,
  };

  static Map<String, Object> sessionEnd() => {'type': 'session.end'};

  static Map<String, Object> ping(int timestamp) => {
    'type': 'ping',
    'timestamp': timestamp,
  };
}
