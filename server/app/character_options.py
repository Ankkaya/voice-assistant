import json
from enum import StrEnum
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, model_validator


class OptionKind(StrEnum):
    IDENTITY = "identities"
    TRAIT = "traits"
    INTEREST = "interests"


class CharacterOption(BaseModel):
    id: str = Field(pattern=r"^[a-z][a-z0-9_]*$")
    label: str = Field(min_length=1, max_length=20)
    prompt_text: str = Field(alias="promptText", min_length=1, max_length=120)

    model_config = ConfigDict(populate_by_name=True, extra="forbid")


class PresetVoiceOption(BaseModel):
    id: str = Field(min_length=1, max_length=40)
    label: str = Field(min_length=1, max_length=40)

    model_config = ConfigDict(extra="forbid")


class CharacterOptionsCatalog(BaseModel):
    options_version: int = Field(alias="optionsVersion", ge=1)
    identities: list[CharacterOption] = Field(min_length=1)
    traits: list[CharacterOption] = Field(min_length=1)
    interests: list[CharacterOption] = Field(min_length=1)
    preset_voices: list[PresetVoiceOption] = Field(
        alias="presetVoices", min_length=1
    )

    model_config = ConfigDict(populate_by_name=True, extra="forbid")

    @model_validator(mode="after")
    def ids_must_be_unique(self) -> "CharacterOptionsCatalog":
        for items in (
            self.identities,
            self.traits,
            self.interests,
            self.preset_voices,
        ):
            ids = [item.id for item in items]
            if len(ids) != len(set(ids)):
                raise ValueError("option IDs must be unique within each collection")
        return self


class CharacterOptionsRegistry:
    def __init__(self, catalog: CharacterOptionsCatalog) -> None:
        self._catalog = catalog
        self._by_kind = {
            OptionKind.IDENTITY: {item.id: item for item in catalog.identities},
            OptionKind.TRAIT: {item.id: item for item in catalog.traits},
            OptionKind.INTEREST: {item.id: item for item in catalog.interests},
        }
        self._voices = {item.id: item for item in catalog.preset_voices}

    @classmethod
    def from_path(cls, path: Path) -> "CharacterOptionsRegistry":
        raw = json.loads(path.read_text(encoding="utf-8"))
        return cls(CharacterOptionsCatalog.model_validate(raw))

    def require(self, kind: OptionKind, option_id: str) -> CharacterOption:
        try:
            return self._by_kind[kind][option_id]
        except KeyError:
            raise KeyError(f"unsupported {kind.value} option") from None

    def require_preset_voice(self, voice: str) -> str:
        if voice not in self._voices:
            raise KeyError("unsupported preset voice")
        return voice

    def public_payload(self) -> dict[str, object]:
        return self._catalog.model_dump(
            by_alias=True,
            exclude={
                "identities": {"__all__": {"prompt_text"}},
                "traits": {"__all__": {"prompt_text"}},
                "interests": {"__all__": {"prompt_text"}},
            },
        )
