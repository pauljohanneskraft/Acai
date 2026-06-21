#pragma once

#include <string>

#include "media_item.hpp"

// One episode of a podcast.
class Podcast : public MediaItem {
public:
    Podcast(std::string title, double duration, std::string host, int episodeNumber);

    void play() override;

private:
    std::string host_;
    int episodeNumber_;
};
