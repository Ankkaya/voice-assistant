import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/character.dart';
import '../protocol/voice_event.dart';
import '../websocket/voice_socket.dart';
import 'call_state.dart';

class CallController extends StateNotifier<CallViewState> {
  CallController({required this.character, required VoiceSocketClient socket})
      : _socket = socket,
        super(const CallViewState());

  final Character character;
  final VoiceSocketClient _socket;
  StreamSubscription<VoiceEvent>? _eventSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _elapsedTimer;
  final _assistantAudio = StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get assistantAudio => _assistantAudio.stream;

  Future<void> connect(Uri uri) async {
    state = state.copyWith(phase: CallPhase.connecting, clearError: true);
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _socket.connect(uri);
        lastError = null;
        break;
      } on Object catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
    if (lastError != null) {
      state = state.copyWith(phase: CallPhase.error, errorMessage: '无法接通，请稍后再试');
      return;
    }

    _eventSubscription = _socket.events.listen(onEvent, onError: onSocketError);
    _audioSubscription = _socket.audioChunks.listen(_assistantAudio.add);
    state = state.copyWith(phase: CallPhase.ringing);
    _socket.sendEvent(VoiceClientEvent.sessionStart(character.id));
  }

  void onEvent(VoiceEvent event) {
    switch (event) {
      case SessionReady():
        _startElapsedTimer();
        state = state.copyWith(phase: CallPhase.ringing);
        break;
      case UserTranscript(:final turnId):
        if (_isCurrentTurn(turnId)) {
          state = state.copyWith(phase: CallPhase.processing);
        }
        break;
      case AssistantThinking(:final turnId):
        if (_isCurrentTurn(turnId)) {
          state = state.copyWith(phase: CallPhase.processing);
        }
        break;
      case AssistantAudioStart(:final turnId):
        state = state.copyWith(
          phase: CallPhase.assistantSpeaking,
          currentTurnId: turnId,
          clearError: true,
        );
        break;
      case AssistantAudioEnd(:final turnId):
        if (_isCurrentTurn(turnId)) {
          state = state.copyWith(phase: CallPhase.listening, clearTurnId: true);
        }
        break;
      case TurnErrorEvent(:final recoverable, :final message):
        state = state.copyWith(
          phase: recoverable ? CallPhase.listening : CallPhase.error,
          errorMessage: message,
          clearTurnId: true,
        );
        break;
      case PongEvent():
        break;
    }
  }

  void onSocketError(Object error, [StackTrace? stackTrace]) {
    state = state.copyWith(phase: CallPhase.error, errorMessage: '通话中断了');
  }

  void startUserTurn(String turnId) {
    if (state.phase != CallPhase.listening) return;
    state = state.copyWith(phase: CallPhase.userSpeaking, currentTurnId: turnId);
    _socket.sendEvent(VoiceClientEvent.audioStart(turnId));
  }

  void sendUserAudio(Uint8List audio) {
    if (state.phase == CallPhase.userSpeaking) {
      _socket.sendAudio(audio);
    }
  }

  void commitUserTurn() {
    final turnId = state.currentTurnId;
    if (state.phase != CallPhase.userSpeaking || turnId == null) return;
    _socket.sendEvent(VoiceClientEvent.audioCommit(turnId));
    state = state.copyWith(phase: CallPhase.processing);
  }

  Future<void> hangUp() async {
    if (state.phase != CallPhase.ended) {
      try {
        _socket.sendEvent(VoiceClientEvent.sessionEnd());
      } on StateError {
        // The socket may already be closed.
      }
    }
    await _shutdown();
    state = state.copyWith(phase: CallPhase.ended, clearTurnId: true);
  }

  Future<void> onLifecyclePaused() => hangUp();

  bool _isCurrentTurn(String turnId) {
    final current = state.currentTurnId;
    return current == null || current == turnId || turnId == 'greeting' || turnId == 'goodbye';
  }

  void _startElapsedTimer() {
    _elapsedTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
    });
  }

  Future<void> _shutdown() async {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    await _eventSubscription?.cancel();
    await _audioSubscription?.cancel();
    await _socket.close();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    unawaited(_audioSubscription?.cancel());
    unawaited(_socket.close());
    unawaited(_assistantAudio.close());
    super.dispose();
  }
}

const defaultVoiceServerUrl = String.fromEnvironment(
  'VOICE_SERVER_URL',
  defaultValue: 'ws://10.0.2.2:8000/ws/voice',
);
