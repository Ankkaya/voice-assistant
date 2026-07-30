import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

sealed class VadAction {
  const VadAction();
}

final class SpeechStart extends VadAction {
  const SpeechStart();
}

final class VadAudio extends VadAction {
  const VadAudio(this.bytes);
  final Uint8List bytes;
}

final class SpeechCommit extends VadAction {
  const SpeechCommit();
}

final class VadDiscard extends VadAction {
  const VadDiscard();
}

enum _VadPhase { idle, candidate, speaking }

class PcmVad {
  PcmVad({
    this.minimumAmplitude = 900,
    this.speechFactor = 3.0,
    this.preRollFrames = 10,
    this.minimumVoicedFrames = 15,
    this.endSilenceFrames = 40,
    this.maximumSpeechFrames = 750,
  });

  final double minimumAmplitude;
  final double speechFactor;
  final int preRollFrames;
  final int minimumVoicedFrames;
  final int endSilenceFrames;
  final int maximumSpeechFrames;

  final Queue<Uint8List> _preRoll = Queue<Uint8List>();
  final List<Uint8List> _candidate = [];
  _VadPhase _phase = _VadPhase.idle;
  double _noiseFloor = 250;
  int _candidateVoiced = 0;
  int _candidateSilence = 0;
  int _speakingSilence = 0;
  int _speakingFrames = 0;

  List<VadAction> process(Uint8List frame) {
    if (frame.lengthInBytes.isOdd) {
      throw ArgumentError('PCM16 frame must contain complete samples');
    }
    final rms = _rms(frame);
    final threshold = math.max(minimumAmplitude, _noiseFloor * speechFactor);
    final voiced = rms >= threshold;

    return switch (_phase) {
      _VadPhase.idle => _processIdle(frame, rms, voiced),
      _VadPhase.candidate => _processCandidate(frame, voiced),
      _VadPhase.speaking => _processSpeaking(frame, voiced),
    };
  }

  List<VadAction> _processIdle(Uint8List frame, double rms, bool voiced) {
    _remember(frame);
    if (!voiced) {
      _noiseFloor = _noiseFloor * 0.95 + rms * 0.05;
      return const [];
    }
    _phase = _VadPhase.candidate;
    _candidate
      ..clear()
      ..addAll(_preRoll.map(Uint8List.fromList));
    _candidateVoiced = 1;
    _candidateSilence = 0;
    return const [];
  }

  List<VadAction> _processCandidate(Uint8List frame, bool voiced) {
    _candidate.add(Uint8List.fromList(frame));
    if (voiced) {
      _candidateVoiced += 1;
      _candidateSilence = 0;
    } else {
      _candidateSilence += 1;
    }

    if (_candidateVoiced >= minimumVoicedFrames) {
      _phase = _VadPhase.speaking;
      _speakingFrames = _candidate.length;
      _speakingSilence = 0;
      final actions = <VadAction>[const SpeechStart()];
      actions.addAll(_candidate.map((bytes) => VadAudio(bytes)));
      _candidate.clear();
      _preRoll.clear();
      return actions;
    }

    if (_candidateSilence >= 5) {
      for (final bytes in _candidate.skip(
        math.max(0, _candidate.length - preRollFrames),
      )) {
        _remember(bytes);
      }
      _candidate.clear();
      _candidateVoiced = 0;
      _candidateSilence = 0;
      _phase = _VadPhase.idle;
      return const [VadDiscard()];
    }
    return const [];
  }

  List<VadAction> _processSpeaking(Uint8List frame, bool voiced) {
    _speakingFrames += 1;
    _speakingSilence = voiced ? 0 : _speakingSilence + 1;
    final actions = <VadAction>[VadAudio(Uint8List.fromList(frame))];
    if (_speakingSilence >= endSilenceFrames ||
        _speakingFrames >= maximumSpeechFrames) {
      actions.add(const SpeechCommit());
      reset();
    }
    return actions;
  }

  void _remember(Uint8List frame) {
    _preRoll.add(Uint8List.fromList(frame));
    while (_preRoll.length > preRollFrames) {
      _preRoll.removeFirst();
    }
  }

  double _rms(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    var sumSquares = 0.0;
    final samples = bytes.lengthInBytes ~/ 2;
    for (var offset = 0; offset < bytes.lengthInBytes; offset += 2) {
      final sample = data.getInt16(offset, Endian.little).toDouble();
      sumSquares += sample * sample;
    }
    return samples == 0 ? 0 : math.sqrt(sumSquares / samples);
  }

  void reset() {
    _phase = _VadPhase.idle;
    _preRoll.clear();
    _candidate.clear();
    _candidateVoiced = 0;
    _candidateSilence = 0;
    _speakingSilence = 0;
    _speakingFrames = 0;
  }
}
