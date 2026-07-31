from pathlib import Path

from fastapi.testclient import TestClient

from app.characters import CharacterRegistry
from app.main import AppDependencies, create_app


class FakeAsr:
    async def transcribe(self, wav_bytes):
        return "你好"


class FakeAgent:
    async def reply(self, character, history, user_text):
        return "你好呀！"


class FakeTts:
    async def synthesize(self, text, config):
        yield b"\x01\x02"


def make_test_app(ready=True):
    config = Path(__file__).parents[1] / "app" / "config" / "characters.json"
    dependencies = AppDependencies(
        registry=CharacterRegistry.from_path(config),
        asr=FakeAsr(),
        agent=FakeAgent(),
        tts=FakeTts(),
        ready=ready,
    )
    return create_app(dependencies)


def test_health_is_available():
    with TestClient(make_test_app()) as client:
        assert client.get("/health").json() == {"status": "ok"}


def test_readiness_does_not_expose_configuration():
    with TestClient(make_test_app(ready=False)) as client:
        response = client.get("/ready")
        assert response.status_code == 503
        assert response.json() == {"status": "not_ready"}


def test_websocket_rejects_binary_before_audio_start():
    with TestClient(make_test_app()) as client:
        with client.websocket_connect("/ws/voice") as ws:
            ws.send_bytes(b"\x00\x00")
            event = ws.receive_json()
            assert event["type"] == "turn.error"
            assert event["code"] == "INVALID_STATE"


def test_websocket_streams_greeting_after_session_start():
    with TestClient(make_test_app()) as client:
        with client.websocket_connect("/ws/voice") as ws:
            ws.send_json({"type": "session.start", "characterId": "ryder"})
            assert ws.receive_json()["type"] == "session.ready"
            assert ws.receive_json()["type"] == "assistant.audio.start"
            assert ws.receive_bytes() == b"\x01\x02"
            assert ws.receive_json()["type"] == "assistant.audio.end"


def test_voice_reference_upload_accepts_wav():
    with TestClient(make_test_app()) as client:
        response = client.post(
            "/api/voice-references",
            files={
                "file": (
                    "authorized.wav",
                    b"RIFF\x04\x00\x00\x00WAVEauthorized",
                    "audio/wav",
                )
            },
        )

    assert response.status_code == 201
    assert len(response.json()["referenceId"]) == 32
    assert response.json()["sizeBytes"] == len(
        b"RIFF\x04\x00\x00\x00WAVEauthorized"
    )


def test_voice_reference_upload_rejects_unsupported_file():
    with TestClient(make_test_app()) as client:
        response = client.post(
            "/api/voice-references",
            files={"file": ("voice.txt", b"not audio", "text/plain")},
        )

    assert response.status_code == 400


def test_voice_reference_upload_rejects_fake_wav():
    with TestClient(make_test_app()) as client:
        response = client.post(
            "/api/voice-references",
            files={"file": ("voice.wav", b"not really wav", "audio/wav")},
        )

    assert response.status_code == 400
