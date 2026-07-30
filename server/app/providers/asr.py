import base64
from typing import Protocol

import httpx

from .base import ProviderError


class AsrProvider(Protocol):
    async def transcribe(self, wav_bytes: bytes) -> str: ...


class XiaomiAsrProvider:
    def __init__(
        self,
        api_key: str,
        *,
        client: httpx.AsyncClient,
        base_url: str = "https://api.xiaomimimo.com/v1",
    ) -> None:
        if not api_key:
            raise ValueError("MiMo API key is required")
        self._api_key = api_key
        self._client = client
        self._endpoint = f"{base_url.rstrip('/')}/chat/completions"

    async def transcribe(self, wav_bytes: bytes) -> str:
        encoded = base64.b64encode(wav_bytes).decode("ascii")
        body = {
            "model": "mimo-v2.5-asr",
            "messages": [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "input_audio",
                            "input_audio": {
                                "data": f"data:audio/wav;base64,{encoded}",
                                "format": "wav",
                            },
                        }
                    ],
                }
            ],
            "asr_options": {"language": "zh"},
            "stream": False,
        }
        try:
            response = await self._client.post(
                self._endpoint,
                headers={
                    "Authorization": f"Bearer {self._api_key}",
                    "Content-Type": "application/json",
                },
                json=body,
                timeout=20.0,
            )
        except httpx.TimeoutException as exc:
            raise ProviderError("asr", "UPSTREAM_TIMEOUT") from exc
        except httpx.HTTPError as exc:
            raise ProviderError("asr", "UPSTREAM_UNAVAILABLE") from exc

        if response.status_code in {401, 403}:
            raise ProviderError("asr", "AUTHENTICATION_FAILED", recoverable=False)
        if response.status_code == 429:
            raise ProviderError("asr", "RATE_LIMITED")
        if response.status_code >= 500:
            raise ProviderError("asr", "UPSTREAM_UNAVAILABLE")
        if response.is_error:
            raise ProviderError("asr", "UPSTREAM_REJECTED")

        try:
            text = response.json()["choices"][0]["message"]["content"].strip()
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            raise ProviderError("asr", "INVALID_RESPONSE") from exc
        if not text:
            raise ProviderError("asr", "EMPTY_RESULT")
        return text

