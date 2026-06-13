import { Library } from "./Library";
import { Playable } from "./Playable";

/** Drives playback over a library. Depends on Library and the Playable interface. */
export class Player {
    private nowPlaying: Playable | null = null;

    constructor(private readonly library: Library) {}

    play(item: Playable): void {
        this.nowPlaying = item;
        item.play();
    }

    playFirstItem(playlistNamed: string): void {
        const item = this.library.playlist(playlistNamed)?.items[0];
        if (item) {
            this.play(item);
        }
    }
}
