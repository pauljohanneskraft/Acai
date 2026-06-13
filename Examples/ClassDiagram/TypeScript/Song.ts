import { MediaItem } from "./MediaItem";
import { Genre } from "./Playable";

/** A single track by an artist. */
export class Song extends MediaItem {
    constructor(
        title: string,
        duration: number,
        genre: Genre,
        readonly artist: string,
        readonly album?: string,
    ) {
        super(title, duration, genre);
    }

    override play(): void {
        console.log(`♪ ${this.artist} — ${this.title}`);
    }
}
