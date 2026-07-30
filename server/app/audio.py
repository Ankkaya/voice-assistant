import io
import wave


def pcm16le_to_wav(
    pcm: bytes,
    sample_rate: int = 16000,
    channels: int = 1,
) -> bytes:
    """Wrap complete PCM16LE samples in a WAV container without touching disk."""
    if sample_rate <= 0:
        raise ValueError("sample_rate must be positive")
    if channels <= 0:
        raise ValueError("channels must be positive")
    frame_width = 2 * channels
    if len(pcm) % frame_width:
        raise ValueError("PCM payload must contain complete 16-bit samples")

    target = io.BytesIO()
    with wave.open(target, "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(pcm)
    return target.getvalue()


def pcm16le_duration_seconds(
    pcm: bytes,
    sample_rate: int = 16000,
    channels: int = 1,
) -> float:
    if sample_rate <= 0 or channels <= 0:
        raise ValueError("sample rate and channels must be positive")
    return len(pcm) / (sample_rate * channels * 2)
