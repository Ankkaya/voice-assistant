import logging
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, File, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

from .agent import LangChainAgent, build_chat_model
from .character_options import CharacterOptionsRegistry
from .characters import CharacterRegistry
from .config import get_settings
from .protocol import (
    CharacterSuggestionRequest,
    CharacterSuggestionResponse,
    ServerEvent,
    TurnError,
    serialize_server_event,
)
from .providers.asr import XiaomiAsrProvider
from .providers.tts import XiaomiTtsProvider
from .safety import SafetyGuard
from .session import VoiceSession
from .custom_characters import SessionCharacterResolver
from .voice_references import MAX_REFERENCE_BYTES, VoiceReferenceStore


logger = logging.getLogger(__name__)


@dataclass(slots=True)
class AppDependencies:
    registry: CharacterRegistry
    options: CharacterOptionsRegistry
    asr: Any | None
    agent: Any | None
    tts: Any | None
    ready: bool
    agent_timeout_seconds: float = 30.0
    reference_store: VoiceReferenceStore = field(default_factory=VoiceReferenceStore)


class WebSocketTransport:
    def __init__(self, websocket: WebSocket) -> None:
        self._websocket = websocket

    async def send_event(self, event: ServerEvent) -> None:
        await self._websocket.send_text(serialize_server_event(event))

    async def send_bytes(self, data: bytes) -> None:
        await self._websocket.send_bytes(data)


def create_app(injected: AppDependencies | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        client: httpx.AsyncClient | None = None
        if injected is not None:
            app.state.dependencies = injected
        else:
            settings = get_settings()
            registry = CharacterRegistry.from_path(
                Path(__file__).parent / "config" / "characters.json"
            )
            options = CharacterOptionsRegistry.from_path(
                Path(__file__).parent / "config" / "character_options.json"
            )
            dependencies = AppDependencies(
                registry=registry,
                options=options,
                asr=None,
                agent=None,
                tts=None,
                ready=settings.providers_ready,
                agent_timeout_seconds=settings.agent_timeout_seconds,
            )
            if settings.providers_ready:
                client = httpx.AsyncClient()
                assert settings.mimo_api_key is not None
                dependencies.asr = XiaomiAsrProvider(
                    settings.mimo_api_key.get_secret_value(),
                    client=client,
                    base_url=settings.mimo_base_url,
                )
                dependencies.tts = XiaomiTtsProvider(
                    settings.mimo_api_key.get_secret_value(),
                    client=client,
                    base_url=settings.mimo_base_url,
                    reference_base_dir=registry.source_dir,
                )
                dependencies.agent = LangChainAgent(
                    build_chat_model(settings),
                    SafetyGuard(),
                )
            app.state.dependencies = dependencies
        try:
            yield
        finally:
            if client is not None:
                await client.aclose()

    app = FastAPI(title="Child Voice Call", version="0.0.1", lifespan=lifespan)

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/ready")
    async def ready():
        dependencies: AppDependencies = app.state.dependencies
        if not dependencies.ready:
            return JSONResponse({"status": "not_ready"}, status_code=503)
        return {"status": "ready"}

    @app.get("/api/character-options")
    async def character_options() -> dict[str, object]:
        dependencies: AppDependencies = app.state.dependencies
        return dependencies.options.public_payload()

    @app.post(
        "/api/character-suggestions",
        response_model=CharacterSuggestionResponse,
    )
    async def character_suggestion(
        request: CharacterSuggestionRequest,
    ) -> CharacterSuggestionResponse:
        dependencies: AppDependencies = app.state.dependencies
        if not dependencies.ready or dependencies.agent is None:
            raise HTTPException(503, "Suggestion service is not ready")
        try:
            suggestion = await dependencies.agent.suggest_character_field(
                request.target_field,
                request.form_context,
            )
        except ValueError as exc:
            raise HTTPException(400, "Character context is not supported") from exc
        except Exception as exc:
            logger.exception("character_suggestion_failed field=%s", request.target_field)
            raise HTTPException(502, "Suggestion generation failed") from exc
        return CharacterSuggestionResponse(suggestion=suggestion)

    @app.post("/api/voice-references", status_code=201)
    async def upload_voice_reference(file: UploadFile = File(...)):
        filename = file.filename or "reference"
        suffix = Path(filename).suffix.lower()
        mime_by_suffix = {".wav": "audio/wav", ".mp3": "audio/mpeg"}
        mime_type = mime_by_suffix.get(suffix)
        if mime_type is None:
            raise HTTPException(400, "Only WAV and MP3 reference audio is supported")
        content = await file.read(MAX_REFERENCE_BYTES + 1)
        await file.close()
        if not content:
            raise HTTPException(400, "Reference audio is empty")
        if len(content) > MAX_REFERENCE_BYTES:
            raise HTTPException(413, "Reference audio exceeds 7.5 MB")
        is_wav = mime_type == "audio/wav" and (
            len(content) >= 12
            and content.startswith(b"RIFF")
            and content[8:12] == b"WAVE"
        )
        is_mp3 = mime_type == "audio/mpeg" and (
            content.startswith(b"ID3")
            or (
                len(content) >= 2
                and content[0] == 0xFF
                and content[1] & 0xE0 == 0xE0
            )
        )
        if not (is_wav or is_mp3):
            raise HTTPException(400, "Reference audio content is invalid")
        dependencies: AppDependencies = app.state.dependencies
        reference_id = dependencies.reference_store.put(content, mime_type)
        return {
            "referenceId": reference_id,
            "fileName": filename,
            "sizeBytes": len(content),
        }

    @app.websocket("/ws/voice")
    async def voice_socket(websocket: WebSocket) -> None:
        await websocket.accept()
        dependencies: AppDependencies = app.state.dependencies
        transport = WebSocketTransport(websocket)
        if not dependencies.ready:
            await transport.send_event(
                TurnError(
                    stage="session",
                    code="SERVICE_NOT_READY",
                    recoverable=False,
                    message="语音服务还没有配置好。",
                )
            )
            await websocket.close(code=1013)
            return

        session = VoiceSession(
            character_resolver=SessionCharacterResolver(
                registry=dependencies.registry,
                options=dependencies.options,
                safety=SafetyGuard(),
                reference_store=dependencies.reference_store,
            ),
            asr=dependencies.asr,
            agent=dependencies.agent,
            tts=dependencies.tts,
            transport=transport,
            agent_timeout_seconds=dependencies.agent_timeout_seconds,
            reference_store=dependencies.reference_store,
        )
        try:
            while True:
                message = await websocket.receive()
                kind = message.get("type")
                if kind == "websocket.disconnect":
                    break
                text = message.get("text")
                data = message.get("bytes")
                if text is not None:
                    await session.handle_text(text)
                elif data is not None:
                    await session.handle_audio(data)
        except WebSocketDisconnect:
            pass
        except Exception:
            logger.exception(
                "voice_websocket_failed session_id=%s",
                session.session_id,
            )
        finally:
            await session.close("socket_closed")

    return app


app = create_app()
