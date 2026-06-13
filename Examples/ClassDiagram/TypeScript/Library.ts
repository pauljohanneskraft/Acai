import { Playlist } from "./Playlist";

/** The user's whole collection: every playlist in one place. */
export class Library {
    constructor(readonly playlists: Playlist[] = []) {}

    addPlaylist(playlist: Playlist): void {
        this.playlists.push(playlist);
    }

    playlist(named: string): Playlist | undefined {
        return this.playlists.find((p) => p.name === named);
    }
}
