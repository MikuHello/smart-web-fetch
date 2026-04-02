class CLIError(Exception):
    def __init__(self, message: str, source: str | None = None) -> None:
        super().__init__(message)
        self.source = source or "none"


class FetchTransportError(Exception):
    pass
