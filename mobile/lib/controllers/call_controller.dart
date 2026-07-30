import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/character.dart';
import '../protocol/voice_event.dart';
import '../websocket/voice_socket.dart';
import 'call_state.dart';

class CallController extends StateNotifier<CallViewState> {
  CallController({required this.character, required this.socket})
    : super(const CallViewState());

  final Character character;
  final VoiceSocketClient socket;
  StreamSubscription<VoiceEvent>? _eventSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _elapsedTimer;
  final _assistantAudio = StreamController<Uint8List>.broadcast();
  final _processedEvents = StreamController<VoiceEvent>.broadcast();

  Stream<Uint8List> get assistantAudio => _assistantAudio.stream;
  Stream<VoiceEvent> get processedEvents => _processedEvents.stream;
  CallViewState get viewState => state;

  Future<void> connect(Uri uri) async {
    state = state.copyWith(phase: CallPhase.connecting, clearError: true);
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await socket.connect(uri);
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
      state = state.copyWith(
        phase: CallPhase.error,
        errorMessage: '无法接通，请稍后再试',
      );
      return;
    }

    _eventSubscription = socket.events.listen(onEvent, onError: onSocketError);
    _audioSubscription = socket.audioChunks.listen(_assistantAudio.add);
    state = state.copyWith(phase: CallPhase.ringing);
    socket.sendEvent(VoiceClientEvent.sessionStart(character.id));
  }

  void onEvent(VoiceEvent event) {
    switch (event) {
      case SessionReady():
        _startElapsedTimer();
        state = state.copyWith(phase: CallPhase.ringing);
        break;
      case UserTranscript(:final turnId):
        if (!_matchesActiveTurn(turnId)) return;
        state = state.copyWith(phase: CallPhase.processing);
        break;
      case AssistantThinking(:final turnId):
        if (!_matchesActiveTurn(turnId)) return;
        state = state.copyWith(phase: CallPhase.processing);
        break;
      case AssistantAudioStart(:final turnId):
        if (!_matchesActiveTurn(turnId)) return;
        state = state.copyWith(
          phase: CallPhase.assistantSpeaking,
          currentTurnId: turnId,
          clearError: true,
        );
        break;
      case AssistantAudioEnd(:final turnId):
        if (!_matchesActiveTurn(turnId)) return;
        state = state.copyWith(phase: CallPhase.listening, clearTurnId: true);
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
    _processedEvents.add(event);
  }

  void onSocketError(Object error, [StackTrace? stackTrace]) {
    state = state.copyWith(phase: CallPhase.error, errorMessage: '通话中断了');
  }

  void startUserTurn(String turnId) {
    if (state.phase != CallPhase.listening) return;
    state = state.copyWith(
      phase: CallPhase.userSpeaking,
      currentTurnId: turnId,
    );
    socket.sendEvent(VoiceClientEvent.audioStart(turnId));
  }

  void sendUserAudio(Uint8List audio) {
    if (state.phase == CallPhase.userSpeaking) {
      socket.sendAudio(audio);
    }
  }

  void commitUserTurn() {
    final turnId = state.currentTurnId;
    if (state.phase != CallPhase.userSpeaking || turnId == null) return;
    socket.sendEvent(VoiceClientEvent.audioCommit(turnId));
    state = state.copyWith(phase: CallPhase.processing);
  }

  Future<void> hangUp() async {
    if (state.phase != CallPhase.ended) {
      try {
        socket.sendEvent(VoiceClientEvent.sessionEnd());
      } on StateError {
        // The socket may already be closed.
      }
    }
    await _shutdown();
    state = state.copyWith(phase: CallPhase.ended, clearTurnId: true);
  }

  Future<void> onLifecyclePaused() => hangUp();

  bool _matchesActiveTurn(String turnId) {
    final current = state.currentTurnId;
    if (turnId == 'greeting') {
      return current == null || current == turnId;
    }
    if (turnId == 'goodbye') {
      return true;
    }
    return current == turnId;
  }

  void _startElapsedTimer() {
    _elapsedTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(
        elapsed: state.elapsed + const Duration(seconds: 1),
      );
    });
  }

  Future<void> _shutdown() async {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    await _eventSubscription?.cancel();
    await _audioSubscription?.cancel();
    await socket.close();
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    unawaited(_eventSubscription?.cancel());
    unawaited(_audioSubscription?.cancel());
    unawaited(socket.close());
    unawaited(_assistantAudio.close());
    unawaited(_processedEvents.close());
    super.dispose();
  }
}

const defaultVoiceServerUrl = String.fromEnvironment(
  'VOICE_SERVER_URL',
  defaultValue: 'ws://10.0.2.2:8000/ws/voice',
);
