import base64
import json

import httpx
import pytest

from app.models import TtsConfig, TtsMode
from app.providers.base import ProviderConfigError, ProviderError
from app.providers.tts import XiaomiTtsProvider


def sse_audio(*chunks: bytes) -> bytes:
    lines = []
    for chunk in chunks:
        data = base64.b64encode(chunk).decode("ascii")
        body = {"choices": [{"delta": {"audio": {"data": data}}}]}
        lines.append(f"data: {json.dumps(body)}\n\n")
    lines.append("data: [DONE]\n\n")
    return "".join(lines).encode()


@pytest.mark.asyncio
async def test_preset_stream_decodes_pcm_chunks(httpx_mock):
    httpx_mock.add_response(content=sse_audio(b"\x01\x02", b"\x03\x04"))
    config = TtsConfig(
        mode=TtsMode.PRESET,
        model="mimo-v2.5-tts",
        voice="白桦",
    )
    async with httpx.AsyncClient() as client:
        provider = XiaomiTtsProvider("test-key", client=client)
        chunks = [chunk async for chunk in provider.synthesize("你好", config)]

    request = httpx_mock.get_request()
    body = json.loads(request.content)
    assert body["audio"] == {"format": "pcm16", "voice": "白桦"}
    assert body["stream"] is True
    assert b"".join(chunks) == b"\x01\x02\x03\x04"


@pytest.mark.asyncio
async def test_voice_design_uses_description(httpx_mock):
    httpx_mock.add_response(content=sse_audio(b"\x01\x02"))
    config = TtsConfig(
        mode=TtsMode.VOICE_DESIGN,
        model="mimo-v2.5-tts-voicedesign",
        voiceDescription="温暖活泼的年轻男声，普通话清晰",
    )
    async with httpx.AsyncClient() as client:
        provider = XiaomiTtsProvider("test-key", client=client)
        assert [chunk async for chunk in provider.synthesize("出发吧", config)]

    body = json.loads(httpx_mock.get_request().content)
    assert body["messages"][0]["content"] == "温暖活泼的年轻男声，普通话清晰"
    assert body["messages"][1]["content"] == "出发吧"
    assert body["audio"]["format"] == "pcm16"


@pytest.mark.asyncio
async def test_voice_clone_embeds_authorized_reference(httpx_mock, tmp_path):
    reference = tmp_path / "voice.wav"
    reference.write_bytes(b"RIFFauthorized")
    httpx_mock.add_response(content=sse_audio(b"\x01\x02"))
    config = TtsConfig(
        mode=TtsMode.VOICE_CLONE,
        model="mimo-v2.5-tts-voiceclone",
        referenceAudioPath=str(reference),
    )
    async with httpx.AsyncClient() as client:
        provider = XiaomiTtsProvider("test-key", client=client)
        assert [chunk async for chunk in provider.synthesize("你好", config)]

    body = json.loads(httpx_mock.get_request().content)
    voice = body["audio"]["voice"]
    assert voice.startswith("data:audio/wav;base64,")
    assert base64.b64decode(voice.split(",", 1)[1]) == b"RIFFauthorized"


def test_clone_requires_existing_reference_audio(tmp_path):
    config = TtsConfig(
        mode=TtsMode.VOICE_CLONE,
        model="mimo-v2.5-tts-voiceclone",
        referenceAudioPath=str(tmp_path / "missing.wav"),
    )
    provider = XiaomiTtsProvider("test-key", client=httpx.AsyncClient())
    with pytest.raises(ProviderConfigError):
        provider.validate(config)


@pytest.mark.asyncio
async def test_tts_rejects_stream_without_audio(httpx_mock):
    httpx_mock.add_response(content=b"data: [DONE]\n\n")
    config = TtsConfig(
        mode=TtsMode.PRESET,
        model="mimo-v2.5-tts",
        voice="白桦",
    )
    async with httpx.AsyncClient() as client:
        provider = XiaomiTtsProvider("test-key", client=client)
        with pytest.raises(ProviderError) as error:
            _ = [chunk async for chunk in provider.synthesize("你好", config)]
    assert error.value.code == "EMPTY_RESULT"

