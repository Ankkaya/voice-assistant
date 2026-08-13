import asyncio
import json
import logging
import uuid
from collections.abc import Sequence
from enum import StrEnum
from typing import Protocol

from pydantic import ValidationError

from .agent import ConversationTurn, LangChainAgent
from .audio import pcm16le_duration_seconds, pcm16le_to_wav
from .custom_characters import CharacterResolutionError, SessionCharacterResolver
from .protocol import (
    AssistantAudioEnd,
    AssistantAudioStart,
    AssistantThinking,
    InputAudioCommit,
    InputAudioStart,
    Ping,
    Pong,
    ServerEvent,
    SessionEnd,
    SessionReady,
    SessionStart,
    TurnError,
    UserTranscript,
    parse_client_event,
)
from .providers.asr import AsrProvider
from .providers.base import ProviderError
from .providers.tts import TtsProvider
from .models import TtsConfig
from .voice_references import VoiceReferenceStore


logger = logging.getLogger(__name__)

MAX_AUDIO_BYTES = 512 * 1024
MAX_AUDIO_SECONDS = 15.0
MIN_AUDIO_SECONDS = 0.3


class SessionState(StrEnum):
    CONNECTING = "connecting"
    SPEAKING = "speaking"
    LISTENING = "listening"
    RECEIVING = "receiving"
    PROCESSING = "processing"
    ENDED = "ended"


class SessionTransport(Protocol):
    async def send_event(self, event: ServerEvent) -> None: ...

    async def send_bytes(self, data: bytes) -> None: ...


class VoiceSession:
    def __init__(
        self,
        *,
        character_resolver: SessionCharacterResolver,
        asr: AsrProvider,
        agent: LangChainAgent,
        tts: TtsProvider,
        transport: SessionTransport,
        max_duration_seconds: int = 600,
        agent_timeout_seconds: float = 30.0,
        session_id: str | None = None,
        reference_store: VoiceReferenceStore | None = None,
    ) -> None:
        self.session_id = session_id or uuid.uuid4().hex
        self.state = SessionState.CONNECTING
        self.history: list[ConversationTurn] = []
        self._character_resolver = character_resolver
        self._asr = asr
        self._agent = agent
        self._tts = tts
        self._transport = transport
        self._character = None
        self._turn_id: str | None = None
        self._audio = bytearray()
        self._empty_asr_count = 0
        self._max_duration_seconds = max_duration_seconds
        self._agent_timeout_seconds = agent_timeout_seconds
        self._deadline_task: asyncio.Task | None = None
        self._active_task: asyncio.Task | None = None
        self._reference_store = reference_store
        self._reference_id: str | None = None
        self._tts_config: TtsConfig | None = None

    @property
    def buffered_audio_bytes(self) -> int:
        return len(self._audio)

    async def start(self, character_id: str) -> None:
        await self._start_session(SessionStart(characterId=character_id))

    async def handle_text(self, raw: str) -> None:
        if self.state is SessionState.ENDED:
            return
        try:
            event = parse_client_event(raw)
        except (ValidationError, ValueError):
            if self._is_custom_session_start(raw):
                await self._send_error(
                    "session", "INVALID_CHARACTER_CONFIG", False
                )
                await self.close("invalid_character_config")
            else:
                await self._send_error("protocol", "INVALID_EVENT", False)
            return

        if isinstance(event, SessionStart):
            await self._start_session(event)
        elif isinstance(event, InputAudioStart):
            await self._start_audio(event)
        elif isinstance(event, InputAudioCommit):
            await self._commit_audio(event)
        elif isinstance(event, Ping):
            await self._transport.send_event(Pong(timestamp=event.timestamp))
        elif isinstance(event, SessionEnd):
            await self.close("client_hangup")

    async def handle_audio(self, data: bytes) -> None:
        if self.state is not SessionState.RECEIVING:
            await self._send_error("protocol", "INVALID_STATE", True)
            return
        if len(self._audio) + len(data) > MAX_AUDIO_BYTES:
            await self._send_error("audio", "AUDIO_TOO_LARGE", True)
            self._reset_turn(SessionState.LISTENING)
            return
        self._audio.extend(data)
        if pcm16le_duration_seconds(self._audio) > MAX_AUDIO_SECONDS:
            await self._send_error("audio", "AUDIO_TOO_LONG", True)
            self._reset_turn(SessionState.LISTENING)

    async def close(self, reason: str) -> None:
        if self.state is SessionState.ENDED:
            return
        self.state = SessionState.ENDED
        current = asyncio.current_task()
        for task in (self._active_task, self._deadline_task):
            if task and task is not current and not task.done():
                task.cancel()
        self._audio.clear()
        self.history.clear()
        self._turn_id = None
        self._character = None
        if self._reference_id and self._reference_store:
            self._reference_store.delete(self._reference_id)
        self._reference_id = None
        self._tts_config = None
        logger.info("voice_session_closed session_id=%s reason=%s", self.session_id, reason)

    async def _start_session(self, event: SessionStart) -> None:
        if self.state is not SessionState.CONNECTING:
            await self._send_error("protocol", "INVALID_STATE", False)
            return
        try:
            resolved = self._character_resolver.resolve(event)
        except KeyError:
            await self._send_error("session", "UNKNOWN_CHARACTER", False)
            return
        except CharacterResolutionError as error:
            await self._send_error("session", error.code, False)
            await self.close("invalid_character_config")
            return
        self._character = resolved.character
        self._tts_config = resolved.tts
        self._reference_id = resolved.reference_id
        await self._transport.send_event(SessionReady(sessionId=self.session_id))
        if self._max_duration_seconds > 0:
            self._deadline_task = asyncio.create_task(self._enforce_deadline())
        try:
            await self._speak(self._character.greeting, "greeting")
        except ProviderError as error:
            await self._send_provider_error(error)
        if self.state is not SessionState.ENDED:
            self.state = SessionState.LISTENING

    async def _start_audio(self, event: InputAudioStart) -> None:
        if self.state is not SessionState.LISTENING:
            await self._send_error("protocol", "INVALID_STATE", True)
            return
        self._audio.clear()
        self._turn_id = event.turn_id
        self.state = SessionState.RECEIVING

    async def _commit_audio(self, event: InputAudioCommit) -> None:
        if self.state is not SessionState.RECEIVING or event.turn_id != self._turn_id:
            await self._send_error("protocol", "INVALID_STATE", True)
            return
        if pcm16le_duration_seconds(self._audio) < MIN_AUDIO_SECONDS:
            await self._send_error("audio", "AUDIO_TOO_SHORT", True)
            self._reset_turn(SessionState.LISTENING)
            return
        self.state = SessionState.PROCESSING
        self._active_task = asyncio.current_task()
        try:
            await self._process_turn(event.turn_id)
        finally:
            self._active_task = None
            self._audio.clear()
            self._turn_id = None
            if self.state is not SessionState.ENDED:
                self.state = SessionState.LISTENING

    async def _process_turn(self, turn_id: str) -> None:
        assert self._character is not None
        try:
            transcript = await self._asr.transcribe(pcm16le_to_wav(bytes(self._audio)))
        except ProviderError as error:
            if error.code == "EMPTY_RESULT":
                self._empty_asr_count += 1
            await self._send_provider_error(error)
            return
        self._empty_asr_count = 0
        await self._transport.send_event(UserTranscript(turnId=turn_id, text=transcript))
        await self._transport.send_event(AssistantThinking(turnId=turn_id))
        try:
            reply = await asyncio.wait_for(
                self._agent.reply(self._character, self.history, transcript),
                timeout=self._agent_timeout_seconds,
            )
        except TimeoutError:
            await self._send_error("agent", "UPSTREAM_TIMEOUT", True)
            return
        except Exception:
            await self._send_error("agent", "GENERATION_FAILED", True)
            return

        try:
            await self._speak(reply, turn_id)
        except ProviderError as error:
            await self._send_provider_error(error)
            return
        self.history.append(ConversationTurn(user=transcript, assistant=reply))
        self.history[:] = self.history[-8:]

    async def _speak(self, text: str, turn_id: str) -> None:
        assert self._character is not None
        assert self._tts_config is not None
        self.state = SessionState.SPEAKING
        await self._transport.send_event(AssistantAudioStart(turnId=turn_id))
        try:
            async for chunk in self._tts.synthesize(text, self._tts_config):
                await self._transport.send_bytes(chunk)
        finally:
            await self._transport.send_event(AssistantAudioEnd(turnId=turn_id))

    async def _send_provider_error(self, error: ProviderError) -> None:
        message = self._error_message(error.stage, error.code)
        await self._send_error(error.stage, error.code, error.recoverable, message)

    async def _send_error(
        self,
        stage: str,
        code: str,
        recoverable: bool,
        message: str | None = None,
    ) -> None:
        await self._transport.send_event(
            TurnError(
                stage=stage,
                code=code,
                recoverable=recoverable,
                message=message or self._error_message(stage, code),
            )
        )

    def _error_message(self, stage: str, code: str) -> str:
        if stage == "session" and code in {
            "INVALID_CHARACTER_CONFIG",
            "UNSUPPORTED_CHARACTER_OPTION",
            "UNSAFE_CHARACTER_CONFIG",
            "UNSUPPORTED_PRESET_VOICE",
        }:
            return "角色设定需要修改后才能通话。"
        if stage == "session" and code == "VOICE_REFERENCE_NOT_FOUND":
            return "参考音频已失效，请重新选择后再试。"
        if stage == "asr" and code in {"EMPTY_RESULT", "INVALID_RESPONSE"}:
            if self._empty_asr_count >= 3:
                return "周围有点吵，可以换个安静的地方再说一次吗？"
            return "我刚刚没有听清，可以再说一次吗？"
        if stage == "agent":
            return "我刚刚走神了，可以再说一次吗？"
        if stage == "tts":
            return "我暂时有点说不出话，请稍后再试一次。"
        if stage == "audio":
            return "这句话有点长，我们再说一次短一点的吧。"
        return "通话遇到了一点问题，请重新试一次。"

    def _reset_turn(self, state: SessionState) -> None:
        self._audio.clear()
        self._turn_id = None
        self.state = state

    @staticmethod
    def _is_custom_session_start(raw: str) -> bool:
        try:
            body = json.loads(raw)
        except (TypeError, ValueError):
            return False
        if not isinstance(body, dict) or body.get("type") != "session.start":
            return False
        character_id = body.get("characterId")
        return (
            isinstance(character_id, str) and character_id.startswith("custom_")
        ) or "customCharacter" in body

    async def _enforce_deadline(self) -> None:
        try:
            await asyncio.sleep(self._max_duration_seconds)
            if self.state is SessionState.ENDED or self._character is None:
                return
            try:
                await self._speak("今天聊得很开心，我们下次再见！", "goodbye")
            except ProviderError as error:
                await self._send_provider_error(error)
            await self.close("time_limit")
        except asyncio.CancelledError:
            raise
