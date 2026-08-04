import re
from typing import Annotated, Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    TypeAdapter,
    field_validator,
    model_validator,
)

from .models import TtsMode


CharacterSuggestionField = Literal[
    "name",
    "subtitle",
    "description",
    "greeting",
    "promptProfile",
    "voiceDescription",
]


class Event(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")


class CharacterSuggestionRequest(Event):
    target_field: CharacterSuggestionField = Field(alias="targetField")
    form_context: dict[str, str | list[str]] = Field(alias="formContext")

    @model_validator(mode="after")
    def context_is_small_and_structured(self) -> "CharacterSuggestionRequest":
        allowed_keys = {
            "name",
            "subtitle",
            "identity",
            "traits",
            "interests",
            "description",
            "greeting",
            "promptProfile",
            "voiceDescription",
        }
        if not set(self.form_context).issubset(allowed_keys):
            raise ValueError("form context contains unsupported fields")
        total_characters = 0
        for value in self.form_context.values():
            values = value if isinstance(value, list) else [value]
            if len(values) > 3:
                raise ValueError("form context list is too long")
            for item in values:
                if len(item) > 2000:
                    raise ValueError("form context value is too long")
                total_characters += len(item)
        if total_characters > 5000:
            raise ValueError("form context is too large")
        return self


class CharacterSuggestionResponse(Event):
    suggestion: str


class CustomCharacterSpec(Event):
    display_name: str = Field(alias="displayName", min_length=1, max_length=20)
    greeting: str = Field(min_length=1, max_length=120)
    identity_id: str = Field(
        alias="identityId", pattern=r"^[a-z][a-z0-9_]*$"
    )
    trait_ids: list[str] = Field(alias="traitIds", min_length=1, max_length=3)
    interest_ids: list[str] = Field(alias="interestIds", max_length=3)
    description: str = Field(default="", max_length=200)
    prompt_profile: str = Field(default="", alias="promptProfile", max_length=2000)

    @field_validator(
        "display_name", "greeting", "description", "prompt_profile", mode="before"
    )
    @classmethod
    def trim_free_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @model_validator(mode="after")
    def options_must_be_unique(self) -> "CustomCharacterSpec":
        if len(set(self.trait_ids)) != len(self.trait_ids):
            raise ValueError("trait IDs must be unique")
        if len(set(self.interest_ids)) != len(self.interest_ids):
            raise ValueError("interest IDs must be unique")
        return self


class SessionVoiceConfig(Event):
    mode: TtsMode
    voice: str | None = Field(default=None, min_length=1, max_length=40)
    voice_description: str | None = Field(
        default=None,
        alias="voiceDescription",
        min_length=8,
        max_length=500,
    )
    reference_id: str | None = Field(
        default=None,
        alias="referenceId",
        pattern=r"^[a-f0-9]{32}$",
    )

    @field_validator("voice", "voice_description", mode="before")
    @classmethod
    def trim_voice_text(cls, value: object) -> object:
        return value.strip() if isinstance(value, str) else value

    @model_validator(mode="after")
    def mode_fields_match(self) -> "SessionVoiceConfig":
        if self.mode is TtsMode.PRESET:
            self.voice_description = None
            self.reference_id = None
            return self
        if self.voice is not None:
            raise ValueError("only preset mode accepts voice")
        if self.mode is TtsMode.VOICE_DESIGN:
            if not self.voice_description:
                raise ValueError("voice design requires a description")
            self.reference_id = None
            return self
        if not self.reference_id:
            raise ValueError("voice clone requires a reference")
        self.voice_description = None
        return self


class SessionStart(Event):
    type: Literal["session.start"] = "session.start"
    character_id: str = Field(alias="characterId", min_length=1)
    custom_character: CustomCharacterSpec | None = Field(
        default=None, alias="customCharacter"
    )
    voice_config: SessionVoiceConfig | None = Field(default=None, alias="voiceConfig")

    @model_validator(mode="after")
    def custom_fields_match_id(self) -> "SessionStart":
        is_custom = self.character_id.startswith("custom_")
        if is_custom:
            if re.fullmatch(r"custom_[a-f0-9]{32}", self.character_id) is None:
                raise ValueError("invalid custom character ID")
            if self.custom_character is None or self.voice_config is None:
                raise ValueError("custom characters require snapshot and voice")
            if (
                self.voice_config.mode is TtsMode.PRESET
                and not self.voice_config.voice
            ):
                raise ValueError("custom preset voice is required")
        elif self.custom_character is not None:
            raise ValueError("bundled characters cannot include custom snapshot")
        return self


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
