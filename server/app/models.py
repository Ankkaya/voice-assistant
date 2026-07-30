from enum import StrEnum
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, model_validator


class TtsMode(StrEnum):
    PRESET = "preset"
    VOICE_DESIGN = "voice_design"
    VOICE_CLONE = "voice_clone"


class TtsConfig(BaseModel):
    mode: TtsMode
    model: str
    voice: str | None = None
    voice_description: str | None = Field(default=None, alias="voiceDescription")
    reference_audio_path: str | None = Field(default=None, alias="referenceAudioPath")

    model_config = ConfigDict(populate_by_name=True)

    @model_validator(mode="after")
    def validate_mode_fields(self) -> "TtsConfig":
        if self.mode is TtsMode.PRESET and not self.voice:
            raise ValueError("preset TTS requires voice")
        if self.mode is TtsMode.VOICE_DESIGN and not self.voice_description:
            raise ValueError("voice_design TTS requires voiceDescription")
        if self.mode is TtsMode.VOICE_CLONE and not self.reference_audio_path:
            raise ValueError("voice_clone TTS requires referenceAudioPath")
        return self

    def resolved_reference_path(self, base_dir: Path) -> Path | None:
        if self.reference_audio_path is None:
            return None
        path = Path(self.reference_audio_path)
        return path if path.is_absolute() else base_dir / path


class CharacterConfig(BaseModel):
    id: str = Field(min_length=1, pattern=r"^[a-z0-9_]+$")
    display_name: str = Field(alias="displayName", min_length=1)
    greeting: str = Field(min_length=1, max_length=120)
    prompt_profile: str = Field(alias="promptProfile", min_length=1)
    max_reply_characters: int = Field(alias="maxReplyCharacters", ge=20, le=120)
    tts: TtsConfig

    model_config = ConfigDict(populate_by_name=True)


class CharacterCollection(BaseModel):
    characters: list[CharacterConfig]

    @model_validator(mode="after")
    def ids_must_be_unique(self) -> "CharacterCollection":
        ids = [character.id for character in self.characters]
        if len(ids) != len(set(ids)):
            raise ValueError("character IDs must be unique")
        return self
