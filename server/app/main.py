import logging
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import httpx
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse

from .agent import LangChainAgent, build_chat_model
from .characters import CharacterRegistry
from .config import get_settings
from .protocol import ServerEvent, TurnError, serialize_server_event
from .providers.asr import XiaomiAsrProvider
from .providers.tts import XiaomiTtsProvider
from .safety import SafetyGuard
from .session import VoiceSession


logger = logging.getLogger(__name__)


@dataclass(slots=True)
class AppDependencies:
    registry: CharacterRegistry
    asr: Any | None
    agent: Any | None
    tts: Any | None
    ready: bool


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
            dependencies = AppDependencies(
                registry=registry,
                asr=None,
                agent=None,
                tts=None,
                ready=settings.providers_ready,
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

    app = FastAPI(title="Child Voice Call", version="0.1.0", lifespan=lifespan)

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/ready")
    async def ready():
        dependencies: AppDependencies = app.state.dependencies
        if not dependencies.ready:
            return JSONResponse({"status": "not_ready"}, status_code=503)
        return {"status": "ready"}

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
            registry=dependencies.registry,
            asr=dependencies.asr,
            agent=dependencies.agent,
            tts=dependencies.tts,
            transport=transport,
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
