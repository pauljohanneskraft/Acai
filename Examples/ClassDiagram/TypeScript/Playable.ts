/** Anything the player knows how to play. */
export interface Playable {
    readonly title: string;
    readonly duration: number;

    play(): void;
}

/** A coarse classification for a piece of media. */
export enum Genre {
    Pop,
    Rock,
    Jazz,
    Classical,
    Electronic,
    SpokenWord,
}
