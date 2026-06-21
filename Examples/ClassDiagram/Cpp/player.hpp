#pragma once

#include <string>

#include "library.hpp"
#include "playable.hpp"

// Drives playback over a library. Depends on Library and the Playable interface.
class Player {
public:
    explicit Player(Library* library);

    void play(Playable* item);
    void playFirstItem(const std::string& playlistNamed);

private:
    Library* library_;
    Playable* nowPlaying_;
};
