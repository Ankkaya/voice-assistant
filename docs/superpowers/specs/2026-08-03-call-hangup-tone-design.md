# Call Hangup Tone Design

**Date:** 2026-08-03

**Status:** Approved for implementation planning

## Goal

Add a short, recognizable telephone hangup sound when a child deliberately ends an accepted call. The sound should reinforce that the call has ended without changing any server protocol or adding configuration UI.

## Scope

The tone plays only when all of the following are true:

- The incoming call has already been accepted.
- The active call action is the red hangup button.
- That button initiates the end-call flow.

The tone does not play when the child declines an incoming call, uses system back navigation, returns from a character configuration error, denies microphone permission, the app pauses or detaches, or the call ends because of an error. Those paths continue to close silently.

No volume control, sound selector, user preference, bundled audio asset, haptic feedback, or server change is included.

## Approach

Create a small `HangupTonePlayer` beside the existing ringtone player. It generates PCM16 audio in Dart and plays it through `PcmAudioPlayer`. The waveform is a child-safe interpretation of a classic telephone disconnect cue: two short tones with a descending pitch, softened with short attack and release envelopes to avoid clicks. Total audible duration is approximately 500 milliseconds.

This approach is preferred over a bundled WAV because it adds no binary asset or licensing obligation. It is preferred over a platform system sound because its behavior remains consistent across supported Android devices and matches the app's existing generated-ringtone architecture.

## Components and Responsibilities

### `HangupTonePlayer`

- Owns its `PcmAudioPlayer` by default and supports dependency injection for tests.
- Generates a deterministic mono PCM16 waveform at the same supported sample rate used by the ringtone.
- Plays at most one tone at a time.
- Waits for the approximately 500 millisecond cue to finish before closing its player.
- Makes `dispose` idempotent so overlapping page teardown cannot close audio resources twice.

### `CallPage`

- Owns one `HangupTonePlayer` for the page lifetime.
- Extends the unified end-call method with an explicit `playHangupTone` flag that defaults to `false`.
- Passes `playHangupTone: true` only from the active red hangup button.
- Keeps every other existing end-call caller on the silent default.
- Retains the existing `_ending` guard so rapid taps cannot play multiple tones or pop multiple routes.
- Provides a narrow testing override for hangup-tone playback, following the existing audio-cleanup override pattern.

## End-Call Sequence

For a deliberate active-call hangup:

1. Set the existing ending guard immediately.
2. Cancel incoming audio and event subscriptions.
3. Close the controller/socket session.
4. Stop capture and dispose ringtone, assistant playback, and microphone resources.
5. Attempt to play the hangup tone.
6. Pop the call route after the tone completes.

Releasing live call audio before starting the cue prevents assistant speech, microphone capture, or an incoming ringtone from overlapping it. If cleanup or tone playback fails, the route must still close. Cleanup retains its current best-effort behavior, while tone failure is explicitly swallowed at the page boundary.

The sound intentionally delays route dismissal by about half a second so it remains audible and visually corresponds to the call screen. The button becomes inert immediately through the ending guard.

## Error Handling

- Audio output unavailable: skip the cue and close the route normally.
- Repeated hangup taps: ignore every call after the first.
- Widget disposed during the async sequence: complete cleanup without attempting to pop an unmounted context.
- Lifecycle termination during a pending manual hangup: reuse the ending guard and do not start a second end-call sequence.

No error message is shown to the child for hangup-tone failures because the cue is nonessential feedback.

## Testing

Add focused tests for:

- The generated waveform has the expected duration, PCM16 shape, non-silent samples, and a descending two-part frequency structure.
- Playback is single-shot and disposal is safe to call repeatedly.
- Tapping the active red hangup button invokes the tone once and returns `CallPageResult.ended` only after playback completes.
- Repeated active-button taps do not invoke the tone more than once.
- Declining an incoming call does not invoke the tone.
- Back navigation, character-error actions, lifecycle termination, and microphone-permission failure retain the silent path.
- A thrown playback error still allows the call page to close.

Run the full Flutter analyzer and test suite after the focused audio and call-page tests. Server tests are not required because the protocol and server code are unchanged.

## Success Criteria

- A deliberate hangup after accepting a call produces one recognizable, approximately 500 millisecond descending telephone cue.
- No other call-ending path produces the cue.
- The call cannot continue sending or receiving audio while the cue plays.
- Tone failure never traps the child on the call screen.
- Existing call lifecycle and homepage navigation tests remain green.
