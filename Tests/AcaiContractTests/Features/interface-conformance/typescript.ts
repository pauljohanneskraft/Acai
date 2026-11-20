export interface Playable {
    play(): boolean
}

export class Song implements Playable {}
