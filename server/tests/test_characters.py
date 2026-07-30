import pytest
from pydantic import ValidationError

from app.characters import CharacterRegistry
from app.models import TtsMode


def test_registry_loads_two_default_characters(registry):
    assert registry.get("labrador_captain").tts.voice == "白桦"
    assert registry.get("ryder").tts.voice == "苏打"
    assert registry.get("ryder").tts.mode is TtsMode.PRESET


def test_registry_rejects_unknown_character(registry):
    with pytest.raises(KeyError):
        registry.get("unknown")


def test_registry_rejects_duplicate_ids(tmp_path):
    source = tmp_path / "characters.json"
    source.write_text(
        """
        [
          {
            "id": "same",
            "displayName": "A",
            "greeting": "hi",
            "promptProfile": "safe",
            "maxReplyCharacters": 80,
            "tts": {"mode": "preset", "model": "mimo-v2.5-tts", "voice": "白桦"}
          },
          {
            "id": "same",
            "displayName": "B",
            "greeting": "hi",
            "promptProfile": "safe",
            "maxReplyCharacters": 80,
            "tts": {"mode": "preset", "model": "mimo-v2.5-tts", "voice": "苏打"}
          }
        ]
        """,
        encoding="utf-8",
    )
    with pytest.raises(ValidationError):
        CharacterRegistry.from_path(source)
