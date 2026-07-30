import json
from pathlib import Path

from pydantic import ValidationError

from .models import CharacterCollection, CharacterConfig


class CharacterRegistry:
    def __init__(self, characters: list[CharacterConfig], source_dir: Path):
        self._characters = {character.id: character for character in characters}
        self.source_dir = source_dir

    @classmethod
    def from_path(cls, path: Path) -> "CharacterRegistry":
        raw = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(raw, list):
            raise ValidationError.from_exception_data("CharacterCollection", [])
        collection = CharacterCollection.model_validate({"characters": raw})
        return cls(collection.characters, path.parent)

    def get(self, character_id: str) -> CharacterConfig:
        try:
            return self._characters[character_id]
        except KeyError:
            raise KeyError(f"unknown character: {character_id}") from None

    def all(self) -> tuple[CharacterConfig, ...]:
        return tuple(self._characters.values())
