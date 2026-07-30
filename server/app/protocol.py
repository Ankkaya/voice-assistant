from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter


class Event(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")


class SessionStart(Event):
    type: Literal["session.start"] = "session.start"
    character_id: str = Field(alias="characterId", min_length=1)


class InputAudioStart(Event):
    type: Literal["input.audio.start"] = "input.audio.start"
    turn_id: str = Field(alias="turnId", min_length=1)


class InputAudioCommit(Event):
    type: Literal["input.audio.commit"] = "input.audio.commit"
    turn_id: str = Field(alias="turnId", min_length=1)


class SessionEnd(Event):
    type: Literal["session.end"] = "session.end"


class Ping(Event):
    type: Literal["ping"] = "ping"
    timestamp: int


ClientEvent = Annotated[
    SessionStart | InputAudioStart | InputAudioCommit | SessionEnd | Ping,
    Field(discriminator="type"),
]
_client_event_adapter = TypeAdapter(ClientEvent)


def parse_client_event(raw: str) -> ClientEvent:
    return _client_event_adapter.validate_json(raw)


class SessionReady(Event):
    type: Literal["session.ready"] = "session.ready"
    session_id: str = Field(alias="sessionId")
    max_duration_seconds: int = Field(default=600, alias="maxDurationSeconds")


class UserTranscript(Event):
    type: Literal["user.transcript"] = "user.transcript"
    turn_id: str = Field(alias="turnId")
    text: str


class AssistantThinking(Event):
    type: Literal["assistant.thinking"] = "assistant.thinking"
    turn_id: str = Field(alias="turnId")


class AssistantAudioStart(Event):
    type: Literal["assistant.audio.start"] = "assistant.audio.start"
    turn_id: str = Field(alias="turnId")
    encoding: Literal["pcm16le"] = "pcm16le"
    sample_rate: int = Field(default=24000, alias="sampleRate")
    channels: int = 1


class AssistantAudioEnd(Event):
    type: Literal["assistant.audio.end"] = "assistant.audio.end"
    turn_id: str = Field(alias="turnId")


class TurnError(Event):
    type: Literal["turn.error"] = "turn.error"
    stage: str
    code: str
    recoverable: bool
    message: str


class Pong(Event):
    type: Literal["pong"] = "pong"
    timestamp: int


ServerEvent = (
    SessionReady
    | UserTranscript
    | AssistantThinking
    | AssistantAudioStart
    | AssistantAudioEnd
    | TurnError
    | Pong
)


def serialize_server_event(event: ServerEvent) -> str:
    return event.model_dump_json(by_alias=True)
