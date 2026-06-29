/** A download whose `state` advances through a pipeline, modelled with string literals
 *  (plain JavaScript has no enums). `run()` walks the happy path as a sequence of
 *  assignments (a transition chain), while `fail()` branches from the start. */
export class Download {
    state = "idle";

    run() {
        this.state = "requested";
        this.state = "downloading";
        this.state = "finished";
    }

    fail() {
        this.state = "failed";
    }
}
