import base64
import json

import httpx
import pytest

from app.providers.asr import XiaomiAsrProvider
from app.providers.base import ProviderError


@pytest.mark.asyncio
async def test_mimo_asr_sends_wav_data_url(httpx_mock):
    httpx_mock.add_response(
        url="https://api.xiaomimimo.com/v1/chat/completions",
        json={"choices": [{"message": {"content": "你好"}}]},
    )
    async with httpx.AsyncClient() as client:
        provider = XiaomiAsrProvider("test-key", client=client)
        result = await provider.transcribe(b"RIFFfake-wave")

    request = httpx_mock.get_request()
    body = json.loads(request.content)
    audio = body["messages"][0]["content"][0]["input_audio"]
    assert request.headers["authorization"] == "Bearer test-key"
    assert body["model"] == "mimo-v2.5-asr"
    assert body["asr_options"] == {"language": "zh"}
    assert body["stream"] is False
    assert audio["format"] == "wav"
    assert base64.b64decode(audio["data"].split(",", 1)[1]) == b"RIFFfake-wave"
    assert result == "你好"


@pytest.mark.asyncio
async def test_mimo_asr_rejects_empty_transcript(httpx_mock):
    httpx_mock.add_response(json={"choices": [{"message": {"content": "  "}}]})
    async with httpx.AsyncClient() as client:
        provider = XiaomiAsrProvider("test-key", client=client)
        with pytest.raises(ProviderError) as error:
            await provider.transcribe(b"RIFFfake-wave")
    assert error.value.code == "EMPTY_RESULT"


@pytest.mark.asyncio
async def test_mimo_asr_maps_timeout(httpx_mock):
    httpx_mock.add_exception(httpx.ReadTimeout("slow upstream"))
    async with httpx.AsyncClient() as client:
        provider = XiaomiAsrProvider("test-key", client=client)
        with pytest.raises(ProviderError) as error:
            await provider.transcribe(b"RIFFfake-wave")
    assert error.value.code == "UPSTREAM_TIMEOUT"
    assert "slow upstream" not in str(error.value)


@pytest.mark.asyncio
async def test_mimo_asr_maps_authentication_error(httpx_mock):
    httpx_mock.add_response(status_code=401, json={"error": {"message": "bad key"}})
    async with httpx.AsyncClient() as client:
        provider = XiaomiAsrProvider("test-key", client=client)
        with pytest.raises(ProviderError) as error:
            await provider.transcribe(b"RIFFfake-wave")
    assert error.value.code == "AUTHENTICATION_FAILED"
    assert "bad key" not in str(error.value)
