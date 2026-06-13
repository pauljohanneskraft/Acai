package medialibrary;

/** Shared base for every item in the library. */
public class MediaItem implements Playable {
    private final String title;
    private final double duration;
    private final Genre genre;

    public MediaItem(String title, double duration, Genre genre) {
        this.title = title;
        this.duration = duration;
        this.genre = genre;
    }

    @Override
    public String title() {
        return title;
    }

    @Override
    public double duration() {
        return duration;
    }

    public Genre genre() {
        return genre;
    }

    @Override
    public void play() {
        System.out.println("Playing " + title + "…");
    }
}
