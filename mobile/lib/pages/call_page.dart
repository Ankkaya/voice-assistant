import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../audio/audio_capture.dart';
import '../audio/audio_player.dart';
import '../audio/hangup_tone_player.dart';
import '../audio/pcm_vad.dart';
import '../audio/ringtone_player.dart';
import '../controllers/call_controller.dart';
import '../controllers/call_state.dart';
import '../models/character.dart';
import '../models/voice_selection.dart';
import '../protocol/voice_event.dart';
import '../websocket/voice_socket.dart';
import '../widgets/call_avatar.dart';
import '../widgets/character_avatar_image.dart';
import '../widgets/hangup_button.dart';
import '../widgets/incoming_call_actions.dart';

enum CallPageResult { ended, editCharacter }

class CallPage extends StatefulWidget {
  const CallPage({
    required this.character,
    this.controller,
    this.autoConnect = true,
    this.incomingCall = true,
    this.voiceSelection = const VoiceSelection(mode: VoiceMode.preset),
    this.audioPlayer,
    this.audioCleanupOverride,
    this.hangupTonePlaybackOverride,
    super.key,
  });

  final Character character;
  final CallController? controller;
  final bool autoConnect;
  final bool incomingCall;
  final VoiceSelection voiceSelection;
  @visibleForTesting
  final PcmAudioPlayer? audioPlayer;
  @visibleForTesting
  final Future<void> Function()? audioCleanupOverride;
  @visibleForTesting
  final Future<void> Function()? hangupTonePlaybackOverride;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> with WidgetsBindingObserver {
  static const _callSystemUiOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  late final CallController _controller;
  late final bool _ownsController;
  late final AudioCapture _capture;
  late final PcmVad _vad;
  late final PcmAudioPlayer _player;
  late final RingtonePlayer _ringtone;
  HangupTonePlayer? _hangupTone;
  late CallViewState _viewState;
  void Function()? _removeStateListener;
  StreamSubscription<Uint8List>? _captureSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<VoiceEvent>? _eventSubscription;
  final Uuid _uuid = const Uuid();
  Future<void> _audioWork = Future<void>.value();
  Future<void>? _playbackStopFuture;
  bool _ending = false;
  bool _resourcesDisposed = false;
  late bool _accepted;

  @override
  void initState() {
    super.initState();
    unawaited(_setSystemUiMode(SystemUiMode.edgeToEdge));
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        CallController(character: widget.character, socket: VoiceSocket());
    _capture = AudioCapture();
    _vad = PcmVad();
    _player = widget.audioPlayer ?? PcmAudioPlayer();
    _ringtone = RingtonePlayer();
    if (widget.hangupTonePlaybackOverride == null) {
      _hangupTone = HangupTonePlayer();
    }
    _accepted = !widget.incomingCall;
    _viewState = _controller.viewState;
    _removeStateListener = _controller.addListener((state) {
      if (!mounted) return;
      setState(() => _viewState = state);
      if (state.connectionLost) unawaited(_endCall());
    });
    _audioSubscription = _controller.assistantAudio.listen((chunk) {
      _audioWork = _audioWork.then((_) async {
        if (_ending) return;
        await _player.feed(chunk);
      });
    });
    _eventSubscription = _controller.processedEvents.listen(_handleVoiceEvent);
    if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.incomingCall) {
          unawaited(_startRinging());
        } else {
          unawaited(_connect());
        }
      });
    }
  }

  Future<void> _startRinging() async {
    try {
      await _ringtone.start();
    } on Object {
      // The incoming call remains answerable if audio output is unavailable.
    }
  }

  Future<void> _acceptCall() async {
    if (_accepted || _ending) return;
    setState(() => _accepted = true);
    await _ringtone.dispose();
    await _connect();
  }

  Future<void> _connect() async {
    if (!await _capture.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('需要麦克风权限才能打电话')));
      await _endCall();
      return;
    }
    await _controller.connect(
      Uri.parse(defaultVoiceServerUrl),
      voiceSelection: widget.voiceSelection,
    );
  }

  void _handleVoiceEvent(VoiceEvent event) {
    switch (event) {
      case AssistantAudioStart(:final sampleRate):
        _audioWork = _audioWork.then((_) async {
          if (_ending) return;
          await _stopListening();
          if (_ending) return;
          await _player.start(sampleRate);
        });
        break;
      case AssistantAudioEnd():
        _audioWork = _audioWork.then((_) async {
          if (_ending) return;
          await _player.finish();
          if (_ending) return;
          if (_controller.viewState.phase == CallPhase.listening) {
            await _startListening();
          }
        });
        break;
      case TurnErrorEvent(:final recoverable):
        if (recoverable) {
          _audioWork = _audioWork.then((_) async {
            if (_ending) return;
            await _startListening();
          });
        }
        break;
      default:
        break;
    }
  }

  Future<void> _startListening() async {
    if (_ending ||
        _captureSubscription != null ||
        _controller.viewState.phase != CallPhase.listening) {
      return;
    }
    _vad.reset();
    final frames = await _capture.start();
    _captureSubscription = frames.listen(_processFrame);
  }

  void _processFrame(Uint8List frame) {
    for (final action in _vad.process(frame)) {
      switch (action) {
        case SpeechStart():
          _controller.startUserTurn(_uuid.v4());
          break;
        case VadAudio(:final bytes):
          _controller.sendUserAudio(bytes);
          break;
        case SpeechCommit():
          _controller.commitUserTurn();
          unawaited(_stopListening());
          break;
        case VadDiscard():
          break;
      }
    }
  }

  Future<void> _stopListening() async {
    final subscription = _captureSubscription;
    _captureSubscription = null;
    await subscription?.cancel();
    await _capture.stop();
    _vad.reset();
  }

  Future<void> _ignoreFailure(Future<void> Function() operation) async {
    try {
      await operation();
    } on Object {
      // Ending a call must not be blocked by an unavailable audio resource.
    }
  }

  Future<void> _endCall({
    CallPageResult result = CallPageResult.ended,
    bool playHangupTone = false,
  }) async {
    if (_ending) return;
    _ending = true;
    final playbackStopped = _stopPlaybackImmediately();

    final audioSubscription = _audioSubscription;
    _audioSubscription = null;
    final eventSubscription = _eventSubscription;
    _eventSubscription = null;
    unawaited(
      _ignoreFailure(() async {
        await audioSubscription?.cancel();
      }),
    );
    unawaited(
      _ignoreFailure(() async {
        await eventSubscription?.cancel();
      }),
    );
    unawaited(_ignoreFailure(_controller.hangUp));
    unawaited(
      _ignoreFailure(
        widget.audioCleanupOverride?.call ?? _disposeAudioResources,
      ),
    );
    if (playHangupTone) {
      unawaited(
        playbackStopped.then(
          (_) => _ignoreFailure(
            widget.hangupTonePlaybackOverride?.call ?? _hangupTone!.play,
          ),
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _disposeAudioResources() async {
    if (_resourcesDisposed) return;
    _resourcesDisposed = true;
    await _stopPlaybackImmediately();
    await _stopListening();
    try {
      await _audioWork;
    } on Object {
      // A failed playback task must not prevent the next call from cleaning up.
    }
    await _ringtone.dispose();
    await _player.dispose();
    await _capture.dispose();
  }

  Future<void> _stopPlaybackImmediately() {
    return _playbackStopFuture ??= _ignoreFailure(_player.stop);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_endCall());
    }
  }

  @override
  void dispose() {
    unawaited(
      _setSystemUiMode(SystemUiMode.manual, overlays: SystemUiOverlay.values),
    );
    WidgetsBinding.instance.removeObserver(this);
    _removeStateListener?.call();
    unawaited(_captureSubscription?.cancel());
    unawaited(_audioSubscription?.cancel());
    unawaited(_eventSubscription?.cancel());
    if (!_resourcesDisposed) unawaited(_disposeAudioResources());
    unawaited(_hangupTone?.dispose());
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_endCall());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 44, sigmaY: 44),
              child: Transform.scale(
                scale: 1.25,
                child: CharacterAvatarImage(
                  avatar: widget.character.avatar,
                  fallbackColor: widget.character.themeColor,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            ColoredBox(color: Colors.black.withValues(alpha: 0.58)),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 28, 28, 34),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Spacer(flex: 2),
                        CallAvatar(
                          character: widget.character,
                          phase: _viewState.phase,
                        ),
                        const SizedBox(height: 30),
                        Text(
                          widget.character.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: Text(
                            _accepted
                                ? _viewState.statusText(widget.character.name)
                                : 'AI 角色来电',
                            key: ValueKey((_accepted, _viewState.phase)),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_accepted) ...[
                          Text(
                            _formatDuration(_viewState.elapsed),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 16,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _MicrophoneStatus(
                            active: _viewState.microphoneEnabled,
                          ),
                        ] else
                          Text(
                            '正在呼叫你…',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
                              fontSize: 16,
                            ),
                          ),
                        const Spacer(flex: 3),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _accepted
                              ? widget.character.isCustom &&
                                        _viewState.phase == CallPhase.error &&
                                        _viewState.canEditCharacter
                                    ? Column(
                                        key: const ValueKey(
                                          'character_error_actions',
                                        ),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          FilledButton.icon(
                                            key: const Key(
                                              'edit_character_after_error',
                                            ),
                                            onPressed: () => _endCall(
                                              result:
                                                  CallPageResult.editCharacter,
                                            ),
                                            icon: const Icon(
                                              Icons.edit_rounded,
                                            ),
                                            label: const Text('编辑角色'),
                                          ),
                                          const SizedBox(height: 10),
                                          TextButton(
                                            key: const Key(
                                              'back_to_characters_after_error',
                                            ),
                                            onPressed: () =>
                                                unawaited(_endCall()),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('返回角色列表'),
                                          ),
                                        ],
                                      )
                                    : HangupButton(
                                        key: const ValueKey(
                                          'active_call_actions',
                                        ),
                                        onPressed: () => unawaited(
                                          _endCall(playHangupTone: true),
                                        ),
                                      )
                              : IncomingCallActions(
                                  key: const ValueKey('incoming_call_actions'),
                                  onDecline: () => unawaited(_endCall()),
                                  onAccept: () => unawaited(_acceptCall()),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _callSystemUiOverlayStyle,
      child: page,
    );
  }

  Future<void> _setSystemUiMode(
    SystemUiMode mode, {
    List<SystemUiOverlay>? overlays,
  }) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(mode, overlays: overlays);
    } on Object {
      // System UI calls are unavailable in widget tests and should not block a call.
    }
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _MicrophoneStatus extends StatelessWidget {
  const _MicrophoneStatus({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: active ? 1 : 0.45,
      duration: const Duration(milliseconds: 180),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.mic_rounded : Icons.mic_off_rounded,
            color: Colors.white,
            size: 19,
          ),
          const SizedBox(width: 7),
          Text(
            active ? '麦克风正在聆听' : '麦克风已暂停',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
