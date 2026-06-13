import { MediaItem } from "./MediaItem";

/** An ordered collection of media items the user has curated. */
export class Playlist {
    constructor(
        readonly name: string,
        readonly items: MediaItem[] = [],
    ) {}

    get totalDuration(): number {
        return this.items.reduce((sum, item) => sum + item.duration, 0);
    }

    add(item: MediaItem): void {
        this.items.push(item);
    }
}
