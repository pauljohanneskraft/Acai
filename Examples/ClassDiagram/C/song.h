#ifndef SONG_H
#define SONG_H

#include "media_item.h"

/* A single track by an artist; embeds the shared MediaItem base. */
struct Song {
    struct MediaItem base;
    const char *artist;
    const char *album;
};

#endif /* SONG_H */
