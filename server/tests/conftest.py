from pathlib import Path

import pytest


@pytest.fixture
def character_config_path() -> Path:
    return Path(__file__).parents[1] / "app" / "config" / "characters.json"


@pytest.fixture
def registry(character_config_path):
    from app.characters import CharacterRegistry

    return CharacterRegistry.from_path(character_config_path)

