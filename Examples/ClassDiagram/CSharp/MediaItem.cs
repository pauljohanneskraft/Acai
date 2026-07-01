using System;

namespace MediaLibrary;

/// <summary>
/// Shared base for every item in the library.
/// </summary>
public class MediaItem : IPlayable {
    private readonly string _title;
    private readonly double _duration;
    private readonly Genre _genre;

    public string Title => _title;
    public double Duration => _duration;
    public Genre Genre => _genre;

    public MediaItem(string title, double duration, Genre genre) {
        _title = title;
        _duration = duration;
        _genre = genre;
    }

    public virtual void Play() {
        Console.WriteLine($"Playing {_title}...");
    }
}
