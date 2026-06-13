import { MediaItem } from "./MediaItem";
import { Genre } from "./Playable";

/** One episode of a podcast. */
export class Podcast extends MediaItem {
    constructor(
        title: string,
        duration: number,
        readonly host: string,
        readonly episodeNumber: number,
    ) {
        super(title, duration, Genre.SpokenWord);
    }

    override play(): void {
        console.log(`🎙 Episode ${this.episodeNumber}: ${this.title}`);
    }
}
