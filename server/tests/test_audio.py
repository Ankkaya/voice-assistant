import io
import wave

import pytest

from app.audio import pcm16le_duration_seconds, pcm16le_to_wav


def test_pcm_is_wrapped_as_16khz_mono_wav():
    pcm = b"\x00\x00" * 160
    wav = pcm16le_to_wav(pcm)

    with wave.open(io.BytesIO(wav), "rb") as source:
        assert source.getframerate() == 16000
        assert source.getnchannels() == 1
        assert source.getsampwidth() == 2
        assert source.readframes(160) == pcm


def test_odd_pcm_payload_is_rejected():
    with pytest.raises(ValueError, match="complete 16-bit samples"):
        pcm16le_to_wav(b"\x00")


def test_duration_uses_sample_rate_and_channels():
    assert pcm16le_duration_seconds(b"\x00\x00" * 16000) == pytest.approx(1.0)

