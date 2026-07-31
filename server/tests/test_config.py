import pytest
from pydantic import ValidationError

from app.config import Settings


def test_settings_load_keys_from_secret_files(tmp_path):
    mimo = tmp_path / "mimo"
    llm = tmp_path / "llm"
    mimo.write_text("mimo-file-key\n", encoding="utf-8")
    llm.write_text("llm-file-key\n", encoding="utf-8")

    settings = Settings(
        _env_file=None,
        mimo_api_key_file=mimo,
        llm_api_key_file=llm,
    )

    assert settings.mimo_api_key is not None
    assert settings.llm_api_key is not None
    assert settings.mimo_api_key.get_secret_value() == "mimo-file-key"
    assert settings.llm_api_key.get_secret_value() == "llm-file-key"


def test_direct_key_takes_precedence_over_secret_file(tmp_path):
    secret = tmp_path / "mimo"
    secret.write_text("file-key", encoding="utf-8")

    settings = Settings(
        _env_file=None,
        mimo_api_key="direct-key",
        mimo_api_key_file=secret,
    )

    assert settings.mimo_api_key is not None
    assert settings.mimo_api_key.get_secret_value() == "direct-key"


def test_missing_secret_file_is_rejected_without_content(tmp_path):
    missing = tmp_path / "missing"

    with pytest.raises(
        ValidationError,
        match="MIMO_API_KEY_FILE could not be read",
    ):
        Settings(_env_file=None, mimo_api_key_file=missing)


def test_empty_secret_file_is_rejected(tmp_path):
    empty = tmp_path / "empty"
    empty.write_text("  \n", encoding="utf-8")

    with pytest.raises(ValidationError, match="MIMO_API_KEY_FILE is empty"):
        Settings(_env_file=None, mimo_api_key_file=empty)
