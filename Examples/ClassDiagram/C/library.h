#ifndef LIBRARY_H
#define LIBRARY_H

#include "playlist.h"

/* The user's whole collection: every playlist in one place. */
struct Library {
    struct Playlist *playlists;
    int count;
};

#endif /* LIBRARY_H */
