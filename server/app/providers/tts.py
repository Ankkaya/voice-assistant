import asyncio
import base64
import json
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Protocol

import httpx

from ..models import TtsConfig, TtsMode
from .base import ProviderConfigError, ProviderError


class TtsProvider(Protocol):
    def synthesize(self, text: str, config: TtsConfig) -> AsyncIterator[bytes]: ...


class XiaomiTtsProvider:
    def __init__(
        self,
        api_key: str,
        *,
        client: httpx.AsyncClient,
        base_url: str = "https://token-plan-cn.xiaomimimo.com/v1",
        reference_base_dir: Path | None = None,
    ) -> None:
        if not api_key:
            raise ValueError("MiMo API key is required")
        self._api_key = api_key
        self._client = client
        self._endpoint = f"{base_url.rstrip('/')}/chat/completions"
        self._reference_base_dir = reference_base_dir or Path.cwd()

    def validate(self, config: TtsConfig) -> None:
        if config.mode is TtsMode.PRESET:
            if not config.voice:
                raise ProviderConfigError("tts")
            return
        if config.mode is TtsMode.VOICE_DESIGN:
            if not config.voice_description:
                raise ProviderConfigError("tts")
            return
        if config.reference_audio_data:
            if config.reference_audio_mime not in {"audio/wav", "audio/mpeg"}:
                raise ProviderConfigError("tts", "UNSUPPORTED_REFERENCE_FORMAT")
            return
        reference = config.resolved_reference_path(self._reference_base_dir)
        if reference is None or not reference.is_file():
            raise ProviderConfigError("tts", "REFERENCE_AUDIO_NOT_FOUND")
        if reference.suffix.lower() not in {".wav", ".mp3"}:
            raise ProviderConfigError("tts", "UNSUPPORTED_REFERENCE_FORMAT")

    async def synthesize(
        self,
        text: str,
        config: TtsConfig,
    ) -> AsyncIterator[bytes]:
        self.validate(config)
        body = self._request_body(text, config)
        yielded_audio = False
        try:
            async with self._client.stream(
                "POST",
                self._endpoint,
                headers={
                    "Authorization": f"Bearer {self._api_key}",
                    "Content-Type": "application/json",
                },
                json=body,
                timeout=httpx.Timeout(connect=15.0, read=None, write=15.0, pool=15.0),
            ) as response:
                self._raise_for_status(response.status_code)
                lines = response.aiter_lines()
                # MiMo currently provides low-latency streaming only for the
                # preset model. Voice design and clone return one compatible
                # stream event after all inference has completed.
                next_timeout = (
                    15.0 if config.mode is TtsMode.PRESET else 45.0
                )
                while True:
                    try:
                        line = await asyncio.wait_for(anext(lines), timeout=next_timeout)
                    except StopAsyncIteration:
                        break
                    except TimeoutError as exc:
                        raise ProviderError("tts", "UPSTREAM_TIMEOUT") from exc
                    if not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if not payload or payload == "[DONE]":
                        continue
                    try:
                        body_chunk = json.loads(payload)
                        choices = body_chunk["choices"]
                        if not choices and "usage" in body_chunk:
                            continue
                        delta = choices[0]["delta"]
                        audio = delta.get("audio")
                        if audio is None:
                            continue
                        encoded = audio["data"]
                        chunk = base64.b64decode(encoded, validate=True)
                    except (
                        AttributeError,
                        KeyError,
                        IndexError,
                        TypeError,
                        ValueError,
                        json.JSONDecodeError,
                    ) as exc:
                        raise ProviderError("tts", "INVALID_RESPONSE") from exc
                    if chunk:
                        yielded_audio = True
                        next_timeout = 5.0
                        yield chunk
        except ProviderError:
            raise
        except httpx.TimeoutException as exc:
            raise ProviderError("tts", "UPSTREAM_TIMEOUT") from exc
        except httpx.HTTPError as exc:
            raise ProviderError("tts", "UPSTREAM_UNAVAILABLE") from exc
        if not yielded_audio:
            raise ProviderError("tts", "EMPTY_RESULT")

    def _request_body(self, text: str, config: TtsConfig) -> dict:
        style = "使用适合6到9岁儿童的温暖、清晰、自然语气，语速适中。"
        audio: dict[str, object] = {"format": "pcm16"}
        if config.mode is TtsMode.PRESET:
            messages = [
                {"role": "user", "content": style},
                {"role": "assistant", "content": text},
            ]
            audio["voice"] = config.voice
        elif config.mode is TtsMode.VOICE_DESIGN:
            messages = [
                {"role": "user", "content": config.voice_description},
                {"role": "assistant", "content": text},
            ]
            audio["optimize_text_preview"] = False
        else:
            if config.reference_audio_data:
                mime = config.reference_audio_mime
                audio_bytes = config.reference_audio_data
            else:
                reference = config.resolved_reference_path(self._reference_base_dir)
                assert reference is not None
                mime = (
                    "audio/wav"
                    if reference.suffix.lower() == ".wav"
                    else "audio/mpeg"
                )
                audio_bytes = reference.read_bytes()
            encoded = base64.b64encode(audio_bytes).decode("ascii")
            messages = [
                {"role": "user", "content": style},
                {"role": "assistant", "content": text},
            ]
            audio["voice"] = f"data:{mime};base64,{encoded}"
        return {
            "model": config.model,
            "messages": messages,
            "audio": audio,
            "stream": True,
        }

    @staticmethod
    def _raise_for_status(status_code: int) -> None:
        if status_code in {401, 403}:
            raise ProviderError("tts", "AUTHENTICATION_FAILED", recoverable=False)
        if status_code == 429:
            raise ProviderError("tts", "RATE_LIMITED")
        if status_code >= 500:
            raise ProviderError("tts", "UPSTREAM_UNAVAILABLE")
        if status_code >= 400:
            raise ProviderError("tts", "UPSTREAM_REJECTED")
