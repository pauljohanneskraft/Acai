package medialibrary;

/** A single track by an artist. */
public final class Song extends MediaItem {
    private final String artist;
    private final String album;

    public Song(String title, double duration, Genre genre, String artist, String album) {
        super(title, duration, genre);
        this.artist = artist;
        this.album = album;
    }

    @Override
    public void play() {
        System.out.println("♪ " + artist + " — " + title());
    }
}
