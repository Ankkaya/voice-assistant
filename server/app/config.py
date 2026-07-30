from functools import lru_cache

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration loaded exclusively from environment variables."""

    mimo_api_key: SecretStr | None = None
    mimo_base_url: str = "https://api.xiaomimimo.com/v1"

    llm_provider: str = "openai_compatible"
    llm_model: str = ""
    llm_base_url: str = ""
    llm_api_key: SecretStr | None = None

    voice_host: str = "0.0.0.0"
    voice_port: int = 8000
    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

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
