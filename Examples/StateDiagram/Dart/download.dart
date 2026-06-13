/// The phases a download moves through.
enum DownloadState { idle, requested, downloading, verifying, finished, failed }

/// A download whose [state] advances through a pipeline: [run] walks the happy path as a
/// sequence of assignments (a transition chain), while [fail] branches from the start.
class Download {
  DownloadState state = DownloadState.idle;

  void run() {
    state = DownloadState.requested;
    state = DownloadState.downloading;
    state = DownloadState.verifying;
    state = DownloadState.finished;
  }

  void fail() {
    state = DownloadState.failed;
  }
}
