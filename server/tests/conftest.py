from pathlib import Path

import pytest


@pytest.fixture
def character_config_path() -> Path:
    return Path(__file__).parents[1] / "app" / "config" / "characters.json"


@pytest.fixture
def option_config_path() -> Path:
    return Path(__file__).parents[1] / "app" / "config" / "character_options.json"


@pytest.fixture
def registry(character_config_path):
    from app.characters import CharacterRegistry

    return CharacterRegistry.from_path(character_config_path)


@pytest.fixture
def option_registry(option_config_path):
    from app.character_options import CharacterOptionsRegistry

    return CharacterOptionsRegistry.from_path(option_config_path)
