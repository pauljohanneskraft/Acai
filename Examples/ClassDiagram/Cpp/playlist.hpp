#pragma once

#include <string>
#include <vector>

#include "media_item.hpp"

// An ordered collection of media items the user has curated.
class Playlist {
public:
    explicit Playlist(std::string name);

    double totalDuration() const;
    void add(const MediaItem& item);

private:
    std::string name_;
    std::vector<MediaItem> items_;
};
