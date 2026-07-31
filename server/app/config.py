from functools import lru_cache
from pathlib import Path

from pydantic import SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration loaded from environment variables or secret files."""

    mimo_api_key: SecretStr | None = None
    mimo_api_key_file: Path | None = None
    mimo_base_url: str = "https://token-plan-cn.xiaomimimo.com/v1"

    llm_provider: str = "openai_compatible"
    llm_model: str = ""
    llm_base_url: str = ""
    llm_api_key: SecretStr | None = None
    llm_api_key_file: Path | None = None

    voice_host: str = "0.0.0.0"
    voice_port: int = 8000
    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    @model_validator(mode="after")
    def load_file_backed_secrets(self) -> "Settings":
        self.mimo_api_key = self._resolve_secret(
            self.mimo_api_key,
            self.mimo_api_key_file,
            "MIMO_API_KEY_FILE",
        )
        self.llm_api_key = self._resolve_secret(
            self.llm_api_key,
            self.llm_api_key_file,
            "LLM_API_KEY_FILE",
        )
        return self

    @staticmethod
    def _resolve_secret(
        direct_value: SecretStr | None,
        file_path: Path | None,
        field_name: str,
    ) -> SecretStr | None:
        if direct_value is not None:
            value = direct_value.get_secret_value().strip()
            if value:
                return SecretStr(value)
        if file_path is None:
            return None
        try:
            value = file_path.read_text(encoding="utf-8").strip()
        except OSError as exc:
            raise ValueError(f"{field_name} could not be read") from exc
        if not value:
            raise ValueError(f"{field_name} is empty")
        return SecretStr(value)

    @property
    def providers_ready(self) -> bool:
        return bool(
            self.mimo_api_key
            and self.llm_api_key
            and self.llm_model.strip()
            and self.llm_base_url.strip()
        )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
