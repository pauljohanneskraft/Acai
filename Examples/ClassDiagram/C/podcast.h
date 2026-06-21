#ifndef PODCAST_H
#define PODCAST_H

#include "media_item.h"

/* One episode of a podcast; embeds the shared MediaItem base. */
struct Podcast {
    struct MediaItem base;
    const char *host;
    int episode_number;
};

#endif /* PODCAST_H */
