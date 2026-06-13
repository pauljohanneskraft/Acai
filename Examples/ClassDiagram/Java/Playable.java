package medialibrary;

/** Anything the player knows how to play. */
public interface Playable {
    String title();

    double duration();

    void play();
}
