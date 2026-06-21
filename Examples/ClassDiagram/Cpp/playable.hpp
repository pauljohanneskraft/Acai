#pragma once

#include <string>

// A coarse classification for a piece of media.
enum class Genre {
    pop,
    rock,
    jazz,
    classical,
    electronic,
    spokenWord
};

// Anything the player knows how to play.
class Playable {
public:
    virtual ~Playable() = default;
    virtual std::string title() const = 0;
    virtual double duration() const = 0;
    virtual void play() = 0;
};
