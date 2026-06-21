#ifndef PLAYER_H
#define PLAYER_H

#include "library.h"

/* Drives playback over a library. Depends on Library. */
struct Player {
    struct Library *library;
    int now_playing;
};

#endif /* PLAYER_H */
