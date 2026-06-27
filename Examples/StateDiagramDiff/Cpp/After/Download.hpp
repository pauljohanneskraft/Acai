#pragma once

// The phases a download moves through.
enum class DownloadState {
    idle,
    requested,
    downloading,
    verifying,
    finished,
    failed
};

// A download whose `state` advances through a pipeline: `run()` walks the happy path as a
// sequence of assignments (a transition chain), while `fail()` branches.
class Download {
public:
    void run() {
        state = DownloadState::requested;
        state = DownloadState::downloading;
        state = DownloadState::verifying;
        state = DownloadState::finished;
    }

    void fail() {
        state = DownloadState::failed;
    }

private:
    DownloadState state = DownloadState::idle;
};
