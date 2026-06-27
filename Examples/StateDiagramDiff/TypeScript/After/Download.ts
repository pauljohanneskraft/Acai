/** The phases a download moves through. */
export enum DownloadState {
    Idle,
    Requested,
    Downloading,
    Verifying,
    Finished,
    Failed,
}

/** A download whose `state` advances through a pipeline: `run()` walks the happy path as a
 *  sequence of assignments (a transition chain), while `fail()` branches from the start. */
export class Download {
    private state: DownloadState = DownloadState.Idle;

    run(): void {
        this.state = DownloadState.Requested;
        this.state = DownloadState.Downloading;
        this.state = DownloadState.Verifying;
        this.state = DownloadState.Finished;
    }

    fail(): void {
        this.state = DownloadState.Failed;
    }
}
