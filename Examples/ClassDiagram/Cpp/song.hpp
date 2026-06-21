#pragma once

#include <string>

#include "media_item.hpp"

// A single track by an artist.
class Song : public MediaItem {
public:
    Song(std::string title, double duration, Genre genre, std::string artist, std::string album);

    void play() override;

private:
    std::string artist_;
    std::string album_;
};
