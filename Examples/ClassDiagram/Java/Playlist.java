package medialibrary;

import java.util.ArrayList;
import java.util.List;

/** An ordered collection of media items the user has curated. */
public final class Playlist {
    private final String name;
    private final List<MediaItem> items;

    public Playlist(String name, List<MediaItem> items) {
        this.name = name;
        this.items = new ArrayList<>(items);
    }

    public String name() {
        return name;
    }

    public List<MediaItem> items() {
        return items;
    }

    public double totalDuration() {
        return items.stream().mapToDouble(MediaItem::duration).sum();
    }

    public void add(MediaItem item) {
        items.add(item);
    }
}
