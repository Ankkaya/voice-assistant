import time
import uuid
from dataclasses import dataclass


# MiMo limits the Base64 data URL to 10 MB. Reserve enough bytes for the MIME
# prefix, then account for Base64's 4/3 expansion.
MAX_REFERENCE_BYTES = ((10_000_000 - 32) // 4) * 3
REFERENCE_TTL_SECONDS = 30 * 60


@dataclass(frozen=True, slots=True)
class VoiceReference:
    data: bytes
    mime_type: str
    created_at: float


class VoiceReferenceStore:
    def __init__(self) -> None:
        self._items: dict[str, VoiceReference] = {}

    def put(self, data: bytes, mime_type: str) -> str:
        self._purge_expired()
        reference_id = uuid.uuid4().hex
        self._items[reference_id] = VoiceReference(
            data=data,
            mime_type=mime_type,
            created_at=time.monotonic(),
        )
        return reference_id

    def get(self, reference_id: str) -> VoiceReference | None:
        self._purge_expired()
        return self._items.get(reference_id)

    def delete(self, reference_id: str) -> None:
        self._items.pop(reference_id, None)

    def _purge_expired(self) -> None:
        cutoff = time.monotonic() - REFERENCE_TTL_SECONDS
        expired = [
            reference_id
            for reference_id, reference in self._items.items()
            if reference.created_at < cutoff
        ]
        for reference_id in expired:
            self._items.pop(reference_id, None)
