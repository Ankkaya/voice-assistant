import logging

import httpx
import pytest

from app.providers.asr import XiaomiAsrProvider
from app.providers.base import ProviderError


@pytest.mark.asyncio
async def test_provider_error_does_not_log_audio_key_or_upstream_body(httpx_mock, caplog):
    httpx_mock.add_response(
        status_code=401,
        json={"error": {"message": "我的学校是测试小学"}},
    )
    caplog.set_level(logging.DEBUG)
    async with httpx.AsyncClient() as client:
        provider = XiaomiAsrProvider("secret-key", client=client)
        with pytest.raises(ProviderError):
            await provider.transcribe(b"RIFF-sensitive-audio")

    combined = "\n".join(record.getMessage() for record in caplog.records)
    assert "secret-key" not in combined
    assert "测试小学" not in combined
    assert "sensitive-audio" not in combined

