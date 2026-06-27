/* A `Download` whose `state` advances through a pipeline. C has no methods, so the transitions
   live in free functions that take the download by pointer: `run` walks the happy path as a chain
   of assignments (a transition chain), while `fail` branches. Unlike the C++/Swift models there is
   no in-struct initializer, so `state` has no separate initial value. Everything lives in one file
   because the parser analyses each translation unit on its own and does not follow `#include`. */

typedef enum {
    REQUESTED,
    DOWNLOADING,
    VERIFYING,
    FINISHED,
    FAILED
} DownloadState;

typedef struct {
    DownloadState state;
} Download;

void run(Download *download) {
    download->state = REQUESTED;
    download->state = DOWNLOADING;
    download->state = FINISHED;
}

void fail(Download *download) {
    download->state = FAILED;
}
