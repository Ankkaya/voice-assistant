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
    reference_audio_data: bytes | None = Field(default=None, exclude=True)
    reference_audio_mime: str | None = Field(default=None, exclude=True)

    model_config = ConfigDict(populate_by_name=True, extra="forbid")

    @model_validator(mode="after")
    def validate_mode_fields(self) -> "TtsConfig":
        reference_supplied = bool(
            self.reference_audio_path or self.reference_audio_data
        )
        if self.mode is TtsMode.PRESET:
            if self.model != "mimo-v2.5-tts" or not self.voice:
                raise ValueError("preset TTS requires mimo-v2.5-tts and voice")
            if self.voice_description or reference_supplied:
                raise ValueError("preset TTS only accepts voice")
        elif self.mode is TtsMode.VOICE_DESIGN:
            if (
                self.model != "mimo-v2.5-tts-voicedesign"
                or not self.voice_description
            ):
                raise ValueError(
                    "voice_design TTS requires its model and voiceDescription"
                )
            if self.voice or reference_supplied:
                raise ValueError("voice_design TTS only accepts voiceDescription")
        else:
            if self.model != "mimo-v2.5-tts-voiceclone" or not reference_supplied:
                raise ValueError(
                    "voice_clone TTS requires its model and reference audio"
                )
            if self.voice or self.voice_description:
                raise ValueError("voice_clone TTS only accepts reference audio")
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
