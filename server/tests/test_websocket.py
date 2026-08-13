from pathlib import Path

from fastapi.testclient import TestClient

from app.character_options import CharacterOptionsRegistry
from app.characters import CharacterRegistry
from app.main import AppDependencies, create_app


class FakeAsr:
    async def transcribe(self, wav_bytes):
        return "你好"


class FakeAgent:
    async def reply(self, character, history, user_text):
        return "你好呀！"

    async def suggest_character_field(self, target_field, form_context):
        assert target_field == "subtitle"
        assert form_context["name"] == "星星船长"
        return "爱探索太空的勇敢伙伴"


class FakeTts:
    async def synthesize(self, text, config):
        yield b"\x01\x02"


def make_test_app(ready=True):
    config_dir = Path(__file__).parents[1] / "app" / "config"
    dependencies = AppDependencies(
        registry=CharacterRegistry.from_path(config_dir / "characters.json"),
        options=CharacterOptionsRegistry.from_path(
            config_dir / "character_options.json"
        ),
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


def test_character_options_endpoint():
    with TestClient(make_test_app()) as client:
        response = client.get("/api/character-options")

    assert response.status_code == 200
    assert response.json()["optionsVersion"] == 2


def test_character_suggestion_endpoint():
    with TestClient(make_test_app()) as client:
        response = client.post(
            "/api/character-suggestions",
            json={
                "targetField": "subtitle",
                "formContext": {
                    "name": "星星船长",
                    "traits": ["勇敢", "耐心"],
                },
            },
        )

    assert response.status_code == 200
    assert response.json() == {"suggestion": "爱探索太空的勇敢伙伴"}


def test_character_suggestion_requires_ready_service():
    with TestClient(make_test_app(ready=False)) as client:
        response = client.post(
            "/api/character-suggestions",
            json={"targetField": "name", "formContext": {}},
        )

    assert response.status_code == 503


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


def test_websocket_supports_custom_character():
    with TestClient(make_test_app()) as client:
        with client.websocket_connect("/ws/voice") as ws:
            ws.send_json(
                {
                    "type": "session.start",
                    "characterId": "custom_20a8d1b51412447a99abc336e306f25f",
                    "customCharacter": {
                        "displayName": "星星船长",
                        "greeting": "你好呀，我是星星船长！",
                        "identityId": "adventure_companion",
                        "traitIds": ["brave", "patient"],
                        "interestIds": ["space", "science"],
                        "description": "喜欢用有趣的小实验解释问题",
                    },
                    "voiceConfig": {"mode": "preset", "voice": "白桦"},
                }
            )
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
