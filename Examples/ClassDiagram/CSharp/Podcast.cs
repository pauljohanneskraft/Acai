using System;

namespace MediaLibrary;

public class Podcast : MediaItem {
    private readonly string _host;
    private readonly int _episodeNumber;

    public string Host => _host;
    public int EpisodeNumber => _episodeNumber;

    public Podcast(string title, double duration, string host, int episodeNumber) 
        : base(title, duration, Genre.Talk) {
        _host = host;
        _episodeNumber = episodeNumber;
    }

    public override void Play() {
        Console.WriteLine($"Playing podcast episode {_episodeNumber}: {Title} hosted by {_host}");
    }
}
