using System;
using System.Collections.Generic;

namespace MediaLibrary;

public class Playlist : IPlayable {
    private readonly string _name;
    private readonly List<IPlayable> _items;

    public string Title => _name;
    
    public double Duration {
        get {
            double total = 0;
            foreach (var item in _items) {
                total += item.Duration;
            }
            return total;
        }
    }

    public Playlist(string name) {
        _name = name;
        _items = new List<IPlayable>();
    }

    public void Add(IPlayable item) {
        _items.Add(item);
    }

    public void Remove(IPlayable item) {
        _items.Remove(item);
    }

    public void Play() {
        Console.WriteLine($"Playing playlist: {_name}");
        foreach (var item in _items) {
            item.Play();
        }
    }
}
