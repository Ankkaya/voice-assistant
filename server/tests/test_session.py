import json

import pytest

from app.protocol import serialize_server_event
from app.providers.base import ProviderError
from app.session import SessionState, VoiceSession


class FakeTransport:
    def __init__(self):
        self.events = []
        self.binary_payloads = []

    async def send_event(self, event):
        self.events.append(json.loads(serialize_server_event(event)))

    async def send_bytes(self, data: bytes):
        self.binary_payloads.append(data)


class FakeAsr:
    def __init__(self, text="你好"):
        self.text = text
        self.wav_payloads = []

    async def transcribe(self, wav_bytes: bytes) -> str:
        self.wav_payloads.append(wav_bytes)
        if isinstance(self.text, Exception):
            raise self.text
        return self.text


class FakeAgent:
    def __init__(self, reply="我们一起出发吧！"):
        self.reply_text = reply
        self.calls = []

    async def reply(self, character, history, user_text):
        self.calls.append((character.id, tuple(history), user_text))
        if isinstance(self.reply_text, Exception):
            raise self.reply_text
        return self.reply_text


class FakeTts:
    def __init__(self, chunks=(b"\x01\x02", b"\x03\x04")):
        self.chunks = chunks
        self.calls = []

    async def synthesize(self, text, config):
        self.calls.append((text, config.mode))
        if isinstance(self.chunks, Exception):
            raise self.chunks
        for chunk in self.chunks:
            yield chunk


def event_types(transport):
    return [event["type"] for event in transport.events]


def session_start(character="ryder"):
    return json.dumps({"type": "session.start", "characterId": character})


def audio_start(turn="turn_1"):
    return json.dumps({"type": "input.audio.start", "turnId": turn})


def audio_commit(turn="turn_1"):
    return json.dumps({"type": "input.audio.commit", "turnId": turn})


@pytest.fixture
def make_session(registry):
    sessions = []

    def factory(asr=None, agent=None, tts=None, transport=None):
        session = VoiceSession(
            registry=registry,
            asr=asr or FakeAsr(),
            agent=agent or FakeAgent(),
            tts=tts or FakeTts(),
            transport=transport or FakeTransport(),
            max_duration_seconds=0,
        )
        sessions.append(session)
        return session

    yield factory


@pytest.mark.asyncio
async def test_committed_audio_produces_transcript_and_pcm(make_session):
    transport = FakeTransport()
    asr = FakeAsr()
    agent = FakeAgent()
    session = make_session(transport=transport, asr=asr, agent=agent)

    await session.handle_text(session_start())
    await session.handle_text(audio_start())
    await session.handle_audio(b"\x00\x00" * 5000)
    await session.handle_text(audio_commit())

    assert event_types(transport) == [
        "session.ready",
        "assistant.audio.start",
        "assistant.audio.end",
        "user.transcript",
        "assistant.thinking",
        "assistant.audio.start",
        "assistant.audio.end",
    ]
    assert asr.wav_payloads[0].startswith(b"RIFF")
    assert agent.calls[0][2] == "你好"
    assert transport.binary_payloads == [b"\x01\x02", b"\x03\x04"] * 2
    assert session.state is SessionState.LISTENING


@pytest.mark.asyncio
async def test_binary_before_audio_start_is_rejected(make_session):
    transport = FakeTransport()
    session = make_session(transport=transport)
    await session.handle_text(session_start())

    await session.handle_audio(b"\x00\x00")

    assert transport.events[-1]["code"] == "INVALID_STATE"
    assert session.state is SessionState.LISTENING


@pytest.mark.asyncio
async def test_oversized_audio_recovers_to_listening(make_session):
    transport = FakeTransport()
    session = make_session(transport=transport)
    await session.handle_text(session_start())
    await session.handle_text(audio_start())

    await session.handle_audio(b"\x00" * (512 * 1024 + 1))

    assert transport.events[-1]["code"] == "AUDIO_TOO_LARGE"
    assert session.state is SessionState.LISTENING


@pytest.mark.asyncio
async def test_empty_asr_result_sends_recoverable_error(make_session):
    transport = FakeTransport()
    asr = FakeAsr(ProviderError("asr", "EMPTY_RESULT"))
    session = make_session(transport=transport, asr=asr)
    await session.handle_text(session_start())
    await session.handle_text(audio_start())
    await session.handle_audio(b"\x00\x00" * 5000)

    await session.handle_text(audio_commit())

    assert transport.events[-1]["type"] == "turn.error"
    assert transport.events[-1]["code"] == "EMPTY_RESULT"
    assert transport.events[-1]["recoverable"] is True
    assert session.state is SessionState.LISTENING


@pytest.mark.asyncio
async def test_close_clears_audio_and_history(make_session):
    session = make_session()
    await session.handle_text(session_start())
    await session.handle_text(audio_start())
    await session.handle_audio(b"\x00\x00" * 5000)
    await session.handle_text(audio_commit())
    assert session.history

    await session.close("test")

    assert session.state is SessionState.ENDED
    assert session.history == []
    assert session.buffered_audio_bytes == 0
