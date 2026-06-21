#ifndef MEDIA_ITEM_H
#define MEDIA_ITEM_H

#include "genre.h"

/* Shared base for every item in the library. */
struct MediaItem {
    const char *title;
    double duration;
    enum Genre genre;
};

#endif /* MEDIA_ITEM_H */
