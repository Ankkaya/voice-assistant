# Child Voice Call MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a locally runnable Flutter Android app with two configurable characters, local VAD, WebSocket PCM transport, MiMo ASR/TTS adapters, and a LangChain text agent.

**Architecture:** Flutter owns UI, microphone capture, VAD, and PCM playback. A single FastAPI WebSocket session buffers each utterance, calls MiMo ASR, runs a constrained LangChain chain, and streams MiMo TTS PCM back; provider interfaces and deterministic fakes isolate external APIs.

**Tech Stack:** Flutter/Dart, Riverpod, `record`, `flutter_sound`, `web_socket_channel`, Python 3.11+, FastAPI, httpx, LangChain, pytest, Docker Compose.

## Global Constraints

- Target Android only for MVP; retain a normal Flutter project structure for future iOS work.
- App-to-server audio uses WebSocket binary PCM frames, never HTTP file upload or Base64.
- Uplink is PCM16LE, 16kHz, mono, 20ms frames; downlink is PCM16LE, 24kHz, mono.
- Flutter performs VAD with 200ms pre-roll, 300ms minimum speech, 800ms end silence, and a 15-second maximum utterance.
- The assistant is half-duplex: microphone/VAD are disabled while TTS is playing.
- Session limit is 10 minutes; no accounts, database, persistence, tools, search, or long-term memory.
- MiMo ASR is `mimo-v2.5-asr`; TTS supports preset, voice design, and voice clone, with preset as default.
- LangChain manages text generation only and retains at most eight user/assistant turns in memory.
- Never log audio, transcripts, model replies, reference audio, or credentials.
- Default voices: Labrador Captain uses `白桦`; Ryder uses `苏打`.
- Do not bundle a protected Ryder likeness or cloned actor voice; ship a neutral “R” avatar and preset voice.

---

### Task 1: Backend foundation, settings, and character registry

**Files:**
- Create: `server/app/__init__.py`
- Create: `server/app/config.py`
- Create: `server/app/models.py`
- Create: `server/app/characters.py`
- Create: `server/app/config/characters.json`
- Create: `server/tests/test_characters.py`
- Create: `server/requirements.txt`

**Interfaces:**
- Produces: `Settings`, `CharacterConfig`, `TtsConfig`, `TtsMode`, and `CharacterRegistry.get(character_id)`.
- Consumes: no earlier project code.

- [ ] **Step 1: Add failing configuration tests**

```python
def test_registry_loads_two_default_characters(registry):
    assert registry.get("labrador_captain").tts.voice == "白桦"
    assert registry.get("ryder").tts.voice == "苏打"

def test_registry_rejects_unknown_character(registry):
    with pytest.raises(KeyError):
        registry.get("unknown")
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `cd server && pytest tests/test_characters.py -q`  
Expected: collection fails because `app.characters` does not exist.

- [ ] **Step 3: Implement typed configuration and registry**

```python
class TtsMode(StrEnum):
    PRESET = "preset"
    VOICE_DESIGN = "voice_design"
    VOICE_CLONE = "voice_clone"

class TtsConfig(BaseModel):
    mode: TtsMode
    model: str
    voice: str | None = None
    voice_description: str | None = None
    reference_audio_path: str | None = None

class CharacterRegistry:
    def get(self, character_id: str) -> CharacterConfig:
        if character_id not in self._characters:
            raise KeyError(character_id)
        return self._characters[character_id]
```

Create two server-side character records with fixed greetings, child-safe role descriptions, 80-character reply limits, and preset voices `白桦` and `苏打`.

Use this dependency set in `server/requirements.txt`:

```text
fastapi>=0.115,<1
uvicorn>=0.30,<1
httpx>=0.27,<1
pydantic-settings>=2.6,<3
langchain-core>=1,<2
langchain-openai>=1,<2
pytest>=8.3,<9
pytest-asyncio>=0.24,<2
pytest-httpx>=0.30,<1
```

- [ ] **Step 4: Run tests**

Run: `cd server && pytest tests/test_characters.py -q`  
Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add server/app server/tests/test_characters.py server/requirements.txt
git commit -m "feat(server): add typed character configuration"
```

### Task 2: PCM/WAV conversion and protocol models

**Files:**
- Create: `server/app/audio.py`
- Create: `server/app/protocol.py`
- Create: `server/tests/test_audio.py`
- Create: `server/tests/test_protocol.py`

**Interfaces:**
- Produces: `pcm16le_to_wav(pcm: bytes, sample_rate: int = 16000, channels: int = 1) -> bytes`.
- Produces: `parse_client_event(raw: str) -> ClientEvent` and typed server event serializers.
- Consumes: Pydantic models from Task 1.

- [ ] **Step 1: Add failing WAV and protocol tests**

```python
def test_pcm_is_wrapped_as_16khz_mono_wav():
    wav = pcm16le_to_wav(b"\x00\x00" * 160)
    with wave.open(io.BytesIO(wav), "rb") as source:
        assert source.getframerate() == 16000
        assert source.getnchannels() == 1
        assert source.getsampwidth() == 2

def test_parse_audio_start_requires_turn_id():
    with pytest.raises(ValidationError):
        parse_client_event('{"type":"input.audio.start"}')
```

- [ ] **Step 2: Verify the tests fail**

Run: `cd server && pytest tests/test_audio.py tests/test_protocol.py -q`  
Expected: imports fail because audio and protocol modules do not exist.

- [ ] **Step 3: Implement in-memory WAV and discriminated events**

Use `wave.open(io.BytesIO(), "wb")` with 16-bit samples. Define `session.start`, `input.audio.start`, `input.audio.commit`, `session.end`, and `ping` client events plus `session.ready`, `user.transcript`, `assistant.thinking`, `assistant.audio.start`, `assistant.audio.end`, `turn.error`, and `pong` server events.

```python
ClientEvent = Annotated[
    SessionStart | InputAudioStart | InputAudioCommit | SessionEnd | Ping,
    Field(discriminator="type"),
]
```

- [ ] **Step 4: Run tests**

Run: `cd server && pytest tests/test_audio.py tests/test_protocol.py -q`  
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add server/app/audio.py server/app/protocol.py server/tests/test_audio.py server/tests/test_protocol.py
git commit -m "feat(server): define audio and websocket protocol"
```

### Task 3: MiMo ASR adapter

**Files:**
- Create: `server/app/providers/__init__.py`
- Create: `server/app/providers/asr.py`
- Create: `server/tests/providers/test_asr.py`

**Interfaces:**
- Produces: `AsrProvider.transcribe(wav_bytes: bytes) -> str` async protocol.
- Produces: `XiaomiAsrProvider(api_key, client).transcribe(wav_bytes)`.
- Consumes: WAV bytes from Task 2 and `Settings.mimo_api_key` from Task 1.

- [ ] **Step 1: Add a failing mocked-request test**

```python
async def test_mimo_asr_sends_wav_data_url(httpx_mock, wav_bytes):
    httpx_mock.add_response(json={"choices": [{"message": {"content": "你好"}}]})
    result = await provider.transcribe(wav_bytes)
    request = httpx_mock.get_request()
    body = json.loads(request.content)
    audio = body["messages"][0]["content"][0]["input_audio"]
    assert body["model"] == "mimo-v2.5-asr"
    assert audio["data"].startswith("data:audio/wav;base64,")
    assert result == "你好"
```

- [ ] **Step 2: Verify failure**

Run: `cd server && pytest tests/providers/test_asr.py -q`  
Expected: import fails because `XiaomiAsrProvider` is absent.

- [ ] **Step 3: Implement the OpenAI-compatible MiMo request**

POST to `https://api.xiaomimimo.com/v1/chat/completions` with Bearer authentication, `stream: false`, language `zh`, one `input_audio` content item, and a 20-second timeout. Convert malformed, empty, 401, 429, 5xx, and timeout responses into stable `ProviderError` codes without including response bodies in logs.

- [ ] **Step 4: Run tests**

Run: `cd server && pytest tests/providers/test_asr.py -q`  
Expected: request-shape, success, timeout, and malformed-response tests pass.

- [ ] **Step 5: Commit**

```bash
git add server/app/providers server/tests/providers/test_asr.py
git commit -m "feat(server): integrate MiMo speech recognition"
```

### Task 4: LangChain agent and child safety

**Files:**
- Create: `server/app/safety.py`
- Create: `server/app/agent.py`
- Create: `server/tests/test_safety.py`
- Create: `server/tests/test_agent.py`

**Interfaces:**
- Produces: `SafetyGuard.check_input(text) -> SafetyDecision` and `sanitize_output(text, max_characters) -> str`.
- Produces: `LangChainAgent.reply(character, history, user_text) -> str` async method.
- Consumes: `CharacterConfig` from Task 1 and a LangChain `BaseChatModel` created from settings.

- [ ] **Step 1: Add failing safety and agent tests**

```python
def test_output_is_plain_and_limited():
    result = guard.sanitize_output("**你好** https://example.com " + "很高兴" * 40, 80)
    assert "**" not in result
    assert "http" not in result
    assert len(result) <= 80

async def test_agent_keeps_only_eight_turns(fake_model, character):
    history = make_history(turns=10)
    await agent.reply(character, history, "你好")
    sent_messages = fake_model.last_messages
    assert count_user_messages(sent_messages) == 9  # eight historical + current
```

- [ ] **Step 2: Verify failure**

Run: `cd server && pytest tests/test_safety.py tests/test_agent.py -q`  
Expected: imports fail.

- [ ] **Step 3: Implement the constrained chain**

Build `ChatPromptTemplate | BaseChatModel | StrOutputParser`; do not use tools or `AgentExecutor`. Combine global rules, character prompt, last eight turns, and current input. Block explicit contact details, sexual content, dangerous instructions, and prompt-injection phrases with deterministic patterns and fixed safe responses. Strip Markdown/URLs and clamp output to the character limit before TTS.

- [ ] **Step 4: Run tests**

Run: `cd server && pytest tests/test_safety.py tests/test_agent.py -q`  
Expected: all safety, history, and response-limit tests pass.

- [ ] **Step 5: Commit**

```bash
git add server/app/agent.py server/app/safety.py server/tests/test_agent.py server/tests/test_safety.py
git commit -m "feat(server): add constrained LangChain character agent"
```

### Task 5: MiMo TTS adapter with three modes

**Files:**
- Create: `server/app/providers/tts.py`
- Create: `server/tests/providers/test_tts.py`

**Interfaces:**
- Produces: `TtsProvider.synthesize(text: str, config: TtsConfig) -> AsyncIterator[bytes]`.
- Consumes: `TtsConfig` and `TtsMode` from Task 1.

- [ ] **Step 1: Add failing tests for preset, design, and clone request bodies**

```python
async def test_preset_stream_decodes_pcm_chunks(provider, sse_response):
    chunks = [chunk async for chunk in provider.synthesize("你好", preset_config)]
    assert b"".join(chunks) == b"\x01\x02\x03\x04"

def test_clone_requires_existing_reference_audio(tmp_path):
    config = clone_config(reference_audio_path=str(tmp_path / "missing.wav"))
    with pytest.raises(ProviderConfigError):
        provider.validate(config)
```

- [ ] **Step 2: Verify failure**

Run: `cd server && pytest tests/providers/test_tts.py -q`  
Expected: import fails because TTS adapter is absent.

- [ ] **Step 3: Implement all request modes and SSE decoding**

Preset uses `mimo-v2.5-tts`, `audio.format=pcm16`, configured `voice`, and `stream=true`. Voice Design supplies `voice_description`; Voice Clone loads an authorized local MP3/WAV file and supplies a data URL. Parse `data:` SSE records, decode `choices[0].delta.audio.data`, ignore terminal `[DONE]`, and yield raw 24kHz PCM. Enforce 15 seconds to first chunk and 5 seconds between chunks.

- [ ] **Step 4: Run tests**

Run: `cd server && pytest tests/providers/test_tts.py -q`  
Expected: request bodies, chunk decoding, configuration validation, and timeout tests pass.

- [ ] **Step 5: Commit**

```bash
git add server/app/providers/tts.py server/tests/providers/test_tts.py
git commit -m "feat(server): support three MiMo TTS modes"
```

### Task 6: Voice session state machine

**Files:**
- Create: `server/app/session.py`
- Create: `server/tests/test_session.py`

**Interfaces:**
- Produces: `VoiceSession.handle_text(raw: str)`, `handle_audio(data: bytes)`, `start()`, and `close(reason)` async methods.
- Consumes: registry, ASR, agent, TTS, protocol events, and a `send_text`/`send_bytes` transport pair.

- [ ] **Step 1: Add a failing end-to-end session test with fakes**

```python
async def test_committed_audio_produces_transcript_and_pcm(session, transport):
    await session.handle_text(start_event("ryder"))
    await session.handle_text(audio_start_event("turn_1"))
    await session.handle_audio(b"\x00\x00" * 1600)
    await session.handle_text(audio_commit_event("turn_1"))
    assert event_types(transport.text_events) == [
        "session.ready", "assistant.audio.start", "assistant.audio.end",
        "user.transcript", "assistant.thinking",
        "assistant.audio.start", "assistant.audio.end",
    ]
    assert transport.binary_payloads
```

- [ ] **Step 2: Verify failure**

Run: `cd server && pytest tests/test_session.py -q`  
Expected: import fails because `VoiceSession` is absent.

- [ ] **Step 3: Implement session states and cleanup**

Implement `CONNECTING`, `SPEAKING`, `LISTENING`, `RECEIVING`, `PROCESSING`, `ENDED`. Enforce one active turn, 512KB audio cap, 15-second logical audio cap, eight-turn history, 10-minute call deadline, recoverable stage errors, and cancellation of every owned task on close. Generate the greeting through the same TTS path before entering `LISTENING`.

- [ ] **Step 4: Run tests**

Run: `cd server && pytest tests/test_session.py -q`  
Expected: happy path, wrong-state, oversized-audio, empty-ASR, provider-error, and cleanup tests pass.

- [ ] **Step 5: Commit**

```bash
git add server/app/session.py server/tests/test_session.py
git commit -m "feat(server): orchestrate voice call sessions"
```

### Task 7: FastAPI WebSocket application and container

**Files:**
- Create: `server/app/main.py`
- Create: `server/tests/test_websocket.py`
- Create: `server/Dockerfile`
- Create: `docker-compose.yml`
- Create: `.env.example`

**Interfaces:**
- Produces: `GET /health`, `GET /ready`, and `WS /ws/voice`.
- Consumes: all server modules from Tasks 1–6.

- [ ] **Step 1: Add failing application tests**

```python
def test_health_is_available(client):
    assert client.get("/health").json() == {"status": "ok"}

def test_websocket_rejects_binary_before_audio_start(client):
    with client.websocket_connect("/ws/voice") as ws:
        ws.send_bytes(b"\x00\x00")
        event = ws.receive_json()
        assert event["type"] == "turn.error"
        assert event["code"] == "INVALID_STATE"
```

- [ ] **Step 2: Verify failure**

Run: `cd server && pytest tests/test_websocket.py -q`  
Expected: import fails because FastAPI app is absent.

- [ ] **Step 3: Implement dependency wiring and transport loop**

Create providers once per FastAPI lifespan, create a fresh `VoiceSession` per accepted socket, dispatch text/binary frames, answer ping with pong, and always call `session.close()` in `finally`. `/ready` returns 503 when MiMo or LLM credentials are absent and never returns credential values.

- [ ] **Step 4: Add Docker and environment configuration**

Use `python:3.11-slim`, install `server/requirements.txt`, run as a non-root user, expose 8000, and start `uvicorn app.main:app --host 0.0.0.0 --port 8000`. Compose loads `.env` and maps port 8000.

- [ ] **Step 5: Run the full backend suite**

Run: `cd server && pytest -q`  
Expected: all backend tests pass.

- [ ] **Step 6: Commit**

```bash
git add server/app/main.py server/tests/test_websocket.py server/Dockerfile docker-compose.yml .env.example
git commit -m "feat(server): expose websocket voice service"
```

### Task 8: Flutter scaffold, character page, and owned assets

**Files:**
- Create: `mobile/pubspec.yaml`
- Create: `mobile/lib/main.dart`
- Create: `mobile/lib/app.dart`
- Create: `mobile/lib/models/character.dart`
- Create: `mobile/lib/pages/character_page.dart`
- Create: `mobile/lib/widgets/character_card.dart`
- Create: `mobile/assets/characters.json`
- Create: `mobile/assets/characters/labrador_captain.png`
- Create: `mobile/assets/characters/ryder.png`
- Create: `mobile/test/character_page_test.dart`
- Create: standard Flutter Android project files under `mobile/android/`

**Interfaces:**
- Produces: `Character`, `CharacterRepository.load()`, and `CharacterPage` navigation callback.
- Consumes: no Flutter project code.

- [ ] **Step 1: Scaffold the Flutter app and add dependencies**

Run: `flutter create --platforms=android --org com.example.childvoice mobile`.

Configure `flutter_riverpod`, `web_socket_channel`, `record`, `flutter_sound`, `permission_handler`, and `uuid`; set Dart SDK to `>=3.3.0 <4.0.0`.

```yaml
environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  web_socket_channel: ^3.0.1
  record: ^5.1.2
  flutter_sound: ^9.6.0
  permission_handler: ^11.3.1
  uuid: ^4.5.1
```

- [ ] **Step 2: Create project-owned character assets**

Generate a friendly original Labrador captain portrait with no protected logos and a neutral red/blue circular “R” avatar that does not depict Ryder. Save both as square PNG files at the exact paths above.

- [ ] **Step 3: Add a failing widget test**

```dart
testWidgets('shows both configured characters', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: VoiceCallApp()));
  await tester.pumpAndSettle();
  expect(find.text('拉布拉多队长'), findsOneWidget);
  expect(find.text('莱德'), findsOneWidget);
});
```

- [ ] **Step 4: Implement the simple selection screen**

Load exactly two records from the asset JSON, render large full-width cards, title the page “想给谁打电话？”, and navigate by character ID. Do not add login, settings, history, or bottom navigation.

- [ ] **Step 5: Run tests and analyzer**

Run: `cd mobile && flutter test test/character_page_test.dart && flutter analyze`  
Expected: widget test passes and analyzer reports no issues.

- [ ] **Step 6: Commit**

```bash
git add mobile
git commit -m "feat(mobile): add character selection screen"
```

### Task 9: Flutter protocol client and call controller

**Files:**
- Create: `mobile/lib/protocol/voice_event.dart`
- Create: `mobile/lib/websocket/voice_socket.dart`
- Create: `mobile/lib/controllers/call_state.dart`
- Create: `mobile/lib/controllers/call_controller.dart`
- Create: `mobile/test/voice_event_test.dart`
- Create: `mobile/test/call_controller_test.dart`

**Interfaces:**
- Produces: `VoiceSocket.connect(uri)`, `sendEvent`, `sendAudio`, `events`, `audioChunks`, and `close`.
- Produces: `CallController` with `connect`, `hangUp`, lifecycle callbacks, and immutable `CallViewState`.
- Consumes: character ID from Task 8 and server protocol from Task 2.

- [ ] **Step 1: Add failing protocol and controller tests**

```dart
test('parses assistant audio metadata', () {
  final event = VoiceEvent.parse({
    'type': 'assistant.audio.start',
    'turnId': 'turn_1',
    'encoding': 'pcm16le',
    'sampleRate': 24000,
    'channels': 1,
  });
  expect(event, isA<AssistantAudioStart>());
});

test('microphone is disabled while assistant speaks', () async {
  await controller.onEvent(const AssistantAudioStart(...));
  expect(controller.state.phase, CallPhase.assistantSpeaking);
  expect(controller.state.microphoneEnabled, isFalse);
});
```

- [ ] **Step 2: Verify failure**

Run: `cd mobile && flutter test test/voice_event_test.dart test/call_controller_test.dart`  
Expected: imports fail.

- [ ] **Step 3: Implement typed events and state transitions**

Support connecting, ringing, assistant speaking, listening, user speaking, processing, error, and ended. Connect timeout is 8 seconds with one retry. Send ping every 15 seconds and fail after 30 seconds without a server event. Ignore stale turn IDs.

- [ ] **Step 4: Run tests**

Run: `cd mobile && flutter test test/voice_event_test.dart test/call_controller_test.dart`  
Expected: parsing, state, heartbeat, retry, and stale-event tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/protocol mobile/lib/websocket mobile/lib/controllers mobile/test/voice_event_test.dart mobile/test/call_controller_test.dart
git commit -m "feat(mobile): add voice protocol and call state"
```

### Task 10: Flutter PCM capture and local VAD

**Files:**
- Create: `mobile/lib/audio/audio_capture.dart`
- Create: `mobile/lib/audio/pcm_vad.dart`
- Create: `mobile/test/pcm_vad_test.dart`

**Interfaces:**
- Produces: `AudioCapture.start() -> Stream<Uint8List>` and `stop()`.
- Produces: `PcmVad.process(Uint8List frame) -> List<VadAction>` where actions are `speechStart`, `audio(bytes)`, `speechCommit`, or `discard`.
- Consumes: `VoiceSocket.sendAudio` and `CallController` phases from Task 9.

- [ ] **Step 1: Add deterministic failing VAD tests using synthetic PCM**

```dart
test('includes 200ms pre-roll and commits after 800ms silence', () {
  feedSilence(vad, milliseconds: 200);
  feedTone(vad, milliseconds: 400, amplitude: 6000);
  final actions = feedSilence(vad, milliseconds: 800);
  expect(actions.whereType<SpeechStart>(), hasLength(1));
  expect(actions.whereType<SpeechCommit>(), hasLength(1));
  expect(totalAudioMilliseconds(actions), greaterThanOrEqualTo(600));
});
```

- [ ] **Step 2: Verify failure**

Run: `cd mobile && flutter test test/pcm_vad_test.dart`  
Expected: import fails.

- [ ] **Step 3: Implement PCM capture and an adaptive energy VAD**

Use `record` streaming PCM16 at 16kHz mono. Compute RMS over each 20ms frame, maintain a slowly adapting noise floor while not speaking, and classify speech when RMS exceeds `max(900, noiseFloor * 3.0)`. Preserve ten frames of pre-roll, require 15 voiced frames total, commit after 40 silent frames, and force commit after 750 frames.

- [ ] **Step 4: Run tests**

Run: `cd mobile && flutter test test/pcm_vad_test.dart`  
Expected: pre-roll, minimum speech, silence commit, noise discard, and 15-second force-commit tests pass.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/audio/audio_capture.dart mobile/lib/audio/pcm_vad.dart mobile/test/pcm_vad_test.dart
git commit -m "feat(mobile): add streaming capture and local VAD"
```

### Task 11: Flutter PCM player and call page integration

**Files:**
- Create: `mobile/lib/audio/audio_player.dart`
- Create: `mobile/lib/pages/call_page.dart`
- Create: `mobile/lib/widgets/call_avatar.dart`
- Create: `mobile/lib/widgets/hangup_button.dart`
- Create: `mobile/test/call_page_test.dart`
- Modify: `mobile/lib/pages/character_page.dart`
- Modify: `mobile/android/app/src/main/AndroidManifest.xml`
- Create: `mobile/android/app/src/debug/AndroidManifest.xml`
- Create: `mobile/android/app/src/debug/res/xml/network_security_config.xml`

**Interfaces:**
- Produces: `PcmAudioPlayer.start(sampleRate)`, `feed(bytes)`, `finish()`, and `stop()`.
- Produces: fully wired `CallPage(character)`.
- Consumes: Tasks 8–10.

- [ ] **Step 1: Add a failing call-page widget test**

```dart
testWidgets('only exposes hangup during a call', (tester) async {
  await tester.pumpWidget(testCallPage(phase: CallPhase.listening));
  expect(find.text('你可以说话啦'), findsOneWidget);
  expect(find.byKey(const Key('hangup_button')), findsOneWidget);
  expect(find.text('按住说话'), findsNothing);
});
```

- [ ] **Step 2: Verify failure**

Run: `cd mobile && flutter test test/call_page_test.dart`  
Expected: import fails because the call page is absent.

- [ ] **Step 3: Implement streaming playback and page wiring**

Use `flutter_sound` PCM16 stream playback at the sample rate declared by `assistant.audio.start`. Buffer 100ms before starting playback, feed chunks in order, and stop immediately on hangup or lifecycle pause. Wire VAD actions to `input.audio.start`, binary frames, and `input.audio.commit`. Only start capture in `listening`; stop it in every other phase.

- [ ] **Step 4: Configure Android permissions and debug LAN access**

Add `RECORD_AUDIO`, `INTERNET`, and `WAKE_LOCK`. Restrict cleartext permission to the Debug manifest/network configuration; Release does not opt into arbitrary cleartext traffic.

- [ ] **Step 5: Run Flutter tests and analyzer**

Run: `cd mobile && flutter test && flutter analyze`  
Expected: all tests pass and analyzer is clean.

- [ ] **Step 6: Commit**

```bash
git add mobile
git commit -m "feat(mobile): complete automatic voice call UI"
```

### Task 12: Documentation, validation, and end-to-end readiness

**Files:**
- Create: `README.md`
- Create: `server/tests/test_no_sensitive_logging.py`
- Modify: `.gitignore`
- Modify: `.env.example`

**Interfaces:**
- Produces: reproducible local setup and verification commands.
- Consumes: the complete mobile and server implementation.

- [ ] **Step 1: Add a failing sensitive-logging test**

```python
def test_provider_error_does_not_log_transcript_or_key(caplog):
    simulate_provider_failure(api_key="secret-key", transcript="我的学校是测试小学")
    combined = "\n".join(record.message for record in caplog.records)
    assert "secret-key" not in combined
    assert "测试小学" not in combined
```

- [ ] **Step 2: Run the test and correct any logging leaks**

Run: `cd server && pytest tests/test_no_sensitive_logging.py -q`  
Expected: passes after logs contain only session IDs, stages, durations, and stable error codes.

- [ ] **Step 3: Write exact local setup documentation**

Document `.env` creation, MiMo/LLM settings, `docker compose up --build`, host LAN-IP discovery, Flutter `--dart-define=VOICE_SERVER_URL=ws://<LAN-IP>:8000/ws/voice`, Android microphone permission, preset/design/clone character configuration, authorized clone reference placement, and real-provider smoke-test commands.

- [ ] **Step 4: Run all available automated verification**

```bash
cd server && pytest -q
cd mobile && flutter test && flutter analyze
```

Expected: backend and Flutter tests pass, analyzer is clean. If MiMo and LLM credentials are absent, live-provider tests report skipped rather than failed.

- [ ] **Step 5: Inspect repository hygiene**

Run: `git status --short && git diff --check && git grep -nE '(MIMO_API_KEY=.+|LLM_API_KEY=.+)' -- ':!*.example'`  
Expected: no secrets, no whitespace errors, and only intended project files.

- [ ] **Step 6: Commit**

```bash
git add README.md .gitignore .env.example server/tests/test_no_sensitive_logging.py
git commit -m "docs: add local MVP setup and validation"
```

## Final Verification

- [ ] Run all server tests.
- [ ] Run all Flutter tests and analyzer.
- [ ] Build an Android debug APK.
- [ ] Start the server locally and verify `/health` and `/ready` behavior.
- [ ] With credentials present, perform one real MiMo ASR/TTS and LangChain smoke test.
- [ ] On Android hardware, verify both roles, automatic VAD, half-duplex behavior, hangup cleanup, and a 10-minute call.
- [ ] Confirm `git status --short` is clean.
