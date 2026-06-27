package net;

/** A download whose {@code state} advances through a pipeline: {@code run()} walks the happy
 *  path as a sequence of assignments (a transition chain), while {@code fail()} branches. */
public final class Download {
    private DownloadState state = DownloadState.IDLE;

    public void run() {
        state = DownloadState.REQUESTED;
        state = DownloadState.DOWNLOADING;
        state = DownloadState.FINISHED;
    }

    public void fail() {
        state = DownloadState.FAILED;
    }
}
