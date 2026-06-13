package medialibrary;

/** One episode of a podcast. */
public final class Podcast extends MediaItem {
    private final String host;
    private final int episodeNumber;

    public Podcast(String title, double duration, String host, int episodeNumber) {
        super(title, duration, Genre.SPOKEN_WORD);
        this.host = host;
        this.episodeNumber = episodeNumber;
    }

    @Override
    public void play() {
        System.out.println("🎙 Episode " + episodeNumber + ": " + title());
    }
}
