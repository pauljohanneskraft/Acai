#pragma once

#include <string>
#include <vector>

#include "playlist.hpp"

// The user's whole collection: every playlist in one place.
class Library {
public:
    void addPlaylist(const Playlist& playlist);
    const Playlist* playlist(const std::string& named) const;

private:
    std::vector<Playlist> playlists_;
};
