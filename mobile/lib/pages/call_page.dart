import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../audio/audio_capture.dart';
import '../audio/audio_player.dart';
import '../audio/pcm_vad.dart';
import '../controllers/call_controller.dart';
import '../controllers/call_state.dart';
import '../models/character.dart';
import '../protocol/voice_event.dart';
import '../websocket/voice_socket.dart';
import '../widgets/call_avatar.dart';
import '../widgets/hangup_button.dart';

class CallPage extends StatefulWidget {
  const CallPage({
    required this.character,
    this.controller,
    this.autoConnect = true,
    super.key,
  });

  final Character character;
  final CallController? controller;
  final bool autoConnect;

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> with WidgetsBindingObserver {
  late final CallController _controller;
  late final bool _ownsController;
  late final AudioCapture _capture;
  late final PcmVad _vad;
  late final PcmAudioPlayer _player;
  late CallViewState _viewState;
  void Function()? _removeStateListener;
  StreamSubscription<Uint8List>? _captureSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<VoiceEvent>? _eventSubscription;
  final Uuid _uuid = const Uuid();
  Future<void> _audioWork = Future<void>.value();
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        CallController(character: widget.character, socket: VoiceSocket());
    _capture = AudioCapture();
    _vad = PcmVad();
    _player = PcmAudioPlayer();
    _viewState = _controller.state;
    _removeStateListener = _controller.addListener((state) {
      if (mounted) setState(() => _viewState = state);
    });
    _audioSubscription = _controller.assistantAudio.listen((chunk) {
      _audioWork = _audioWork.then((_) => _player.feed(chunk));
    });
    _eventSubscription = _controller.processedEvents.listen(_handleVoiceEvent);
    if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  Future<void> _connect() async {
    if (!await _capture.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要麦克风权限才能打电话')),
      );
      Navigator.of(context).pop();
      return;
    }
    await _controller.connect(Uri.parse(defaultVoiceServerUrl));
  }

  void _handleVoiceEvent(VoiceEvent event) {
    switch (event) {
      case AssistantAudioStart(:final sampleRate):
        _audioWork = _audioWork.then((_) async {
          await _stopListening();
          await _player.start(sampleRate);
        });
        break;
      case AssistantAudioEnd():
        _audioWork = _audioWork.then((_) async {
          await _player.finish();
          if (_controller.state.phase == CallPhase.listening) {
            await _startListening();
          }
        });
        break;
      case TurnErrorEvent(:final recoverable):
        if (recoverable) {
          _audioWork = _audioWork.then((_) => _startListening());
        }
        break;
      default:
        break;
    }
  }

  Future<void> _startListening() async {
    if (_ending || _captureSubscription != null ||
        _controller.state.phase != CallPhase.listening) {
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

  Future<void> _endCall() async {
    if (_ending) return;
    _ending = true;
    await _stopListening();
    await _player.stop();
    await _controller.hangUp();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      unawaited(_endCall());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeStateListener?.call();
    unawaited(_captureSubscription?.cancel());
    unawaited(_audioSubscription?.cancel());
    unawaited(_eventSubscription?.cancel());
    unawaited(_capture.dispose());
    unawaited(_player.dispose());
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.character.themeColor;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_endCall());
      },
      child: Scaffold(
        backgroundColor: color,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 34),
            child: Column(
              children: [
                Text(
                  '${widget.character.name} · AI角色',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDuration(_viewState.elapsed),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 17,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                CallAvatar(character: widget.character, phase: _viewState.phase),
                const SizedBox(height: 38),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _viewState.statusText(widget.character.name),
                    key: ValueKey(_viewState.phase),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _MicrophoneStatus(active: _viewState.microphoneEnabled),
                const Spacer(),
                HangupButton(onPressed: () => unawaited(_endCall())),
              ],
            ),
          ),
        ),
      ),
    );
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
          Icon(active ? Icons.mic_rounded : Icons.mic_off_rounded,
              color: Colors.white, size: 19),
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
