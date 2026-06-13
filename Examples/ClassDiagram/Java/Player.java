package medialibrary;

/** Drives playback over a library. Depends on {@link Library} and the {@link Playable} interface. */
public final class Player {
    private final Library library;
    private Playable nowPlaying;

    public Player(Library library) {
        this.library = library;
    }

    public Playable nowPlaying() {
        return nowPlaying;
    }

    public void play(Playable item) {
        nowPlaying = item;
        item.play();
    }

    public void playFirstItem(String playlistNamed) {
        Playlist playlist = library.playlist(playlistNamed);
        if (playlist != null && !playlist.items().isEmpty()) {
            play(playlist.items().get(0));
        }
    }
}
