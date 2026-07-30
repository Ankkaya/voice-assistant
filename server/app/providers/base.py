class ProviderError(Exception):
    """A sanitized upstream error safe to expose as a stable protocol code."""

    def __init__(
        self,
        stage: str,
        code: str,
        *,
        recoverable: bool = True,
    ) -> None:
        self.stage = stage
        self.code = code
        self.recoverable = recoverable
        super().__init__(f"{stage} provider failed: {code}")


class ProviderConfigError(ProviderError):
    def __init__(self, stage: str, code: str = "INVALID_CONFIGURATION") -> None:
        super().__init__(stage, code, recoverable=False)

