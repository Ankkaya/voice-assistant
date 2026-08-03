import copy
import json

import pytest
from pydantic import ValidationError

from app.protocol import (
    AssistantAudioStart,
    InputAudioStart,
    SessionStart,
    TurnError,
    parse_client_event,
    serialize_server_event,
)


CUSTOM_START = {
    "type": "session.start",
    "characterId": "custom_20a8d1b51412447a99abc336e306f25f",
    "customCharacter": {
        "displayName": "星星船长",
        "greeting": "你好呀，我是星星船长！",
        "identityId": "adventure_companion",
        "traitIds": ["brave", "patient"],
        "interestIds": ["space", "science"],
        "description": "喜欢用有趣的小实验解释问题",
        "promptProfile": "保持耐心，多用太空冒险的比喻。",
    },
    "voiceConfig": {"mode": "preset", "voice": "白桦"},
}


def test_parse_audio_start_requires_turn_id():
    with pytest.raises(ValidationError):
        parse_client_event('{"type":"input.audio.start"}')


def test_parse_audio_start():
    event = parse_client_event('{"type":"input.audio.start","turnId":"turn_1"}')
    assert isinstance(event, InputAudioStart)
    assert event.turn_id == "turn_1"


def test_custom_session_start_parses():
    event = parse_client_event(json.dumps(CUSTOM_START, ensure_ascii=False))

    assert isinstance(event, SessionStart)
    assert event.custom_character is not None
    assert event.custom_character.display_name == "星星船长"
    assert event.custom_character.prompt_profile == "保持耐心，多用太空冒险的比喻。"
    assert event.voice_config is not None
    assert event.voice_config.voice == "白桦"


@pytest.mark.parametrize(
    "mutation",
    [
        lambda value: value.pop("customCharacter"),
        lambda value: value.pop("voiceConfig"),
        lambda value: value.update(characterId="ryder"),
        lambda value: value.update(characterId="custom_not_a_uuid"),
    ],
)
def test_custom_session_start_rejects_inconsistent_shape(mutation):
    value = copy.deepcopy(CUSTOM_START)
    mutation(value)

    with pytest.raises(ValidationError):
        parse_client_event(json.dumps(value, ensure_ascii=False))


def test_bundled_session_start_remains_backward_compatible():
    event = parse_client_event('{"type":"session.start","characterId":"ryder"}')

    assert isinstance(event, SessionStart)
    assert event.custom_character is None
    assert event.voice_config is None


def test_audio_start_serializes_camel_case_metadata():
    raw = serialize_server_event(
        AssistantAudioStart(turnId="turn_1", sampleRate=24000)
    )
    body = json.loads(raw)
    assert body == {
        "type": "assistant.audio.start",
        "turnId": "turn_1",
        "encoding": "pcm16le",
        "sampleRate": 24000,
        "channels": 1,
    }


def test_turn_error_contains_only_stable_fields():
    body = json.loads(
        serialize_server_event(
            TurnError(
                stage="asr",
                code="UPSTREAM_TIMEOUT",
                recoverable=True,
                message="请再说一次",
            )
        )
    )
    assert set(body) == {"type", "stage", "code", "recoverable", "message"}
