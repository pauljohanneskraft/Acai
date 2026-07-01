using System.Collections.Generic;
using System.Linq;

namespace MediaLibrary;

public class Library {
    private readonly List<MediaItem> _items = new List<MediaItem>();
    private readonly List<Playlist> _playlists = new List<Playlist>();

    public void AddItem(MediaItem item) {
        _items.Add(item);
    }

    public void AddPlaylist(Playlist playlist) {
        _playlists.Add(playlist);
    }

    public IEnumerable<MediaItem> GetItemsByGenre(Genre genre) {
        return _items.Where(item => item.Genre == genre);
    }
    
    public IEnumerable<MediaItem> Items => _items.AsReadOnly();
    public IEnumerable<Playlist> Playlists => _playlists.AsReadOnly();
}
