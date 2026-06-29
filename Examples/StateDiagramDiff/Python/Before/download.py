from enum import Enum


class DownloadState(Enum):
    """The phases a download moves through."""

    IDLE = "idle"
    REQUESTED = "requested"
    DOWNLOADING = "downloading"
    VERIFYING = "verifying"
    FINISHED = "finished"
    FAILED = "failed"


class Download:
    """A download whose ``state`` advances through a pipeline: ``run`` walks the happy path as a
    sequence of assignments (a transition chain), while ``fail`` branches from the start."""

    state: DownloadState = DownloadState.IDLE

    def run(self) -> None:
        self.state = DownloadState.REQUESTED
        self.state = DownloadState.DOWNLOADING
        self.state = DownloadState.FINISHED

    def fail(self) -> None:
        self.state = DownloadState.FAILED
