package net

/** The phases a download moves through. */
enum class DownloadState { IDLE, REQUESTED, DOWNLOADING, VERIFYING, FINISHED, FAILED }

/** A download whose [state] advances through a pipeline: `run()` walks the happy path as a
 *  sequence of assignments (a transition chain), while `fail()` branches from the start. */
class Download {
    var state: DownloadState = DownloadState.IDLE

    fun run() {
        state = DownloadState.REQUESTED
        state = DownloadState.DOWNLOADING
        state = DownloadState.VERIFYING
        state = DownloadState.FINISHED
    }

    fun fail() {
        state = DownloadState.FAILED
    }
}
