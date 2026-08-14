import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../audio/voice_clone_recorder.dart';
import '../theme/app_colors.dart';

Future<VoiceCloneRecording?> showVoiceCloneRecordingSheet(
  BuildContext context, {
  VoiceCloneRecorder? recorder,
  VoiceClonePreviewPlayer? previewPlayer,
}) {
  final actualRecorder = recorder ?? RecordVoiceCloneRecorder();
  final actualPlayer = previewPlayer ?? FlutterSoundVoiceClonePreviewPlayer();
  return showModalBottomSheet<VoiceCloneRecording>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    builder: (_) => VoiceCloneRecordingSheet(
      recorder: actualRecorder,
      previewPlayer: actualPlayer,
    ),
  );
}

class VoiceCloneRecordingSheet extends StatefulWidget {
  const VoiceCloneRecordingSheet({
    required this.recorder,
    required this.previewPlayer,
    super.key,
  });

  final VoiceCloneRecorder recorder;
  final VoiceClonePreviewPlayer previewPlayer;

  @override
  State<VoiceCloneRecordingSheet> createState() =>
      _VoiceCloneRecordingSheetState();
}

enum _RecordingStage { ready, recording, review }

class _VoiceCloneRecordingSheetState extends State<VoiceCloneRecordingSheet>
    with WidgetsBindingObserver {
  _RecordingStage _stage = _RecordingStage.ready;
  StreamSubscription<double>? _levelSubscription;
  Timer? _timer;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  VoiceCloneRecording? _recording;
  String? _errorText;
  bool _busy = false;
  bool _playing = false;
  bool _accepted = false;
  bool _allowPop = false;

  bool get _isRecording => _stage == _RecordingStage.recording;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isRecording && state != AppLifecycleState.resumed) {
      unawaited(_stopRecording(interrupted: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_levelSubscription?.cancel());
    unawaited(widget.previewPlayer.dispose());
    if (!_accepted) unawaited(widget.recorder.cancel());
    unawaited(widget.recorder.dispose());
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      if (!await widget.recorder.requestPermission()) {
        if (!mounted) return;
        setState(() => _errorText = '需要麦克风权限才能录制声音');
        return;
      }
      await widget.recorder.start();
      if (!mounted) {
        await widget.recorder.cancel();
        return;
      }
      _startedAt = DateTime.now();
      _levelSubscription = widget.recorder.levels.listen((level) {
        if (mounted) setState(() => _level = level);
      });
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final startedAt = _startedAt;
        if (!mounted || startedAt == null) return;
        final elapsed = DateTime.now().difference(startedAt);
        if (elapsed >= voiceCloneMaximumDuration) {
          unawaited(_stopRecording());
        } else {
          setState(() => _elapsed = elapsed);
        }
      });
      setState(() {
        _stage = _RecordingStage.recording;
        _elapsed = Duration.zero;
        _level = 0;
      });
    } on Object {
      if (mounted) setState(() => _errorText = '录音启动失败，请重试');
      await widget.recorder.cancel();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording({bool interrupted = false}) async {
    if (!_isRecording || _busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    _timer = null;
    unawaited(_levelSubscription?.cancel());
    _levelSubscription = null;
    try {
      final recording = await widget.recorder.stop();
      if (recording.duration < voiceCloneMinimumDuration) {
        await widget.recorder.cancel();
        if (!mounted) return;
        setState(() {
          _stage = _RecordingStage.ready;
          _recording = null;
          _errorText = interrupted ? '录音已中断，请至少连续录制 5 秒' : '录音太短，请至少录制 5 秒';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _recording = recording;
        _elapsed = recording.duration;
        _stage = _RecordingStage.review;
        _errorText = interrupted ? '录音因应用进入后台而停止，请试听确认' : null;
      });
    } on Object {
      await widget.recorder.cancel();
      if (!mounted) return;
      setState(() {
        _stage = _RecordingStage.ready;
        _recording = null;
        _errorText = '录音生成失败，请重试';
      });
    } finally {
      _startedAt = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePreview() async {
    final recording = _recording;
    if (recording == null || _busy) return;
    if (_playing) {
      await widget.previewPlayer.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      await widget.previewPlayer.play(
        recording.path,
        onFinished: () {
          if (mounted) setState(() => _playing = false);
        },
      );
      if (mounted) setState(() => _playing = true);
    } on Object {
      if (mounted) setState(() => _errorText = '暂时无法试听，请重新录制或直接使用');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordAgain() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.previewPlayer.stop();
      await widget.recorder.cancel();
      if (!mounted) return;
      setState(() {
        _stage = _RecordingStage.ready;
        _recording = null;
        _elapsed = Duration.zero;
        _playing = false;
        _errorText = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDismiss() async {
    if (!_isRecording) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃本次录音？'),
        content: const Text('正在录制的内容不会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续录音'),
          ),
          FilledButton(
            key: const Key('discard_voice_recording'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  void _useRecording() {
    final recording = _recording;
    if (recording == null || _busy) return;
    _accepted = true;
    Navigator.pop(context, recording);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !_isRecording,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmDismiss() || !mounted) return;
        setState(() => _allowPop = true);
        Navigator.pop(this.context);
      },
      child: Material(
        color: AppColors.background,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.88,
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: _content(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      children: [
        IconButton(
          key: const Key('close_voice_recording'),
          tooltip: '关闭录音',
          onPressed: _busy
              ? null
              : () async {
                  if (await _confirmDismiss() && context.mounted) {
                    setState(() => _allowPop = true);
                    Navigator.pop(context);
                  }
                },
          icon: const Icon(Icons.close_rounded),
        ),
        Expanded(
          child: Text(
            '录制参考声音',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 48),
      ],
    ),
  );

  Widget _content(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _RecordingGuidance(),
      const SizedBox(height: 28),
      if (_stage == _RecordingStage.ready) _readyContent(context),
      if (_stage == _RecordingStage.recording) _recordingContent(context),
      if (_stage == _RecordingStage.review) _reviewContent(context),
      if (_errorText != null) ...[
        const SizedBox(height: 16),
        Text(
          _errorText!,
          key: const Key('voice_recording_error'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );

  Widget _readyContent(BuildContext context) => Column(
    children: [
      Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.mic_rounded,
          size: 48,
          color: AppColors.primary,
        ),
      ),
      const SizedBox(height: 20),
      const Text('准备好后，用平常的语气自然说话'),
      const SizedBox(height: 24),
      FilledButton.icon(
        key: const Key('start_voice_recording'),
        onPressed: _busy ? null : _startRecording,
        icon: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.mic_rounded),
        label: Text(_busy ? '正在准备…' : '开始录音'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      if (_errorText?.contains('权限') == true) ...[
        const SizedBox(height: 8),
        TextButton(
          key: const Key('open_microphone_settings'),
          onPressed: openAppSettings,
          child: const Text('前往系统设置'),
        ),
      ],
    ],
  );

  Widget _recordingContent(BuildContext context) => Column(
    children: [
      _VoiceLevel(level: _level),
      const SizedBox(height: 24),
      Text(
        '${_formatDuration(_elapsed)} / 01:00',
        key: const Key('voice_recording_timer'),
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 8),
      const Text('正在录音，请保持手机距离嘴边约 20 厘米'),
      const SizedBox(height: 28),
      FilledButton.icon(
        key: const Key('stop_voice_recording'),
        onPressed: _busy ? null : _stopRecording,
        icon: const Icon(Icons.stop_rounded),
        label: const Text('停止录音'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: AppColors.secondary,
        ),
      ),
    ],
  );

  Widget _reviewContent(BuildContext context) => Column(
    children: [
      Container(
        width: 96,
        height: 96,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          key: const Key('preview_voice_recording'),
          tooltip: _playing ? '停止试听' : '试听录音',
          onPressed: _busy ? null : _togglePreview,
          iconSize: 44,
          color: AppColors.primary,
          icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '录音时长 ${_formatDuration(_recording!.duration)}',
        key: const Key('voice_recording_duration'),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text('请试听确认声音清晰、没有其他人说话'),
      const SizedBox(height: 28),
      FilledButton.icon(
        key: const Key('use_voice_recording'),
        onPressed: _busy ? null : _useRecording,
        icon: const Icon(Icons.check_circle_outline_rounded),
        label: const Text('使用此录音'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        key: const Key('record_voice_again'),
        onPressed: _busy ? null : _recordAgain,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重新录制'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      ),
    ],
  );

  static String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 60);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _RecordingGuidance extends StatelessWidget {
  const _RecordingGuidance();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.outline),
    ),
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('录音建议', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          Text('在安静环境中连续说话 10～30 秒；请使用自然语气，不要刻意模仿或大声朗读。'),
        ],
      ),
    ),
  );
}

class _VoiceLevel extends StatelessWidget {
  const _VoiceLevel({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '麦克风音量',
    child: SizedBox(
      height: 92,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(13, (index) {
          final distance = (index - 6).abs();
          final factor = 1 - distance * 0.08;
          final height = 12 + 70 * level * factor;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 5,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      ),
    ),
  );
}
