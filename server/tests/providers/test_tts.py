import base64
import json

import httpx
import pytest
from pydantic import ValidationError

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
async def test_stream_skips_status_events_without_audio_data(httpx_mock):
    audio_data = base64.b64encode(b"\x01\x02").decode("ascii")
    events = [
        {"choices": [{"delta": {"audio": None}, "finish_reason": None}]},
        {"choices": [{"delta": {"audio": {"data": audio_data}}}]},
        {"choices": [{"delta": {"audio": None}, "finish_reason": "stop"}]},
        {"choices": [], "usage": {"total_tokens": 1}},
    ]
    content = "".join(f"data: {json.dumps(event)}\n\n" for event in events)
    content += "data: [DONE]\n\n"
    httpx_mock.add_response(content=content.encode())
    config = TtsConfig(
        mode=TtsMode.PRESET,
        model="mimo-v2.5-tts",
        voice="白桦",
    )

    async with httpx.AsyncClient() as client:
        provider = XiaomiTtsProvider("test-key", client=client)
        chunks = [chunk async for chunk in provider.synthesize("你好", config)]

    assert chunks == [b"\x01\x02"]


@pytest.mark.asyncio
async def test_stream_rejects_malformed_audio_event(httpx_mock):
    event = {"choices": [{"delta": {"audio": {"id": "audio-id"}}}]}
    content = f"data: {json.dumps(event)}\n\ndata: [DONE]\n\n"
    httpx_mock.add_response(content=content.encode())
    config = TtsConfig(
        mode=TtsMode.PRESET,
        model="mimo-v2.5-tts",
        voice="白桦",
    )

    async with httpx.AsyncClient() as client:
        provider = XiaomiTtsProvider("test-key", client=client)
        with pytest.raises(ProviderError) as error:
            _ = [chunk async for chunk in provider.synthesize("你好", config)]

    assert error.value.code == "INVALID_RESPONSE"


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
    assert body["audio"] == {
        "format": "pcm16",
        "optimize_text_preview": False,
    }
    assert "voice" not in body["audio"]


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
    assert body["messages"][1] == {"role": "assistant", "content": "你好"}
    assert "optimize_text_preview" not in body["audio"]


def test_clone_requires_existing_reference_audio(tmp_path):
    config = TtsConfig(
        mode=TtsMode.VOICE_CLONE,
        model="mimo-v2.5-tts-voiceclone",
        referenceAudioPath=str(tmp_path / "missing.wav"),
    )
    provider = XiaomiTtsProvider("test-key", client=httpx.AsyncClient())
    with pytest.raises(ProviderConfigError):
        provider.validate(config)


def test_clone_accepts_in_memory_uploaded_reference():
    config = TtsConfig(
        mode="voice_clone",
        model="mimo-v2.5-tts-voiceclone",
        reference_audio_data=b"RIFFauthorized",
        reference_audio_mime="audio/wav",
    )
    provider = XiaomiTtsProvider("test-key", client=httpx.AsyncClient())

    provider.validate(config)


@pytest.mark.parametrize(
    ("values", "message"),
    [
        (
            {
                "mode": "preset",
                "model": "mimo-v2.5-tts-voicedesign",
                "voice": "白桦",
            },
            "preset TTS requires mimo-v2.5-tts",
        ),
        (
            {
                "mode": "voice_design",
                "model": "mimo-v2.5-tts-voicedesign",
                "voice": "白桦",
                "voiceDescription": "温暖清亮的少年声音",
            },
            "voice_design TTS only accepts voiceDescription",
        ),
        (
            {
                "mode": "voice_clone",
                "model": "mimo-v2.5-tts-voiceclone",
                "voiceDescription": "不应传入的描述",
                "reference_audio_data": b"RIFFauthorized",
                "reference_audio_mime": "audio/wav",
            },
            "voice_clone TTS only accepts reference audio",
        ),
    ],
)
def test_tts_config_rejects_model_or_mode_field_mismatch(values, message):
    with pytest.raises(ValidationError, match=message):
        TtsConfig.model_validate(values)


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
