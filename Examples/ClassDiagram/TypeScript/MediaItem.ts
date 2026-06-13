import { Playable, Genre } from "./Playable";

/** Shared base for every item in the library. */
export class MediaItem implements Playable {
    constructor(
        readonly title: string,
        readonly duration: number,
        readonly genre: Genre,
    ) {}

    play(): void {
        console.log(`Playing ${this.title}…`);
    }
}
