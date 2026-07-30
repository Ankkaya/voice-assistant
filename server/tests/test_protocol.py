import json

import pytest
from pydantic import ValidationError

from app.protocol import (
    AssistantAudioStart,
    InputAudioStart,
    TurnError,
    parse_client_event,
    serialize_server_event,
)


def test_parse_audio_start_requires_turn_id():
    with pytest.raises(ValidationError):
        parse_client_event('{"type":"input.audio.start"}')


def test_parse_audio_start():
    event = parse_client_event('{"type":"input.audio.start","turnId":"turn_1"}')
    assert isinstance(event, InputAudioStart)
    assert event.turn_id == "turn_1"


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

