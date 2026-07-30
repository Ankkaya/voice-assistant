"""Live MiMo + LangChain smoke test. It never prints transcript or model content."""

import asyncio
from pathlib import Path

import httpx

from app.agent import LangChainAgent, build_chat_model
from app.audio import pcm16le_to_wav
from app.characters import CharacterRegistry
from app.config import Settings
from app.providers.asr import XiaomiAsrProvider
from app.providers.tts import XiaomiTtsProvider
from app.safety import SafetyGuard


async def main() -> None:
    settings = Settings()
    if not settings.providers_ready:
        raise SystemExit(
            "Set MIMO_API_KEY, LLM_API_KEY, LLM_MODEL and LLM_BASE_URL first."
        )

    registry = CharacterRegistry.from_path(
        Path(__file__).parents[1] / "app" / "config" / "characters.json"
    )
    character = registry.get("labrador_captain")
    assert settings.mimo_api_key is not None
    async with httpx.AsyncClient() as client:
        tts = XiaomiTtsProvider(
            settings.mimo_api_key.get_secret_value(),
            client=client,
            base_url=settings.mimo_base_url,
            reference_base_dir=registry.source_dir,
        )
        pcm = b"".join(
            [
                chunk
                async for chunk in tts.synthesize(
                    "你好，今天一起探险吧！",
                    character.tts,
                )
            ]
        )
        asr = XiaomiAsrProvider(
            settings.mimo_api_key.get_secret_value(),
            client=client,
            base_url=settings.mimo_base_url,
        )
        transcript = await asr.transcribe(pcm16le_to_wav(pcm, sample_rate=24000))

    agent = LangChainAgent(build_chat_model(settings), SafetyGuard())
    reply = await agent.reply(character, [], transcript)
    if not pcm or not transcript or not reply:
        raise SystemExit("Provider smoke test returned an empty stage.")
    print(
        "Provider smoke test passed:",
        f"tts_bytes={len(pcm)}",
        f"asr_chars={len(transcript)}",
        f"agent_chars={len(reply)}",
    )


if __name__ == "__main__":
    asyncio.run(main())

