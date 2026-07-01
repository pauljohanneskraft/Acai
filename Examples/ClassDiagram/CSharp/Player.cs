using System;
using System.Collections.Generic;

namespace MediaLibrary;

public class Player {
    private readonly Library _library;
    private IPlayable? _currentPlaying;

    public Player(Library library) {
        _library = library;
    }

    public void Play(IPlayable item) {
        _currentPlaying = item;
        item.Play();
    }

    public void PlayAll(IEnumerable<IPlayable> items) {
        foreach (var item in items) {
            Play(item);
        }
    }

    public IPlayable? CurrentPlaying => _currentPlaying;
}
