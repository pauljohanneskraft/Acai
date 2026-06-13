package medialibrary;

import java.util.ArrayList;
import java.util.List;

/** The user's whole collection: every playlist in one place. */
public final class Library {
    private final List<Playlist> playlists;

    public Library(List<Playlist> playlists) {
        this.playlists = new ArrayList<>(playlists);
    }

    public List<Playlist> playlists() {
        return playlists;
    }

    public void addPlaylist(Playlist playlist) {
        playlists.add(playlist);
    }

    public Playlist playlist(String named) {
        return playlists.stream().filter(p -> p.name().equals(named)).findFirst().orElse(null);
    }
}
