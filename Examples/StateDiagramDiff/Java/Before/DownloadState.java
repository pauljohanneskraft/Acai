package net;

/** The phases a download moves through. */
public enum DownloadState {
    IDLE,
    REQUESTED,
    DOWNLOADING,
    VERIFYING,
    FINISHED,
    FAILED
}
