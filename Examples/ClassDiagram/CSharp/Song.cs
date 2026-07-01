using System;

namespace MediaLibrary;

public class Song : MediaItem {
    private readonly string _artist;
    private readonly string _album;

    public string Artist => _artist;
    public string Album => _album;

    public Song(string title, double duration, Genre genre, string artist, string album) 
        : base(title, duration, genre) {
        _artist = artist;
        _album = album;
    }

    public override void Play() {
        Console.WriteLine($"Playing song: {Title} by {_artist}");
    }
}
