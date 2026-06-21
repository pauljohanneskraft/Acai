#ifndef PLAYLIST_H
#define PLAYLIST_H

#include "media_item.h"

/* An ordered collection of media items the user has curated. */
struct Playlist {
    const char *name;
    struct MediaItem *items;
    int count;
};

#endif /* PLAYLIST_H */
