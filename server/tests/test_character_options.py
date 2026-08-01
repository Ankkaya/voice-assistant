import json

import pytest
from pydantic import ValidationError

from app.character_options import CharacterOptionsRegistry, OptionKind


def test_option_registry_exposes_public_labels_without_prompt_text(option_registry):
    payload = option_registry.public_payload()

    assert payload["optionsVersion"] == 1
    assert payload["identities"][0] == {
        "id": "adventure_companion",
        "label": "探险伙伴",
    }
    assert "promptText" not in payload["identities"][0]
    assert payload["presetVoices"] == [
        {"id": "白桦", "label": "白桦"},
        {"id": "苏打", "label": "苏打"},
    ]


def test_option_registry_rejects_unknown_and_duplicate_ids(
    tmp_path, option_config_path, option_registry
):
    with pytest.raises(KeyError):
        option_registry.require(OptionKind.TRAIT, "not_supported")

    duplicate = tmp_path / "options.json"
    raw = json.loads(option_config_path.read_text(encoding="utf-8"))
    raw["traits"].append(dict(raw["traits"][0]))
    duplicate.write_text(json.dumps(raw, ensure_ascii=False), encoding="utf-8")

    with pytest.raises(ValidationError):
        CharacterOptionsRegistry.from_path(duplicate)
