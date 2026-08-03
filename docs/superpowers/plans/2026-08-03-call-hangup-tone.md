# Call Hangup Tone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play one approximately 500 millisecond classic descending telephone cue only when the child deliberately taps the red hangup button after accepting a call.

**Architecture:** Add a focused `HangupTonePlayer` that generates deterministic PCM16 audio and uses the existing `PcmAudioPlayer` through a testable output boundary. `CallPage` retains one optional tone player, marks only the active red button as audible, and keeps every other end-call path silent while preserving guaranteed cleanup and route dismissal.

**Tech Stack:** Flutter 3 / Dart 3.12, `flutter_sound` through the existing `PcmAudioPlayer`, `flutter_test`, generated mono PCM16 audio.

## Global Constraints

- Play the cue only from the red hangup button after the incoming call has been accepted.
- Do not play it for decline, back navigation, character-error actions, microphone denial, lifecycle pause/detach, or other error paths.
- Generate the sound in Dart; do not add an asset, dependency, sound setting, haptic effect, or server/protocol change.
- Use two short descending tones with click-free attack/release envelopes and a total duration of exactly 500 milliseconds.
- Release live ringtone, assistant playback, capture, and controller resources before starting the cue.
- Ignore repeated hangup attempts after the first.
- Never keep the child on the call page because cleanup or cue playback failed.
- Preserve the user's untracked `.superpowers/` directory.

---

## File Structure

- Create `mobile/lib/audio/hangup_tone_player.dart`: generated waveform, output adapter, single-shot playback, and idempotent disposal.
- Create `mobile/test/hangup_tone_player_test.dart`: waveform and playback-lifecycle unit tests without platform audio.
- Modify `mobile/lib/pages/call_page.dart`: active-button-only trigger, best-effort teardown, tone lifetime, and testing seam.
- Modify `mobile/test/call_page_test.dart`: audible and silent end-path widget tests.

---

### Task 1: Implement a Deterministic Single-Shot Hangup Tone

**Files:**

- Create: `mobile/lib/audio/hangup_tone_player.dart`
- Create: `mobile/test/hangup_tone_player_test.dart`

**Interfaces:**

- Consumes: `PcmAudioPlayer.start`, `feed`, `finish`, and `dispose`.
- Produces: `HangupToneOutput`, `PcmHangupToneOutput`, and `HangupTonePlayer.play/dispose/buildTone`.
- `HangupTonePlayer.sampleRate` is `24000`; `HangupTonePlayer.duration` is exactly 500 milliseconds.

- [ ] **Step 1: Write failing waveform tests**

Create `mobile/test/hangup_tone_player_test.dart` with helpers that read little-endian PCM16 samples and count zero crossings:

```dart
import 'dart:typed_data';

import 'package:child_voice_call/audio/hangup_tone_player.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _samples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return [
    for (var offset = 0; offset < bytes.length; offset += 2)
      data.getInt16(offset, Endian.little),
  ];
}

int _zeroCrossings(List<int> samples, int start, int end) {
  var crossings = 0;
  for (var index = start + 1; index < end; index++) {
    if ((samples[index - 1] < 0 && samples[index] >= 0) ||
        (samples[index - 1] > 0 && samples[index] <= 0)) {
      crossings++;
    }
  }
  return crossings;
}

void main() {
  test('builds 500ms pcm16 with a descending two-part tone', () {
    final bytes = HangupTonePlayer.buildTone();
    final samples = _samples(bytes);
    final samplesPerMillisecond = HangupTonePlayer.sampleRate ~/ 1000;

    expect(bytes, hasLength(HangupTonePlayer.sampleRate));
    expect(samples.any((sample) => sample != 0), isTrue);
    expect(
      samples.sublist(
        185 * samplesPerMillisecond,
        225 * samplesPerMillisecond,
      ).every((sample) => sample == 0),
      isTrue,
    );

    final highCrossings = _zeroCrossings(
      samples,
      20 * samplesPerMillisecond,
      160 * samplesPerMillisecond,
    );
    final lowCrossings = _zeroCrossings(
      samples,
      250 * samplesPerMillisecond,
      450 * samplesPerMillisecond,
    );
    expect(highCrossings / 140, greaterThan(lowCrossings / 200));
  });
}
```

- [ ] **Step 2: Write failing playback lifecycle tests**

In the same file, add a fake output and verify the exact sequence, single-shot behavior, injected delay, and idempotent disposal:

```dart
final class FakeHangupToneOutput implements HangupToneOutput {
  final calls = <String>[];

  @override
  Future<void> start(int sampleRate) async => calls.add('start:$sampleRate');

  @override
  Future<void> feed(Uint8List bytes) async => calls.add('feed:${bytes.length}');

  @override
  Future<void> finish() async => calls.add('finish');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

test('plays once for 500ms and disposes output once', () async {
  final output = FakeHangupToneOutput();
  final delays = <Duration>[];
  final player = HangupTonePlayer(
    output: output,
    delay: (duration) async => delays.add(duration),
  );

  await player.play();
  await player.play();
  await player.dispose();

  expect(output.calls, [
    'start:24000',
    'feed:24000',
    'finish',
    'dispose',
  ]);
  expect(delays, [const Duration(milliseconds: 500)]);
});
```

- [ ] **Step 3: Run the new tests and verify they fail**

Run:

```bash
cd mobile
flutter test --no-pub test/hangup_tone_player_test.dart
```

Expected: FAIL because `audio/hangup_tone_player.dart` and its public types do not exist.

- [ ] **Step 4: Implement the output boundary and PCM adapter**

Create `mobile/lib/audio/hangup_tone_player.dart` with this boundary so unit tests do not invoke platform channels:

```dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'audio_player.dart';

abstract interface class HangupToneOutput {
  Future<void> start(int sampleRate);
  Future<void> feed(Uint8List bytes);
  Future<void> finish();
  Future<void> dispose();
}

final class PcmHangupToneOutput implements HangupToneOutput {
  PcmHangupToneOutput({PcmAudioPlayer? player})
    : _player = player ?? PcmAudioPlayer();

  final PcmAudioPlayer _player;

  @override
  Future<void> start(int sampleRate) => _player.start(sampleRate);

  @override
  Future<void> feed(Uint8List bytes) => _player.feed(bytes);

  @override
  Future<void> finish() => _player.finish();

  @override
  Future<void> dispose() => _player.dispose();
}
```

- [ ] **Step 5: Implement single-shot playback and the waveform**

Use 620 Hz from 0–180 ms, silence from 180–230 ms, 440 Hz from 230–480 ms, and trailing silence through 500 ms. Apply a 12 ms linear attack and release to both audible segments:

```dart
final class HangupTonePlayer {
  HangupTonePlayer({
    HangupToneOutput? output,
    Future<void> Function(Duration)? delay,
  }) : _output = output ?? PcmHangupToneOutput(),
       _delay = delay ?? Future<void>.delayed;

  static const sampleRate = 24000;
  static const duration = Duration(milliseconds: 500);

  final HangupToneOutput _output;
  final Future<void> Function(Duration) _delay;
  Future<void>? _playFuture;
  bool _disposed = false;

  Future<void> play() => _playFuture ??= _playOnce();

  Future<void> _playOnce() async {
    if (_disposed) return;
    try {
      await _output.start(sampleRate);
      await _output.feed(buildTone());
      await _output.finish();
      await _delay(duration);
    } finally {
      await dispose();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _output.dispose();
  }

  @visibleForTesting
  static Uint8List buildTone() {
    const firstEndMs = 180.0;
    const secondStartMs = 230.0;
    const secondEndMs = 480.0;
    const fadeMs = 12.0;
    final sampleCount = sampleRate * duration.inMilliseconds ~/ 1000;
    final data = ByteData(sampleCount * 2);

    for (var index = 0; index < sampleCount; index++) {
      final milliseconds = index * 1000 / sampleRate;
      final (frequency, segmentPosition, segmentLength) =
          milliseconds < firstEndMs
          ? (620.0, milliseconds, firstEndMs)
          : milliseconds >= secondStartMs && milliseconds < secondEndMs
          ? (440.0, milliseconds - secondStartMs, secondEndMs - secondStartMs)
          : (0.0, 0.0, 0.0);
      final envelope = frequency == 0
          ? 0.0
          : math.min(
              1.0,
              math.min(
                segmentPosition / fadeMs,
                (segmentLength - segmentPosition) / fadeMs,
              ),
            );
      final seconds = index / sampleRate;
      final sample = (math.sin(2 * math.pi * frequency * seconds) *
              envelope *
              6500)
          .round()
          .clamp(-32768, 32767);
      data.setInt16(index * 2, sample, Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
```

- [ ] **Step 6: Format and run the audio unit tests**

Run:

```bash
cd mobile
dart format lib/audio/hangup_tone_player.dart test/hangup_tone_player_test.dart
flutter test --no-pub test/hangup_tone_player_test.dart
flutter analyze --no-pub
```

Expected: both focused tests pass and analysis reports no issues.

- [ ] **Step 7: Commit the standalone tone player**

```bash
git add mobile/lib/audio/hangup_tone_player.dart mobile/test/hangup_tone_player_test.dart
git commit -m "feat: add generated hangup tone player"
```

---

### Task 2: Trigger the Tone Only from an Active Manual Hangup

**Files:**

- Modify: `mobile/lib/pages/call_page.dart`
- Modify: `mobile/test/call_page_test.dart`

**Interfaces:**

- Consumes: `HangupTonePlayer.play()` and `HangupTonePlayer.dispose()` from Task 1.
- Produces: `CallPage.hangupTonePlaybackOverride` for widget tests and `_endCall(playHangupTone: bool)` for explicit audible/silent routing.

- [ ] **Step 1: Add a routed-call test helper**

In `mobile/test/call_page_test.dart`, add a helper that opens `CallPage` through a real route and captures its result:

```dart
Future<Completer<CallPageResult?>> openCallRoute(
  WidgetTester tester, {
  required CallController controller,
  required bool incomingCall,
  required Future<void> Function() cleanup,
  required Future<void> Function() playHangupTone,
  bool autoConnect = false,
}) async {
  final result = Completer<CallPageResult?>();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => FilledButton(
          key: const Key('open_call'),
          onPressed: () async {
            result.complete(
              await Navigator.of(context).push<CallPageResult>(
                MaterialPageRoute<CallPageResult>(
                  builder: (_) => CallPage(
                    character: character,
                    controller: controller,
                    autoConnect: autoConnect,
                    incomingCall: incomingCall,
                    audioCleanupOverride: cleanup,
                    hangupTonePlaybackOverride: playHangupTone,
                  ),
                ),
              ),
            );
          },
          child: const Text('打开通话'),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open_call')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return result;
}
```

- [ ] **Step 2: Write failing tests for active hangup, repetition, and playback failure**

Add these behaviors using the helper:

```dart
testWidgets('active hangup plays one tone before returning', (tester) async {
  final controller = CallController(
    character: character,
    socket: PageTestSocket(),
  );
  addTearDown(controller.dispose);
  var plays = 0;
  final events = <String>[];
  final result = await openCallRoute(
    tester,
    controller: controller,
    incomingCall: false,
    cleanup: () async => events.add('cleanup'),
    playHangupTone: () async {
      plays++;
      events.add('tone');
    },
  );

  await tester.tap(find.byKey(const Key('hangup_button')));
  await tester.pumpAndSettle();

  expect(plays, 1);
  expect(events, ['cleanup', 'tone']);
  expect(await result.future, CallPageResult.ended);
});

testWidgets('repeated active hangup taps play only one tone', (tester) async {
  final controller = CallController(
    character: character,
    socket: PageTestSocket(),
  );
  addTearDown(controller.dispose);
  final playback = Completer<void>();
  var plays = 0;
  final result = await openCallRoute(
    tester,
    controller: controller,
    incomingCall: false,
    cleanup: () async {},
    playHangupTone: () {
      plays++;
      return playback.future;
    },
  );

  await tester.tap(find.byKey(const Key('hangup_button')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('hangup_button')));
  await tester.pump();
  expect(plays, 1);
  expect(result.isCompleted, isFalse);

  playback.complete();
  await tester.pumpAndSettle();
  expect(await result.future, CallPageResult.ended);
});

testWidgets('tone failure still returns from the call', (tester) async {
  final controller = CallController(
    character: character,
    socket: PageTestSocket(),
  );
  addTearDown(controller.dispose);
  final result = await openCallRoute(
    tester,
    controller: controller,
    incomingCall: false,
    cleanup: () async {},
    playHangupTone: () => Future<void>.error(StateError('audio unavailable')),
  );

  await tester.tap(find.byKey(const Key('hangup_button')));
  await tester.pumpAndSettle();

  expect(await result.future, CallPageResult.ended);
});

testWidgets('cleanup failure still plays tone and returns', (tester) async {
  final controller = CallController(
    character: character,
    socket: PageTestSocket(),
  );
  addTearDown(controller.dispose);
  var plays = 0;
  final result = await openCallRoute(
    tester,
    controller: controller,
    incomingCall: false,
    cleanup: () => Future<void>.error(StateError('cleanup failed')),
    playHangupTone: () async => plays++,
  );

  await tester.tap(find.byKey(const Key('hangup_button')));
  await tester.pumpAndSettle();

  expect(plays, 1);
  expect(await result.future, CallPageResult.ended);
});
```

- [ ] **Step 3: Write failing tests for silent end paths**

Add tests that inject a counter and prove the default remains silent:

```dart
testWidgets('declining an incoming call does not play hangup tone', (
  tester,
) async {
  final controller = CallController(
    character: character,
    socket: PageTestSocket(),
  );
  addTearDown(controller.dispose);
  var plays = 0;
  await openCallRoute(
    tester,
    controller: controller,
    incomingCall: true,
    cleanup: () async {},
    playHangupTone: () async => plays++,
  );

  await tester.tap(find.byKey(const Key('decline_call_button')));
  await tester.pumpAndSettle();

  expect(plays, 0);
});

testWidgets('system back from an active call stays silent', (tester) async {
  final controller = CallController(
    character: character,
    socket: PageTestSocket(),
  );
  addTearDown(controller.dispose);
  var plays = 0;
  await openCallRoute(
    tester,
    controller: controller,
    incomingCall: false,
    cleanup: () async {},
    playHangupTone: () async => plays++,
  );

  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();

  expect(plays, 0);
});

testWidgets('paused lifecycle termination stays silent', (tester) async {
  final controller = CallController(
    character: character,
    socket: PageTestSocket(),
  );
  addTearDown(controller.dispose);
  var plays = 0;
  await openCallRoute(
    tester,
    controller: controller,
    incomingCall: false,
    cleanup: () async {},
    playHangupTone: () async => plays++,
  );

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pumpAndSettle();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

  expect(plays, 0);
});

testWidgets('microphone denial closes without hangup tone', (tester) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.record/messages'),
        (call) async => call.method == 'hasPermission' ? false : null,
      );
  final controller = CallController(
    character: character,
    socket: PageTestSocket(),
  );
  addTearDown(controller.dispose);
  var plays = 0;
  final result = await openCallRoute(
    tester,
    controller: controller,
    incomingCall: false,
    autoConnect: true,
    cleanup: () async {},
    playHangupTone: () async => plays++,
  );

  await tester.pumpAndSettle();

  expect(plays, 0);
  expect(await result.future, CallPageResult.ended);
});
```

In the existing character-configuration-error test, declare `var hangupTonePlays = 0`, pass `hangupTonePlaybackOverride: () async => hangupTonePlays++` next to `audioCleanupOverride`, and assert `expect(hangupTonePlays, 0)` after tapping `edit_character_after_error`. Duplicate that setup in a test that taps `back_to_characters_after_error` and assert the same zero count. Both buttons continue calling `_endCall` without the new audible flag.

- [ ] **Step 4: Run the call-page tests and verify they fail**

Run:

```bash
cd mobile
flutter test --no-pub test/call_page_test.dart
```

Expected: FAIL because `hangupTonePlaybackOverride` and the audible end-call flag do not exist.

- [ ] **Step 5: Add the tone player and testing seam to `CallPage`**

Import the new player and extend the widget/state:

```dart
import '../audio/hangup_tone_player.dart';

const CallPage({
  required this.character,
  this.controller,
  this.autoConnect = true,
  this.incomingCall = true,
  this.voiceSelection = const VoiceSelection(mode: VoiceMode.preset),
  this.audioCleanupOverride,
  this.hangupTonePlaybackOverride,
  super.key,
});

@visibleForTesting
final Future<void> Function()? hangupTonePlaybackOverride;

HangupTonePlayer? _hangupTone;
```

In `initState`, avoid constructing platform audio in tests that supply the override:

```dart
if (widget.hangupTonePlaybackOverride == null) {
  _hangupTone = HangupTonePlayer();
}
```

- [ ] **Step 6: Make end-call cleanup best-effort and add the explicit tone flag**

Replace `_endCall` with an explicit audible flag and isolate every nonessential failure:

```dart
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

  final audioSubscription = _audioSubscription;
  _audioSubscription = null;
  final eventSubscription = _eventSubscription;
  _eventSubscription = null;
  await _ignoreFailure(() async {
    await audioSubscription?.cancel();
  });
  await _ignoreFailure(() async {
    await eventSubscription?.cancel();
  });
  await _ignoreFailure(_controller.hangUp);
  await _ignoreFailure(
    widget.audioCleanupOverride?.call ?? _disposeAudioResources,
  );
  if (playHangupTone) {
    await _ignoreFailure(
      widget.hangupTonePlaybackOverride?.call ?? _hangupTone!.play,
    );
  }
  if (mounted) Navigator.of(context).pop(result);
}
```

Keep all existing `_endCall()` and `_endCall(result: ...)` callers unchanged. Change only the active `HangupButton` callback:

```dart
HangupButton(
  key: const ValueKey('active_call_actions'),
  onPressed: () => unawaited(_endCall(playHangupTone: true)),
)
```

- [ ] **Step 7: Dispose an unused tone player during page teardown**

Add this line to `dispose`, before `super.dispose()`:

```dart
unawaited(_hangupTone?.dispose());
```

The call is safe after successful playback because Task 1 makes disposal idempotent. Silent end paths use it to close the never-played output.

- [ ] **Step 8: Format and run focused tests**

Run:

```bash
cd mobile
dart format lib/pages/call_page.dart test/call_page_test.dart
flutter test --no-pub test/hangup_tone_player_test.dart test/call_page_test.dart
flutter test --no-pub test/character_page_test.dart test/call_controller_test.dart
flutter analyze --no-pub
```

Expected: all focused audio, call-page, navigation, and controller tests pass; analysis reports no issues.

- [ ] **Step 9: Run the full Flutter regression suite**

Run:

```bash
cd mobile
flutter test --no-pub
```

Expected: every Flutter test passes. Do not run server tests because no server or protocol files changed.

- [ ] **Step 10: Inspect scope and commit the integration**

Run:

```bash
git diff --check
git status --short
git diff --stat
```

Confirm only the four planned mobile files changed and `.superpowers/` remains untracked. Then commit:

```bash
git add mobile/lib/pages/call_page.dart mobile/test/call_page_test.dart
git commit -m "feat: play tone on active call hangup"
```

- [ ] **Step 11: Report delivery evidence**

Report the two implementation commit hashes, the exact focused and full verification results, and link `hangup_tone_player.dart`, `call_page.dart`, the design specification, and this implementation plan.
