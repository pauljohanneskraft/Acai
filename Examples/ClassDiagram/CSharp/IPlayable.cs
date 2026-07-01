namespace MediaLibrary;

public interface IPlayable {
    string Title { get; }
    double Duration { get; }
    void Play();
}
