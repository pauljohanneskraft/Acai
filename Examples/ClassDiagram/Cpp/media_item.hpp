#pragma once

#include <string>

#include "playable.hpp"

// Shared base for every item in the library.
class MediaItem : public Playable {
public:
    MediaItem(std::string title, double duration, Genre genre);

    std::string title() const override;
    double duration() const override;
    void play() override;

private:
    std::string title_;
    double duration_;
    Genre genre_;
};
